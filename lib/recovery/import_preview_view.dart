import 'package:atomic_notes/recovery/import_validator.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
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
    final c = context.colors;
    final body = AtomicType.bodyMedium.copyWith(color: c.textPrimary);
    final p = preview;
    if (p.locked) {
      return Semantics(
        liveRegion: true,
        child: Text(
            'This archive is protected. Enter its export password to see what it contains.',
            style: body),
      );
    }
    String plural(int n, String one, [String? many]) =>
        '$n ${n == 1 ? one : (many ?? '${one}s')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(plural(p.total, 'note'),
            style: AtomicType.titleLarge.copyWith(color: c.textPrimary)),
        const SizedBox(height: AtomicSpace.x2),
        Text(
            [
              plural(p.live, 'note in use', 'notes in use'),
              plural(p.deleted, 'in the recycle bin', 'in the recycle bin'),
              if (p.checklists > 0) plural(p.checklists, 'checklist'),
              if (p.images > 0) plural(p.images, 'image'),
              if (p.sealed > 0) plural(p.sealed, 'encrypted note'),
            ].join(' · '),
            style: body),
        const SizedBox(height: AtomicSpace.x2),
        Text(
            [
              plural(
                  p.added.length, 'new to this device', 'new to this device'),
              plural(p.unchanged.length, 'already here', 'already here'),
              if (p.conflicts.isNotEmpty)
                '${plural(p.conflicts.length, 'differs', 'differ')} from this device; you will choose what to keep',
            ].join(' · '),
            key: const ValueKey('import-preview-comparison'),
            style: body),
        if (p.issues.isNotEmpty) ...[
          const SizedBox(height: AtomicSpace.x2),
          Semantics(
            liveRegion: true,
            child: Text(
                '${plural(p.issues.length, 'note')} cannot be restored: '
                '${{for (final issue in p.issues) issue.message}.join('; ')}.',
                key: const ValueKey('import-preview-issues'),
                style: body.copyWith(color: c.dangerText)),
          ),
        ],
        const SizedBox(height: AtomicSpace.x4),
        FilledButton(
          key: const ValueKey('import-preview-restore'),
          onPressed: p.canRestore ? onRestore : null,
          style: FilledButton.styleFrom(
              minimumSize: const Size.square(AtomicSpace.minTarget)),
          child: const Text('Review restore'),
        ),
      ],
    );
  }
}
