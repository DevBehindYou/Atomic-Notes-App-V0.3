import 'dart:ui' show PathMetric;

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/widgets.dart';

/// Where a checkbox sits, which sets its colours (components spec,
/// Checklist pill and round checkbox; tokens, note card colour variants).
enum CheckboxTone {
  /// Outline ring; accent fill with a black check.
  standard,

  /// On the featured card's white pill: black ring; black fill, white check.
  featured,

  /// On an important card's pill: ring and check in the inverse content
  /// colour; accent fill.
  important,
}

/// A 22 dp round checkbox, drawn only. Completing it pops the fill from the
/// centre (150 ms), then draws the check (150 ms); under reduced motion the
/// change is instant.
class AtomicCheckboxMark extends StatelessWidget {
  const AtomicCheckboxMark({
    super.key,
    required this.checked,
    this.tone = CheckboxTone.standard,
    this.enabled = true,
  });

  final bool checked;
  final CheckboxTone tone;
  final bool enabled;

  static const double size = 22;
  static const Duration pop = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (ring, fill, check) = switch (tone) {
      CheckboxTone.standard => (c.outlineStrong, c.accent, c.onAccent),
      CheckboxTone.featured => (
          AtomicPalette.black,
          AtomicPalette.black,
          AtomicPalette.white
        ),
      CheckboxTone.important => (c.onInverse, c.accent, c.onAccent),
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(end: checked ? 1 : 0),
      duration: AtomicMotion.move(context, pop),
      builder: (context, t, _) => CustomPaint(
        size: const Size.square(size),
        painter: _CheckPainter(
          progress: t,
          ring: enabled ? ring : c.textDisabled,
          fill: enabled ? fill : c.textDisabled,
          check: check,
        ),
      ),
    );
  }
}

/// A standalone checkbox control: the mark in a 48 dp target, reporting its
/// checked state. Plays a light haptic when completing only.
class AtomicCheckbox extends StatelessWidget {
  const AtomicCheckbox({
    super.key,
    required this.checked,
    required this.onChanged,
    required this.semanticsLabel,
    this.tone = CheckboxTone.standard,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final String semanticsLabel;
  final CheckboxTone tone;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return AtomicPressable(
      button: false,
      checked: checked,
      semanticsLabel: semanticsLabel,
      excludeSemantics: true,
      onTap: onChanged == null
          ? null
          : () {
              if (!checked) AtomicHaptics.play(AtomicHaptic.light);
              onChanged(!checked);
            },
      child: AtomicCheckboxMark(
          checked: checked, tone: tone, enabled: onChanged != null),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.progress,
    required this.ring,
    required this.fill,
    required this.check,
  });

  final double progress;
  final Color ring;
  final Color fill;
  final Color check;

  static const double ringWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final fillT = (progress * 2).clamp(0.0, 1.0);
    final checkT = (progress * 2 - 1).clamp(0.0, 1.0);
    if (fillT < 1) {
      canvas.drawCircle(
        center,
        radius - ringWidth / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..color = ring,
      );
    }
    if (fillT > 0) {
      canvas.drawCircle(center, radius * fillT, Paint()..color = fill);
    }
    if (checkT > 0) {
      final path = Path()
        ..moveTo(size.width * 0.28, size.height * 0.52)
        ..lineTo(size.width * 0.44, size.height * 0.67)
        ..lineTo(size.width * 0.73, size.height * 0.36);
      final drawn = Path();
      for (final PathMetric metric in path.computeMetrics()) {
        drawn.addPath(
            metric.extractPath(0, metric.length * checkT), Offset.zero);
      }
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = check,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress ||
      old.ring != ring ||
      old.fill != fill ||
      old.check != check;
}
