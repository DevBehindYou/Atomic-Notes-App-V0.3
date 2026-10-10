import 'dart:convert';

import 'logout_protocol.dart';

enum LogoutRecoveryState { prepared, completed, aborted }

/// Metadata-only inspection input. Never sends a note body, token or owner ID.
class LogoutRecoveryQuery {
  LogoutRecoveryQuery._(this.attemptId, this.previousSessionHash, this.batches);
  final String attemptId;
  final String previousSessionHash;
  final List<LogoutEnvelope> batches;
  static const maxWireBytes = 16 * 1024;
  static final _hash = RegExp(r'^[0-9a-f]{64}$');

  factory LogoutRecoveryQuery({
    required String previousSessionHash,
    required List<LogoutEnvelope> batches,
  }) {
    if (!_hash.hasMatch(previousSessionHash) ||
        batches.isEmpty ||
        batches.length > 5) {
      throw const FormatException('Invalid logout recovery query');
    }
    final frozen = List<LogoutEnvelope>.unmodifiable(batches);
    final attempt = frozen.first.attemptId;
    final ids = frozen
        .expand((batch) => batch.rows.map((row) => row['id']))
        .toList();
    if (frozen.any((batch) => batch.attemptId != attempt) ||
        frozen.map((batch) => batch.requestId).toSet().length !=
            frozen.length ||
        ids.toSet().length != ids.length) {
      throw const FormatException('Invalid logout recovery manifest');
    }
    final query = LogoutRecoveryQuery._(attempt, previousSessionHash, frozen);
    if (utf8.encode(jsonEncode(query.toWire())).length > maxWireBytes) {
      throw const FormatException('Logout recovery query exceeds size limit');
    }
    return query;
  }

  Map<String, dynamic> toWire() => {
    'attemptId': attemptId,
    'previousSessionHash': previousSessionHash,
    'batches': batches
        .map((batch) => batch.toManifest())
        .toList(growable: false),
  };
}

class LogoutRecoveryBatchSummary {
  const LogoutRecoveryBatchSummary._(
    this.requestId,
    this.charged,
    this.refunded,
    this.accepted,
    this.failed,
  );
  final String requestId;
  final int charged;
  final int refunded;
  final int accepted;
  final int failed;
}

/// Advisory snapshot only. There are deliberately no acknowledgements or
/// erasure/completion methods here. Even a completed snapshot cannot clear Hive.
class LogoutRecoveryStatus {
  LogoutRecoveryStatus._(this.attemptId, this.state, this.batches);
  final String attemptId;
  final LogoutRecoveryState state;
  final List<LogoutRecoveryBatchSummary> batches;
  static const _maxSafeInteger = 9007199254740991;
  static bool _whole(Object? value) =>
      value is int && value >= 0 && value <= _maxSafeInteger;
  static bool _keys(Map value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);

  factory LogoutRecoveryStatus.parse(Object? value, LogoutRecoveryQuery query) {
    if (value is! Map ||
        !_keys(value, {'attemptId', 'state', 'batches'}) ||
        value['attemptId'] != query.attemptId ||
        value['batches'] is! List) {
      throw const FormatException('Invalid logout recovery status');
    }
    final state = switch (value['state']) {
      'prepared' => LogoutRecoveryState.prepared,
      'completed' => LogoutRecoveryState.completed,
      'aborted' => LogoutRecoveryState.aborted,
      _ => throw const FormatException('Invalid logout recovery state'),
    };
    final raw = value['batches'] as List;
    if (raw.length != query.batches.length) {
      throw const FormatException('Incomplete logout recovery status');
    }
    final summaries = <LogoutRecoveryBatchSummary>[];
    int? cost;
    for (var i = 0; i < raw.length; i++) {
      final row = raw[i], expected = query.batches[i];
      if (row is! Map ||
          !_keys(row, {
            'requestId',
            'charged',
            'refunded',
            'accepted',
            'failed',
          }) ||
          row['requestId'] != expected.requestId ||
          ![
            'charged',
            'refunded',
            'accepted',
            'failed',
          ].every((key) => _whole(row[key]))) {
        throw const FormatException('Invalid logout recovery batch');
      }
      final charged = row['charged'] as int, refunded = row['refunded'] as int;
      final accepted = row['accepted'] as int, failed = row['failed'] as int;
      // Validate historical amounts, without deciding a price or a new debit.
      if (refunded > charged ||
          accepted > expected.rows.length ||
          failed > expected.rows.length ||
          accepted + failed != expected.rows.length ||
          (failed == 0 && refunded != 0) ||
          (state == LogoutRecoveryState.completed && failed != 0) ||
          (cost != null && cost != charged)) {
        throw const FormatException('Inconsistent logout recovery summary');
      }
      cost = charged;
      summaries.add(
        LogoutRecoveryBatchSummary._(
          expected.requestId,
          charged,
          refunded,
          accepted,
          failed,
        ),
      );
    }
    return LogoutRecoveryStatus._(
      query.attemptId,
      state,
      List.unmodifiable(summaries),
    );
  }
}

/// Detached immutable acknowledgement. Delivery does not apply it to Hive.
class LogoutRecoveryAcknowledgement {
  const LogoutRecoveryAcknowledgement._(
    this.id,
    this.ok,
    this.version,
    this.updatedAt,
    this.error,
    this.sequence,
    this.unchanged,
  );
  final String id;
  final bool ok;
  final int? version;
  final String? updatedAt;
  final String? error;
  final int? sequence;
  final bool? unchanged;
}

class LogoutRecoveryBatchReceipt {
  const LogoutRecoveryBatchReceipt._(
    this.requestId,
    this.charged,
    this.refunded,
    this.results,
  );
  final String requestId;
  final int charged;
  final int refunded;
  final List<LogoutRecoveryAcknowledgement> results;
}

/// Retained receipts are evidence to validate, never authorization to adopt a
/// plan, close an attempt, clear notes or revoke a newly authenticated session.
class LogoutRecoveryReceipts {
  LogoutRecoveryReceipts._(this.attemptId, this.state, this.batches);
  final String attemptId;
  final LogoutRecoveryState state;
  final List<LogoutRecoveryBatchReceipt> batches;
  static const maxWireBytes = 128 * 1024;
  static final _errorCode = RegExp(r'^[a-z][a-z0-9_]{0,79}$');
  static final _timestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$',
  );
  static bool _positive(Object? value) =>
      LogoutRecoveryStatus._whole(value) && (value as int) > 0;
  static bool _validTimestamp(Object? value) {
    if (value is! String || !_timestamp.hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return false;
    // DateTime parsing normalizes impossible dates; exact round-trip rejects
    // them. Current Server receipts use UTC ISO milliseconds (or whole seconds).
    final canonical = value.contains('.')
        ? value
        : value.replaceFirst('Z', '.000Z');
    return parsed.toUtc().toIso8601String() == canonical;
  }

  factory LogoutRecoveryReceipts.parse(
    Object? value,
    LogoutRecoveryQuery query,
  ) {
    if (value is! Map ||
        !LogoutRecoveryStatus._keys(value, {'attemptId', 'state', 'batches'}) ||
        value['attemptId'] != query.attemptId ||
        value['batches'] is! List ||
        (value['batches'] as List).length != query.batches.length) {
      throw const FormatException('Invalid logout recovery receipts');
    }
    final receipts = <LogoutRecoveryBatchReceipt>[];
    final summaries = <Map<String, dynamic>>[];
    final raw = value['batches'] as List;
    for (var i = 0; i < raw.length; i++) {
      final batch = raw[i], expected = query.batches[i];
      if (batch is! Map ||
          !LogoutRecoveryStatus._keys(batch, {
            'requestId',
            'charged',
            'refunded',
            'results',
          }) ||
          batch['requestId'] != expected.requestId ||
          batch['results'] is! List ||
          (batch['results'] as List).length != expected.rows.length ||
          !LogoutRecoveryStatus._whole(batch['charged']) ||
          !LogoutRecoveryStatus._whole(batch['refunded'])) {
        throw const FormatException('Invalid logout recovery batch receipt');
      }
      final ids = expected.rows.map((row) => row['id']).toSet();
      final seen = <String>{};
      final results = <LogoutRecoveryAcknowledgement>[];
      for (final row in batch['results'] as List) {
        if (row is! Map ||
            row['id'] is! String ||
            !ids.contains(row['id']) ||
            !seen.add(row['id'] as String) ||
            row['ok'] is! bool) {
          throw const FormatException('Invalid logout recovery note identity');
        }
        final ok = row['ok'] as bool;
        final required = ok
            ? {'id', 'ok', 'version', 'updated_at'}
            : {'id', 'ok', 'error'};
        final allowed = {...required, 'version', 'seq', 'unchanged'};
        if (!required.every(row.containsKey) ||
            !row.keys.every(allowed.contains) ||
            (row.containsKey('version') && !_positive(row['version'])) ||
            (row.containsKey('seq') && !_positive(row['seq'])) ||
            (row.containsKey('unchanged') && row['unchanged'] is! bool)) {
          throw const FormatException(
            'Invalid logout recovery acknowledgement',
          );
        }
        if (ok) {
          final updated = row['updated_at'];
          if (!_validTimestamp(updated)) {
            throw const FormatException(
              'Invalid logout recovery acknowledgement time',
            );
          }
        } else {
          final error = row['error'];
          if (error is! String || !_errorCode.hasMatch(error)) {
            throw const FormatException('Invalid logout recovery failure code');
          }
        }
        results.add(
          LogoutRecoveryAcknowledgement._(
            row['id'] as String,
            ok,
            row['version'] as int?,
            row['updated_at'] as String?,
            row['error'] as String?,
            row['seq'] as int?,
            row['unchanged'] as bool?,
          ),
        );
      }
      final charged = batch['charged'] as int,
          refunded = batch['refunded'] as int;
      final accepted = results.where((row) => row.ok).length;
      summaries.add({
        'requestId': expected.requestId,
        'charged': charged,
        'refunded': refunded,
        'accepted': accepted,
        'failed': results.length - accepted,
      });
      receipts.add(
        LogoutRecoveryBatchReceipt._(
          expected.requestId,
          charged,
          refunded,
          List.unmodifiable(results),
        ),
      );
    }
    // Reuse state/count/billing invariants of the advisory summary contract.
    final summary = LogoutRecoveryStatus.parse({
      'attemptId': value['attemptId'],
      'state': value['state'],
      'batches': summaries,
    }, query);
    return LogoutRecoveryReceipts._(
      summary.attemptId,
      summary.state,
      List.unmodifiable(receipts),
    );
  }
}
