import 'dart:math' as math;

import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:flutter/widgets.dart';

/// Owns a screen's entrance: one controller per route, run once when the
/// route is first shown, never again on return from a pushed route or on
/// resume (CA02). Under reduced motion everything is shown at once.
///
/// Put it at the top of a page, and wrap top-level blocks in [Entrance] and
/// list items in [Stagger].
class EntranceGroup extends StatefulWidget {
  const EntranceGroup({super.key, required this.child});

  final Widget child;

  /// Long enough for the last block and the last staggered item.
  static final Duration total = Duration(
    milliseconds: math.max(
      _blockStart(_maxBlocks - 1) + AtomicMotion.entrance.inMilliseconds,
      _itemStart(AtomicMotion.staggerMaxItems - 1) +
          AtomicMotion.entrance.inMilliseconds,
    ),
  );

  static const int _maxBlocks = 8;

  static int _blockStart(int index) =>
      math.min(index, _maxBlocks - 1) *
      AtomicMotion.entranceStep.inMilliseconds;

  static int _itemStart(int index) =>
      AtomicMotion.staggerDelay.inMilliseconds +
      index * AtomicMotion.staggerStep.inMilliseconds;

  static Animation<double>? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EntranceScope>()?.animation;

  @override
  State<EntranceGroup> createState() => _EntranceGroupState();
}

class _EntranceGroupState extends State<EntranceGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: EntranceGroup.total);
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AtomicMotion.reduced(context)) {
      // Also cancels an entrance already running (ADR-011).
      _controller.value = 1;
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        _controller.forward();
      } else {
        _controller.value = 1;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _EntranceScope(animation: _controller, child: widget.child);
}

class _EntranceScope extends InheritedWidget {
  const _EntranceScope({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_EntranceScope old) => old.animation != animation;
}

/// A top-level block of a screen: rises 18 dp from 98.5 % scale and fades
/// in over `entrance` with the expressive curve, [index] × 60 ms after the
/// first. Shown as is outside an [EntranceGroup].
class Entrance extends StatelessWidget {
  const Entrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final group = EntranceGroup._of(context);
    if (group == null) return child;
    final start = EntranceGroup._blockStart(index);
    return _Rise(
      animation: _interval(group, start),
      rise: AtomicMotion.entranceRise,
      fromScale: 0.985,
      child: child,
    );
  }
}

/// An item of a list inside a screen: the first [AtomicMotion.staggerMaxItems]
/// items fade in and rise 8 dp, 45 ms apart, starting 200 ms into the
/// entrance. Later items are shown as they are.
class Stagger extends StatelessWidget {
  const Stagger({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final group = EntranceGroup._of(context);
    if (group == null || index >= AtomicMotion.staggerMaxItems) return child;
    return _Rise(
      animation: _interval(group, EntranceGroup._itemStart(index)),
      rise: 8,
      fromScale: 1,
      child: child,
    );
  }
}

Animation<double> _interval(Animation<double> parent, int startMs) {
  final total = EntranceGroup.total.inMilliseconds;
  final end = startMs + AtomicMotion.entrance.inMilliseconds;
  return parent.drive(CurveTween(
    curve: Interval(startMs / total, math.min(1, end / total),
        curve: AtomicMotion.expressiveCurve),
  ));
}

class _Rise extends StatelessWidget {
  const _Rise({
    required this.animation,
    required this.rise,
    required this.fromScale,
    required this.child,
  });

  final Animation<double> animation;
  final double rise;
  final double fromScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final t = animation.value;
          return Transform.translate(
            offset: Offset(0, rise * (1 - t)),
            child: Transform.scale(
              scale: fromScale + (1 - fromScale) * t,
              child: child,
            ),
          );
        },
      ),
    );
  }
}
