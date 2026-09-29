import 'package:atomic_notes/security/two_factor.dart';
import 'package:bloc/bloc.dart';

/// Whether two-factor is armed on this device, read from [TwoFactor] (a
/// `ChangeNotifier`) and turned into one boolean state. The profile row and
/// the two-factor screen's overview both draw this without reading the
/// singleton in build().
///
/// Created with the screen, like `EnergyCubit`, not shared above the app: the
/// two-factor screen takes an optional `TwoFactor` for tests, and this cubit
/// has to wrap that same instance rather than always the real singleton.
class TwoFactorArmedCubit extends Cubit<bool> {
  TwoFactorArmedCubit({TwoFactor? source})
      : _source = source ?? TwoFactor.instance,
        super((source ?? TwoFactor.instance).isArmed) {
    _source.addListener(_changed);
  }

  final TwoFactor _source;

  void _changed() {
    if (isClosed) return;
    final next = _source.isArmed;
    if (next != state) emit(next);
  }

  @override
  Future<void> close() {
    _source.removeListener(_changed);
    return super.close();
  }
}
