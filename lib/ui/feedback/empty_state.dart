import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:flutter/material.dart';

/// A centred empty state (components spec, Empty state): art (the mascot
/// stage at 96), a headline that names the space, one line, and an optional
/// tonal button.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.art,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final Widget? art;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final art = this.art;
    final actionLabel = this.actionLabel;
    return Padding(
      padding: const EdgeInsets.all(AtomicSpace.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (art != null) ...[
            art,
            const SizedBox(height: AtomicSpace.x5),
          ],
          Semantics(
            header: true,
            child: Text(title,
                textAlign: TextAlign.center,
                style:
                    AtomicType.headlineMedium.copyWith(color: c.textPrimary)),
          ),
          const SizedBox(height: AtomicSpace.x2),
          Text(body,
              textAlign: TextAlign.center,
              style: AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
          if (actionLabel != null) ...[
            const SizedBox(height: AtomicSpace.x5),
            AtomicButton.tonal(label: actionLabel, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}
