import 'package:atomic_notes/database/note.dart';

/// Guest claim preparation (C18): moving a Guest's local notes into a
/// signed-in library, modelled and tested against ports only.
///
/// Nothing here is reachable from the app. A live claim, and any account or
/// library binding change, waits for B05 and the accepted identity contracts
/// (C28/C29); [GuestClaimFeature.enabled] stays false until then.
abstract final class GuestClaimFeature {
  static const enabled = false;
}

/// One guest note as it was when the claim started.
class ClaimEntry {
  const ClaimEntry(this.id, this.sig, this.deleted);
  final String id;

  /// [Note.contentSig] at snapshot time.
  final String sig;
  final bool deleted;

  Map<String, Object> toJson() => {'id': id, 'sig': sig, 'deleted': deleted};
  static ClaimEntry fromJson(Map<String, Object?> j) =>
      ClaimEntry(j['id'] as String, j['sig'] as String, j['deleted'] as bool);
}

/// The frozen snapshot a claim copies. Ids are kept exactly; content is
/// compared by signature, so edits made after the snapshot are detected.
class GuestClaimManifest {
  GuestClaimManifest({
    required this.claimId,
    required this.profileId,
    required this.generation,
    required List<ClaimEntry> entries,
  }) : entries = List.unmodifiable(entries);

  final String claimId;
  final String profileId;
  final int generation;
  final List<ClaimEntry> entries;

  /// Freezes [notes]. Deleted (recycle-bin) notes are carried too, so a
  /// claim never resurrects or drops them.
  factory GuestClaimManifest.freeze(
          {required String claimId,
          required String profileId,
          required int generation,
          required List<Note> notes}) =>
      GuestClaimManifest(
        claimId: claimId,
        profileId: profileId,
        generation: generation,
        entries: [
          for (final note in [...notes]..sort((a, b) => a.id.compareTo(b.id)))
            ClaimEntry(note.id, note.contentSig, note.deleted)
        ],
      );

  Map<String, Object> toJson() => {
        'v': 1,
        'claimId': claimId,
        'profileId': profileId,
        'generation': generation,
        'entries': [for (final e in entries) e.toJson()],
      };

  static GuestClaimManifest fromJson(Map<String, Object?> j) {
    if (j['v'] != 1) throw const FormatException('unsupported claim manifest');
    return GuestClaimManifest(
      claimId: j['claimId'] as String,
      profileId: j['profileId'] as String,
      generation: j['generation'] as int,
      entries: [
        for (final e in (j['entries'] as List).cast<Map<String, Object?>>())
          ClaimEntry.fromJson(e)
      ],
    );
  }
}

/// What a claim may write into. Read-only queries plus one idempotent put.
abstract class ClaimDestination {
  /// Ids already in the signed-in library.
  Future<Set<String>> existingIds();

  /// How many more notes the library may hold (its note limit), or null when
  /// unlimited.
  Future<int?> remainingCapacity();

  /// The note the library holds for [id], or null.
  Future<Note?> get(String id);

  /// Writes [note] with its id unchanged.
  Future<void> put(Note note);
}

/// The guest notes being claimed, read at each step (they may still change).
abstract class ClaimSource {
  Future<List<Note>> current();
}

/// Durable claim progress, so an interrupted claim resumes rather than
/// starting over or copying twice.
abstract class ClaimJournal {
  Future<Map<String, Object?>?> read();
  Future<void> write(Map<String, Object?> state);
  Future<void> clear();
}

class ClaimRefused implements Exception {
  const ClaimRefused(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'ClaimRefused($code): $message';
}

class ClaimResult {
  const ClaimResult(
      this.claimId, this.copied, this.removedDuringClaim, this.rounds);
  final String claimId;

  /// Every guest note id now in the library, ids unchanged.
  final List<String> copied;

  /// Copied notes the Guest removed before the claim finished. They are kept
  /// in the library's recycle bin, not dropped and not left live.
  final List<String> removedDuringClaim;

  /// Snapshot rounds needed to catch edits made during the claim.
  final int rounds;
}

/// Copies a Guest's notes into an empty library, preserving ids.
///
/// 1. **Preflight**, no writes: the library must be empty (a claim never
///    merges into an occupied library) and have room for every live note.
/// 2. **Copy**: the frozen snapshot is recorded in the journal, then each
///    note is put. A put is skipped when the library already holds that id
///    with the same content, so a retry or duplicate claim writes nothing
///    twice.
/// 3. **Catch up**: the guest notes are read again. Notes changed or added
///    after the snapshot form a new snapshot round, and a copied note the
///    Guest has since removed goes to the library's recycle bin. Rounds repeat
///    until a read matches the library. No edit made during the claim is lost.
///    Each round first writes the copies the Guest has binned or removed, so
///    room is freed only by written changes. Every note the round would make
///    live, new or restored from the recycle bin, must then fit, or the
///    claim stops with its journal kept.
/// 4. The journal is cleared last. The guest's own notes are never removed
///    here: releasing the Guest profile is a separate, later step.
class GuestClaimCoordinator {
  GuestClaimCoordinator(
      {required this.source,
      required this.destination,
      required this.journal,
      this.maxRounds = 5,
      this.enabled = GuestClaimFeature.enabled});

  final ClaimSource source;
  final ClaimDestination destination;
  final ClaimJournal journal;

  /// A claim that cannot settle after this many rounds stops, keeping its
  /// journal, rather than chasing a Guest who keeps editing.
  final int maxRounds;

  /// Off in every build until the gate is accepted; fixtures pass true.
  final bool enabled;

  Future<ClaimResult> claim(
      {required String claimId,
      required String profileId,
      required int generation}) async {
    if (!enabled) {
      throw const ClaimRefused(
          'claim_disabled', 'Guest claim is not available yet.');
    }
    if (await journal.read() != null) return resume();
    final notes = await source.current();
    await _preflight(notes);
    final manifest = GuestClaimManifest.freeze(
        claimId: claimId,
        profileId: profileId,
        generation: generation,
        notes: notes);
    final claimed = [for (final e in manifest.entries) e.id];
    await journal.write(_state(manifest, 1, claimed));
    return _run(manifest, 1, claimed.toSet());
  }

  /// Finishes a claim an interruption stopped. Already-copied notes are
  /// skipped by content, so nothing is written twice.
  Future<ClaimResult> resume() async {
    if (!enabled) {
      throw const ClaimRefused(
          'claim_disabled', 'Guest claim is not available yet.');
    }
    final state = await journal.read();
    if (state == null) {
      throw const ClaimRefused('claim_missing', 'No claim is in progress.');
    }
    final manifest = GuestClaimManifest.fromJson(
        (state['manifest'] as Map).cast<String, Object?>());
    return _run(manifest, state['round'] as int,
        (state['claimed'] as List).cast<String>().toSet());
  }

  Map<String, Object?> _state(
          GuestClaimManifest manifest, int round, Iterable<String> claimed) =>
      {
        'phase': 'copying',
        'round': round,
        'claimed': [...claimed]..sort(),
        'manifest': manifest.toJson(),
      };

  Future<void> _preflight(List<Note> notes) async {
    final existing = await destination.existingIds();
    if (existing.isNotEmpty) {
      throw const ClaimRefused('claim_target_occupied',
          'This account already has notes. Guest notes are never merged into it.');
    }
    final room = await destination.remainingCapacity();
    final live = notes.where((n) => !n.deleted).length;
    if (room != null && live > room) {
      throw ClaimRefused('claim_capacity_exceeded',
          'This account has room for $room notes; the guest has $live.');
    }
  }

  Future<ClaimResult> _run(
      GuestClaimManifest first, int round, Set<String> claimed) async {
    var current = first;
    var rounds = round;
    while (true) {
      final byId = {for (final n in await source.current()) n.id: n};
      // Copies the Guest has since binned or removed leave the live library
      // first. Only a written change frees room for the check below.
      for (final id in claimed) {
        final held = await destination.get(id);
        if (held == null || held.deleted) continue;
        final note = byId[id];
        if (note == null) {
          await destination.put(held.copy()
            ..deleted = true
            ..touch());
        } else if (note.deleted) {
          await destination.put(note.copy());
        }
      }
      // Every note this round makes live must fit: a new copy, or a copy in
      // the library's recycle bin that the Guest has restored.
      var adding = 0;
      for (final entry in current.entries) {
        final note = byId[entry.id];
        if (note == null || note.deleted) continue;
        final held = await destination.get(entry.id);
        if (held == null || held.deleted) adding++;
      }
      final room = await destination.remainingCapacity();
      if (room != null && adding > room) {
        throw ClaimRefused('claim_capacity_exceeded',
            'This account has room for $room more notes; $adding guest notes remain. The claim is kept and can be resumed.');
      }
      for (final entry in current.entries) {
        final note = byId[entry.id];
        if (note == null) continue; // Removed since; handled below.
        final held = await destination.get(entry.id);
        if (held != null && held.contentSig == note.contentSig) continue;
        await destination.put(note.copy());
      }

      final after = {for (final n in await source.current()) n.id: n};
      final changed = <Note>[];
      for (final note in after.values) {
        final held = await destination.get(note.id);
        if (held?.contentSig != note.contentSig) changed.add(note);
      }
      final removed = <String>[];
      for (final id in claimed.where((id) => !after.containsKey(id))) {
        final held = await destination.get(id);
        if (held == null) continue; // Never copied: nothing to keep.
        removed.add(id);
        if (!held.deleted) {
          await destination.put(held.copy()
            ..deleted = true
            ..touch());
        }
      }
      if (changed.isEmpty) {
        await journal.clear();
        return ClaimResult(
            first.claimId, [...after.keys]..sort(), removed..sort(), rounds);
      }
      if (rounds >= maxRounds) {
        throw ClaimRefused('claim_unsettled',
            '${changed.length} guest notes keep changing. The claim is kept and can be resumed.');
      }
      rounds++;
      current = GuestClaimManifest.freeze(
          claimId: first.claimId,
          profileId: first.profileId,
          generation: first.generation,
          notes: changed);
      claimed.addAll(current.entries.map((e) => e.id));
      await journal.write(_state(current, rounds, claimed));
    }
  }
}
