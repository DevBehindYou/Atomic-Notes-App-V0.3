import 'dart:convert';

import 'package:atomic_notes/api/logout_protocol.dart';
import 'package:atomic_notes/database/note.dart' show newId;
import 'package:hive_ce/hive_ce.dart';

enum LogoutPlanPhase { prepared, completing, completed }

/// Local acknowledgement metadata; no plaintext content or session token.
class LogoutSnapshot {
  const LogoutSnapshot({required this.contentSig, required this.updatedAt,
    required this.conflictId});
  final String contentSig;
  final String updatedAt;
  final String conflictId;

  Map<String, dynamic> toMap() => {'contentSig': contentSig,
    'updatedAt': updatedAt, 'conflictId': conflictId};
}

/// A frozen, bounded attempt. The caller seals protected rows before preparing
/// it and fences writers/session changes through persistence and completion.
/// This object alone does not authorize clearing notes or ending a session.
class LogoutPlan {
  LogoutPlan._(this.userId, this.sessionHash, this.attemptId, this.batches, this.snapshots);
  final String userId;
  final String sessionHash;
  final String attemptId;
  final List<LogoutEnvelope> batches;
  final Map<String, LogoutSnapshot> snapshots;

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _hash = RegExp(r'^[0-9a-f]{64}$');
  static final _sig = RegExp(r'^[0-9a-f]+-[0-9a-f]+-[0-9a-f]+$');

  static Future<LogoutPlan> prepare({required String userId, required String sessionHash,
    required List<Map<String, dynamic>> rows, required Map<String, LogoutSnapshot> snapshots,
    String? attemptId}) async {
    final attempt = attemptId ?? newId();
    if (!_uuid.hasMatch(userId) || !_hash.hasMatch(sessionHash) || !_uuid.hasMatch(attempt) ||
        rows.isEmpty || rows.length > 250) {
      throw const FormatException('Invalid logout plan');
    }
    // Normalize and detach input before the first asynchronous fingerprint.
    // JSON round-trip intentionally rejects non-wire objects.
    final input = (jsonDecode(jsonEncode(rows)) as List)
        .map((row) => Map<String, dynamic>.from(row as Map)).toList(growable: false);
    final snapshotCopy = Map<String, LogoutSnapshot>.unmodifiable(snapshots);
    final batches = <LogoutEnvelope>[];
    var request = newId();
    var group = <Map<String, dynamic>>[];
    int overhead(String requestId) => utf8.encode(jsonEncode({'rows': <dynamic>[],
      'requestId': requestId, 'mode': 'instant', 'logoutAttemptId': attempt})).length;
    var bytes = overhead(request);
    for (final row in input) {
      final single = await LogoutEnvelope.prepare(attemptId: attempt, requestId: request, rows: [row]);
      final normalized = single.rows.single;
      if (normalized['enc_v'] == 1 && (normalized['title'] != '' || normalized['body'] != '' ||
          (normalized['items'] as List).isNotEmpty || normalized['payload'] is! String ||
          (normalized['payload'] as String).isEmpty)) {
        throw const FormatException('Protected logout content must be sealed');
      }
      final size = utf8.encode(jsonEncode(normalized)).length;
      if (group.length == 50 || (group.isNotEmpty && bytes + size + 1 > 2500000)) {
        batches.add(await LogoutEnvelope.prepare(attemptId: attempt, requestId: request, rows: group));
        if (batches.length == 5) throw const FormatException('Logout plan exceeds sync bounds');
        request = newId(); group = []; bytes = overhead(request);
      }
      bytes += size + (group.isEmpty ? 0 : 1);
      group.add(normalized);
    }
    batches.add(await LogoutEnvelope.prepare(attemptId: attempt, requestId: request, rows: group));
    return _validated(userId, sessionHash, attempt, batches, snapshotCopy);
  }

  static LogoutPlan _validated(String owner, String session, String attempt,
      List<LogoutEnvelope> batches, Map<String, LogoutSnapshot> snapshots) {
    if (!_uuid.hasMatch(owner) || !_hash.hasMatch(session) || !_uuid.hasMatch(attempt) ||
        batches.isEmpty || batches.length > 5 ||
        batches.any((batch) => batch.attemptId != attempt) ||
        batches.map((batch) => batch.requestId).toSet().length != batches.length) {
      throw const FormatException('Invalid saved logout plan');
    }
    final ids = batches.expand((batch) => batch.rows.map((row) => row['id'] as String)).toList();
    final unique = ids.toSet();
    if (ids.length != unique.length || snapshots.length != unique.length ||
        !snapshots.keys.every(unique.contains) ||
        snapshots.values.map((snapshot) => snapshot.conflictId).toSet().length != snapshots.length) {
      throw const FormatException('Invalid logout snapshots');
    }
    for (final snapshot in snapshots.values) {
      if (!_sig.hasMatch(snapshot.contentSig) || DateTime.tryParse(snapshot.updatedAt) == null ||
          !_uuid.hasMatch(snapshot.conflictId) || unique.contains(snapshot.conflictId)) {
        throw const FormatException('Invalid logout snapshot');
      }
    }
    for (final row in batches.expand((batch) => batch.rows)) {
      if (row['enc_v'] == 1 && (row['title'] != '' || row['body'] != '' ||
          (row['items'] as List).isNotEmpty || row['payload'] is! String || (row['payload'] as String).isEmpty)) {
        throw const FormatException('Protected logout content must be sealed');
      }
    }
    return LogoutPlan._(owner, session, attempt, List.unmodifiable(batches), Map.unmodifiable(snapshots));
  }

  Map<String, dynamic> toMap() => {'version': 1, 'userId': userId,
    'sessionHash': sessionHash, 'attemptId': attemptId,
    'batches': batches.map((batch) => {...batch.toWire(),
      'fingerprint': batch.fingerprint, 'wireBytes': batch.wireBytes}).toList(growable: false),
    'snapshots': snapshots.map((id, snapshot) => MapEntry(id, snapshot.toMap()))};

  /// Fail closed on corruption or another session. The caller keeps the saved
  /// attempt and note cache for reconciliation; there is no fresh-plan fallback.
  static Future<LogoutPlan> restore(Object? raw, {required String userId, required String sessionHash}) async {
    if (raw is! Map || raw['version'] != 1 || raw['batches'] is! List || raw['snapshots'] is! Map ||
        raw['attemptId'] is! String) {
      throw const FormatException('Invalid saved logout plan');
    }
    if (raw['userId'] != userId || raw['sessionHash'] != sessionHash) {
      throw StateError('Saved logout belongs to another session. Notes remain on this device.');
    }
    if (raw.containsKey('phase') && !LogoutPlanPhase.values.any((phase) => phase.name == raw['phase'])) {
      throw const FormatException('Invalid saved logout phase');
    }
    final attempt = raw['attemptId'] as String;
    final batches = <LogoutEnvelope>[];
    if ((raw['batches'] as List).length > 5) throw const FormatException('Invalid saved logout batches');
    for (final saved in raw['batches'] as List) {
      if (saved is! Map || saved['rows'] is! List || saved['requestId'] is! String ||
          saved['mode'] != 'instant' || saved['logoutAttemptId'] != attempt ||
          (saved['rows'] as List).any((row) => row is! Map)) {
        throw const FormatException('Invalid saved logout batch');
      }
      final envelope = await LogoutEnvelope.prepare(attemptId: attempt, requestId: saved['requestId'] as String,
        rows: (saved['rows'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList());
      if (envelope.fingerprint != saved['fingerprint'] || envelope.wireBytes != saved['wireBytes']) {
        throw const FormatException('Saved logout batch changed');
      }
      batches.add(envelope);
    }
    final snapshots = <String, LogoutSnapshot>{};
    for (final entry in (raw['snapshots'] as Map).entries) {
      final value = entry.value;
      if (entry.key is! String || value is! Map || value['contentSig'] is! String ||
          value['updatedAt'] is! String || value['conflictId'] is! String) {
        throw const FormatException('Invalid saved logout snapshot');
      }
      snapshots[entry.key as String] = LogoutSnapshot(contentSig: value['contentSig'] as String,
        updatedAt: value['updatedAt'] as String, conflictId: value['conflictId'] as String);
    }
    return _validated(userId, sessionHash, attempt, batches, snapshots);
  }
}

/// One caller-owned queue per repository. Only this reserved key is changed;
/// malformed/foreign data is retained. Await save + flush BEFORE any HTTP call.
class LogoutPlanStore {
  LogoutPlanStore(this.box);
  final Box box;
  static const key = '__pending_logout_attempt__';
  Future<void> _tail = Future<void>.value();
  bool get hasPending => box.containsKey(key);

  Future<LogoutPlanPhase> phaseOf(LogoutPlan plan) async {
    await _tail;
    final raw = await _matching(plan);
    return LogoutPlanPhase.values.byName(raw['phase'] as String? ?? 'prepared');
  }

  Future<Map> _matching(LogoutPlan plan) async {
    if (box.get('__cache_owner__') != plan.userId) throw StateError('Logout cache owner changed');
    final raw = box.get(key);
    final existing = await LogoutPlan.restore(raw, userId: plan.userId, sessionHash: plan.sessionHash);
    if (box.get('__cache_owner__') != plan.userId || jsonEncode(existing.toMap()) != jsonEncode(plan.toMap())) {
      throw StateError('Saved logout attempt changed');
    }
    return raw as Map;
  }

  /// Persist BEFORE completion HTTP. After restart retry completion first,
  /// since a lost response may mean the Server already revoked this session.
  Future<void> recordCompletionRequested(LogoutPlan plan) => _transition(plan, false);

  /// Caller must have validated the matching successful Server receipt. This
  /// marker is local progress only; it never authorizes deleting note data.
  Future<void> recordCompletionAcknowledged(LogoutPlan plan) => _transition(plan, true);

  /// Caller has received the matching completed Server receipt and fenced all
  /// note writers. This consumes metadata only; it never deletes note rows.
  Future<void> consumeCompleted(LogoutPlan plan) => _remove(plan, true);

  /// Caller has received the matching aborted Server receipt. Retain notes;
  /// a later explicit logout can prepare a new plan for remaining work.
  Future<void> consumeAborted(LogoutPlan plan) => _remove(plan, false);

  Future<void> _remove(LogoutPlan plan, bool completed) {
    final write = _tail.then((_) async {
      final raw = await _matching(plan);
      final phase =
          LogoutPlanPhase.values.byName(raw['phase'] as String? ?? 'prepared');
      if (completed != (phase == LogoutPlanPhase.completed)) {
        throw StateError(
            'Logout terminal receipt does not match local progress');
      }
      await box.delete(key);
      await box.flush();
    });
    _tail = write.catchError((_) {});
    return write;
  }

  Future<void> _transition(LogoutPlan plan, bool acknowledged) {
    final write = _tail.then((_) async {
      final raw = await _matching(plan);
      final phase = LogoutPlanPhase.values.byName(raw['phase'] as String? ?? 'prepared');
      if (acknowledged && phase == LogoutPlanPhase.prepared) {
        throw StateError('Completion must be requested before it is acknowledged');
      }
      if (phase == LogoutPlanPhase.completed) return;
      await box.put(key, {...plan.toMap(), 'phase': acknowledged ? 'completed' : 'completing'});
      await box.flush();
    });
    _tail = write.catchError((_) {});
    return write;
  }

  Future<LogoutPlan?> load({required String userId, required String sessionHash}) async {
    await _tail;
    if (box.get('__cache_owner__') != userId) throw StateError('Logout cache owner changed');
    if (!hasPending) return null;
    final plan = await LogoutPlan.restore(box.get(key), userId: userId, sessionHash: sessionHash);
    if (box.get('__cache_owner__') != userId) throw StateError('Logout cache owner changed');
    return plan;
  }

  Future<void> save(LogoutPlan plan) {
    final write = _tail.then((_) async {
      if (box.get('__cache_owner__') != plan.userId) throw StateError('Logout cache owner changed');
      if (hasPending) {
        final existing = await LogoutPlan.restore(box.get(key), userId: plan.userId, sessionHash: plan.sessionHash);
        if (jsonEncode(existing.toMap()) != jsonEncode(plan.toMap())) {
          throw StateError('Resolve the saved logout before preparing another attempt');
        }
      } else {
        await box.put(key, plan.toMap());
      }
      await box.flush();
    });
    _tail = write.catchError((_) {});
    return write;
  }
}
