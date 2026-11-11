import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/controls/atomic_checkbox.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';

/// One checklist item as a pill: a round checkbox, then the text (components
/// spec, Checklist pill). The whole pill is one checkbox toggle.
///
/// [onToggle] only flips the item's done flag; the page decides what that
/// saves, as today (preservation rule 3). In the editor, [onRemove] adds the
/// trailing remove button and the pill stretches full width.
class ChecklistRow extends StatelessWidget {
  const ChecklistRow({
    super.key,
    required this.text,
    required this.done,
    required this.onToggle,
    this.tone = CheckboxTone.standard,
    this.semanticsLabel,
    this.onRemove,
    this.removeTooltip,
  });

  final String text;
  final bool done;

  /// Null in selection mode: the pill ignores taps, as today.
  final VoidCallback? onToggle;
  final CheckboxTone tone;

  /// Defaults to "Complete {text}".
  final String? semanticsLabel;
  final VoidCallback? onRemove;

  /// For example "Remove item 2" (the editor's existing string).
  final String? removeTooltip;

  static const double minHeight = 44;

  (Color, Color, Color) _colors(BuildContext context, AtomicColors c) {
    final light = Theme.of(context).brightness == Brightness.light;
    return switch (tone) {
      CheckboxTone.standard => (c.surfaceInset, c.textPrimary, c.textSecondary),
      CheckboxTone.featured => (
          AtomicPalette.white,
          AtomicPalette.black,
          AtomicPalette.gray600
        ),
      CheckboxTone.important => (
          light ? AtomicPalette.gray850 : AtomicPalette.gray200,
          c.onInverse,
          c.onInverse.withValues(alpha: 0.72)
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (fill, textColor, doneColor) = _colors(context, context.colors);
    final onToggle = this.onToggle;
    final onRemove = this.onRemove;
    final label = Text(
      text,
      style: AtomicType.bodyMedium.copyWith(
        color: done ? doneColor : textColor,
        decoration: done ? TextDecoration.lineThrough : null,
        decorationColor: doneColor,
      ),
    );
    final pill = AtomicPressable(
      button: false,
      checked: done,
      semanticsLabel: semanticsLabel ?? 'Complete $text',
      excludeSemantics: true,
      borderRadius: AtomicRadius.pill,
      onTap: onToggle == null
          ? null
          : () {
              if (!done) AtomicHaptics.play(AtomicHaptic.light);
              onToggle();
            },
      child: Container(
        constraints: const BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(
            horizontal: AtomicSpace.x3, vertical: AtomicSpace.x2),
        decoration: BoxDecoration(color: fill, borderRadius: AtomicRadius.pill),
        child: Row(
          mainAxisSize: onRemove == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            AtomicCheckboxMark(checked: done, tone: tone),
            const SizedBox(width: AtomicSpace.x2),
            Flexible(fit: FlexFit.loose, child: label),
          ],
        ),
      ),
    );
    if (onRemove == null) return pill;
    final remove = removeTooltip ?? 'Remove item';
    return Row(
      children: [
        Expanded(child: pill),
        Tooltip(
          message: remove,
          excludeFromSemantics: true,
          child: AtomicPressable(
            onTap: onRemove,
            semanticsLabel: remove,
            excludeSemantics: true,
            child: Icon(AtomicIcons.x,
                size: 20, color: context.colors.textSecondary),
          ),
        ),
      ],
    );
  }
}
