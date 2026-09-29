import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/energy_store.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// What the energy screen and the energy popup show: the balances, the prices, the activity and
/// how many notes are in use. The models are value types, so a balance that did not change gives
/// an equal state and nothing is rebuilt.
final class EnergyState extends Equatable {
  const EnergyState({
    this.wallet = Wallet.empty,
    this.limits = const EnergyLimits(),
    this.history = const [],
    this.loading = false,
    this.hasLoaded = false,
    this.error,
    this.notesUsed = 0,
  });

  final Wallet wallet;
  final EnergyLimits limits;
  final List<EnergyTx> history;
  final bool loading;

  /// True once a balance of the signed-in account has been read.
  final bool hasLoaded;
  final String? error;

  /// Live notes on this device, for the capacity bar.
  final int notesUsed;

  int get coins => wallet.coins;
  int get energy => wallet.energy;
  int get energyCap => wallet.energyCap;

  /// How many notes the account may hold, as the Server reports it.
  int get noteLimit => wallet.noteLimit;

  /// The tier the next purchase reaches, or null at the ceiling.
  NoteLimitTier? get nextTier => limits.tierAfter(noteLimit);

  /// A further tier can be bought.
  bool get canRaiseNoteLimit => nextTier != null;

  /// There are enough coins for the next tier.
  bool get canAffordNoteLimit {
    final tier = nextTier;
    return tier != null && coins >= tier.costCoins;
  }

  /// The limit after the next purchase.
  int get nextNoteLimit => nextTier?.limit ?? noteLimit;

  @override
  List<Object?> get props =>
      [wallet, limits, history, loading, hasLoaded, error, notesUsed];
}

/// State and actions of the Atomic Energy screen and popup. The balances stay in the [EnergyStore]
/// (the Server is what changes them); this listens to it and to the notes store.
class EnergyCubit extends Cubit<EnergyState> {
  EnergyCubit({required EnergyStore store, NotesSource? notes})
      : _store = store,
        _notes = notes,
        super(_read(store, notes)) {
    _store.addListener(_changed);
    _notes?.addListener(_changed);
  }

  final EnergyStore _store;
  final NotesSource? _notes;

  static EnergyState _read(EnergyStore store, NotesSource? notes) => EnergyState(
        wallet: store.wallet,
        limits: store.limits,
        history: List<EnergyTx>.unmodifiable(store.history),
        loading: store.loading,
        hasLoaded: store.hasLoaded,
        error: store.error,
        notesUsed: notes?.count ?? 0,
      );

  void _changed() {
    if (isClosed) return;
    final next = _read(_store, _notes);
    if (next != state) emit(next);
  }

  @override
  Future<void> close() {
    _store.removeListener(_changed);
    _notes?.removeListener(_changed);
    return super.close();
  }

  Future<void> refresh() => _store.refresh();

  /// Null on success, else the message to show.
  Future<String?> convertCoins(int coins) => _store.convertCoins(coins);

  /// Null on success, else the message to show.
  Future<String?> upgradeNoteLimit() => _store.upgradeNoteLimit();
}
