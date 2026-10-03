import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  const rows = <Map<String, dynamic>>[
    {'id': 'note-a', 'base_version': 3},
  ];
  const accepted = <Map<String, dynamic>>[
    {'id': 'note-a', 'ok': true, 'version': 4, 'seq': 9},
  ];
  const rejected = <Map<String, dynamic>>[
    {'id': 'note-a', 'ok': false, 'error': 'note_write_failed'},
  ];
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'atomic_api_session_token': 'fixture-session-a',
      'atomic_api_user_id': 'user-a',
      'atomic_api_user_email': 'a@example.test',
    });
  });
  Future<ApiClient> client(Future<http.Response> Function(http.Request) handler) async {
    final transport = MockClient(handler);
    addTearDown(transport.close);
    final api = ApiClient.forTest(client: transport, storage: storage,
      baseUrl: Uri.parse('https://fixture.invalid/api'));
    await api.init();
    return api;
  }

  for (final scenario in [
    (name: 'standard', instant: false, status: 200, charged: 5, refunded: 0),
    (name: 'instant', instant: true, status: 200, charged: 10, refunded: 0),
    (name: 'partial failure', instant: true, status: 502, charged: 10, refunded: 0),
    (name: 'all-failed refund', instant: true, status: 502, charged: 10, refunded: 10),
    (name: 'zero-cost operation', instant: false, status: 200, charged: 0, refunded: 0),
  ]) {
    test('R8 preserves ${scenario.name} operation receipt and row results', () async {
      final results = scenario.status == 502 ? rejected : accepted;
      late http.Request sent;
      final api = await client((request) async {
        sent = request;
        return http.Response(jsonEncode({
          'results': results,
          if (scenario.status == 502) 'error': 'note_sync_failed',
          'charged': scenario.charged, 'refunded': scenario.refunded,
        }), scenario.status);
      });
      final dynamic reply = await api.pushNotes(rows,
        requestId: 'fixture-request', instant: scenario.instant);
      expect(reply, isNot(isA<List>()), reason: 'Do not discard operation metadata');
      expect(reply.results, results);
      expect(reply.requestId, 'fixture-request');
      expect(reply.instant, scenario.instant);
      expect(reply.receipt.charged, scenario.charged);
      expect(reply.receipt.refunded, scenario.refunded);
      expect(reply.receipt.netCharge, scenario.charged - scenario.refunded);
      expect(jsonDecode(sent.body), {'rows': rows, 'requestId': 'fixture-request',
        'mode': scenario.instant ? 'instant' : 'standard'});
      expect(sent.headers['Authorization'], 'Bearer fixture-session-a');
    });
  }

  for (final scenario in <String, Map<String, dynamic>>{
    'legacy omitted': {},
    'missing refund': {'charged': 5},
    'string charge': {'charged': '5', 'refunded': 0},
    'fractional charge': {'charged': 5.5, 'refunded': 0},
    'negative charge': {'charged': -1, 'refunded': 0},
    'negative refund': {'charged': 5, 'refunded': -1},
    'refund exceeds charge': {'charged': 5, 'refunded': 10},
  }.entries) {
    test('R8 ${scenario.key} receipt stays unknown without losing accepted rows', () async {
      final api = await client((_) async => http.Response(jsonEncode({
        'results': accepted, ...scenario.value,
      }), 200));
      final dynamic reply = await api.pushNotes(rows, requestId: 'fixture-request');
      expect(reply, isNot(isA<List>()), reason: 'Unknown cost differs from free');
      expect(reply.results, accepted);
      expect(reply.receipt, isNull);
    });
  }

  test('R8 replay retains the same historical receipt and request identity', () async {
    final sentIds = <String>[];
    final api = await client((request) async {
      sentIds.add((jsonDecode(request.body) as Map)['requestId'] as String);
      return http.Response(jsonEncode({
        'results': accepted, 'charged': 10, 'refunded': 0,
      }), 200);
    });
    final dynamic first = await api.pushNotes(rows, requestId: 'fixture-replay', instant: true);
    final dynamic replay = await api.pushNotes(rows, requestId: 'fixture-replay', instant: true);
    expect(first, isNot(isA<List>()));
    expect(replay.requestId, first.requestId);
    expect(replay.receipt.charged, first.receipt.charged);
    expect(sentIds, ['fixture-replay', 'fixture-replay']);
    // This transport test makes no claim that a replay debits the wallet again.
  });

  test('R8 old-session receipt cannot escape after same-account re-login', () async {
    final entered = Completer<void>(), response = Completer<http.Response>();
    final api = await client((_) { entered.complete(); return response.future; });
    final outcome = expectLater(api.pushNotes(rows, requestId: 'fixture-request'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'session_changed')));
    await entered.future;
    await storage.write(key: 'atomic_api_session_token', value: 'fixture-new-session');
    await api.init();
    response.complete(http.Response(jsonEncode({
      'results': accepted, 'charged': 5, 'refunded': 0,
    }), 200));
    await outcome;
    expect(api.isSignedIn, isTrue);
  });

  test('R8 ordinary HTTP failure remains an exception, not a zero-cost receipt', () async {
    final api = await client((_) async => http.Response('{"error":"busy"}', 503));
    await expectLater(api.pushNotes(rows, requestId: 'fixture-request'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'busy')));
  });
}
