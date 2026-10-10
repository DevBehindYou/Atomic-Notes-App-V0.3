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
      'atomic_api_session_token': 'public-current-receipt-session',
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
  Map<String, dynamic> ack() => {
    'id': batch.rows.single['id'],
    'ok': true,
    'version': 3,
    'updated_at': '2026-10-10T00:00:00.000Z',
    'seq': 5,
    'unchanged': true,
  };
  Map<String, dynamic> receipt(List<Object?> results) => {
    'requestId': batch.requestId,
    'charged': 10,
    'refunded': 0,
    'results': results,
  };
  Map<String, dynamic> reply() => {
    'attemptId': batch.attemptId,
    'state': 'completed',
    'batches': [
      receipt([ack()]),
    ],
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
    'receipt retains immutable version sequence time and unchanged metadata',
    () {
      final input = reply();
      final parsed = LogoutRecoveryReceipts.parse(input, query);
      final result = parsed.batches.single.results.single;
      (input['batches'] as List).clear();
      expect(parsed.state, LogoutRecoveryState.completed);
      expect(result.version, 3);
      expect(result.sequence, 5);
      expect(result.unchanged, isTrue);
      expect(result.updatedAt, '2026-10-10T00:00:00.000Z');
      expect(result.error, isNull);
      expect(() => parsed.batches.clear(), throwsUnsupportedError);
      expect(
        () => parsed.batches.single.results.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'partial conflict and failed receipts preserve codes and historical refunds',
    () {
      final conflict = {
        'id': batch.rows.single['id'],
        'ok': false,
        'error': 'note_conflict',
        'version': 4,
      };
      final parsed = LogoutRecoveryReceipts.parse({
        ...reply(),
        'state': 'aborted',
        'batches': [
          {
            ...receipt([conflict]),
            'refunded': 10,
          },
        ],
      }, query);
      expect(parsed.batches.single.results.single.version, 4);
      expect(parsed.batches.single.results.single.error, 'note_conflict');
      expect(parsed.batches.single.refunded, 10);
    },
  );
  test(
    'foreign duplicate missing or unknown acknowledgement fields are refused',
    () {
      for (final results in <List<Object?>>[
        [],
        [ack(), ack()],
        [null],
        [
          {...ack(), 'id': batch.attemptId},
        ],
        [
          {...ack(), 'body': 'private'},
        ],
        [
          {...ack(), 'ok': 'true'},
        ],
        [
          {...ack(), 'error': 'note_write_failed'},
        ],
      ]) {
        expect(
          () => LogoutRecoveryReceipts.parse({
            ...reply(),
            'batches': [receipt(results)],
          }, query),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'unsafe versions sequences timestamps and boolean metadata are refused',
    () {
      for (final mutation in <Map<String, dynamic>>[
        {'version': 0},
        {'version': 3.0},
        {'version': null},
        {'version': 9007199254740992},
        {'seq': -1},
        {'seq': null},
        {'seq': 1.0},
        {'unchanged': 'true'},
        {'updated_at': null},
        {'updated_at': 'broken'},
        {'updated_at': '2026-13-01T00:00:00Z'},
        {'updated_at': '2026-02-30T00:00:00Z'},
        {'updated_at': '2026-10-10T25:00:00Z'},
      ]) {
        expect(
          () => LogoutRecoveryReceipts.parse({
            ...reply(),
            'batches': [
              receipt([
                {...ack(), ...mutation},
              ]),
            ],
          }, query),
          throwsFormatException,
        );
      }
      final minimal = {
        'id': batch.rows.single['id'],
        'ok': true,
        'version': 1,
        'updated_at': '2026-10-10T00:00:00Z',
      };
      expect(
        LogoutRecoveryReceipts.parse({
          ...reply(),
          'batches': [
            receipt([minimal]),
          ],
        }, query).batches.single.results.single.sequence,
        isNull,
      );
    },
  );
  test(
    'billing state and fixed error strings are validated before returning receipts',
    () {
      final failed = {
        'id': batch.rows.single['id'],
        'ok': false,
        'error': 'note_write_failed',
      };
      for (final mutation in <Map<String, dynamic>>[
        {'state': 'unknown'},
        {'attemptId': batch.requestId},
        {'batches': []},
        {
          'batches': [
            {
              ...receipt([ack()]),
              'refunded': 1,
            },
          ],
        },
        {
          'batches': [
            {
              ...receipt([ack()]),
              'charged': -1,
            },
          ],
        },
        {
          'batches': [
            receipt([failed]),
          ],
        },
        {
          'state': 'prepared',
          'batches': [
            receipt([
              {...failed, 'error': 'private exception text'},
            ]),
          ],
        },
        {
          'state': 'prepared',
          'batches': [
            receipt([
              {...failed, 'error': 'x' * 81},
            ]),
          ],
        },
      ]) {
        expect(
          () => LogoutRecoveryReceipts.parse({...reply(), ...mutation}, query),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'receipt request is metadata-only and never changes auth or completion marker',
    () async {
      final api = await client((request) async {
        expect(request.url.path, '/api/notes/logout-attempt/recovery-receipts');
        expect(jsonDecode(request.body), query.toWire());
        expect(request.body.contains('Public Ω'), isFalse);
        return http.Response(jsonEncode(reply()), 200);
      });
      final revision = api.sessionRevision;
      expect(
        (await api.readLogoutRecoveryReceipts(
          query,
        )).batches.single.results.single.ok,
        isTrue,
      );
      expect(api.sessionRevision, revision);
      expect(api.isSignedIn, isTrue);
      expect(api.pendingLogoutCompletion, isNull);
    },
  );
  test(
    'oversized disabled and malformed receipt responses have no fallback',
    () async {
      for (final response in [
        http.Response(' ' * (LogoutRecoveryReceipts.maxWireBytes + 1), 200),
        http.Response('{}', 200),
        http.Response('{"error":"logout_sync_unavailable"}', 404),
      ]) {
        var calls = 0;
        final api = await client((_) async {
          calls++;
          return response;
        });
        await expectLater(
          api.readLogoutRecoveryReceipts(query),
          throwsA(anyOf(isA<ApiException>(), isA<FormatException>())),
        );
        expect(calls, 1);
        expect(api.isSignedIn, isTrue);
        expect(api.pendingLogoutCompletion, isNull);
      }
    },
  );
  for (final sameOwner in [false, true]) {
    test(
      'delayed receipt cannot affect a replacement session (sameOwner=$sameOwner)',
      () async {
        final entered = Completer<void>(), release = Completer<http.Response>();
        final api = await client((_) {
          entered.complete();
          return release.future;
        });
        final pending = expectLater(
          api.readLogoutRecoveryReceipts(query),
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
          value: 'public-replacement-session',
        );
        await storage.write(
          key: 'atomic_api_user_id',
          value: sameOwner ? 'public-owner' : 'public-other',
        );
        await api.init();
        release.complete(http.Response(jsonEncode(reply()), 200));
        await pending;
        expect(
          await storage.read(key: 'atomic_api_session_token'),
          'public-replacement-session',
        );
        expect(api.pendingLogoutCompletion, isNull);
      },
    );
  }
}
