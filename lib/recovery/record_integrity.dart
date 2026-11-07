import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';

/// Why a stored record is not a sound note. Codes are stable; none carries
/// note content.
enum IntegrityProblem {
  /// The storage key is not a note id (and not a reserved `__…` key).
  invalidKey,

  /// The value is not a record map, or has no string id.
  notARecord,

  /// The record's id differs from the key it is stored under.
  idMismatch,

  /// Another key holds the same id in different letter case.
  duplicateId,

  /// A field has the wrong type or an unknown value (kind, flags, dates).
  malformedFields,

  /// A rich document that does not parse (blocks, styles, images).
  malformedRichContent,

  /// Vault fields that contradict each other: a payload without `enc_v`, a
  /// sealed row without a payload, or sealed and readable content together.
  contradictorySealing,
}

class IntegrityFinding {
  const IntegrityFinding(this.key, this.problem);

  /// The storage key, rendered as text. Keys are note ids, never content.
  final String key;
  final IntegrityProblem problem;
}

/// The result of scanning one notes store without changing it (C19).
class IntegrityReport {
  IntegrityReport._(this.scanned, this.sound, this.findings);

  /// Non-reserved records examined.
  final int scanned;

  /// Keys whose records are sound and readable as they are.
  final List<String> sound;
  final List<IntegrityFinding> findings;

  Map<IntegrityProblem, int> get counts => {
        for (final problem in IntegrityProblem.values)
          problem: findings.where((f) => f.problem == problem).length,
      };

  bool get clean => findings.isEmpty;

  /// Keys to set aside. Each is copied, never moved or deleted: the
  /// original stays where it is until an owner-gated repair decides.
  List<String> get quarantine => {for (final f in findings) f.key}.toList();
}

/// Where a quarantined copy is preserved. It only adds; there is no delete
/// or repair operation here by design.
abstract class QuarantinePort {
  Future<void> preserve(
      String key, Object? original, List<IntegrityProblem> why);
}

/// Detects unsound note records in a raw notes store.
///
/// Read-only: it reports, and [preserveCopies] copies flagged records to a
/// [QuarantinePort]. It never deletes, rewrites, merges or "repairs" a record,
/// and sound records are reported readable exactly as stored. Wiring it to
/// the device repository waits for its owner gate (`notes_repository.dart`
/// is reserved).
abstract final class RecordIntegrity {
  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// Repository bookkeeping (`__cache_owner__`, `__sync_cursor__`, …).
  static bool isReserved(Object? key) => key is String && key.startsWith('__');

  static IntegrityReport scan(Map<Object?, Object?> store) {
    final sound = <String>[];
    final findings = <IntegrityFinding>[];
    final byLowerId = <String, List<String>>{};
    var scanned = 0;
    for (final entry in store.entries) {
      if (isReserved(entry.key)) continue;
      scanned++;
      final key = '${entry.key}';
      final problems = _problems(entry.key, entry.value);
      if (entry.key is String && _uuid.hasMatch(key)) {
        (byLowerId[key.toLowerCase()] ??= []).add(key);
      }
      if (problems.isEmpty) {
        sound.add(key);
      } else {
        for (final problem in problems) {
          findings.add(IntegrityFinding(key, problem));
        }
      }
    }
    for (final keys in byLowerId.values) {
      if (keys.length < 2) continue;
      for (final key in keys) {
        sound.remove(key);
        findings.add(IntegrityFinding(key, IntegrityProblem.duplicateId));
      }
    }
    return IntegrityReport._(
        scanned, List.unmodifiable(sound), List.unmodifiable(findings));
  }

  static List<IntegrityProblem> _problems(Object? key, Object? value) {
    if (key is! String || !_uuid.hasMatch(key)) {
      return const [IntegrityProblem.invalidKey];
    }
    if (value is! Map || value['id'] is! String) {
      return const [IntegrityProblem.notARecord];
    }
    final problems = <IntegrityProblem>[];
    if (value['id'] != key) problems.add(IntegrityProblem.idMismatch);
    if (!_fieldsSound(value)) {
      problems.add(IntegrityProblem.malformedFields);
      return problems;
    }
    final encV = value['enc_v'];
    final payload = value['payload'];
    final sealed = encV is int && encV >= 1;
    final hasReadable = (value['title'] as String? ?? '').isNotEmpty ||
        (value['body'] as String? ?? '').isNotEmpty ||
        ((value['items'] as List?) ?? const []).isNotEmpty;
    if ((encV != null && encV is! int) ||
        (sealed && (payload is! String || payload.isEmpty || hasReadable)) ||
        (!sealed && payload != null)) {
      problems.add(IntegrityProblem.contradictorySealing);
      return problems;
    }
    if (!sealed) {
      final note = Note.fromMap(value);
      if (NoteDocument.hasRichContent(note) &&
          NoteDocument.fromNote(note).isReadOnly) {
        problems.add(IntegrityProblem.malformedRichContent);
      }
    }
    return problems;
  }

  /// The loader coerces or defaults these fields; a sound record never needs
  /// that.
  static bool _fieldsSound(Map value) {
    bool optionalString(String name) =>
        !value.containsKey(name) || value[name] is String;
    bool optionalBool(String name) =>
        !value.containsKey(name) || value[name] is bool;
    bool date(String name) =>
        !value.containsKey(name) ||
        (value[name] is String &&
            DateTime.tryParse(value[name] as String) != null);
    final items = value['items'];
    return optionalString('title') &&
        optionalString('body') &&
        (!value.containsKey('kind') ||
            value['kind'] == 'text' ||
            value['kind'] == 'todo') &&
        (items == null ||
            (items is List &&
                items.every((item) =>
                    item is Map &&
                    (item['t'] ?? item['text']) is String &&
                    ((item['d'] ?? item['done']) == null ||
                        (item['d'] ?? item['done']) is bool)))) &&
        optionalBool('pinned') &&
        optionalBool('important') &&
        optionalBool('deleted') &&
        optionalBool('dirty') &&
        date('createdAt') &&
        date('updatedAt') &&
        (!value.containsKey('serverVersion') ||
            value['serverVersion'] is int) &&
        optionalString('syncedSig');
  }

  /// Copies every flagged record, as stored, to [port]. Returns the number of
  /// records copied. The source store is not modified.
  static Future<int> preserveCopies(Map<Object?, Object?> store,
      IntegrityReport report, QuarantinePort port) async {
    final byKey = <String, Object?>{
      for (final entry in store.entries) '${entry.key}': entry.value
    };
    var copied = 0;
    for (final key in report.quarantine) {
      await port.preserve(key, _deepCopy(byKey[key]), [
        for (final f in report.findings)
          if (f.key == key) f.problem
      ]);
      copied++;
    }
    return copied;
  }

  static Object? _deepCopy(Object? value) => switch (value) {
        Map() => {
            for (final entry in value.entries) entry.key: _deepCopy(entry.value)
          },
        List() => [for (final item in value) _deepCopy(item)],
        _ => value,
      };
}
