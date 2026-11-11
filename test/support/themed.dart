import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two redesign themes, for running one widget test in both.
final Map<String, ThemeData> atomicThemes = {
  'light': AtomicTheme.light,
  'dark': AtomicTheme.dark,
};

/// Pumps [child] inside a [MaterialApp] using [theme], with optional media
/// overrides for text scale and reduced motion.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  required ThemeData theme,
  double textScale = 1.0,
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
}

/// Pumps [child] at text scale 2.0 in a 320 dp wide frame: the layout check
/// every `lib/ui` widget passes (Target-UI-Architecture section 6). The
/// frame scrolls vertically, as a page does, so only width can overflow.
/// Follow it with `expect(tester.takeException(), isNull)`.
Future<void> pumpNarrow(
  WidgetTester tester,
  Widget child, {
  required ThemeData theme,
  double textScale = 2.0,
  double width = 320,
}) {
  return pumpThemed(
    tester,
    SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
    theme: theme,
    textScale: textScale,
  );
}
