import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';

/// Shows a bottom sheet (components spec, Bottom sheet): surface, top radius
/// 26, a 36 × 4 drag handle, padding 20, at most 90 % of the screen tall.
/// It stays an imperative `showModalBottomSheet`, so existing call sites
/// keep their shape.
Future<T?> showAtomicSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  final c = context.colors;
  final light = Theme.of(context).brightness == Brightness.light;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: true,
    backgroundColor: c.surface,
    barrierColor: c.scrim,
    elevation: light ? 8 : 0,
    shape: const RoundedRectangleBorder(borderRadius: AtomicRadius.sheet),
    constraints:
        BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (context) => AtomicSheetBody(child: builder(context)),
  );
}

/// The inside of a sheet: the handle, then [child] with the sheet padding,
/// scrolling when it is taller than the sheet.
class AtomicSheetBody extends StatelessWidget {
  const AtomicSheetBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AtomicSpace.x3),
        ExcludeSemantics(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.badge,
              borderRadius: AtomicRadius.pill,
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AtomicSpace.x5,
              AtomicSpace.x3,
              AtomicSpace.x5,
              AtomicSpace.x5 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// One row of a quick-action sheet: 56 high, a 24 icon and a `bodyLarge`
/// label. Destructive rows read in the danger text colour.
class AtomicSheetAction extends StatelessWidget {
  const AtomicSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = destructive ? c.dangerText : c.textPrimary;
    return AtomicPressable(
      onTap: onTap,
      semanticsLabel: label,
      excludeSemantics: true,
      borderRadius: AtomicRadius.mediumAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: AtomicSpace.x4),
            Expanded(
              child: Text(label,
                  style: AtomicType.bodyLarge.copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
