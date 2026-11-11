import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:flutter/material.dart';

/// A rounded tonal surface (replaces `EditorialModule`). Depth is tonal in
/// the dark theme; in the light theme the card gets a 1 dp outline edge
/// (tokens, Elevation). No shadow.
class AtomicCard extends StatelessWidget {
  const AtomicCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AtomicSpace.cardPadding),
    this.radius = AtomicRadius.largeAll,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius radius;

  /// Defaults to `surface`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: radius,
        border: light ? Border.all(color: c.outline) : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
