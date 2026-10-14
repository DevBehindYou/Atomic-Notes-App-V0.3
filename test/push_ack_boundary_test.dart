import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'notes_repository_lifecycle_test.dart' show TestVault;

const refusalCodes = [
  'later_date',
  'calendar_date',
  'fractional_version',
  'regressing_version',
  'duplicate_id',
  'missing_id',
  'foreign_id',
  'fractional_seq',
  'nonboolean_ok',
  'nonboolean_unchanged',
  'empty_error',
];
const controlCodes = [
  'valid_write',
  'legacy_billing',
  'unknown_billing',
  'unchanged',
  'mixed_failure',
  'first_delete',
  'omitted_seq',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  late Directory directory;
  late Box box;
  late ApiClient api;
  late MockClient transport;
  late NotesRepository repository;
  late String code;
  late List<String> requestBodies;
  late String pendingBeforeReply;
  late Future<http.Response> Function(http.Request) push;
  var sequence = 0;

  http.Response jsonResponse(Map<String, dynamic> value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json'},
      );

  List<Map<String, dynamic>> accepted(http.Request request) =>
      ((jsonDecode(request.body) as Map)['rows'] as List).map((value) {
        final row = value as Map;
        return <String, dynamic>{
          'id': row['id'],
          'ok': true,
          'version': (row['base_version'] as int) + 1,
          'seq': ++sequence,
          'updated_at': '2026-10-14T00:00:00.000Z',
        };
      }).toList();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-push-ack-');
    Hive.init(directory.path);
    box = await Hive.openBox('isolated-push-ack');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>(
      'isolated-push-ack-sync',
    );
    FlutterSecureStorage.setMockInitialValues({
      'atomic_api_session_token': 'fixture-push-ack-session',
      'atomic_api_user_id': 'user-a',
      'atomic_api_user_email': 'fixture@example.test',
    });
    requestBodies = [];
    sequence = 0;
    push = (request) async => jsonResponse({
      'results': accepted(request),
      'charged': 10,
      'refunded': 0,
    });
    transport = MockClient((request) async {
      expect(request.url.host, 'fixture.invalid');
      switch ((request.method, request.url.path)) {
        case ('POST', '/api/notes/push'):
          requestBodies.add(request.body);
          pendingBeforeReply = jsonEncode(box.get('__pending_sync_operation'));
          return push(request);
        case ('GET', '/api/notes/pull'):
          return jsonResponse({
            'rows': <dynamic>[],
            'nextCursor': sequence,
            'hasMore': false,
            'cursor': '2026-10-14T00:00:00.000Z',
          });
        case ('GET', '/api/energy'):
          return jsonResponse({'energy': 100, 'coins': 0});
        default:
          fail('Unexpected fixture endpoint');
      }
    });
    api = ApiClient.forTest(
      client: transport,
      storage: storage,
      baseUrl: Uri.parse('https://fixture.invalid/api'),
    );
    await api.init();
    repository = NotesRepository.forTest(
      box: box,
      api: api,
      vault: TestVault(),
      checkConnectivity: () async => [ConnectivityResult.wifi],
    );
    await repository.start();
  });

  tearDown(() async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    transport.close();
    await Hive.close();
    await storage.deleteAll();
    final resolved = await directory.resolveSymbolicLinks();
    final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
    expect(Directory(resolved).parent.path, tempRoot);
    expect(
      Directory(
        resolved,
      ).uri.pathSegments.where((part) => part.isNotEmpty).last,
      startsWith('atomic-push-ack-'),
    );
    await Directory(resolved).delete(recursive: true);
    expect(await Directory(resolved).exists(), isFalse);
    // Fixed receipt only, after owned files/transport/session fixture cleanup.
    // ignore: avoid_print
    print('atomic_push_ack_cleanup:$code');
  });

  Future<List<Note>> addPair({bool firstDelete = false}) async {
    final pair = [
      Note(
        id: newId(),
        title: 'synthetic A',
        body: 'public fixture A',
        serverVersion: firstDelete ? 0 : 5,
        deleted: firstDelete,
      ),
      Note(
        id: newId(),
        title: 'synthetic B',
        body: 'public fixture B',
        serverVersion: 5,
      ),
    ];
    for (final note in pair) {
      await repository.save(note);
    }
    return pair;
  }

  for (final scenario in refusalCodes) {
    test('push ack refusal $scenario preserves the complete batch', () async {
      code = scenario;
      final pair = await addPair();
      final beforeMemory = pair
          .map((note) => jsonEncode(note.toMap()))
          .toList();
      final beforeDisk = pair
          .map((note) => jsonEncode(box.get(note.id)))
          .toList();
      final beforeCursor = box.get('__sync_cursor__');
      push = (request) async {
        final results = accepted(request);
        final last = results.last;
        switch (scenario) {
          case 'later_date':
            last['updated_at'] = 'not-a-date';
          case 'calendar_date':
            last['updated_at'] = '2026-02-31T00:00:00.000Z';
          case 'fractional_version':
            last['version'] = 6.5;
          case 'regressing_version':
            last['version'] = 4;
          case 'duplicate_id':
            last['id'] = results.first['id'];
          case 'missing_id':
            results.removeLast();
          case 'foreign_id':
            last['id'] = 'foreign-unsent-note';
          case 'fractional_seq':
            last['seq'] = 2.5;
          case 'nonboolean_ok':
            last['ok'] = 'true';
          case 'nonboolean_unchanged':
            last['unchanged'] = 'true';
          case 'empty_error':
            results[1] = {'id': last['id'], 'ok': false, 'error': ''};
        }
        return jsonResponse({'results': results, 'charged': 10, 'refunded': 0});
      };
      final report = await repository.syncWithReport(instant: true);
      expect(report.completed, isFalse);
      expect(requestBodies, hasLength(1));
      expect(
        pair
            .map((note) => jsonEncode(repository.byId(note.id)!.toMap()))
            .toList(),
        beforeMemory,
        reason: 'No acknowledgement may mutate a partial batch',
      );
      expect(
        pair.map((note) => jsonEncode(box.get(note.id))).toList(),
        beforeDisk,
      );
      expect(pair.every((note) => repository.byId(note.id)!.dirty), isTrue);
      expect(box.get('__sync_cursor__'), beforeCursor);
      expect(
        jsonEncode(box.get('__pending_sync_operation')),
        pendingBeforeReply,
      );
      final originalBody = requestBodies.single;
      push = (request) async => jsonResponse({
        'results': accepted(request),
        'charged': 10,
        'refunded': 0,
      });
      final retry = await repository.syncWithReport(instant: true);
      expect(retry.completed, isTrue);
      expect(requestBodies, [originalBody, originalBody]);
      expect(pair.every((note) => !repository.byId(note.id)!.dirty), isTrue);
      expect(box.get('__pending_sync_operation'), isNull);
    });
  }

  for (final scenario in controlCodes) {
    test('push ack control $scenario preserves compatible results', () async {
      code = scenario;
      final pair = await addPair(firstDelete: scenario == 'first_delete');
      push = (request) async {
        final results = accepted(request);
        if (scenario == 'unchanged') {
          for (final result in results) {
            result['version'] = 5;
            result['unchanged'] = true;
            result.remove('seq');
          }
        }
        if (scenario == 'omitted_seq') {
          for (final result in results) {
            result.remove('seq');
          }
        }
        if (scenario == 'mixed_failure') {
          results[1] = {
            'id': pair[1].id,
            'ok': false,
            'error': 'note_write_failed',
          };
        }
        return jsonResponse({
          'results': results,
          if (scenario != 'legacy_billing')
            'charged': scenario == 'unknown_billing' ? '10' : 10,
          if (scenario != 'legacy_billing') 'refunded': 0,
          if (scenario == 'mixed_failure') 'error': 'note_sync_failed',
        }, scenario == 'mixed_failure' ? 502 : 200);
      };
      final report = await repository.syncWithReport(instant: true);
      expect(report.completed, scenario != 'mixed_failure');
      expect(report.operations, hasLength(1));
      expect(
        report.netCharge,
        ['legacy_billing', 'unknown_billing'].contains(scenario) ? null : 10,
      );
      expect(repository.byId(pair.first.id)!.dirty, isFalse);
      expect(
        repository.byId(pair.first.id)!.serverVersion,
        scenario == 'unchanged'
            ? 5
            : scenario == 'first_delete'
            ? 1
            : 6,
      );
      expect((box.get(pair.first.id) as Map)['dirty'], isFalse);
      expect(repository.byId(pair.last.id)!.dirty, scenario == 'mixed_failure');
      expect(
        repository.byId(pair.first.id)!.deleted,
        scenario == 'first_delete',
      );
      expect(box.get('__pending_sync_operation'), isNull);
      expect(requestBodies, hasLength(1));
    });
  }
}
