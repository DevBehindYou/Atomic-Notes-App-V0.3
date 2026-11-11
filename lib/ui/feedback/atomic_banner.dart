import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/material.dart';

enum BannerTone { info, attention, danger }

/// A message card (components spec, Banner): a 40 dp tone circle, a title
/// and a body. The card stays `surface` in every tone; only the circle
/// carries the colour. Named apart from Flutter's `Banner`.
class AtomicBanner extends StatelessWidget {
  const AtomicBanner({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final BannerTone tone;
  final IconData icon;
  final String title;
  final String? body;

  /// Optional, for example a tonal button.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final (fill, iconColor) = switch (tone) {
      BannerTone.info => (c.info, AtomicPalette.white),
      BannerTone.attention => (c.accent, AtomicPalette.black),
      BannerTone.danger => (c.danger, AtomicPalette.black),
    };
    final body = this.body;
    final action = this.action;
    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AtomicRadius.largeAll,
          border: light ? Border.all(color: c.outline) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AtomicSpace.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: AtomicSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: AtomicType.titleMedium
                            .copyWith(color: c.textPrimary)),
                    if (body != null) ...[
                      const SizedBox(height: AtomicSpace.x1),
                      Text(body,
                          style: AtomicType.bodyMedium
                              .copyWith(color: c.textSecondary)),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: AtomicSpace.x3),
                      action,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
