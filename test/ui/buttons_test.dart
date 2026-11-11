// Buttons, icon buttons and the new-note button (components spec).

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_fab.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

Color? _fill(WidgetTester tester, Finder of) {
  final box = tester.widget<DecoratedBox>(
      find.descendant(of: of, matching: find.byType(DecoratedBox)).first);
  return (box.decoration as BoxDecoration).color;
}

Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  for (final MapEntry(key: name, value: theme) in atomicThemes.entries) {
    final c = theme.extension<AtomicColors>()!;

    group('AtomicButton ($name)', () {
      final expected = {
        AtomicButtonVariant.primary: (c.accent, c.onAccent),
        AtomicButtonVariant.secondary: (c.inverseSurface, c.onInverse),
        AtomicButtonVariant.tonal: (c.surface, c.textPrimary),
        AtomicButtonVariant.text: (null, c.textPrimary),
        AtomicButtonVariant.danger: (c.danger, c.onDanger),
      };
      for (final MapEntry(key: variant, value: (fill, content))
          in expected.entries) {
        testWidgets('${variant.name} uses its colour roles', (tester) async {
          await pumpThemed(
              tester,
              Center(
                  child: AtomicButton(
                      label: 'Go', variant: variant, onPressed: () {})),
              theme: theme);
          expect(_fill(tester, find.byType(AtomicButton)), fill);
          expect(_textColor(tester, 'Go'), content);
        });
      }

      testWidgets('tonal steps down to the inset fill on a card',
          (tester) async {
        await pumpThemed(
            tester,
            Center(
                child: AtomicButton.tonal(
                    label: 'Go', onCard: true, onPressed: () {})),
            theme: theme);
        expect(_fill(tester, find.byType(AtomicButton)), c.surfaceInset);
      });

      testWidgets('disabled reads disabled and looks disabled', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(tester,
            const Center(child: AtomicButton(label: 'Go', onPressed: null)),
            theme: theme);
        expect(_fill(tester, find.byType(AtomicButton)), c.surfaceInset);
        expect(_textColor(tester, 'Go'), c.textDisabled);
        expect(tester.getSemantics(find.bySemanticsLabel('Go')),
            isSemantics(isButton: true, isEnabled: false));
        handle.dispose();
      });

      testWidgets('busy keeps the width, shows a spinner and ignores taps',
          (tester) async {
        var taps = 0;
        Widget button(bool busy) => Center(
            child: AtomicButton(
                label: 'Save note', busy: busy, onPressed: () => taps++));
        await pumpThemed(tester, button(false), theme: theme);
        final idle = tester.getSize(find.byType(AtomicButton));
        await pumpThemed(tester, button(true), theme: theme);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.getSize(find.byType(AtomicButton)), idle);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.tap(find.byType(AtomicButton), warnIfMissed: false);
        expect(taps, 0);
      });

      testWidgets('heights: large 56, regular 48, compact 48 target',
          (tester) async {
        for (final (size, height) in [
          (AtomicButtonSize.large, 56.0),
          (AtomicButtonSize.regular, 48.0),
          (AtomicButtonSize.compact, 48.0),
        ]) {
          await pumpThemed(
              tester,
              Center(
                  child:
                      AtomicButton(label: 'Go', size: size, onPressed: () {})),
              theme: theme);
          expect(tester.getSize(find.byType(AtomicButton)).height, height,
              reason: size.name);
        }
      });

      testWidgets('a long label wraps at 2.0 text in 320 dp', (tester) async {
        await pumpNarrow(
          tester,
          Column(children: [
            AtomicButton.primary(
              label: 'Generate a new recovery phrase now',
              icon: AtomicIcons.key,
              expand: true,
              size: AtomicButtonSize.large,
              onPressed: () {},
            ),
            AtomicButton.text(label: 'Mark all read', onPressed: () {}),
          ]),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('AtomicIconButton ($name)', () {
      testWidgets('tooltip is the label; target is 48', (tester) async {
        final handle = tester.ensureSemantics();
        var taps = 0;
        await pumpThemed(
            tester,
            Center(
                child: AtomicIconButton(
                    icon: AtomicIcons.search,
                    tooltip: 'Search notes',
                    onPressed: () => taps++)),
            theme: theme);
        expect(find.byTooltip('Search notes'), findsOneWidget);
        expect(tester.getSemantics(find.bySemanticsLabel('Search notes')),
            isSemantics(isButton: true, isEnabled: true, hasTapAction: true));
        expect(tester.getSize(find.byType(AtomicIconButton)).width,
            greaterThanOrEqualTo(48));
        await tester.tap(find.byType(AtomicIconButton));
        expect(taps, 1);
        expect(_fill(tester, find.byType(AtomicIconButton)), c.surface);
        handle.dispose();
      });

      testWidgets('a toggle reports its state and fills with the accent',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(
            tester,
            Center(
                child: AtomicIconButton(
                    icon: AtomicIcons.pin,
                    toggledIcon: AtomicIcons.pinFilled,
                    tooltip: 'Unpin',
                    toggled: true,
                    onPressed: () {})),
            theme: theme);
        expect(_fill(tester, find.byType(AtomicIconButton)), c.accent);
        expect(
            tester.widget<Icon>(find.byType(Icon)).icon, AtomicIcons.pinFilled);
        expect(tester.getSemantics(find.bySemanticsLabel('Unpin')),
            isSemantics(hasToggledState: true, isToggled: true));
        handle.dispose();
      });

      testWidgets('unread badge caps at 9+', (tester) async {
        await pumpThemed(
            tester,
            Center(
                child: AtomicIconButton(
                    icon: AtomicIcons.bell,
                    tooltip: 'Notifications',
                    badgeCount: 12,
                    onPressed: () {})),
            theme: theme);
        expect(find.text('9+'), findsOneWidget);
      });
    });

    group('AtomicFab ($name)', () {
      testWidgets('64 dp accent circle in a 6 dp ring, labelled New note',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(tester, Center(child: AtomicFab(onPressed: () {})),
            theme: theme);
        expect(tester.getSize(find.byType(AtomicFab)), const Size(76, 76));
        expect(find.byTooltip('New note'), findsOneWidget);
        expect(tester.getSemantics(find.bySemanticsLabel('New note')),
            isSemantics(isButton: true));
        handle.dispose();
      });

      testWidgets('at the limit it stays tappable and says why',
          (tester) async {
        final handle = tester.ensureSemantics();
        var taps = 0;
        await pumpThemed(tester,
            Center(child: AtomicFab(atLimit: true, onPressed: () => taps++)),
            theme: theme);
        expect(find.text('!'), findsOneWidget);
        expect(find.bySemanticsLabel('New note. Note limit reached'),
            findsOneWidget);
        await tester.tap(find.byType(AtomicFab));
        expect(taps, 1);
        handle.dispose();
      });
    });
  }
}
