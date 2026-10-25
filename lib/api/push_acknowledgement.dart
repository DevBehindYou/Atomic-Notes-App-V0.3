import 'package:atomic_notes/api/wire_timestamp.dart';

/// Historical totals for one Server operation, including on requestId replay.
/// These amounts do not indicate a new wallet debit for this HTTP attempt.
class PushReceipt {
  const PushReceipt({required this.charged, required this.refunded})
      : assert(charged >= 0),
        assert(refunded >= 0),
        assert(refunded <= charged);
  final int charged;
  final int refunded;
  int get netCharge => charged - refunded;
}

/// Note acknowledgements and optional billing metadata for the submitted batch.
/// A missing receipt means unknown cost, including with older Servers.
class PushReply {
  const PushReply(
      {required this.requestId,
      required this.instant,
      required this.results,
      this.receipt});
  final String requestId;
  final bool instant;
  final List<Map<String, dynamic>> results;
  final PushReceipt? receipt;
}

/// Validates one complete push reply against identities captured before I/O.
/// Construction validates and snapshots the submitted IDs and base versions.
class PushAcknowledgementDecoder {
  PushAcknowledgementDecoder(List<Map<String, dynamic>> rows)
      : _expected = Map<String, int>.unmodifiable(_pushExpectedVersions(rows));

  final Map<String, int> _expected;

  static Map<String, int> _pushExpectedVersions(
      List<Map<String, dynamic>> rows) {
    final expected = <String, int>{};
    for (final row in rows) {
      final id = row['id'], version = row['base_version'];
      if (id is! String ||
          id.isEmpty ||
          expected.containsKey(id) ||
          version is! int ||
          version < 0) {
        throw const FormatException('Invalid submitted push identities');
      }
      expected[id] = version;
    }
    return expected;
  }

  List<Map<String, dynamic>> _pushResults(Object? value) {
    if (value is! List || value.length != _expected.length) {
      throw const FormatException('Invalid push acknowledgement coverage');
    }
    final seen = <String>{}, results = <Map<String, dynamic>>[];
    for (final entry in value) {
      if (entry is! Map || !entry.keys.every((key) => key is String)) {
        throw const FormatException('Invalid push acknowledgement');
      }
      final result = Map<String, dynamic>.from(entry);
      final id = result['id'], ok = result['ok'];
      if (id is! String ||
          !_expected.containsKey(id) ||
          !seen.add(id) ||
          ok is! bool) {
        throw const FormatException('Invalid push acknowledgement identity');
      }
      final seq = result['seq'], unchanged = result['unchanged'];
      if ((result.containsKey('seq') && (seq is! int || seq <= 0)) ||
          (result.containsKey('unchanged') && unchanged is! bool)) {
        throw const FormatException('Invalid push acknowledgement metadata');
      }
      if (ok) {
        final version = result['version'];
        final base = _expected[id]!;
        if (version is! int ||
            version <= 0 ||
            version < base ||
            (version == base && unchanged != true) ||
            !isServerUtcTimestamp(result['updated_at'])) {
          throw const FormatException('Invalid push success acknowledgement');
        }
      } else {
        final error = result['error'];
        if (error is! String || error.trim().isEmpty) {
          throw const FormatException('Invalid push failure acknowledgement');
        }
      }
      results.add(Map<String, dynamic>.unmodifiable(result));
    }
    // Nothing escapes until the entire batch has passed validation.
    return List<Map<String, dynamic>>.unmodifiable(results);
  }

  PushReply decode(Map data,
      {required String requestId, required bool instant}) {
    final results = _pushResults(data['results']);
    final charged = data['charged'];
    final refunded = data['refunded'];
    // Old Servers omit receipts. Malformed optional billing metadata must not
    // discard valid note acknowledgements or imply that an operation was free.
    final receipt = charged is int &&
            refunded is int &&
            charged >= 0 &&
            refunded >= 0 &&
            refunded <= charged
        ? PushReceipt(charged: charged, refunded: refunded)
        : null;
    return PushReply(
      requestId: requestId,
      instant: instant,
      results: results,
      receipt: receipt,
    );
  }
}
