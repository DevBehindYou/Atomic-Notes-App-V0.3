import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

/// Reports what goes wrong inside a bloc. An error thrown by an event handler would otherwise
/// vanish into the zone; here it is at least written to the log with the bloc it came from.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    debugPrint('${bloc.runtimeType} failed: $error');
    super.onError(bloc, error, stackTrace);
  }
}
