import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/widgets.dart';

/// A count in a pill at least 22 × 22, with tabular figures; above 99 it
/// reads "99+". Used by chips and settings rows.
class CountBubble extends StatelessWidget {
  const CountBubble({
    super.key,
    required this.count,
    required this.fill,
    required this.textColor,
  });

  final int count;
  final Color fill;
  final Color textColor;

  static String format(int count) => count > 99 ? '99+' : '$count';

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, borderRadius: AtomicRadius.pill),
      child: Text(
        format(count),
        style: AtomicType.labelSmall.copyWith(color: textColor),
      ),
    );
  }
}
