// The state behind the Recycle Bin, Cloud Notes and Danger Zone screens. The store is a fake in
// memory, so these need neither Hive nor the network.

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/state/cloud_notes/cloud_notes_cubit.dart';
import 'package:atomic_notes/state/danger_zone/danger_zone_cubit.dart';
import 'package:atomic_notes/state/recycle_bin/recycle_bin_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

Note _deleted(String id, String title, DateTime deletedAt) {
  final n = syncedNote(id, title: title)..deleted = true;
  n.updatedAt = deletedAt;
  return n;
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('Recycle Bin', () {
    FakeNotesSource source() => FakeNotesSource(limit: 3, notes: [
          syncedNote('live', title: 'Live'),
          _deleted('old', 'Old', DateTime.utc(2026, 9, 1)),
          _deleted('new', 'New', DateTime.utc(2026, 9, 2)),
        ]);

    test('lists the deleted notes, the latest deletion first', () {
      final cubit = RecycleBinCubit(source: source());
      addTearDown(cubit.close);
      expect(cubit.state.notes.map((n) => n.id), ['new', 'old']);
    });

    test('follows the store', () async {
      final s = source();
      final cubit = RecycleBinCubit(source: s);
      addTearDown(cubit.close);

      await s.deleteForever(['old']);
      await _settle();

      expect(cubit.state.notes.map((n) => n.id), ['new']);
    });

    test('a store that changes nothing on view emits nothing', () async {
      final s = source();
      final cubit = RecycleBinCubit(source: s);
      addTearDown(cubit.close);
      final seen = <RecycleBinState>[];
      final sub = cubit.stream.listen(seen.add);
      addTearDown(sub.cancel);

      s.poke();
      s.poke();
      await _settle();

      expect(seen, isEmpty);
    });

    test('restoring puts the note back and says so', () async {
      final s = source();
      final cubit = RecycleBinCubit(source: s);
      addTearDown(cubit.close);

      final message = await cubit.restore(s.byId('new')!);
      await _settle();

      expect(message.text, 'Note restored');
      expect(message.millis, 2000);
      expect(cubit.state.notes.map((n) => n.id), ['old']);
    });

    test('at the limit a restore is refused, with the limit in the words', () async {
      final s = FakeNotesSource(limit: 2, notes: [
        syncedNote('a', title: 'A'),
        syncedNote('b', title: 'B'),
        _deleted('gone', 'Gone', DateTime.utc(2026, 9, 1)),
      ]);
      final cubit = RecycleBinCubit(source: s);
      addTearDown(cubit.close);

      final message = await cubit.restore(s.byId('gone')!);

      expect(message.text, 'Note limit reached (2). Delete a note to make room.');
      expect(message.millis, 3000);
      expect(s.byId('gone')!.deleted, isTrue);
    });

    test('deleting for good says so', () async {
      final s = source();
      final cubit = RecycleBinCubit(source: s);
      addTearDown(cubit.close);

      final message = await cubit.deleteForever(s.byId('old')!);

      expect(message.text, 'Deleted for good');
      expect(s.byId('old'), isNull);
    });

    test('a deletion the cloud has not seen yet is explained, with no timer when sync is off', () async {
      final s = source()..deleteForeverWorks = false;
      final cubit = RecycleBinCubit(source: s);
      addTearDown(cubit.close);

      final message = await cubit.deleteForever(s.byId('old')!);

      expect(message.text, 'Could not delete yet. Turn on Cloud Sync and sync first.');
      expect(s.byId('old'), isNotNull);
    });

    test('a deletion the cloud has not seen yet says when the next sync sends it', () async {
      final s = source()
        ..deleteForeverWorks = false
        ..nextAutoSyncAt = DateTime.now().add(const Duration(minutes: 10));
      final cubit = RecycleBinCubit(source: s);
      addTearDown(cubit.close);

      final message = await cubit.emptyBin();

      expect(message.text, contains('sends in 10 min'));
      expect(message.text, contains('Sync now in Cloud Notes'));
    });

    test('emptying the bin removes the deleted notes and keeps the live ones', () async {
      final s = source();
      final cubit = RecycleBinCubit(source: s);
      addTearDown(cubit.close);

      final message = await cubit.emptyBin();
      await _settle();

      expect(message.text, 'Recycle Bin emptied');
      expect(cubit.state.notes, isEmpty);
      expect(s.byId('live'), isNotNull);
    });
  });

  group('Cloud Notes', () {
    FakeNotesSource source() => FakeNotesSource(notes: [
          syncedNote('a', title: 'A'),
          syncedNote('b', title: 'B'),
          syncedNote('c', title: 'C')..touch(),
        ])
          ..cloudNotes = 3;

    test('starts from the store, before any check', () {
      final s = source()..lastSyncedAt = DateTime.utc(2026, 9, 21, 10);
      final cubit = CloudNotesCubit(source: s);
      addTearDown(cubit.close);

      expect(cubit.state.onDevice, 3);
      expect(cubit.state.waiting, 1);
      expect(cubit.state.synced, 2);
      expect(cubit.state.cloud, isNull);
      expect(cubit.state.checked, isFalse);
      expect(cubit.state.lastSyncedAt, DateTime.utc(2026, 9, 21, 10));
    });

    test('a check counts the cloud and remembers when', () async {
      final cubit = CloudNotesCubit(source: source());
      addTearDown(cubit.close);
      final checking = <bool>[];
      final sub = cubit.stream.map((s) => s.checking).listen(checking.add);
      addTearDown(sub.cancel);

      await cubit.check();
      await _settle();

      expect(cubit.state.cloud, 3);
      expect(cubit.state.checked, isTrue);
      expect(cubit.state.checkedAt, isNotNull);
      expect(checking, [true, false]);
    });

    test('an unreachable cloud is a finished check with no number', () async {
      final s = source()..cloudNotes = null;
      final cubit = CloudNotesCubit(source: s);
      addTearDown(cubit.close);

      await cubit.check();

      expect(cubit.state.checked, isTrue);
      expect(cubit.state.cloud, isNull);
    });

    test('a later check that fails clears the number from the earlier one', () async {
      final s = source();
      final cubit = CloudNotesCubit(source: s);
      addTearDown(cubit.close);
      await cubit.check();
      expect(cubit.state.cloud, 3);

      s.cloudNotes = null;
      await cubit.check();

      expect(cubit.state.cloud, isNull);
    });

    test('Sync now sends the edited notes instantly and says so', () async {
      final s = source();
      final cubit = CloudNotesCubit(source: s);
      addTearDown(cubit.close);

      final message = await cubit.sync(uploadAll: false);
      await _settle();

      expect(message?.text, 'Synced with the cloud');
      expect(message?.millis, 3000);
      expect(s.lastSyncInstant, isTrue);
      expect(s.markAllCalls, 0);
      expect(cubit.state.working, isFalse);
      expect(cubit.state.waiting, 0);
    });

    test('Upload all marks every note first', () async {
      final s = source();
      final cubit = CloudNotesCubit(source: s);
      addTearDown(cubit.close);

      final message = await cubit.sync(uploadAll: true);

      expect(message?.text, 'All notes uploaded to the cloud');
      expect(s.markAllCalls, 1);
      expect(s.syncCalls, 1);
    });

    test('a failed sync gives the reason, or the general words', () async {
      final s = source()
        ..syncResult = false
        ..lastError = 'Not enough Atomic Energy for this sync.';
      final cubit = CloudNotesCubit(source: s);
      addTearDown(cubit.close);

      expect((await cubit.sync(uploadAll: false))?.text,
          'Not enough Atomic Energy for this sync.');

      s.lastError = null;
      expect((await cubit.sync(uploadAll: false))?.text,
          'Sync failed. Check your connection.');
    });

    test('a second sync while one is running does nothing', () async {
      final s = source();
      final cubit = CloudNotesCubit(source: s);
      addTearDown(cubit.close);

      final first = cubit.sync(uploadAll: false);
      final second = await cubit.sync(uploadAll: false);
      await first;

      expect(second, isNull);
      expect(s.syncCalls, 1);
    });

    test('follows the store: waiting notes, the last sync, the automatic sync', () async {
      final s = source();
      final cubit = CloudNotesCubit(source: s);
      addTearDown(cubit.close);

      final soon = DateTime.now().add(const Duration(minutes: 5));
      s.changeBehindTheScenes(() {
        s.byId('a')!.touch();
        s.lastSyncedAt = DateTime.utc(2026, 9, 21, 12);
        s.nextAutoSyncAt = soon;
      });
      await _settle();

      expect(cubit.state.waiting, 2);
      expect(cubit.state.lastSyncedAt, DateTime.utc(2026, 9, 21, 12));
      expect(cubit.state.nextAutoSyncAt, soon);

      // A wipe forgets the last sync and the wait: both must be able to go back to nothing.
      s.changeBehindTheScenes(() {
        s.lastSyncedAt = null;
        s.nextAutoSyncAt = null;
      });
      await _settle();

      expect(cubit.state.lastSyncedAt, isNull);
      expect(cubit.state.nextAutoSyncAt, isNull);
    });

    test('a check made after the screen closed does not throw', () async {
      final s = source();
      final cubit = CloudNotesCubit(source: s);
      final pending = cubit.check();
      await cubit.close();
      await pending;
      expect(cubit.isClosed, isTrue);
    });
  });

  group('Danger Zone', () {
    FakeNotesSource source() => FakeNotesSource(notes: [
          syncedNote('a', title: 'A'),
          syncedNote('b', title: 'B')..touch(),
        ]);

    test('shows how many notes are on the device and how many exist only there', () {
      final cubit = DangerZoneCubit(source: source());
      addTearDown(cubit.close);
      expect(cubit.state.onDevice, 2);
      expect(cubit.state.unsynced, 1);
    });

    test('wiping the cloud reports what the store reports and leaves the device alone', () async {
      final s = source();
      final cubit = DangerZoneCubit(source: s);
      addTearDown(cubit.close);

      final outcome = await cubit.wipeCloud();

      expect(outcome.ok, isTrue);
      expect(s.count, 2);
    });

    test('a cloud wipe that fails says so', () async {
      final cubit = DangerZoneCubit(source: source()..wipeRemoteWorks = false);
      addTearDown(cubit.close);
      expect((await cubit.wipeCloud()).ok, isFalse);
    });

    test('wiping the device removes the notes and says how many, in the singular too', () async {
      final s = source();
      final cubit = DangerZoneCubit(source: s);
      addTearDown(cubit.close);

      final outcome = await cubit.wipeLocal();
      await _settle();

      expect(outcome.ok, isTrue);
      expect(outcome.message,
          'Removed 2 notes from this device. Cloud notes are untouched and download again on the next sync.');
      expect(cubit.state.onDevice, 0);

      final one = DangerZoneCubit(source: FakeNotesSource(notes: [syncedNote('x')]));
      addTearDown(one.close);
      expect((await one.wipeLocal()).message,
          'Removed 1 note from this device. Cloud notes are untouched and download again on the next sync.');
    });
  });
}
