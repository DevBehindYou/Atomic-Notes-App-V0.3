import 'package:atomic_notes/api/atomic_notes_api.dart' as legacy
    show PushReceipt, PushReply;
import 'package:atomic_notes/api/push_acknowledgement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rows = <Map<String, dynamic>>[
    {'id': 'a', 'base_version': 5},
    {'id': 'b', 'base_version': 2},
  ];
  const accepted = <String, dynamic>{
    'id': 'a',
    'ok': true,
    'version': 6,
    'updated_at': '2026-10-14T00:00:00Z',
  };
  const rejected = <String, dynamic>{
    'id': 'b',
    'ok': false,
    'error': 'future_server_failure',
  };

  PushReply decode(Object? results,
          [Map<String, dynamic> billing = const {}]) =>
      PushAcknowledgementDecoder(rows).decode(
        {'results': results, ...billing},
        requestId: 'r',
        instant: true,
      );

  test('decoder freezes submitted identities and rejects partial batches', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'a', 'base_version': 5},
      {'id': 'b', 'base_version': 2},
    ];
    final decoder = PushAcknowledgementDecoder(rows);
    rows.first['id'] = 'changed';
    rows.first['base_version'] = 99;
    rows.removeLast();

    const first = {
      'id': 'a',
      'ok': true,
      'version': 6,
      'updated_at': '2026-10-14T00:00:00Z',
    };
    const second = {'id': 'b', 'ok': false, 'error': 'note_write_failed'};
    expect(
      () => decoder.decode({
        'results': [first]
      }, requestId: 'r', instant: true),
      throwsFormatException,
    );
    final reply = decoder.decode(
      {
        'results': [first, second],
        'charged': 'unknown',
        'refunded': 0
      },
      requestId: 'r',
      instant: true,
    );
    expect(reply, isA<legacy.PushReply>());
    expect(reply.requestId, 'r');
    expect(reply.instant, isTrue);
    expect(reply.receipt, isNull);
    expect(reply.results, [first, second]);
    expect(() => reply.results.add({}), throwsUnsupportedError);
    expect(() => reply.results.first['version'] = 7, throwsUnsupportedError);
  });

  test('legacy API export keeps PushReceipt constructor and net charge', () {
    const receipt = legacy.PushReceipt(charged: 10, refunded: 3);
    expect(receipt.netCharge, 7);
  });

  test('submitted identity preflight rejects malformed or duplicate rows', () {
    for (final row in <Map<String, dynamic>>[
      {'base_version': 0},
      {'id': '', 'base_version': 0},
      {'id': 1, 'base_version': 0},
      {'id': 'a'},
      {'id': 'a', 'base_version': -1},
      {'id': 'a', 'base_version': 1.5},
      {'id': 'a', 'base_version': '1'},
      {'id': 'a', 'base_version': true},
    ]) {
      expect(() => PushAcknowledgementDecoder([row]), throwsFormatException,
          reason: '$row');
    }
    expect(() => PushAcknowledgementDecoder([rows.first, rows.first]),
        throwsFormatException);
  });

  test('complete coverage rejects duplicates, foreign IDs and non-map rows',
      () {
    for (final results in <Object?>[
      null,
      {},
      [],
      [accepted],
      [accepted, rejected, rejected],
      [accepted, accepted],
      [
        accepted,
        {...rejected, 'id': 'foreign'}
      ],
      [accepted, 42],
      [
        accepted,
        {1: 'non-string key'}
      ],
    ]) {
      expect(() => decode(results), throwsFormatException, reason: '$results');
    }
    expect(decode([rejected, accepted]).results, [rejected, accepted]);
  });

  test('metadata and success validation retain strict wire types', () {
    for (final change in <Map<String, dynamic>>[
      {'ok': 1},
      {'ok': null},
      {'seq': 0},
      {'seq': -1},
      {'seq': 1.5},
      {'seq': null},
      {'unchanged': 1},
      {'unchanged': null},
      {'version': 0},
      {'version': 4},
      {'version': 5},
      {'version': 6.0},
      {'version': '6'},
      {'updated_at': null},
      {'updated_at': '2026-10-14T00:00:00'},
      {'updated_at': '2026-02-30T00:00:00Z'},
    ]) {
      expect(
          () => decode([
                {...accepted, ...change},
                rejected
              ]),
          throwsFormatException,
          reason: '$change');
    }
    final unchanged = {...accepted, 'version': 5, 'unchanged': true, 'seq': 1};
    expect(decode([unchanged, rejected]).results.first, unchanged);
    final firstWrite = PushAcknowledgementDecoder([
      {'id': 'a', 'base_version': 0},
    ]).decode({
      'results': [
        {...accepted, 'version': 1}
      ]
    }, requestId: 'new', instant: false);
    expect(firstWrite.results.single['version'], 1);
  });

  test('failure codes need content but unknown extra fields remain compatible',
      () {
    for (final error in <Object?>[null, '', ' \n ', 42, false]) {
      expect(
          () => decode([
                accepted,
                {...rejected, 'error': error}
              ]),
          throwsFormatException,
          reason: '$error');
    }
    final failure = {
      ...rejected,
      'future_detail': {'reason': 'synthetic'},
      'version': 'not success metadata',
      'updated_at': null
    };
    expect(decode([accepted, failure]).results.last, failure);
    expect(
        () => decode([
              accepted,
              {...failure, 'seq': 0}
            ]),
        throwsFormatException);
    expect(
        () => decode([
              accepted,
              {...failure, 'unchanged': 'true'}
            ]),
        throwsFormatException);
  });

  test('optional billing never discards valid notes or turns unknown into free',
      () {
    for (final billing in <Map<String, dynamic>>[
      {},
      {'charged': 5},
      {'refunded': 0},
      {'charged': null, 'refunded': 0},
      {'charged': '5', 'refunded': 0},
      {'charged': 5.0, 'refunded': 0},
      {'charged': 5, 'refunded': false},
      {'charged': -1, 'refunded': 0},
      {'charged': 5, 'refunded': -1},
      {'charged': 5, 'refunded': 6},
    ]) {
      final reply = decode([accepted, rejected], billing);
      expect(reply.receipt, isNull, reason: '$billing');
      expect(reply.results, [accepted, rejected]);
    }
    final free = decode([accepted, rejected], {'charged': 0, 'refunded': 0});
    expect(free.receipt!.netCharge, 0);
    final billed = decode([accepted, rejected], {'charged': 10, 'refunded': 3});
    expect(billed.receipt!.charged, 10);
    expect(billed.receipt!.refunded, 3);
    expect(billed.receipt!.netCharge, 7);
  });
}
