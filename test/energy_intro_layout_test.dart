import 'package:atomic_notes/theme/app_theme.dart';
import 'package:atomic_notes/utility/intropages/energy_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    (name: 'normal portrait control', size: const Size(390, 844), scale: 1.0),
    (name: 'large text portrait', size: const Size(390, 844), scale: 2.0),
    (
      name: 'large text narrow portrait',
      size: const Size(320, 640),
      scale: 2.0
    ),
    (name: 'large text landscape', size: const Size(844, 390), scale: 2.0),
  ]) {
    testWidgets('R30 energy tour navigation fits ${scenario.name}',
        (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      addTearDown(() => FlutterError.onError = previous);
      Future<void> advance() async {
        FlutterError.onError = errors.add;
        try {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        } finally {
          FlutterError.onError = previous;
        }
      }

      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scenario.scale)),
              child: child!),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const EnergyIntroScreen())),
                      child: const Text('Start tour'))))));
      await tester.tap(find.text('Start tour'));
      await advance();
      for (var step = 0; step < 4; step++) {
        expect(errors, isEmpty,
            reason: errors.map((e) => e.toString()).join('\n'));
        final action = find.text(step == 3 ? 'GOT IT' : 'NEXT');
        expect(action.hitTestable(), findsOneWidget);
        expect(find.text('SKIP').hitTestable(), findsOneWidget);
        await tester.tap(action);
        await advance();
      }
      expect(find.text('Start tour'), findsOneWidget);
      expect(errors, isEmpty,
          reason: errors.map((e) => e.toString()).join('\n'));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
