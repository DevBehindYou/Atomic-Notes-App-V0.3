import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/widgets.dart';

enum StatusTone { neutral, inverse, accent, info, danger }

/// A small read-only status pill, in sentence case (replaces `DataChip`).
class StatusChip extends StatelessWidget {
  const StatusChip(this.label,
      {super.key, this.tone = StatusTone.neutral, this.icon});

  final String label;
  final StatusTone tone;
  final IconData? icon;

  (Color, Color) _colors(AtomicColors c) => switch (tone) {
        StatusTone.neutral => (c.surfaceInset, c.textPrimary),
        StatusTone.inverse => (c.inverseSurface, c.onInverse),
        StatusTone.accent => (c.accent, c.onAccent),
        StatusTone.info => (c.info, c.onInfo),
        StatusTone.danger => (c.danger, c.onDanger),
      };

  @override
  Widget build(BuildContext context) {
    final (fill, content) = _colors(context.colors);
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(
          horizontal: AtomicSpace.x2 + 2, vertical: 3),
      decoration: BoxDecoration(color: fill, borderRadius: AtomicRadius.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: content),
            const SizedBox(width: AtomicSpace.x1),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AtomicType.labelMedium.copyWith(color: content),
            ),
          ),
        ],
      ),
    );
  }
}
