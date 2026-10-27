import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' show ClientException;

import 'notes_repository_lifecycle_test.dart' show TestApi, TestVault;

const _cooldownKey = '__standard_sync_cooldown__';
const _pendingKey = '__pending_sync_operation';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;
  late TestApi api;
  late TestVault vault;
  late NotesRepository repository;

  NotesRepository create({bool automaticSync = false}) =>
      NotesRepository.forTest(
          box: box,
          api: api,
          vault: vault,
          automaticSync: automaticSync,
          checkConnectivity: () async => [ConnectivityResult.wifi]);

  Future<void> restart() async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    await box.close();
    box = await Hive.openBox('cooldown-notes');
    repository = create();
    await repository.start();
  }

  Future<Note> changedNote() async {
    final note = Note.create()
      ..body = 'Synthetic image-bearing upload placeholder';
    await repository.save(note);
    return note;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-cooldown-test-');
    Hive.init(directory.path);
    box = await Hive.openBox('cooldown-notes');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('cooldown-switch');
    api = TestApi();
    vault = TestVault();
    repository = create();
    await repository.start();
  });
  tearDown(() async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
      'standard success survives cold restart without resending a waiting body',
      () async {
    await changedNote();
    expect(await repository.syncNow(), isTrue);
    final waiting = await changedNote();
    final preserved = Map.from(box.get(waiting.id) as Map);
    await restart();
    expect(repository.nextAutoSyncAt, isNotNull);
    expect(await repository.syncNow(), isFalse);
    expect(api.pushes.length, 1,
        reason: 'no second large rejected upload on restart');
    expect(api.pullCursors.length, 2, reason: 'free incoming sync still runs');
    expect(box.get(waiting.id), preserved);
    expect(repository.pendingCount, 1);
    expect(box.get(_pendingKey), isNull);
  });

  test('known cooldown also survives stop and start on the same repository',
      () async {
    await changedNote();
    expect(await repository.syncNow(), isTrue);
    await changedNote();
    await repository.stop(waitForSync: true);
    await repository.start();
    expect(repository.nextAutoSyncAt, isNotNull);
    expect(await repository.syncNow(), isFalse);
    expect(api.pushes.length, 1);
  });

  test(
      'definitive 429 cooldown survives restart while the dirty note stays intact',
      () async {
    final note = await changedNote();
    api.beforePush = () async =>
        throw ApiException('sync_cooldown', 429, retryAfterSeconds: 1800);
    expect(await repository.syncNow(), isFalse);
    expect(box.get(_pendingKey), isNull);
    final preserved = Map.from(box.get(note.id) as Map);
    api.beforePush = null;
    await restart();
    expect(repository.nextAutoSyncAt, isNotNull);
    expect(await repository.syncNow(), isFalse);
    expect(api.pushes.length, 1);
    expect(box.get(note.id), preserved);
  });

  test('instant upload bypasses restored standard cooldown', () async {
    await changedNote();
    expect(await repository.syncNow(), isTrue);
    await changedNote();
    await restart();
    expect(await repository.syncNow(instant: true), isTrue);
    expect(api.pushModes, [false, true]);
    expect(repository.pendingCount, 0);
    expect(repository.nextAutoSyncAt, isNotNull);
  });

  test('saved unanswered instant envelope replays during restored cooldown',
      () async {
    await changedNote();
    expect(await repository.syncNow(), isTrue);
    await changedNote();
    api.beforePush =
        () async => throw ClientException('synthetic disconnected response');
    expect(await repository.syncNow(instant: true), isFalse);
    final saved = Map.from(box.get(_pendingKey) as Map);
    api.beforePush = null;
    await restart();
    expect(repository.nextAutoSyncAt, isNotNull);
    expect(await repository.syncNow(), isTrue);
    expect(api.requestIds.last, saved['requestId']);
    expect(api.pushes.last, saved['rows']);
    expect(api.pushModes, [false, true, true]);
    expect(repository.pendingCount, 0);
  });

  test(
      'saved unanswered standard envelope also replays with the original request',
      () async {
    await changedNote();
    api.beforePush =
        () async => throw ClientException('synthetic disconnected response');
    expect(await repository.syncNow(), isFalse);
    final saved = Map.from(box.get(_pendingKey) as Map);
    await box.put(_cooldownKey, {
      'userId': api.user,
      'until': DateTime.now()
          .add(const Duration(minutes: 30))
          .toUtc()
          .toIso8601String()
    });
    api.beforePush = null;
    await restart();
    expect(repository.nextAutoSyncAt, isNotNull);
    expect(await repository.syncNow(), isTrue);
    expect(api.requestIds.last, saved['requestId']);
    expect(api.pushes.last, saved['rows']);
    expect(api.pushModes, [false, false]);
    expect(repository.pendingCount, 0);
  });

  for (final value in [
    null,
    'malformed',
    {
      'userId': 'another-owner',
      'until': DateTime.now()
          .add(const Duration(minutes: 30))
          .toUtc()
          .toIso8601String()
    },
    {'userId': 'user-a', 'until': 'not-a-date'},
    {'userId': 'user-a', 'until': 123},
    {
      'userId': 'user-a',
      'until': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String()
    },
    {
      'userId': 'user-a',
      'until':
          DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String()
    },
  ]) {
    test('invalid, foreign or expired cooldown is harmless: $value', () async {
      await box.put(_cooldownKey, value);
      await restart();
      expect(repository.nextAutoSyncAt, isNull);
      await changedNote();
      expect(await repository.syncNow(), isTrue);
      expect(api.pushes.length, 1);
    });
  }

  test('a new account does not inherit a previous owned cache cooldown',
      () async {
    await changedNote();
    expect(await repository.syncNow(), isTrue);
    await repository.stop(waitForSync: true);
    api.user = 'user-b';
    await repository.start();
    expect(repository.nextAutoSyncAt, isNull);
    await changedNote();
    expect(await repository.syncNow(), isTrue);
    expect(api.pushes.length, 2);
    expect(api.pushes.last.single['user_id'], 'user-b');
  });

  test(
      'a stale-session cooldown reply cannot retire its envelope or persist a gate',
      () async {
    await changedNote();
    api.beforePush = () async {
      api.sessionRevision++;
      throw ApiException('sync_cooldown', 429, retryAfterSeconds: 1800);
    };
    expect(await repository.syncNow(), isFalse);
    expect(box.get(_pendingKey), isA<Map>());
    expect(box.get(_cooldownKey), isNull);
    expect(repository.nextAutoSyncAt, isNull);
  });

  test('non-429 cooldown-looking error is not a definitive admission refusal',
      () async {
    await changedNote();
    api.beforePush = () async =>
        throw ApiException('sync_cooldown', 500, retryAfterSeconds: 1800);
    expect(await repository.syncNow(), isFalse);
    expect(box.get(_pendingKey), isA<Map>());
    expect(box.get(_cooldownKey), isNull);
    expect(repository.nextAutoSyncAt, isNull);
  });

  test('an old-session success cannot cache a cooldown for a new session',
      () async {
    await changedNote();
    api.beforePush = () async {
      api.sessionRevision++;
    };
    await repository.syncNow();
    expect(box.get(_cooldownKey), isNull);
    expect(repository.nextAutoSyncAt, isNull);
  });

  test(
      'restored cooldown retries automatically after expiry without an hourly wait',
      () async {
    await changedNote();
    await repository.stop(waitForSync: true);
    repository.dispose();
    await box.put(_cooldownKey, {
      'userId': api.user,
      'until': DateTime.now()
          .add(const Duration(seconds: 1))
          .toUtc()
          .toIso8601String()
    });
    final uploaded = Completer<void>();
    api.beforePush = () async {
      if (!uploaded.isCompleted) uploaded.complete();
    };
    repository = create(automaticSync: true);
    await repository.start();
    expect(repository.nextAutoSyncAt, isNotNull);
    expect(api.pushes, isEmpty);
    await uploaded.future.timeout(const Duration(seconds: 9));
    while (repository.isSyncing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(api.pushes.length, 1);
    expect(api.pushModes, [false]);
    expect(repository.pendingCount, 0);
  });

  for (final transition in ['lock', 'unlock']) {
    test('vault $transition preserves the restored deadline retry', () async {
      await changedNote();
      await repository.stop(waitForSync: true);
      repository.dispose();
      await box.put(_cooldownKey, {
        'userId': api.user,
        'until': DateTime.now()
            .add(const Duration(seconds: 1))
            .toUtc()
            .toIso8601String()
      });
      final uploaded = Completer<void>();
      api.beforePush = () async {
        if (!uploaded.isCompleted) uploaded.complete();
      };
      repository = create(automaticSync: true);
      await repository.start();
      while (repository.isSyncing) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (transition == 'lock') {
        await repository.lockVault();
      } else {
        vault.unlocked = true;
        await repository.reloadAfterUnlock();
      }
      expect(repository.nextAutoSyncAt, isNotNull);
      expect(api.pushes, isEmpty);
      await uploaded.future.timeout(const Duration(seconds: 9));
      while (repository.isSyncing) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(api.pushes.length, 1);
      expect(repository.pendingCount, 0);
    });
  }

  test('a restored retry timer retires when the session changes', () async {
    await changedNote();
    await repository.stop(waitForSync: true);
    repository.dispose();
    await box.put(_cooldownKey, {
      'userId': api.user,
      'until': DateTime.now()
          .add(const Duration(milliseconds: 200))
          .toUtc()
          .toIso8601String()
    });
    repository = create(automaticSync: true);
    await repository.start();
    while (repository.isSyncing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    api.sessionRevision++;
    await Future<void>.delayed(const Duration(milliseconds: 5500));
    expect(api.pushes, isEmpty);
    expect(repository.pendingCount, 1);
  });
}
