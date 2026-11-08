import 'package:atomic_notes/recovery/archive_manifest.dart';
import 'package:atomic_notes/recovery/export_writer.dart';
import 'package:atomic_notes/recovery/import_preview_view.dart';
import 'package:atomic_notes/recovery/import_validator.dart';
import 'package:atomic_notes/recovery/restore_coordinator.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:flutter/material.dart';

/// Backup and restore stays off until its device integration is accepted:
/// the native store adapter waits for B05 and the reserved repository.
abstract final class RecoveryFeature {
  static const enabled = bool.fromEnvironment('ATOMIC_RECOVERY_PREVIEW');
}

/// The last export that actually finished. Only a committed export is ever
/// recorded; a failed or cancelled one leaves the previous record as it was.
class BackupRecord {
  const BackupRecord(this.finishedAt, this.notes, this.encrypted,
      {this.sealed = 0});
  final DateTime finishedAt;
  final int notes;
  final bool encrypted;

  /// Encrypted vault notes in the archive. They are kept in it but cannot be
  /// restored from it yet (C13), so they are never counted as backed up.
  final int sealed;
}

/// The user-facing text for an archive the reader refused.
String archiveProblem(ArchiveFormatException error) => switch (error.code) {
      'unsupported_kdf' =>
        'This backup uses password settings this version does not support. '
            'Nothing was opened or changed.',
      _ => error.message,
    };

/// Why a backup holding encrypted vault notes is not a full backup.
String sealedNotice(int sealed) =>
    '$sealed encrypted vault ${sealed == 1 ? 'note is' : 'notes are'} '
    'included but cannot be restored from a backup yet.';

/// The device facts the page shows and the ports it acts through. A native
/// adapter is not part of this change.
abstract class RecoveryPorts {
  /// Notes saved on this device (not necessarily backed up or synced).
  int get savedLocally;

  /// What the device knows about cloud sync, stated plainly, or null if
  /// unknown. The page never infers a backup from sync.
  String? get cloudStatus;

  BackupRecord? get lastBackup;
  Future<void> recordBackup(BackupRecord record);

  Future<List<ArchiveSource>> snapshot();
  ArchiveVault? get vault;
  ExportTarget newExportTarget();

  /// The archive the user chose, or null when they cancelled.
  Future<ArchiveByteSource Function()?> pickArchive();
  LocalNotesView get local;
  RestoreStore get restoreStore;
}

/// Backup status, export and restore (C15). Not reachable from any route.
class RecoveryPage extends StatefulWidget {
  const RecoveryPage(
      {required this.ports,
      this.enabled = RecoveryFeature.enabled,
      this.deriveKey = ArchiveKey.create,
      this.openKey = _deriveForHeader,
      super.key});

  final RecoveryPorts ports;
  final bool enabled;
  final Future<ArchiveKey> Function(String password) deriveKey;
  final Future<ArchiveKey> Function(String password, ArchiveHeader header)
      openKey;

  static Future<ArchiveKey> _deriveForHeader(
          String password, ArchiveHeader header) =>
      ArchiveKey.derive(password, header.salt!,
          memory: header.memory,
          iterations: header.iterations,
          parallelism: header.parallelism);

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

enum _Busy { none, exporting, opening, restoring }

class _RecoveryPageState extends State<RecoveryPage> {
  final _password = TextEditingController();
  _Busy _busy = _Busy.none;
  int _done = 0, _total = 0;
  ExportCancel? _cancel;
  String? _message;
  bool _failed = false;

  ArchiveByteSource Function()? _archive;
  ArchiveKey? _archiveKey;
  ImportPreview? _preview;
  final _choices = <String, ConflictChoice>{};

  @override
  void dispose() {
    _cancel?.cancel();
    _password.dispose();
    super.dispose();
  }

  void _say(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _failed = failed;
      _busy = _Busy.none;
    });
  }

  Future<void> _export() async {
    final ports = widget.ports;
    final cancel = _cancel = ExportCancel();
    setState(() {
      _busy = _Busy.exporting;
      _done = 0;
      _total = 0;
      _message = null;
    });
    try {
      final sources = await ports.snapshot();
      final password = _password.text;
      final key = password.isEmpty ? null : await widget.deriveKey(password);
      if (cancel.isCancelled) throw const ExportCancelled();
      final result = await ExportWriter().write(
          ports.newExportTarget(), sources,
          key: key,
          vault: ports.vault,
          cancel: cancel, onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
          });
        }
      });
      // Recorded only after the archive was committed to its final place.
      final sealed = result.manifest.entries.where((e) => e.sealed).length;
      await ports.recordBackup(BackupRecord(
          DateTime.now().toUtc(), result.manifest.entries.length, key != null,
          sealed: sealed));
      _say([
        'Backup saved: ${result.manifest.entries.length} notes.',
        if (sealed > 0) sealedNotice(sealed),
      ].join(' '));
    } on ExportCancelled {
      _say(
          'Backup cancelled. Nothing was saved; your last backup is unchanged.');
    } on ArchiveFormatException catch (error) {
      _say(archiveProblem(error), failed: true);
    } on ExportFailed catch (error) {
      _say(error.message, failed: true);
    } catch (_) {
      _say('The backup could not be written. Your notes are unchanged.',
          failed: true);
    } finally {
      _cancel = null;
    }
  }

  Future<void> _openArchive() async {
    setState(() {
      _busy = _Busy.opening;
      _message = null;
      _preview = null;
      _archiveKey = null;
      _choices.clear();
    });
    try {
      final archive = await widget.ports.pickArchive();
      if (archive == null) return _say('No archive chosen.');
      _archive = archive;
      await _inspect();
    } on ArchiveFormatException catch (error) {
      _say(archiveProblem(error), failed: true);
    }
  }

  Future<void> _inspect() async {
    final archive = _archive!;
    final password = _password.text;
    final preview = await ImportValidator.inspect(archive(),
        local: widget.ports.local,
        unlock: password.isEmpty
            ? null
            : (header) async =>
                _archiveKey = await widget.openKey(password, header));
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _busy = _Busy.none;
    });
  }

  Future<void> _unlock() async {
    setState(() => _busy = _Busy.opening);
    try {
      await _inspect();
    } on ArchiveFormatException catch (error) {
      _say(archiveProblem(error), failed: true);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = _Busy.restoring);
    try {
      final result = await RestoreCoordinator(widget.ports.restoreStore)
          .restore(_archive!,
              approved: _preview!,
              local: widget.ports.local,
              choices: Map.of(_choices),
              key: _archiveKey);
      setState(() => _preview = null);
      _say('Restored ${result.written.length} notes. '
          '${result.kept.length} kept as they were on this device.');
    } on RestoreRefused catch (error) {
      _say(error.message, failed: true);
    } on ArchiveFormatException catch (error) {
      _say(archiveProblem(error), failed: true);
    } catch (_) {
      _say('The restore stopped. It will finish or be undone next time.',
          failed: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const MyAppBar(text: 'Backup and restore'),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.md),
            children: widget.enabled ? _content() : [_unavailable()],
          ),
        ),
      );

  Widget _unavailable() => Semantics(
        liveRegion: true,
        child: const Text(
            'Backup and restore is not available yet. Your notes stay saved on this device and sync as usual.',
            key: ValueKey('recovery-unavailable'),
            style: AppType.bodyMd),
      );

  List<Widget> _content() {
    final ports = widget.ports;
    final backup = ports.lastBackup;
    final busy = _busy != _Busy.none;
    return [
      // Three separate facts, never merged into one "safe" claim.
      Text('${ports.savedLocally} notes saved on this device',
          key: const ValueKey('recovery-local'), style: AppType.bodyMd),
      Text(ports.cloudStatus ?? 'Cloud sync status unknown',
          key: const ValueKey('recovery-cloud'), style: AppType.bodyMd),
      Text(
          backup == null
              ? 'No backup made on this device yet'
              : 'Last backup: ${backup.notes} notes, '
                  '${backup.finishedAt.toLocal().toString().substring(0, 16)}'
                  '${backup.encrypted ? ', password protected' : ''}'
                  '${backup.sealed > 0 ? '. ${sealedNotice(backup.sealed)}' : ''}',
          key: const ValueKey('recovery-backup'),
          style: AppType.bodyMd),
      const SizedBox(height: AppSpace.md),
      TextField(
        key: const ValueKey('recovery-password'),
        controller: _password,
        obscureText: true,
        enabled: !busy,
        decoration: const InputDecoration(
            labelText: 'Backup password',
            helperText:
                'Protects the backup file. Without it, anyone with the file can read your notes.',
            border: OutlineInputBorder()),
      ),
      const SizedBox(height: AppSpace.md),
      if (_busy == _Busy.exporting) ...[
        Semantics(
          liveRegion: true,
          child: Text(
              _total == 0
                  ? 'Preparing backup…'
                  : 'Saving $_done of $_total notes…',
              key: const ValueKey('recovery-progress'),
              style: AppType.bodyMd),
        ),
        LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
        TextButton(
            key: const ValueKey('recovery-cancel'),
            onPressed: () => _cancel?.cancel(),
            child: const Text('Cancel backup')),
      ] else
        FilledButton(
            key: const ValueKey('recovery-export'),
            onPressed: busy ? null : _export,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Back up notes')),
      const SizedBox(height: AppSpace.sm),
      OutlinedButton(
          key: const ValueKey('recovery-open'),
          onPressed: busy ? null : _openArchive,
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text('Restore from a backup')),
      if (_message != null) ...[
        const SizedBox(height: AppSpace.sm),
        Semantics(
          liveRegion: true,
          child: Text(_message!,
              key: const ValueKey('recovery-message'),
              style: _failed
                  ? AppType.bodyMd.copyWith(color: AppColors.error)
                  : AppType.bodyMd),
        ),
      ],
      if (_preview != null) ..._previewSection(_preview!),
    ];
  }

  List<Widget> _previewSection(ImportPreview preview) => [
        const SizedBox(height: AppSpace.md),
        ImportPreviewView(
          preview: preview,
          onRestore: preview.conflicts.every(_choices.containsKey) &&
                  _busy == _Busy.none
              ? _restore
              : null,
        ),
        if (preview.locked)
          TextButton(
              key: const ValueKey('recovery-unlock'),
              onPressed: _busy == _Busy.none ? _unlock : null,
              child: const Text('Open with the password above')),
        for (final (index, id) in preview.conflicts.indexed)
          SwitchListTile(
            key: ValueKey('recovery-choice-$id'),
            title: Text('Differing note ${index + 1}: use the backup version'),
            subtitle: Text(_choices[id] == null
                ? 'Choose before restoring'
                : _choices[id] == ConflictChoice.useArchive
                    ? 'The backup version replaces this device\'s; it is kept as a copy'
                    : 'This device\'s version is kept'),
            value: _choices[id] == ConflictChoice.useArchive,
            onChanged: (useArchive) => setState(() => _choices[id] = useArchive
                ? ConflictChoice.useArchive
                : ConflictChoice.keepDevice),
          ),
      ];
}
