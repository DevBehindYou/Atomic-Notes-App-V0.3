// A confirmed "delete for good" covers exactly the notes its confirmation
// showed, and only while they are as it showed them (Codex R33), and its
// words come from what the removal does now, never from the note's version
// number (R34). Part one drives the Recycle Bin page's BinRemover over the
// in-memory fake store; part two over the real repository on an isolated
// Hive box with a fake API. All notes are synthetic.

import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/endpage/recycle_bin_page.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'support/fake_notes_source.dart';

const String _changed = 'The Recycle Bin changed before this could finish. '
    'Nothing was deleted for good. Check it and try again.';

Note _tomb(String id, {bool dirty = false, int serverVersion = 4}) {
  final n = syncedNote(id, title: 'Note $id')
    ..deleted = true
    ..dirty = dirty
    ..serverVersion = serverVersion;
  n.updatedAt = DateTime.utc(2026, 11, 1);
  return n;
}

/// A fake store whose syncs and removals can be held open and are counted.
class _Store extends FakeNotesSource {
  _Store({super.notes});

  Completer<void>? removeGate;
  final List<List<String>> removals = [];

  @override
  Future<int> deleteForever(Iterable<String> ids) async {
    removals.add(ids.toList());
    if (removeGate != null) await removeGate!.future;
    return super.deleteForever(ids);
  }
}

/// A fake API: every push is accepted at the next version, pulls are empty.
class _Api implements ApiClient {
  @override
  int sessionRevision = 0;
  int pushCalls = 0;
  int sequence = 0;
  Future<void> Function()? beforePush;

  @override
  String? get currentUserId => 'synthetic-user';

  @override
  Future<PushReply> pushNotes(List<Map<String, dynamic>> rows,
      {required String requestId, bool instant = false}) async {
    pushCalls++;
    final hook = beforePush;
    beforePush = null;
    await hook?.call();
    return PushReply(
        requestId: requestId,
        instant: instant,
        results: [
          for (final row in rows)
            <String, dynamic>{
              'id': row['id'],
              'ok': true,
              'version': (row['base_version'] as int) + 1,
              'seq': ++sequence,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
        ],
        receipt: null);
  }

  @override
  Future<Map<String, dynamic>> pullNotes(
          {int? after, bool encOnly = false}) async =>
      {
        'rows': <Map<String, dynamic>>[],
        'nextCursor': sequence,
        'hasMore': false,
        'cursor': DateTime.now().toUtc().toIso8601String(),
      };

  @override
  Future<void> wipeRemoteNotes() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A vault that stays locked; no note here is protected.
class _Vault implements Vault {
  @override
  bool get isUnlocked => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('over the fake store', () {
    test('a tombstone added after confirming is not removed', () async {
      final s = _Store(notes: [_tomb('a'), _tomb('b')]);
      final remover = BinRemover(s);

      final removal = remover.confirm(s.binNotes, wholeBin: true);
      s.changeBehindTheScenes(() => s.all.add(_tomb('late')));
      final message = await remover.remove(removal);

      expect(s.removals.single.toSet(), {'a', 'b'});
      expect(s.byId('a'), isNull);
      expect(s.byId('b'), isNull);
      expect(s.byId('late')!.deleted, isTrue);
      expect(
          message.text,
          '2 notes deleted for good. Notes deleted after you confirmed are '
          'still in the Recycle Bin.');
    });

    test(
        'a tombstone that must sync, added after confirming, is not synced '
        'or removed', () async {
      final s = _Store(notes: [_tomb('a')]);
      final remover = BinRemover(s);

      final removal = remover.confirm(s.binNotes, wholeBin: true);
      s.changeBehindTheScenes(() => s.all.add(_tomb('late', dirty: true)));
      await remover.remove(removal);

      expect(s.syncCalls, 0);
      expect(s.byId('a'), isNull);
      expect(s.byId('late'), isNotNull);
    });

    test('a confirmed note that now must sync stops the removal', () async {
      final s = _Store(notes: [_tomb('a'), _tomb('b')]);
      final remover = BinRemover(s);

      final removal = remover.confirm(s.binNotes, wholeBin: true);
      s.changeBehindTheScenes(() => s.byId('b')!.dirty = true);
      final message = await remover.remove(removal);

      expect(message.text, _changed);
      expect(s.removals, isEmpty);
      expect(s.syncCalls, 0);
      expect(s.binNotes, hasLength(2));
    });

    test('a confirmed note that was restored stops the removal', () async {
      final s = _Store(notes: [_tomb('a'), _tomb('b')]);
      final remover = BinRemover(s);

      final removal = remover.confirm(s.binNotes, wholeBin: true);
      await s.restoreNote('a');
      final message = await remover.remove(removal);

      expect(message.text, _changed);
      expect(s.removals, isEmpty);
      expect(s.byId('a')!.deleted, isFalse);
      expect(s.byId('b')!.deleted, isTrue);
    });

    test('a confirmed note that disappeared stops the removal', () async {
      final s = _Store(notes: [_tomb('a'), _tomb('b')]);
      final remover = BinRemover(s);

      final removal = remover.confirm(s.binNotes, wholeBin: true);
      s.changeBehindTheScenes(() => s.all.removeWhere((n) => n.id == 'a'));
      final message = await remover.remove(removal);

      expect(message.text, _changed);
      expect(s.removals, isEmpty);
      expect(s.byId('b'), isNotNull);
    });

    test('a confirmed note that was replaced stops the removal', () async {
      final s = _Store(notes: [_tomb('a')]);
      final remover = BinRemover(s);

      final removal = remover.confirm(s.binNotes);
      s.changeBehindTheScenes(() => s.byId('a')!.title = 'Other words');
      expect((await remover.remove(removal)).text, _changed);
      expect(s.byId('a'), isNotNull);
    });

    test('a note to sync first syncs once, then exactly the confirmed notes go',
        () async {
      final s = _Store(notes: [
        syncedNote('live'),
        _tomb('clean'),
        _tomb('wiped', serverVersion: 0),
        _tomb('pending', dirty: true),
      ]);
      final remover = BinRemover(s);

      final removal = remover.confirm(s.binNotes, wholeBin: true);
      expect(removal.count(BinRemovalStep.syncFirst), 1);
      expect(removal.count(BinRemovalStep.removeNow), 2);
      final message = await remover.remove(removal);

      expect(s.syncCalls, 1);
      expect(s.removals.single.toSet(), {'clean', 'wiped', 'pending'});
      expect(s.binNotes, isEmpty);
      expect(s.byId('live'), isNotNull);
      expect(message.text, 'Recycle Bin emptied');
    });

    test('a failed sync deletes nothing, not even the notes that need none',
        () async {
      final s = _Store(notes: [_tomb('clean'), _tomb('pending', dirty: true)])
        ..syncResult = false;
      final remover = BinRemover(s);

      final message =
          await remover.remove(remover.confirm(s.binNotes, wholeBin: true));

      expect(s.syncCalls, 1);
      expect(s.removals, isEmpty);
      expect(s.binNotes, hasLength(2));
      expect(s.byId('pending')!.dirty, isTrue);
      expect(message.text,
          'Could not delete yet. Turn on Cloud Sync and sync first.');
    });

    test('a tombstone added during the sync is not removed', () async {
      final s = _Store(notes: [_tomb('pending', dirty: true)])
        ..syncGate = Completer<void>();
      final remover = BinRemover(s);

      final running =
          remover.remove(remover.confirm(s.binNotes, wholeBin: true));
      await Future<void>.delayed(Duration.zero);
      s.changeBehindTheScenes(() => s.all.add(_tomb('late')));
      s.syncGate!.complete();
      await running;

      expect(s.byId('pending'), isNull);
      expect(s.byId('late'), isNotNull);
      expect(s.removals.single, ['pending']);
    });

    test('a confirmed note restored during the sync is kept', () async {
      final s = _Store(notes: [_tomb('pending', dirty: true)])
        ..syncGate = Completer<void>();
      final remover = BinRemover(s);

      final running = remover.remove(remover.confirm(s.binNotes));
      await Future<void>.delayed(Duration.zero);
      await s.restoreNote('pending');
      s.syncGate!.complete();
      final message = await running;

      expect(message.text, _changed);
      expect(s.removals, isEmpty);
      expect(s.byId('pending')!.deleted, isFalse);
    });

    test('a second removal while one runs is refused', () async {
      final s = _Store(notes: [_tomb('a'), _tomb('b')])
        ..removeGate = Completer<void>();
      final remover = BinRemover(s);

      final first = remover.remove(remover.confirm([s.byId('a')!]));
      final second =
          await remover.remove(remover.confirm(s.binNotes, wholeBin: true));
      expect(second.text,
          'Another removal is still running. Try again when it finishes.');
      s.removeGate!.complete();
      expect((await first).text, 'Deleted for good');

      expect(s.removals, [
        ['a']
      ]);
      expect(s.byId('b'), isNotNull);
      // Released afterwards.
      expect((await remover.remove(remover.confirm([s.byId('b')!]))).text,
          'Deleted for good');
    });

    test('a store that throws reports the notes it still holds', () async {
      final s = _ThrowingStore(notes: [_tomb('a'), _tomb('b')]);
      final remover = BinRemover(s);

      final message =
          await remover.remove(remover.confirm(s.binNotes, wholeBin: true));
      expect(message.text,
          "Couldn't finish removing these notes. They remain in the Recycle Bin.");
      expect((await remover.remove(remover.confirm([s.byId('a')!]))).text,
          "Couldn't finish removing this note. It remains in the Recycle Bin.");
    });

    test('a removal the store answers only in part says so', () async {
      final s = _PartialStore(notes: [_tomb('a'), _tomb('b'), _tomb('c')]);
      final remover = BinRemover(s);

      final message =
          await remover.remove(remover.confirm(s.binNotes, wholeBin: true));
      expect(message.text,
          'Deleted 1 of 3 notes for good. 2 are still in the Recycle Bin.');
    });

    test('the step comes from the sync flag only, never the version', () {
      expect(BinRemovalStep.of(_tomb('a', serverVersion: 0)),
          BinRemovalStep.removeNow);
      expect(BinRemovalStep.of(_tomb('b')), BinRemovalStep.removeNow);
      expect(BinRemovalStep.of(_tomb('c', dirty: true, serverVersion: 0)),
          BinRemovalStep.syncFirst);
      expect(
          BinRemovalStep.of(_tomb('d', dirty: true)), BinRemovalStep.syncFirst);
    });
  });

  group('over the repository (isolated Hive, fake API)', () {
    late Directory directory;
    late _Api api;
    late NotesRepository repository;
    late BinRemover remover;

    setUp(() async {
      directory =
          await Directory.systemTemp.createTemp('atomic-bin-scope-test-');
      Hive.init(directory.path);
      final box = await Hive.openBox('isolated-notes');
      SyncStatusHelper.syncBox = await Hive.openBox<bool>('isolated-sync');
      api = _Api();
      repository = NotesRepository.forTest(
          box: box,
          api: api,
          vault: _Vault(),
          checkConnectivity: () async => [ConnectivityResult.wifi]);
      await repository.start();
      remover = BinRemover(repository);
    });

    tearDown(() async {
      await repository.stop(waitForSync: true);
      repository.dispose();
      await Hive.close();
      await directory.delete(recursive: true);
    });

    Future<Note> synced(String body) async {
      final note = Note.create()..body = body;
      await repository.save(note);
      expect(await repository.syncNow(instant: true), isTrue);
      return repository.byId(note.id)!;
    }

    test('a note deleted after confirming stays in the bin', () async {
      final a = await synced('Synthetic A');
      final b = await synced('Synthetic B');
      await repository.deleteNotes([a.id]);
      expect(await repository.syncNow(instant: true), isTrue);
      expect(repository.byId(a.id)!.dirty, isFalse);

      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      await repository.deleteNotes([b.id]);
      expect(await repository.syncNow(instant: true), isTrue);
      final pushes = api.pushCalls;
      await remover.remove(removal);

      expect(repository.byId(a.id), isNull);
      expect(repository.byId(b.id)!.deleted, isTrue);
      expect(repository.binNotes.map((n) => n.id), [b.id]);
      expect(api.pushCalls, pushes, reason: 'Nothing confirmed had to sync.');
    });

    test(
        'a pending deletion syncs first; a note deleted during that sync stays',
        () async {
      final a = await synced('Synthetic A');
      final c = await synced('Synthetic C');
      await repository.deleteNotes([a.id]);
      expect(repository.byId(a.id)!.dirty, isTrue);

      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      api.beforePush = () => repository.deleteNotes([c.id]);
      await remover.remove(removal);

      expect(repository.byId(a.id), isNull);
      expect(repository.byId(c.id)!.deleted, isTrue);
    });

    test('a pending deletion restored during its sync is kept', () async {
      final a = await synced('Synthetic A');
      await repository.deleteNotes([a.id]);

      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      api.beforePush = () async {
        expect(await repository.restoreNote(a.id), isTrue);
      };
      final message = await remover.remove(removal);

      expect(message.text, _changed);
      expect(repository.byId(a.id), isNotNull);
      expect(repository.byId(a.id)!.deleted, isFalse);
    });

    test('a session change during the sync deletes nothing', () async {
      final a = await synced('Synthetic A');
      await repository.deleteNotes([a.id]);

      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      api.beforePush = () async => api.sessionRevision++;
      final message = await remover.remove(removal);

      expect(message.text, _changed);
      expect(repository.byId(a.id), isNotNull);
    });

    test('with Cloud Sync off a pending deletion is kept and nothing is sent',
        () async {
      final a = await synced('Synthetic A');
      final b = await synced('Synthetic B');
      await repository.deleteNotes([b.id]);
      expect(await repository.syncNow(instant: true), isTrue);
      await repository.deleteNotes([a.id]);
      await SyncStatusHelper.setSyncStatus(false);
      final pushes = api.pushCalls;

      final message = await remover
          .remove(remover.confirm(repository.binNotes, wholeBin: true));

      expect(api.pushCalls, pushes);
      expect(repository.byId(a.id)!.deleted, isTrue);
      expect(repository.byId(b.id)!.deleted, isTrue,
          reason: 'All or nothing: the clean note is kept too.');
      expect(message.text, contains('Could not delete yet'));
    });

    test(
        'after a cloud wipe a synced tombstone is not called never synced, '
        'and it is removed without a sync', () async {
      final a = await synced('Synthetic A');
      await repository.deleteNotes([a.id]);
      expect(await repository.syncNow(instant: true), isTrue);
      expect((await repository.wipeRemote()).ok, isTrue);
      final retained = repository.binNotes.single;
      expect(retained.serverVersion, 0);
      expect(retained.dirty, isFalse);

      final body = RecycleBinPage.deleteForeverBody(retained);
      expect(body, isNot(contains('never synced')));
      expect(body, isNot(contains('no cloud copy')));
      expect(body, isNot(contains('Drive')));
      final pushes = api.pushCalls;
      expect((await remover.remove(remover.confirm([retained]))).text,
          'Deleted for good');
      expect(repository.byId(a.id), isNull);
      expect(api.pushCalls, pushes);
    });
  });
}

/// A store whose removals fail.
class _ThrowingStore extends FakeNotesSource {
  _ThrowingStore({super.notes});

  @override
  Future<int> deleteForever(Iterable<String> ids) async =>
      throw StateError('Notes are changing session. Please retry.');
}

/// A store that removes only the first note it is given.
class _PartialStore extends FakeNotesSource {
  _PartialStore({super.notes});

  @override
  Future<int> deleteForever(Iterable<String> ids) =>
      super.deleteForever(ids.take(1));
}
