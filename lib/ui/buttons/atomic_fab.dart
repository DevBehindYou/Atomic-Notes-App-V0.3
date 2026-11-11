import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';

/// The new-note button: a 64 dp accent circle inside a 6 dp canvas ring
/// (components spec, Floating action button).
///
/// At the note limit it stays tappable, so the page can say why, and shows a
/// small danger "!" badge.
class AtomicFab extends StatelessWidget {
  const AtomicFab({
    super.key,
    required this.onPressed,
    this.label = 'New note',
    this.icon = AtomicIcons.plus,
    this.atLimit = false,
  });

  final VoidCallback? onPressed;

  /// Tooltip and semantics label.
  final String label;
  final IconData icon;
  final bool atLimit;

  static const double size = 64;
  static const double ring = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: AtomicPressable(
        onTap: onPressed,
        semanticsLabel: atLimit ? '$label. Note limit reached' : label,
        excludeSemantics: true,
        haptic: AtomicHaptic.light,
        pressScale: 0.92,
        child: SizedBox.square(
          dimension: size + ring * 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: c.canvas,
                        width: ring,
                        strokeAlign: BorderSide.strokeAlignInside),
                  ),
                  child: Icon(icon, size: 28, color: c.onAccent),
                ),
              ),
              if (atLimit)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.canvas, width: 2),
                    ),
                    child: Text(
                      '!',
                      textScaler: TextScaler.noScaling,
                      style: AtomicType.labelSmall.copyWith(color: c.onDanger),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
