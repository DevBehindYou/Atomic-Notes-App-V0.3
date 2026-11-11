import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:flutter/material.dart';

/// The 64 dp header of every pushed page except Home and the editor (screens
/// spec, shared page layout): a named back button, a small centred title
/// shown once the page's large title has scrolled away, and optional
/// actions. No rule underneath.
class AtomicPageHeader extends StatelessWidget {
  const AtomicPageHeader({
    super.key,
    this.title,
    this.showTitle = false,
    this.onBack,
    this.backTooltip = 'Back',
    this.actions = const [],
  });

  /// The collapsed title, in `titleMedium`.
  final String? title;

  /// Whether [title] shows: true once the page's [PageTitle] has scrolled
  /// past.
  final bool showTitle;

  /// Defaults to `Navigator.maybePop`.
  final VoidCallback? onBack;
  final String backTooltip;
  final List<Widget> actions;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = this.title;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AtomicSpace.x2),
        child: NavigationToolbar(
          leading: AtomicIconButton(
            icon: AtomicIcons.arrowLeft,
            tooltip: backTooltip,
            onPressed: onBack ?? () => Navigator.maybePop(context),
          ),
          middle: title == null
              ? null
              : AnimatedOpacity(
                  opacity: showTitle ? 1 : 0,
                  duration: AtomicMotion.fade(context, AtomicMotion.quick),
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AtomicType.titleMedium.copyWith(color: c.textPrimary),
                    ),
                  ),
                ),
          trailing: actions.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: AtomicSpace.x1),
                      actions[i],
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// A page's large title under the header: `headlineLarge`, left-aligned,
/// with the screen margin.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, AtomicSpace.x2, margin, 0),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: AtomicType.headlineLarge
              .copyWith(color: context.colors.textPrimary),
        ),
      ),
    );
  }
}
