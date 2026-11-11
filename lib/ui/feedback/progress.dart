import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:flutter/material.dart';

/// A circular progress indicator: 20 or 24 dp, 2.5 dp stroke, accent on the
/// inset colour (components spec, Progress). Indeterminate when [value] is
/// null. Replaces `circularProgress`.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    this.value,
    this.size = 24,
    this.semanticsLabel,
  });

  final double? value;
  final double size;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: 2.5,
        color: c.accent,
        backgroundColor: c.surfaceInset,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}

/// An 8 dp pill progress bar that grows from zero on entry (`roll`, the
/// expressive curve) and animates to each new value. On an accent card the
/// track is black at 20 % with a black fill; elsewhere an accent fill on the
/// inset track. Replaces `EnergyBar`.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.onAccent = false,
    this.semanticsLabel,
    this.semanticsValue,
  });

  /// From 0 to 1.
  final double value;
  final bool onAccent;
  final String? semanticsLabel;

  /// For example "28 of 30".
  final String? semanticsValue;

  static const double height = 8;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final track =
        onAccent ? AtomicPalette.black.withValues(alpha: 0.2) : c.surfaceInset;
    final fill = onAccent ? AtomicPalette.black : c.accent;
    return Semantics(
      label: semanticsLabel,
      value: semanticsValue ?? '${(value.clamp(0, 1) * 100).round()}%',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
          duration: AtomicMotion.move(context, AtomicMotion.roll),
          curve: AtomicMotion.expressiveCurve,
          builder: (context, t, _) => Container(
            height: height,
            decoration:
                BoxDecoration(color: track, borderRadius: AtomicRadius.pill),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: t,
              heightFactor: 1,
              child: DecoratedBox(
                decoration:
                    BoxDecoration(color: fill, borderRadius: AtomicRadius.pill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A placeholder block in the inset colour with a slow opacity pulse
/// (components spec, Skeleton). The pulse stops under reduced motion and
/// whenever tickers are muted (off screen, route not current). Use it only
/// when loading takes longer than 300 ms.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AtomicRadius.mediumAll,
  });

  final double? width;
  final double height;
  final BorderRadius radius;

  static const Duration pulse = Duration(milliseconds: 1200);

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: Skeleton.pulse);
  late final Animation<double> _opacity = Tween<double>(begin: 0.45, end: 1)
      .animate(
          CurvedAnimation(parent: _pulse, curve: AtomicMotion.ambientCurve));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AtomicMotion.reduced(context)) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: context.colors.surfaceInset,
            borderRadius: widget.radius,
          ),
        ),
      ),
    );
  }
}
