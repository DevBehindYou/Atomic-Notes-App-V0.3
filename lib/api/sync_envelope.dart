import 'dart:convert';

import 'package:cryptography/cryptography.dart';

enum SyncEnvelopeMode { standard, instant }

/// A pure immutable projected operation. No storage, auth, crypto sealing or
/// dispatch is authorized by construction. Server-compatible insertion order
/// and frozen ciphertext are preserved; this is not a full Server validator.
class SyncEnvelope {
  const SyncEnvelope._(
    this.requestId,
    this.mode,
    this.logoutAttemptId,
    this.rows,
    this.fingerprint,
    this.wireJson,
    this.wireBytes,
  );
  final String requestId;
  final SyncEnvelopeMode mode;
  final String? logoutAttemptId;
  final List<Map<String, dynamic>> rows;
  final String fingerprint;
  final String wireJson;
  final int wireBytes;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const maxRows = 50;
  static const maxWireBytes = 2500000;

  static Future<SyncEnvelope> prepare({
    required String requestId,
    required SyncEnvelopeMode mode,
    required List<Map<String, dynamic>> rows,
  }) =>
      _prepare(requestId: requestId, mode: mode, rows: rows);

  /// Preserve the established native logout validation, errors and wire bytes.
  static Future<SyncEnvelope> prepareLogout({
    required String attemptId,
    required String requestId,
    required List<Map<String, dynamic>> rows,
  }) =>
      _prepare(
        requestId: requestId,
        mode: SyncEnvelopeMode.instant,
        rows: rows,
        logoutAttemptId: attemptId,
      );

  static Future<SyncEnvelope> _prepare({
    required String requestId,
    required SyncEnvelopeMode mode,
    required List<Map<String, dynamic>> rows,
    String? logoutAttemptId,
  }) async {
    final logout = logoutAttemptId != null;
    if ((logoutAttemptId != null && !_uuid.hasMatch(logoutAttemptId)) ||
        !_uuid.hasMatch(requestId) ||
        rows.isEmpty ||
        rows.length > maxRows) {
      throw FormatException(
        logout ? 'Invalid logout batch' : 'Invalid sync batch',
      );
    }
    // The new ordinary envelope cannot encode numbers that Node/JavaScript
    // would normalize differently. Keep historical logout acceptance unchanged.
    if (!logout &&
        rows.any(
          (row) =>
              row['enc_v'] is! int ||
              (row.containsKey('base_version') &&
                  (row['base_version'] is! int ||
                      (row['base_version'] as int) > 9007199254740991)),
        )) {
      throw const FormatException('Invalid sync note');
    }
    // Deeply detach projected rows before the first asynchronous fingerprint.
    final normalized = rows
        .map(
          (row) => _normalize(
            row,
            logout ? 'Invalid logout note' : 'Invalid sync note',
            logout ? 'Invalid logout checklist' : 'Invalid sync checklist',
            logout,
          ),
        )
        .toList(growable: false);
    if (normalized.map((row) => row['id']).toSet().length != rows.length) {
      throw FormatException(
        logout ? 'Duplicate logout note' : 'Duplicate sync note',
      );
    }
    final wire = {
      'rows': normalized,
      'requestId': requestId,
      'mode': mode.name,
      if (logout) 'logoutAttemptId': logoutAttemptId,
    };
    final wireJson = jsonEncode(wire);
    final bytes = utf8.encode(wireJson).length;
    if (bytes > maxWireBytes) {
      throw FormatException(
        logout
            ? 'Logout batch exceeds sync size limit'
            : 'Sync batch exceeds sync size limit',
      );
    }
    final hash = await Sha256().hash(
      utf8.encode(jsonEncode({'rows': normalized, 'mode': mode.name})),
    );
    return SyncEnvelope._(
      requestId,
      mode,
      logoutAttemptId,
      List.unmodifiable(normalized),
      hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      wireJson,
      bytes,
    );
  }

  static Map<String, dynamic> _normalize(
    Map<String, dynamic> row,
    String noteError,
    String checklistError,
    bool legacyLogout,
  ) {
    final version = row['base_version'] ?? 0;
    if (row['id'] is! String ||
        !_uuid.hasMatch(row['id'] as String) ||
        !['text', 'todo'].contains(row['kind']) ||
        row['title'] is! String ||
        row['body'] is! String ||
        row['items'] is! List ||
        row['pinned'] is! bool ||
        (row.containsKey('important') && row['important'] is! bool) ||
        row['deleted'] is! bool ||
        row['created_at'] is! String ||
        (row.containsKey('updated_at') && row['updated_at'] is! String) ||
        ![0, 1].contains(row['enc_v']) ||
        (row['payload'] != null && row['payload'] is! String) ||
        version is! int ||
        version < 0) {
      throw FormatException(noteError);
    }
    final items = (row['items'] as List).map((item) {
      if (item is! Map) throw FormatException(checklistError);
      // Server's union chooses one complete representation. Historical native
      // logout instead falls back per field; retain that established behavior.
      final longForm = item['text'] is String && item['done'] is bool;
      final text = legacyLogout
          ? item['text'] ?? item['t']
          : longForm
              ? item['text']
              : item['t'];
      final done = legacyLogout
          ? item['done'] ?? item['d']
          : longForm
              ? item['done']
              : item['d'];
      if (text is! String || done is! bool) {
        throw FormatException(checklistError);
      }
      return Map<String, dynamic>.unmodifiable({
        'text': text,
        'done': done,
      });
    }).toList(growable: false);
    // Match the existing Server Zod projection and key ordering exactly.
    return Map<String, dynamic>.unmodifiable({
      'id': row['id'],
      'kind': row['kind'],
      'title': row['title'],
      'body': row['body'],
      'items': List.unmodifiable(items),
      'pinned': row['pinned'],
      if (row.containsKey('important')) 'important': row['important'],
      'deleted': row['deleted'],
      'created_at': row['created_at'],
      if (row.containsKey('updated_at')) 'updated_at': row['updated_at'],
      'enc_v': row['enc_v'],
      'payload': row['payload'],
      'base_version': version,
    });
  }

  Map<String, dynamic> toWire() => Map.unmodifiable({
        'rows': rows,
        'requestId': requestId,
        'mode': mode.name,
        if (logoutAttemptId != null) 'logoutAttemptId': logoutAttemptId,
      });
}
