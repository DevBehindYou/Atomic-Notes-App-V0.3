import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/material.dart';

/// An action on a snackbar: a small accent pill with a black label.
class AtomicSnackBarAction {
  const AtomicSnackBarAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// A floating message (components spec, Snackbar; replaces `MySnackBar`):
/// an inverse pill at most 560 wide, a shadow in the light theme only, an
/// optional action, and an error form with a leading alert icon.
///
/// Keeps `MySnackBar`'s call style: build it, then [show] it, which
/// replaces any snackbar already showing. [millis] is the time on screen,
/// as `MySnackBar.sec` is today.
class AtomicSnackBar {
  const AtomicSnackBar({
    required this.text,
    required this.millis,
    this.action,
    this.error = false,
  });

  final String text;
  final int millis;
  final AtomicSnackBarAction? action;
  final bool error;

  static const double maxWidth = 560;

  /// The alert icon's colour: it must read on the inverse fill, which is
  /// black in the light theme and light grey in the dark theme.
  static Color errorColor(AtomicColors c) =>
      c.inverseSurface.computeLuminance() > 0.5
          ? AtomicPalette.red700
          : AtomicPalette.red400;

  SnackBar build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final width = MediaQuery.sizeOf(context).width;
    final action = this.action;
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: Duration(milliseconds: millis),
      backgroundColor: c.inverseSurface,
      elevation: light ? 8 : 0,
      shape: const RoundedRectangleBorder(borderRadius: AtomicRadius.largeAll),
      width: width - 32 > maxWidth ? maxWidth : null,
      padding: const EdgeInsets.symmetric(
          horizontal: AtomicSpace.x5, vertical: AtomicSpace.x3),
      content: Row(
        children: [
          if (error) ...[
            Icon(AtomicIcons.alertCircle, size: 20, color: errorColor(c)),
            const SizedBox(width: AtomicSpace.x3),
          ],
          Expanded(
            child: Text(text,
                style: AtomicType.bodyMedium.copyWith(color: c.onInverse)),
          ),
          if (action != null) ...[
            const SizedBox(width: AtomicSpace.x3),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                action.onPressed();
              },
              style: TextButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                shape: const StadiumBorder(),
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.padded,
                padding: const EdgeInsets.symmetric(horizontal: AtomicSpace.x4),
                textStyle: AtomicType.labelLarge,
              ),
              child: Text(action.label),
            ),
          ],
        ],
      ),
    );
  }

  /// Shows this snackbar, replacing the current one.
  void show(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(build(context));
  }
}
