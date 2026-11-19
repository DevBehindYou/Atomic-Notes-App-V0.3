import 'package:flutter/material.dart';
import '../database/note_rich_content.dart';
import '../theme/atomic_colors.dart';
import '../theme/atomic_tokens.dart';
import '../theme/atomic_type.dart';
import 'rich_text_controller.dart';

/// One anchored menu: styles stay above the platform's unmodified actions.
/// Applying a style never invokes hideToolbar or requests another focus node.
class RichSelectionToolbar extends StatelessWidget {
  const RichSelectionToolbar(
      {super.key, required this.editable, required this.controller});
  final EditableTextState editable;
  final RichNoteController controller;
  @override
  Widget build(BuildContext context) {
    final media = MediaQueryData.fromView(View.of(context));
    final anchors = editable.contextMenuAnchors;
    final top = media.padding.top + 8;
    final bottom = media.viewInsets.bottom > media.padding.bottom
        ? media.viewInsets.bottom
        : media.padding.bottom;
    final native = editable.contextMenuButtonItems;
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, top, 8, bottom + 8),
      child: CustomSingleChildLayout(
        delegate: _MenuPosition(
          above: anchors.primaryAnchor - Offset(8, top + 8),
          below: (anchors.secondaryAnchor ?? anchors.primaryAnchor) -
              Offset(8, top - 20),
        ),
        child: SizedBox(
          width: (media.size.width - 16).clamp(0, 400),
          child: SingleChildScrollView(
            child: Column(
              key: const ValueKey('note-selection-menu'),
              mainAxisSize: MainAxisSize.min,
              children: [
                NoteFormatBar(controller: controller),
                if (native.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: c.surfaceRaised,
                    elevation: light ? 2 : 0,
                    borderRadius: AtomicRadius.pill,
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final button
                            in AdaptiveTextSelectionToolbar.getAdaptiveButtons(
                                context, native))
                          ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: button),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// B, I, U, S and H as round toggles on an inverse pill (components spec,
/// Rich selection toolbar). An active style is an accent fill with a black
/// glyph.
class NoteFormatBar extends StatelessWidget {
  const NoteFormatBar({super.key, required this.controller});
  final RichNoteController controller;
  static const _styles = [
    ('B', 'Bold', NoteTextStyle.bold),
    ('I', 'Italic', NoteTextStyle.italic),
    ('U', 'Underline', NoteTextStyle.underline),
    ('S', 'Strikethrough', NoteTextStyle.strike),
    ('H', 'Heading', NoteTextStyle.heading),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Material(
        key: const ValueKey('note-format-bar'),
        color: c.inverseSurface,
        borderRadius: AtomicRadius.pill,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AtomicSpace.x2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: AtomicSpace.x1,
                children: [
                  for (final (letter, label, flag) in _styles)
                    // Merged so the on/off state is on the button itself,
                    // not on a separate unnamed node around it.
                    MergeSemantics(
                        child: Semantics(
                      toggled: controller.hasStyle(flag),
                      // A round toggle filling its 48 dp target.
                      child: IconButton(
                        tooltip: label,
                        isSelected: controller.hasStyle(flag),
                        onPressed: () => controller.toggleStyle(flag),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          foregroundColor: controller.hasStyle(flag)
                              ? c.onAccent
                              : c.onInverse,
                          backgroundColor: controller.hasStyle(flag)
                              ? c.accent
                              : Colors.transparent,
                          shape: const CircleBorder(),
                        ),
                        // The tooltip names the style; the glyph is
                        // visual only, so it is not read as a letter too.
                        icon: ExcludeSemantics(
                            child: Text(letter,
                                style: TextStyle(
                                  fontFamily: AtomicFonts.sans,
                                  color: controller.hasStyle(flag)
                                      ? c.onAccent
                                      : c.onInverse,
                                  fontSize: 18,
                                  fontWeight: letter == 'B' || letter == 'H'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontStyle: letter == 'I'
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  decorationColor: controller.hasStyle(flag)
                                      ? c.onAccent
                                      : c.onInverse,
                                  decoration: letter == 'U'
                                      ? TextDecoration.underline
                                      : letter == 'S'
                                          ? TextDecoration.lineThrough
                                          : null,
                                ))),
                      ),
                    )),
                ]),
          ),
        ),
      ),
    );
  }
}

class _MenuPosition extends SingleChildLayoutDelegate {
  _MenuPosition({required this.above, required this.below});
  final Offset above;
  final Offset below;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (above.dx - childSize.width / 2)
        .clamp(0.0, (size.width - childSize.width).clamp(0.0, double.infinity));
    final y =
        above.dy >= childSize.height ? above.dy - childSize.height : below.dy;
    return Offset(
        x,
        y.clamp(
            0.0, (size.height - childSize.height).clamp(0.0, double.infinity)));
  }

  @override
  bool shouldRelayout(covariant _MenuPosition oldDelegate) =>
      above != oldDelegate.above || below != oldDelegate.below;
}
