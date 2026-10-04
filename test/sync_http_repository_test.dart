import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_report.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/state/cloud_notes/cloud_notes_cubit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'notes_repository_lifecycle_test.dart' show TestVault;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  late Directory directory;
  late Box box;
  late ApiClient api;
  late MockClient transport;
  late NotesRepository repository;
  late CloudNotesCubit cubit;
  late Future<http.Response> Function(http.Request) push;
  late List<http.Request> requests;
  var sequence = 0;
  var refusePull = false;

  http.Response jsonResponse(Map<String, dynamic> body, {int status = 200}) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});

  List<Map<String, dynamic>> accepted(http.Request request) {
    final body = jsonDecode(request.body) as Map;
    return (body['rows'] as List).map((value) {
      final row = value as Map;
      return <String, dynamic>{
        'id': row['id'],
        'ok': true,
        'version': (row['base_version'] as int) + 1,
        'seq': ++sequence,
        'updated_at': DateTime.utc(2026, 10, 4).toIso8601String(),
      };
    }).toList();
  }

  NotesRepository newRepository() => NotesRepository.forTest(
      box: box,
      api: api,
      vault: TestVault(),
      checkConnectivity: () async => [ConnectivityResult.wifi]);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-http-contract-');
    Hive.init(directory.path);
    box = await Hive.openBox('isolated-http-notes');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('isolated-http-sync');
    FlutterSecureStorage.setMockInitialValues({
      'atomic_api_session_token': 'fixture-contract-session',
      'atomic_api_user_id': 'user-a',
      'atomic_api_user_email': 'fixture@example.test',
    });
    sequence = 0;
    refusePull = false;
    requests = [];
    push = (request) async => jsonResponse({
          'ok': true,
          'results': accepted(request),
          'charged': 10,
          'refunded': 0,
        });
    transport = MockClient((request) async {
      expect(request.url.host, 'fixture.invalid');
      requests.add(request);
      switch ((request.method, request.url.path)) {
        case ('POST', '/api/notes/push'):
          return push(request);
        case ('GET', '/api/notes/pull'):
          if (refusePull) {
            return jsonResponse({'error': 'note_content_mismatch'},
                status: 409);
          }
          return jsonResponse({
            'rows': <dynamic>[],
            'nextCursor': sequence,
            'hasMore': false,
            'cursor': DateTime.utc(2026, 10, 4).toIso8601String(),
          });
        default:
          fail('Unexpected fixture endpoint');
      }
    });
    api = ApiClient.forTest(
        client: transport,
        storage: storage,
        baseUrl: Uri.parse('https://fixture.invalid/api'));
    await api.init();
    repository = newRepository();
    await repository.start();
    cubit = CloudNotesCubit(source: repository);
  });

  tearDown(() async {
    await cubit.close();
    await repository.stop(waitForSync: true);
    repository.dispose();
    transport.close();
    await Hive.close();
    // Delete only the resolved, explicitly named temporary fixture directory.
    final resolved = await directory.resolveSymbolicLinks();
    final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
    expect(Directory(resolved).parent.path, tempRoot);
    expect(
        Directory(resolved)
            .uri
            .pathSegments
            .where((part) => part.isNotEmpty)
            .last,
        startsWith('atomic-http-contract-'));
    await Directory(resolved).delete(recursive: true);
  });

  Future<Note> addNote(String title) async {
    final note = Note(id: newId(), title: title, body: 'synthetic fixture');
    await repository.save(note);
    return note;
  }

  List<http.Request> getPushes() =>
      requests.where((request) => request.method == 'POST').toList();

  test('HTTP 502 partial results reach Hive and the caller receipt together',
      () async {
    final good = await addNote('accepted'), bad = await addNote('rejected');
    push = (request) async => jsonResponse({
          'ok': false,
          'error': 'note_sync_failed',
          'results': [
            accepted(request).first,
            {'id': bad.id, 'ok': false, 'error': 'note_write_failed'},
          ],
          'charged': 10,
          'refunded': 0,
        }, status: 502);
    final message = await cubit.sync(uploadAll: false);
    expect(message!.text, contains('could not be uploaded'));
    expect(cubit.state.lastReport!.completed, isFalse);
    expect(cubit.state.lastReport!.netCharge, 10);
    expect(cubit.state.working, isFalse);
    expect(repository.byId(good.id)!.dirty, isFalse);
    expect(repository.byId(good.id)!.serverVersion, 1);
    expect(repository.byId(bad.id)!.dirty, isTrue);
    expect((box.get(good.id) as Map)['dirty'], isFalse);
    expect((box.get(bad.id) as Map)['dirty'], isTrue);
    expect(box.get('__pending_sync_operation'), isNull);
    expect(getPushes(), hasLength(1));
  });

  for (final refund in [0, 3, 10]) {
    test('HTTP 502 all-failed receipt retains the actual $refund refund',
        () async {
      final note = await addNote('failed');
      push = (_) async => jsonResponse({
            'ok': false,
            'error': 'note_sync_failed',
            'results': [
              {'id': note.id, 'ok': false, 'error': 'note_write_failed'},
            ],
            'charged': 10,
            'refunded': refund,
          }, status: 502);
      await cubit.sync(uploadAll: false);
      final report = cubit.state.lastReport!;
      expect(report.completed, isFalse);
      expect([report.charged, report.refunded, report.netCharge],
          [10, refund, 10 - refund]);
      expect(repository.byId(note.id)!.dirty, isTrue);
      expect((box.get(note.id) as Map)['dirty'], isTrue);
      expect(getPushes(), hasLength(1));
    });
  }

  test('legacy HTTP acknowledgement clears dirty state with unknown cost',
      () async {
    final note = await addNote('legacy');
    push = (request) async =>
        jsonResponse({'ok': true, 'results': accepted(request)});
    await cubit.sync(uploadAll: false);
    final report = cubit.state.lastReport!;
    expect(report.completed, isTrue);
    expect(report.operations, hasLength(1));
    expect(report.netCharge, isNull);
    expect(repository.byId(note.id)!.dirty, isFalse);
    expect((box.get(note.id) as Map)['dirty'], isFalse);
    expect(getPushes(), hasLength(1));
  });

  test('lost HTTP response reopens Hive and replays identical standard request',
      () async {
    final note = await addNote('restart');
    push = (_) async => throw TimeoutException('fixture response lost');
    final lost = await repository.syncWithReport();
    expect(lost.completed, isFalse);
    expect(lost.netCharge, isNull);
    expect(repository.byId(note.id)!.dirty, isTrue);
    final firstBody = getPushes().single.body;
    final saved = jsonEncode(box.get('__pending_sync_operation'));
    await cubit.close();
    await repository.stop(waitForSync: true);
    repository.dispose();
    await box.close();
    box = await Hive.openBox('isolated-http-notes');
    expect(jsonEncode(box.get('__pending_sync_operation')), saved);
    await api.init();
    repository = newRepository();
    await repository.start();
    cubit = CloudNotesCubit(source: repository);
    push = (request) async => jsonResponse({
          'ok': true,
          'results': accepted(request),
          'charged': 5,
          'refunded': 0,
        });
    await cubit.sync(uploadAll: false);
    final recovered = cubit.state.lastReport!;
    expect(recovered.completed, isTrue);
    expect(recovered.netCharge, 5);
    expect(recovered.operations.single.recovered, isTrue);
    expect(recovered.operations.single.instant, isFalse);
    expect(recovered.operations.single.requestId,
        lost.operations.single.requestId);
    expect(getPushes().last.body, firstBody);
    expect(jsonDecode(firstBody)['mode'], 'standard');
    expect(box.get('__pending_sync_operation'), isNull);
    expect(repository.byId(note.id)!.dirty, isFalse);
    expect(lost.netCharge, isNull,
        reason: 'The prior caller snapshot stays unknown');
  });

  test('HTTP pull refusal preserves the upload receipt and saved cursor',
      () async {
    final note = await addNote('uploaded');
    refusePull = true;
    await cubit.sync(uploadAll: false);
    final report = cubit.state.lastReport!;
    expect(report.completed, isFalse);
    expect(report.netCharge, 10);
    expect(report.errorMessage,
        'A cloud note could not be read safely. Try syncing again.');
    expect(repository.byId(note.id)!.dirty, isFalse);
    expect(box.get('__sync_cursor__'), isNull);
    refusePull = false;
    await cubit.sync(uploadAll: false);
    expect(cubit.state.lastReport!.completed, isTrue);
    expect(cubit.state.lastReport!.netCharge, 0);
    expect(getPushes(), hasLength(1));
    expect(box.get('__sync_cursor__'), 1);
  });

  test('receive-only uses real HTTP pull without an upload receipt', () async {
    await cubit.sync(uploadAll: false);
    final report = cubit.state.lastReport!;
    expect(report.completed, isTrue);
    expect(report.activity, SyncAttemptActivity.started);
    expect(report.operations, isEmpty);
    expect(report.netCharge, 0);
    expect(getPushes(), isEmpty);
    expect(requests.single.url.path, '/api/notes/pull');
    expect(repository.count, 0);
  });

  test('standard HTTP sync charges only the first 50-row batch in its window',
      () async {
    for (var index = 0; index < 100; index++) {
      await addNote('fixture $index');
    }
    push = (request) async => jsonResponse({
          'ok': true,
          'results': accepted(request),
          'charged': 5,
          'refunded': 0,
        });
    final report = await repository.syncWithReport();
    expect(report.completed, isFalse);
    expect(report.netCharge, 5);
    expect(report.operations, hasLength(1));
    final body = jsonDecode(getPushes().single.body) as Map;
    expect(body['mode'], 'standard');
    expect(body['rows'], hasLength(50));
    expect(repository.pendingCount, 50);
    expect(repository.count, 100);
    expect(repository.nextAutoSyncAt, isNotNull);
  });

  test('current HTTP 401 retires the report and preserves unsent Hive notes',
      () async {
    final note = await addNote('unsent');
    push = (_) async => jsonResponse({'error': 'invalid_session'}, status: 401);
    final message = await cubit.sync(uploadAll: false);
    expect(message, isNull);
    expect(api.isSignedIn, isFalse);
    expect(cubit.state.lastReport, isNull);
    expect(cubit.state.working, isFalse);
    expect((box.get(note.id) as Map)['dirty'], isTrue);
    expect((box.get('__pending_sync_operation') as Map)['requestId'],
        jsonDecode(getPushes().single.body)['requestId']);
    expect(getPushes(), hasLength(1));
  });
}
