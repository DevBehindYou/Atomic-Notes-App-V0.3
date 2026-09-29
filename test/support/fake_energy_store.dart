import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/energy_store.dart';
import 'package:flutter/foundation.dart';

/// Balances in memory, for tests of the state layer. The Server is the real authority over these
/// numbers; the fake only keeps the same promises (a conversion moves coins into energy, a
/// purchase moves coins into capacity) so the state can be tested without a network.
class FakeEnergyStore extends ChangeNotifier implements EnergyStore {
  FakeEnergyStore({
    this.wallet = const Wallet(
        coins: 12, energy: 60, energyCap: 120, lastDailyGrantAt: null),
    this.limits = const EnergyLimits(),
    this.history = const [],
  });

  @override
  Wallet wallet;

  @override
  EnergyLimits limits;

  @override
  List<EnergyTx> history;

  @override
  bool loading = false;

  @override
  bool hasLoaded = true;

  @override
  String? error;

  int refreshCalls = 0;
  final List<int> converted = [];
  int upgrades = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
    notifyListeners();
  }

  @override
  Future<String?> convertCoins(int coins) async {
    if (coins > wallet.coins) return 'Not enough Atomic Coins.';
    converted.add(coins);
    wallet = Wallet(
      coins: wallet.coins - coins,
      energy: wallet.energy + coins * 40,
      energyCap: wallet.energyCap,
      lastDailyGrantAt: wallet.lastDailyGrantAt,
      noteLimit: wallet.noteLimit,
    );
    notifyListeners();
    return null;
  }

  @override
  Future<String?> upgradeNoteLimit() async {
    final tier = limits.tierAfter(wallet.noteLimit);
    if (tier == null) {
      return 'You already have the most notes possible.';
    }
    if (wallet.coins < tier.costCoins) {
      return 'Not enough Atomic Coins.';
    }
    upgrades++;
    wallet = Wallet(
      coins: wallet.coins - tier.costCoins,
      energy: wallet.energy,
      energyCap: wallet.energyCap,
      lastDailyGrantAt: wallet.lastDailyGrantAt,
      noteLimit: tier.limit,
    );
    notifyListeners();
    return null;
  }

  /// Tells the listeners without changing anything, like a load starting or ending.
  void poke() => notifyListeners();

  /// A change made by something other than the screen, such as a sync that spent energy.
  void change(void Function() change) {
    change();
    notifyListeners();
  }
}
