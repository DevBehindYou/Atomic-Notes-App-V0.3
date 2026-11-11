import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/chips/count_bubble.dart';
import 'package:atomic_notes/ui/controls/atomic_switch.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';

/// An optional label, then one card of rows separated by 1 dp dividers inset
/// 64 dp (components spec, Settings group and row).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.label, required this.children});

  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = this.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(
                left: AtomicSpace.x1, bottom: AtomicSpace.x2),
            child: Semantics(
              header: true,
              child: Text(label,
                  style: AtomicType.bodySmall.copyWith(color: c.textSecondary)),
            ),
          ),
        AtomicCard(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      thickness: 1,
                      indent: AtomicSpace.x16,
                      color: c.outline),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One settings row: a 40 dp icon tile, the title and an optional caption,
/// and one trailing item: a value, a count, a switch, or a chevron. The
/// whole row is one control whose label reads "{title}. {caption}. {value}",
/// as `SettingsCard` does today.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.caption,
    this.onTap,
    this.value,
    this.count,
    this.danger = false,
    this.chevron = true,
  })  : switchValue = null,
        onSwitch = null;

  /// A row whose trailing item is a switch. Tapping anywhere toggles it, and
  /// screen readers hear one switch, not a button and a switch.
  const SettingsRow.toggle({
    super.key,
    required this.icon,
    required this.title,
    this.caption,
    required bool value,
    required ValueChanged<bool>? onChanged,
    this.danger = false,
  })  : switchValue = value,
        onSwitch = onChanged,
        onTap = null,
        value = null,
        count = null,
        chevron = false;

  final IconData icon;
  final String title;
  final String? caption;
  final VoidCallback? onTap;

  /// A short value on the right, for example "On" or "System".
  final String? value;
  final int? count;
  final bool danger;
  final bool chevron;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitch;

  static const double minHeight = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final switchValue = this.switchValue;
    final onSwitch = this.onSwitch;
    final isToggle = switchValue != null;
    final semantics = [title, caption, value]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join('. ');
    Widget? trailing;
    if (isToggle) {
      trailing =
          AtomicSwitchTrack(value: switchValue, enabled: onSwitch != null);
    } else if (count != null) {
      trailing =
          CountBubble(count: count!, fill: c.badge, textColor: c.textPrimary);
    } else if (value != null) {
      trailing = Text(value!,
          style: AtomicType.bodyMedium.copyWith(color: c.textSecondary));
    }
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AtomicSpace.x4, vertical: AtomicSpace.x3),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: danger ? c.danger : c.surfaceInset,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 20, color: danger ? c.onDanger : c.textPrimary),
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
                  if (caption != null && caption!.isNotEmpty)
                    Text(caption!,
                        style: AtomicType.bodySmall
                            .copyWith(color: c.textSecondary)),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AtomicSpace.x3),
              trailing,
            ],
            if (chevron && !isToggle && onTap != null) ...[
              const SizedBox(width: AtomicSpace.x2),
              Icon(AtomicIcons.chevronRight, size: 20, color: c.textSecondary),
            ],
          ],
        ),
      ),
    );
    return AtomicPressable(
      button: !isToggle,
      toggled: switchValue,
      semanticsLabel: semantics,
      excludeSemantics: true,
      borderRadius: BorderRadius.zero,
      onTap: isToggle
          ? (onSwitch == null
              ? null
              : () {
                  AtomicHaptics.play(AtomicHaptic.selection);
                  onSwitch(!switchValue);
                })
          : onTap,
      child: row,
    );
  }
}

/// A row in an activity list: what happened, when, and the amount (Energy
/// activity, coin batches, cloud receipts).
class LedgerRow extends StatelessWidget {
  const LedgerRow({
    super.key,
    required this.title,
    required this.amount,
    this.caption,
    this.icon,
    this.credit = false,
  });

  final String title;

  /// Already formatted, with its sign, for example "+50" or "−5".
  final String amount;
  final String? caption;
  final IconData? icon;

  /// A credit reads in the accent text colour.
  final bool credit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = this.icon;
    final caption = this.caption;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AtomicSpace.x4, vertical: AtomicSpace.x2),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: c.surfaceInset, shape: BoxShape.circle),
                  child: Icon(icon, size: 20, color: c.textPrimary),
                ),
                const SizedBox(width: AtomicSpace.x3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: AtomicType.bodyLarge
                            .copyWith(color: c.textPrimary)),
                    if (caption != null)
                      Text(caption,
                          style: AtomicType.numeric(AtomicType.bodySmall)
                              .copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: AtomicSpace.x3),
              Text(
                amount,
                style: AtomicType.numeric(AtomicType.titleMedium)
                    .copyWith(color: credit ? c.accentText : c.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
