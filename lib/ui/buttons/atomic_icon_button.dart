import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';

/// A 44 dp circular icon button in a 48 target (components spec, Icon
/// button). [tooltip] is required and is also the semantics label, so
/// existing tests that find controls by tooltip keep working.
///
/// A toggle (pin, important) passes [toggled]; when on it shows
/// [toggledIcon] on an accent fill.
class AtomicIconButton extends StatelessWidget {
  const AtomicIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onLongPress,
    this.toggled,
    this.toggledIcon,
    this.onCard = false,
    this.badgeCount = 0,
    this.dot = false,
    this.semanticsLabel,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool? toggled;
  final IconData? toggledIcon;

  /// On a card the fill steps down to `surfaceInset`.
  final bool onCard;

  /// An unread count in an accent pill; nothing when zero, "9+" above nine.
  final int badgeCount;

  /// A small accent dot, for example changes waiting to sync.
  final bool dot;

  /// Overrides [tooltip] for screen readers, for example to add a count.
  final String? semanticsLabel;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = toggled ?? false;
    final enabled = onPressed != null || onLongPress != null;
    final fill = on ? c.accent : (onCard ? c.surfaceInset : c.surface);
    final iconColor =
        !enabled ? c.textDisabled : (on ? c.onAccent : c.textPrimary);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: AtomicPressable(
        onTap: onPressed,
        onLongPress: onLongPress,
        toggled: toggled,
        semanticsLabel: semanticsLabel ?? tooltip,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration:
                      BoxDecoration(color: fill, shape: BoxShape.circle),
                  child: Icon(on ? (toggledIcon ?? icon) : icon,
                      size: 24, color: iconColor),
                ),
              ),
              if (dot && badgeCount <= 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: fill, width: 2),
                    ),
                  ),
                ),
              if (badgeCount > 0)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: AtomicRadius.pill,
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      textScaler: TextScaler.noScaling,
                      style: AtomicType.labelSmall.copyWith(color: c.onAccent),
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
