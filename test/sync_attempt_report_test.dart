import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_report.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

// Reuse the existing isolated API/vault fixtures; that library's main is not run.
import 'notes_repository_lifecycle_test.dart' show TestApi, TestVault;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late NotesRepository repository;
  late TestApi api;
  late List<ConnectivityResult> connection;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-sync-report-test-');
    Hive.init(directory.path);
    final box = await Hive.openBox('isolated-report-notes');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('isolated-report-sync');
    api = TestApi();
    connection = [ConnectivityResult.wifi];
    repository = NotesRepository.forTest(box: box, api: api, vault: TestVault(),
      checkConnectivity: () async => connection);
    await repository.start();
  });
  tearDown(() async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Future<Note> addNote(String title) async {
    final note = Note(id: newId(), title: title, body: 'fixture');
    await repository.save(note);
    return note;
  }

  test('R8 two instant batches retain distinct receipts and total their historical cost', () async {
    api.pushReceipt = const PushReceipt(charged: 10, refunded: 0);
    for (var i = 0; i < 100; i++) { await addNote('note $i'); }
    final report = await repository.syncWithReport(instant: true);
    expect(report.completed, isTrue);
    expect(report.activity, SyncAttemptActivity.started);
    expect(report.operations.map((operation) => operation.requestId), api.requestIds);
    expect(report.operations.length, 2);
    expect(report.operations.every((operation) => operation.instant && !operation.recovered), isTrue);
    expect([report.charged, report.refunded, report.netCharge], [20, 0, 20]);
    expect(() => report.operations.clear(), throwsUnsupportedError);
    expect(repository.pendingCount, 0);
  });

  test('R8 standard window reports only the completed first batch', () async {
    api.pushReceipt = const PushReceipt(charged: 5, refunded: 0);
    for (var i = 0; i < 100; i++) { await addNote('note $i'); }
    final report = await repository.syncWithReport();
    expect(report.completed, isFalse);
    expect(report.operations.length, 1);
    expect(report.charged, 5);
    expect(repository.pendingCount, 50);
  });

  test('R8 receive-only attempt has no uploads and no upload charge', () async {
    final report = await repository.syncWithReport(instant: true);
    expect(report.completed, isTrue);
    expect(report.activity, SyncAttemptActivity.started);
    expect(report.operations, isEmpty);
    expect(report.netCharge, 0);
    expect(api.pushes, isEmpty);
    expect(api.pullCursors.length, 1);
  });

  test('R8 legacy receipt is unknown although its note was acknowledged', () async {
    final note = await addNote('legacy');
    final report = await repository.syncWithReport(instant: true);
    expect(report.completed, isTrue);
    expect(report.operations.length, 1);
    expect(report.operations.single.requestId, api.requestIds.single);
    expect(report.charged, isNull);
    expect(report.refunded, isNull);
    expect(report.netCharge, isNull);
    expect(repository.byId(note.id)!.dirty, isFalse);
  });

  test('R8 partial failure retains charge and successful acknowledgement', () async {
    final good = await addNote('accepted'), bad = await addNote('failed');
    api.pushReceipt = const PushReceipt(charged: 10, refunded: 0);
    api.pushResults = [
      {'id': good.id, 'ok': true, 'version': 1, 'seq': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String()},
      {'id': bad.id, 'ok': false, 'error': 'note_write_failed'},
    ];
    final report = await repository.syncWithReport(instant: true);
    expect(report.completed, isFalse);
    expect(report.netCharge, 10);
    expect(report.errorMessage, contains('could not be uploaded'));
    expect(repository.byId(good.id)!.dirty, isFalse);
    expect(repository.byId(bad.id)!.dirty, isTrue);
  });

  test('R8 all-failed capped refund uses recorded amount', () async {
    final note = await addNote('failed');
    api.pushReceipt = const PushReceipt(charged: 10, refunded: 3);
    api.pushResults = [{'id': note.id, 'ok': false, 'error': 'note_write_failed'}];
    final report = await repository.syncWithReport(instant: true);
    expect(report.completed, isFalse);
    expect([report.charged, report.refunded, report.netCharge], [10, 3, 7]);
    expect(repository.byId(note.id)!.dirty, isTrue);
  });

  test('R8 lost response stays unknown and recovered request retains original standard mode', () async {
    await addNote('recovery');
    api.beforePush = () async { throw TimeoutException('synthetic lost response'); };
    final lost = await repository.syncWithReport();
    expect(lost.completed, isFalse);
    expect(lost.operations.length, 1);
    expect(lost.netCharge, isNull);
    api.beforePush = null;
    api.pushReceipt = const PushReceipt(charged: 5, refunded: 0);
    final recovered = await repository.syncWithReport(instant: true);
    expect(recovered.completed, isTrue);
    expect(recovered.operations.single.requestId, lost.operations.single.requestId);
    expect(recovered.operations.single.recovered, isTrue);
    expect(recovered.operations.single.instant, isFalse);
    expect(recovered.netCharge, 5);
    expect(lost.netCharge, isNull, reason: 'Prior caller snapshot remains unchanged');
  });

  test('R8 pull failure retains the preceding upload receipt', () async {
    await addNote('uploaded');
    api.pushReceipt = const PushReceipt(charged: 10, refunded: 0);
    api.pullFailure = ApiException('note_content_unavailable', 409);
    final report = await repository.syncWithReport(instant: true);
    expect(report.completed, isFalse);
    expect(report.charged, 10);
    expect(report.errorMessage, contains('missing or unreadable'));
    expect(repository.pendingCount, 0);
  });

  test('R8 waiting caller does not borrow the running sync receipts', () async {
    await addNote('busy');
    api.pushReceipt = const PushReceipt(charged: 10, refunded: 0);
    final entered = Completer<void>(), gate = Completer<void>();
    api.beforePush = () { entered.complete(); return gate.future; };
    final running = repository.syncWithReport(instant: true);
    await entered.future;
    final waiting = repository.syncWithReport(instant: true);
    gate.complete();
    final owner = await running, joined = await waiting;
    expect(owner.charged, 10);
    expect(joined.completed, isTrue);
    expect(joined.activity, SyncAttemptActivity.joined);
    expect(joined.operations, isEmpty);
    expect(joined.netCharge, isNull);
  });

  for (final sameAccount in [false, true]) {
    test('R8 retired ${sameAccount ? 'same' : 'other'} account attempt exposes no receipts', () async {
      await addNote('retired');
      api.pushReceipt = const PushReceipt(charged: 10, refunded: 0);
      final entered = Completer<void>(), gate = Completer<void>();
      api.beforePush = () { entered.complete(); return gate.future; };
      final running = repository.syncWithReport(instant: true);
      await entered.future;
      await repository.stop(); repository.clearMemory();
      api.user = sameAccount ? 'user-a' : 'user-b';
      api.sessionRevision++;
      gate.complete();
      final retired = await running;
      expect(retired.completed, isFalse);
      expect(retired.activity, SyncAttemptActivity.retired);
      expect(retired.operations, isEmpty);
      expect(retired.errorMessage, isNull);
      expect(retired.netCharge, isNull);
    });
  }

  test('R8 a later batch with a lost response makes the overall cost unknown', () async {
    api.pushReceipt = const PushReceipt(charged: 10, refunded: 0);
    for (var i = 0; i < 100; i++) { await addNote('note $i'); }
    api.beforePush = () async {
      if (api.pushes.length == 2) throw TimeoutException('second batch response lost');
    };
    final report = await repository.syncWithReport(instant: true);
    expect(report.completed, isFalse);
    expect(report.operations.length, 2);
    expect(report.operations.first.charged, 10);
    expect(report.operations.last.charged, isNull);
    expect(report.netCharge, isNull);
    expect(repository.pendingCount, 50);
  });

  test('R8 session revision alone retires the report before repository teardown', () async {
    await addNote('session');
    api.pushReceipt = const PushReceipt(charged: 10, refunded: 0);
    final entered = Completer<void>(), gate = Completer<void>();
    api.beforePush = () { entered.complete(); return gate.future; };
    final running = repository.syncWithReport(instant: true);
    await entered.future;
    api.sessionRevision++;
    gate.complete();
    final report = await running;
    expect(report.activity, SyncAttemptActivity.retired);
    expect(report.completed, isFalse);
    expect(report.operations, isEmpty);
    expect(report.netCharge, isNull);
  });

  test('R8 completion listeners cannot replace the caller error snapshot', () async {
    api.pullFailure = ApiException('note_content_unavailable', 409);
    repository.addListener(() {
      if (!repository.isSyncing && repository.lastError != null) repository.lastError = null;
    });
    final report = await repository.syncWithReport(instant: true);
    expect(report.completed, isFalse);
    expect(report.errorMessage, contains('missing or unreadable'));
    expect(repository.lastError, isNull);
  });

  test('R8 offline attempt never repeats the preceding receipt', () async {
    await addNote('first');
    api.pushReceipt = const PushReceipt(charged: 10, refunded: 0);
    expect((await repository.syncWithReport(instant: true)).charged, 10);
    connection = [ConnectivityResult.none];
    final offline = await repository.syncWithReport(instant: true);
    expect(offline.completed, isFalse);
    expect(offline.activity, SyncAttemptActivity.notStarted);
    expect(offline.operations, isEmpty);
    expect(offline.netCharge, isNull);
    expect(offline.errorMessage, contains('Offline'));
  });
}
