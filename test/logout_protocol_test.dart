import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/api/logout_protocol.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final goldens = (jsonDecode(File('test/fixtures/logout_fingerprints.json').readAsStringSync()) as List)
      .map((item) => Map<String, dynamic>.from(item as Map)).toList();
  final attemptId = goldens.first['attemptId'] as String;
  final requestId = goldens.first['requestId'] as String;
  List<Map<String, dynamic>> rowsOf(Map<String, dynamic> fixture) =>
      (fixture['rows'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
  Future<LogoutEnvelope> envelope() => LogoutEnvelope.prepare(attemptId: attemptId,
      requestId: requestId, rows: rowsOf(goldens.first));
  const storage = FlutterSecureStorage();
  setUp(() => FlutterSecureStorage.setMockInitialValues({
    'atomic_api_session_token': 'public-fixture-session',
    'atomic_api_user_id': 'public-user-a',
    'atomic_api_user_email': 'a@example.test',
  }));
  Future<ApiClient> client(Future<http.Response> Function(http.Request) handler) async {
    final transport = MockClient(handler); addTearDown(transport.close);
    final api = ApiClient.forTest(client: transport, storage: storage,
      baseUrl: Uri.parse('https://fixture.invalid/api'));
    await api.init(); return api;
  }

  for (final fixture in goldens) {
    test('logout envelope matches Server fingerprint and UTF-8 bytes: ${fixture['name']}', () async {
      final prepared = await LogoutEnvelope.prepare(attemptId: attemptId, requestId: requestId, rows: rowsOf(fixture));
      expect(prepared.fingerprint, fixture['fingerprint']);
      expect(prepared.wireBytes, fixture['wireBytes']);
      expect(prepared.toManifest().keys.toSet(), {'requestId', 'fingerprint', 'rowIds', 'wireBytes'});
      expect(prepared.rows.single.containsKey('user_id'), isFalse);
    });
  }
  test('prepared envelope cannot change through its input or nested checklist', () async {
    final input = rowsOf(goldens[1]);
    final prepared = await LogoutEnvelope.prepare(attemptId: attemptId, requestId: requestId, rows: input);
    input.single['body'] = 'Public later edit';
    expect(prepared.rows.single['body'], isNot('Public later edit'));
    expect(() => prepared.rows.single['body'] = 'Other edit', throwsUnsupportedError);
    expect(() => (prepared.rows.single['items'] as List).clear(), throwsUnsupportedError);
  });
  test('invalid duplicate and oversized envelopes are refused before transport', () async {
    final rows = rowsOf(goldens.first);
    for (final input in <List<Map<String, dynamic>>>[[], [rows.single, rows.single],
      [{...rows.single, 'body': 'a' * 2500000}], [{...rows.single, 'base_version': -1}]]) {
      await expectLater(LogoutEnvelope.prepare(attemptId: attemptId, requestId: requestId, rows: input), throwsFormatException);
    }
  });
  test('admission requires matching identity count funding and explicit price', () {
    final value = {'attemptId': attemptId, 'batches': 1, 'funding': 'emergency', 'costPerBatch': 0};
    expect(LogoutAdmission.parse(value, attemptId, 1).funding, LogoutFunding.emergency);
    expect(LogoutAdmission.parse({...value, 'funding': 'paid', 'costPerBatch': 10}, attemptId, 1).costPerBatch, 10);
    for (final mutation in [{'attemptId': 'wrong'}, {'batches': 2}, {'funding': 'unknown'},
      {'funding': 'paid'}, {'costPerBatch': 10}, {'costPerBatch': null}]) {
      expect(() => LogoutAdmission.parse({...value, ...mutation}, attemptId, 1), throwsFormatException);
    }
  });
  test('admission sends metadata only and reports the Server funding decision', () async {
    final prepared = await envelope();
    final api = await client((request) async {
      expect(request.url.path, '/api/notes/logout-attempt');
      expect(request.headers['Authorization'], 'Bearer public-fixture-session');
      expect(jsonDecode(request.body), {'attemptId': attemptId, 'batches': [prepared.toManifest()]});
      expect(request.body.contains('Public Ω'), isFalse);
      return http.Response(jsonEncode({'attemptId': attemptId, 'batches': 1, 'funding': 'emergency', 'costPerBatch': 0}), 200);
    });
    expect((await api.beginLogoutSync(attemptId, [prepared.toManifest()])).funding, LogoutFunding.emergency);
  });
  test('logout push retains exact envelope and recoverable free failure receipts', () async {
    final prepared = await envelope();
    final api = await client((request) async {
      expect(request.url.path, '/api/notes/push'); expect(jsonDecode(request.body), prepared.toWire());
      return http.Response(jsonEncode({'error': 'note_sync_failed', 'charged': 0, 'refunded': 0,
        'results': [{'id': prepared.rows.single['id'], 'ok': false, 'error': 'note_write_failed'}]}), 502);
    });
    final result = await api.pushLogoutNotes(prepared);
    expect(result.requestId, prepared.requestId); expect(result.instant, isTrue);
    expect(result.receipt!.netCharge, 0); expect(result.results.single['ok'], isFalse);
    expect(api.isSignedIn, isTrue);
  });
  test('disabled Server preserves local session and does not fall back to a paid write', () async {
    var calls = 0;
    final api = await client((_) async { calls++; return http.Response('{"error":"logout_sync_unavailable"}', 404); });
    await expectLater(api.beginLogoutSync(attemptId, [(await envelope()).toManifest()]),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'logout_sync_unavailable')));
    expect(calls, 1); expect(api.isSignedIn, isTrue);
  });
  test('completion replay is validated but never clears local authentication itself', () async {
    var calls = 0;
    final api = await client((request) async {
      calls++; expect(request.url.path, '/api/notes/logout-attempt/complete');
      return http.Response(jsonEncode({'ok': true, 'attemptId': attemptId, 'state': 'completed'}), 200);
    });
    final revision = api.sessionRevision;
    await api.completeLogoutSync(attemptId); await api.completeLogoutSync(attemptId);
    expect(calls, 2); expect(api.isSignedIn, isTrue); expect(api.sessionRevision, revision);
  });
  test('malformed completion cannot authorize local logout', () async {
    final api = await client((_) async => http.Response(jsonEncode({'ok': true, 'attemptId': attemptId, 'state': 'prepared'}), 200));
    await expectLater(api.completeLogoutSync(attemptId), throwsFormatException);
    expect(api.isSignedIn, isTrue);
  });
  test('aborting is an authenticated distinct request with an explicit terminal result', () async {
    final api = await client((request) async {
      expect(request.url.path, '/api/notes/logout-attempt/abort');
      expect(jsonDecode(request.body), {'attemptId': attemptId});
      return http.Response(jsonEncode({'ok': true, 'attemptId': attemptId, 'state': 'aborted'}), 200);
    });
    await api.abortLogoutSync(attemptId); expect(api.isSignedIn, isTrue);
  });
  for (final sameOwner in [false, true]) {
    test('late completion cannot affect a newer session (sameOwner=$sameOwner)', () async {
      final entered = Completer<void>(), release = Completer<http.Response>();
      final api = await client((_) { entered.complete(); return release.future; });
      final outcome = expectLater(api.completeLogoutSync(attemptId),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'session_changed')));
      await entered.future;
      await storage.write(key: 'atomic_api_session_token', value: 'public-new-session');
      await storage.write(key: 'atomic_api_user_id', value: sameOwner ? 'public-user-a' : 'public-user-b');
      await api.init();
      release.complete(http.Response(jsonEncode({'ok': true, 'attemptId': attemptId, 'state': 'completed'}), 200));
      await outcome; expect(api.isSignedIn, isTrue);
      expect(await storage.read(key: 'atomic_api_session_token'), 'public-new-session');
    });
  }
}
