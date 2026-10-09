import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/database/logout_plan.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  final owner = newId(), session = 'a' * 64;
  final now = DateTime.utc(2026, 10, 9).toIso8601String();
  Map<String, dynamic> row({String body = 'Public synthetic content', bool sealed = false}) => {
    'id': newId(), 'kind': 'text', 'title': sealed ? '' : 'Public note',
    'body': sealed ? '' : body, 'items': <dynamic>[], 'pinned': false, 'deleted': false,
    'created_at': now, 'updated_at': now, 'enc_v': sealed ? 1 : 0,
    'payload': sealed ? 'public-synthetic-ciphertext' : null, 'base_version': 0,
  };
  Map<String, LogoutSnapshot> snapshots(List<Map<String, dynamic>> rows) => {
    for (final r in rows) r['id'] as String: LogoutSnapshot(contentSig: 'a-12-34', updatedAt: now, conflictId: newId()),
  };
  Future<LogoutPlan> prepare(List<Map<String, dynamic>> rows) => LogoutPlan.prepare(userId: owner,
    sessionHash: session, rows: rows, snapshots: snapshots(rows));
  Future<LogoutPlan> restore(Object? raw) => LogoutPlan.restore(raw, userId: owner, sessionHash: session);
  Map<String, dynamic> copy(LogoutPlan plan) => jsonDecode(jsonEncode(plan.toMap())) as Map<String, dynamic>;

  test('51 rows split without loss, repeat IDs, or excessive envelope bytes', () async {
    final rows = List.generate(51, (_) => row());
    final plan = await prepare(rows);
    expect(plan.batches.map((b) => b.rows.length), [50, 1]);
    expect(plan.batches.map((b) => b.requestId).toSet().length, 2);
    expect(plan.batches.expand((b) => b.rows).map((r) => r['id']), rows.map((r) => r['id']));
    expect(plan.batches.every((b) => b.wireBytes <= 2500000), isTrue);
    expect((await restore(plan.toMap())).toMap(), plan.toMap());
  });

  test('UTF-8 expansion splits below 50 rows and preserves exact bytes', () async {
    final rows = List.generate(40, (_) => row(body: 'Ω' * 40000));
    final plan = await prepare(rows);
    expect(plan.batches.length, 2);
    for (final batch in plan.batches) {
      expect(batch.wireBytes, utf8.encode(jsonEncode(batch.toWire())).length);
      expect(batch.wireBytes, lessThanOrEqualTo(2500000));
    }
    expect(plan.batches.expand((b) => b.rows).length, 40);
  });

  test('overlarge single rows, sixth batches and duplicate IDs refuse whole plan', () async {
    final one = row();
    for (final rows in <List<Map<String, dynamic>>>[
      [], [row(body: 'a' * 2500000)], [one, one], List.generate(251, (_) => row()),
      List.generate(6, (_) => row(body: 'a' * 1300000)),
    ]) {
      await expectLater(prepare(rows), throwsFormatException);
    }
  });

  test('snapshot IDs must cover every note and conflict copies cannot overwrite originals', () async {
    final rows = [row(), row()];
    final valid = snapshots(rows);
    final duplicate = valid.values.first;
    for (final values in <Map<String, LogoutSnapshot>>[
      {}, {rows.first['id'] as String: valid.values.first},
      {...valid, rows.last['id'] as String: duplicate},
      {...valid, rows.first['id'] as String: LogoutSnapshot(contentSig: 'a-12-34', updatedAt: now,
        conflictId: rows.last['id'] as String)},
    ]) {
      await expectLater(LogoutPlan.prepare(userId: owner, sessionHash: session, rows: rows, snapshots: values), throwsFormatException);
    }
  });

  test('protected batches never persist plaintext alongside ciphertext', () async {
    final sealed = row(sealed: true), plan = await prepare([sealed]);
    expect(plan.toMap().toString(), isNot(contains('Public synthetic content')));
    expect((await restore(plan.toMap())).batches.single.rows.single['payload'], sealed['payload']);
    await expectLater(prepare([{...sealed, 'body': 'Public leaked plaintext'}]), throwsFormatException);
  });

  test('prepared content and snapshots are detached before asynchronous work', () async {
    final rows = [row()], values = snapshots(rows);
    final future = LogoutPlan.prepare(userId: owner, sessionHash: session, rows: rows, snapshots: values);
    rows.single['body'] = 'Public later edit'; values.clear();
    final plan = await future;
    expect(plan.batches.single.rows.single['body'], 'Public synthetic content');
    expect(plan.snapshots.length, 1);
    expect(() => plan.snapshots.clear(), throwsUnsupportedError);
  });

  test('foreign owner, newer session and damaged plan cannot become a new attempt', () async {
    final plan = await prepare([row()]);
    await expectLater(LogoutPlan.restore(plan.toMap(), userId: newId(), sessionHash: session), throwsStateError);
    await expectLater(LogoutPlan.restore(plan.toMap(), userId: owner, sessionHash: 'b' * 64), throwsStateError);
    for (final kind in ['version', 'fingerprint', 'bytes', 'payload', 'mode', 'attempt', 'snapshot']) {
      final raw = copy(plan), batch = (copy(plan)['batches'] as List).single as Map;
      raw['batches'] = [batch];
      switch (kind) {
        case 'version': raw['version'] = 2;
        case 'fingerprint': batch['fingerprint'] = '0' * 64;
        case 'bytes': batch['wireBytes'] = 1;
        case 'payload': ((batch['rows'] as List).single as Map)['body'] = 'Public damaged';
        case 'mode': batch['mode'] = 'standard';
        case 'attempt': batch['logoutAttemptId'] = newId();
        case 'snapshot': raw['snapshots'] = {};
      }
      await expectLater(restore(raw), throwsFormatException);
    }
  });

  group('actual disposable Hive persistence', () {
    late Directory directory;
    late Box box;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('atomic-logout-plan-');
      box = await Hive.openBox('notes', path: directory.path);
      await box.put('__cache_owner__', owner);
    });
    tearDown(() async {
      if (box.isOpen) await box.close();
      // Exactly the owned directory returned by createTemp, never a derived root.
      await directory.delete(recursive: true);
    });

    test('flushed ciphertext plan survives close/reopen with same envelopes and IDs', () async {
      final plan = await prepare([row(sealed: true)]);
      await box.put('untouched-note', {'body': 'Public preserved local note'});
      await LogoutPlanStore(box).save(plan);
      await box.close();
      box = await Hive.openBox('notes', path: directory.path);
      final restored = await LogoutPlanStore(box).load(userId: owner, sessionHash: session);
      expect(restored!.toMap(), plan.toMap());
      expect(box.get('untouched-note'), {'body': 'Public preserved local note'});
    });

    test('completion intent survives restart, replay and ordinary save without regression', () async {
      final plan = await prepare([row(sealed: true)]);
      var store = LogoutPlanStore(box);
      await store.save(plan);
      expect(await store.phaseOf(plan), LogoutPlanPhase.prepared);
      await expectLater(store.recordCompletionAcknowledged(plan), throwsStateError);
      await store.recordCompletionRequested(plan);
      await box.close(); box = await Hive.openBox('notes', path: directory.path);
      store = LogoutPlanStore(box);
      final restored = (await store.load(userId: owner, sessionHash: session))!;
      expect(await store.phaseOf(restored), LogoutPlanPhase.completing);
      await store.save(restored);
      expect(await store.phaseOf(restored), LogoutPlanPhase.completing);
      await store.recordCompletionAcknowledged(restored);
      await store.recordCompletionRequested(restored);
      await store.recordCompletionAcknowledged(restored);
      expect(await store.phaseOf(restored), LogoutPlanPhase.completed);
      expect(store.hasPending, isTrue);
    });

    test('markers cannot change another plan, foreign cache or malformed progress', () async {
      final plan = await prepare([row()]), other = await prepare([row()]);
      final store = LogoutPlanStore(box);
      await store.save(plan);
      await expectLater(store.recordCompletionRequested(other), throwsStateError);
      final malformed = {...plan.toMap(), 'phase': 'unknown'};
      await box.put(LogoutPlanStore.key, malformed);
      await expectLater(store.phaseOf(plan), throwsFormatException);
      await expectLater(store.recordCompletionRequested(plan), throwsFormatException);
      expect(box.get(LogoutPlanStore.key), malformed);
      await box.put(LogoutPlanStore.key, plan.toMap());
      await box.put('__cache_owner__', newId());
      await expectLater(store.recordCompletionRequested(plan), throwsStateError);
      expect(box.get(LogoutPlanStore.key), plan.toMap());
    });

    test('exact save replay is allowed and overlapping replacement is refused', () async {
      final plan = await prepare([row()]), other = await prepare([row()]);
      final store = LogoutPlanStore(box);
      final first = store.save(plan);
      final second = expectLater(store.save(other), throwsStateError);
      await first; await second; await store.save(plan);
      expect((await store.load(userId: owner, sessionHash: session))!.toMap(), plan.toMap());
    });

    test('corrupt saved state is retained and cannot be overwritten', () async {
      final store = LogoutPlanStore(box), plan = await prepare([row()]);
      await box.put(LogoutPlanStore.key, 'public-corrupt-record');
      await expectLater(store.load(userId: owner, sessionHash: session), throwsFormatException);
      await expectLater(store.save(plan), throwsFormatException);
      expect(box.get(LogoutPlanStore.key), 'public-corrupt-record');
    });

    test('foreign/newer sessions cannot read or overwrite a saved attempt', () async {
      final store = LogoutPlanStore(box), plan = await prepare([row()]);
      await store.save(plan);
      await expectLater(store.load(userId: owner, sessionHash: 'b' * 64), throwsStateError);
      await box.put('__cache_owner__', newId());
      await expectLater(store.load(userId: owner, sessionHash: session), throwsStateError);
      await expectLater(store.save(plan), throwsStateError);
      expect(box.get(LogoutPlanStore.key), plan.toMap());
    });
  });
}
