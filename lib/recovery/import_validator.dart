import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/recovery/archive_manifest.dart';
import 'package:atomic_notes/recovery/export_writer.dart';

/// Read-only access to the notes already on this device. The validator has
/// no way to write: restore (C14) is a separate, explicit step.
abstract class LocalNotesView {
  Note? byId(String id);
}

/// Why one archived note cannot be restored as it is. [message] names the
/// limit, never the note's content.
class ImportIssue {
  const ImportIssue(this.id, this.code, this.message);
  final String id;
  final String code;
  final String message;
}

/// What restoring this archive would do, before anything is written.
///
/// It holds counts, ids and issue codes only: no titles, bodies or images, so
/// showing it reveals no note content. A [locked] preview of an encrypted
/// archive holds nothing at all until the export password is given.
class ImportPreview {
  const ImportPreview._({
    required this.locked,
    required this.encrypted,
    this.createdAt,
    this.total = 0,
    this.live = 0,
    this.deleted = 0,
    this.sealed = 0,
    this.checklists = 0,
    this.images = 0,
    this.added = const [],
    this.unchanged = const [],
    this.conflicts = const [],
    this.issues = const [],
  });

  factory ImportPreview.locked() =>
      const ImportPreview._(locked: true, encrypted: true);

  final bool locked;
  final bool encrypted;
  final DateTime? createdAt;
  final int total;
  final int live;
  final int deleted;

  /// Notes kept as vault payloads. Their content is checked when the vault
  /// opens them; here only their framing, size and checksum are verified.
  final int sealed;
  final int checklists;
  final int images;

  /// Ids not on this device.
  final List<String> added;

  /// Ids whose content matches this device.
  final List<String> unchanged;

  /// Ids that exist here with different content (or, for sealed notes, whose
  /// content cannot be compared yet). Restore must ask; it never merges.
  final List<String> conflicts;
  final List<ImportIssue> issues;

  /// Restore may be offered only for a fully validated, unlocked archive.
  bool get canRestore => !locked && issues.isEmpty;
}

/// Inspects an archive without writing anything.
///
/// Every frame is authenticated (encrypted archives) and every entry's size
/// and checksum verified before its note is decoded. Each readable note is
/// then held to the same rules a save enforces: a supported format, valid
/// images within 180 KB, a title of at most 300 characters and the sync size
/// limits. One entry is held in memory at a time.
abstract final class ImportValidator {
  /// Throws [ArchiveFormatException] for a damaged, truncated, unsupported or
  /// wrongly-keyed archive. [unlock] supplies the export key for an encrypted
  /// archive; without it the result is [ImportPreview.locked].
  static Future<ImportPreview> inspect(
    ArchiveByteSource source, {
    required LocalNotesView local,
    Future<ArchiveKey> Function(ArchiveHeader header)? unlock,
  }) async {
    final reader = ArchiveReader(source);
    final header = await reader.readHeader();
    if (header.encrypted) {
      if (unlock == null) return ImportPreview.locked();
      reader.useKey(await unlock(header));
    }
    final manifest = await reader.readManifest();
    var live = 0, deleted = 0, sealed = 0, checklists = 0, images = 0;
    final added = <String>[];
    final unchanged = <String>[];
    final conflicts = <String>[];
    final issues = <ImportIssue>[];
    for (final entry in manifest.entries) {
      final archived = await reader.readEntry(entry);
      final note = archived.note;
      entry.deleted ? deleted++ : live++;
      final existing = local.byId(note.id);
      if (archived.sealed) {
        sealed++;
        _sealedIssue(archived, issues);
        // Sealed content cannot be compared until the vault opens it.
        existing == null ? added.add(note.id) : conflicts.add(note.id);
        continue;
      }
      if (note.kind == NoteKind.todo) checklists++;
      final document = NoteDocument.fromNote(note);
      images += document.imageCount;
      final error = NoteContentBudget.errorFor(note);
      if (error != null) {
        issues.add(ImportIssue(note.id, _code(note, document), error));
      }
      if (existing == null) {
        added.add(note.id);
      } else if (existing.contentSig == note.contentSig) {
        unchanged.add(note.id);
      } else {
        conflicts.add(note.id);
      }
    }
    await reader.readTrailer(manifest);
    return ImportPreview._(
      locked: false,
      encrypted: header.encrypted,
      createdAt: manifest.createdAt,
      total: manifest.entries.length,
      live: live,
      deleted: deleted,
      sealed: sealed,
      checklists: checklists,
      images: images,
      added: List.unmodifiable(added),
      unchanged: List.unmodifiable(unchanged),
      conflicts: List.unmodifiable(conflicts),
      issues: List.unmodifiable(issues),
    );
  }

  static void _sealedIssue(ArchivedNote archived, List<ImportIssue> issues) {
    // The codec already bounds the payload to the Server's sealed limit; a
    // sealed row's wire form must also fit the note wire budget.
    final row = archived.note.toRemote('')
      ..['enc_v'] = 1
      ..['payload'] = archived.payload;
    if (utf8.encode(jsonEncode(row)).length > NoteContentBudget.maxWireBytes) {
      issues.add(ImportIssue(archived.note.id, 'too_large',
          'This note exceeds the sync size limit'));
    }
  }

  static String _code(Note note, NoteDocument document) {
    if (note.title.length > 300) return 'title_too_long';
    if (document.isReadOnly) return 'unsupported_format';
    return 'too_large';
  }
}
