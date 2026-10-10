import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/api/logout_protocol.dart';
import 'package:atomic_notes/database/logout_plan.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/settings_page.dart';
import 'package:atomic_notes/profile/profile_store.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/logout_dialogbox.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'notes_repository_lifecycle_test.dart' show TestApi, TestVault;

// Public synthetic account and receipts; no real auth, Drive or Energy is used.
class LogoutTestApi extends TestApi {
  LogoutTestApi() {
    user = newId();
  }
  bool available = true;
  bool emergency = true;
  String? completion;
  bool dropPushReply = false,
      dropCompletionReply = false,
      dropAbortReply = false;
  int dropBatch = 1, admissions = 0, completes = 0, aborts = 0;
  String? attempt, closedState;
  List<Map<String, dynamic>>? manifest;
  final receipts = <String, PushReply>{};
  final logoutRequests = <String>[];
  Future<void> Function()? beforeAdmission, beforeCompletion;
  @override
  String? get pendingLogoutCompletion => completion;
  @override
  String? get currentUserEmail => 'public@example.test';
  @override
  Future<String> logoutSessionHash() async => 'a' * 64;
  @override
  Future<bool> logoutSyncAvailable() async => available;
  @override
  Future<LogoutAdmission> beginLogoutSync(
      String attemptId, List<Map<String, dynamic>> batches) async {
    admissions++;
    await beforeAdmission?.call();
    if (attempt == attemptId && closedState != null) {
      throw ApiException('logout_attempt_closed', 409);
    }
    attempt = attemptId;
    manifest = batches;
    closedState = null;
    return LogoutAdmission(
        attemptId: attemptId,
        funding: emergency ? LogoutFunding.emergency : LogoutFunding.paid,
        batches: batches.length,
        costPerBatch: emergency ? 0 : 10);
  }

  @override
  Future<PushReply> pushLogoutNotes(LogoutEnvelope envelope) async {
    logoutRequests.add(envelope.requestId);
    await beforePush?.call();
    final result = receipts.putIfAbsent(
        envelope.requestId,
        () => PushReply(
            requestId: envelope.requestId,
            instant: true,
            receipt: PushReceipt(charged: emergency ? 0 : 10, refunded: 0),
            results: pushResults ??
                envelope.rows
                    .map((row) => <String, dynamic>{
                          'id': row['id'],
                          'ok': true,
                          'version': (row['base_version'] as int) + 1,
                          'seq': ++sequence,
                          'updated_at':
                              DateTime.now().toUtc().toIso8601String(),
                        })
                    .toList()));
    if (dropPushReply && receipts.length == dropBatch) {
      dropPushReply = false;
      throw const SocketException('Public fixture lost reply');
    }
    return result;
  }

  @override
  Future<void> completeLogoutSync(String attemptId) async {
    completion = attemptId;
    completes++;
    await beforeCompletion?.call();
    if (closedState != 'completed' &&
        (manifest == null ||
            manifest!.any((batch) =>
                !receipts.containsKey(batch['requestId']) ||
                receipts[batch['requestId']]!
                    .results
                    .any((result) => result['ok'] != true)))) {
      completion = null;
      throw ApiException('logout_sync_incomplete', 409);
    }
    closedState = 'completed';
    if (dropCompletionReply) {
      dropCompletionReply = false;
      throw const SocketException('Public fixture lost completion');
    }
  }

  @override
  Future<void> abortLogoutSync(String attemptId) async {
    aborts++;
    closedState = 'aborted';
    if (dropAbortReply) {
      dropAbortReply = false;
      throw const SocketException('Public fixture lost abort');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;
  late LogoutTestApi api;
  late TestVault vault;
  late NotesRepository repo;
  var online = true, finished = 0;
  var widgetResourcesClosed = false;
  final statuses = <String>[];
  NotesRepository createRepository() => NotesRepository.forTest(
      box: box,
      api: api,
      vault: vault,
      checkConnectivity: () async =>
          [online ? ConnectivityResult.wifi : ConnectivityResult.none]);
  Future<void> logout() => repo.logoutSafely(
      onProgress: statuses.add,
      finishLocal: (check) async {
        check();
        finished++;
      });
  Future<Note> dirtyNote() async {
    final note = Note.create()
      ..title = 'Public fixture'
      ..body = 'Preserve this offline edit';
    await repo.save(note);
    return note;
  }

  Future<void> restart() async {
    await repo.stop(waitForSync: true);
    repo.dispose();
    await box.close();
    box = await Hive.openBox('logout-notes');
    repo = createRepository();
    await repo.start();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-logout-test-');
    Hive.init(directory.path);
    box = await Hive.openBox('logout-notes');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('logout-sync');
    await SyncStatusHelper.setSyncStatus(true);
    api = LogoutTestApi();
    vault = TestVault();
    online = true;
    finished = 0;
    statuses.clear();
    widgetResourcesClosed = false;
    repo = createRepository();
    await repo.start();
  });
  tearDown(() async {
    if (widgetResourcesClosed) return;
    await repo.stop(waitForSync: true);
    repo.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('clean offline logout does not admit, upload or spend Energy', () async {
    final note = await dirtyNote();
    expect(await repo.syncNow(instant: true), isTrue);
    online = false;
    await logout();
    expect(finished, 1);
    expect(api.admissions, 0);
    expect(api.logoutRequests, isEmpty);
    expect(box.containsKey(note.id), isFalse);
  });
  for (final free in [true, false]) {
    test(
        'dirty logout uses bound ${free ? 'emergency' : 'paid'} receipt before clearing',
        () async {
      final note = await dirtyNote();
      api.emergency = free;
      api.beforeCompletion = () async {
        expect(box.containsKey(note.id), isTrue);
        expect((box.get(note.id) as Map)['dirty'], isFalse);
        expect((box.get(LogoutPlanStore.key) as Map)['phase'], 'completing');
        expect(finished, 0);
      };
      await logout();
      expect(api.receipts.values.single.receipt!.charged, free ? 0 : 10);
      expect(statuses.any((s) => s.contains(free ? 'no Energy' : '10 Energy')),
          isTrue);
      expect(finished, 1);
      expect(box.isEmpty, isTrue);
    });
  }
  for (final reason in ['offline', 'disabled', 'unavailable', 'corrupt']) {
    test('$reason refuses logout and retains local content', () async {
      final note = await dirtyNote();
      if (reason == 'offline') online = false;
      if (reason == 'disabled') await SyncStatusHelper.setSyncStatus(false);
      if (reason == 'unavailable') api.available = false;
      if (reason == 'corrupt') await box.put(LogoutPlanStore.key, null);
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect((box.get(note.id) as Map)['body'], note.body);
      expect(finished, 0);
      expect(api.admissions, 0);
      expect(api.logoutRequests, isEmpty);
    });
  }
  test(
      'locked hidden encrypted changes require unlock without discarding ciphertext',
      () async {
    vault.unlocked = true;
    final note = await dirtyNote();
    await repo.lockVault();
    final saved = Map.from(box.get(note.id) as Map);
    expect(repo.pendingCount, 0);
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    expect(box.get(note.id), saved);
    expect(finished, 0);
    expect(api.admissions, 0);
  });
  test('cloud wipe version-zero clean note must be uploaded before logout',
      () async {
    final note = await dirtyNote();
    expect(await repo.syncNow(instant: true), isTrue);
    expect((await repo.wipeRemote()).ok, isTrue);
    expect(repo.pendingCount, 0);
    await logout();
    expect(api.receipts.values.single.results.single['id'], note.id);
    expect(finished, 1);
  });
  test(
      'original paid pending request is reconciled without relabeling it emergency',
      () async {
    await dirtyNote();
    api.beforePush = () async {
      throw const SocketException('Public previous sync');
    };
    expect(await repo.syncNow(instant: true), isFalse);
    final request = api.requestIds.single;
    api.beforePush = null;
    await logout();
    expect(api.requestIds, [request, request]);
    expect(api.pushModes, [true, true]);
    expect(api.admissions, 0);
    expect(finished, 1);
  });
  for (final free in [true, false]) {
    test(
        'lost second batch reply survives actual Hive reopen (${free ? 'free' : 'paid'})',
        () async {
      for (var i = 0; i < 51; i++) {
        await dirtyNote();
      }
      api.emergency = free;
      api.dropPushReply = true;
      api.dropBatch = 2;
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      final attempt = api.attempt,
          original = api.manifest!.map((b) => b['requestId']).toList();
      expect(api.receipts.length, 2);
      expect(finished, 0);
      expect(box.containsKey('__pending_sync_operation'), isTrue);
      await restart();
      await logout();
      expect(api.attempt, attempt);
      expect(api.receipts.length, 2);
      expect(api.logoutRequests,
          [original[0], original[1], original[1], original[0], original[1]]);
      expect(
          api.receipts.values
              .map((r) => r.receipt!.charged)
              .reduce((a, b) => a + b),
          free ? 0 : 20);
      expect(finished, 1);
      expect(box.isEmpty, isTrue);
    });
  }
  test(
      'completion reply loss replays completion first after reopen without another upload',
      () async {
    await dirtyNote();
    api.dropCompletionReply = true;
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    final attempt = api.attempt;
    expect((box.get(LogoutPlanStore.key) as Map)['phase'], 'completing');
    expect(finished, 0);
    await restart();
    await logout();
    expect(api.attempt, attempt);
    expect(api.admissions, 1);
    expect(api.logoutRequests.length, 1);
    expect(api.completes, 2);
    expect(finished, 1);
  });
  test(
      'partial receipt refuses logout and new explicit retry can sync retained note',
      () async {
    final note = await dirtyNote();
    api.pushResults = [
      {'id': note.id, 'ok': false, 'error': 'drive_failed'}
    ];
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    expect(repo.byId(note.id)!.dirty, isTrue);
    expect(finished, 0);
    expect(api.aborts, 1);
    expect(box.containsKey(LogoutPlanStore.key), isFalse);
    final previous = api.attempt;
    api.pushResults = null;
    await logout();
    expect(api.attempt, isNot(previous));
    expect(finished, 1);
  });
  test('lost abort receipt is confirmed before metadata removal and a new plan',
      () async {
    final note = await dirtyNote();
    api.dropAbortReply = true;
    api.pushResults = [
      {'id': note.id, 'ok': false, 'error': 'drive_failed'}
    ];
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    expect(box.containsKey(LogoutPlanStore.key), isTrue);
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    expect(api.aborts, 2);
    expect(box.containsKey(LogoutPlanStore.key), isFalse);
    expect(repo.byId(note.id)!.dirty, isTrue);
    expect(finished, 0);
    api.pushResults = null;
    await logout();
    expect(finished, 1);
  });
  test('conflict preserves both versions and cancels logout', () async {
    final note = await dirtyNote();
    api.pushResults = [
      {'id': note.id, 'ok': false, 'error': 'note_conflict'}
    ];
    api.pullRows = [
      {
        ...note.toRemote(api.user!),
        'version': 2,
        'title': 'Other device',
        'body': 'Public other version',
        'updated_at': DateTime.now().toUtc().toIso8601String()
      }
    ];
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    expect(repo.byId(note.id)!.body, 'Public other version');
    expect(repo.visible().singleWhere((n) => n.id != note.id).body,
        'Preserve this offline edit');
    expect(finished, 0);
    expect(api.aborts, 1);
  });
  test(
      'writer, duplicate logout, wipe and vault lock are fenced during an upload',
      () async {
    final note = await dirtyNote();
    final entered = Completer<void>(), release = Completer<void>();
    api.beforePush = () async {
      entered.complete();
      await release.future;
    };
    final pending = logout();
    await entered.future;
    await expectLater(repo.save(note.copy()), throwsStateError);
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    await expectLater(repo.lockVault(), throwsStateError);
    await expectLater(repo.wipeLocalNotes(), throwsStateError);
    expect((await repo.wipeRemote()).ok, isFalse);
    expect(await repo.syncNow(instant: true), isFalse);
    release.complete();
    await pending;
    expect(finished, 1);
  });
  test(
      'late receipt for a replaced session cannot clear notes or end the new session',
      () async {
    final note = await dirtyNote();
    final entered = Completer<void>(), release = Completer<void>();
    api.beforePush = () async {
      entered.complete();
      await release.future;
    };
    final pending = logout();
    await entered.future;
    api.sessionRevision++;
    release.complete();
    await expectLater(pending, throwsA(isA<LogoutBlocked>()));
    expect(box.containsKey(note.id), isTrue);
    expect(finished, 0);
    expect(box.containsKey(LogoutPlanStore.key), isTrue);
  });
  test('editing during an interrupted plan is retained and requires a new plan',
      () async {
    final note = await dirtyNote();
    api.dropPushReply = true;
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    final edited = repo.byId(note.id)!.copy()..body = 'Newer unsynced content';
    await repo.save(edited);
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    expect(repo.byId(note.id)!.body, edited.body);
    expect(repo.byId(note.id)!.dirty, isTrue);
    expect(finished, 0);
    expect(box.containsKey(LogoutPlanStore.key), isFalse);
    await logout();
    expect(finished, 1);
  });
  test(
      'damaged pending snapshot refuses a receipt even when request identity matches',
      () async {
    final note = await dirtyNote();
    api.dropPushReply = true;
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    final saved =
        Map<String, dynamic>.from(box.get('__pending_sync_operation') as Map);
    saved['sigs'] = {note.id: 'public-tampered-signature'};
    await box.put('__pending_sync_operation', saved);
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    expect(api.logoutRequests.length, 1);
    expect(finished, 0);
    expect(box.containsKey(note.id), isTrue);
    expect(box.containsKey(LogoutPlanStore.key), isTrue);
  });
  test(
      'completion intent freezes edits and vault conversion until confirmation',
      () async {
    final note = await dirtyNote();
    api.dropCompletionReply = true;
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    await expectLater(repo.save(note.copy()), throwsStateError);
    await expectLater(repo.migrateToVault(), throwsStateError);
    final pulls = api.pullCursors.length;
    await repo.reloadAfterUnlock();
    expect(api.pullCursors.length, pulls);
    expect(box.containsKey(note.id), isTrue);
    expect(finished, 0);
  });
  testWidgets(
      'Settings closes confirmation, shows emergency progress and blocks navigation while syncing',
      (tester) async {
    final entered = Completer<void>(),
        release = Completer<void>(),
        done = Completer<void>();
    final notes = NotesBloc(
        source: repo, isSyncEnabled: () => true, isOnline: () async => true);
    final profile = ProfileCubit(store: ProfileStore.instance);
    await tester.pumpWidget(MultiBlocProvider(
        providers: [
          BlocProvider<NotesBloc>.value(value: notes),
          BlocProvider<ProfileCubit>.value(value: profile),
        ],
        child: MaterialApp(
            routes: {
              '/cloudsyncpage': (_) => const Text('Unexpected navigation')
            },
            home: SettingsPage(
                api: api,
                repository: repo,
                logoutOperation: ({required finishLocal, onProgress}) async {
                  onProgress?.call('Emergency InstaSync for logout — no Energy used…');
                  entered.complete();
                  await release.future;
                  await finishLocal(() {});
                },
                finishLogout: (check) async {
                  check();
                  finished++;
                  done.complete();
                }))));
    await tester.tap(find.text('LOG OUT'));
    await tester.pumpAndSettle();
    expect(find.byType(DialogBoxLogout), findsOneWidget);
    // UI state uses a controlled coordinator; actual Hive delivery/restart is
    // exercised by the repository cases above, outside the simulated clock.
    await tester.tap(find.widgetWithText(InkActionButton, 'CONFIRM'));
    await tester.pump(); expect(entered.isCompleted, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DialogBoxLogout), findsNothing);
    expect(find.text('Emergency InstaSync for logout — no Energy used…'),
        findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    expect(
        tester
            .widget<AbsorbPointer>(find.descendant(of: find.byType(SettingsPage),
              matching: find.byWidgetPredicate((widget) => widget is AbsorbPointer && widget.absorbing)).first)
            .absorbing,
        isTrue);
    expect(finished, 0);
    release.complete(); await tester.pump(); expect(done.isCompleted, isTrue);
    await tester.pump();
    expect(finished, 1);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await notes.close(); await profile.close();
      // Completed logout already drained writes before clearing Hive. Do not
      // await a simulated-clock Future again from the real IO cleanup zone.
      await repo.stop(); repo.dispose();
      await Hive.close(); await directory.delete(recursive: true);
      widgetResourcesClosed = true;
    });
  });
  test('replayed conflict cannot overwrite a separately edited conflict copy', () async {
    final note = await dirtyNote(); api.dropPushReply = true;
    api.pushResults = [{'id': note.id, 'ok': false, 'error': 'note_conflict'}];
    api.pullRows = [{...note.toRemote(api.user!), 'version': 2, 'title': 'Other device',
      'body': 'Public other version', 'updated_at': DateTime.now().toUtc().toIso8601String()}];
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    final plan = await LogoutPlanStore(box).load(userId: api.user!, sessionHash: 'a' * 64);
    final copy = Note(id: plan!.snapshots[note.id]!.conflictId,
      title: 'Existing conflict copy', body: 'Separately edited copy');
    await repo.save(copy);
    await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
    expect(repo.byId(copy.id)!.body, copy.body);
    expect(repo.visible().map((n) => n.body), containsAll([
      'Public other version', 'Separately edited copy', 'Preserve this offline edit']));
    expect(finished, 0);
  });
  for (final operation in ['conversion', 'bulk upload']) {
    test('logout cannot overtake an already-running $operation', () async {
      await dirtyNote(); expect(await repo.syncNow(instant: true), isTrue);
      vault.unlocked = true;
      vault.sealEntered = Completer<void>(); vault.sealGate = Completer<void>();
      final mutation = operation == 'conversion' ? repo.migrateToVault() : repo.markAllForUpload();
      await vault.sealEntered!.future;
      await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
      expect(finished, 0); expect(api.admissions, 0); expect(box.isNotEmpty, isTrue);
      vault.sealGate!.complete(); await mutation;
    });
  }
}
