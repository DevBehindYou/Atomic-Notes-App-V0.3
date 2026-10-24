import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// The editor's paper-and-ink popup surface. The title, content and actions
/// share a scroll view so every action remains reachable above a keyboard or
/// with large accessibility text, rather than clipping a fixed button row.
class EditorPopup extends StatelessWidget {
  const EditorPopup(
      {required this.title,
      required this.content,
      required this.actions,
      super.key});

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md, vertical: AppSpace.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: AppRadius.std,
              border:
                  Border.all(color: AppColors.ink, width: AppStroke.hairline),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.ink,
                    offset: Offset(AppStroke.offset, AppStroke.offset),
                    blurRadius: 0)
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.modulePadding),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                        namesRoute: true,
                        header: true,
                        child: Text(title, style: AppType.headlineMd)),
                    const SizedBox(height: AppSpace.md),
                    DefaultTextStyle.merge(
                        style: AppType.bodyLg, child: content),
                    const SizedBox(height: AppSpace.lg),
                    for (var index = 0; index < actions.length; index++) ...[
                      if (index > 0) const SizedBox(height: AppSpace.md),
                      actions[index],
                    ],
                  ]),
            ),
          ),
        ),
      );
}

enum EditorPopupActionTone { primary, secondary, destructive }

/// A real Material button keeps keyboard activation, focus, semantics and ink
/// feedback. Labels wrap freely instead of hiding the decision in an ellipsis.
class EditorPopupButton extends StatelessWidget {
  const EditorPopupButton(
      {required this.label,
      required this.onPressed,
      this.tone = EditorPopupActionTone.secondary,
      super.key});

  final String label;
  final VoidCallback? onPressed;
  final EditorPopupActionTone tone;

  @override
  Widget build(BuildContext context) {
    final secondary = tone == EditorPopupActionTone.secondary;
    final fill = tone == EditorPopupActionTone.destructive
        ? AppColors.error
        : AppColors.signal;
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md)),
      textStyle: WidgetStatePropertyAll(AppType.cta
          .copyWith(fontSize: AppType.headlineSm.fontSize, height: 1.2)),
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? AppColors.slateData
              : (secondary ? AppColors.ink : AppColors.paper)),
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? AppColors.surfaceHigh
              : (secondary ? AppColors.paper : fill)),
      side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.ink, width: AppStroke.hairline)),
      shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.std)),
    );
    final text = Text(label, softWrap: true, textAlign: TextAlign.center);
    final button = secondary
        ? OutlinedButton(onPressed: onPressed, style: style, child: text)
        : FilledButton(onPressed: onPressed, style: style, child: text);
    return SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
              borderRadius: AppRadius.std,
              boxShadow: secondary || onPressed == null
                  ? null
                  : const [
                      BoxShadow(
                          color: AppColors.ink,
                          offset: Offset(AppStroke.offset, AppStroke.offset),
                          blurRadius: 0)
                    ]),
          child: button,
        ));
  }
}
