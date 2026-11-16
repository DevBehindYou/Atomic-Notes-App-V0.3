import 'dart:math' as math;

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/ui/motion/ambient.dart';
import 'package:flutter/widgets.dart';

/// A conic accent ring that circles [child] while [busy] (the sync orbit).
///
/// The orbit is a budgeted ambient loop ([AmbientBudget]): it turns only
/// while busy, in the foreground, on a shown route, without reduced motion,
/// and when a slot is free. Whenever it cannot turn but [busy] is still true,
/// a still ring shows instead, so the busy state never disappears.
class OrbitRing extends StatefulWidget {
  const OrbitRing({
    super.key,
    required this.busy,
    required this.child,
    this.stroke = 2.5,
  });

  final bool busy;
  final Widget child;
  final double stroke;

  static const Duration period = Duration(milliseconds: 1200);

  @override
  State<OrbitRing> createState() => _OrbitRingState();
}

class _OrbitRingState extends State<OrbitRing>
    with SingleTickerProviderStateMixin, AmbientLoop<OrbitRing> {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: OrbitRing.period);

  @override
  bool get wantsLoop => widget.busy;

  @override
  void startLoop() => _controller.repeat();

  @override
  void stopLoop() => _controller.stop();

  @override
  void didUpdateWidget(OrbitRing old) {
    super.didUpdateWidget(old);
    if (old.busy != widget.busy) updateLoop(rebuild: false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) => CustomPaint(
          foregroundPainter: widget.busy
              ? _OrbitPainter(
                  turn: _controller.value,
                  colour: accent,
                  stroke: widget.stroke,
                  still: !looping,
                )
              : null,
          child: child,
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.turn,
    required this.colour,
    required this.stroke,
    required this.still,
  });

  final double turn;
  final Color colour;
  final double stroke;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (still) {
      canvas.drawOval(rect, paint..color = colour);
      return;
    }
    final start = turn * 2 * math.pi;
    paint.shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: [colour.withValues(alpha: 0), colour],
      transform: GradientRotation(start),
    ).createShader(rect);
    canvas.drawArc(rect, start, 1.5 * math.pi, false, paint);
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.turn != turn ||
      old.colour != colour ||
      old.still != still ||
      old.stroke != stroke;
}
