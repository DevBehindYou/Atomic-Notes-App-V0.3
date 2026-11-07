import 'dart:math';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/recovery/archive_manifest.dart';
import 'package:atomic_notes/recovery/export_writer.dart';
import 'package:atomic_notes/recovery/import_validator.dart';

/// What to do with a note that exists here with different content. There is
/// no merge choice: one whole version is kept, the other is preserved.
enum ConflictChoice { keepDevice, useArchive }

/// The durable record of a restore in progress. It is written before the
/// first change to the target, so a restart can finish or undo the restore.
class RestoreMarker {
  const RestoreMarker({
    required this.operationId,
    required this.phase,
    required this.ids,
  });

  final String operationId;
  final RestorePhase phase;

  /// The notes this restore writes, in order.
  final List<String> ids;

  Map<String, Object> toJson() =>
      {'operationId': operationId, 'phase': phase.name, 'ids': ids};

  static RestoreMarker fromJson(Map<String, Object?> json) => RestoreMarker(
        operationId: json['operationId'] as String,
        phase: RestorePhase.values.byName(json['phase'] as String),
        ids: (json['ids'] as List).cast<String>(),
      );
}

/// `staging`: copies are being prepared; the target is untouched.
/// `committing`: staged copies are being written; finish on resume.
/// `cleanup`: every copy is written; only staged data remains to discard.
enum RestorePhase { staging, committing, cleanup }

/// The isolated persistence a restore runs against. Every method is one
/// persistence boundary: a crash may happen before or after any of them.
///
/// It is a port: the native repository adapter is not part of this change
/// (`notes_repository.dart` is reserved, and activation waits for B05).
abstract class RestoreStore {
  /// The note currently in the target, as the device stores it.
  Future<Map<String, Object?>?> current(String id);

  Future<RestoreMarker?> readMarker();
  Future<void> writeMarker(RestoreMarker marker);
  Future<void> clearMarker();

  /// Staged copies live apart from the target until commit.
  Future<void> stage(
      String operationId, String id, Map<String, Object?> record);
  Future<Map<String, Object?>?> staged(String operationId, String id);
  Future<void> discardStaged(String operationId);

  /// Keeps the target's previous version of [id] before it is replaced.
  /// [previous] is null when the note did not exist here.
  Future<bool> hasBackup(String operationId, String id);
  Future<void> backup(
      String operationId, String id, Map<String, Object?>? previous);

  /// Replaces the target's record for [id].
  Future<void> put(String id, Map<String, Object?> record);
}

class RestoreRefused implements Exception {
  const RestoreRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

class RestoreResult {
  const RestoreResult(this.operationId, this.written, this.kept);
  final String operationId;

  /// Ids written from the archive. Their previous versions are kept in the
  /// store's backup for [operationId].
  final List<String> written;

  /// Conflicting ids left as they are on this device.
  final List<String> kept;
}

/// Restores a validated archive in two durable phases, with no silent merge.
///
/// 1. **Preflight**, with no writes: the archive is inspected again
///    ([ImportValidator]) and must be restorable; every conflict must have a
///    [ConflictChoice]; a restore already in progress must be finished first.
/// 2. **Staging**: a `staging` marker is written, then each planned note is
///    read from the archive again (authenticated and checksummed) and staged.
///    A failure here leaves the target untouched; [resume] discards it.
/// 3. **Commit**: the marker moves to `committing`. For each note, the
///    target's previous version is backed up once, then the staged copy is
///    written. Each step is idempotent, so [resume] simply repeats the
///    remaining commit. A `cleanup` marker then discards the staged copies
///    and the marker is cleared last. Backups are kept for the caller.
///
/// New and archive-chosen notes are written as local changes (dirty, no
/// server version), so the next sync uploads them. Unchanged notes and
/// device-chosen conflicts are not touched.
class RestoreCoordinator {
  RestoreCoordinator(this.store, {Random? random})
      : _random = random ?? Random.secure();

  final RestoreStore store;
  final Random _random;

  Future<RestoreResult> restore(
    ArchiveByteSource Function() open, {
    required LocalNotesView local,
    Map<String, ConflictChoice> choices = const {},
    ArchiveKey? key,
  }) async {
    if (await store.readMarker() != null) {
      throw const RestoreRefused(
          'An earlier restore has not finished. Finish it before starting another.');
    }
    final preview = await ImportValidator.inspect(open(),
        local: local, unlock: key == null ? null : (_) async => key);
    if (!preview.canRestore) {
      throw const RestoreRefused('This archive cannot be restored as it is.');
    }
    final missing = preview.conflicts.where((id) => !choices.containsKey(id));
    if (missing.isNotEmpty) {
      throw RestoreRefused(
          'Choose what to keep for ${missing.length} note(s) that differ.');
    }
    final kept = [
      for (final id in preview.conflicts)
        if (choices[id] == ConflictChoice.keepDevice) id
    ];
    final ids = [
      ...preview.added,
      for (final id in preview.conflicts)
        if (choices[id] == ConflictChoice.useArchive) id
    ];
    final operationId = _operationId();

    // Staging: the target is not touched.
    await store.writeMarker(RestoreMarker(
        operationId: operationId, phase: RestorePhase.staging, ids: ids));
    final wanted = ids.toSet();
    final reader = ArchiveReader(open());
    final header = await reader.readHeader();
    if (header.encrypted) reader.useKey(key!);
    final manifest = await reader.readManifest();
    for (final entry in manifest.entries) {
      final archived = await reader.readEntry(entry);
      if (wanted.contains(entry.id)) {
        await store.stage(operationId, entry.id, restoreRecord(archived));
      }
    }
    await reader.readTrailer(manifest);

    await store.writeMarker(RestoreMarker(
        operationId: operationId, phase: RestorePhase.committing, ids: ids));
    await _commit(operationId, ids);
    return RestoreResult(operationId, ids, kept);
  }

  /// Finishes or undoes a restore a crash interrupted. Returns the finished
  /// operation id, or null when nothing was pending or it was undone.
  Future<String?> resume() async {
    final marker = await store.readMarker();
    if (marker == null) return null;
    switch (marker.phase) {
      case RestorePhase.staging:
        await store.discardStaged(marker.operationId);
        await store.clearMarker();
        return null;
      case RestorePhase.committing:
        await _commit(marker.operationId, marker.ids);
      case RestorePhase.cleanup:
        await _cleanup(marker.operationId);
    }
    return marker.operationId;
  }

  Future<void> _commit(String operationId, List<String> ids) async {
    for (final id in ids) {
      final record = await store.staged(operationId, id);
      if (record == null) {
        // A committing marker is only written after every copy was staged.
        throw const RestoreRefused(
            'The restore copy is incomplete. Your notes are unchanged by it.');
      }
      if (!await store.hasBackup(operationId, id)) {
        await store.backup(operationId, id, await store.current(id));
      }
      await store.put(id, record);
    }
    await store.writeMarker(RestoreMarker(
        operationId: operationId, phase: RestorePhase.cleanup, ids: ids));
    await _cleanup(operationId);
  }

  Future<void> _cleanup(String operationId) async {
    await store.discardStaged(operationId);
    await store.clearMarker();
  }

  String _operationId() => List.generate(
      16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  /// The device record for an archived note: a local change for the next
  /// sync. A sealed note keeps its vault payload exactly as a sealed row.
  static Map<String, Object?> restoreRecord(ArchivedNote archived) {
    final note = Note.fromMap(archived.note.toMap())
      ..dirty = true
      ..serverVersion = 0
      ..syncedSig = '';
    return {
      ...note.toMap(),
      if (archived.sealed) 'enc_v': 1,
      if (archived.sealed) 'payload': archived.payload,
    };
  }
}
