import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/api/logout_protocol.dart';
import 'package:atomic_notes/api/logout_recovery.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _StreamClient extends http.BaseClient {
  _StreamClient(this.response);
  final http.StreamedResponse response;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      response;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  final fixture =
      (jsonDecode(
                    File(
                      'test/fixtures/logout_fingerprints.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .first
          as Map;
  late LogoutEnvelope batch;
  late LogoutRecoveryQuery query;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'atomic_api_session_token': 'public-recovery-current-session',
      'atomic_api_user_id': 'public-owner',
    });
    batch = await LogoutEnvelope.prepare(
      attemptId: fixture['attemptId'] as String,
      requestId: fixture['requestId'] as String,
      rows: (fixture['rows'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
    );
    query = LogoutRecoveryQuery(
      previousSessionHash: 'a' * 64,
      batches: [batch],
    );
  });
  Map<String, dynamic> summary() => {
    'requestId': batch.requestId,
    'charged': 10,
    'refunded': 0,
    'accepted': 1,
    'failed': 0,
  };
  Map<String, dynamic> status() => {
    'attemptId': batch.attemptId,
    'state': 'completed',
    'batches': [summary()],
  };
  Future<ApiClient> client(
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final transport = MockClient(handler);
    addTearDown(transport.close);
    final api = ApiClient.forTest(
      client: transport,
      storage: storage,
      baseUrl: Uri.parse('https://fixture.invalid/api'),
    );
    await api.init();
    return api;
  }

  test(
    'query freezes metadata and rejects duplicate, foreign and excessive batches',
    () async {
      final input = [batch];
      final frozen = LogoutRecoveryQuery(
        previousSessionHash: 'a' * 64,
        batches: input,
      );
      input.clear();
      expect(frozen.toWire()['batches'], [batch.toManifest()]);
      expect(() => frozen.batches.clear(), throwsUnsupportedError);
      for (final invalid in <List<LogoutEnvelope>>[
        [],
        [batch, batch],
        List.filled(6, batch),
      ]) {
        expect(
          () => LogoutRecoveryQuery(
            previousSessionHash: 'a' * 64,
            batches: invalid,
          ),
          throwsFormatException,
        );
      }
      final foreign = await LogoutEnvelope.prepare(
        attemptId: batch.requestId,
        requestId: batch.attemptId,
        rows: batch.rows,
      );
      expect(
        () => LogoutRecoveryQuery(
          previousSessionHash: 'a' * 64,
          batches: [batch, foreign],
        ),
        throwsFormatException,
      );
      expect(
        () => LogoutRecoveryQuery(previousSessionHash: 'bad', batches: [batch]),
        throwsFormatException,
      );
    },
  );

  test(
    'all valid states are immutable advisory summaries, including partial failure',
    () {
      for (final state in LogoutRecoveryState.values) {
        final parsed = LogoutRecoveryStatus.parse({
          ...status(),
          'state': state.name,
        }, query);
        expect(parsed.state, state);
        expect(parsed.batches.single.accepted, 1);
        expect(() => parsed.batches.clear(), throwsUnsupportedError);
      }
      final partial = LogoutRecoveryStatus.parse({
        ...status(),
        'state': 'prepared',
        'batches': [
          {...summary(), 'accepted': 0, 'failed': 1, 'refunded': 10},
        ],
      }, query);
      expect(partial.batches.single.failed, 1);
      final free = LogoutRecoveryStatus.parse({
        ...status(),
        'batches': [
          {...summary(), 'charged': 0},
        ],
      }, query);
      expect(free.batches.single.charged, 0);
    },
  );

  test(
    'maximum five by fifty manifest fits the bounded metadata contract',
    () async {
      final maximum = <LogoutEnvelope>[];
      for (var group = 0; group < 5; group++) {
        maximum.add(
          await LogoutEnvelope.prepare(
            attemptId: batch.attemptId,
            requestId:
                '00000000-0000-4000-8000-${(group + 1000).toString().padLeft(12, '0')}',
            rows: List.generate(
              50,
              (row) => {
                ...batch.rows.single,
                'id':
                    '00000000-0000-4000-8000-${(group * 50 + row + 2000).toString().padLeft(12, '0')}',
              },
            ),
          ),
        );
      }
      final bounded = LogoutRecoveryQuery(
        previousSessionHash: 'a' * 64,
        batches: maximum,
      );
      expect(
        utf8.encode(jsonEncode(bounded.toWire())).length,
        lessThanOrEqualTo(LogoutRecoveryQuery.maxWireBytes),
      );
      final duplicate = await LogoutEnvelope.prepare(
        attemptId: batch.attemptId,
        requestId: '00000000-0000-4000-8000-000000000007',
        rows: batch.rows,
      );
      expect(
        () => LogoutRecoveryQuery(
          previousSessionHash: 'a' * 64,
          batches: [batch, duplicate],
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'malformed counts, identities, terminal state and refund cannot become evidence',
    () {
      for (final mutation in <Map<String, dynamic>>[
        {'requestId': batch.attemptId},
        {'accepted': 0},
        {'accepted': 1.0},
        {'accepted': -1},
        {'failed': 1},
        {'charged': null},
        {'charged': '10'},
        {'charged': 9007199254740992},
        {'refunded': 11},
        {'refunded': 1},
        {'extra': true},
      ]) {
        expect(
          () => LogoutRecoveryStatus.parse({
            ...status(),
            'batches': [
              {...summary(), ...mutation},
            ],
          }, query),
          throwsFormatException,
        );
      }
      for (final mutation in <Map<String, dynamic>>[
        {'attemptId': batch.requestId},
        {'state': 'unknown'},
        {'batches': []},
        {
          'batches': [summary(), summary()],
        },
        {'results': []},
        {'batches': null},
        {
          'batches': [
            {...summary(), 'accepted': 0, 'failed': 1},
          ],
        },
      ]) {
        expect(
          () => LogoutRecoveryStatus.parse({...status(), ...mutation}, query),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'manifest order and historical charge must agree across multiple batches',
    () async {
      final second = await LogoutEnvelope.prepare(
        attemptId: batch.attemptId,
        requestId: '00000000-0000-4000-8000-000000000005',
        rows: [
          {...batch.rows.single, 'id': '00000000-0000-4000-8000-000000000006'},
        ],
      );
      final two = LogoutRecoveryQuery(
        previousSessionHash: 'a' * 64,
        batches: [batch, second],
      );
      final other = {...summary(), 'requestId': second.requestId};
      expect(
        LogoutRecoveryStatus.parse({
          ...status(),
          'batches': [summary(), other],
        }, two).batches.length,
        2,
      );
      for (final rows in [
        [other, summary()],
        [
          summary(),
          {...other, 'charged': 0},
        ],
      ]) {
        expect(
          () => LogoutRecoveryStatus.parse({...status(), 'batches': rows}, two),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'inspection sends no contents or owner and changes no local authentication',
    () async {
      var calls = 0;
      final api = await client((request) async {
        calls++;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/notes/logout-attempt/recovery-status');
        expect(
          request.headers['Authorization'],
          'Bearer public-recovery-current-session',
        );
        expect(jsonDecode(request.body), query.toWire());
        expect(request.body.contains('Public Ω'), isFalse);
        expect(request.body.contains('public-owner'), isFalse);
        return http.Response(jsonEncode(status()), 200);
      });
      final revision = api.sessionRevision;
      expect(
        (await api.inspectLogoutRecovery(query)).state,
        LogoutRecoveryState.completed,
      );
      expect(calls, 1);
      expect(api.sessionRevision, revision);
      expect(api.pendingLogoutCompletion, isNull);
      expect(
        await storage.read(key: 'atomic_api_session_token'),
        'public-recovery-current-session',
      );
    },
  );

  test(
    'disabled, ambiguous and malformed replies have no fallback request',
    () async {
      for (final response in [
        http.Response('{"error":"logout_sync_unavailable"}', 404),
        http.Response('{"error":"logout_recovery_receipt_missing"}', 409),
        http.Response('{}', 200),
        http.Response('{"state":', 200),
      ]) {
        var calls = 0;
        final api = await client((_) async {
          calls++;
          return response;
        });
        await expectLater(
          api.inspectLogoutRecovery(query),
          throwsA(anyOf(isA<ApiException>(), isA<FormatException>())),
        );
        expect(calls, 1);
        expect(api.isSignedIn, isTrue);
        expect(api.pendingLogoutCompletion, isNull);
      }
    },
  );

  test(
    'oversized and invalid UTF-8 replies are rejected before JSON interpretation',
    () async {
      for (final response in [
        http.Response(' ' * (LogoutRecoveryQuery.maxWireBytes + 1), 200),
        http.Response.bytes([0xff], 200),
      ]) {
        final api = await client((_) async => response);
        await expectLater(
          api.inspectLogoutRecovery(query),
          throwsA(
            isA<ApiException>().having(
              (error) => error.code,
              'code',
              'invalid_response',
            ),
          ),
        );
        expect(api.isSignedIn, isTrue);
        expect(api.pendingLogoutCompletion, isNull);
      }
      final padded = jsonEncode(status());
      final api = await client(
        (_) async => http.Response(
          padded +
              ' ' *
                  (LogoutRecoveryQuery.maxWireBytes -
                      utf8.encode(padded).length),
          200,
        ),
      );
      expect(
        (await api.inspectLogoutRecovery(query)).state,
        LogoutRecoveryState.completed,
      );
    },
  );

  test(
    'overflow cancels the response stream even with a false length header',
    () async {
      final cancelled = Completer<void>();
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled.complete();
        },
      );
      final transport = _StreamClient(
        http.StreamedResponse(
          stream.stream,
          200,
          headers: {'content-length': '2'},
        ),
      );
      addTearDown(transport.close);
      final api = ApiClient.forTest(
        client: transport,
        storage: storage,
        baseUrl: Uri.parse('https://fixture.invalid/api'),
      );
      await api.init();
      final pending = expectLater(
        api.inspectLogoutRecovery(query),
        throwsA(isA<ApiException>()),
      );
      stream.add(List.filled(LogoutRecoveryQuery.maxWireBytes, 32));
      stream.add([32]);
      await pending;
      await cancelled.future.timeout(const Duration(seconds: 2));
      await stream.close();
      expect(api.isSignedIn, isTrue);
    },
  );

  for (final sameOwner in [true, false]) {
    test(
      'late inspection cannot cross a replaced session (sameOwner=$sameOwner)',
      () async {
        final entered = Completer<void>(), release = Completer<http.Response>();
        final api = await client((_) {
          entered.complete();
          return release.future;
        });
        final pending = expectLater(
          api.inspectLogoutRecovery(query),
          throwsA(
            isA<ApiException>().having(
              (error) => error.code,
              'code',
              'session_changed',
            ),
          ),
        );
        await entered.future;
        await storage.write(
          key: 'atomic_api_session_token',
          value: 'public-new-session',
        );
        await storage.write(
          key: 'atomic_api_user_id',
          value: sameOwner ? 'public-owner' : 'public-other',
        );
        await api.init();
        release.complete(http.Response(jsonEncode(status()), 200));
        await pending;
        expect(api.isSignedIn, isTrue);
        expect(
          await storage.read(key: 'atomic_api_session_token'),
          'public-new-session',
        );
        expect(api.pendingLogoutCompletion, isNull);
      },
    );
  }
}
