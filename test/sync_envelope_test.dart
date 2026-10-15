import 'dart:convert';

import 'package:atomic_notes/api/logout_protocol.dart';
import 'package:atomic_notes/api/sync_envelope.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/sync_envelope_vectors.dart';

Future<String> digest(String value) async => (await Sha256().hash(
  utf8.encode(value),
)).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final vectors = (jsonDecode(syncEnvelopeVectorsJson) as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList();
  List<Map<String, dynamic>> rowsOf(Map<String, dynamic> vector) =>
      (vector['rows'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
  final requestId = vectors.first['requestId'] as String;
  const attemptId = '00000000-0000-4000-8000-000000000004';
  Future<SyncEnvelope> ordinary(
    List<Map<String, dynamic>> rows, {
    String? request,
  }) => SyncEnvelope.prepare(
    requestId: request ?? requestId,
    mode: SyncEnvelopeMode.standard,
    rows: rows,
  );

  for (final vector in vectors) {
    test(vector['case'] as String, () async {
      final expected = vector['expected'] as Map;
      final mode = SyncEnvelopeMode.values.byName(vector['mode'] as String);
      final rows = rowsOf(vector);
      final prepared = vector.containsKey('attemptId')
          ? await SyncEnvelope.prepareLogout(
              attemptId: vector['attemptId'] as String,
              requestId: requestId,
              rows: rows,
            )
          : await SyncEnvelope.prepare(
              requestId: requestId,
              mode: mode,
              rows: rows,
            );
      expect(prepared.fingerprint, expected['fingerprint']);
      expect(prepared.wireBytes, expected['wireBytes']);
      expect(await digest(prepared.wireJson), expected['wireSha256']);
      expect(
        await digest(jsonEncode(prepared.rows)),
        expected['projectedSha256'],
      );
      expect(jsonEncode(prepared.toWire()), prepared.wireJson);
      expect(utf8.encode(prepared.wireJson).length, prepared.wireBytes);
      // Public synthetic wires stay in CI-private transient streams, then are
      // reparsed by the actual locked Server. Evidence retains booleans only.
      if (const bool.fromEnvironment('ATOMIC_SYNC_ENVELOPE_WIRE_PROOF')) {
        // ignore: avoid_print
        print(
          'ATOMIC_SYNC_ENVELOPE_WIRE:${jsonEncode({'case': vector['case'], 'wire': prepared.wireJson})}',
        );
      }
      if (vector.containsKey('attemptId')) {
        final logout = await LogoutEnvelope.prepare(
          attemptId: attemptId,
          requestId: requestId,
          rows: rows,
        );
        expect(jsonEncode(logout.toWire()), prepared.wireJson);
        expect(logout.fingerprint, prepared.fingerprint);
        expect(logout.wireBytes, prepared.wireBytes);
      }
    });
  }

  test(
    'C16 prepared inputs detach before async hashing and all nested output is immutable',
    () async {
      final input = rowsOf(vectors[2]);
      final items = input.single['items'] as List;
      final item = items.single as Map;
      final pending = ordinary(input);
      input.single['body'] = 'Later public edit';
      item['t'] = 'Later public task';
      items.clear();
      input.clear();
      final prepared = await pending;
      expect(
        prepared.fingerprint,
        (vectors[2]['expected'] as Map)['fingerprint'],
      );
      expect(() => prepared.rows.clear(), throwsUnsupportedError);
      expect(() => prepared.rows.single['body'] = '', throwsUnsupportedError);
      expect(
        () => (prepared.rows.single['items'] as List).clear(),
        throwsUnsupportedError,
      );
      expect(
        () => ((prepared.rows.single['items'] as List).single as Map)['text'] =
            '',
        throwsUnsupportedError,
      );
      expect(
        () => prepared.toWire()['mode'] = 'instant',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'C17 invalid identities row shapes aliases and duplicates are refused',
    () async {
      final row = rowsOf(vectors.first).single;
      for (final rows in <List<Map<String, dynamic>>>[
        [],
        [row, row],
        [
          {...row, 'id': 'invalid'},
        ],
        [
          {...row, 'kind': 'other'},
        ],
        [
          {...row, 'title': null},
        ],
        [
          {...row, 'body': 0},
        ],
        [
          {...row, 'items': null},
        ],
        [
          {...row, 'pinned': 0},
        ],
        [
          {...row, 'deleted': null},
        ],
        [
          {...row, 'created_at': 0},
        ],
        [
          {...row, 'updated_at': null},
        ],
        [
          {...row, 'payload': []},
        ],
        [
          {
            ...row,
            'items': [null],
          },
        ],
        [
          {
            ...row,
            'items': [
              {'t': 'task', 'd': 0},
            ],
          },
        ],
        [
          {
            ...row,
            'items': [
              {'text': 'mixed task', 'd': true},
            ],
          },
        ],
      ]) {
        await expectLater(ordinary(rows), throwsFormatException);
      }
      await expectLater(
        ordinary([row], request: 'invalid'),
        throwsFormatException,
      );
    },
  );

  test(
    'C18 ordinary numeric guards and safe version boundary preserve native legacy validation',
    () async {
      final row = rowsOf(vectors.first).single;
      for (final version in [null, -1, 1.5, '1', 9007199254740991 + 1]) {
        await expectLater(
          ordinary([
            {...row, 'base_version': version},
          ]),
          throwsFormatException,
        );
      }
      for (final encV in [null, -1, 2, 0.5, '0']) {
        await expectLater(
          ordinary([
            {...row, 'enc_v': encV},
          ]),
          throwsFormatException,
        );
      }
      expect(
        (await ordinary([
          {...row, 'base_version': 9007199254740991},
        ])).rows.single['base_version'],
        9007199254740991,
      );
      final legacy = await LogoutEnvelope.prepare(
        attemptId: attemptId,
        requestId: requestId,
        rows: [
          {...row, 'base_version': null, 'enc_v': 0.0},
        ],
      );
      expect(legacy.rows.single['base_version'], 0);
      expect(legacy.rows.single['enc_v'], 0.0);
      // VM distinguishes integral doubles; JavaScript uses one Number type.
      if (!identical(0, 0.0)) {
        for (final encV in [0.0, 1.0]) {
          await expectLater(
            ordinary([
              {...row, 'enc_v': encV},
            ]),
            throwsFormatException,
          );
        }
      }
      final omittedPayload = {...row}..remove('payload');
      expect((await ordinary([omittedPayload])).rows.single['payload'], isNull);
      final aliases = await LogoutEnvelope.prepare(
        attemptId: attemptId,
        requestId: requestId,
        rows: [
          {
            ...row,
            'items': [
              {
                'text': 'Long public task',
                'done': null,
                't': 'Compact public task',
                'd': true,
              },
            ],
          },
        ],
      );
      expect((aliases.rows.single['items'] as List).single, {
        'text': 'Long public task',
        'done': true,
      });
      expect(
        (await LogoutEnvelope.prepare(
          attemptId: attemptId,
          requestId: requestId,
          rows: [
            {...row, 'base_version': 9007199254740991 + 1},
          ],
        )).rows.single['base_version'],
        9007199254740991 + 1,
      );
    },
  );

  test(
    'C19 exact client row and UTF8 byte limits include envelope metadata and escaping',
    () async {
      final row = rowsOf(vectors.first).single;
      List<Map<String, dynamic>> count(int n) => List.generate(
        n,
        (i) => {
          ...row,
          'id':
              '00000000-0000-4000-8000-${(i + 10).toString().padLeft(12, '0')}',
        },
      );
      expect((await ordinary(count(50))).rows.length, 50);
      await expectLater(ordinary(count(51)), throwsFormatException);
      final empty = {...row, 'body': ''};
      final overhead = (await ordinary([empty])).wireBytes;
      final atLimit = {
        ...empty,
        'body': 'a' * (SyncEnvelope.maxWireBytes - overhead),
      };
      expect((await ordinary([atLimit])).wireBytes, SyncEnvelope.maxWireBytes);
      await expectLater(
        ordinary([
          {...atLimit, 'body': '${atLimit['body']}a'},
        ]),
        throwsFormatException,
      );
      final logoutOverhead = (await LogoutEnvelope.prepare(
        attemptId: attemptId,
        requestId: requestId,
        rows: [empty],
      )).wireBytes;
      final logoutLimit = {
        ...empty,
        'body': 'a' * (SyncEnvelope.maxWireBytes - logoutOverhead),
      };
      expect(
        (await LogoutEnvelope.prepare(
          attemptId: attemptId,
          requestId: requestId,
          rows: [logoutLimit],
        )).wireBytes,
        SyncEnvelope.maxWireBytes,
      );
      await expectLater(
        LogoutEnvelope.prepare(
          attemptId: attemptId,
          requestId: requestId,
          rows: [
            {...logoutLimit, 'body': '${logoutLimit['body']}a'},
          ],
        ),
        throwsFormatException,
      );
      await expectLater(
        ordinary([
          {...row, 'body': '"' * 1250000},
        ]),
        throwsFormatException,
      );
      await expectLater(
        ordinary([
          {...row, 'body': 'Ω' * 1250000},
        ]),
        throwsFormatException,
      );
    },
  );

  test('C20 native logout validation errors remain exact', () async {
    final row = rowsOf(vectors.first).single;
    Future<void> refuses(
      List<Map<String, dynamic>> rows,
      String message, {
      String attempt = attemptId,
      String? request,
    }) async {
      await expectLater(
        LogoutEnvelope.prepare(
          attemptId: attempt,
          requestId: request ?? requestId,
          rows: rows,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            message,
          ),
        ),
      );
    }

    await refuses([], 'Invalid logout batch');
    await refuses([row], 'Invalid logout batch', attempt: 'invalid');
    await refuses([row], 'Invalid logout batch', request: 'invalid');
    await refuses([row, row], 'Duplicate logout note');
    await refuses([
      {...row, 'base_version': -1},
    ], 'Invalid logout note');
    await refuses([
      {
        ...row,
        'items': [0],
      },
    ], 'Invalid logout checklist');
    await refuses([
      {
        ...row,
        'items': [
          {'text': 0, 'done': false},
        ],
      },
    ], 'Invalid logout checklist');
    await refuses([
      {...row, 'body': 'a' * 2500000},
    ], 'Logout batch exceeds sync size limit');
  });
}
