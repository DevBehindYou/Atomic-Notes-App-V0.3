import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/utility/component/atomic_icon.dart';
import 'package:atomic_notes/utility/intropages/intro_art.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';

/// One-time feature tour for Atomic Energy, Atomic Coins, and the long-press
/// sync popup. Shown once from the home screen (flagged in `authBox`), and
/// replayable from the Atomic Energy screen's "How it works" link.
///
/// Pushed on top of the home screen: it pops back when finished, rather than
/// replacing the route, so it works both as the auto-shown intro and as a
/// manual replay. Skip and "Got it" both set the flag; system Back leaves
/// it unset, so the tour shows again next time.
///
/// Every number comes from the policy: the sync prices from the Server's
/// limits, the energy cap from the wallet, and the grant and conversion rate
/// from the [EnergyService] economy constants.
class EnergyIntroScreen extends StatefulWidget {
  const EnergyIntroScreen({super.key});

  /// authBox flag: has this device seen the energy tour yet.
  static const String seenFlag = 'hasSeenEnergyIntro';

  @override
  State<EnergyIntroScreen> createState() => _EnergyIntroScreenState();
}

class _EnergyIntroScreenState extends State<EnergyIntroScreen> {
  /// The animated GIF, or under reduced motion the still mark it settles on.
  static Widget _gif(BuildContext context, String name,
          {required String still, required String label}) =>
      Semantics(
        image: true,
        label: label,
        child: ExcludeSemantics(
          child: AtomicMotion.reduced(context)
              ? AtomicIcon(still, size: 110, set: 'Icons-Without-label-2.5D')
              : Image.asset(
                  'assets/Atomic Icons/$name',
                  height: 150,
                  fit: BoxFit.contain,
                ),
        ),
      );

  static Widget _mark(String name, {required String label}) => Semantics(
        image: true,
        label: label,
        child: ExcludeSemantics(
          child: AtomicIcon(name, size: 110, set: 'Icons-Without-label-2.5D'),
        ),
      );

  List<IntroTourPage> _pages() {
    final energy = EnergyService.instance;
    final limits = energy.limits;
    return [
      IntroTourPage(
        art: (context) => _gif(context, 'atom-formation.gif',
            still: 'atom', label: 'An atom forming'),
        eyebrow: 'Atomic Energy',
        title: 'Energy powers\nyour sync.',
        body: 'You get +${EnergyService.dailyGrant} Atomic Energy free every '
            '24 hours, up to ${energy.energyCap}. Local note-taking is always '
            'free — energy only powers cloud sync.',
      ),
      IntroTourPage(
        art: (_) => _mark('atom', label: 'The Atomic Energy mark'),
        eyebrow: 'Quick peek',
        title: 'Long-press\nthe sync button.',
        body: 'Press and hold the sync button in the top bar to peek at your '
            'Atomic Energy and Coins without leaving your notes. Tap it as '
            'usual to sync.',
      ),
      IntroTourPage(
        art: (context) => _gif(context, 'atom-to-coin.gif',
            still: 'atomic-coin', label: 'An atom turning into a coin'),
        eyebrow: 'Atomic Coins',
        title: 'Coins top up\nyour energy.',
        body: '1 Atomic Coin converts to ${EnergyService.coinToEnergy} '
            'energy, and new accounts start with 5 coins. Convert whenever '
            'you like from the Atomic Energy screen.',
      ),
      IntroTourPage(
        art: (_) => _mark('atomic-coin', label: 'The Atomic Coin mark'),
        eyebrow: 'Sync costs',
        title: 'Instant or\nautomatic.',
        body: 'Charges apply per upload batch of up to 50 changed notes, '
            'limited by size. Each instant batch costs '
            '${limits.syncInstantCost} energy; each automatic batch costs '
            '${limits.syncStandardCost}, with an hourly window shared across '
            'your account. Large instant syncs can cost more than '
            '${limits.syncInstantCost}. Receive-only sync is free. Changes '
            'waiting to upload stay on this device.',
      ),
    ];
  }

  Future<void> _finish() async {
    try {
      await Hive.box<bool>('authBox').put(EnergyIntroScreen.seenFlag, true);
    } catch (_) {
      // Non-fatal: worst case the tour shows again next launch.
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return IntroTour(
      doneLabel: 'Got it',
      onFinish: _finish,
      pages: _pages(),
    );
  }
}
