import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/chips/count_bubble.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';

/// A single-select filter chip with an optional count bubble (components
/// spec, Filter chip and Tag chip). Named apart from Material's
/// `FilterChip`.
///
/// Selected: an inverse fill, with the bubble cut out in the canvas colour.
class AtomicFilterChip extends StatelessWidget {
  const AtomicFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.count,
  }) : maxLabelWidth = null;

  /// A tag, shown as `#tag` exactly as stored. Long tags truncate at 160 dp;
  /// the full tag stays in the semantics label.
  const AtomicFilterChip.tag({
    super.key,
    required String tag,
    required this.selected,
    required this.onSelected,
    this.count,
  })  : label = '#$tag',
        maxLabelWidth = 160;

  final String label;
  final bool selected;
  final VoidCallback? onSelected;
  final int? count;
  final double? maxLabelWidth;

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final duration = AtomicMotion.fade(context, AtomicMotion.quick);
    final textColor = selected ? c.onInverse : c.textPrimary;
    Widget text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AtomicType.labelMedium.copyWith(color: textColor),
    );
    if (maxLabelWidth != null) {
      text = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxLabelWidth!), child: text);
    }
    final count = this.count;
    return AtomicPressable(
      onTap: onSelected,
      selected: selected,
      haptic: AtomicHaptic.selection,
      semanticsLabel: count == null ? label : '$label, $count',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: AtomicMotion.standardCurve,
        constraints: const BoxConstraints(minHeight: height),
        padding: EdgeInsets.only(
          left: AtomicSpace.x4,
          right: count == null ? AtomicSpace.x4 : AtomicSpace.x2,
          top: AtomicSpace.x1,
          bottom: AtomicSpace.x1,
        ),
        decoration: BoxDecoration(
          color: selected ? c.inverseSurface : c.surface,
          borderRadius: AtomicRadius.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: text),
            if (count != null) ...[
              const SizedBox(width: AtomicSpace.x2),
              AnimatedSwitcher(
                duration: duration,
                child: CountBubble(
                  key: ValueKey(count),
                  count: count,
                  fill: selected ? c.canvas : c.badge,
                  textColor: c.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
