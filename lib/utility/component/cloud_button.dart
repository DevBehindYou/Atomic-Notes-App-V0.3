import 'dart:math' as math;

import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

/// Sync action in the app bar. Busy includes connectivity checks and receiving
/// changes; the animation indicates activity, not confirmed uploads.
/// [clr] remains in the API for existing callers; colours use the design tokens.
class CloudButton extends StatelessWidget {
  final VoidCallback action;
  final VoidCallback? onLongPress;
  final String ico;
  final int clr;
  final bool isLoading;
  const CloudButton({
    required this.ico,
    required this.action,
    required this.clr,
    required this.isLoading,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      // Busy disables sync, but the optional Energy action remains available.
      enabled: !isLoading || onLongPress != null,
      label: 'Sync now',
      value: isLoading ? 'Syncing' : null,
      hint: onLongPress == null ? null : 'Long press to open Atomic Energy',
      onTap: isLoading ? null : action,
      onLongPress: onLongPress,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: isLoading ? null : action,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
              child: Container(
            key: const ValueKey('cloud-button-surface'),
            height: 38,
            width: 46,
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: isLoading ? AppColors.ink : AppColors.signal,
              borderRadius: AppRadius.std,
              border: Border.all(color: AppColors.ink, width: AppStroke.rule),
            ),
            child: Center(
                child: SizedBox.square(
                    dimension: 20,
                    child: isLoading
                        ? const Center(child: _SyncActivityRing())
                        : SvgPicture.asset(
                            ico,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ))),
          )),
        ),
      ),
    );
  }
}

/// Three rounded white segments drawn without a GIF decoder. The controller
/// exists only while the parent control is busy, and pauses off-screen.
class _SyncActivityRing extends StatefulWidget {
  const _SyncActivityRing();

  @override
  State<_SyncActivityRing> createState() => _SyncActivityRingState();
}

class _SyncActivityRingState extends State<_SyncActivityRing>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateRotation();
  }

  void _updateRotation() {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    if (_foreground && TickerMode.valuesOf(context).enabled && !reduceMotion) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
      _rotation.value = 0;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateRotation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _rotation,
        builder: (_, __) => CustomPaint(
          key: const ValueKey('cloud-sync-ring'),
          size: const Size.square(22),
          painter: _SyncRingPainter(_rotation.value * math.pi * 2),
        ),
      );
}

class _SyncRingPainter extends CustomPainter {
  const _SyncRingPainter(this.angle);
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2 - 2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    const segment = math.pi * 2 / 3;
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(rect, angle + i * segment, segment - 0.45, false, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _SyncRingPainter oldDelegate) =>
      oldDelegate.angle != angle;
}
