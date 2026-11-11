import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/fields/atomic_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A two-factor code: six digits from an authenticator app, or (with
/// [recovery]) a single-use recovery code `XXXXX-XXXXX`. Keeps the input
/// rules of `TwoFactorCodeField`: digits only and six long, or letters,
/// digits and a hyphen, eleven long, upper-cased; paste works in both.
///
/// The page clears [controller] after a wrong code, as today.
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    this.recovery = false,
    this.enabled = true,
    this.autofocus = false,
    this.errorText,
    this.onCompleted,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool recovery;
  final bool enabled;
  final bool autofocus;
  final String? errorText;

  /// Called once six digits are typed. Not used for recovery codes, which
  /// have no fixed moment of completion.
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onSubmitted;

  static final List<TextInputFormatter> digitFormatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(6),
  ];

  static final List<TextInputFormatter> recoveryFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
    LengthLimitingTextInputFormatter(11),
    const _UpperCase(),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final codeStyle = AtomicType.mono.copyWith(fontSize: 28, letterSpacing: 6);
    return AtomicTextField(
      controller: controller,
      label: recovery ? 'Recovery code' : '6-digit code',
      enabled: enabled,
      autofocus: autofocus,
      errorText: errorText,
      keyboardType: recovery ? TextInputType.text : TextInputType.number,
      textCapitalization:
          recovery ? TextCapitalization.characters : TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: recovery ? recoveryFormatters : digitFormatters,
      onChanged: (value) {
        if (!recovery && value.length == 6) onCompleted?.call(value);
      },
      onSubmitted: onSubmitted,
      hintText: recovery ? 'XXXXX-XXXXX' : '000000',
      textAlign: TextAlign.center,
      style: codeStyle.copyWith(color: c.textPrimary),
      hintStyle: codeStyle.copyWith(color: c.textSecondary),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  const _UpperCase();

  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
