import 'package:atomic_notes/database/energy_models.dart';
import 'package:flutter/foundation.dart';

/// What the energy state needs from the place balances are kept.
///
/// [EnergyService] is the real one: it reads the Server's balances and never computes its own.
/// The state layer only sees this interface, so it can be tested with a small fake and no network.
/// It tells listeners whenever anything changed, including a load starting or ending.
abstract interface class EnergyStore implements Listenable {
  Wallet get wallet;

  /// The prices and ceilings the Server enforces.
  EnergyLimits get limits;
  List<EnergyTx> get history;
  bool get loading;

  /// True once a balance of the signed-in account has been read.
  bool get hasLoaded;

  /// Why the last load failed, in words for the user.
  String? get error;

  /// Reads the balance and the history again.
  Future<void> refresh();

  /// Converts [coins] Atomic Coins into energy. Null on success, else a message for the user.
  Future<String?> convertCoins(int coins);

  /// Buys the next 10 notes of capacity. Null on success, else a message for the user.
  Future<String?> upgradeNoteLimit();
}
