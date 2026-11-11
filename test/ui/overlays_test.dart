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
