// Dialog, sheet and snackbar (components spec).

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/ui/overlays/atomic_sheet.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

/// Pumps a button that runs [open] with a context under the theme.
Future<void> _host(WidgetTester tester, ThemeData theme,
    void Function(BuildContext context) open,
    {double textScale = 1}) async {
  await pumpThemed(
    tester,
    Builder(
      builder: (context) => Center(
        child: TextButton(
            onPressed: () => open(context), child: const Text('open')),
      ),
    ),
    theme: theme,
    textScale: textScale,
  );
}

enum _Save { save, discard, keep }

void main() {
  for (final MapEntry(key: name, value: theme) in atomicThemes.entries) {
    final c = theme.extension<AtomicColors>()!;

    group('AtomicDialog ($name)', () {
      testWidgets('three actions stack and return their results',
          (tester) async {
        final results = <_Save?>[];
        await _host(tester, theme, (context) async {
          results.add(await showAtomicDialog<_Save>(
            context: context,
            title: 'Save your changes?',
            body: 'Your edits stay on this device until you save.',
            actions: const [
              AtomicDialogAction(
                  label: 'Save',
                  result: _Save.save,
                  variant: AtomicButtonVariant.primary),
              AtomicDialogAction(
                  label: 'Discard',
                  result: _Save.discard,
                  variant: AtomicButtonVariant.danger),
              AtomicDialogAction(label: 'Keep editing', result: _Save.keep),
            ],
          ));
        });
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final save = tester.getRect(find.text('Save'));
        final discard = tester.getRect(find.text('Discard'));
        expect(discard.top, greaterThan(save.bottom), reason: 'stacked');
        expect(tester.getSize(find.byType(AtomicButton).first).width,
            tester.getSize(find.byType(AtomicButton).last).width,
            reason: 'full width');
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(results, [_Save.discard]);
      });

      testWidgets('surface, radius 32, at most 400 wide', (tester) async {
        await _host(
            tester,
            theme,
            (context) => showAtomicDialog<bool>(
                  context: context,
                  title: 'Sign out?',
                  icon: AtomicIcons.logout,
                  actions: const [
                    AtomicDialogAction(label: 'Cancel', result: false),
                    AtomicDialogAction(
                        label: 'Sign out',
                        result: true,
                        variant: AtomicButtonVariant.primary),
                  ],
                ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final material = tester.widget<Material>(find
            .descendant(
                of: find.byType(AtomicDialog<bool>),
                matching: find.byType(Material))
            .first);
        expect(material.color, c.surface);
        expect(tester.getSize(find.byType(Material).last).width,
            lessThanOrEqualTo(AtomicDialog.maxWidth));
        final cancel = tester.getRect(find.text('Cancel'));
        final signOut = tester.getRect(find.text('Sign out'));
        expect(cancel.top, closeTo(signOut.top, 1), reason: 'one row');
      });

      testWidgets('a non-dismissible dialog ignores the scrim and Back',
          (tester) async {
        await _host(
            tester,
            theme,
            (context) => showAtomicDialog<bool>(
                  context: context,
                  title: 'Wipe cloud notes?',
                  destructive: true,
                  icon: AtomicIcons.trash,
                  barrierDismissible: false,
                  actions: const [
                    AtomicDialogAction(label: 'Cancel', result: false),
                  ],
                ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(find.text('Wipe cloud notes?'), findsOneWidget);
        final popped = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(popped, isTrue);
        expect(find.text('Wipe cloud notes?'), findsOneWidget);
        expect(tester.widget<Icon>(find.byIcon(AtomicIcons.trash)).color,
            c.onDanger);
      });

      testWidgets('fits 2.0 text in 320 dp', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _host(
            tester,
            theme,
            (context) => showAtomicDialog<int>(
                  context: context,
                  title: 'Delete forever?',
                  body: 'These notes leave this device and the cloud. '
                      'This cannot be undone.',
                  icon: AtomicIcons.trash,
                  destructive: true,
                  actions: const [
                    AtomicDialogAction(label: 'Keep notes', result: 0),
                    AtomicDialogAction(
                        label: 'Delete forever',
                        result: 1,
                        variant: AtomicButtonVariant.danger),
                  ],
                ),
            textScale: 2);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });

    group('AtomicDialog above the keyboard (F05, $name)', () {
      /// Sets the logical screen and keyboard height (device pixel ratio 1).
      void view(WidgetTester tester, Size size, {double keyboard = 0}) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.reset);
      }

      void setKeyboard(WidgetTester tester, double keyboard) =>
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard);

      Future<List<String?>> openNameDialog(WidgetTester tester,
          {double textScale = 1, int actions = 2}) async {
        final results = <String?>[];
        await _host(tester, theme, (context) async {
          results.add(await showAtomicDialog<String>(
            context: context,
            title: 'Rename note',
            body: 'Choose a short, clear name.',
            content: const TextField(autofocus: true),
            actions: [
              const AtomicDialogAction(label: 'Cancel', result: 'cancel'),
              if (actions >= 3)
                const AtomicDialogAction(
                    label: 'Discard',
                    result: 'discard',
                    variant: AtomicButtonVariant.danger),
              const AtomicDialogAction(
                  label: 'Save',
                  result: 'save',
                  variant: AtomicButtonVariant.primary),
            ],
          ));
        }, textScale: textScale);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        return results;
      }

      Future<void> expectReachable(
          WidgetTester tester, String label, double keyboardTop) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.text(label)).bottom,
            lessThanOrEqualTo(keyboardTop),
            reason: '$label is above the keyboard');
      }

      testWidgets('reviewer fixture: 800 x 600 with a 300 dp keyboard',
          (tester) async {
        view(tester, const Size(800, 600), keyboard: 300);
        final results = await openNameDialog(tester);
        expect(tester.takeException(), isNull);
        await expectReachable(tester, 'Save', 300);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(results, ['save']);
      });

      testWidgets('the keyboard opening and closing under an open dialog',
          (tester) async {
        view(tester, const Size(800, 600));
        await openNameDialog(tester);
        expect(tester.getRect(find.text('Save')).bottom, lessThan(600));
        setKeyboard(tester, 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectReachable(tester, 'Save', 300);
        setKeyboard(tester, 0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.text('Save')).bottom, lessThan(600));
      });

      testWidgets('landscape phone at 200 % text with the keyboard',
          (tester) async {
        view(tester, const Size(640, 360), keyboard: 160);
        final results = await openNameDialog(tester, textScale: 2);
        expect(tester.takeException(), isNull);
        await expectReachable(tester, 'Save', 200);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(results, ['save']);
      });

      testWidgets('320 dp phone, 200 % text, three actions, keyboard open',
          (tester) async {
        view(tester, const Size(320, 640), keyboard: 280);
        final results = await openNameDialog(tester, textScale: 2, actions: 3);
        expect(tester.takeException(), isNull);
        for (final label in ['Cancel', 'Discard', 'Save']) {
          await expectReachable(tester, label, 360);
        }
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(results, ['discard']);
      });

      testWidgets('with room, long content scrolls and the actions stay pinned',
          (tester) async {
        view(tester, const Size(800, 600));
        await _host(
            tester,
            theme,
            (context) => showAtomicDialog<bool>(
                  context: context,
                  title: 'What syncing does',
                  body: List.filled(40, 'A line of explanation.').join(' '),
                  actions: const [
                    AtomicDialogAction(label: 'Close', result: true),
                  ],
                ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.text('Close')).bottom,
            lessThanOrEqualTo(600 - 24),
            reason: 'visible without scrolling');
        expect(find.byType(SingleChildScrollView), findsOneWidget);
      });
    });

    group('AtomicSheet ($name)', () {
      testWidgets('handle, surface, top radius, action rows', (tester) async {
        final picked = <String>[];
        await _host(
          tester,
          theme,
          (context) => showAtomicSheet<void>(
            context: context,
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AtomicSheetAction(
                    icon: AtomicIcons.pin,
                    label: 'Pin',
                    onTap: () {
                      picked.add('pin');
                      Navigator.pop(context);
                    }),
                AtomicSheetAction(
                    icon: AtomicIcons.trash,
                    label: 'Move to Recycle Bin',
                    destructive: true,
                    onTap: () {}),
              ],
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(sheet.backgroundColor, c.surface);
        expect(
            tester.widget<Text>(find.text('Move to Recycle Bin')).style?.color,
            c.dangerText);
        expect(tester.getSize(find.byType(AtomicSheetAction).first).height,
            greaterThanOrEqualTo(56));
        await tester.tap(find.text('Pin'));
        await tester.pumpAndSettle();
        expect(picked, ['pin']);
        expect(find.byType(BottomSheet), findsNothing);
      });
    });

    group('AtomicSnackBar ($name)', () {
      testWidgets('inverse pill; replaces the current one; action runs',
          (tester) async {
        var undone = 0;
        await _host(tester, theme, (context) {
          const AtomicSnackBar(text: 'first', millis: 4000).show(context);
          AtomicSnackBar(
            text: 'Note moved to the Recycle Bin',
            millis: 4000,
            action:
                AtomicSnackBarAction(label: 'Undo', onPressed: () => undone++),
          ).show(context);
        });
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('first'), findsNothing);
        final bar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(bar.backgroundColor, c.inverseSurface);
        expect(bar.elevation, theme.brightness == Brightness.light ? 8 : 0);
        expect(
            tester
                .widget<Text>(find.text('Note moved to the Recycle Bin'))
                .style
                ?.color,
            c.onInverse);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(undone, 1);
      });

      testWidgets('the error icon reads on the inverse fill', (tester) async {
        await _host(
            tester,
            theme,
            (context) => const AtomicSnackBar(
                    text: 'Could not sync', millis: 3000, error: true)
                .show(context));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.widget<Icon>(find.byIcon(AtomicIcons.alertCircle)).color,
            AtomicSnackBar.errorColor(c));
        expect(
            AtomicSnackBar.errorColor(c),
            theme.brightness == Brightness.light
                ? AtomicPalette.red400
                : AtomicPalette.red700);
      });
    });
  }
}
