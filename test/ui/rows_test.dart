// Card, checklist row, settings group and row, ledger row.

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/controls/atomic_checkbox.dart';
import 'package:atomic_notes/ui/rows/checklist_row.dart';
import 'package:atomic_notes/ui/rows/settings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

/// [row] in a settings group on a real phone screen [width] logical pixels
/// wide (device pixel ratio 1), with the page margins for that width.
Future<void> _pumpOnPhone(
  WidgetTester tester,
  Widget row, {
  required ThemeData theme,
  required double width,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Scaffold(
      body: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: AtomicSpace.screenMargin(width)),
        child: Column(children: [
          SettingsGroup(children: [row])
        ]),
      ),
    ),
  ));
}

void main() {
  for (final MapEntry(key: name, value: theme) in atomicThemes.entries) {
    final c = theme.extension<AtomicColors>()!;
    final light = theme.brightness == Brightness.light;

    testWidgets('AtomicCard: outline edge in light only ($name)',
        (tester) async {
      await pumpThemed(tester, const AtomicCard(child: Text('x')),
          theme: theme);
      final deco = tester
          .widget<DecoratedBox>(find
              .descendant(
                  of: find.byType(AtomicCard),
                  matching: find.byType(DecoratedBox))
              .first)
          .decoration as BoxDecoration;
      expect(deco.color, c.surface);
      expect(deco.border != null, light);
    });

    group('ChecklistRow ($name)', () {
      testWidgets('one checkbox toggle labelled "Complete {item}"',
          (tester) async {
        final handle = tester.ensureSemantics();
        var toggles = 0;
        await pumpThemed(
            tester,
            Center(
                child: ChecklistRow(
                    text: 'milk', done: false, onToggle: () => toggles++)),
            theme: theme);
        expect(
            tester.getSemantics(find.bySemanticsLabel('Complete milk')),
            isSemantics(
                isButton: false,
                hasCheckedState: true,
                isChecked: false,
                hasTapAction: true));
        await tester.tap(find.text('milk'));
        expect(toggles, 1);
        handle.dispose();
      });

      testWidgets('done text is struck through in the secondary colour',
          (tester) async {
        await pumpThemed(
            tester,
            Center(
                child: ChecklistRow(text: 'milk', done: true, onToggle: () {})),
            theme: theme);
        final style = tester.widget<Text>(find.text('milk')).style!;
        expect(style.decoration, TextDecoration.lineThrough);
        expect(style.color, c.textSecondary);
      });

      testWidgets('in selection mode the pill ignores taps', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(
            tester,
            const Center(
                child: ChecklistRow(text: 'milk', done: false, onToggle: null)),
            theme: theme);
        expect(tester.getSemantics(find.bySemanticsLabel('Complete milk')),
            isSemantics(isEnabled: false));
        handle.dispose();
      });

      testWidgets('editor form keeps "Remove item {n}" and fills the width',
          (tester) async {
        var removed = 0;
        await pumpNarrow(
          tester,
          ChecklistRow(
            text: 'a long checklist item that has to wrap onto lines',
            done: false,
            onToggle: () {},
            semanticsLabel: 'Complete item 2',
            onRemove: () => removed++,
            removeTooltip: 'Remove item 2',
          ),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Remove item 2'));
        expect(removed, 1);
      });

      for (final tone in CheckboxTone.values) {
        testWidgets('${tone.name} pill fits 2.0 text in 320 dp',
            (tester) async {
          await pumpNarrow(
              tester,
              ChecklistRow(
                  text: 'pick up the dry cleaning before six',
                  done: true,
                  tone: tone,
                  onToggle: () {}),
              theme: theme);
          expect(tester.takeException(), isNull);
        });
      }
    });

    group('SettingsRow ($name)', () {
      testWidgets('one button reading "{title}. {caption}. {value}"',
          (tester) async {
        final handle = tester.ensureSemantics();
        var taps = 0;
        await pumpThemed(
          tester,
          SettingsGroup(label: 'Account', children: [
            SettingsRow(
              icon: AtomicIcons.palette,
              title: 'Appearance',
              caption: 'Theme for this device',
              value: 'System',
              onTap: () => taps++,
            ),
            SettingsRow(
                icon: AtomicIcons.trash,
                title: 'Recycle Bin',
                count: 3,
                onTap: () {}),
          ]),
          theme: theme,
        );
        expect(
            tester.getSemantics(find
                .bySemanticsLabel('Appearance. Theme for this device. System')),
            isSemantics(isButton: true, hasTapAction: true));
        expect(find.byIcon(AtomicIcons.chevronRight), findsNWidgets(2));
        expect(find.text('3'), findsOneWidget);
        expect(find.byType(Divider), findsOneWidget);
        await tester.tap(find.text('Appearance'));
        expect(taps, 1);
        expect(tester.getSize(find.byType(SettingsRow).first).height,
            greaterThanOrEqualTo(64));
        handle.dispose();
      });

      testWidgets('a switch row is one switch, toggled from anywhere',
          (tester) async {
        final handle = tester.ensureSemantics();
        var on = false;
        await pumpThemed(
          tester,
          StatefulBuilder(
            builder: (context, setState) => SettingsRow.toggle(
              icon: AtomicIcons.cloud,
              title: 'Cloud sync',
              value: on,
              onChanged: (v) => setState(() => on = v),
            ),
          ),
          theme: theme,
        );
        expect(
            tester.getSemantics(find.bySemanticsLabel('Cloud sync')),
            isSemantics(
                isButton: false, hasToggledState: true, isToggled: false));
        await tester.tap(find.text('Cloud sync'));
        await tester.pumpAndSettle();
        expect(on, isTrue);
        expect(find.byIcon(AtomicIcons.chevronRight), findsNothing);
        handle.dispose();
      });

      testWidgets('F10: a counted row announces its count once',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(
          tester,
          SettingsGroup(children: [
            SettingsRow(
                icon: AtomicIcons.trash,
                title: 'Recycle Bin',
                count: 3,
                countLabel: '3 notes',
                onTap: () {}),
            SettingsRow(
                icon: AtomicIcons.bell,
                title: 'Notifications',
                caption: 'Unread',
                count: 7,
                onTap: () {}),
          ]),
          theme: theme,
        );
        expect(
            tester.getSemantics(find.bySemanticsLabel('Recycle Bin. 3 notes')),
            isSemantics(isButton: true, hasTapAction: true));
        expect(
            find.bySemanticsLabel('Notifications. Unread. 7'), findsOneWidget,
            reason: 'defaults to the number');
        expect(find.bySemanticsLabel(RegExp(r'\b3\b.*\b3\b')), findsNothing,
            reason: 'not announced twice');
        handle.dispose();
      });

      testWidgets('F10: a large count shows 99+ and is read in full',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpNarrow(
          tester,
          SettingsRow(
              icon: AtomicIcons.bell,
              title: 'Notifications waiting for you',
              count: 1234,
              onTap: () {}),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('99+'), findsOneWidget);
        expect(find.bySemanticsLabel('Notifications waiting for you. 1234'),
            findsOneWidget);
        handle.dispose();
      });

      testWidgets('danger rows use the danger tile', (tester) async {
        await pumpThemed(
            tester,
            SettingsRow(
                icon: AtomicIcons.alertTriangle,
                title: 'Danger zone',
                danger: true,
                onTap: () {}),
            theme: theme);
        expect(
            tester.widget<Icon>(find.byIcon(AtomicIcons.alertTriangle)).color,
            c.onDanger);
      });

      testWidgets('rows fit 2.0 text in 320 dp', (tester) async {
        await pumpNarrow(
          tester,
          SettingsGroup(label: 'Security and privacy', children: [
            SettingsRow(
              icon: AtomicIcons.shieldLock,
              title: 'Two-factor authentication',
              caption: 'Ask for a code when signing in on a new device',
              value: 'Off',
              onTap: () {},
            ),
            SettingsRow.toggle(
              icon: AtomicIcons.eyeOff,
              title: 'Block screenshots',
              value: true,
              onChanged: (_) {},
            ),
          ]),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });

      SettingsRow appearance(String value, {String title = 'Appearance'}) =>
          SettingsRow(
              icon: AtomicIcons.palette,
              title: title,
              value: value,
              onTap: () {});

      for (final direction in TextDirection.values) {
        testWidgets(
            'a value that fits stays at the end of the title line '
            '(${direction.name})', (tester) async {
          // Short enough for one line even in the square test font.
          await _pumpOnPhone(tester, appearance('Dark', title: 'Theme'),
              theme: theme, width: 360, direction: direction);
          final title = tester.getRect(find.text('Theme'));
          final shown = tester.getRect(find.text('Dark'));
          final chevron = tester.getRect(find.byIcon(AtomicIcons.chevronRight));
          expect(shown.center.dy, moreOrLessEquals(title.center.dy));
          if (direction == TextDirection.ltr) {
            expect(
                shown.right, moreOrLessEquals(chevron.left - AtomicSpace.x2));
            expect(title.right, lessThan(shown.left));
          } else {
            expect(
                shown.left, moreOrLessEquals(chevron.right + AtomicSpace.x2));
            expect(title.left, greaterThan(shown.right));
          }
          expect(tester.widget<Text>(find.text('Dark')).style!.color,
              c.textSecondary);
        });

        // The overflows these replace: 26 px for "System" on a 320 dp
        // phone and 16 px for "English" on a 360 dp phone, at 2.0 text.
        for (final (width, value) in [(320.0, 'System'), (360.0, 'English')]) {
          testWidgets(
              'a value too wide for the title line moves under it, '
              '$width dp at 2.0 text (${direction.name})', (tester) async {
            final handle = tester.ensureSemantics();
            await _pumpOnPhone(tester, appearance(value),
                theme: theme, width: width, textScale: 2, direction: direction);
            expect(tester.takeException(), isNull);
            final title = tester.getRect(find.text('Appearance'));
            final shown = tester.getRect(find.text(value));
            expect(shown.top, greaterThanOrEqualTo(title.bottom));
            if (direction == TextDirection.ltr) {
              expect(shown.left, moreOrLessEquals(title.left));
            } else {
              expect(shown.right, moreOrLessEquals(title.right));
            }
            expect(find.byIcon(AtomicIcons.chevronRight), findsOneWidget);
            expect(
                tester
                    .getSemantics(find.bySemanticsLabel('Appearance. $value')),
                isSemantics(isButton: true, hasTapAction: true));
            expect(tester.getSize(find.byType(SettingsRow)).height,
                greaterThanOrEqualTo(SettingsRow.minHeight));
            handle.dispose();
          });
        }
      }
    });

    testWidgets('LedgerRow reads as one item and fits 320 dp ($name)',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpNarrow(
        tester,
        const LedgerRow(
          icon: AtomicIcons.bolt,
          title: 'Instant sync',
          caption: 'Today 16:41',
          amount: '−5',
        ),
        theme: theme,
      );
      expect(tester.takeException(), isNull);
      expect(
          find.bySemanticsLabel(
              RegExp('Instant sync.*Today 16:41.*−5', dotAll: true)),
          findsOneWidget);
      handle.dispose();
    });
  }
}
