import 'package:atomic_notes/api/sync_envelope.dart';

enum LogoutFunding { paid, emergency }

class LogoutAdmission {
  const LogoutAdmission({required this.attemptId, required this.funding,
    required this.batches, required this.costPerBatch});
  final String attemptId;
  final LogoutFunding funding;
  final int batches;
  final int costPerBatch;

  factory LogoutAdmission.parse(Object? value, String attemptId, int batches) {
    if (value is! Map || value['attemptId'] != attemptId || value['batches'] != batches ||
        batches < 1 || batches > 5 || value['costPerBatch'] is! int) {
      throw const FormatException('Invalid logout admission');
    }
    final cost = value['costPerBatch'] as int;
    final funding = switch (value['funding']) {
      'paid' when cost > 0 => LogoutFunding.paid,
      'emergency' when cost == 0 => LogoutFunding.emergency,
      _ => throw const FormatException('Invalid logout funding'),
    };
    return LogoutAdmission(attemptId: attemptId, funding: funding,
      batches: batches, costPerBatch: cost);
  }
}

/// Immutable request prepared before admission. Only its manifest goes to the
/// attempt record; plaintext or sealed note content travels through /notes/push.
class LogoutEnvelope {
  LogoutEnvelope._(this.attemptId, this.requestId, this.rows, this.fingerprint, this.wireBytes);
  final String attemptId;
  final String requestId;
  final List<Map<String, dynamic>> rows;
  final String fingerprint;
  final int wireBytes;

  static Future<LogoutEnvelope> prepare({required String attemptId,
    required String requestId, required List<Map<String, dynamic>> rows}) async {
    final prepared = await SyncEnvelope.prepareLogout(attemptId: attemptId,
      requestId: requestId, rows: rows);
    return LogoutEnvelope._(attemptId, requestId, prepared.rows,
      prepared.fingerprint, prepared.wireBytes);
  }

  Map<String, dynamic> toWire() => {'rows': rows, 'requestId': requestId,
    'mode': 'instant', 'logoutAttemptId': attemptId};
  Map<String, dynamic> toManifest() => {'requestId': requestId, 'fingerprint': fingerprint,
    'rowIds': rows.map((row) => row['id']).toList(growable: false), 'wireBytes': wireBytes};
}
