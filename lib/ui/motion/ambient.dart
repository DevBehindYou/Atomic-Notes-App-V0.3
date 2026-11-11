import 'dart:math' as math;

import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:flutter/widgets.dart';

/// The app-wide cap on continuously repeating effects: at most
/// [AtomicMotion.maxAmbientLoops] run at once (ADR-011). Finite transitions
/// and interactive animations do not count.
abstract final class AmbientBudget {
  static int _active = 0;

  static int get active => _active;

  static bool _acquire() {
    if (_active >= AtomicMotion.maxAmbientLoops) return false;
    _active++;
    return true;
  }

  static void _release() => _active = math.max(0, _active - 1);

  @visibleForTesting
  static void reset() => _active = 0;
}

/// A gentle loop for screens that are moments rather than work surfaces
/// (onboarding art, splash orbits, the QR scan line, the App info float).
///
/// It runs only while the app is in the foreground, its route is shown
/// (tickers not muted), reduced motion is off, and the [AmbientBudget] has
/// room; otherwise [builder] gets a still frame at 0. Turning reduced
/// motion on stops it at once.
class Ambient extends StatefulWidget {
  const Ambient({
    super.key,
    required this.period,
    required this.builder,
    this.reverse = true,
    this.child,
  });

  /// 2 to 18 seconds (motion spec, Ambient life).
  final Duration period;

  /// Builds a frame for loop position `t`, from 0 to 1, with the ambient
  /// curve applied. [child] is built once and passed through.
  final Widget Function(BuildContext context, double t, Widget? child) builder;
  final bool reverse;
  final Widget? child;

  @override
  State<Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<Ambient>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period);
  bool _holding = false;

  bool get _resumed {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _update() {
    final run = mounted &&
        _resumed &&
        TickerMode.valuesOf(context).enabled &&
        !AtomicMotion.reduced(context);
    if (run && !_holding) {
      _holding = AmbientBudget._acquire();
      if (_holding) _controller.repeat(reverse: widget.reverse);
    } else if (!run && _holding) {
      _controller
        ..stop()
        ..value = 0;
      AmbientBudget._release();
      _holding = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _update();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_holding) AmbientBudget._release();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) => widget.builder(
          context,
          AtomicMotion.ambientCurve.transform(_controller.value),
          child,
        ),
      ),
    );
  }
}
