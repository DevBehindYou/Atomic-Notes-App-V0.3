import 'dart:async';

import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:flutter/widgets.dart';

/// The app-wide cap on continuously repeating decorative effects: at most
/// [AtomicMotion.maxAmbientLoops] run at once (ADR-011).
///
/// What it covers: every effect that uses [AmbientLoop], which is [Ambient]
/// (onboarding art, splash orbits, the QR scan line, the App info float) and
/// the sync orbit (`OrbitRing`). A loop without a slot shows a still frame
/// and starts as soon as a slot frees.
///
/// What it does not cover, by design: progress indicators that say work is
/// happening (`Skeleton`, `ProgressRing`, button spinners) and the mascot's
/// own clips (owned by `lib/mascot`). Finite transitions and interactive
/// animations never count.
abstract final class AmbientBudget {
  static final Set<Object> _holders = {};
  static final List<_Waiter> _waiting = [];

  /// Loops running now.
  static int get active => _holders.length;

  /// Whether [owner] holds a slot.
  @visibleForTesting
  static bool holds(Object owner) => _holders.contains(owner);

  static bool _acquire(Object owner) {
    if (_holders.contains(owner)) return true;
    if (_holders.length >= AtomicMotion.maxAmbientLoops) return false;
    _holders.add(owner);
    return true;
  }

  static void _release(Object owner) {
    if (!_holders.remove(owner)) return;
    // The first waiter retries after the current frame work, never inside
    // another widget's dispose or build.
    if (_waiting.isNotEmpty) {
      final next = _waiting.removeAt(0);
      scheduleMicrotask(next.retry);
    }
  }

  static void _wait(_Waiter waiter) {
    if (!_waiting.contains(waiter)) _waiting.add(waiter);
  }

  static void _unwait(_Waiter waiter) => _waiting.remove(waiter);

  @visibleForTesting
  static void reset() {
    _holders.clear();
    _waiting.clear();
  }
}

class _Waiter {
  _Waiter(this.retry);
  final VoidCallback retry;
}

/// Shared ownership of one budgeted loop for a [State]: it runs only while
/// the effect wants to loop ([wantsLoop]), the app is in the foreground,
/// tickers are on (route shown), reduced motion is off, and the
/// [AmbientBudget] grants a slot. Turning reduced motion on, covering the
/// route or backgrounding the app stops it and frees the slot at once.
mixin AmbientLoop<T extends StatefulWidget> on State<T> {
  /// Whether the effect wants to loop now (for example, only while busy).
  bool get wantsLoop;

  /// Start or stop the repeating controller. Called only on a change.
  void startLoop();
  void stopLoop();

  bool _holding = false;
  late final _Waiter _waiter = _Waiter(() {
    if (mounted) updateLoop();
  });
  late final _LifecycleListener _lifecycle = _LifecycleListener(() {
    if (mounted) updateLoop();
  });

  /// Whether the loop is running (it holds a budget slot).
  bool get looping => _holding;

  bool get _resumed {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Re-evaluates whether to run. Call after [wantsLoop] changes. [rebuild]
  /// is false where a build follows anyway (dependency changes).
  void updateLoop({bool rebuild = true}) {
    final run = mounted &&
        wantsLoop &&
        _resumed &&
        TickerMode.valuesOf(context).enabled &&
        !AtomicMotion.reduced(context);
    if (run && !_holding) {
      _holding = AmbientBudget._acquire(this);
      if (_holding) {
        AmbientBudget._unwait(_waiter);
        startLoop();
        if (rebuild && mounted) setState(() {});
      } else {
        AmbientBudget._wait(_waiter);
      }
    } else if (!run) {
      AmbientBudget._unwait(_waiter);
      if (_holding) {
        _holding = false;
        stopLoop();
        AmbientBudget._release(this);
        if (rebuild && mounted) setState(() {});
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    updateLoop(rebuild: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycle);
    AmbientBudget._unwait(_waiter);
    if (_holding) {
      _holding = false;
      AmbientBudget._release(this);
    }
    super.dispose();
  }
}

class _LifecycleListener with WidgetsBindingObserver {
  _LifecycleListener(this.onChange);
  final VoidCallback onChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChange();
}

/// A gentle loop for screens that are moments rather than work surfaces.
/// [builder] gets the loop position `t` (0 to 1, ambient curve) while a
/// budget slot is held, and a still frame at 0 otherwise.
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
    with SingleTickerProviderStateMixin, AmbientLoop<Ambient> {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period);

  @override
  bool get wantsLoop => true;

  @override
  void startLoop() => _controller.repeat(reverse: widget.reverse);

  @override
  void stopLoop() {
    _controller
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
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
