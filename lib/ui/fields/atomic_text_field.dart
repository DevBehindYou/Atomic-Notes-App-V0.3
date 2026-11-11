import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The redesign's input decoration (components spec, Text field): an inset
/// fill with a 1 dp strong outline, a 2 dp focus border, and a 2 dp danger
/// border with the message below behind an alert icon.
abstract final class AtomicInputDecoration {
  static InputDecoration of(
    BuildContext context, {
    String? hintText,
    String? errorText,
    bool multiline = false,
    Widget? prefixIcon,
    Widget? suffixIcon,
    TextStyle? hintStyle,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final c = context.colors;
    final radius = multiline ? AtomicRadius.mediumAll : AtomicRadius.pill;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      filled: true,
      fillColor: c.surfaceInset,
      hintText: hintText,
      hintStyle:
          hintStyle ?? AtomicType.bodyLarge.copyWith(color: c.textSecondary),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(
              horizontal: AtomicSpace.x5, vertical: AtomicSpace.x4),
      enabledBorder: border(c.outlineStrong, 1),
      disabledBorder: border(c.outline, 1),
      focusedBorder: border(c.focus, 2),
      errorBorder: border(c.danger, 2),
      focusedErrorBorder: border(c.danger, 2),
      error: errorText == null
          ? null
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(AtomicIcons.alertCircle,
                      size: 16, color: c.dangerText),
                ),
                const SizedBox(width: AtomicSpace.x1),
                Expanded(
                  child: Text(errorText,
                      style:
                          AtomicType.bodySmall.copyWith(color: c.dangerText)),
                ),
              ],
            ),
    );
  }
}

/// A labelled text field (components spec, Text field). The label sits
/// above the field; placeholders are real examples.
class AtomicTextField extends StatelessWidget {
  const AtomicTextField({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.errorText,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.sentences,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.suffixIcon,
    this.style,
    this.hintStyle,
    this.textAlign = TextAlign.start,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final String? errorText;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final bool enableSuggestions;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;

  /// Defaults to `bodyLarge` in the primary text colour.
  final TextStyle? style;

  /// Defaults to `bodyLarge` in the secondary text colour.
  final TextStyle? hintStyle;
  final TextAlign textAlign;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = this.label;
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofillHints: autofillHints,
      textAlign: textAlign,
      cursorColor: c.textPrimary,
      style: style ?? AtomicType.bodyLarge.copyWith(color: c.textPrimary),
      decoration: AtomicInputDecoration.of(
        context,
        hintText: hintText,
        errorText: errorText,
        multiline: (maxLines ?? 2) > 1 && !obscureText,
        suffixIcon: suffixIcon,
        hintStyle: hintStyle,
      ),
    );
    if (label == null) return field;
    // One node: the label is read as the text field's name.
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(
                left: AtomicSpace.x1, bottom: AtomicSpace.x2),
            child: Text(label,
                style: AtomicType.bodySmall.copyWith(color: c.textSecondary)),
          ),
          field,
        ],
      ),
    );
  }
}

/// A recovery phrase, typed or pasted: fixed-width words, no autocorrect, no
/// suggestions, never capitalised.
class PhraseField extends StatelessWidget {
  const PhraseField({
    super.key,
    required this.controller,
    this.label = 'Recovery phrase',
    this.hintText,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AtomicTextField(
      controller: controller,
      label: label,
      hintText: hintText,
      errorText: errorText,
      enabled: enabled,
      autofocus: autofocus,
      minLines: 3,
      maxLines: 6,
      keyboardType: TextInputType.visiblePassword,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: AtomicType.mono.copyWith(color: context.colors.textPrimary),
    );
  }
}
