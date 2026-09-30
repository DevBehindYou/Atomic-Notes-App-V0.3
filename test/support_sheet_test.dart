import 'package:atomic_notes/page/endpage/energy_page.dart';
import 'package:atomic_notes/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_energy_store.dart';
import 'support/fake_notes_source.dart';

void main() {
  for (final scenario in [
    (name: 'normal portrait', size: const Size(375, 667), scale: 1.0),
    (name: 'large text portrait', size: const Size(375, 667), scale: 2.0),
    (name: 'large text landscape', size: const Size(667, 375), scale: 2.0),
  ]) {
    testWidgets('R22 support sheet remains reachable at ${scenario.name}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final scale = ValueNotifier<double>(1);
      final store = FakeEnergyStore();
      final notes = FakeNotesSource();
      addTearDown(scale.dispose);
      addTearDown(store.dispose);
      addTearDown(notes.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: scale,
          builder: (context, value, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(value),
            ),
            child: child!,
          ),
        ),
        home: EnergyPage(store: store, notes: notes),
      ));
      await tester.pumpAndSettle();
      final open = find.text('GET ATOMIC COINS');
      await tester.scrollUntilVisible(open, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.text('COIN STORE'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Resize/scale the actual open modal, as when rotating or changing font size.
      tester.view.physicalSize = scenario.size;
      scale.value = scenario.scale;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'The modal must fit or scroll instead of overflowing.');
      final support = find.text('SUPPORT ATOMIC NOTES');
      await tester.ensureVisible(support);
      await tester.pumpAndSettle();
      expect(support.hitTestable(), findsOneWidget);
      final dismiss = find.text('NOT NOW');
      await tester.ensureVisible(dismiss);
      await tester.pumpAndSettle();
      expect(dismiss.hitTestable(), findsOneWidget);
      await tester.tap(dismiss);
      await tester.pumpAndSettle();
      expect(find.text('COIN STORE'), findsNothing);
      expect(store.converted, isEmpty);
      expect(store.upgrades, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
