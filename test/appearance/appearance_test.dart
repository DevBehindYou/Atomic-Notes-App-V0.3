// The theme choice (redesign ADR-004): box `appearanceBox`, key `themeMode`,
// absent or unknown = System, read at startup once switching is enabled.

import 'dart:io';

import 'package:atomic_notes/appearance/appearance_controller.dart';
import 'package:atomic_notes/appearance/appearance_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  group('stored value', () {
    test('only a known name reads as that mode; anything else is System', () {
      expect(HiveAppearanceStore.decode('dark'), AppearanceMode.dark);
      expect(HiveAppearanceStore.decode('light'), AppearanceMode.light);
      expect(HiveAppearanceStore.decode('system'), AppearanceMode.system);
      for (final raw in [
        null,
        'DARK',
        'sepia',
        '',
        2,
        true,
        const {'mode': 'dark'}
      ]) {
        expect(HiveAppearanceStore.decode(raw), AppearanceMode.system,
            reason: '$raw');
      }
    });
  });

  group('device store', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('atomic-appearance-');
      Hive.init(directory.path);
    });
    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('keeps the mode name under appearanceBox / themeMode', () async {
      final store = await HiveAppearanceStore.open();
      expect(store.read(), AppearanceMode.system, reason: 'absent');
      await store.write(AppearanceMode.dark);
      await Hive.close();

      final raw = await Hive.openBox<dynamic>('appearanceBox');
      expect(raw.toMap(), {'themeMode': 'dark'});
      expect((await HiveAppearanceStore.open()).read(), AppearanceMode.dark);
    });

    test('a corrupt value reads as System and is replaced by the next choice',
        () async {
      final raw = await Hive.openBox<dynamic>('appearanceBox');
      await raw.put('themeMode', {'schemaVersion': 9});
      final controller = AppearanceController(themeSwitchingEnabled: true);
      await controller.init();
      expect(controller.value, AppearanceMode.system);
      expect(await controller.setMode(AppearanceMode.light), isTrue);
      expect(raw.get('themeMode'), 'light');
    });

    test('init reads the stored choice', () async {
      await (await Hive.openBox<dynamic>('appearanceBox'))
          .put('themeMode', 'dark');
      final controller = AppearanceController(themeSwitchingEnabled: true);
      await controller.init();
      expect(controller.themeMode, ThemeMode.dark);
    });
  });

  group('controller', () {
    test('stays light while theme switching is disabled', () {
      expect(kAtomicThemeSwitchingEnabled, isFalse);
      final controller = AppearanceController(
          store: MemoryAppearanceStore(AppearanceMode.dark));
      expect(controller.value, AppearanceMode.dark);
      expect(controller.themeMode, ThemeMode.light);
    });

    test('maps each mode once switching is enabled', () {
      final controller = AppearanceController(
          store: MemoryAppearanceStore(), themeSwitchingEnabled: true);
      expect(controller.themeMode, ThemeMode.system);
      controller.value = AppearanceMode.light;
      expect(controller.themeMode, ThemeMode.light);
      controller.value = AppearanceMode.dark;
      expect(controller.themeMode, ThemeMode.dark);
    });

    test('a choice applies at once and is kept', () async {
      final store = MemoryAppearanceStore();
      final controller =
          AppearanceController(store: store, themeSwitchingEnabled: true);
      var notified = 0;
      controller.addListener(() => notified++);
      expect(await controller.setMode(AppearanceMode.dark), isTrue);
      expect(notified, 1);
      expect(store.value, AppearanceMode.dark);
    });

    test('a failed write still applies the choice and says it was not kept',
        () async {
      final store = MemoryAppearanceStore()..failWrites = true;
      final controller =
          AppearanceController(store: store, themeSwitchingEnabled: true);
      expect(await controller.setMode(AppearanceMode.dark), isFalse);
      expect(controller.value, AppearanceMode.dark);
    });

    test('a store that cannot be opened leaves System, and nothing is kept',
        () async {
      final controller = AppearanceController(themeSwitchingEnabled: true);
      await expectLater(
          controller.init(open: () => Future.error(StateError('locked'))),
          throwsStateError);
      expect(controller.value, AppearanceMode.system);
      expect(await controller.setMode(AppearanceMode.dark), isFalse);
      expect(controller.themeMode, ThemeMode.dark,
          reason: 'the choice still applies until the app closes');
    });
  });

  testWidgets('a theme change rebuilds MaterialApp, not what sits above it',
      (tester) async {
    final controller = AppearanceController(
        store: MemoryAppearanceStore(), themeSwitchingEnabled: true);
    var outerBuilds = 0;
    await tester.pumpWidget(AppearanceScope(
      controller: controller,
      child: Builder(builder: (context) {
        outerBuilds++;
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) => MaterialApp(
            themeMode: controller.themeMode,
            theme: ThemeData(brightness: Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            home: Builder(
                builder: (context) => Text(Theme.of(context).brightness.name)),
          ),
        );
      }),
    ));
    await controller.setMode(AppearanceMode.dark);
    await tester.pumpAndSettle(); // MaterialApp animates the theme change
    expect(find.text('dark'), findsOneWidget);
    expect(outerBuilds, 1);
  });
}
