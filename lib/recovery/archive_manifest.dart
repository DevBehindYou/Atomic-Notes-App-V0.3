import 'dart:convert';
import 'dart:typed_data';

import 'package:atomic_notes/database/note.dart';
import 'package:cryptography/dart.dart';

/// Why an archive manifest or entry was refused. [code] is stable for callers
/// and tests; [message] is safe to show and never contains archive content.
class ArchiveFormatException implements Exception {
  const ArchiveFormatException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'ArchiveFormatException($code): $message';
}

/// Bounds checked before any entry is read, so a hostile archive cannot make
/// a reader allocate or expand without limit.
abstract final class ArchiveLimits {
  static const maxManifestBytes = 4 * 1024 * 1024;
  static const maxEntries = 5000;

  /// One portable note: the Server's 400,000-byte wire bound plus JSON margin.
  static const maxEntryBytes = 1024 * 1024;
  static const maxTotalBytes = 256 * 1024 * 1024;
}

/// Vault parameters needed to open sealed entries elsewhere. Never a key,
/// phrase, verifier or token: restoring sealed notes needs the phrase.
class ArchiveVault {
  const ArchiveVault({
    required this.encVersion,
    required this.kdfMemory,
    required this.kdfIterations,
    required this.kdfParallelism,
  });

  final int encVersion;
  final int kdfMemory;
  final int kdfIterations;
  final int kdfParallelism;

  Map<String, Object> toJson() => {
        'encVersion': encVersion,
        'kdf': {
          'memory': kdfMemory,
          'iterations': kdfIterations,
          'parallelism': kdfParallelism,
        },
      };

  static ArchiveVault parse(Object? value) {
    final map = _object(value, 'vault', const {'encVersion', 'kdf'});
    final kdf = _object(
        map['kdf'], 'vault.kdf', const {'memory', 'iterations', 'parallelism'});
    return ArchiveVault(
      encVersion: _int(map['encVersion'], 'vault.encVersion', min: 1, max: 1),
      kdfMemory: _int(kdf['memory'], 'vault.kdf.memory', min: 8, max: 1 << 22),
      kdfIterations:
          _int(kdf['iterations'], 'vault.kdf.iterations', min: 1, max: 64),
      kdfParallelism:
          _int(kdf['parallelism'], 'vault.kdf.parallelism', min: 1, max: 16),
    );
  }
}

/// One note in the archive. The content lives in a separate entry at [path],
/// which is always derived from [id], never taken from the archive.
class ArchiveEntry {
  const ArchiveEntry({
    required this.id,
    required this.kind,
    required this.deleted,
    required this.sealed,
    required this.bytes,
    required this.sha256,
    required this.updatedAt,
  });

  final String id;
  final NoteKind kind;
  final bool deleted;

  /// The entry holds the note's vault payload instead of readable content;
  /// opening it needs the account's phrase.
  final bool sealed;
  final int bytes;
  final String sha256;
  final DateTime updatedAt;

  String get path => ArchiveManifest.entryPath(id);

  Map<String, Object> toJson() => {
        'id': id,
        'path': path,
        'kind': kind.name,
        'deleted': deleted,
        'sealed': sealed,
        'bytes': bytes,
        'sha256': sha256,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  static ArchiveEntry parse(Object? value, int index) {
    final where = 'entries[$index]';
    final map = _object(value, where, const {
      'id',
      'path',
      'kind',
      'deleted',
      'sealed',
      'bytes',
      'sha256',
      'updatedAt',
    });
    final id = _string(map['id'], '$where.id', max: 36);
    if (!ArchiveManifest._uuid.hasMatch(id)) {
      throw ArchiveFormatException(
          'invalid_id', '$where has an invalid note id');
    }
    final path = _string(map['path'], '$where.path', max: 64);
    if (path != ArchiveManifest.entryPath(id)) {
      // Rejects traversal (../), absolute and backslash paths, and any entry
      // that points at another note's content.
      throw ArchiveFormatException(
          'invalid_path', '$where has an invalid path');
    }
    final kind = switch (map['kind']) {
      'text' => NoteKind.text,
      'todo' => NoteKind.todo,
      _ => throw ArchiveFormatException('malformed', '$where.kind is invalid'),
    };
    final sha = _string(map['sha256'], '$where.sha256', max: 64);
    if (!ArchiveManifest._sha256.hasMatch(sha)) {
      throw ArchiveFormatException('malformed', '$where.sha256 is invalid');
    }
    return ArchiveEntry(
      id: id,
      kind: kind,
      deleted: _bool(map['deleted'], '$where.deleted'),
      sealed: _bool(map['sealed'], '$where.sealed'),
      bytes: _int(map['bytes'], '$where.bytes',
          min: 2, max: ArchiveLimits.maxEntryBytes),
      sha256: sha,
      updatedAt: _date(map['updatedAt'], '$where.updatedAt'),
    );
  }
}

/// The versioned, bounded table of contents of a portable notes archive.
///
/// Version policy: [version] is the major format. A reader refuses any other
/// major, and any name in `requires` it does not implement. Additive, optional
/// data goes under the open `ext` object, which readers ignore; every other
/// object is closed, so unknown fields (including misplaced secrets) are
/// refused rather than carried along.
class ArchiveManifest {
  ArchiveManifest({
    required this.createdAt,
    required List<ArchiveEntry> entries,
    this.vault,
  }) : entries = List.unmodifiable(entries);

  static const format = 'atomic-notes-archive';
  static const version = 1;

  /// Mandatory features this reader implements. None exist in version 1.
  static const supportedRequirements = <String>{};

  final DateTime createdAt;
  final List<ArchiveEntry> entries;
  final ArchiveVault? vault;

  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Ids are kept exactly as the Server knows them. Paths differing only in
  /// case are refused as duplicates (see [parse]), so extraction onto a
  /// case-insensitive file system cannot merge two notes.
  static String entryPath(String id) => 'notes/$id.json';

  int get totalBytes => entries.fold(0, (sum, entry) => sum + entry.bytes);

  Map<String, Object?> toJson() => {
        'format': format,
        'version': version,
        'requires': const <String>[],
        'createdAt': createdAt.toUtc().toIso8601String(),
        'vault': vault?.toJson(),
        'entries': [for (final entry in entries) entry.toJson()],
      };

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Parses and validates a manifest without reading any entry.
  static ArchiveManifest parse(List<int> bytes) {
    if (bytes.length > ArchiveLimits.maxManifestBytes) {
      throw const ArchiveFormatException(
          'too_large', 'The archive manifest is too large');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const ArchiveFormatException(
          'malformed', 'The archive manifest is not valid JSON');
    }
    if (json is! Map) {
      throw const ArchiveFormatException(
          'malformed', 'The archive manifest is not an object');
    }
    // Version first, so a newer archive is reported as unsupported rather
    // than as malformed.
    if (json['format'] != format) {
      throw const ArchiveFormatException(
          'malformed', 'This is not an Atomic Notes archive');
    }
    if (json['version'] != version) {
      throw const ArchiveFormatException('unsupported_version',
          'This archive needs a newer version of Atomic Notes');
    }
    final requires = json['requires'];
    if (requires is! List || requires.any((r) => r is! String)) {
      throw const ArchiveFormatException(
          'malformed', 'The archive requirements are invalid');
    }
    if (requires.any((r) => !supportedRequirements.contains(r))) {
      throw const ArchiveFormatException('unsupported_version',
          'This archive needs a newer version of Atomic Notes');
    }
    final map = _object(json, 'manifest', const {
      'format',
      'version',
      'requires',
      'createdAt',
      'vault',
      'entries',
      'ext',
    });
    final rawEntries = map['entries'];
    if (rawEntries is! List) {
      throw const ArchiveFormatException(
          'malformed', 'The archive entries are invalid');
    }
    if (rawEntries.length > ArchiveLimits.maxEntries) {
      throw const ArchiveFormatException(
          'limit_exceeded', 'The archive holds too many notes');
    }
    final entries = <ArchiveEntry>[];
    final ids = <String>{};
    var total = 0;
    for (var i = 0; i < rawEntries.length; i++) {
      final entry = ArchiveEntry.parse(rawEntries[i], i);
      if (!ids.add(entry.id.toLowerCase())) {
        throw ArchiveFormatException(
            'duplicate_id', 'entries[$i] repeats a note id');
      }
      total += entry.bytes;
      if (total > ArchiveLimits.maxTotalBytes) {
        throw const ArchiveFormatException(
            'limit_exceeded', 'The archive content is too large');
      }
      entries.add(entry);
    }
    final vault =
        map['vault'] == null ? null : ArchiveVault.parse(map['vault']);
    if (vault == null && entries.any((e) => e.sealed)) {
      throw const ArchiveFormatException(
          'malformed', 'Sealed notes need the archive vault parameters');
    }
    return ArchiveManifest(
      createdAt: _date(map['createdAt'], 'createdAt'),
      entries: entries,
      vault: vault,
    );
  }
}

/// A note read back from an archive. A sealed note has empty readable fields
/// and its vault [payload], exactly as a sealed row is kept on the device.
class ArchivedNote {
  const ArchivedNote(this.note, this.payload);
  final Note note;
  final String? payload;
  bool get sealed => payload != null;
}

/// The portable form of one note: content and identity only. Device sync
/// state (dirty, serverVersion, syncedSig) and account data are never written.
abstract final class ArchiveNoteCodec {
  /// Matches the Server's sealed payload bound.
  static const maxPayloadLength = 393216;

  static const _fields = {
    'id',
    'kind',
    'title',
    'body',
    'items',
    'pinned',
    'important',
    'deleted',
    'createdAt',
    'updatedAt',
    'encV',
    'payload',
  };

  static Map<String, Object?> _portable(Note note, String? payload) => {
        'id': note.id,
        'kind': note.kind.name,
        'title': note.title,
        'body': note.body,
        'items': [for (final item in note.items) item.toMap()],
        'pinned': note.pinned,
        'important': note.important,
        'deleted': note.deleted,
        'createdAt': note.createdAt.toUtc().toIso8601String(),
        'updatedAt': note.updatedAt.toUtc().toIso8601String(),
        if (payload != null) 'encV': 1,
        if (payload != null) 'payload': payload,
      };

  /// The entry bytes and its manifest record. For a sealed device row pass
  /// its vault [sealedPayload]; [note]'s readable fields must then be empty.
  static (Uint8List, ArchiveEntry) encode(Note note, {String? sealedPayload}) {
    if (!ArchiveManifest._uuid.hasMatch(note.id)) {
      throw const ArchiveFormatException(
          'invalid_id', 'A note has an id that cannot be archived');
    }
    if (sealedPayload != null &&
        (sealedPayload.isEmpty ||
            sealedPayload.length > maxPayloadLength ||
            note.title.isNotEmpty ||
            note.body.isNotEmpty ||
            note.items.isNotEmpty)) {
      throw const ArchiveFormatException(
          'malformed', 'A sealed note must carry only its payload');
    }
    final bytes = Uint8List.fromList(
        utf8.encode(jsonEncode(_portable(note, sealedPayload))));
    if (bytes.length > ArchiveLimits.maxEntryBytes) {
      throw const ArchiveFormatException(
          'limit_exceeded', 'A note is too large to archive');
    }
    return (
      bytes,
      ArchiveEntry(
        id: note.id,
        kind: note.kind,
        deleted: note.deleted,
        sealed: sealedPayload != null,
        bytes: bytes.length,
        sha256: sha256Hex(bytes),
        updatedAt: note.updatedAt,
      ),
    );
  }

  /// Verifies [bytes] against [entry] before decoding, then checks that the
  /// note agrees with its manifest record. The result is a clean local note.
  static ArchivedNote decode(List<int> bytes, ArchiveEntry entry) {
    if (bytes.length != entry.bytes) {
      throw ArchiveFormatException(
          'invalid_size', 'Note ${entry.id} has the wrong size');
    }
    if (sha256Hex(bytes) != entry.sha256) {
      throw ArchiveFormatException(
          'invalid_checksum', 'Note ${entry.id} is damaged');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw ArchiveFormatException('malformed', 'Note ${entry.id} is damaged');
    }
    final map = _object(json, 'note ${entry.id}', _fields);
    final items = map['items'];
    if (items is! List ||
        items.any((item) =>
            item is! Map ||
            item.keys.any((k) => k != 't' && k != 'd') ||
            item['t'] is! String ||
            item['d'] is! bool)) {
      throw ArchiveFormatException(
          'malformed', 'Note ${entry.id} has invalid items');
    }
    final note = Note(
      id: _string(map['id'], 'id', max: 36),
      kind: map['kind'] == 'todo' ? NoteKind.todo : NoteKind.text,
      title: _string(map['title'], 'title', max: ArchiveLimits.maxEntryBytes),
      body: _string(map['body'], 'body', max: ArchiveLimits.maxEntryBytes),
      items: [for (final item in items) TodoItem.fromMap(item as Map)],
      pinned: _bool(map['pinned'], 'pinned'),
      important: _bool(map['important'], 'important'),
      deleted: _bool(map['deleted'], 'deleted'),
      createdAt: _date(map['createdAt'], 'createdAt'),
      updatedAt: _date(map['updatedAt'], 'updatedAt'),
    );
    String? payload;
    if (map.containsKey('payload') || map.containsKey('encV')) {
      payload = _string(map['payload'], 'payload', max: maxPayloadLength);
      if (map['encV'] != 1 ||
          payload.isEmpty ||
          note.title.isNotEmpty ||
          note.body.isNotEmpty ||
          note.items.isNotEmpty) {
        throw ArchiveFormatException(
            'malformed', 'Note ${entry.id} has an invalid sealed payload');
      }
    }
    if (map['kind'] != entry.kind.name ||
        note.id != entry.id ||
        note.deleted != entry.deleted ||
        (payload != null) != entry.sealed ||
        !note.updatedAt.isAtSameMomentAs(entry.updatedAt)) {
      throw ArchiveFormatException(
          'malformed', 'Note ${entry.id} does not match the archive');
    }
    return ArchivedNote(note, payload);
  }

  static String sha256Hex(List<int> bytes) {
    final digest = const DartSha256().hashSync(bytes).bytes;
    return [for (final b in digest) b.toRadixString(16).padLeft(2, '0')].join();
  }
}

Map<String, Object?> _object(Object? value, String where, Set<String> allowed) {
  if (value is! Map) {
    throw ArchiveFormatException('malformed', '$where is not an object');
  }
  for (final key in value.keys) {
    if (key is! String || !allowed.contains(key)) {
      throw ArchiveFormatException(
          'unknown_field', '$where has an unknown field');
    }
  }
  return value.cast<String, Object?>();
}

String _string(Object? value, String where, {required int max}) {
  if (value is! String || value.length > max) {
    throw ArchiveFormatException('malformed', '$where is invalid');
  }
  return value;
}

bool _bool(Object? value, String where) {
  if (value is! bool) {
    throw ArchiveFormatException('malformed', '$where is invalid');
  }
  return value;
}

int _int(Object? value, String where, {required int min, required int max}) {
  if (value is! int || value < min || value > max) {
    throw ArchiveFormatException('malformed', '$where is out of range');
  }
  return value;
}

DateTime _date(Object? value, String where) {
  final text = _string(value, where, max: 40);
  final parsed = DateTime.tryParse(text);
  if (parsed == null || !parsed.isUtc) {
    throw ArchiveFormatException('malformed', '$where is not a UTC time');
  }
  return parsed;
}
