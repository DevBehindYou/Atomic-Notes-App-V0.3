import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/widgets.dart';

/// A 52 × 32 pill switch (components spec, Switch). The orange track alone is
/// not the signal: the black thumb on it is (accessibility spec, contrast).
class AtomicSwitch extends StatelessWidget {
  const AtomicSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticsLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return AtomicPressable(
      button: false,
      toggled: value,
      semanticsLabel: semanticsLabel,
      excludeSemantics: true,
      haptic: AtomicHaptic.selection,
      onTap: onChanged == null ? null : () => onChanged(!value),
      child: AtomicSwitchTrack(value: value, enabled: onChanged != null),
    );
  }
}

/// The switch's look alone, for a row that is itself the control (a
/// settings row with a switch is one toggle, not two).
class AtomicSwitchTrack extends StatelessWidget {
  const AtomicSwitchTrack(
      {super.key, required this.value, this.enabled = true});

  final bool value;
  final bool enabled;

  static const Size size = Size(52, 32);
  static const double thumb = 24;

  /// Thumb travel and track colour together (components spec, Switch).
  static const Duration travel = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final duration = AtomicMotion.move(context, travel);
    final track = !enabled
        ? c.surfaceInset
        : value
            ? c.accent
            : c.badge;
    final thumbColor = !enabled
        ? c.textDisabled
        : value
            ? c.onAccent
            : c.outlineStrong;
    return AnimatedContainer(
      duration: duration,
      curve: AtomicMotion.standardCurve,
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: AtomicRadius.pill,
        border: Border.all(
          color: value && enabled ? track : c.outlineStrong,
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: AnimatedAlign(
        duration: duration,
        curve: AtomicMotion.standardCurve,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: duration,
          width: thumb - 3,
          height: thumb - 3,
          decoration: BoxDecoration(color: thumbColor, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
