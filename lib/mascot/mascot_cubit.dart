import 'package:bloc/bloc.dart';
import 'mascot_catalog.dart';
import 'mascot_preferences.dart';

enum MascotSaveState { idle, pending, saved, error, readOnly }

class MascotState {
  final MascotPreferences desired;
  final MascotPreferences? persisted;
  final bool isLoading;
  final MascotSaveState saveState;
  final String? errorCode;
  const MascotState(
      {required this.desired,
      this.persisted,
      this.isLoading = false,
      this.saveState = MascotSaveState.idle,
      this.errorCode});
}

class MascotCubit extends Cubit<MascotState> {
  final MascotPreferencesStore _store;
  bool _selectedTouched = false, _motionTouched = false;
  bool _readSucceeded = false, _readOnly = false, _writing = false;
  Future<void>? _loading;
  MascotCubit(this._store)
      : super(MascotState(desired: MascotPreferences.defaults()));
  void _publish(
      {MascotPreferences? desired,
      MascotPreferences? persisted,
      bool? loading,
      MascotSaveState? saveState,
      String? errorCode}) {
    if (!isClosed) {
      emit(MascotState(
          desired: desired ?? state.desired,
          persisted: persisted ?? state.persisted,
          isLoading: loading ?? state.isLoading,
          saveState: saveState ?? state.saveState,
          errorCode: errorCode));
    }
  }

  Future<void> load() => _readSucceeded
      ? Future<void>.value()
      : (_loading ??= _load().whenComplete(() => _loading = null));
  Future<void> _load() async {
    _publish(loading: true);
    try {
      final result = await _store.read();
      if (isClosed) return;
      _readSucceeded = true;
      _readOnly = result.kind == MascotPreferenceReadKind.futureVersion;
      final stored = result.value ?? MascotPreferences.defaults();
      final value = _readOnly
          ? MascotPreferences.defaults()
          : MascotPreferences(
              selectedId: _selectedTouched
                  ? state.desired.selectedId
                  : stored.selectedId,
              animationsEnabled: _motionTouched
                  ? state.desired.animationsEnabled
                  : stored.animationsEnabled);
      _publish(
          desired: value,
          persisted: result.value,
          loading: false,
          saveState:
              _readOnly ? MascotSaveState.readOnly : MascotSaveState.idle,
          errorCode: result.diagnosticCode);
      if (_selectedTouched || _motionTouched) _drain();
    } catch (_) {
      if (!isClosed) {
        _publish(
            loading: false,
            saveState: MascotSaveState.error,
            errorCode: 'read_failed');
      }
    }
  }

  void selectMascot(String id) {
    if (isClosed || _readOnly) return;
    if (MascotCatalog.findById(id) == null) {
      _publish(errorCode: 'unknown_mascot');
      return;
    }
    _change(state.desired.copyWith(selectedId: id), selectedTouched: true);
  }

  void setAnimationsEnabled(bool value) =>
      _change(state.desired.copyWith(animationsEnabled: value),
          motionTouched: true);
  void _change(MascotPreferences value,
      {bool selectedTouched = false, bool motionTouched = false}) {
    if (isClosed || _readOnly) return;
    _selectedTouched |= selectedTouched;
    _motionTouched |= motionTouched;
    if (value == state.desired) return;
    _publish(
        desired: value,
        saveState: _readOnly
            ? MascotSaveState.readOnly
            : (_readSucceeded ? MascotSaveState.pending : state.saveState),
        errorCode:
            !_readSucceeded && !state.isLoading ? state.errorCode : null);
    _drain();
  }

  void retrySave() {
    if (isClosed || _readOnly) return;
    if (!_readSucceeded) {
      load();
      return;
    }
    _drain();
  }

  Future<void> _drain() async {
    if (_writing || !_readSucceeded || _readOnly || isClosed) return;
    _writing = true;
    try {
      while (!isClosed && state.desired != state.persisted) {
        final value = state.desired;
        _publish(saveState: MascotSaveState.pending);
        try {
          await _store.write(value);
        } catch (_) {
          _publish(saveState: MascotSaveState.error, errorCode: 'write_failed');
          return;
        }
        if (isClosed) return;
        _publish(
            persisted: value,
            saveState: state.desired == value
                ? MascotSaveState.saved
                : MascotSaveState.pending);
      }
    } finally {
      _writing = false;
    }
  }
}
