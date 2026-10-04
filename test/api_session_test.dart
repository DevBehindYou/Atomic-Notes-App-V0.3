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
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'atomic_api_session_token': 'fixture-session-a',
      'atomic_api_user_id': 'user-a',
      'atomic_api_user_email': 'a@example.test',
    });
  });
  Future<ApiClient> client(Future<http.Response> Function(http.Request) handler,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final httpClient = MockClient(handler);
    addTearDown(httpClient.close);
    final api = ApiClient.forTest(client: httpClient, storage: storage,
      baseUrl: Uri.parse('https://fixture.invalid/api'), requestTimeout: timeout);
    await api.init();
    return api;
  }
  Future<void> reauthenticate(ApiClient api, {String user = 'user-b'}) async {
    await storage.write(key: 'atomic_api_session_token', value: 'fixture-new-session');
    await storage.write(key: 'atomic_api_user_id', value: user);
    await storage.write(key: 'atomic_api_user_email', value: 'new@example.test');
    await api.init();
  }

  for (final sameUser in [false, true]) {
    test('R18 old non-JSON 401 cannot clear a newer ${sameUser ? 'same-account' : 'other-account'} session', () async {
      final entered = Completer<void>(), response = Completer<http.Response>();
      final api = await client((_) { entered.complete(); return response.future; });
      final outcome = expectLater(api.energyState(), throwsA(isA<ApiException>()
        .having((e) => e.code, 'code', 'session_changed')));
      await entered.future;
      await reauthenticate(api, user: sameUser ? 'user-a' : 'user-b');
      response.complete(http.Response('<html>Expired</html>', 401));
      await outcome;
      expect(api.isSignedIn, isTrue);
      expect(api.currentUserId, sameUser ? 'user-a' : 'user-b');
      expect(await storage.read(key: 'atomic_api_session_token'), 'fixture-new-session');
    });
  }

  test('R18 old successful responses also cannot escape the transport boundary', () async {
    final entered = Completer<void>(), response = Completer<http.Response>();
    final api = await client((_) { entered.complete(); return response.future; });
    final outcome = expectLater(api.energyState(), throwsA(isA<ApiException>()
      .having((e) => e.code, 'code', 'session_changed')));
    await entered.future;
    await reauthenticate(api);
    response.complete(http.Response('{"wallet":{"coins":999}}', 200));
    await outcome;
  });

  test('R18 current non-JSON 401 clears the session and emits teardown once', () async {
    final api = await client((_) async => http.Response('<html>Expired</html>', 401));
    final ended = api.onSessionEnded.first;
    await expectLater(api.energyState(), throwsA(isA<ApiException>()
      .having((e) => e.statusCode, 'status', 401)));
    await ended;
    expect(api.isSignedIn, isFalse);
    // init drains queued secure-store writes before reading the cache.
    await api.init();
    expect(api.currentUserId, isNull);
  });

  test('missing_token remains a caller error and does not revoke a valid local session', () async {
    final api = await client((_) async => http.Response('{"error":"missing_token"}', 401));
    await expectLater(api.energyState(), throwsA(isA<ApiException>()));
    expect(api.isSignedIn, isTrue);
  });

  test('R13 a hanging ordinary request has a deadline without clearing auth', () async {
    final api = await client((_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 10));
    await expectLater(api.energyState(), throwsA(isA<TimeoutException>()));
    expect(api.isSignedIn, isTrue);
  });

  test('push preserves its request ID mode rows and recoverable per-row 502 results', () async {
    late http.Request sent;
    final api = await client((request) async {
      sent = request;
      return http.Response(jsonEncode({'error': 'note_sync_failed',
        'results': [{'id': 'note-a', 'ok': false, 'error': 'note_write_failed'}]}), 502);
    });
    final rows = <Map<String, dynamic>>[{'id': 'note-a', 'base_version': 2}];
    final result = await api.pushNotes(rows, requestId: 'fixture-request', instant: true);
    expect(sent.url.path, '/api/notes/push');
    expect(sent.headers['Authorization'], 'Bearer fixture-session-a');
    expect(jsonDecode(sent.body), {'rows': rows, 'requestId': 'fixture-request', 'mode': 'instant'});
    expect(result.results.single['error'], 'note_write_failed');
  });

  test('cooldown metadata and non-JSON size errors survive decoding', () async {
    var status = 429;
    final api = await client((_) async => status == 429
      ? http.Response('{"error":"sync_cooldown","retry_after_seconds":37}', 429)
      : http.Response('<html>too large</html>', 413));
    await expectLater(api.pushNotes([], requestId: 'fixture-request'), throwsA(isA<ApiException>()
      .having((e) => e.retryAfterSeconds, 'retry interval', 37)));
    status = 413;
    await expectLater(api.pushNotes([], requestId: 'fixture-request'), throwsA(isA<ApiException>()
      .having((e) => e.statusCode, 'status', 413)));
  });

  test('read-all transmits the same App version used by feed reads', () async {
    final paths = <Uri>[];
    final api = await client((request) async {
      paths.add(request.url);
      return http.Response('{"rows":[],"ok":true}', 200);
    });
    await api.notificationsFeed(appVersion: '2.03.5');
    await api.markAllNotificationsRead(appVersion: '2.03.5');
    expect(paths.map((u) => u.queryParameters['app_version']), ['2.03.5', '2.03.5']);
    expect(paths.last.path, '/api/notifications/read-all');
  });
}
