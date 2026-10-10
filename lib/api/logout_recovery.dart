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
