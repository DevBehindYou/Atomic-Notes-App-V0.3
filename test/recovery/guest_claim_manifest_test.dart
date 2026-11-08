import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/recovery/guest_claim_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

final _time = DateTime.utc(2026, 11, 8, 12);
String _id(int i) => '0000000$i-0000-4000-8000-00000000000$i';
Note _note(int i, String title, {bool deleted = false}) => Note(
    id: _id(i),
    title: title,
    body: 'Body $i',
    deleted: deleted,
    createdAt: _time,
    updatedAt: _time);

class _Crash implements Exception {
  const _Crash();
}

/// Counts persistence boundaries; [failAt] crashes at the n-th one.
class _Boundaries {
  int calls = 0;
  int? failAt;
  void hit() {
    calls++;
    if (failAt != null && calls == failAt) throw const _Crash();
  }
}

class _Guest implements ClaimSource {
  _Guest(List<Note> notes) : notes = {for (final n in notes) n.id: n};
  final Map<String, Note> notes;

  /// Runs on every read, to edit the guest store while a claim runs.
  void Function(int read)? onRead;
  int reads = 0;

  @override
  Future<List<Note>> current() async {
    onRead?.call(++reads);
    return [for (final n in notes.values) n.copy()];
  }
}

class _Library implements ClaimDestination {
  _Library(this.b, {this.capacity});
  final _Boundaries b;
  final notes = <String, Map<String, dynamic>>{};
  int? capacity;
  int puts = 0;
  @override
  Future<Set<String>> existingIds() async => notes.keys.toSet();
  @override
  Future<int?> remainingCapacity() async => capacity == null
      ? null
      : capacity! - notes.values.where((n) => n['deleted'] != true).length;
  @override
  Future<Note?> get(String id) async =>
      notes[id] == null ? null : Note.fromMap(notes[id]!);
  @override
  Future<void> put(Note note) async {
    b.hit();
    puts++;
    notes[note.id] = note.toMap();
  }
}

class _Journal implements ClaimJournal {
  _Journal(this.b);
  final _Boundaries b;
  String? stored;
  @override
  Future<Map<String, Object?>?> read() async =>
      stored == null ? null : jsonDecode(stored!) as Map<String, Object?>;
  @override
  Future<void> write(Map<String, Object?> state) async {
    b.hit();
    stored = jsonEncode(state);
  }

  @override
  Future<void> clear() async {
    b.hit();
    stored = null;
  }
}

typedef _World = ({
  _Guest guest,
  _Library library,
  _Journal journal,
  _Boundaries b
});

_World _world(List<Note> notes, {int? capacity}) {
  final b = _Boundaries();
  return (
    guest: _Guest(notes),
    library: _Library(b, capacity: capacity),
    journal: _Journal(b),
    b: b
  );
}

GuestClaimCoordinator _coordinator(_World w) => GuestClaimCoordinator(
    source: w.guest, destination: w.library, journal: w.journal, enabled: true);

Future<ClaimResult> _claim(_World w) => _coordinator(w)
    .claim(claimId: 'claim-1', profileId: 'guest-profile', generation: 1);

List<Note> _three() =>
    [_note(1, 'One'), _note(2, 'Two'), _note(3, 'Old', deleted: true)];

void _expectLibraryMatchesGuest(_World w) {
  expect(w.library.notes.keys.toSet(), w.guest.notes.keys.toSet());
  for (final note in w.guest.notes.values) {
    expect(Note.fromMap(w.library.notes[note.id]!).contentSig, note.contentSig,
        reason: note.id);
  }
}

void main() {
  test('the feature is off by default and refuses to run', () async {
    expect(GuestClaimFeature.enabled, isFalse);
    final w = _world(_three());
    await expectLater(
        GuestClaimCoordinator(
                source: w.guest, destination: w.library, journal: w.journal)
            .claim(claimId: 'c', profileId: 'p', generation: 1),
        throwsA(isA<ClaimRefused>()
            .having((e) => e.code, 'code', 'claim_disabled')));
    expect(w.library.puts, 0);
  });

  test('copies every note with its id, including the recycle bin', () async {
    final w = _world(_three());
    final result = await _claim(w);
    expect(result.copied, [_id(1), _id(2), _id(3)]);
    expect(result.rounds, 1);
    _expectLibraryMatchesGuest(w);
    expect(Note.fromMap(w.library.notes[_id(3)]!).deleted, isTrue);
    expect(w.journal.stored, isNull);
    expect(w.guest.notes, hasLength(3), reason: 'guest notes are kept');
  });

  test('an occupied library is refused, never merged', () async {
    final w = _world(_three());
    w.library.notes['someone-else'] = _note(9, 'Account note').toMap();
    await expectLater(
        _claim(w),
        throwsA(isA<ClaimRefused>()
            .having((e) => e.code, 'code', 'claim_target_occupied')));
    expect(w.library.puts, 0);
    expect(w.journal.stored, isNull);
  });

  test('a library without room is refused before writing', () async {
    final w = _world(_three(), capacity: 1);
    await expectLater(
        _claim(w),
        throwsA(isA<ClaimRefused>()
            .having((e) => e.code, 'code', 'claim_capacity_exceeded')));
    expect(w.library.puts, 0);
    // Recycle-bin notes do not count against the limit.
    final fits = _world(_three(), capacity: 2);
    await _claim(fits);
    _expectLibraryMatchesGuest(fits);
  });

  test('a duplicate or repeated claim writes nothing twice', () async {
    final w = _world(_three());
    await _claim(w);
    final puts = w.library.puts;
    await _coordinator(w).resume().then((_) {}, onError: (_) {});
    expect(w.library.puts, puts);
    // Resuming a claim whose copies already landed skips them by content.
    w.journal.stored = jsonEncode({
      'phase': 'copying',
      'round': 1,
      'claimed': [_id(1), _id(2), _id(3)],
      'manifest': GuestClaimManifest.freeze(
              claimId: 'claim-1',
              profileId: 'guest-profile',
              generation: 1,
              notes: w.guest.notes.values.toList())
          .toJson(),
    });
    await _coordinator(w).resume();
    expect(w.library.puts, puts);
  });

  test('edits, additions and removals during the claim are not lost', () async {
    final w = _world(_three());
    w.guest.onRead = (read) {
      if (read == 3) {
        // After the snapshot was copied: edit one, add one, remove one.
        w.guest.notes[_id(1)] = _note(1, 'One, edited later');
        w.guest.notes[_id(4)] = _note(4, 'Added during claim');
        w.guest.notes.remove(_id(2));
      }
    };
    final result = await _claim(w);
    expect(result.rounds, 2);
    expect(result.copied, [_id(1), _id(3), _id(4)]);
    expect(result.removedDuringClaim, [_id(2)]);
    expect(Note.fromMap(w.library.notes[_id(1)]!).title, 'One, edited later');
    expect(Note.fromMap(w.library.notes[_id(4)]!).title, 'Added during claim');
    final removed = Note.fromMap(w.library.notes[_id(2)]!);
    expect([removed.title, removed.deleted], ['Two', true],
        reason: 'kept in the recycle bin, not dropped and not live');
  });

  test('a Guest who never stops editing stops the claim, which resumes',
      () async {
    final w = _world(_three());
    var n = 0;
    w.guest.onRead = (_) => w.guest.notes[_id(1)] = _note(1, 'Edit ${n++}');
    await expectLater(
        GuestClaimCoordinator(
                source: w.guest,
                destination: w.library,
                journal: w.journal,
                maxRounds: 3,
                enabled: true)
            .claim(claimId: 'c', profileId: 'p', generation: 1),
        throwsA(isA<ClaimRefused>()
            .having((e) => e.code, 'code', 'claim_unsettled')));
    expect(w.journal.stored, isNotNull, reason: 'progress is kept');
    w.guest.onRead = null;
    await _coordinator(w).resume();
    _expectLibraryMatchesGuest(w);
    expect(w.journal.stored, isNull);
  });

  test('a crash at any persistence boundary resumes without loss or repeats',
      () async {
    final probe = _world(_three());
    await _claim(probe);
    final boundaries = probe.b.calls;
    expect(boundaries, greaterThanOrEqualTo(5));
    for (var k = 1; k <= boundaries; k++) {
      final w = _world(_three())..b.failAt = k;
      await expectLater(_claim(w), throwsA(isA<_Crash>()),
          reason: 'boundary $k');
      w.b.failAt = null;
      // Restart: claim again, which resumes when a journal exists.
      await _claim(w);
      _expectLibraryMatchesGuest(w);
      expect(w.journal.stored, isNull, reason: 'boundary $k');
      expect(w.library.puts, lessThanOrEqualTo(3 + 1),
          reason: 'boundary $k: at most the crashed put is repeated');
    }
  });

  test('the manifest round-trips and refuses unknown versions', () {
    final manifest = GuestClaimManifest.freeze(
        claimId: 'c', profileId: 'p', generation: 2, notes: _three());
    final again = GuestClaimManifest.fromJson(
        jsonDecode(jsonEncode(manifest.toJson())) as Map<String, Object?>);
    expect(again.toJson(), manifest.toJson());
    expect([for (final e in again.entries) e.id], [_id(1), _id(2), _id(3)]);
    expect(() => GuestClaimManifest.fromJson({'v': 2}),
        throwsA(isA<FormatException>()));
  });
}
