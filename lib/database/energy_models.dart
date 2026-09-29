// Data models for Atomic Energy + Atomic Coins.
//
// Plain value types with no Supabase/Flutter coupling, mirroring how
// `Note`/`TodoItem` stay separate from the repository. All balance mutation
// lives server-side (see supabase/migrations/006_energy.sql); these just carry
// what the client reads back.

import 'package:equatable/equatable.dart';

/// One kind of ledger entry. String values match the `kind` column check
/// constraint in Postgres.
enum EnergyTxKind {
  dailyGrant,
  convert,
  spend,
  purchase,
  adminAdjust,
  unknown;

  static EnergyTxKind fromRaw(String? raw) {
    switch (raw) {
      case 'daily_grant':
        return EnergyTxKind.dailyGrant;
      case 'convert':
        return EnergyTxKind.convert;
      case 'spend':
        return EnergyTxKind.spend;
      case 'purchase':
        return EnergyTxKind.purchase;
      case 'admin_adjust':
        return EnergyTxKind.adminAdjust;
      default:
        return EnergyTxKind.unknown;
    }
  }

  /// Human label for the history row.
  String get label {
    switch (this) {
      case EnergyTxKind.dailyGrant:
        return 'Daily energy';
      case EnergyTxKind.convert:
        return 'Coins converted';
      case EnergyTxKind.spend:
        return 'Energy used';
      case EnergyTxKind.purchase:
        return 'Coins purchased';
      case EnergyTxKind.adminAdjust:
        return 'Adjustment';
      case EnergyTxKind.unknown:
        return 'Transaction';
    }
  }
}

/// A single balance-changing event, read from `energy_ledger`.
class EnergyTx extends Equatable {
  final String id;
  final EnergyTxKind kind;
  final int coinsDelta;
  final int energyDelta;
  final int resultingCoins;
  final int resultingEnergy;
  final String? note;
  final DateTime createdAt;

  const EnergyTx({
    required this.id,
    required this.kind,
    required this.coinsDelta,
    required this.energyDelta,
    required this.resultingCoins,
    required this.resultingEnergy,
    required this.note,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        kind,
        coinsDelta,
        energyDelta,
        resultingCoins,
        resultingEnergy,
        note,
        createdAt,
      ];

  factory EnergyTx.fromMap(Map<String, dynamic> m) {
    int asInt(dynamic v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;
    return EnergyTx(
      id: '${m['id']}',
      kind: EnergyTxKind.fromRaw(m['kind'] as String?),
      coinsDelta: asInt(m['coins_delta']),
      energyDelta: asInt(m['energy_delta']),
      resultingCoins: asInt(m['resulting_coins']),
      resultingEnergy: asInt(m['resulting_energy']),
      note: m['note'] as String?,
      createdAt:
          DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
    );
  }
}

/// The current balances, read from the `atomicuser` row.
class Wallet extends Equatable {
  final int coins;
  final int energy;
  final int energyCap;
  final DateTime? lastDailyGrantAt;

  /// How many notes this account may hold, as the Server enforces it.
  final int noteLimit;

  const Wallet({
    required this.coins,
    required this.energy,
    required this.energyCap,
    required this.lastDailyGrantAt,
    this.noteLimit = 30,
  });

  @override
  List<Object?> get props =>
      [coins, energy, energyCap, lastDailyGrantAt, noteLimit];

  /// Empty wallet used before the first load / for a fresh account.
  static const Wallet empty =
      Wallet(coins: 0, energy: 0, energyCap: 120, lastDailyGrantAt: null);

  /// 0..1 fill for the energy bar.
  double get energyFraction =>
      energyCap <= 0 ? 0 : (energy / energyCap).clamp(0.0, 1.0);

  factory Wallet.fromMap(Map<String, dynamic> m) {
    int asInt(dynamic v, [int fallback = 0]) =>
        v is int ? v : int.tryParse('${v ?? fallback}') ?? fallback;
    return Wallet(
      coins: asInt(m['coins']),
      energy: asInt(m['energy']),
      energyCap: asInt(m['energy_cap'], 120),
      noteLimit: asInt(m['note_limit'], 30),
      lastDailyGrantAt: m['last_daily_grant_at'] == null
          ? null
          : DateTime.tryParse('${m['last_daily_grant_at']}')?.toLocal(),
    );
  }
}

/// One note-capacity tier the Server sells. [costCoins] is what it takes to reach [limit] from the
/// tier before it; 0 on the free starting tier. [name] is a particle, biggest at the top: Tachyon,
/// Antimatter, Monopole, Strangelet.
class NoteLimitTier extends Equatable {
  final int limit;
  final String name;
  final int costCoins;

  const NoteLimitTier({
    required this.limit,
    required this.name,
    required this.costCoins,
  });

  @override
  List<Object?> get props => [limit, name, costCoins];

  factory NoteLimitTier.fromMap(Map<String, dynamic> m) {
    int asInt(String key) {
      final v = m[key];
      return v is num ? v.toInt() : 0;
    }

    return NoteLimitTier(
      limit: asInt('limit'),
      name: m['name'] as String? ?? '',
      costCoins: asInt('cost_coins'),
    );
  }
}

/// The prices and ceilings the Server enforces, sent with the wallet so the App
/// shows what will really happen. The defaults are used until the first load.
class EnergyLimits extends Equatable {
  final int noteLimitFree;
  final int noteLimitCeiling;

  /// Every note-capacity tier in order, free tier first. The Server sends this; the
  /// constant here is only what a fresh install shows before the first load.
  final List<NoteLimitTier> noteLimitTiers;
  final int syncStandardCost;
  final int syncInstantCost;
  final int syncStandardIntervalSeconds;

  const EnergyLimits({
    this.noteLimitFree = 30,
    this.noteLimitCeiling = 100,
    this.noteLimitTiers = _defaultTiers,
    this.syncStandardCost = 5,
    this.syncInstantCost = 10,
    this.syncStandardIntervalSeconds = 3600,
  });

  static const _defaultTiers = <NoteLimitTier>[
    NoteLimitTier(limit: 30, name: 'Tachyon', costCoins: 0),
    NoteLimitTier(limit: 40, name: 'Antimatter', costCoins: 10),
    NoteLimitTier(limit: 50, name: 'Monopole', costCoins: 20),
    NoteLimitTier(limit: 100, name: 'Strangelet', costCoins: 30),
  ];

  @override
  List<Object?> get props => [
        noteLimitFree,
        noteLimitCeiling,
        noteLimitTiers,
        syncStandardCost,
        syncInstantCost,
        syncStandardIntervalSeconds,
      ];

  /// The tier past [currentLimit], or null at the ceiling (or a limit that matches no tier).
  NoteLimitTier? tierAfter(int currentLimit) {
    final i = noteLimitTiers.indexWhere((t) => t.limit == currentLimit);
    if (i < 0 || i + 1 >= noteLimitTiers.length) return null;
    return noteLimitTiers[i + 1];
  }

  /// The tier that grants exactly [limit], or null if nothing matches.
  NoteLimitTier? tierFor(int limit) {
    final i = noteLimitTiers.indexWhere((t) => t.limit == limit);
    return i < 0 ? null : noteLimitTiers[i];
  }

  factory EnergyLimits.fromMap(Map<String, dynamic> m) {
    int asInt(String key, int fallback) {
      final v = m[key];
      return v is num ? v.toInt() : fallback;
    }

    const d = EnergyLimits();
    final rawTiers = m['note_limit_tiers'];
    final tiers = rawTiers is List
        ? rawTiers
            .whereType<Map>()
            .map((e) => NoteLimitTier.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : const <NoteLimitTier>[];

    return EnergyLimits(
      noteLimitFree: asInt('note_limit_free', d.noteLimitFree),
      noteLimitCeiling: asInt('note_limit_ceiling', d.noteLimitCeiling),
      noteLimitTiers: tiers.isEmpty ? d.noteLimitTiers : tiers,
      syncStandardCost: asInt('sync_standard_cost', d.syncStandardCost),
      syncInstantCost: asInt('sync_instant_cost', d.syncInstantCost),
      syncStandardIntervalSeconds: asInt(
          'sync_standard_interval_seconds', d.syncStandardIntervalSeconds),
    );
  }
}
