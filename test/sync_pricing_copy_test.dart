import 'package:atomic_notes/theme/app_theme.dart';
import 'package:atomic_notes/utility/intropages/energy_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('R8 pricing tour explains upload batches at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!), home: const EnergyIntroScreen()));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
      final explanation = find.textContaining('per upload batch');
      expect(explanation, findsOneWidget);
      final text = tester.widget<Text>(explanation).data!;
      expect(text, contains('Large instant syncs can cost more than 10.'));
      expect(text, contains('Receive-only sync is free.'));
      await tester.ensureVisible(explanation);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Got it').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
