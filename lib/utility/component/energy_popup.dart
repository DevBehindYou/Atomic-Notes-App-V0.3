import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/state/energy/energy_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/utility/component/atomic_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Compact Atomic Energy / Coins popup shown on a long-press of the Sync
/// button (screens spec, Energy popup): a centred card that scales in,
/// showing energy and coins, with "Open energy" and "Dismiss". A tap outside
/// or Back dismisses it too; it scrolls instead of overflowing.
Future<void> showEnergyPopup(BuildContext context) {
  final c = context.colors;
  final reduced = AtomicMotion.reduced(context);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: c.scrim,
    transitionDuration:
        reduced ? AtomicMotion.reducedFade : const Duration(milliseconds: 200),
    pageBuilder: (ctx, a1, a2) => const _EnergyPopup(),
    transitionBuilder: (ctx, anim, sec, child) {
      final curved = CurvedAnimation(
          parent: anim,
          curve: AtomicMotion.standardCurve,
          reverseCurve: AtomicMotion.exitCurve);
      return FadeTransition(
        opacity: curved,
        child: reduced
            ? child
            : ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
                child: child,
              ),
      );
    },
  );
}

class _EnergyPopup extends StatelessWidget {
  const _EnergyPopup();

  @override
  Widget build(BuildContext context) {
    return BlocProvider<EnergyCubit>(
      // Freshen quietly when opened; the popup renders cached values immediately.
      create: (_) => EnergyCubit(store: EnergyService.instance)..refresh(),
      child: const _EnergyPopupView(),
    );
  }
}

class _EnergyPopupView extends StatelessWidget {
  const _EnergyPopupView();

  static const double maxWidth = 360;

  void _openPage(BuildContext context) {
    Navigator.of(context).pop(); // close popup first
    Navigator.of(context).pushNamed('/energypage');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AtomicSpace.x6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: Material(
              key: const ValueKey('energy-popup'),
              type: MaterialType.transparency,
              child: AtomicCard(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AtomicSpace.x5),
                  child: BlocBuilder<EnergyCubit, EnergyState>(
                    builder: (context, energy) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Atomic Energy
                        Semantics(
                          container: true,
                          label: 'Atomic energy, ${energy.energy} of '
                              '${energy.energyCap}',
                          child: ExcludeSemantics(
                            child: Row(
                              children: [
                                const AtomicIcon.energy(size: 32),
                                const SizedBox(width: AtomicSpace.x3),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Atomic energy',
                                          style: AtomicType.bodySmall.copyWith(
                                              color: c.textSecondary)),
                                      Text(
                                        '${energy.energy} / ${energy.energyCap}',
                                        style: AtomicType.numeric(
                                                AtomicType.titleLarge)
                                            .copyWith(color: c.textPrimary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AtomicSpace.x3),
                        ExcludeSemantics(
                          child:
                              ProgressBar(value: energy.wallet.energyFraction),
                        ),
                        const SizedBox(height: AtomicSpace.x4),
                        Divider(height: 1, thickness: 1, color: c.outline),
                        const SizedBox(height: AtomicSpace.x4),
                        // Atomic Coins
                        MergeSemantics(
                          child: Row(
                            children: [
                              const ExcludeSemantics(
                                  child: AtomicIcon.coin(size: 32)),
                              const SizedBox(width: AtomicSpace.x3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Atomic coins',
                                        style: AtomicType.bodySmall
                                            .copyWith(color: c.textSecondary)),
                                    Text(
                                      '${energy.coins}',
                                      style: AtomicType.numeric(
                                              AtomicType.titleLarge)
                                          .copyWith(color: c.textPrimary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AtomicSpace.x5),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: AtomicSpace.x2,
                          runSpacing: AtomicSpace.x2,
                          children: [
                            AtomicButton.text(
                              key: const ValueKey('energy-popup-dismiss'),
                              label: 'Dismiss',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            AtomicButton.primary(
                              key: const ValueKey('energy-popup-open'),
                              label: 'Open energy',
                              onPressed: () => _openPage(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
