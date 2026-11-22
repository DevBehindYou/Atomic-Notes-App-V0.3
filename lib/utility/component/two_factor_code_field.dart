import 'dart:math' as math;

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/fields/code_field.dart';
import 'package:flutter/material.dart';

/// The box a two-factor code is typed into: six digits from an authenticator
/// app, or (with [recovery]) one of the single-use recovery codes.
///
/// Six digits show as six 48 × 56 pill cells (screens spec, Two-factor gate)
/// over one real text field, so typing, paste, the keyboard's Done key,
/// one-time-code autofill and screen readers all work on a single input.
/// Recovery codes use the shared [CodeField]. The input rules are the ones
/// [CodeField] keeps: digits only and six long, or letters, digits and a
/// hyphen, eleven long, upper-cased.
class TwoFactorCodeField extends StatefulWidget {
  final TextEditingController controller;
  final bool recovery;
  final bool enabled;
  final bool autofocus;

  /// Shown under the field with an alert icon; the cells take a danger
  /// border.
  final String? errorText;

  /// Called once six digits have been typed. Not used for recovery codes,
  /// which have no fixed moment of completion.
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onSubmitted;

  const TwoFactorCodeField({
    required this.controller,
    this.recovery = false,
    this.enabled = true,
    this.autofocus = false,
    this.errorText,
    this.onCompleted,
    this.onSubmitted,
    super.key,
  });

  static const int digits = 6;
  static const double cellWidth = 48;
  static const double cellHeight = 56;
  static const double cellGap = 8;

  static const String digitLabel = '6-digit code';
  static const String recoveryLabel = 'Recovery code';

  /// The key of digit cell [index], for tests.
  static ValueKey<String> cellKey(int index) => ValueKey('tf-code-cell-$index');

  @override
  State<TwoFactorCodeField> createState() => _TwoFactorCodeFieldState();
}

class _TwoFactorCodeFieldState extends State<TwoFactorCodeField> {
  final FocusNode _focus = FocusNode(debugLabel: 'two-factor code');

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(TwoFactorCodeField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (widget.recovery) return;
    // The cursor is hidden, so typing always goes at the end.
    final controller = widget.controller;
    final end = controller.text.length;
    final selection = controller.selection;
    if (selection.isValid &&
        (!selection.isCollapsed || selection.baseOffset != end)) {
      controller.selection = TextSelection.collapsed(offset: end);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.recovery) {
      return CodeField(
        controller: widget.controller,
        recovery: true,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        errorText: widget.errorText,
        onSubmitted: widget.onSubmitted,
      );
    }
    final c = context.colors;
    final error = widget.errorText;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding:
                const EdgeInsets.only(left: AtomicSpace.x1, bottom: AtomicSpace.x2),
            child: Text(TwoFactorCodeField.digitLabel,
                style: AtomicType.bodySmall.copyWith(color: c.textSecondary)),
          ),
          LayoutBuilder(builder: (context, constraints) {
            const gap = TwoFactorCodeField.cellGap;
            const n = TwoFactorCodeField.digits;
            final cell = math.min(TwoFactorCodeField.cellWidth,
                (constraints.maxWidth - gap * (n - 1)) / n);
            return Center(
              child: SizedBox(
                width: cell * n + gap * (n - 1),
                height: TwoFactorCodeField.cellHeight,
                child: Stack(
                  children: [
                    // A tap between cells still focuses the field.
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTap: widget.enabled ? _focus.requestFocus : null,
                      ),
                    ),
                    Positioned.fill(child: Center(child: _input())),
                    IgnorePointer(
                      child: ExcludeSemantics(
                        child: Row(
                          children: [
                            for (var i = 0; i < n; i++) ...[
                              if (i > 0) const SizedBox(width: gap),
                              _Cell(
                                key: TwoFactorCodeField.cellKey(i),
                                width: cell,
                                digit: i < widget.controller.text.length
                                    ? widget.controller.text[i]
                                    : null,
                                active: widget.enabled &&
                                    _focus.hasFocus &&
                                    i ==
                                        math.min(widget.controller.text.length,
                                            n - 1),
                                enabled: widget.enabled,
                                error: error != null,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(
                  top: AtomicSpace.x2, left: AtomicSpace.x1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(AtomicIcons.alertCircle,
                        size: 16, color: c.dangerText),
                  ),
                  const SizedBox(width: AtomicSpace.x1),
                  Expanded(
                    child: Text(error,
                        style:
                            AtomicType.bodySmall.copyWith(color: c.dangerText)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The real input under the cells. Its text and cursor are invisible; the
  /// cells draw the digits. Text scaling is off here only: the cells scale
  /// their own digits to fit.
  Widget _input() {
    const invisible = TextStyle(
      fontFamily: AtomicFonts.mono,
      fontSize: 28,
      color: Colors.transparent,
    );
    return MediaQuery.withNoTextScaling(
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        showCursor: false,
        cursorColor: Colors.transparent,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: CodeField.digitFormatters,
        style: invisible,
        decoration: const InputDecoration(
          isCollapsed: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          counterText: '',
        ),
        onChanged: (value) {
          if (value.length == TwoFactorCodeField.digits) {
            widget.onCompleted?.call(value);
          }
        },
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

/// One digit cell: a 48 × 56 inset pill with the digit in `mono`. The next
/// cell to fill takes the 2 dp focus border; a wrong code turns them all
/// danger.
class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.width,
    required this.digit,
    required this.active,
    required this.enabled,
    required this.error,
  });

  final double width;
  final String? digit;
  final bool active;
  final bool enabled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final digit = this.digit;
    final (Color border, double stroke) = !enabled
        ? (c.outline, 1)
        : error
            ? (c.danger, 2)
            : active
                ? (c.focus, 2)
                : digit != null
                    ? (c.outlineStrong, 1)
                    : (c.outline, 1);
    return AnimatedContainer(
      duration: AtomicMotion.fade(context, AtomicMotion.quick),
      curve: AtomicMotion.standardCurve,
      width: width,
      height: TwoFactorCodeField.cellHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceInset,
        borderRadius: AtomicRadius.pill,
        border: Border.all(color: border, width: stroke),
      ),
      child: AnimatedSwitcher(
        duration: AtomicMotion.move(context, AtomicMotion.quick),
        switchInCurve: AtomicMotion.overshootCurve,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: digit == null
            ? const SizedBox.shrink(key: ValueKey('empty'))
            : Padding(
                key: ValueKey(digit),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    digit,
                    style: AtomicType.mono.copyWith(
                      fontSize: 28,
                      height: 1.2,
                      color: enabled ? c.textPrimary : c.textDisabled,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
