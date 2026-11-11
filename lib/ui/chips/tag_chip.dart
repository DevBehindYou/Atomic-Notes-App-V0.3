import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';

/// The editor's tag: `#tag` on a 36 dp inset pill with a remove button
/// (components spec, Editor tag chip). The tooltip "Remove tag {tag}" is the
/// existing string tests look for.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.tag, required this.onRemove});

  final String tag;
  final VoidCallback? onRemove;

  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: height),
      padding: const EdgeInsets.only(left: AtomicSpace.x3),
      decoration: BoxDecoration(
        color: c.surfaceInset,
        borderRadius: AtomicRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '#$tag',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AtomicType.labelMedium.copyWith(color: c.textPrimary),
            ),
          ),
          Tooltip(
            message: 'Remove tag $tag',
            excludeFromSemantics: true,
            child: AtomicPressable(
              onTap: onRemove,
              semanticsLabel: 'Remove tag $tag',
              excludeSemantics: true,
              minSize: AtomicSpace.minTarget,
              child: Icon(AtomicIcons.x, size: 16, color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Add tag" as a tonal pill with a plus. The page hides it at three tags.
class AddTagChip extends StatelessWidget {
  const AddTagChip({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AtomicPressable(
      onTap: onPressed,
      semanticsLabel: 'Add tag',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: TagChip.height),
        padding: const EdgeInsets.symmetric(horizontal: AtomicSpace.x3),
        decoration: BoxDecoration(
          color: c.surfaceInset,
          borderRadius: AtomicRadius.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AtomicIcons.plus, size: 16, color: c.textPrimary),
            const SizedBox(width: AtomicSpace.x1),
            Flexible(
              child: Text(
                'Add tag',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AtomicType.labelMedium.copyWith(color: c.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
