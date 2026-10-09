import 'dart:convert';

import 'package:cryptography/cryptography.dart';

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

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  static Future<LogoutEnvelope> prepare({required String attemptId,
    required String requestId, required List<Map<String, dynamic>> rows}) async {
    if (!_uuid.hasMatch(attemptId) || !_uuid.hasMatch(requestId) || rows.isEmpty || rows.length > 50) {
      throw const FormatException('Invalid logout batch');
    }
    final normalized = rows.map(_normalize).toList(growable: false);
    if (normalized.map((r) => r['id']).toSet().length != rows.length) {
      throw const FormatException('Duplicate logout note');
    }
    final bytes = utf8.encode(jsonEncode({'rows': normalized, 'requestId': requestId,
      'mode': 'instant', 'logoutAttemptId': attemptId})).length;
    if (bytes > 2500000) throw const FormatException('Logout batch exceeds sync size limit');
    final hash = await Sha256().hash(utf8.encode(jsonEncode({'rows': normalized, 'mode': 'instant'})));
    return LogoutEnvelope._(attemptId, requestId, List.unmodifiable(normalized),
      hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), bytes);
  }

  static Map<String, dynamic> _normalize(Map<String, dynamic> row) {
    final version = row['base_version'] ?? 0;
    if (row['id'] is! String || !_uuid.hasMatch(row['id'] as String) ||
        !['text', 'todo'].contains(row['kind']) || row['title'] is! String || row['body'] is! String ||
        row['items'] is! List || row['pinned'] is! bool || row['deleted'] is! bool ||
        row['created_at'] is! String || (row.containsKey('updated_at') && row['updated_at'] is! String) ||
        ![0, 1].contains(row['enc_v']) || (row['payload'] != null && row['payload'] is! String) ||
        version is! int || version < 0) {
      throw const FormatException('Invalid logout note');
    }
    final items = (row['items'] as List).map((item) {
      if (item is! Map) throw const FormatException('Invalid logout checklist');
      final text = item['text'] ?? item['t'], done = item['done'] ?? item['d'];
      if (text is! String || done is! bool) throw const FormatException('Invalid logout checklist');
      return Map<String, dynamic>.unmodifiable({'text': text, 'done': done});
    }).toList(growable: false);
    // Match the existing Server Zod projection and key ordering exactly.
    return Map<String, dynamic>.unmodifiable({
      'id': row['id'], 'kind': row['kind'], 'title': row['title'], 'body': row['body'],
      'items': List.unmodifiable(items), 'pinned': row['pinned'], 'deleted': row['deleted'],
      'created_at': row['created_at'], if (row.containsKey('updated_at')) 'updated_at': row['updated_at'],
      'enc_v': row['enc_v'], 'payload': row['payload'], 'base_version': version,
    });
  }

  Map<String, dynamic> toWire() => {'rows': rows, 'requestId': requestId,
    'mode': 'instant', 'logoutAttemptId': attemptId};
  Map<String, dynamic> toManifest() => {'requestId': requestId, 'fingerprint': fingerprint,
    'rowIds': rows.map((row) => row['id']).toList(growable: false), 'wireBytes': wireBytes};
}
