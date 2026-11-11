import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/fields/atomic_text_field.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';

/// The Home search pill (components spec, Search): a 48 dp raised field with
/// a search icon, a clear button while there is text, and Cancel.
///
/// The page owns [controller] and [focusNode] and keeps the existing
/// `GlobalKey` reparenting that preserves focus across layout changes; this
/// widget only draws the field.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = 'Search notes or #tags',
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Shows Cancel to the right of the field. The page clears the query.
  final VoidCallback? onCancel;

  static const double height = 48;

  void _clear() {
    controller.clear();
    onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final field = ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        cursorColor: c.textPrimary,
        style: AtomicType.bodyLarge.copyWith(color: c.textPrimary),
        decoration: AtomicInputDecoration.of(
          context,
          hintText: hintText,
          contentPadding: const EdgeInsets.symmetric(vertical: AtomicSpace.x3),
          prefixIcon:
              Icon(AtomicIcons.search, size: 20, color: c.textSecondary),
          suffixIcon: value.text.isEmpty
              ? null
              : Tooltip(
                  message: 'Clear search',
                  excludeFromSemantics: true,
                  child: AtomicPressable(
                    onTap: _clear,
                    semanticsLabel: 'Clear search',
                    excludeSemantics: true,
                    child:
                        Icon(AtomicIcons.x, size: 20, color: c.textSecondary),
                  ),
                ),
        ).copyWith(
          fillColor: c.surfaceRaised,
          enabledBorder: OutlineInputBorder(
            borderRadius: AtomicRadius.pill,
            borderSide: BorderSide(color: c.surfaceRaised),
          ),
        ),
      ),
    );
    final onCancel = this.onCancel;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: Row(
        children: [
          Expanded(child: field),
          if (onCancel != null) ...[
            const SizedBox(width: AtomicSpace.x1),
            AtomicButton.text(
                label: 'Cancel',
                size: AtomicButtonSize.compact,
                onPressed: onCancel),
          ],
        ],
      ),
    );
  }
}
