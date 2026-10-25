import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
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
  late List<Map<String, dynamic>> pullRows;
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
    pullRows = [];
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
            'rows': pullRows,
            'nextCursor': sequence,
            'hasMore': false,
            'cursor': DateTime.utc(2026, 10, 4).toIso8601String(),
          });
        case ('DELETE', '/api/notes'):
          return jsonResponse({});
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

  void offerRemoteNote() {
    final remote = Note(
        id: 'remote-receive-fixture',
        title: 'Other device',
        body: 'Remote work');
    pullRows = [
      {...remote.toRemote('user-a'), 'version': 1, 'seq': 1},
    ];
    sequence = 1;
  }

  for (final instant in [false, true]) {
    test(
        'B02 definitive refusal receives remote work and preserves newer local edits (instant=$instant)',
        () async {
      final note = await addNote('queued locally');
      offerRemoteNote();
      pullRows.add({
        ...note.toRemote('user-a'),
        'version': 1,
        'body': 'Competing remote edit'
      });
      final entered = Completer<void>();
      final release = Completer<void>();
      push = (_) async {
        entered.complete();
        await release.future;
        return jsonResponse({'error': 'insufficient_energy'}, status: 409);
      };
      final syncing = repository.syncWithReport(instant: instant);
      await entered.future;
      await repository.save(note..body = 'Newer local edit');
      release.complete();
      final report = await syncing;
      expect(report.completed, isFalse);
      expect(report.errorMessage, contains('Not enough Atomic Energy'));
      expect(report.netCharge, isNull);
      expect(repository.byId(note.id)!.body, 'Newer local edit');
      expect(repository.byId(note.id)!.dirty, isTrue);
      expect((box.get(note.id) as Map)['body'], 'Newer local edit');
      expect((box.get(note.id) as Map)['dirty'], isTrue);
      expect(box.get('__pending_sync_operation'), isNull);
      expect(getPushes(), hasLength(1));
      expect(repository.byId('remote-receive-fixture')?.body, 'Remote work');
      expect(repository.byId(note.id)!.serverVersion, 0);
      expect(
          requests.where((request) => request.method == 'GET'), hasLength(1));
      expect(box.get('__sync_cursor__'), 1);
      final refusedId = jsonDecode(getPushes().single.body)['requestId'];
      push = (request) async => jsonResponse({
            'results': accepted(request),
            'charged': instant ? 10 : 5,
            'refunded': 0,
          });
      final funded = await repository.syncWithReport(instant: instant);
      expect(funded.completed, isTrue);
      expect(funded.netCharge, instant ? 10 : 5);
      final retry = jsonDecode(getPushes().last.body) as Map;
      expect(retry['requestId'], isNot(refusedId));
      expect((retry['rows'] as List).single['body'], 'Newer local edit');
      expect(repository.byId(note.id)!.dirty, isFalse);
      expect(report.netCharge, isNull,
          reason: 'Later funding cannot rewrite an unknown receipt');
    });
  }

  test('B01 unknown HTTP write blocks pull and replays the frozen envelope',
      () async {
    final note = await addNote('queued before unknown write');
    offerRemoteNote();
    push = (_) async =>
        jsonResponse({'error': 'provider_unavailable'}, status: 503);
    final failed = await repository.syncWithReport();
    final originalBody = getPushes().single.body;
    final frozen = jsonEncode(box.get('__pending_sync_operation'));
    expect(failed.completed, isFalse);
    expect(failed.netCharge, isNull);
    expect(box.get('__pending_sync_operation'), isA<Map>());
    expect(requests.where((request) => request.method == 'GET'), isEmpty);
    expect(repository.byId('remote-receive-fixture'), isNull);
    expect(box.get('__sync_cursor__'), isNull);
    await repository.save(note..body = 'Edit after unknown write');
    final repeated = await repository.syncWithReport(instant: true);
    expect(repeated.completed, isFalse);
    expect(repeated.operations.single.recovered, isTrue);
    expect(repeated.operations.single.instant, isFalse);
    expect(getPushes().map((request) => request.body),
        [originalBody, originalBody]);
    expect(jsonEncode(box.get('__pending_sync_operation')), frozen);
    expect((box.get(note.id) as Map)['body'], 'Edit after unknown write');
    expect((box.get(note.id) as Map)['dirty'], isTrue);
    expect(requests.where((request) => request.method == 'GET'), isEmpty);
    expect(box.get('__sync_cursor__'), isNull);
  });

  for (final scenario in [
    'same_code_503',
    'other_code_409',
    'substring_code_409',
    'generic_error_text',
    'network_error_text'
  ]) {
    test(
        'B02 ambiguous refusal $scenario retains its envelope and blocks receive',
        () async {
      final note = await addNote('unresolved admission');
      offerRemoteNote();
      push = (_) async {
        return switch (scenario) {
          'same_code_503' =>
            jsonResponse({'error': 'insufficient_energy'}, status: 503),
          'other_code_409' =>
            jsonResponse({'error': 'operation_in_progress'}, status: 409),
          'substring_code_409' =>
            jsonResponse({'error': 'not_insufficient_energy'}, status: 409),
          'generic_error_text' => throw Exception('insufficient_energy'),
          _ => throw const SocketException('insufficient_energy'),
        };
      };
      final report = await repository.syncWithReport();
      expect(report.completed, isFalse);
      expect(report.netCharge, isNull);
      expect(requests.where((request) => request.method == 'GET'), isEmpty);
      final frozen = box.get('__pending_sync_operation') as Map?;
      expect(frozen?['requestId'],
          jsonDecode(getPushes().single.body)['requestId']);
      expect((box.get(note.id) as Map)['dirty'], isTrue);
      expect(box.get('__sync_cursor__'), isNull);
    });
  }

  test('B02 a recovered unknown request stays frozen after a later 409 refusal',
      () async {
    final note = await addNote('unknown original outcome');
    offerRemoteNote();
    push = (_) async => throw TimeoutException('Public fixture lost reply');
    await repository.syncWithReport();
    final frozen = jsonEncode(box.get('__pending_sync_operation'));
    final originalBody = getPushes().single.body;
    await repository.save(note..body = 'Newer recovery edit');
    push = (_) async =>
        jsonResponse({'error': 'insufficient_energy'}, status: 409);
    final recovered = await repository.syncWithReport(instant: true);
    expect(recovered.completed, isFalse);
    expect(recovered.netCharge, isNull);
    expect(recovered.operations.single.recovered, isTrue);
    expect(getPushes().last.body, originalBody);
    expect(jsonEncode(box.get('__pending_sync_operation')), frozen);
    expect((box.get(note.id) as Map)['body'], 'Newer recovery edit');
    expect(requests.where((request) => request.method == 'GET'), isEmpty);
    expect(box.get('__sync_cursor__'), isNull);
  });

  test('B02 refused upload still reports an independent pull failure',
      () async {
    final note = await addNote('upload still waiting');
    offerRemoteNote();
    refusePull = true;
    push = (_) async =>
        jsonResponse({'error': 'insufficient_energy'}, status: 409);
    final report = await repository.syncWithReport();
    expect(requests.where((request) => request.method == 'GET'), hasLength(1));
    expect(report.completed, isFalse);
    expect(report.netCharge, isNull);
    expect(report.errorMessage,
        'A cloud note could not be read safely. Try syncing again.');
    expect((box.get(note.id) as Map)['dirty'], isTrue);
    expect(box.get('__pending_sync_operation'), isNull);
    expect(box.get('__sync_cursor__'), isNull);
    expect(repository.byId('remote-receive-fixture'), isNull);
  });

  for (final replaceEnvelope in [false, true]) {
    test(
        'B02 a ${replaceEnvelope ? 'replaced envelope' : 'cloud wipe'} fences receiving after refusal',
        () async {
      final note = await addNote('fenced local work');
      offerRemoteNote();
      final entered = Completer<void>();
      final release = Completer<void>();
      push = (_) async {
        entered.complete();
        await release.future;
        return jsonResponse({'error': 'insufficient_energy'}, status: 409);
      };
      final syncing = repository.syncWithReport();
      await entered.future;
      Future<WipeOutcome>? wiping;
      Map? replacement;
      if (replaceEnvelope) {
        replacement = {
          ...box.get('__pending_sync_operation') as Map,
          'requestId': 'replacement-operation'
        };
        await box.put('__pending_sync_operation', replacement);
      } else {
        wiping = repository.wipeRemote();
      }
      release.complete();
      final report = await syncing;
      if (wiping != null) expect((await wiping).ok, isTrue);
      expect(report.completed, isFalse);
      expect(requests.where((request) => request.method == 'GET'), isEmpty);
      expect(box.get('__sync_cursor__'), isNull);
      expect(box.get('remote-receive-fixture'), isNull);
      expect((box.get(note.id) as Map)['dirty'], isTrue);
      if (replaceEnvelope) {
        expect(box.get('__pending_sync_operation'), replacement);
      }
    });
  }

  test('B01 cooldown still receives remote work while a local edit waits',
      () async {
    final note = await addNote('waiting through cooldown');
    offerRemoteNote();
    push = (_) async => jsonResponse(
        {'error': 'sync_cooldown', 'retry_after_seconds': 3600},
        status: 429);
    final report = await repository.syncWithReport();
    expect(report.completed, isFalse);
    expect(repository.byId('remote-receive-fixture')!.body, 'Remote work');
    expect(repository.byId(note.id)!.dirty, isTrue);
    expect((box.get(note.id) as Map)['dirty'], isTrue);
    expect(box.get('__pending_sync_operation'), isNull);
    expect(box.get('__sync_cursor__'), 1);
    expect(repository.nextAutoSyncAt, isNotNull);
    expect(getPushes(), hasLength(1));
    expect(requests.where((request) => request.method == 'GET'), hasLength(1));
    await repository.syncWithReport();
    expect(getPushes(), hasLength(1),
        reason: 'The closed standard window skips upload');
    expect(requests.where((request) => request.method == 'GET'), hasLength(2));
    expect(repository.pendingCount, 1);
  });

  for (final sameOwner in [false, true]) {
    test(
        'B01 late insufficient Energy cannot receive into a replacement session (sameOwner=$sameOwner)',
        () async {
      final note = await addNote('old session local work');
      offerRemoteNote();
      final entered = Completer<void>();
      final release = Completer<void>();
      push = (_) async {
        entered.complete();
        await release.future;
        return jsonResponse({'error': 'insufficient_energy'}, status: 409);
      };
      final syncing = repository.syncWithReport();
      await entered.future;
      final frozen = jsonEncode(box.get('__pending_sync_operation'));
      await storage.write(
          key: 'atomic_api_session_token',
          value: 'replacement-fixture-session');
      await storage.write(
          key: 'atomic_api_user_id', value: sameOwner ? 'user-a' : 'user-b');
      await api.init();
      release.complete();
      final report = await syncing;
      expect(report.activity, SyncAttemptActivity.retired);
      expect(report.completed, isFalse);
      expect(report.operations, isEmpty);
      expect(requests.where((request) => request.method == 'GET'), isEmpty);
      expect(jsonEncode(box.get('__pending_sync_operation')), frozen);
      expect((box.get(note.id) as Map)['dirty'], isTrue);
      expect(box.get('remote-receive-fixture'), isNull);
      expect(box.get('__sync_cursor__'), isNull);
    });
  }

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
