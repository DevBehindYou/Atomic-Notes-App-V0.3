import 'dart:async';
import 'dart:math' as math;

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A destructive confirmation that cannot happen by accident (components
/// spec, Slide to confirm; replaces `utility/component/slide_to_confirm.dart`
/// when the Danger Zone migrates).
///
/// Two deliberate ways to confirm, and only these:
/// - **Drag** the thumb past [confirmAt] and lift the finger. Lifting earlier
///   snaps back in 180 ms; a cancelled drag (another gesture wins, the route
///   goes away) never confirms.
/// - **Activate twice**: a tap, a screen reader's activate action, or Enter or
///   Space with keyboard or switch access first *arms* the control
///   ("Tap again to confirm", announced), and a second activation within
///   [armedFor] confirms. Escape, the timeout, the app going to the
///   background, the route losing focus or a change of [label] or [target]
///   disarms it. Each key activation must be a fresh press: the auto-repeat
///   of a held key never arms or confirms.
///
/// While [onConfirmed] runs the thumb shows a spinner, the control reads
/// "Working" and ignores every input. An error from [onConfirmed] resets the
/// control and is reported, never swallowed.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.target,
    this.focusNode,
  });

  /// What the slide does, in sentence case: "wipe cloud notes" reads
  /// "Slide to wipe cloud notes".
  final String label;
  final Future<void> Function() onConfirmed;

  /// What would be destroyed. When it changes, an armed confirmation is
  /// withdrawn, so it can never apply to something else.
  final Object? target;
  final FocusNode? focusNode;

  static const double confirmAt = 0.92;
  static const Duration snapBack = Duration(milliseconds: 180);
  static const Duration armedFor = Duration(seconds: 4);
  static const Key thumbKey = Key('atomic-slide-to-confirm-thumb');

  static const String armedText = 'Tap again to confirm';
  static const String workingText = 'Working…';

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with WidgetsBindingObserver {
  static const double _track = 64;
  static const double _thumb = 56;
  static const double _inset = (_track - _thumb) / 2;

  double _offset = 0;
  double _travel = 1;
  bool _dragging = false;
  bool _running = false;
  bool _armed = false;
  bool _focused = false;

  /// True only when the dragging finger was actually lifted. Flutter's drag
  /// recognizer also reports a drag end when the pointer is cancelled or the
  /// widget goes away mid-drag; those must never confirm (review F02).
  bool _lifted = false;

  /// True while the key event being dispatched is an auto-repeat. A held
  /// Enter or Space is one activation, never the second (review R06).
  bool _keyRepeat = false;
  Timer? _disarm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another route on top: withdraw any armed confirmation.
    if (ModalRoute.of(context)?.isCurrent == false) _disarmNow();
  }

  @override
  void didUpdateWidget(SlideToConfirm old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label || old.target != widget.target) {
      _disarmNow();
      if (!_running) _resetDrag();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _disarmNow();
      if (!_running) _resetDrag();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disarm?.cancel();
    super.dispose();
  }

  void _disarmNow() {
    _disarm?.cancel();
    _disarm = null;
    if (_armed && mounted) setState(() => _armed = false);
  }

  void _resetDrag() {
    if (_offset != 0 || _dragging) {
      setState(() {
        _dragging = false;
        _offset = 0;
      });
    }
  }

  Future<void> _confirm() async {
    if (_running) return;
    _disarm?.cancel();
    setState(() {
      _offset = _travel;
      _dragging = false;
      _armed = false;
      _running = true;
    });
    unawaited(AtomicHaptics.play(AtomicHaptic.medium));
    try {
      await widget.onConfirmed();
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'atomic_notes ui',
        context: ErrorDescription('while confirming "${widget.label}"'),
      ));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _offset = 0;
        });
      }
    }
  }

  /// The drag ended: confirm only if the finger was lifted past the
  /// threshold, while the control is still on screen.
  void _release() {
    if (!mounted || _running) return;
    if (!_dragging || !_lifted) {
      _cancelDrag();
      return;
    }
    if (_offset / _travel >= SlideToConfirm.confirmAt) {
      _confirm();
    } else {
      _resetDrag();
    }
  }

  /// A drag that did not end with the finger lifting never confirms.
  void _cancelDrag() {
    if (mounted && !_running) _resetDrag();
  }

  /// A tap, a screen reader activation, or Enter/Space: arm, then confirm.
  void _activate() {
    if (_running) return;
    if (_armed) {
      _confirm();
      return;
    }
    setState(() => _armed = true);
    _disarm?.cancel();
    _disarm = Timer(SlideToConfirm.armedFor, _disarmNow);
  }

  /// Records whether the focused control's key event is an auto-repeat. It
  /// runs before the app's shortcuts turn the event into an activation.
  KeyEventResult _noteKey(FocusNode node, KeyEvent event) {
    _keyRepeat = event is KeyRepeatEvent;
    return KeyEventResult.ignored;
  }

  /// An activation key (Enter, Space, Select, a game button, or Enter on the
  /// web): only a fresh press counts.
  Object? _keyActivate() {
    final repeat = _keyRepeat;
    _keyRepeat = false;
    if (!repeat) _activate();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final follow = _dragging
        ? Duration.zero
        : AtomicMotion.move(context, SlideToConfirm.snapBack);
    final instruction = _running
        ? SlideToConfirm.workingText
        : _armed
            ? SlideToConfirm.armedText
            : 'Slide to ${widget.label}';
    return LayoutBuilder(builder: (context, box) {
      _travel = math.max(1.0, box.maxWidth - _thumb - _inset * 2);
      final progress = math.min(1.0, _offset / _travel);
      return Semantics(
        container: true,
        button: true,
        enabled: !_running,
        liveRegion: true,
        label: 'Slide to ${widget.label}',
        value: _running
            ? 'Working'
            : _armed
                ? 'Armed. Activate again to confirm'
                : null,
        onTap: _running ? null : _activate,
        child: ExcludeSemantics(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _noteKey,
            child: FocusableActionDetector(
              focusNode: widget.focusNode,
              enabled: !_running,
              mouseCursor: SystemMouseCursors.click,
              onShowFocusHighlight: (value) {
                if (_focused != value) setState(() => _focused = value);
              },
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) => _keyActivate()),
                ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
                    onInvoke: (_) => _keyActivate()),
                DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
                  _disarmNow();
                  return null;
                }),
              },
              child: CustomPaint(
                foregroundPainter: _focused ? _TrackFocusRing(c.focus) : null,
                child: Container(
                  height: _track,
                  decoration: BoxDecoration(
                      color: c.surfaceInset, borderRadius: AtomicRadius.pill),
                  child: ClipRRect(
                    borderRadius: AtomicRadius.pill,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        AnimatedContainer(
                          duration: follow,
                          curve: AtomicMotion.standardCurve,
                          width: _offset + _thumb + _inset * 2,
                          decoration: BoxDecoration(
                              color: c.danger, borderRadius: AtomicRadius.pill),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.only(
                                left: _thumb + _inset * 2,
                                right: AtomicSpace.x4),
                            child: Center(
                              child: Opacity(
                                opacity: _running || _armed ? 1 : 1 - progress,
                                child: Text(
                                  instruction,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: AtomicType.labelLarge.copyWith(
                                    color: _running
                                        ? c.onDanger
                                        : _armed
                                            ? c.dangerText
                                            : c.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: follow,
                          curve: AtomicMotion.standardCurve,
                          left: _offset + _inset,
                          child: Listener(
                            // Runs before the drag recognizer sees the event.
                            onPointerDown: (_) => _lifted = false,
                            onPointerUp: (_) => _lifted = true,
                            onPointerCancel: (_) => _lifted = false,
                            child: GestureDetector(
                              key: SlideToConfirm.thumbKey,
                              behavior: HitTestBehavior.opaque,
                              onTap: _running ? null : _activate,
                              onHorizontalDragStart: _running
                                  ? null
                                  : (_) => setState(() => _dragging = true),
                              onHorizontalDragUpdate: _running
                                  ? null
                                  : (details) => setState(() {
                                        _offset = math.min(
                                            _travel,
                                            math.max(0.0,
                                                _offset + details.delta.dx));
                                      }),
                              onHorizontalDragEnd:
                                  _running ? null : (_) => _release(),
                              onHorizontalDragCancel:
                                  _running ? null : _cancelDrag,
                              child: Container(
                                width: _thumb,
                                height: _thumb,
                                decoration: BoxDecoration(
                                    color: c.danger, shape: BoxShape.circle),
                                child: Center(
                                  child: _running
                                      ? SizedBox.square(
                                          dimension: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: c.onDanger),
                                        )
                                      : Icon(AtomicIcons.arrowRight,
                                          size: 24, color: c.onDanger),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _TrackFocusRing extends CustomPainter {
  _TrackFocusRing(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      AtomicRadius.pill.toRRect(Offset.zero & size).inflate(3 + 1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrackFocusRing old) => old.color != color;
}
