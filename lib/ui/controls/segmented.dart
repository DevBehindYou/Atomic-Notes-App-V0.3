import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/widgets.dart';

/// A pill of two to four equal segments with a sliding highlight
/// (components spec, Segmented control): System, Light and Dark; Newest and
/// Oldest.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  }) : assert(segments.length >= 2 && segments.length <= 4);

  /// Each value and its label, in order.
  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = segments.length;
    final index = segments.indexWhere((s) => s.$1 == value);
    final duration = AtomicMotion.move(context, AtomicMotion.quick);
    final onChanged = this.onChanged;
    return Container(
      padding: const EdgeInsets.all(AtomicSpace.x1),
      decoration: BoxDecoration(
        color: c.surfaceInset,
        borderRadius: AtomicRadius.pill,
      ),
      child: Stack(
        children: [
          if (index >= 0)
            Positioned.fill(
              child: AnimatedAlign(
                duration: duration,
                curve: AtomicMotion.standardCurve,
                alignment: Alignment(-1 + 2 * index / (count - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / count,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.inverseSurface,
                      borderRadius: AtomicRadius.pill,
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final (i, (segment, label)) in segments.indexed)
                Expanded(
                  child: AtomicPressable(
                    selected: i == index,
                    semanticsLabel: label,
                    excludeSemantics: true,
                    onTap: onChanged == null
                        ? null
                        : () {
                            if (i == index) return;
                            AtomicHaptics.play(AtomicHaptic.selection);
                            onChanged(segment);
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AtomicSpace.x3, vertical: AtomicSpace.x2),
                      child: AnimatedDefaultTextStyle(
                        duration:
                            AtomicMotion.fade(context, AtomicMotion.quick),
                        style: AtomicType.labelMedium.copyWith(
                          color: i == index ? c.onInverse : c.textPrimary,
                        ),
                        child: Text(label, textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
