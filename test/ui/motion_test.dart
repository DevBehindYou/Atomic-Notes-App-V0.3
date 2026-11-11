// Motion primitives (motion spec, premium motion system; ADR-011).

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/mascot/mascot_stage.dart';
import 'package:atomic_notes/ui/motion/ambient.dart';
import 'package:atomic_notes/ui/motion/burst.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/motion/odometer.dart';
import 'package:atomic_notes/ui/motion/orbit_ring.dart';
import 'package:atomic_notes/ui/motion/slide_to_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

double _opacityOf(WidgetTester tester, Finder child) => tester
    .widget<FadeTransition>(
        find.ancestor(of: child, matching: find.byType(FadeTransition)).first)
    .opacity
    .value;

void main() {
  final theme = AtomicTheme.light;

  group('EntranceGroup', () {
    Widget page() => EntranceGroup(
          child: Column(children: [
            const Entrance(index: 0, child: Text('header')),
            const Entrance(index: 1, child: Text('strip')),
            for (var i = 0; i < 10; i++)
              Stagger(index: i, child: Text('card $i')),
          ]),
        );

    testWidgets('blocks cascade in once, 60 ms apart, then rest at full',
        (tester) async {
      await pumpThemed(tester, page(), theme: theme);
      expect(_opacityOf(tester, find.text('header')), 0);
      await tester.pump(); // post-frame start
      await tester.pump(const Duration(milliseconds: 60));
      expect(_opacityOf(tester, find.text('header')),
          greaterThan(_opacityOf(tester, find.text('strip'))));
      await tester.pumpAndSettle();
      expect(_opacityOf(tester, find.text('header')), 1);
      expect(_opacityOf(tester, find.text('card 7')), 1);
    });

    testWidgets('only the first eight list items stagger', (tester) async {
      await pumpThemed(tester, page(), theme: theme);
      // card 8 has no entrance of its own: its nearest fade is the route's.
      final ownFades = tester.widgetList(find.ancestor(
          of: find.text('card 8'), matching: find.byType(FadeTransition)));
      final staggeredFades = tester.widgetList(find.ancestor(
          of: find.text('card 7'), matching: find.byType(FadeTransition)));
      expect(staggeredFades.length, ownFades.length + 1);
      await tester.pumpAndSettle();
    });

    testWidgets('reduced motion shows everything at once', (tester) async {
      await pumpThemed(tester, page(), theme: theme, disableAnimations: true);
      expect(_opacityOf(tester, find.text('header')), 1);
      expect(_opacityOf(tester, find.text('card 3')), 1);
    });

    testWidgets('returning to the route does not replay it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: EntranceGroup(
              child: Column(children: [
                const Entrance(index: 0, child: Text('header')),
                TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(body: Text('next')))),
                  child: const Text('push'),
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      expect(_opacityOf(tester, find.text('header')), 1);
      await tester.pumpAndSettle();
    });
  });

  group('Odometer', () {
    testWidgets('rolls from zero to its digits; one label for readers',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpThemed(
          tester, const Odometer(text: '1,250', style: AtomicType.display),
          theme: theme);
      expect(find.bySemanticsLabel('1,250'), findsOneWidget);
      FractionalTranslation column(int position) =>
          tester.widget<FractionalTranslation>(find.descendant(
              of: find.byKey(ValueKey('digit-$position')),
              matching: find.byType(FractionalTranslation)));
      expect(column(2).translation.dy, 0, reason: 'the 2 starts at 0');
      await tester.pumpAndSettle();
      expect(column(2).translation.dy, closeTo(-0.2, 1e-9));
      expect(column(3).translation.dy, closeTo(-0.1, 1e-9));
      expect(find.text(','), findsOneWidget);
      handle.dispose();
    });

    testWidgets('reduced motion shows the value at once', (tester) async {
      await pumpThemed(
          tester, const Odometer(text: '7', style: AtomicType.display),
          theme: theme, disableAnimations: true);
      await tester.pump();
      expect(
          tester
              .widget<FractionalTranslation>(find.descendant(
                  of: find.byType(Odometer),
                  matching: find.byType(FractionalTranslation)))
              .translation
              .dy,
          closeTo(-0.7, 1e-9));
    });
  });

  group('Burst', () {
    testWidgets('plays once per trigger and paints nothing after',
        (tester) async {
      Widget burst(int trigger) =>
          Burst(trigger: trigger, child: const SizedBox.square(dimension: 40));
      CustomPaint paint() => tester.widget<CustomPaint>(find.descendant(
          of: find.byType(Burst), matching: find.byType(CustomPaint)));
      await pumpThemed(tester, Center(child: burst(0)), theme: theme);
      expect(paint().foregroundPainter, isNull);
      await pumpThemed(tester, Center(child: burst(1)), theme: theme);
      await tester.pump(const Duration(milliseconds: 100));
      expect(paint().foregroundPainter, isNotNull);
      await tester.pumpAndSettle();
      expect(paint().foregroundPainter, isNull);
    });

    testWidgets('never plays under reduced motion', (tester) async {
      Widget burst(int trigger) =>
          Burst(trigger: trigger, child: const SizedBox.square(dimension: 40));
      await pumpThemed(tester, Center(child: burst(0)),
          theme: theme, disableAnimations: true);
      await pumpThemed(tester, Center(child: burst(1)),
          theme: theme, disableAnimations: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('OrbitRing', () {
    testWidgets('circles while busy and stops when done', (tester) async {
      Widget ring(bool busy) => Center(
          child: OrbitRing(
              busy: busy, child: const SizedBox.square(dimension: 44)));
      await pumpThemed(tester, ring(true), theme: theme);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await pumpThemed(tester, ring(false), theme: theme);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('reduced motion: a still ring, no frames', (tester) async {
      await pumpThemed(
          tester,
          const Center(
              child:
                  OrbitRing(busy: true, child: SizedBox.square(dimension: 44))),
          theme: theme,
          disableAnimations: true);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
          tester
              .widget<CustomPaint>(find.descendant(
                  of: find.byType(OrbitRing),
                  matching: find.byType(CustomPaint)))
              .foregroundPainter,
          isNotNull);
    });
  });

  group('Ambient', () {
    setUp(AmbientBudget.reset);

    Widget loop(String label) => Ambient(
          period: const Duration(seconds: 2),
          builder: (context, t, child) =>
              Opacity(opacity: 0.5 + t / 2, child: child),
          child: Text(label),
        );

    testWidgets('at most two loops run at once', (tester) async {
      await pumpThemed(
          tester, Column(children: [loop('a'), loop('b'), loop('c')]),
          theme: theme);
      expect(AmbientBudget.active, AtomicMotion.maxAmbientLoops);
      await pumpThemed(tester, const SizedBox(), theme: theme);
      expect(AmbientBudget.active, 0, reason: 'released on dispose');
    });

    testWidgets(
        'stops when its route is covered, in the background, and '
        'under reduced motion', (tester) async {
      await pumpThemed(tester, TickerMode(enabled: false, child: loop('a')),
          theme: theme);
      expect(AmbientBudget.active, 0);

      await pumpThemed(tester, loop('a'), theme: theme);
      expect(AmbientBudget.active, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(AmbientBudget.active, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(AmbientBudget.active, 1);

      await pumpThemed(tester, loop('a'),
          theme: theme, disableAnimations: true);
      expect(AmbientBudget.active, 0);
    });
  });

  group('SlideToConfirm', () {
    Future<List<String>> pumpSlide(WidgetTester tester,
        {bool slow = false, double textScale = 1}) async {
      final calls = <String>[];
      await pumpNarrow(
        tester,
        SlideToConfirm(
          label: 'wipe cloud notes',
          onConfirmed: () async {
            calls.add('confirmed');
            if (slow) await Future<void>.delayed(const Duration(seconds: 1));
          },
        ),
        theme: theme,
        textScale: textScale,
      );
      return calls;
    }

    testWidgets('a short drag snaps back and does nothing', (tester) async {
      final calls = await pumpSlide(tester);
      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('Slide to wipe cloud notes'), findsOneWidget);
    });

    testWidgets('a full drag confirms once, with a medium haptic',
        (tester) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final calls = await pumpSlide(tester, slow: true);
      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(400, 0));
      await tester.pump();
      expect(calls, ['confirmed']);
      expect(find.text('Working…'), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Slide to wipe cloud notes'), findsOneWidget);
    });

    testWidgets('two taps confirm; one tap only arms, then disarms',
        (tester) async {
      final calls = await pumpSlide(tester);
      await tester.tap(find.byKey(SlideToConfirm.thumbKey));
      await tester.pump();
      expect(find.text('Tap again to confirm'), findsOneWidget);
      await tester.pump(SlideToConfirm.armedFor);
      expect(find.text('Slide to wipe cloud notes'), findsOneWidget);
      expect(calls, isEmpty);

      await tester.tap(find.byKey(SlideToConfirm.thumbKey));
      await tester.pump();
      await tester.tap(find.byKey(SlideToConfirm.thumbKey));
      await tester.pumpAndSettle();
      expect(calls, ['confirmed']);
    });

    testWidgets('screen readers get a slider whose increase confirms',
        (tester) async {
      final handle = tester.ensureSemantics();
      final calls = await pumpSlide(tester);
      final node = tester
          .getSemantics(find.bySemanticsLabel('Slide to wipe cloud notes'));
      expect(node,
          isSemantics(isSlider: true, value: '0%', hasIncreaseAction: true));
      tester.semantics
          .increase(find.semantics.byLabel('Slide to wipe cloud notes'));
      await tester.pumpAndSettle();
      expect(calls, ['confirmed']);
      handle.dispose();
    });

    testWidgets('fits 2.0 text in 320 dp', (tester) async {
      await pumpSlide(tester, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('MascotStage: the light disc in both themes', (tester) async {
    for (final t in atomicThemes.values) {
      await pumpThemed(
          tester,
          const Center(
              child:
                  MascotStage(size: 56, child: SizedBox.square(dimension: 44))),
          theme: t);
      final deco = tester
          .widget<Container>(find.byType(Container).first)
          .decoration as BoxDecoration;
      expect(deco.color, t.extension<AtomicColors>()!.mascotStage);
      expect(tester.getSize(find.byType(MascotStage)), const Size(56, 56));
    }
    expect(MascotStage.artSize(56), 44);
  });
}
