import 'dart:math' as math;

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:flutter/widgets.dart';

/// A success burst: 12 sparks fly out of [child] in the accent, blue and
/// grey over 1.1 s, then nothing is painted (encryption on, two-factor on, a
/// wipe finished, a checklist completed). Plays each time [trigger] changes;
/// never under reduced motion.
class Burst extends StatefulWidget {
  const Burst({
    super.key,
    required this.trigger,
    required this.child,
    this.radius = 56,
  });

  /// Change it (for example, increment it) to play the burst once.
  final int trigger;
  final Widget child;

  /// How far the sparks travel from the centre.
  final double radius;

  static const Duration duration = Duration(milliseconds: 1100);
  static const int sparks = 12;

  @override
  State<Burst> createState() => _BurstState();
}

class _BurstState extends State<Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Burst.duration);

  @override
  void didUpdateWidget(Burst old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !AtomicMotion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AtomicMotion.reduced(context) && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colours = [c.accent, c.info, AtomicPalette.gray500];
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) => CustomPaint(
          foregroundPainter: _controller.isAnimating
              ? _BurstPainter(
                  t: AtomicMotion.expressiveCurve.transform(_controller.value),
                  radius: widget.radius,
                  colours: colours,
                )
              : null,
          child: child,
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t, required this.radius, required this.colours});

  final double t;
  final double radius;
  final List<Color> colours;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final paint = Paint();
    for (var i = 0; i < Burst.sparks; i++) {
      final angle = i * 2 * math.pi / Burst.sparks;
      final distance = radius * t;
      paint.color = colours[i % colours.length].withValues(alpha: 1 - t);
      canvas.drawCircle(
        centre + Offset(math.cos(angle), math.sin(angle)) * distance,
        1 + 3 * (1 - t),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
