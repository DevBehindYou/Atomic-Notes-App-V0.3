// The shared touch surface (Target-UI-Architecture section 2, ADR-011).

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

/// The scale actually rendered for the child.
double _scale(WidgetTester tester) => tester
    .widget<ScaleTransition>(find.descendant(
        of: find.byType(AtomicPressable),
        matching: find.byType(ScaleTransition)))
    .scale
    .value;

Widget _dot(
        {VoidCallback? onTap, VoidCallback? onLongPress, FocusNode? node}) =>
    Center(
      child: AtomicPressable(
        onTap: onTap,
        onLongPress: onLongPress,
        focusNode: node,
        semanticsLabel: 'Dot',
        child: const SizedBox.square(dimension: 20),
      ),
    );

void main() {
  testWidgets('a press scales the child to 0.965 and releases back to 1',
      (tester) async {
    var taps = 0;
    await pumpThemed(tester, _dot(onTap: () => taps++),
        theme: AtomicTheme.light);
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(AtomicPressable)));
    await tester.pump(kPressTimeout);
    await tester.pump(AtomicMotion.pressIn);
    expect(_scale(tester), closeTo(AtomicMotion.pressScale, 1e-9));
    await gesture.up();
    expect(taps, 1);
    var peak = 0.0;
    for (var t = 0; t < AtomicMotion.pressOut.inMilliseconds; t += 10) {
      await tester.pump(const Duration(milliseconds: 10));
      if (_scale(tester) > peak) peak = _scale(tester);
    }
    expect(peak, greaterThan(1), reason: 'the return overshoots');
    expect(peak, lessThan(1.01), reason: 'and the overshoot is bounded');
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
  });

  testWidgets('the return does not block the next tap', (tester) async {
    var taps = 0;
    await pumpThemed(tester, _dot(onTap: () => taps++),
        theme: AtomicTheme.light);
    await tester.tap(find.byType(AtomicPressable));
    await tester.pump(const Duration(milliseconds: 50)); // mid-return
    await tester.tap(find.byType(AtomicPressable));
    expect(taps, 2);
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion keeps the child still', (tester) async {
    await pumpThemed(tester, _dot(onTap: () {}),
        theme: AtomicTheme.light, disableAnimations: true);
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(AtomicPressable)));
    await tester.pump(kPressTimeout);
    expect(_scale(tester), 1);
    await gesture.up();
  });

  group('reduced motion turned on during an interaction (review F04)', () {
    testWidgets('mid-press: the child settles at once', (tester) async {
      await pumpThemed(tester, _dot(onTap: () {}), theme: AtomicTheme.light);
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(AtomicPressable)));
      await tester.pump(kPressTimeout);
      await tester.pump(const Duration(milliseconds: 40));
      expect(_scale(tester), lessThan(1), reason: 'pressing in');

      await pumpThemed(tester, _dot(onTap: () {}),
          theme: AtomicTheme.light, disableAnimations: true);
      expect(_scale(tester), 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_scale(tester), 1, reason: 'nothing resumes');
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_scale(tester), 1, reason: 'the release does not animate');
    });

    testWidgets('mid-release: the overshoot is cancelled at once',
        (tester) async {
      await pumpThemed(tester, _dot(onTap: () {}), theme: AtomicTheme.light);
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(AtomicPressable)));
      await tester.pump(kPressTimeout);
      await tester.pump(AtomicMotion.pressIn);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_scale(tester), isNot(1), reason: 'returning');

      await pumpThemed(tester, _dot(onTap: () {}),
          theme: AtomicTheme.light, disableAnimations: true);
      expect(_scale(tester), 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scale(tester), 1, reason: 'no overshoot after cancelling');
    });

    testWidgets('turning it off again restores the full press', (tester) async {
      await pumpThemed(tester, _dot(onTap: () {}),
          theme: AtomicTheme.light, disableAnimations: true);
      await pumpThemed(tester, _dot(onTap: () {}), theme: AtomicTheme.light);
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(AtomicPressable)));
      await tester.pump(kPressTimeout);
      await tester.pump(AtomicMotion.pressIn);
      expect(_scale(tester), closeTo(AtomicMotion.pressScale, 1e-9));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scale(tester), 1);
    });

    testWidgets('disabled mid-press: the child returns', (tester) async {
      await pumpThemed(tester, _dot(onTap: () {}), theme: AtomicTheme.light);
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(AtomicPressable)));
      await tester.pump(kPressTimeout);
      await tester.pump(AtomicMotion.pressIn);
      await pumpThemed(tester, _dot(), theme: AtomicTheme.light);
      await tester.pumpAndSettle();
      expect(_scale(tester), 1);
      await gesture.up();
    });
  });

  testWidgets('a 20 dp child gets a 48 dp target', (tester) async {
    var taps = 0;
    await pumpThemed(tester, _dot(onTap: () => taps++),
        theme: AtomicTheme.light);
    final box = tester.getRect(find.byType(AtomicPressable));
    expect(box.width, greaterThanOrEqualTo(48));
    expect(box.height, greaterThanOrEqualTo(48));
    await tester.tapAt(box.topLeft + const Offset(2, 2));
    expect(taps, 1, reason: 'the corner of the target, outside the child');
  });

  testWidgets('semantics: a button with its label, enabled or not',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpThemed(tester, _dot(onTap: () {}), theme: AtomicTheme.light);
    expect(
        tester.getSemantics(find.bySemanticsLabel('Dot')),
        isSemantics(
            label: 'Dot', isButton: true, isEnabled: true, hasTapAction: true));

    await pumpThemed(tester, _dot(), theme: AtomicTheme.light);
    expect(tester.getSemantics(find.bySemanticsLabel('Dot')),
        isSemantics(isButton: true, isEnabled: false));
    handle.dispose();
  });

  testWidgets('disabled ignores taps and does not scale', (tester) async {
    await pumpThemed(tester, _dot(), theme: AtomicTheme.light);
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(AtomicPressable)));
    await tester.pump(kPressTimeout);
    expect(_scale(tester), 1);
    await gesture.up();
  });

  testWidgets('long-press is separate from tap', (tester) async {
    var taps = 0, longs = 0;
    await pumpThemed(
        tester, _dot(onTap: () => taps++, onLongPress: () => longs++),
        theme: AtomicTheme.light);
    await tester.longPress(find.byType(AtomicPressable));
    await tester.pumpAndSettle();
    expect((taps, longs), (0, 1));
    expect(_scale(tester), 1);
  });

  for (final MapEntry(key: name, value: theme) in atomicThemes.entries) {
    testWidgets('keyboard focus draws the focus ring and Enter taps ($name)',
        (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic);
      final node = FocusNode();
      addTearDown(node.dispose);
      var taps = 0;
      await pumpThemed(tester, _dot(onTap: () => taps++, node: node),
          theme: theme);
      CustomPaint paint() => tester.widget<CustomPaint>(find
          .descendant(
              of: find.byType(AtomicPressable),
              matching: find.byType(CustomPaint))
          .first);
      expect(paint().foregroundPainter, isNull);

      node.requestFocus();
      await tester.pump();
      expect(paint().foregroundPainter, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, 1);
      expect(theme.extension<AtomicColors>()!.focus, isNot(Colors.transparent));
    });
  }

  testWidgets('plays its haptic on tap only', (tester) async {
    final calls = <String?>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String?);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpThemed(
      tester,
      Center(
        child: AtomicPressable(
          onTap: () {},
          onLongPress: () {},
          haptic: AtomicHaptic.light,
          child: const SizedBox.square(dimension: 48),
        ),
      ),
      theme: AtomicTheme.light,
    );
    await tester.tap(find.byType(AtomicPressable));
    await tester.longPress(find.byType(AtomicPressable));
    await tester.pumpAndSettle();
    expect(calls, ['HapticFeedbackType.lightImpact']);

    AtomicHaptics.enabled = false;
    addTearDown(() => AtomicHaptics.enabled = true);
    await tester.tap(find.byType(AtomicPressable));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
  });
}
