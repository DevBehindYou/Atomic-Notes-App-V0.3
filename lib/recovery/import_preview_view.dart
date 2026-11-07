import 'package:atomic_notes/recovery/import_validator.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Shows what restoring an archive would do. It shows counts and reasons
/// only, never note content, and offers [onRestore] only when the archive is
/// unlocked and fully valid. Not yet reachable from any screen (C15).
class ImportPreviewView extends StatelessWidget {
  const ImportPreviewView({required this.preview, this.onRestore, super.key});

  final ImportPreview preview;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final p = preview;
    if (p.locked) {
      return Semantics(
        liveRegion: true,
        child: const Text(
            'This archive is protected. Enter its export password to see what it contains.',
            style: AppType.bodyMd),
      );
    }
    String plural(int n, String one, [String? many]) =>
        '$n ${n == 1 ? one : (many ?? '${one}s')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(plural(p.total, 'note'), style: AppType.headlineSm),
        const SizedBox(height: AppSpace.sm),
        Text(
            [
              plural(p.live, 'note in use', 'notes in use'),
              plural(p.deleted, 'in the recycle bin', 'in the recycle bin'),
              if (p.checklists > 0) plural(p.checklists, 'checklist'),
              if (p.images > 0) plural(p.images, 'image'),
              if (p.sealed > 0) plural(p.sealed, 'encrypted note'),
            ].join(' · '),
            style: AppType.bodyMd),
        const SizedBox(height: AppSpace.sm),
        Text(
            [
              plural(
                  p.added.length, 'new to this device', 'new to this device'),
              plural(p.unchanged.length, 'already here', 'already here'),
              if (p.conflicts.isNotEmpty)
                '${plural(p.conflicts.length, 'differs', 'differ')} from this device; you will choose what to keep',
            ].join(' · '),
            key: const ValueKey('import-preview-comparison'),
            style: AppType.bodyMd),
        if (p.issues.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Semantics(
            liveRegion: true,
            child: Text(
                '${plural(p.issues.length, 'note')} cannot be restored: '
                '${{for (final issue in p.issues) issue.message}.join('; ')}.',
                key: const ValueKey('import-preview-issues'),
                style: AppType.bodyMd.copyWith(color: AppColors.error)),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        FilledButton(
          key: const ValueKey('import-preview-restore'),
          onPressed: p.canRestore ? onRestore : null,
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text('Review restore'),
        ),
      ],
    );
  }
}
