import 'package:atomic_notes/appearance/appearance_preferences.dart';
import 'package:flutter/material.dart';

/// Whether the app may leave the light theme yet.
///
/// The redesign moves screens to theme-aware colours over several changes.
/// Until M9 finishes that move, screens still painting fixed light colours
/// would break in dark mode, so the theme stays light, the picker stays
/// hidden and startup does not read the stored choice. M9 flips this.
const bool kAtomicThemeSwitchingEnabled = false;

/// Holds the person's [AppearanceMode] and maps it to a [ThemeMode].
///
/// Without a store (until [init] has run: while switching is disabled, or
/// when the device's store could not be opened) the choice starts as System
/// and lasts only until the app closes.
class AppearanceController extends ValueNotifier<AppearanceMode> {
  AppearanceController({
    AppearanceStore? store,
    this.themeSwitchingEnabled = kAtomicThemeSwitchingEnabled,
  })  : _store = store,
        super(store?.read() ?? AppearanceMode.system);

  static final AppearanceController instance = AppearanceController();

  AppearanceStore? _store;

  /// Injected so tests can exercise the mapping after M9.
  final bool themeSwitchingEnabled;

  /// What `MaterialApp.themeMode` uses now.
  ThemeMode get themeMode {
    if (!themeSwitchingEnabled) return ThemeMode.light;
    return switch (value) {
      AppearanceMode.system => ThemeMode.system,
      AppearanceMode.light => ThemeMode.light,
      AppearanceMode.dark => ThemeMode.dark,
    };
  }

  /// Opens the device's store and reads the stored choice. A startup step
  /// (see runStartupSequence), so the first themed frame already uses it.
  /// A failure leaves the controller without a store and the current choice
  /// in place, and is rethrown for startup to log.
  Future<void> init(
      {Future<AppearanceStore> Function() open =
          HiveAppearanceStore.open}) async {
    final store = await open();
    _store = store;
    value = store.read();
  }

  /// Applies [mode] at once and keeps it. Returns false when it could not be
  /// kept; the choice still applies until the app closes.
  Future<bool> setMode(AppearanceMode mode) async {
    value = mode;
    final store = _store;
    if (store == null) return false;
    try {
      await store.write(mode);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Makes the [AppearanceController] reachable from Settings without threading
/// it through constructors.
class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    super.key,
    required AppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppearanceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}
