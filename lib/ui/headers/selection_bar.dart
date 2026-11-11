import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:flutter/material.dart';

/// Replaces the Home title row in selection mode (components spec, Selection
/// bar): cancel, "{n} selected", Select all, and Delete. On a narrow screen
/// or with large text the actions wrap onto a second line.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.onCancel,
    required this.onSelectAll,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AtomicSpace.x2,
      spacing: AtomicSpace.x2,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AtomicIconButton(
              icon: AtomicIcons.x,
              tooltip: 'Cancel selection',
              onPressed: onCancel,
            ),
            const SizedBox(width: AtomicSpace.x2),
            Flexible(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '$count selected',
                  style:
                      AtomicType.headlineMedium.copyWith(color: c.textPrimary),
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: AtomicButton.text(
                  label: 'Select all', onPressed: onSelectAll),
            ),
            const SizedBox(width: AtomicSpace.x1),
            Flexible(
              child: AtomicButton.danger(
                label: 'Delete',
                icon: AtomicIcons.trash,
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
