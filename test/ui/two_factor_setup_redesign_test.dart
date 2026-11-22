// The two-factor setup screen on lib/ui components (screens spec,
// Two-factor setup): step cards "Add to your authenticator app" and
// "Confirm", a QR code that is always black on a white card with a 16 dp
// quiet zone, the setup key in mono with Copy, and the recovery codes in a
// two-column mono grid. The enrollment logic is the service's; the page owns
// the stale-result guard. Every key and code here is synthetic, and the
// tests compare secret material only as booleans so a failure never prints
// it.

import 'dart:async';
import 'dart:math';

import 'package:atomic_notes/page/endpage/two_factor_page.dart';
import 'package:atomic_notes/security/two_factor.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/chips/status_chip.dart';
import 'package:atomic_notes/ui/controls/atomic_checkbox.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/utility/component/two_factor_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../support/two_factor_fakes.dart';

/// A [TwoFactor] whose confirm and count reads wait for the test.
class _HeldTwoFactor extends TwoFactor {
  _HeldTwoFactor()
      : super(
          storage: FakeTwoFactorStorage(),
          account: () => testAccount,
          label: () => 'synthetic',
          random: Random(3),
        );

  bool armedFlag = false;
  final List<Completer<List<String>?>> confirms = [];
  final List<String> confirmInputs = [];
  int cancels = 0;
  int? left;
  Completer<int?>? heldCount;

  @override
  bool get isArmed => armedFlag;

  void arm(bool value) {
    armedFlag = value;
    notifyListeners();
  }

  @override
  Future<List<String>?> confirmSetup(String code) {
    confirmInputs.add(code);
    final c = Completer<List<String>?>();
    confirms.add(c);
    return c.future;
  }

  @override
  void cancelSetup() {
    cancels++;
    super.cancelSetup();
  }

  @override
  Future<int?> recoveryCodesLeft() => heldCount?.future ?? Future.value(left);
}

final List<String> _synthCodes = [
  for (var i = 0; i < 8; i++) 'SYNTH-CODE$i',
];

Finder _k(String key) => find.byKey(ValueKey(key));
final Finder _field = find.byType(TextField);

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  TwoFactor tf, {
  Object? Function()? identity,
  ThemeData? theme,
  double width = 412,
  double height = 915,
  double textScale = 1,
  bool disableAnimations = false,
  bool pushed = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final page = TwoFactorPage(twoFactor: tf, identity: identity);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: pushed
        ? Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => page)),
                child: const Text('base page'),
              ),
            ),
          )
        : page,
  ));
  if (pushed) {
    await tester.tap(find.text('base page'));
  }
  if (settle) await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await _settle(tester);
}

AtomicButton _button(WidgetTester tester, Finder f) =>
    tester.widget<AtomicButton>(f);

String _secretShown(WidgetTester tester) =>
    tester.widget<SelectableText>(_k('tf-setup-key')).data!.replaceAll(' ', '');

void main() {
  group('overview', () {
    testWidgets('off: title, status, the way in and the notes', (tester) async {
      await _pump(tester, _HeldTwoFactor());

      expect(find.text(TwoFactorPage.title), findsWidgets);
      expect(tester.widget<StatusChip>(_k('tf-setup-status')).label,
          TwoFactorPage.offChip);
      expect(find.text(TwoFactorPage.offHeading), findsOneWidget);
      expect(_button(tester, _k('tf-setup-begin')).variant,
          AtomicButtonVariant.primary);
      expect(tester.getSize(_k('tf-setup-begin')).height, 56);
      expect(find.text(TwoFactorPage.goodToKnow), findsOneWidget);
    });

    testWidgets('on: status, count left, new codes and turn off',
        (tester) async {
      final tf = _HeldTwoFactor()
        ..armedFlag = true
        ..left = 6;
      await _pump(tester, tf);

      final chip = tester.widget<StatusChip>(_k('tf-setup-status'));
      expect(chip.label, TwoFactorPage.onChip);
      expect(chip.tone, StatusTone.accent);
      expect(find.text(TwoFactorPage.onHeading), findsOneWidget);
      expect(tester.widget<Text>(_k('tf-setup-codes-left')).data, '6');
      expect(_k('tf-setup-low-codes'), findsNothing);
      expect(_button(tester, _k('tf-setup-new-codes')).variant,
          AtomicButtonVariant.tonal);
      expect(_button(tester, _k('tf-setup-turn-off')).variant,
          AtomicButtonVariant.danger);
    });

    testWidgets('few codes left: attention at 2, danger at 0', (tester) async {
      final tf = _HeldTwoFactor()
        ..armedFlag = true
        ..left = 2;
      await _pump(tester, tf);
      expect(tester.widget<AtomicBanner>(_k('tf-setup-low-codes')).tone,
          BannerTone.attention);

      await tester.pumpWidget(const SizedBox());
      final none = _HeldTwoFactor()
        ..armedFlag = true
        ..left = 0;
      await _pump(tester, none);
      expect(tester.widget<AtomicBanner>(_k('tf-setup-low-codes')).tone,
          BannerTone.danger);
    });
  });

  group('enrollment and confirmation', () {
    testWidgets('step cards, QR, key and Copy, then codes and Done',
        (tester) async {
      final storage = FakeTwoFactorStorage();
      final clock = TestClock();
      final tf = makeTwoFactor(storage, clock);
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester, tf);

      await _tap(tester, _k('tf-setup-begin'));
      expect(_k('tf-setup-step-1'), findsOneWidget);
      expect(_k('tf-setup-step-2'), findsOneWidget);
      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(find.text(TwoFactorPage.step1Title), findsOneWidget);
      expect(find.text(TwoFactorPage.step2Title), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      final secret = _secretShown(tester);
      expect(secret.length, greaterThanOrEqualTo(32));
      expect(
          tester.widget<SelectableText>(_k('tf-setup-key')).style!.fontFamily,
          'JetBrainsMono');

      await _tap(tester, _k('tf-setup-copy-key'));
      expect(copied == secret, isTrue,
          reason: 'Copy puts the key on the clipboard');
      expect(find.text('Setup key copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // A wrong code: the message, an empty field, still off.
      final wrong =
          (await tester.runAsync(() => wrongCodeAt(secret, clock.now)))!;
      await tester.ensureVisible(_field);
      await tester.enterText(_field, wrong);
      await _settle(tester);
      expect(find.text(TwoFactorPage.wrongCode), findsOneWidget);
      expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
      expect(tf.isArmed, isFalse);

      // The right one: on, with the codes in two columns.
      final right = (await tester.runAsync(() => codeAt(secret, clock.now)))!;
      await tester.enterText(_field, right);
      await _settle(tester);
      expect(tf.isArmed, isTrue);
      expect(find.text(TwoFactorPage.codesTitle), findsOneWidget);
      expect(find.text(TwoFactorPage.shownOnce), findsOneWidget);
      final codes = find.descendant(
          of: _k('tf-setup-code-grid'), matching: find.byType(SelectableText));
      expect(codes, findsNWidgets(TwoFactor.recoveryCodeCount));
      final a = tester.getTopLeft(codes.at(0));
      final b = tester.getTopLeft(codes.at(1));
      final c = tester.getTopLeft(codes.at(2));
      expect(a.dy, b.dy);
      expect(b.dx, greaterThan(a.dx));
      expect(c.dx, a.dx);
      expect(c.dy, greaterThan(a.dy));
      expect(tester.widget<SelectableText>(codes.first).style!.fontFamily,
          'JetBrainsMono');

      // Done waits for the checkbox.
      expect(_button(tester, _k('tf-setup-done')).onPressed, isNull);
      await _tap(tester, find.byType(AtomicCheckbox));
      expect(tester.widget<AtomicCheckbox>(find.byType(AtomicCheckbox)).checked,
          isTrue);
      await _tap(tester, _k('tf-setup-done'));
      expect(tester.widget<StatusChip>(_k('tf-setup-status')).label,
          TwoFactorPage.onChip);
      expect(tester.widget<Text>(_k('tf-setup-codes-left')).data, '8');
    });

    testWidgets('a short code is refused before any check', (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);
      await _tap(tester, _k('tf-setup-begin'));

      await tester.enterText(_field, '123');
      await _tap(tester, _k('tf-setup-verify'));
      expect(find.text(TwoFactorPage.needSixDigits), findsOneWidget);
      expect(tf.confirmInputs, isEmpty);
    });

    testWidgets('Done on the keyboard confirms, with one-time-code autofill',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);
      await _tap(tester, _k('tf-setup-begin'));

      expect(tester.widget<TextField>(_field).autofillHints,
          contains(AutofillHints.oneTimeCode));
      await tester.enterText(_field, '12345');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text(TwoFactorPage.needSixDigits), findsOneWidget);
      expect(tf.confirmInputs, isEmpty);
    });
  });

  group('cancellation, failure and retry', () {
    testWidgets('cancel stores nothing and a new setup has a new key',
        (tester) async {
      final storage = FakeTwoFactorStorage();
      final tf = makeTwoFactor(storage, TestClock());
      await _pump(tester, tf);

      await _tap(tester, _k('tf-setup-begin'));
      final first = _secretShown(tester);
      await _tap(tester, _k('tf-setup-cancel'));
      expect(_k('tf-setup-off'), findsOneWidget);
      expect(tf.isArmed, isFalse);
      expect(storage.state, isEmpty);

      await _tap(tester, _k('tf-setup-begin'));
      expect(_secretShown(tester) == first, isFalse);
    });

    testWidgets('a refused code can be retried in the same setup',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);
      await _tap(tester, _k('tf-setup-begin'));

      await tester.enterText(_field, '000000');
      await tester.pump();
      tf.confirms.single.complete(null);
      await _settle(tester);
      expect(find.text(TwoFactorPage.wrongCode), findsOneWidget);
      expect(_button(tester, _k('tf-setup-verify')).busy, isFalse);
      expect(tf.cancels, 0, reason: 'a wrong code keeps the same key');

      await tester.enterText(_field, '111111');
      await tester.pump();
      expect(find.text(TwoFactorPage.wrongCode), findsNothing);
      tf.confirms.last.complete(_synthCodes);
      await _settle(tester);
      expect(tf.confirmInputs, ['000000', '111111']);
      expect(_k('tf-setup-codes'), findsOneWidget);
    });

    testWidgets('while a confirm runs: one check, no cancel, no leaving',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf, pushed: true);
      await _tap(tester, _k('tf-setup-begin'));

      await tester.enterText(_field, '123456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.tap(_k('tf-setup-verify'), warnIfMissed: false);
      await tester.pump();
      expect(tf.confirmInputs, ['123456']);
      expect(_button(tester, _k('tf-setup-cancel')).onPressed, isNull);
      expect(tester.widget<TextField>(_field).enabled, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TwoFactorPage), findsOneWidget);

      tf.confirms.single.complete(_synthCodes);
      await _settle(tester);
      expect(_k('tf-setup-codes'), findsOneWidget);
    });
  });

  group('route disposal and stale results', () {
    testWidgets('a confirm that returns after the page has gone does nothing',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);
      await _tap(tester, _k('tf-setup-begin'));
      await tester.enterText(_field, '123456');
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      expect(tf.cancels, greaterThanOrEqualTo(1));
      tf.confirms.single.complete(_synthCodes);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('an old account\'s codes are never shown to the new account',
        (tester) async {
      Object? account = 'account-a';
      final tf = _HeldTwoFactor();
      await _pump(tester, tf, identity: () => account);
      await _tap(tester, _k('tf-setup-begin'));
      await tester.enterText(_field, '123456');
      await tester.pump();

      account = 'account-b';
      tf.confirms.single.complete(_synthCodes);
      await _settle(tester);

      expect(_k('tf-setup-codes'), findsNothing);
      expect(find.text(_synthCodes.first), findsNothing);
      expect(_k('tf-setup-notice'), findsOneWidget);
      expect(_k('tf-setup-off'), findsOneWidget);
    });

    testWidgets('an old account\'s count is not shown', (tester) async {
      Object? account = 'account-a';
      final count = Completer<int?>();
      final tf = _HeldTwoFactor()
        ..armedFlag = true
        ..heldCount = count;
      await _pump(tester, tf, identity: () => account);

      account = 'account-b';
      count.complete(5);
      await _settle(tester);
      expect(tester.widget<Text>(_k('tf-setup-codes-left')).data, '–');
    });

    testWidgets('a sign-in change while a code prompt is open shows nothing',
        (tester) async {
      Object? account = 'account-a';
      final storage = FakeTwoFactorStorage();
      final clock = TestClock();
      final tf = makeTwoFactor(storage, clock);
      final on = (await tester.runAsync(() => turnOn(tf, clock)))!;
      clock.advance(const Duration(seconds: 30));
      await _pump(tester, tf, identity: () => account);

      await _tap(tester, _k('tf-setup-new-codes'));
      account = 'account-b';
      final code = (await tester.runAsync(() => codeAt(on.secret, clock.now)))!;
      await tester.enterText(_field, code);
      await _settle(tester);

      expect(_k('tf-setup-codes'), findsNothing);
      expect(_k('tf-setup-notice'), findsOneWidget);
    });
  });

  group('code prompts', () {
    testWidgets('new codes: a dialog with the code field, then new codes',
        (tester) async {
      final storage = FakeTwoFactorStorage();
      final clock = TestClock();
      final tf = makeTwoFactor(storage, clock);
      final on = (await tester.runAsync(() => turnOn(tf, clock)))!;
      clock.advance(const Duration(seconds: 30));
      await _pump(tester, tf);

      await _tap(tester, _k('tf-setup-new-codes'));
      expect(find.byType(AtomicDialog<TwoFactorCheck>), findsOneWidget);
      expect(find.byType(TwoFactorCodeField), findsOneWidget);

      final wrong =
          (await tester.runAsync(() => wrongCodeAt(on.secret, clock.now)))!;
      await tester.enterText(_field, wrong);
      await _settle(tester);
      expect(find.textContaining("didn't match"), findsOneWidget);

      final code = (await tester.runAsync(() => codeAt(on.secret, clock.now)))!;
      await tester.enterText(_field, code);
      await _settle(tester);
      expect(find.byType(AtomicDialog<TwoFactorCheck>), findsNothing);
      final shown = [
        for (final w in tester.widgetList<SelectableText>(find.descendant(
            of: _k('tf-setup-code-grid'),
            matching: find.byType(SelectableText))))
          w.data!,
      ];
      expect(shown.length, TwoFactor.recoveryCodeCount);
      expect(shown.any(on.codes.contains), isFalse,
          reason: 'the old codes are replaced');
    });

    testWidgets('turn off: Cancel keeps it on, a code turns it off',
        (tester) async {
      final storage = FakeTwoFactorStorage();
      final clock = TestClock();
      final tf = makeTwoFactor(storage, clock);
      final on = (await tester.runAsync(() => turnOn(tf, clock)))!;
      clock.advance(const Duration(seconds: 30));
      await _pump(tester, tf);

      await _tap(tester, _k('tf-setup-turn-off'));
      expect(find.byType(AtomicDialog<TwoFactorCheck>), findsOneWidget);
      await _tap(tester, _k('tf-prompt-cancel'));
      expect(tf.isArmed, isTrue);

      await _tap(tester, _k('tf-setup-turn-off'));
      await _tap(tester, _k('tf-prompt-toggle'));
      expect(find.text(TwoFactorCodeField.recoveryLabel), findsOneWidget);
      await tester.enterText(_field, on.codes.first);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(tf.isArmed, isFalse);
      expect(find.text('Two-factor is off'), findsOneWidget);
      expect(_k('tf-setup-off'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('design checks', () {
    testWidgets('the QR is black on white with a 16 dp quiet zone in dark',
        (tester) async {
      await _pump(tester, _HeldTwoFactor(), theme: AtomicTheme.dark);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AtomicColors.dark.canvas);

      await _tap(tester, _k('tf-setup-begin'));
      final card = tester.widget<Container>(_k('tf-setup-qr'));
      expect((card.decoration! as BoxDecoration).color, AtomicPalette.white);
      expect(card.padding, const EdgeInsets.all(16));
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.backgroundColor, AtomicPalette.white);
      expect(qr.eyeStyle.color, AtomicPalette.black);
      expect(qr.dataModuleStyle.color, AtomicPalette.black);
    });

    testWidgets('320 dp at 2x text: every stage lays out, 48 dp targets',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf, width: 320, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_k('tf-setup-begin')).height,
          greaterThanOrEqualTo(48));

      await _tap(tester, _k('tf-setup-begin'));
      expect(tester.takeException(), isNull);
      for (final key in [
        'tf-setup-copy-key',
        'tf-setup-verify',
        'tf-setup-cancel'
      ]) {
        await tester.ensureVisible(_k(key));
        expect(tester.getSize(_k(key)).height, greaterThanOrEqualTo(48),
            reason: key);
      }
      expect(tester.getRect(find.byType(QrImageView)).right,
          lessThanOrEqualTo(320));

      await tester.enterText(_field, '123456');
      await tester.pump();
      tf.confirms.single.complete(_synthCodes);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(AtomicCheckbox));
      expect(tester.getSize(find.byType(AtomicCheckbox)).height,
          greaterThanOrEqualTo(48));
    });

    testWidgets('entrance motion runs, and is instant under reduced motion',
        (tester) async {
      final title = find.text(TwoFactorPage.offHeading);
      double opacity() => tester
          .widgetList<FadeTransition>(
              find.ancestor(of: title, matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value)
          .fold(1.0, (a, b) => a * b);

      await _pump(tester, _HeldTwoFactor(), settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(opacity(), lessThan(1));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, _HeldTwoFactor(),
          disableAnimations: true, settle: false);
      await tester.pump();
      expect(opacity(), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('semantics: header title, labelled QR and saved checkbox',
        (tester) async {
      final handle = tester.ensureSemantics();
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);
      expect(find.bySemanticsLabel('Two-factor setup QR code'), findsNothing);

      await _tap(tester, _k('tf-setup-begin'));
      expect(find.bySemanticsLabel('Two-factor setup QR code'), findsOneWidget);
      expect(tester.getSemantics(find.text(TwoFactorPage.step1Title)),
          isSemantics(isHeader: true));

      await tester.enterText(_field, '123456');
      await tester.pump();
      tf.confirms.single.complete(_synthCodes);
      await _settle(tester);
      expect(
        tester.getSemantics(find.byType(AtomicCheckbox)),
        isSemantics(label: TwoFactorPage.savedLabel, isChecked: false),
      );
      await _tap(tester, find.text(TwoFactorPage.savedLabel));
      expect(
        tester.getSemantics(find.byType(AtomicCheckbox)),
        isSemantics(label: TwoFactorPage.savedLabel, isChecked: true),
      );
      handle.dispose();
    });
  });
}
