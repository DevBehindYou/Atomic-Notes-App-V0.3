import 'package:atomic_notes/mascot/mascot_asset_resolver.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_cubit.dart';
import 'package:atomic_notes/mascot/mascot_preferences.dart';
import 'package:atomic_notes/page/endpage/mascot_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Preferences implements MascotPreferencesStore {
  final writes = <MascotPreferences>[];
  @override
  Future<MascotPreferenceRead> read() async =>
      const MascotPreferenceRead.missing();
  @override
  Future<void> write(MascotPreferences value) async {
    writes.add(value);
  }
}

class _NoFetchResolver implements MascotAssetResolver {
  @override
  Future<MascotAssetLease> openVerifiedClip(MascotClip clip) =>
      throw StateError('artwork seam renders local test label');
}

void main() {
  late _Preferences store;
  late MascotCubit preferences;
  setUp(() async {
    store = _Preferences();
    preferences = MascotCubit(store);
    await preferences.load();
  });
  tearDown(() async {
    await preferences.close();
  });
  Future<void> show(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: MascotSettingsPage(
                preferences: preferences,
                resolver: _NoFetchResolver(),
                artworkBuilder: (_, mascot, animate) => SizedBox(
                    width: 64,
                    height: 64,
                    child: Text(animate
                        ? 'Hero ${mascot.id}'
                        : 'Still ${mascot.id}'))))));
    await tester.pump();
  }

  testWidgets('all choices are included with no download controls',
      (tester) async {
    await show(tester);
    expect(
        find.text(
            'All 13 mascots are included and work offline. Each has four animations.'),
        findsOneWidget);
    expect(find.textContaining('Download'), findsNothing);
    for (final mascot in MascotCatalog.all) {
      await tester.scrollUntilVisible(
          find.byKey(ValueKey('choose-${mascot.id}')), 180);
      expect(find.byKey(ValueKey('choose-${mascot.id}')), findsOneWidget);
    }
    expect(store.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('an included non-default favorite updates and saves locally',
      (tester) async {
    await show(tester);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('choose-051-blink')), 180);
    await tester.tap(find.byKey(const ValueKey('choose-051-blink')));
    await tester.pump();
    expect(preferences.state.desired.selectedId, '051-blink');
    expect(store.writes.last.selectedId, '051-blink');
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pump();
    expect(find.text('Your mascot: Blink'), findsOneWidget);
    expect(find.text('Hero 051-blink'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('large text keeps favorite and motion controls usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await show(tester, scale: 2);
    await tester.scrollUntilVisible(find.byType(SwitchListTile), 120);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(preferences.state.desired.animationsEnabled, isFalse);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('choose-022-antimatter')), 120);
    await tester
        .ensureVisible(find.byKey(const ValueKey('choose-022-antimatter')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('choose-022-antimatter')));
    await tester.pump();
    expect(preferences.state.desired.selectedId, '022-antimatter');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
