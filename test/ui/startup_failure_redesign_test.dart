// The startup failure screen after R48 (screens spec, Splash and startup
// failure): system-theme colours, safe primary copy, the trace gated behind
// "Show details" in a mono surfaceInset box, and a danger icon circle.
// Every value here is synthetic.

import 'package:atomic_notes/page/startup_failed_page.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _error = 'StateError: synthetic hive failure at /synthetic/path';

void _phone(WidgetTester tester,
    {double textScale = 1, Brightness brightness = Brightness.light}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

Color? _canvas(WidgetTester tester) =>
    tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;

final _toggle = find.byKey(const ValueKey('startup-failed-details'));
final _trace = find.byKey(const ValueKey('startup-failed-trace'));

void main() {
  testWidgets('the primary copy is safe: no raw error until Show details',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(const StartupFailedApp(error: _error));
    expect(find.text(StartupFailedPage.title), findsOneWidget);
    expect(find.text(StartupFailedPage.body), findsOneWidget);
    expect(find.text(StartupFailedPage.showDetails), findsOneWidget);
    expect(find.textContaining('synthetic hive failure'), findsNothing);
    expect(_trace, findsNothing);
  });

  testWidgets('Show details reveals the trace; Hide details hides it again',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(const StartupFailedApp(error: _error));
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    expect(find.text(_error), findsOneWidget);
    expect(find.text(StartupFailedPage.hideDetails), findsOneWidget);
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    expect(find.text(_error), findsNothing);
    expect(find.text(StartupFailedPage.showDetails), findsOneWidget);
  });

  testWidgets('the trace is mono text in a surfaceInset box', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const StartupFailedApp(error: _error));
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    final box = tester.widget<DecoratedBox>(_trace).decoration as BoxDecoration;
    expect(box.color, AtomicColors.light.surfaceInset);
    final text = tester.widget<Text>(find.text(_error));
    expect(text.style?.fontFamily, AtomicType.mono.fontFamily);
    expect(text.style?.color, AtomicColors.light.textPrimary);
  });

  for (final (brightness, tokens) in [
    (Brightness.light, AtomicColors.light),
    (Brightness.dark, AtomicColors.dark),
  ]) {
    testWidgets('follows the ${brightness.name} system setting',
        (tester) async {
      _phone(tester, brightness: brightness);
      await tester.pumpWidget(const StartupFailedApp(error: _error));
      expect(_canvas(tester), tokens.canvas);
      final circle = tester
          .widget<Container>(find.byKey(const ValueKey('startup-failed-icon')))
          .decoration as BoxDecoration;
      expect(circle.color, tokens.danger);
      expect(circle.shape, BoxShape.circle);
      final title = tester.widget<Text>(find.text(StartupFailedPage.title));
      expect(title.style?.color, tokens.textPrimary);
    });
  }

  testWidgets(
      'the title is a header and the toggle is one named button that a '
      'keyboard can reach and press', (tester) async {
    _phone(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const StartupFailedApp(error: _error));
    expect(tester.getSemantics(find.text(StartupFailedPage.title)),
        matchesSemantics(label: StartupFailedPage.title, isHeader: true));
    expect(
        tester.getSemantics(_toggle),
        matchesSemantics(
            label: StartupFailedPage.showDetails,
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true));
    final size = tester.getSize(_toggle);
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));

    // Keyboard: move focus to the toggle and press Enter.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(_error), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a long trace at 320 dp and 2.0 text scrolls without overflow',
      (tester) async {
    _phone(tester, textScale: 2, brightness: Brightness.dark);
    final long = List.filled(30, 'synthetic-frame-without-spaces').join();
    await tester.pumpWidget(StartupFailedApp(error: long));
    await tester.ensureVisible(_toggle);
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(long), findsOneWidget);
  });

  testWidgets('needs no app theme: the page alone falls back to the system',
      (tester) async {
    _phone(tester, brightness: Brightness.dark);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: const StartupFailedPage(error: _error),
    ));
    expect(tester.takeException(), isNull);
    expect(_canvas(tester), AtomicColors.dark.canvas);
  });
}
