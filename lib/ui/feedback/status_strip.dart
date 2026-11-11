import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/material.dart';

/// How close the account is to its note limit.
enum QuotaLevel {
  normal,

  /// Five or fewer notes left: the quota reads in the accent text colour.
  low,

  /// At the limit: the quota reads in the danger text colour.
  limit,
}

/// The Home status strip (components spec): the mascot stage, the greeting,
/// and one line of counts, for example "28 of 30 notes · 2 waiting to sync".
/// The page supplies the words; this only lays them out.
class StatusStrip extends StatelessWidget {
  const StatusStrip({
    super.key,
    required this.leading,
    required this.greeting,
    required this.quota,
    this.quotaLevel = QuotaLevel.normal,
    this.detail,
  });

  /// The mascot stage (56 dp).
  final Widget leading;
  final String greeting;

  /// "28 of 30 notes", or "Note limit reached" at the limit.
  final String quota;
  final QuotaLevel quotaLevel;

  /// What follows the quota, for example "2 waiting to sync".
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final quotaColor = switch (quotaLevel) {
      QuotaLevel.normal => c.textSecondary,
      QuotaLevel.low => c.accentText,
      QuotaLevel.limit => c.dangerText,
    };
    final line = AtomicType.numeric(AtomicType.bodySmall);
    final detail = this.detail;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AtomicRadius.largeAll,
        border: light ? Border.all(color: c.outline) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AtomicSpace.x3),
        child: Row(
          children: [
            leading,
            const SizedBox(width: AtomicSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(greeting,
                      style: AtomicType.titleMedium
                          .copyWith(color: c.textPrimary)),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: quota,
                          style: line.copyWith(
                            color: quotaColor,
                            fontWeight: quotaLevel == QuotaLevel.normal
                                ? null
                                : FontWeight.w600,
                          )),
                      if (detail != null)
                        TextSpan(
                            text: ' · $detail',
                            style: line.copyWith(color: c.textSecondary)),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
