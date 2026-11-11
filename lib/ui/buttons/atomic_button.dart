import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';

enum AtomicButtonVariant {
  /// The one main action on a screen.
  primary,

  /// A strong alternative.
  secondary,

  /// Ordinary actions.
  tonal,

  /// Low emphasis: Skip, Cancel, Mark all read.
  text,

  /// Destructive confirmations only.
  danger,
}

enum AtomicButtonSize {
  /// 56 high: full-width page actions.
  large,

  /// 48 high.
  regular,

  /// 40 visible inside a 48 target: inside cards.
  compact,
}

/// A pill button with a sentence-case label (components spec, Buttons).
///
/// [onPressed] null shows the disabled look; prefer an enabled button that
/// explains why on tap. While [busy] the label fades out, a spinner fades in,
/// the width stays, and taps are ignored.
class AtomicButton extends StatelessWidget {
  const AtomicButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AtomicButtonVariant.primary,
    this.size = AtomicButtonSize.regular,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.onCard = false,
  });

  const AtomicButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AtomicButtonSize.regular,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.onCard = false,
  }) : variant = AtomicButtonVariant.primary;

  const AtomicButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AtomicButtonSize.regular,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.onCard = false,
  }) : variant = AtomicButtonVariant.secondary;

  const AtomicButton.tonal({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AtomicButtonSize.regular,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.onCard = false,
  }) : variant = AtomicButtonVariant.tonal;

  const AtomicButton.text({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AtomicButtonSize.regular,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.onCard = false,
  }) : variant = AtomicButtonVariant.text;

  const AtomicButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AtomicButtonSize.regular,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.onCard = false,
  }) : variant = AtomicButtonVariant.danger;

  final String label;
  final VoidCallback? onPressed;
  final AtomicButtonVariant variant;
  final AtomicButtonSize size;

  /// Optional leading icon, drawn at 20.
  final IconData? icon;
  final bool busy;

  /// Fills the available width.
  final bool expand;

  /// On a card the tonal fill steps down to `surfaceInset`.
  final bool onCard;

  static double heightOf(AtomicButtonSize size) => switch (size) {
        AtomicButtonSize.large => 56,
        AtomicButtonSize.regular => 48,
        AtomicButtonSize.compact => 40,
      };

  (Color?, Color) _colors(AtomicColors c) {
    if (onPressed == null) {
      return (
        variant == AtomicButtonVariant.text ? null : c.surfaceInset,
        c.textDisabled,
      );
    }
    return switch (variant) {
      AtomicButtonVariant.primary => (c.accent, c.onAccent),
      AtomicButtonVariant.secondary => (c.inverseSurface, c.onInverse),
      AtomicButtonVariant.tonal => (
          onCard ? c.surfaceInset : c.surface,
          c.textPrimary
        ),
      AtomicButtonVariant.text => (null, c.textPrimary),
      AtomicButtonVariant.danger => (c.danger, c.onDanger),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (fill, content) = _colors(context.colors);
    final fade = AtomicMotion.fade(context, AtomicMotion.quick);
    final face = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: content),
          const SizedBox(width: AtomicSpace.x2),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AtomicType.labelLarge.copyWith(color: content),
          ),
        ),
      ],
    );
    final body = Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(opacity: busy ? 0 : 1, duration: fade, child: face),
        if (busy)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: fade,
            builder: (context, t, child) => Opacity(opacity: t, child: child),
            child: SizedBox.square(
              dimension: 20,
              child:
                  CircularProgressIndicator(strokeWidth: 2.5, color: content),
            ),
          ),
      ],
    );
    Widget button = DecoratedBox(
      decoration: BoxDecoration(color: fill, borderRadius: AtomicRadius.pill),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: heightOf(size)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: size == AtomicButtonSize.compact
                ? AtomicSpace.x4
                : AtomicSpace.x6,
            vertical: AtomicSpace.x2,
          ),
          child: Center(widthFactor: 1, heightFactor: 1, child: body),
        ),
      ),
    );
    if (expand) button = SizedBox(width: double.infinity, child: button);
    return AtomicPressable(
      onTap: busy ? null : onPressed,
      semanticsLabel: label,
      excludeSemantics: true,
      child: button,
    );
  }
}
