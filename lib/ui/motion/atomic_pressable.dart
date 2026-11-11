import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:flutter/widgets.dart';

/// The one touch surface of the redesign. Every tappable `lib/ui` widget
/// wraps it, so press, focus, target size and role are the same everywhere.
///
/// - Press: [child] scales to [pressScale] over [AtomicMotion.pressIn], then
///   returns with a bounded overshoot over [AtomicMotion.pressOut] (ADR-011).
///   Only the child scales: the hit area and the layout stay put, and the
///   return never blocks the next tap. Under reduced motion nothing scales.
/// - Focus: a 3 dp ring in the focus colour, 3 dp outside the child, while
///   it has keyboard or switch-access focus.
/// - Target: at least [minSize] square, with a smaller child centred.
/// - Semantics: one node, a button unless [button] is false (switches and
///   checkboxes report [toggled] or [checked] instead), with [selected],
///   [toggled] or [checked] when given.
///
/// Disabled when both [onTap] and [onLongPress] are null.
class AtomicPressable extends StatefulWidget {
  const AtomicPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.semanticsLabel,
    this.excludeSemantics = false,
    this.selected,
    this.toggled,
    this.checked,
    this.button = true,
    this.haptic = AtomicHaptic.none,
    this.pressScale = AtomicMotion.pressScale,
    this.borderRadius = AtomicRadius.pill,
    this.minSize = AtomicSpace.minTarget,
    this.focusNode,
    this.autofocus = false,
  });

  /// Built once by the caller; pressing never rebuilds it.
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Read instead of, or before, the child's own text.
  final String? semanticsLabel;

  /// Hides the child's semantics, for a child whose text [semanticsLabel]
  /// already says. Leave false when the child holds its own controls.
  final bool excludeSemantics;
  final bool? selected;
  final bool? toggled;
  final bool? checked;
  final bool button;

  /// Played on tap, not on long-press.
  final AtomicHaptic haptic;
  final double pressScale;

  /// The shape of the focus ring.
  final BorderRadius borderRadius;
  final double minSize;
  final FocusNode? focusNode;
  final bool autofocus;

  bool get enabled => onTap != null || onLongPress != null;

  @override
  State<AtomicPressable> createState() => _AtomicPressableState();
}

class _AtomicPressableState extends State<AtomicPressable> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  void _tap() {
    final onTap = widget.onTap;
    if (onTap == null) return;
    AtomicHaptics.play(widget.haptic);
    onTap();
  }

  void _longPress() {
    _setPressed(false);
    widget.onLongPress?.call();
  }

  @override
  void didUpdateWidget(AtomicPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final pressed = _pressed && enabled && !AtomicMotion.reduced(context);
    final visual = CustomPaint(
      foregroundPainter: _focused
          ? _FocusRing(context.colors.focus, widget.borderRadius)
          : null,
      child: AnimatedScale(
        scale: pressed ? widget.pressScale : 1,
        duration: pressed ? AtomicMotion.pressIn : AtomicMotion.pressOut,
        curve:
            pressed ? AtomicMotion.standardCurve : AtomicMotion.overshootCurve,
        child: widget.child,
      ),
    );
    return Semantics(
      container: true,
      button: widget.button,
      enabled: enabled,
      selected: widget.selected,
      toggled: widget.toggled,
      checked: widget.checked,
      label: widget.semanticsLabel,
      excludeSemantics: widget.excludeSemantics,
      onTap: widget.onTap == null ? null : _tap,
      onLongPress: widget.onLongPress == null ? null : _longPress,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _tap();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onTap: widget.onTap == null ? null : _tap,
          onLongPress: widget.onLongPress == null ? null : _longPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minWidth: widget.minSize, minHeight: widget.minSize),
            child: Center(widthFactor: 1, heightFactor: 1, child: visual),
          ),
        ),
      ),
    );
  }
}

class _FocusRing extends CustomPainter {
  _FocusRing(this.color, this.radius);

  static const double width = 3;
  static const double gap = 3;

  final Color color;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      radius.toRRect(Offset.zero & size).inflate(gap + width / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FocusRing old) =>
      old.color != color || old.radius != radius;
}
