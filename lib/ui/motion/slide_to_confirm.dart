import 'dart:async';
import 'dart:math' as math;

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:flutter/material.dart';

/// A confirmation that cannot happen by accident (components spec, Slide to
/// confirm; replaces `utility/component/slide_to_confirm.dart` when the
/// Danger Zone migrates). The thumb is dragged along the track; letting go
/// before [confirmAt] snaps it back in 180 ms and nothing runs.
///
/// Two more ways in, for people who cannot drag (UX05):
/// - screen readers get a slider whose "increase" action confirms;
/// - a tap on the thumb arms it ("Tap again to confirm"), and a second tap
///   within [armedFor] confirms.
///
/// On completion the track fills with danger behind the thumb, a medium
/// haptic plays, and a spinner replaces the arrow until [onConfirmed] ends.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
  });

  /// What the slide does, in sentence case: "wipe cloud notes" reads
  /// "Slide to wipe cloud notes".
  final String label;
  final Future<void> Function() onConfirmed;

  static const double confirmAt = 0.92;
  static const Duration snapBack = Duration(milliseconds: 180);
  static const Duration armedFor = Duration(seconds: 4);
  static const Key thumbKey = Key('atomic-slide-to-confirm-thumb');

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  static const double _track = 64;
  static const double _thumb = 56;
  static const double _inset = (_track - _thumb) / 2;

  double _offset = 0;
  double _travel = 1;
  bool _dragging = false;
  bool _running = false;
  bool _armed = false;
  Timer? _disarm;

  @override
  void dispose() {
    _disarm?.cancel();
    super.dispose();
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
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _offset = 0;
        });
      }
    }
  }

  void _release() {
    if (_offset / _travel >= SlideToConfirm.confirmAt) {
      _confirm();
    } else {
      setState(() {
        _dragging = false;
        _offset = 0;
      });
    }
  }

  void _tap() {
    if (_running) return;
    if (_armed) {
      _confirm();
      return;
    }
    setState(() => _armed = true);
    _disarm?.cancel();
    _disarm = Timer(SlideToConfirm.armedFor, () {
      if (mounted) setState(() => _armed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final follow = _dragging
        ? Duration.zero
        : AtomicMotion.move(context, SlideToConfirm.snapBack);
    final instruction = _running
        ? 'Working…'
        : _armed
            ? 'Tap again to confirm'
            : 'Slide to ${widget.label}';
    return LayoutBuilder(builder: (context, box) {
      _travel = math.max(1.0, box.maxWidth - _thumb - _inset * 2);
      final progress = math.min(1.0, _offset / _travel);
      return Semantics(
        slider: true,
        label: 'Slide to ${widget.label}',
        value: _running ? 'Working' : '${(progress * 100).round()}%',
        increasedValue: '100%',
        onIncrease: _running ? null : _confirm,
        onTap: _running ? null : _tap,
        child: ExcludeSemantics(
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
                          left: _thumb + _inset * 2, right: AtomicSpace.x4),
                      child: Center(
                        child: Opacity(
                          opacity: _running ? 1 : 1 - progress,
                          child: Text(
                            instruction,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: AtomicType.labelLarge.copyWith(
                                color: _running ? c.onDanger : c.textSecondary),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: follow,
                    curve: AtomicMotion.standardCurve,
                    left: _offset + _inset,
                    child: GestureDetector(
                      key: SlideToConfirm.thumbKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: _tap,
                      onHorizontalDragStart: _running
                          ? null
                          : (_) => setState(() => _dragging = true),
                      onHorizontalDragUpdate: _running
                          ? null
                          : (details) => setState(() {
                                _offset = math.min(_travel,
                                    math.max(0.0, _offset + details.delta.dx));
                              }),
                      onHorizontalDragEnd: _running ? null : (_) => _release(),
                      onHorizontalDragCancel: _running ? null : _release,
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
                                      strokeWidth: 2.5, color: c.onDanger),
                                )
                              : Icon(AtomicIcons.arrowRight,
                                  size: 24, color: c.onDanger),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
