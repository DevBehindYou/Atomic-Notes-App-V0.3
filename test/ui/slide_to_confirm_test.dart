// The destructive slide-to-confirm (components spec; Codex review F02/F03).

import 'dart:async';

import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/motion/slide_to_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

const _label = 'wipe cloud notes';
const _idle = 'Slide to $_label';

/// Pumps the control and returns the list its callback appends to.
Future<List<String>> _pump(
  WidgetTester tester, {
  Future<void> Function()? onConfirmed,
  Object? target,
  double textScale = 1,
}) async {
  final calls = <String>[];
  await pumpNarrow(
    tester,
    SlideToConfirm(
      label: _label,
      target: target,
      onConfirmed: () async {
        calls.add('confirmed');
        await onConfirmed?.call();
      },
    ),
    theme: AtomicTheme.light,
    textScale: textScale,
  );
  return calls;
}

Finder get _thumb => find.byKey(SlideToConfirm.thumbKey);

/// Drags the thumb far past the threshold without lifting the finger.
Future<TestGesture> _dragPastThreshold(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(_thumb));
  for (var i = 0; i < 8; i++) {
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
  }
  return gesture;
}

void main() {
  group('drag', () {
    testWidgets('lifted past the threshold confirms exactly once (control)',
        (tester) async {
      final calls = await _pump(tester);
      final gesture = await _dragPastThreshold(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, ['confirmed']);
    });

    testWidgets('F02: a drag cancelled past the threshold never confirms',
        (tester) async {
      final calls = await _pump(tester);
      final gesture = await _dragPastThreshold(tester);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text(_idle), findsOneWidget, reason: 'snapped back');
    });

    testWidgets('a drag cancelled below the threshold never confirms',
        (tester) async {
      final calls = await _pump(tester);
      final gesture = await tester.startGesture(tester.getCenter(_thumb));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('lifted below the threshold snaps back and does nothing',
        (tester) async {
      final calls = await _pump(tester);
      await tester.drag(_thumb, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text(_idle), findsOneWidget);
    });

    testWidgets('the route going away mid-drag never confirms', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: AtomicTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: SizedBox(
                    width: 320,
                    child: SlideToConfirm(
                      label: _label,
                      onConfirmed: () async => calls.add('confirmed'),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final gesture = await _dragPastThreshold(tester);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });
  });

  group('activate twice', () {
    testWidgets('one tap only arms and says so; a second tap confirms',
        (tester) async {
      final calls = await _pump(tester);
      await tester.tap(_thumb);
      await tester.pump();
      expect(find.text(SlideToConfirm.armedText), findsOneWidget);
      expect(calls, isEmpty);
      await tester.tap(_thumb);
      await tester.pumpAndSettle();
      expect(calls, ['confirmed']);
    });

    testWidgets('the arm expires', (tester) async {
      final calls = await _pump(tester);
      await tester.tap(_thumb);
      await tester.pump(SlideToConfirm.armedFor);
      expect(find.text(_idle), findsOneWidget);
      await tester.tap(_thumb);
      await tester.pump();
      expect(calls, isEmpty, reason: 'the second tap only re-arms');
      expect(find.text(SlideToConfirm.armedText), findsOneWidget);
      await tester.pump(SlideToConfirm.armedFor);
    });

    testWidgets('a new target withdraws the arm', (tester) async {
      final calls = await _pump(tester, target: 'notes:a');
      await tester.tap(_thumb);
      await tester.pump();
      expect(find.text(SlideToConfirm.armedText), findsOneWidget);
      await _pump(tester, target: 'notes:b');
      expect(find.text(_idle), findsOneWidget);
      await tester.tap(_thumb);
      await tester.pump();
      expect(calls, isEmpty);
      await tester.pump(SlideToConfirm.armedFor);
    });

    testWidgets('going to the background withdraws the arm', (tester) async {
      final calls = await _pump(tester);
      await tester.tap(_thumb);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text(_idle), findsOneWidget);
      await tester.tap(_thumb);
      await tester.pump();
      expect(calls, isEmpty);
      await tester.pump(SlideToConfirm.armedFor);
    });
  });

  group('assistive and keyboard access (F03)', () {
    testWidgets('no single semantics action confirms; two activations do',
        (tester) async {
      final handle = tester.ensureSemantics();
      final calls = await _pump(tester);
      final node = find.semantics.byLabel(_idle);
      expect(
          tester.getSemantics(find.bySemanticsLabel(_idle)),
          isSemantics(
              isButton: true,
              hasTapAction: true,
              hasIncreaseAction: false,
              isLiveRegion: true));
      tester.semantics.tap(node);
      await tester.pump();
      expect(calls, isEmpty);
      expect(tester.getSemantics(find.bySemanticsLabel(_idle)),
          isSemantics(value: 'Armed. Activate again to confirm'));
      tester.semantics.tap(node);
      await tester.pumpAndSettle();
      expect(calls, ['confirmed']);
      handle.dispose();
    });

    testWidgets('Enter arms, Enter confirms; Escape disarms', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic);
      final calls = await _pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text(SlideToConfirm.armedText), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text(_idle), findsOneWidget);
      expect(calls, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, ['confirmed']);
    });
  });

  group('busy and errors', () {
    testWidgets('while working: announced, and every input is ignored',
        (tester) async {
      final handle = tester.ensureSemantics();
      final gate = Completer<void>();
      final calls = await _pump(tester, onConfirmed: () => gate.future);
      final gesture = await _dragPastThreshold(tester);
      await gesture.up();
      await tester.pump();
      expect(find.text(SlideToConfirm.workingText), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel(_idle)),
          isSemantics(isEnabled: false, value: 'Working'));
      await tester.tap(_thumb, warnIfMissed: false);
      await tester.tap(_thumb, warnIfMissed: false);
      await tester.drag(_thumb, const Offset(400, 0), warnIfMissed: false);
      await tester.pump();
      expect(calls, ['confirmed'], reason: 'no duplicate while busy');
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(_idle), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a failing action resets the control and is reported',
        (tester) async {
      final calls = await _pump(tester,
          onConfirmed: () => Future<void>.error(StateError('wipe failed')));
      final gesture = await _dragPastThreshold(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, ['confirmed']);
      expect(tester.takeException(), isA<StateError>());
      expect(find.text(_idle), findsOneWidget);
    });
  });

  testWidgets('fits 2.0 text in 320 dp, armed and idle', (tester) async {
    await _pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(_thumb);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(SlideToConfirm.armedFor);
  });
}
