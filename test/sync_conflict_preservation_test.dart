import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'notes_repository_lifecycle_test.dart' show TestApi, TestVault;

const _pendingKey = '__pending_sync_operation';

class _FaultBox implements Box {
  _FaultBox(this.inner);
  final Box inner;
  String? failPut;
  bool failFlush = false;
  int flushes = 0;
  Future<void> Function(dynamic key)? beforePut;
  Future<void> Function()? beforeFlush;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      inner.get(key, defaultValue: defaultValue);
  @override
  bool containsKey(dynamic key) => inner.containsKey(key);
  @override
  Iterable<dynamic> get values => inner.values;
  @override
  bool get isEmpty => inner.isEmpty;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    await beforePut?.call(key);
    if (key == failPut) {
      failPut = null;
      throw StateError('Synthetic preservation write failure');
    }
    await inner.put(key, value);
  }

  @override
  Future<void> delete(dynamic key) => inner.delete(key);
  @override
  Future<int> clear() => inner.clear();
  @override
  Future<void> flush() async {
    await beforeFlush?.call();
    flushes++;
    if (failFlush) {
      failFlush = false;
      throw StateError('Synthetic preservation flush failure');
    }
    await inner.flush();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box raw;
  late _FaultBox box;
  late TestApi api;
  late TestVault vault;
  late NotesRepository repository;

  NotesRepository createRepository() => NotesRepository.forTest(
      box: box,
      api: api,
      vault: vault,
      checkConnectivity: () async => [ConnectivityResult.wifi]);

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('atomic-conflict-fixture-');
    Hive.init(directory.path);
    raw = await Hive.openBox('conflict-notes');
    box = _FaultBox(raw);
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('conflict-sync');
    api = TestApi();
    vault = TestVault();
    repository = createRepository();
    await repository.start();
  });
  tearDown(() async {
    vault.sealGate?.complete();
    await repository.stop(waitForSync: true);
    repository.dispose();
    await Hive.close();
    final resolved = await directory.resolveSymbolicLinks();
    final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
    expect(Directory(resolved).parent.path, tempRoot);
    expect(Directory(resolved).uri.pathSegments.where((s) => s.isNotEmpty).last,
        startsWith('atomic-conflict-fixture-'));
    await Directory(resolved).delete(recursive: true);
  });

  Future<Note> seed() async {
    final note = Note(
        id: newId(),
        title: 'Shared',
        body: 'Captured source',
        kind: NoteKind.todo,
        items: [TodoItem(text: 'Captured task', done: true)],
        pinned: true,
        important: true,
        serverVersion: 3);
    await repository.save(note);
    api.pushResults = [
      {'id': note.id, 'ok': false, 'error': 'note_conflict', 'version': 4}
    ];
    final remote = note.copy()..body = 'Remote winner';
    api.pullRows = [
      {
        ...remote.toRemote('user-a'),
        'version': 4,
        'updated_at': '2026-10-25T00:00:00.000Z'
      }
    ];
    return note;
  }

  String copyId(String id) =>
      ((box.get(_pendingKey) as Map)['conflictIds'] as Map)[id] as String;
  Future<void> reopen() async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    await raw.close();
    raw = await Hive.openBox('conflict-notes');
    box = _FaultBox(raw);
    repository = createRepository();
    await repository.start();
  }

  for (final tombstone in [false, true]) {
    test(
        'replay preserves an existing ${tombstone ? 'deleted' : 'edited'} copy',
        () async {
      final note = await seed();
      api.beforePush =
          () async => throw TimeoutException('Synthetic lost reply');
      expect(await repository.syncNow(instant: true), isFalse);
      final id = copyId(note.id);
      final existing = Note(
          id: id,
          title: 'User preserved copy',
          body: 'User-owned later work',
          deleted: tombstone,
          serverVersion: 2);
      await repository.save(existing);
      final before = jsonEncode(existing.toMap());
      final frozenRows = jsonEncode((box.get(_pendingKey) as Map)['rows']);
      final requestId = (box.get(_pendingKey) as Map)['requestId'];
      String? mapped;
      api.beforePush = () async {
        mapped = copyId(note.id);
      };
      expect(await repository.syncNow(instant: true), isFalse);
      expect(jsonEncode(repository.byId(id)!.toMap()), before);
      expect(jsonEncode(Note.fromMap(box.get(id) as Map).toMap()), before);
      final preserved = repository
          .visible()
          .singleWhere((n) => n.id != note.id && n.id != id);
      expect(preserved.body, 'Captured source');
      expect(preserved.pinned, isTrue);
      expect(preserved.items.single.text, 'Captured task');
      expect(api.requestIds.last, requestId);
      expect(jsonEncode(api.pushes.last), frozenRows);
      expect(mapped, id);
    });
  }

  for (final stage in ['encryption', 'put', 'flush']) {
    for (final mutation in ['edit', 'delete', 'restore']) {
      test('source $mutation during copy $stage remains pending', () async {
        vault.unlocked = stage == 'encryption';
        final note = await seed();
        final entered = Completer<void>(), release = Completer<void>();
        api.beforePush = () async {
          if (stage == 'encryption') {
            vault.sealEntered = entered;
            vault.sealGate = release;
          } else if (stage == 'put') {
            final id = copyId(note.id);
            box.beforePut = (key) async {
              if (key == id) {
                entered.complete();
                await release.future;
              }
            };
          } else {
            box.beforeFlush = () async {
              entered.complete();
              await release.future;
            };
          }
        };
        final syncing = repository.syncNow(instant: true);
        await entered.future.timeout(const Duration(seconds: 5));
        Future<void>? save;
        try {
          if (mutation == 'edit') {
            save = repository.save(note
              ..body = 'Newer edit'
              ..items.single.text = 'Newer task');
          } else if (mutation == 'delete') {
            save = repository.deleteNotes([note.id]);
          } else {
            // A delete/restore with identical final content still changes the source timestamp.
            note.deleted = true;
            note.touch();
            note.deleted = false;
            save = repository.save(note);
          }
        } finally {
          vault.sealGate = null;
          box.beforePut = null;
          box.beforeFlush = null;
          release.complete();
        }
        await save;
        expect(await syncing, isFalse);
        expect(repository.byId(note.id)!.dirty, isTrue);
        expect(repository.byId(note.id)!.deleted, mutation == 'delete');
        expect(repository.byId(note.id)!.body,
            mutation == 'edit' ? 'Newer edit' : 'Captured source');
        final preserved =
            repository.visible().singleWhere((n) => n.id != note.id);
        expect(preserved.body, 'Captured source');
        expect(preserved.items.single.text, 'Captured task');
        await reopen();
        expect(repository.byId(note.id)!.dirty, isTrue);
        expect(repository.byId(note.id)!.deleted, mutation == 'delete');
      });
    }
  }

  for (final deleted in [false, true]) {
    test(
        'a copy ${deleted ? 'deleted' : 'edited'} during preservation cannot release its source',
        () async {
      vault.unlocked = true;
      final note = await seed();
      final entered = Completer<void>(), release = Completer<void>();
      String? id;
      api.beforePush = () async {
        id = copyId(note.id);
        vault.sealEntered = entered;
        vault.sealGate = release;
      };
      final syncing = repository.syncNow(instant: true);
      await entered.future.timeout(const Duration(seconds: 5));
      Future<void>? mutation;
      try {
        mutation = deleted
            ? repository.deleteNotes([id!])
            : repository.save(repository.byId(id!)!..body = 'New copy edit');
      } finally {
        vault.sealGate = null;
        release.complete();
      }
      await mutation;
      expect(await syncing, isFalse);
      expect(repository.byId(note.id)!.body, 'Captured source');
      expect(repository.byId(note.id)!.dirty, isTrue);
      expect(repository.byId(id!)!.deleted, deleted);
      if (!deleted) expect(repository.byId(id!)!.body, 'New copy edit');
      await reopen();
      expect(repository.byId(note.id)!.dirty, isTrue);
    });
  }

  for (final boundary in ['session', 'lifecycle', 'request', 'lock', 'wipe']) {
    test('$boundary change while preserving cannot clear the source', () async {
      vault.unlocked = true;
      final note = await seed();
      final entered = Completer<void>(), release = Completer<void>();
      api.beforePush = () async {
        vault.sealEntered = entered;
        vault.sealGate = release;
      };
      final syncing = repository.syncWithReport(instant: true);
      await entered.future.timeout(const Duration(seconds: 5));
      Future<void>? locking;
      Future<dynamic>? wiping;
      try {
        switch (boundary) {
          case 'session':
            api.sessionRevision++;
          case 'lifecycle':
            await repository.stop();
          case 'request':
            final pending =
                Map<String, dynamic>.from(box.get(_pendingKey) as Map);
            pending['requestId'] = 'synthetic-replacement-request';
            await box.put(_pendingKey, pending);
          case 'lock':
            locking = repository.lockVault();
          case 'wipe':
            wiping = repository.wipeRemote();
        }
      } finally {
        vault.sealGate = null;
        release.complete();
      }
      final report = await syncing;
      await locking;
      await wiping;
      expect(report.completed, isFalse);
      expect((box.get(note.id) as Map)['dirty'], isTrue);
      expect(api.pullCursors, isEmpty);
      if (boundary == 'request') {
        expect((box.get(_pendingKey) as Map)['requestId'],
            'synthetic-replacement-request');
      } else if (boundary != 'wipe') {
        expect(box.get(_pendingKey), isA<Map>());
      }
    });
  }

  test('a deleted captured source stays deleted without a live copy', () async {
    final note = await seed();
    await repository.deleteNotes([note.id]);
    expect(await repository.syncNow(instant: true), isFalse);
    expect(repository.visible(), isEmpty);
    expect(repository.byId(note.id)!.deleted, isTrue);
    expect(repository.byId(note.id)!.dirty, isTrue);
    expect(box.get(_pendingKey), isNull);
    expect(repository.lastError,
        'A deleted note changed on another device. Its deletion remains pending and needs review in the Recycle Bin. Other notes can continue syncing.');
    expect(repository.byId(note.id)!.serverVersion, 3);
  });

  test(
      'a completed deletion conflict does not starve unrelated work across reopen',
      () async {
    final note = await seed();
    await repository.deleteNotes([note.id]);
    final unrelated = Note(id: newId(), title: 'Same batch work');
    await repository.save(unrelated);
    api.pushReceipt = const PushReceipt(charged: 10, refunded: 0);
    api.beforePush = () async {
      api.pushResults = api.pushes.last
          .map((row) => row['id'] == note.id
              ? <String, dynamic>{
                  'id': note.id,
                  'ok': false,
                  'error': 'note_conflict',
                  'version': 4
                }
              : <String, dynamic>{
                  'id': row['id'],
                  'ok': true,
                  'version': (row['base_version'] as int) + 1,
                  'seq': ++api.sequence,
                  'updated_at': '2026-10-25T00:00:00.000Z'
                })
          .toList();
    };
    final first = await repository.syncWithReport(instant: true);
    expect(first.completed, isFalse);
    expect(first.netCharge, 10);
    expect(repository.byId(unrelated.id)!.dirty, isFalse);
    expect(repository.byId(note.id)!.deleted, isTrue);
    expect(repository.byId(note.id)!.dirty, isTrue);
    expect(repository.byId(note.id)!.serverVersion, 3);
    expect(box.get(_pendingKey), isNull);
    final firstId = api.requestIds.single;
    await reopen();
    final later = Note(id: newId(), title: 'Later work');
    await repository.save(later);
    final remote = Note(id: newId(), title: 'Other device new work');
    api.pullRows.add({
      ...remote.toRemote('user-a'),
      'version': 1,
      'updated_at': '2026-10-25T00:00:00.000Z'
    });
    final second = await repository.syncWithReport(instant: true);
    expect(second.completed, isFalse);
    expect(second.netCharge, 10,
        reason: 'A fresh manual request keeps the existing charging contract');
    expect(api.requestIds.last, isNot(firstId));
    expect(api.pushes.last.map((row) => row['id']),
        containsAll([note.id, later.id]));
    expect(repository.byId(later.id)!.dirty, isFalse);
    expect(repository.byId(remote.id)!.title, 'Other device new work');
    expect(repository.byId(note.id)!.deleted, isTrue);
    expect(repository.byId(note.id)!.dirty, isTrue);
    expect(repository.byId(note.id)!.serverVersion, 3);
    expect(box.get(_pendingKey), isNull);
    expect(first.netCharge, 10);

    // The existing explicit Recycle Bin action restores normal conflict handling.
    expect(await repository.restoreNote(note.id), isTrue);
    expect(await repository.syncNow(instant: true), isFalse);
    expect(repository.byId(note.id)!.body, 'Remote winner');
    expect(repository.byId(note.id)!.serverVersion, 4);
    expect(repository.byId(note.id)!.deleted, isFalse);
    final preserved = repository
        .visible()
        .singleWhere((n) => n.title == 'Shared (conflict copy)');
    expect(preserved.body, 'Captured source');
    expect(preserved.dirty, isTrue);
    expect(api.requestIds.toSet(), hasLength(3));
  });

  for (final fault in ['put', 'flush']) {
    for (final restart in [false, true]) {
      test('$fault failure retries preservation (reopen=$restart)', () async {
        final note = await seed();
        String? id;
        api.beforePush = () async {
          id = copyId(note.id);
          if (fault == 'put') box.failPut = id;
          if (fault == 'flush') box.failFlush = true;
        };
        expect(await repository.syncNow(instant: true), isFalse);
        expect(repository.byId(note.id)!.dirty, isTrue);
        expect(box.get(_pendingKey), isA<Map>());
        final firstRequest = api.requestIds.single;
        final before = repository.byId(id!)?.updatedAt;
        if (restart) await reopen();
        api.beforePush = null;
        expect(await repository.syncNow(instant: true), isFalse);
        expect(api.requestIds.last, firstRequest);
        expect(repository.byId(id!)!.body, 'Captured source');
        expect(repository.byId(id!)!.pinned, isTrue);
        if (!restart) expect(repository.byId(id!)!.updatedAt, before);
        expect((box.get(id) as Map)['dirty'], isTrue);
        expect(repository.byId(note.id)!.body, 'Remote winner');
        expect(box.flushes, greaterThan(0));
      });
    }
  }
}
