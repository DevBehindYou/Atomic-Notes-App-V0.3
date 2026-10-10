import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/api/logout_recovery.dart';
import 'package:atomic_notes/database/logout_plan.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'logout_orchestration_test.dart' show LogoutTestApi;
import 'notes_repository_lifecycle_test.dart' show TestVault;

class _RecoveryApi extends LogoutTestApi {
  String binding = 'a' * 64;
  int recoveries = 0;
  bool loseRecovery = false, missingReceipt = false;
  Future<void> Function()? beforeRecovery;
  @override
  Future<String> logoutSessionHash() async => binding;
  void reauthenticate() {
    binding = 'b' * 64;
    sessionRevision++;
    completion = null;
  }

  @override
  Future<LogoutRecoveryReceipts> commitLogoutRecovery(
    LogoutRecoveryQuery query,
  ) async {
    recoveries++;
    await beforeRecovery?.call();
    if (missingReceipt) throw ApiException('logout_recovery_unavailable', 409);
    final state =
        closedState ??
        (receipts.values.any(
              (receipt) => receipt.results.any((row) => row['ok'] != true),
            )
            ? 'aborted'
            : 'completed');
    closedState = state;
    if (loseRecovery) {
      loseRecovery = false;
      throw const SocketException('Public fixture loses recovery commit reply');
    }
    return LogoutRecoveryReceipts.parse({
      'attemptId': query.attemptId,
      'state': state,
      'batches': query.batches.map((batch) {
        final receipt = receipts[batch.requestId]!;
        return {
          'requestId': batch.requestId,
          'charged': receipt.receipt!.charged,
          'refunded': receipt.receipt!.refunded,
          'results': receipt.results,
        };
      }).toList(),
    }, query);
  }
}

/// Only owned test-box writes fail. Real Hive persists and reopens the rows.
class _FaultBox implements Box {
  _FaultBox(this.inner);
  final Box inner;
  bool failFlush = false;
  String? failPut;
  String? failDeleteBefore, failDeleteAfter;
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
    if (key == failPut) {
      failPut = null;
      throw StateError('Public fixture interrupted note write');
    }
    await inner.put(key, value);
  }

  @override
  Future<void> delete(dynamic key) async {
    if (key == failDeleteBefore) {
      failDeleteBefore = null;
      throw StateError('Public fixture interrupted metadata deletion');
    }
    await inner.delete(key);
    if (key == failDeleteAfter) {
      failDeleteAfter = null;
      throw StateError('Public fixture lost metadata deletion acknowledgement');
    }
  }

  @override
  Future<int> clear() => inner.clear();
  @override
  Future<void> flush() async {
    if (failFlush) {
      failFlush = false;
      throw StateError('Public fixture interrupted note flush');
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
  late _RecoveryApi api;
  late TestVault vault;
  late NotesRepository repository;
  var finished = 0;
  NotesRepository create() => NotesRepository.forTest(
    box: box,
    api: api,
    vault: vault,
    checkConnectivity: () async => [ConnectivityResult.wifi],
  );
  Future<void> logout() => repository.logoutSafely(
    finishLocal: (check) async {
      check();
      finished++;
    },
  );
  Future<Note> interrupted({bool completion = false}) async {
    final note = Note.create()
      ..title = 'Public old edit'
      ..body = 'Keep offline work';
    await repository.save(note);
    api.dropPushReply = !completion;
    api.dropCompletionReply = completion;
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    api.reauthenticate();
    return note;
  }

  Future<void> restart() async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    await raw.close();
    raw = await Hive.openBox('same-owner-recovery');
    box = _FaultBox(raw);
    repository = create();
    await repository.start();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-same-owner-');
    Hive.init(directory.path);
    raw = await Hive.openBox('same-owner-recovery');
    box = _FaultBox(raw);
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('same-owner-sync');
    await SyncStatusHelper.setSyncStatus(true);
    api = _RecoveryApi();
    vault = TestVault();
    finished = 0;
    repository = create();
    await repository.start();
  });
  tearDown(() async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final paid in [false, true]) {
    for (final completion in [false, true]) {
      test(
        'same owner recovers ${paid ? 'paid' : 'free'} ${completion ? 'completion' : 'push'} without upload',
        () async {
          api.emergency = !paid;
          await interrupted(completion: completion);
          await restart();
          expect(
            api.recoveries,
            0,
          ); // Startup never adopts a plan automatically.
          await logout();
          expect(api.recoveries, 1);
          expect(api.logoutRequests.length, 1);
          expect(api.admissions, 1);
          expect(api.receipts.values.single.receipt!.charged, paid ? 10 : 0);
          expect(finished, 1);
          expect(raw.isEmpty, isTrue);
        },
      );
    }
  }
  test(
    'newer edit is retained after recovery and only a new explicit attempt uploads it',
    () async {
      final note = await interrupted();
      await repository.save(
        repository.byId(note.id)!.copy()..body = 'Newer unsent work',
      );
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect(repository.byId(note.id)!.body, 'Newer unsent work');
      expect(repository.byId(note.id)!.dirty, isTrue);
      expect(repository.byId(note.id)!.serverVersion, 1);
      expect(raw.containsKey(LogoutPlanStore.key), isFalse);
      expect(api.logoutRequests.length, 1);
      expect(finished, 0);
      await logout();
      expect(api.admissions, 2);
      expect(api.logoutRequests.length, 2);
      expect(finished, 1);
    },
  );
  test(
    'foreign account is blocked before receipt delivery without erasing owner cache',
    () async {
      final note = await interrupted();
      final owner = raw.get('__cache_owner__');
      api.user = newId();
      api.sessionRevision++;
      await expectLater(logout(), throwsA(isA<ForeignPendingCacheError>()));
      expect(raw.get('__cache_owner__'), owner);
      expect((raw.get(note.id) as Map)['body'], note.body);
      expect(raw.containsKey(LogoutPlanStore.key), isTrue);
      expect(api.recoveries, 0);
      expect(repository.visible(), isEmpty);
    },
  );
  test(
    'locked protected rows remain byte-for-byte retained before recovery network',
    () async {
      vault.unlocked = true;
      final note = await interrupted();
      await repository.lockVault();
      final original = Map.from(raw.get(note.id) as Map);
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect(raw.get(note.id), original);
      expect(api.recoveries, 0);
      expect(finished, 0);
    },
  );
  test(
    'missing receipt refuses recovery and retains exact old plan and request',
    () async {
      final note = await interrupted();
      final plan = raw.get(LogoutPlanStore.key),
          pending = raw.get('__pending_sync_operation');
      api.missingReceipt = true;
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect(raw.get(LogoutPlanStore.key), plan);
      expect(raw.get('__pending_sync_operation'), pending);
      expect((raw.get(note.id) as Map)['dirty'], isTrue);
      expect(finished, 0);
    },
  );
  for (final fault in ['reply', 'put', 'flush']) {
    test(
      '$fault loss after Server settlement survives real Hive reopen without another debit or upload',
      () async {
        final note = await interrupted();
        if (fault == 'reply') api.loseRecovery = true;
        if (fault == 'put') box.failPut = note.id;
        if (fault == 'flush') box.failFlush = true;
        await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
        expect(raw.containsKey(LogoutPlanStore.key), isTrue);
        expect(raw.containsKey(note.id), isTrue);
        expect(finished, 0);
        await restart();
        await logout();
        expect(api.recoveries, 2);
        expect(api.logoutRequests.length, 1);
        expect(api.admissions, 1);
        expect(finished, 1);
      },
    );
  }
  test(
    'late same-owner replaced-session reply cannot apply or erase notes',
    () async {
      final note = await interrupted();
      api.beforeRecovery = () async {
        api.sessionRevision++;
      };
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect((raw.get(note.id) as Map)['dirty'], isTrue);
      expect(raw.containsKey(LogoutPlanStore.key), isTrue);
      expect(finished, 0);
    },
  );
  test('tampered frozen pending snapshot is blocked before commit', () async {
    final note = await interrupted();
    final pending = Map<String, dynamic>.from(
      raw.get('__pending_sync_operation') as Map,
    );
    pending['sigs'] = {note.id: 'changed-signature'};
    await raw.put('__pending_sync_operation', pending);
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    expect(api.recoveries, 0);
    expect(raw.containsKey(LogoutPlanStore.key), isTrue);
    expect(finished, 0);
  });
  test(
    'settled conflict uses deterministic copy and a reset pull, retaining both versions',
    () async {
      final note = Note.create()
        ..title = 'Public conflict'
        ..body = 'Local version';
      await repository.save(note);
      api.pushResults = [
        {'id': note.id, 'ok': false, 'error': 'note_conflict'},
      ];
      api.dropPushReply = true;
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      api.pullRows = [
        {
          ...note.toRemote(api.user!),
          'version': 2,
          'title': 'Remote version',
          'body': 'Other device work',
          'updated_at': '2026-10-10T00:00:00.000Z',
        },
      ];
      api.reauthenticate();
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect(repository.byId(note.id)!.body, 'Other device work');
      expect(
        repository.visible().singleWhere((row) => row.id != note.id).body,
        'Local version',
      );
      expect(api.closedState, 'aborted');
      expect(api.logoutRequests.length, 1);
      expect(raw.containsKey(LogoutPlanStore.key), isFalse);
      expect(finished, 0);
    },
  );
  test(
    'interrupted conflict recovery never overwrites an edited copy on replay',
    () async {
      final note = Note.create()
        ..title = 'Public conflict'
        ..body = 'Local version';
      await repository.save(note);
      api.pushResults = [
        {'id': note.id, 'ok': false, 'error': 'note_conflict'},
      ];
      api.dropPushReply = true;
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      api.reauthenticate();
      api.pullFailure = const SocketException(
        'Public fixture interrupted recovery pull',
      );
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      final copy = repository.visible().singleWhere((row) => row.id != note.id);
      await repository.save(copy.copy()..body = 'Edited preserved copy');
      await restart();
      api.pullFailure = null;
      api.pullRows = [
        {
          ...note.toRemote(api.user!),
          'version': 2,
          'title': 'Remote version',
          'body': 'Other device work',
          'updated_at': '2026-10-10T00:00:00.000Z',
        },
      ];
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect(repository.visible().length, 2);
      expect(repository.byId(copy.id)!.body, 'Edited preserved copy');
      expect(repository.byId(copy.id)!.dirty, isTrue);
      expect(api.recoveries, 2);
      expect(api.logoutRequests.length, 1);
      expect(finished, 0);
    },
  );
  for (final reopen in [false, true]) {
    test('conflict-copy put loss retries durably (reopen=$reopen)', () async {
      final note = Note.create()
        ..title = 'Conflict copy put fault'
        ..body = 'Only local edit';
      await repository.save(note);
      api.pushResults = [
        {'id': note.id, 'ok': false, 'error': 'note_conflict'},
      ];
      api.dropPushReply = true;
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      api.reauthenticate();
      final saved = raw.get(LogoutPlanStore.key) as Map;
      final copyId =
          ((saved['snapshots'] as Map)[note.id] as Map)['conflictId'] as String;
      box.failPut = copyId;
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect(raw.containsKey(copyId), isFalse);
      expect((raw.get(note.id) as Map)['dirty'], isTrue);
      expect(raw.containsKey(LogoutPlanStore.key), isTrue);
      if (reopen) await restart();
      api.pullRows = [
        {
          ...note.toRemote(api.user!),
          'version': 2,
          'title': 'Remote version',
          'body': 'Other device work',
          'updated_at': '2026-10-10T00:00:00.000Z',
        },
      ];
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect((raw.get(copyId) as Map)['body'], 'Only local edit');
      expect((raw.get(copyId) as Map)['dirty'], isTrue);
      expect(repository.byId(note.id)!.body, 'Other device work');
      expect(raw.containsKey(LogoutPlanStore.key), isFalse);
      expect(finished, 0);
      expect(api.logoutRequests.length, 1);
    });
  }
  test(
    'aborted failed old receipt does not regress an already newer acknowledged row',
    () async {
      final note = Note.create()
        ..title = 'Previous unsent work'
        ..body = 'Old content';
      await repository.save(note);
      api.pushResults = [
        {'id': note.id, 'ok': false, 'error': 'drive_failed'},
      ];
      api.dropPushReply = true;
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      final newer = note.copy()
        ..body = 'Later acknowledged version'
        ..serverVersion = 3
        ..dirty = false;
      newer.syncedSig = newer.contentSig;
      await raw.put(note.id, newer.toMap());
      api.reauthenticate();
      await restart();
      api.beforeRecovery = () async {
        expect((raw.get(note.id) as Map)['body'], newer.body);
        expect((raw.get(note.id) as Map)['serverVersion'], 3);
      };
      await logout();
      expect(api.closedState, 'aborted');
      expect(api.logoutRequests.length, 1);
      expect(finished, 1);
    },
  );
  for (final key in ['__pending_sync_operation', LogoutPlanStore.key]) {
    for (final after in [false, true]) {
      test(
        'metadata deletion interruption keeps notes (key=$key after=$after)',
        () async {
          final note = await interrupted();
          if (after) {
            box.failDeleteAfter = key;
          } else {
            box.failDeleteBefore = key;
          }
          await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
          expect((raw.get(note.id) as Map)['body'], note.body);
          expect((raw.get(note.id) as Map)['dirty'], isFalse);
          expect(finished, 0);
          expect(
            raw.containsKey(LogoutPlanStore.key),
            !(key == LogoutPlanStore.key && after),
          );
          await restart();
          await logout();
          expect(api.logoutRequests.length, 1);
          expect(api.admissions, 1);
          expect(api.recoveries, key == LogoutPlanStore.key && after ? 1 : 2);
          expect(finished, 1);
        },
      );
    }
  }
  test(
    'partial settled recovery keeps failed work and never uploads the accepted row again',
    () async {
      final accepted = Note.create()..body = 'Accepted local content';
      final failed = Note.create()..body = 'Unsent local content';
      await repository.save(accepted);
      await repository.save(failed);
      api.pushResults = [
        {
          'id': accepted.id,
          'ok': true,
          'version': 1,
          'updated_at': '2026-10-10T00:00:00.000Z',
        },
        {'id': failed.id, 'ok': false, 'error': 'drive_failed'},
      ];
      api.dropPushReply = true;
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      api.reauthenticate();
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect(repository.byId(accepted.id)!.dirty, isFalse);
      expect(repository.byId(failed.id)!.dirty, isTrue);
      expect(repository.byId(failed.id)!.body, failed.body);
      expect(raw.containsKey(LogoutPlanStore.key), isFalse);
      expect(api.logoutRequests.length, 1);
      expect(finished, 0);
      api.pushResults = null;
      await logout();
      expect(api.admissions, 2);
      expect(api.logoutRequests.length, 2);
      expect(api.receipts.values.last.results.single['id'], failed.id);
      expect(finished, 1);
    },
  );
  test(
    'same-content post-plan vault migration remains dirty until a new sealed attempt',
    () async {
      final note = await interrupted();
      final signature = repository.byId(note.id)!.contentSig;
      vault.unlocked = true;
      expect(await repository.migrateToVault(), 1);
      expect(repository.byId(note.id)!.contentSig, signature);
      expect((raw.get(note.id) as Map)['enc_v'], 1);
      await restart();
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect(repository.byId(note.id)!.contentSig, signature);
      expect(repository.byId(note.id)!.dirty, isTrue);
      expect(repository.byId(note.id)!.syncedSig, isEmpty);
      expect(repository.byId(note.id)!.serverVersion, 1);
      expect((raw.get(note.id) as Map)['enc_v'], 1);
      expect(raw.containsKey(LogoutPlanStore.key), isFalse);
      expect(api.logoutRequests.length, 1);
      expect(finished, 0);
      api.beforePush = () async {
        final frozen = raw.get(LogoutPlanStore.key) as Map;
        final envelope = (frozen['batches'] as List).single as Map;
        final row = (envelope['rows'] as List).single as Map;
        expect(row['enc_v'], 1);
        expect(row['title'], isEmpty);
        expect(row['body'], isEmpty);
        expect(row['payload'], isNotEmpty);
      };
      await logout();
      expect(api.admissions, 2);
      expect(api.logoutRequests.length, 2);
      expect(finished, 1);
    },
  );
}
