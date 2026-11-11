import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:flutter/material.dart';

/// One action in an [AtomicDialog]. Choosing it closes the dialog with
/// [result], so a page reads the same result values it reads today.
class AtomicDialogAction<T> {
  const AtomicDialogAction({
    required this.label,
    required this.result,
    this.variant = AtomicButtonVariant.text,
  });

  final String label;
  final T result;
  final AtomicButtonVariant variant;
}

/// The one dialog of the redesign (components spec, Dialog; replaces
/// `DialogBox`, `DialogBoxLogout` and `EditorPopup`): surface, radius 32,
/// padding 24, at most 400 wide. Two actions sit in a right-aligned row;
/// three stack full width.
class AtomicDialog<T> extends StatelessWidget {
  const AtomicDialog({
    super.key,
    required this.title,
    this.body,
    this.content,
    this.icon,
    this.destructive = false,
    required this.actions,
  });

  final String title;
  final String? body;

  /// Extra content under the body, for example a field.
  final Widget? content;

  /// Shown in a 56 dp circle; a danger circle when [destructive].
  final IconData? icon;
  final bool destructive;
  final List<AtomicDialogAction<T>> actions;

  static const double maxWidth = 400;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = this.icon;
    final body = this.body;
    final content = this.content;
    Widget action(AtomicDialogAction<T> a, {bool expand = false}) =>
        AtomicButton(
          label: a.label,
          variant: a.variant,
          expand: expand,
          onPressed: () => Navigator.of(context).pop(a.result),
        );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AtomicSpace.x6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: Material(
            color: c.surface,
            shape: const RoundedRectangleBorder(
                borderRadius: AtomicRadius.xLargeAll),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AtomicSpace.x6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (icon != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: destructive ? c.danger : c.surfaceInset,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon,
                            size: 28,
                            color: destructive ? c.onDanger : c.textPrimary),
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x4),
                  ],
                  Semantics(
                    header: true,
                    child: Text(title,
                        style: AtomicType.titleLarge
                            .copyWith(color: c.textPrimary)),
                  ),
                  if (body != null) ...[
                    const SizedBox(height: AtomicSpace.x2),
                    Text(body,
                        style: AtomicType.bodyMedium
                            .copyWith(color: c.textSecondary)),
                  ],
                  if (content != null) ...[
                    const SizedBox(height: AtomicSpace.x4),
                    content,
                  ],
                  const SizedBox(height: AtomicSpace.x6),
                  if (actions.length >= 3)
                    for (final (i, a) in actions.indexed) ...[
                      if (i > 0) const SizedBox(height: AtomicSpace.x2),
                      action(a, expand: true),
                    ]
                  else
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AtomicSpace.x2,
                      runSpacing: AtomicSpace.x2,
                      children: [for (final a in actions) action(a)],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows an [AtomicDialog] over the scrim: fade and scale from 0.96 over
/// 200 ms, out in 150 ms; a fade alone under reduced motion. Back or a tap
/// on the scrim dismisses only when [barrierDismissible]; keep it false
/// wherever the current dialog sets `barrierDismissible: false`.
Future<T?> showAtomicDialog<T>({
  required BuildContext context,
  required String title,
  String? body,
  Widget? content,
  IconData? icon,
  bool destructive = false,
  required List<AtomicDialogAction<T>> actions,
  bool barrierDismissible = true,
}) {
  final c = context.colors;
  final reduced = AtomicMotion.reduced(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: c.scrim,
    transitionDuration:
        reduced ? AtomicMotion.reducedFade : const Duration(milliseconds: 200),
    pageBuilder: (context, _, __) => PopScope(
      canPop: barrierDismissible,
      child: AtomicDialog<T>(
        title: title,
        body: body,
        content: content,
        icon: icon,
        destructive: destructive,
        actions: actions,
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
          parent: animation,
          curve: AtomicMotion.standardCurve,
          reverseCurve: AtomicMotion.exitCurve);
      return FadeTransition(
        opacity: curved,
        child: reduced
            ? child
            : ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                child: child,
              ),
      );
    },
  );
}
