import 'dart:ui' show lerpDouble;

import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:flutter/widgets.dart';

/// Where an editor route grows from and returns to, in the coordinates of the
/// navigator that shows it. Null when that place no longer exists (the card
/// was deleted, filtered out or rebuilt elsewhere): the route then fades.
typedef EditorOrigin = Rect? Function();

/// The bounds of [context]'s render box inside [navigator], or null when the
/// element or its box is gone. For building an [EditorOrigin].
Rect? editorOriginRect(BuildContext context, NavigatorState navigator) {
  if (!context.mounted || !navigator.mounted) return null;
  final box = context.findRenderObject();
  final space = navigator.context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  if (space is! RenderBox || !space.attached) return null;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: space);
  return topLeft & box.size;
}

/// The editor's full-screen route (motion spec, Editor open): a container
/// transform. The origin's bounds and radius grow to the whole screen while
/// its colour cross-fades to the editor's canvas, and the content fades in
/// over the last 60 %. Close reverses into the origin as it is then, or fades
/// out when it has gone.
///
/// [duration] comes from the caller through `AtomicMotion.move`, so reduced
/// motion opens and closes at once. The page itself is unchanged: it keeps its
/// own layout, Back handling and result.
class EditorRoute<T> extends PageRoute<T> {
  EditorRoute({
    required this.builder,
    required Duration duration,
    required this.canvas,
    this.origin,
    this.originColor,
    this.originRadius = AtomicRadius.large,
    super.settings,
  }) : _duration = duration;

  final WidgetBuilder builder;
  final EditorOrigin? origin;

  /// The origin's fill, cross-faded to [canvas]. Null keeps [canvas].
  final Color? originColor;
  final Color canvas;

  /// The origin's corner radius; null means a circle (the new-note button).
  final double? originRadius;

  final Duration _duration;

  /// The origin measured when the open or close started.
  Rect? _from;

  @override
  Duration get transitionDuration => _duration;

  @override
  Duration get reverseTransitionDuration => _duration;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  TickerFuture didPush() {
    _from = origin?.call();
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    // Return into where the origin is now, or fade if it has gone.
    _from = origin?.call();
    return super.didPop(result);
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final progress = CurvedAnimation(
      parent: animation,
      curve: AtomicMotion.emphasizedCurve,
      reverseCurve: AtomicMotion.emphasizedCurve.flipped,
    );
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: progress,
        child: child,
        builder: (context, child) {
          final t = progress.value;
          final full = Offset.zero & constraints.biggest;
          final from = _from;
          final Rect rect;
          final double radius;
          final double content;
          final Color fill;
          double opacity = 1;
          if (from == null) {
            rect = full;
            radius = 0;
            content = 1;
            fill = canvas;
            opacity = t;
          } else {
            rect = Rect.lerp(from, full, t)!;
            radius = lerpDouble(originRadius ?? from.shortestSide / 2, 0, t)!;
            content = const Interval(0.4, 1).transform(t);
            fill = Color.lerp(originColor ?? canvas, canvas, t)!;
          }
          return Opacity(
            opacity: opacity,
            child: ClipRRect(
              key: const ValueKey('editor-route-clip'),
              clipper: _RRectClipper(
                  RRect.fromRectAndRadius(rect, Radius.circular(radius))),
              child: ColoredBox(
                color: fill,
                child: Opacity(
                  key: const ValueKey('editor-route-content'),
                  opacity: content,
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RRectClipper extends CustomClipper<RRect> {
  const _RRectClipper(this.rrect);

  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(_RRectClipper oldClipper) => oldClipper.rrect != rrect;
}
