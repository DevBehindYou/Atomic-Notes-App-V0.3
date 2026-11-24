import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_projection.dart';
import 'package:flutter/foundation.dart';

/// What the notes state needs from the place notes are kept.
///
/// [NotesRepository] is the real one (Hive on the device, the Server in the cloud). The state
/// layer only sees this interface, so it can be tested with a small fake and no storage.
/// It tells listeners when anything changed, including changes that do not touch a note
/// (a sync starting or ending), so a listener must compare before it rebuilds anything.
abstract interface class NotesSource implements Listenable {
  /// Live notes of the current owner (deleted ones excluded), pinned first,
  /// cut to [type] and, when given, to notes carrying exactly [tag], and
  /// ordered by creation time per [sort].
  ///
  /// A legacy [filter], when given, replaces [type] and [sort] with its old
  /// meaning (see [NoteFilterParts]).
  List<Note> visible({
    NoteFilter? filter,
    NoteTypeFilter type = NoteTypeFilter.all,
    NoteSort sort = NoteSort.newest,
    String? tag,
  });

  /// One note by id, deleted or not; null when the device has no such note.
  Note? byId(String id);

  /// How many live notes there are.
  int get count;

  /// The most live notes the account may hold.
  int get limit;

  /// How many notes wait to be sent to the cloud.
  int get pendingCount;

  /// A repository sync is running, whether requested by a timer or by the user.
  bool get isSyncing;

  /// The reason the last sync failed, in words for the user.
  String? get lastError;

  /// Notes that were deleted on a device and still wait in the Recycle Bin, newest deletion first.
  List<Note> get binNotes;

  /// When the last pull finished, or null when this device has not synced since it started.
  DateTime? get lastSyncedAt;

  /// When an automatic sync can send changes, or null when it is open now.
  DateTime? get nextAutoSyncAt;

  Future<void> save(Note note);

  /// Moves the notes to the Recycle Bin (soft delete).
  Future<void> deleteNotes(Iterable<String> ids);

  /// Pushes waiting changes, then pulls. True when the sync finished cleanly.
  Future<bool> syncNow({bool instant = false});

  /// Puts a deleted note back. False when it is not in the bin or the limit leaves no room.
  Future<bool> restoreNote(String id);

  /// Removes deleted notes from this device for good. Returns how many were removed.
  Future<int> deleteForever(Iterable<String> ids);

  /// How many live notes the cloud holds, or null when it cannot be reached. Changes nothing.
  Future<int?> cloudCount();

  /// Marks every live note as waiting, so the next sync writes all of them to the cloud.
  Future<int> markAllForUpload();

  /// Empties the cloud copy and leaves this device alone.
  Future<WipeOutcome> wipeRemote();

  /// Removes every note from this device only. Returns how many.
  Future<int> wipeLocalNotes();
}

/// Result of a wipe: whether it happened, and what to tell the user.
class WipeOutcome {
  final bool ok;
  final String message;
  const WipeOutcome(this.ok, this.message);
}

/// Who may store an editor's draft: the account, its session and the store's
/// lifecycle when the editor opened. Opaque; only its store can read it.
abstract interface class NoteEditorContext {}

/// What one acknowledged local save did.
sealed class NoteLocalSaveReceipt {
  const NoteLocalSaveReceipt();
}

/// This attempt's note, as submitted, was written to this device's store for
/// the editor's own account.
final class NoteLocalSaveStored extends NoteLocalSaveReceipt {
  const NoteLocalSaveStored();
}

/// Why a store deliberately did not keep an attempt.
enum NoteSaveRetirement {
  /// The account, session or store lifecycle is no longer the editor's. The
  /// draft must not be saved into whatever is current now.
  contextChanged,

  /// Another change to the same note replaced this attempt before it was
  /// written.
  replaced,

  /// The note was deleted before this attempt was written.
  deleted,
}

/// Not written, on purpose. Memory may already hold the attempt's note until
/// the store reloads or the replacing change is written.
final class NoteLocalSaveRetired extends NoteLocalSaveReceipt {
  const NoteLocalSaveRetired(this.reason);
  final NoteSaveRetirement reason;
}

/// The write was attempted and failed. Memory may already hold the change;
/// the device's store does not have it confirmed.
final class NoteLocalSaveFailed extends NoteLocalSaveReceipt {
  const NoteLocalSaveFailed(this.error);
  final Object error;
}

/// A store that can save an editor's draft and say truthfully what happened
/// to that exact attempt. Other callers keep using [NotesSource.save].
abstract interface class EditorNoteSaveSource {
  /// The context for an editor opened now, or null when nobody may write
  /// (signed out, stopped, locking, logging out, or another account's cache).
  NoteEditorContext? captureEditorContext();

  /// Saves [note] for [context] and reports what happened to this attempt.
  /// It never writes for a context that is no longer current, and never
  /// throws: a failure is a [NoteLocalSaveFailed].
  Future<NoteLocalSaveReceipt> saveForEditor(
      Note note, NoteEditorContext context);
}

/// Optional repository-owned derived data. Small test sources need not cache.
abstract interface class NoteProjectionSource {
  NoteProjection projectionFor(Note note, {bool evict = true});
}

NoteProjection projectNote(NotesSource source, Note note,
        {bool evict = true}) =>
    source is NoteProjectionSource
        ? (source as NoteProjectionSource).projectionFor(note, evict: evict)
        : NoteProjection.fromNote(note);

/// What one bin note was when a "delete for good" was confirmed, as its store
/// judged it: whether removing it must sync first, and the facts that say
/// which tombstone it was.
final class BinPurgeFact {
  const BinPurgeFact({
    required this.needsSync,
    required this.deleted,
    required this.contentSig,
    required this.serverVersion,
    required this.dirty,
    required this.updatedAt,
    this.generation,
  });

  /// The store must sync this note before it may forget it: it has a change
  /// waiting, and the cloud may hold (or be receiving) a copy of it.
  final bool needsSync;
  final bool deleted;
  final String contentSig;
  final int serverVersion;
  final bool dirty;
  final DateTime updatedAt;

  /// Which record of the note this was, compared by identity only. The store
  /// gives the record it holds: an acknowledgement of its own upload settles
  /// that record in place, while a note that came in from the cloud is a new
  /// record, whatever its content. Null when the store gives none.
  final Object? generation;
}

/// A confirmed "delete for good", frozen by the store when its confirmation
/// opened: exactly which notes, what each one needed, and whose account,
/// session and store lifecycle it was. A later freeze of the same notes is
/// compared with it by [allows] before anything is removed.
final class BinPurgeConsent {
  BinPurgeConsent(this._identity, Map<String, BinPurgeFact?> facts)
      : _facts = Map.unmodifiable(facts);

  final Object? _identity;

  /// Null for a note the store did not hold when this was frozen.
  final Map<String, BinPurgeFact?> _facts;

  /// The confirmed notes, in the order they were given.
  List<String> get ids => List.unmodifiable(_facts.keys);

  /// What the store said about [id] when this was frozen.
  BinPurgeFact? factOf(String id) => _facts[id];

  /// Whether any confirmed note must sync first.
  bool get needsSync => _facts.values.any((f) => f?.needsSync ?? false);

  /// Same store, account, session and lifecycle as [now].
  bool sameIdentity(BinPurgeConsent now) => now._identity == _identity;

  /// Whether [now], a later freeze of the same notes by the same store, still
  /// describes what this confirmation showed. Each note must still be the
  /// same deleted record with the same content, needing no more than was
  /// disclosed. The only change allowed is an acknowledgement of a note that
  /// had a change waiting: its sync flag and version settle, its content and
  /// record do not. A restored note, a newer or different tombstone (even one
  /// with the same content), a note gone, or another session all need a fresh
  /// confirmation. Facts alone cannot say which upload an acknowledgement
  /// answered, so the store also checks that (see [unchanged] and
  /// [acknowledged]).
  bool allows(BinPurgeConsent now) {
    if (!sameIdentity(now) || now._facts.length != _facts.length) return false;
    for (final MapEntry(key: id, value: was) in _facts.entries) {
      final cur = now._facts[id];
      if (was == null || cur == null || !was.deleted || !cur.deleted) {
        return false;
      }
      if (!identical(cur.generation, was.generation)) return false;
      if (cur.contentSig != was.contentSig) return false;
      if (cur.needsSync && !was.needsSync) return false;
      final same = cur.serverVersion == was.serverVersion &&
          cur.dirty == was.dirty &&
          cur.updatedAt == was.updatedAt;
      if (same) continue;
      // Only a waiting change can be acknowledged, and an acknowledgement
      // always moves the version forward.
      if (!was.dirty || cur.serverVersion <= was.serverVersion) return false;
    }
    return true;
  }

  /// Whether [now] is exactly what this confirmation showed: it [allows] it
  /// and no confirmed note carries an acknowledgement.
  bool unchanged(BinPurgeConsent now) => allows(now) && !acknowledged(now);

  /// Whether any confirmed note in [now] has settled since this was frozen:
  /// its version, sync flag or time differs.
  bool acknowledged(BinPurgeConsent now) => _facts.entries.any((e) {
        final cur = now._facts[e.key], was = e.value;
        return cur != null &&
            was != null &&
            (cur.serverVersion != was.serverVersion ||
                cur.dirty != was.dirty ||
                cur.updatedAt != was.updatedAt);
      });
}
