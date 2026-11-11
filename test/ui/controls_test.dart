// Switch, checkbox and segmented control (components spec).

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/ui/controls/atomic_checkbox.dart';
import 'package:atomic_notes/ui/controls/atomic_switch.dart';
import 'package:atomic_notes/ui/controls/segmented.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

List<String?> _haptics(WidgetTester tester) {
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
  return calls;
}

void main() {
  for (final MapEntry(key: name, value: theme) in atomicThemes.entries) {
    final c = theme.extension<AtomicColors>()!;

    group('AtomicSwitch ($name)', () {
      testWidgets('a toggle, not a button; flips and clicks', (tester) async {
        final handle = tester.ensureSemantics();
        final haptics = _haptics(tester);
        var value = false;
        await pumpThemed(
          tester,
          StatefulBuilder(
            builder: (context, setState) => Center(
              child: AtomicSwitch(
                value: value,
                semanticsLabel: 'Cloud sync',
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
          theme: theme,
        );
        expect(
            tester.getSemantics(find.bySemanticsLabel('Cloud sync')),
            isSemantics(
                isButton: false, hasToggledState: true, isToggled: false));
        await tester.tap(find.byType(AtomicSwitch));
        await tester.pumpAndSettle();
        expect(value, isTrue);
        expect(tester.getSemantics(find.bySemanticsLabel('Cloud sync')),
            isSemantics(isToggled: true));
        expect(haptics, ['HapticFeedbackType.selectionClick']);
        final track = tester
            .widget<AnimatedContainer>(find
                .descendant(
                    of: find.byType(AtomicSwitchTrack),
                    matching: find.byType(AnimatedContainer))
                .first)
            .decoration! as BoxDecoration;
        expect(track.color, c.accent);
        expect(tester.getSize(find.byType(AtomicSwitch)).height,
            greaterThanOrEqualTo(48));
        handle.dispose();
      });

      testWidgets('reduced motion moves the thumb at once', (tester) async {
        await pumpThemed(
            tester,
            const Center(
                child: AtomicSwitch(
                    value: true, semanticsLabel: 'x', onChanged: null)),
            theme: theme,
            disableAnimations: true);
        expect(
            tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).duration,
            Duration.zero);
      });
    });

    group('AtomicCheckbox ($name)', () {
      testWidgets('reports checked, pops then draws, haptic on completing only',
          (tester) async {
        final handle = tester.ensureSemantics();
        final haptics = _haptics(tester);
        var checked = false;
        await pumpThemed(
          tester,
          StatefulBuilder(
            builder: (context, setState) => Center(
              child: AtomicCheckbox(
                checked: checked,
                semanticsLabel: 'Complete milk',
                onChanged: (v) => setState(() => checked = v),
              ),
            ),
          ),
          theme: theme,
        );
        expect(tester.getSemantics(find.bySemanticsLabel('Complete milk')),
            isSemantics(hasCheckedState: true, isChecked: false));
        await tester.tap(find.byType(AtomicCheckbox));
        await tester.pump(const Duration(milliseconds: 100));
        expect(checked, isTrue);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(find.bySemanticsLabel('Complete milk')),
            isSemantics(isChecked: true));
        await tester.tap(find.byType(AtomicCheckbox));
        await tester.pumpAndSettle();
        expect(checked, isFalse);
        expect(haptics, ['HapticFeedbackType.lightImpact']);
        handle.dispose();
      });
    });

    group('Segmented ($name)', () {
      testWidgets('one selected segment; changing it slides and calls back',
          (tester) async {
        final handle = tester.ensureSemantics();
        var mode = 'system';
        await pumpThemed(
          tester,
          StatefulBuilder(
            builder: (context, setState) => Segmented<String>(
              segments: const [
                ('system', 'System'),
                ('light', 'Light'),
                ('dark', 'Dark'),
              ],
              value: mode,
              onChanged: (v) => setState(() => mode = v),
            ),
          ),
          theme: theme,
        );
        expect(tester.getSemantics(find.bySemanticsLabel('System')),
            isSemantics(isSelected: true, isButton: true));
        expect(tester.getSemantics(find.bySemanticsLabel('Dark')),
            isSemantics(isSelected: false));
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        expect(mode, 'dark');
        expect(
            tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment,
            const Alignment(1, 0));
        handle.dispose();
      });

      testWidgets('fits 2.0 text in 320 dp', (tester) async {
        await pumpNarrow(
          tester,
          Segmented<int>(
            segments: const [(0, 'Newest first'), (1, 'Oldest first')],
            value: 0,
            onChanged: (_) {},
          ),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    });
  }
}
