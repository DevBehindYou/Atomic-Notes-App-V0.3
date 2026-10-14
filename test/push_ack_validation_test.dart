import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/api/logout_protocol.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  const rows = [
    {'id': 'note-a', 'base_version': 5},
  ];
  const accepted = {
    'id': 'note-a',
    'ok': true,
    'version': 6,
    'updated_at': '2026-10-14T00:00:00.000Z',
  };
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'atomic_api_session_token': 'fixture-session',
      'atomic_api_user_id': 'user-a',
    });
  });
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

  for (final value in <String, Object?>{
    'not a list': {},
    'non map entry': [42],
    'zero version': [
      {...accepted, 'version': 0},
    ],
    'equal version without unchanged': [
      {...accepted, 'version': 5},
    ],
    'string version': [
      {...accepted, 'version': '6'},
    ],
    'negative sequence': [
      {...accepted, 'seq': -1},
    ],
    'zero sequence': [
      {...accepted, 'seq': 0},
    ],
    'null sequence': [
      {...accepted, 'seq': null},
    ],
    'null unchanged': [
      {...accepted, 'unchanged': null},
    ],
    'missing timestamp': [
      {'id': 'note-a', 'ok': true, 'version': 6},
    ],
    'local timestamp': [
      {...accepted, 'updated_at': '2026-10-14T00:00:00'},
    ],
    'invalid hour': [
      {...accepted, 'updated_at': '2026-10-14T25:00:00.000Z'},
    ],
    'missing failure code': [
      {'id': 'note-a', 'ok': false},
    ],
    'whitespace failure code': [
      {'id': 'note-a', 'ok': false, 'error': '  '},
    ],
  }.entries) {
    test(
      'push validation refuses ${value.key} without clearing the session',
      () async {
        final api = await client(
          (_) async => http.Response(jsonEncode({'results': value.value}), 200),
        );
        await expectLater(
          api.pushNotes(rows, requestId: 'fixture-request'),
          throwsFormatException,
        );
        expect(api.isSignedIn, isTrue);
      },
    );
  }

  test('push identity snapshot survives caller mutation during HTTP', () async {
    final entered = Completer<void>(), response = Completer<http.Response>();
    final mutable = [
      {'id': 'note-a', 'base_version': 5},
    ];
    final api = await client((request) {
      expect((jsonDecode(request.body) as Map)['rows'], rows);
      entered.complete();
      return response.future;
    });
    final result = api.pushNotes(mutable, requestId: 'fixture-request');
    await entered.future;
    mutable.first['id'] = 'foreign';
    mutable.first['base_version'] = 100;
    response.complete(
      http.Response(
        jsonEncode({
          'results': [accepted],
        }),
        200,
      ),
    );
    final reply = await result;
    expect(reply.results, [accepted]);
    expect(() => reply.results.add(Map.from(accepted)), throwsUnsupportedError);
    expect(() => reply.results.first['version'] = 100, throwsUnsupportedError);
  });

  test('legacy whole-second UTC timestamp remains accepted', () async {
    final api = await client(
      (_) async => http.Response(
        jsonEncode({
          'results': [
            {...accepted, 'updated_at': '2026-10-14T00:00:00Z'},
          ],
        }),
        200,
      ),
    );
    expect(
      (await api.pushNotes(
        rows,
        requestId: 'fixture-request',
      )).results.single['version'],
      6,
    );
  });

  test(
    'logout shares version and sequence preflight before mandatory funding',
    () async {
      const id = '00000000-0000-4000-8000-000000000001';
      final envelope = await LogoutEnvelope.prepare(
        attemptId: '00000000-0000-4000-8000-000000000002',
        requestId: '00000000-0000-4000-8000-000000000003',
        rows: [
          {
            'id': id,
            'base_version': 5,
            'kind': 'text',
          'title': 'public fixture',
          'body': 'synthetic',
          'items': <dynamic>[],
            'pinned': false,
            'deleted': false,
            'created_at': '2026-10-14T00:00:00.000Z',
            'enc_v': 0,
          'payload': null,
          },
        ],
      );
      for (final change in [
        {'version': 4},
        {'version': 5},
        {'seq': 0},
        {'seq': 1.5},
      ]) {
        final api = await client(
          (_) async => http.Response(
            jsonEncode({
              'results': [
                {...accepted, 'id': id, ...change},
              ],
              'charged': 0,
              'refunded': 0,
            }),
            200,
          ),
        );
        await expectLater(api.pushLogoutNotes(envelope), throwsFormatException);
      }
    },
  );
}
