// The two-factor gate on lib/ui components (screens spec, Two-factor gate):
// the large title, six 48 x 56 code cells over one real field, Verify, the
// recovery-code toggle and the key-unavailable path. The check logic is the
// service's; the page owns the stale-result guard: a result that returns
// after the page has gone, after a newer attempt, or after the sign-in
// changed never opens the app. All codes here are synthetic.

import 'dart:async';

import 'package:atomic_notes/page/endpage/two_factor_gate_page.dart';
import 'package:atomic_notes/security/two_factor.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/utility/component/two_factor_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/two_factor_fakes.dart';

/// A [TwoFactor] whose checks and probes wait for the test to answer.
class _HeldTwoFactor extends TwoFactor {
  _HeldTwoFactor()
      : super(storage: FakeTwoFactorStorage(), account: () => testAccount);

  final List<Completer<TwoFactorCheck>> checks = [];
  final List<String> inputs = [];

  /// When set, every probe waits; otherwise it answers [readable].
  bool holdProbes = false;
  bool readable = true;
  final List<Completer<bool>> probes = [];
  int probeCount = 0;
  int resets = 0;

  @override
  Future<bool> hasVerificationData() {
    probeCount++;
    if (!holdProbes) return Future.value(readable);
    final c = Completer<bool>();
    probes.add(c);
    return c.future;
  }

  @override
  Future<TwoFactorCheck> check(String input) {
    inputs.add(input);
    final c = Completer<TwoFactorCheck>();
    checks.add(c);
    return c.future;
  }

  @override
  Future<void> resetOnThisDevice() async => resets++;
}

const _ok = TwoFactorCheck(TwoFactorResult.ok);
const _wrong = TwoFactorCheck(TwoFactorResult.wrong);

final Finder _field = find.byType(TextField);
final Finder _title = find.byKey(const ValueKey('tf-gate-title'));
final Finder _verify = find.byKey(const ValueKey('tf-gate-verify'));
final Finder _toggle = find.byKey(const ValueKey('tf-gate-toggle'));
final Finder _retry = find.byKey(const ValueKey('tf-gate-retry'));
final Finder _turnOff = find.byKey(const ValueKey('tf-gate-turn-off'));
final Finder _locked = find.byKey(const ValueKey('tf-gate-locked'));
final Finder _unavailable = find.byKey(const ValueKey('tf-gate-unavailable'));
Finder _cell(int i) => find.byKey(TwoFactorCodeField.cellKey(i));

final List<String> _pushed = [];

Future<void> _pump(
  WidgetTester tester,
  TwoFactor tf, {
  Object? Function()? identity,
  ThemeData? theme,
  double width = 412,
  double height = 915,
  double textScale = 1,
  bool disableAnimations = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: TwoFactorGatePage(twoFactor: tf, identity: identity),
    onGenerateRoute: (settings) {
      _pushed.add(settings.name!);
      return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('route ${settings.name}')));
    },
  ));
  if (settle) await tester.pumpAndSettle();
}

TextField _textField(WidgetTester tester) => tester.widget<TextField>(_field);

AtomicButton _button(WidgetTester tester, Finder f) =>
    tester.widget<AtomicButton>(f);

String _cellText(WidgetTester tester, int i) {
  final texts = find.descendant(of: _cell(i), matching: find.byType(Text));
  if (texts.evaluate().isEmpty) return '';
  return tester.widget<Text>(texts.first).data ?? '';
}

BoxDecoration _cellBox(WidgetTester tester, int i) {
  final box = tester.widget<AnimatedContainer>(
      find.descendant(of: _cell(i), matching: find.byType(AnimatedContainer)));
  return box.decoration! as BoxDecoration;
}

void main() {
  setUp(_pushed.clear);

  group('layout', () {
    testWidgets('large title, six 48 x 56 cells, Verify and the toggle',
        (tester) async {
      await _pump(tester, _HeldTwoFactor());

      expect(find.text(TwoFactorGatePage.title), findsOneWidget);
      expect(find.text(TwoFactorGatePage.codeHint), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        expect(tester.getSize(_cell(i)), const Size(48, 56));
      }
      expect(_cell(6), findsNothing);
      expect(_field, findsOneWidget);
      expect(_button(tester, _verify).variant, AtomicButtonVariant.primary);
      expect(tester.getSize(_verify).height, 56);
      expect(find.text(TwoFactorGatePage.useRecovery), findsOneWidget);
      expect(tester.getSize(_toggle).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });

    testWidgets('probing shows a ring and no field yet', (tester) async {
      final tf = _HeldTwoFactor()..holdProbes = true;
      await _pump(tester, tf, settle: false);
      await tester.pump();

      expect(find.byKey(const ValueKey('tf-gate-probing')), findsOneWidget);
      expect(_field, findsNothing);
      tf.probes.single.complete(true);
      await tester.pumpAndSettle();
      expect(_field, findsOneWidget);
    });

    testWidgets('dark theme uses the dark tokens', (tester) async {
      await _pump(tester, _HeldTwoFactor(), theme: AtomicTheme.dark);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AtomicColors.dark.canvas);
      expect(_cellBox(tester, 0).color, AtomicColors.dark.surfaceInset);
      final title = tester.widget<Text>(_title);
      expect(title.style!.color, AtomicColors.dark.textPrimary);
    });

    testWidgets('320 dp at 2x text: no overflow, cells fit, 48 dp targets',
        (tester) async {
      await _pump(tester, _HeldTwoFactor(), width: 320, textScale: 2);

      expect(tester.takeException(), isNull);
      final right = tester.getRect(_cell(5)).right;
      expect(right, lessThanOrEqualTo(320 - 20));
      expect(tester.getRect(_cell(0)).left, greaterThanOrEqualTo(20));
      expect(tester.getSize(_cell(0)).height, 56);
      expect(tester.getSize(_verify).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(_toggle).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(_field).width, greaterThanOrEqualTo(48));

      await tester.ensureVisible(_toggle);
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_verify).height, greaterThanOrEqualTo(48));
    });

    testWidgets('entrance motion runs, and is instant under reduced motion',
        (tester) async {
      double titleOpacity() => tester
          .widgetList<FadeTransition>(
              find.ancestor(of: _title, matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value)
          .fold(1.0, (a, b) => a * b);

      await _pump(tester, _HeldTwoFactor(), settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(titleOpacity(), lessThan(1));
      await tester.pumpAndSettle();
      expect(titleOpacity(), 1);

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, _HeldTwoFactor(),
          disableAnimations: true, settle: false);
      await tester.pump();
      expect(titleOpacity(), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('semantics: one named text field, header title, cells hidden',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _HeldTwoFactor());

      expect(
        tester.getSemantics(_field),
        isSemantics(label: TwoFactorCodeField.digitLabel, isTextField: true),
      );
      expect(tester.getSemantics(_title), isSemantics(isHeader: true));
      await tester.enterText(_field, '12');
      await tester.pump();
      // The digits are read once, as the field's value, not per cell.
      expect(find.bySemanticsLabel('1'), findsNothing);
      handle.dispose();
    });
  });

  group('code field', () {
    testWidgets('digits only, six long, number keyboard, one-time-code autofill',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);

      final field = _textField(tester);
      expect(field.keyboardType, TextInputType.number);
      expect(field.textInputAction, TextInputAction.done);
      expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);

      await tester.enterText(_field, '12a4');
      await tester.pump();
      expect(field.controller!.text, '124');
      expect([for (var i = 0; i < 6; i++) _cellText(tester, i)],
          ['1', '2', '4', '', '', '']);
      expect(tf.checks, isEmpty);
    });

    testWidgets('the next empty cell shows focus', (tester) async {
      await _pump(tester, _HeldTwoFactor());
      await tester.enterText(_field, '12');
      await tester.pumpAndSettle();
      final focus = AtomicColors.light.focus;
      expect((_cellBox(tester, 2).border! as Border).top.color, focus);
      expect((_cellBox(tester, 1).border! as Border).top.color,
          isNot(focus));
    });

    testWidgets('Done on the keyboard submits a typed code', (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);
      await tester.enterText(_field, '12345');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tf.inputs, ['12345']);
      tf.checks.single.complete(_wrong);
      await tester.pumpAndSettle();
    });
  });

  group('valid and invalid codes', () {
    testWidgets('a full code submits once and the right one opens the app',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);

      await tester.enterText(_field, '123456');
      await tester.pump();
      expect(tf.inputs, ['123456']);
      expect(_button(tester, _verify).busy, isTrue);
      expect(_textField(tester).enabled, isFalse);

      tf.checks.single.complete(_ok);
      await tester.pumpAndSettle();
      expect(_pushed, ['/mainpage']);
      expect(find.text('route /mainpage'), findsOneWidget);
    });

    testWidgets('a wrong code clears the cells and shows the message',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);

      await tester.enterText(_field, '000000');
      await tester.pump();
      tf.checks.single.complete(_wrong);
      await tester.pumpAndSettle();

      expect(find.text(TwoFactorGatePage.wrongCode), findsOneWidget);
      expect(_textField(tester).controller!.text, isEmpty);
      expect(_cellText(tester, 0), isEmpty);
      expect((_cellBox(tester, 0).border! as Border).top.color,
          AtomicColors.light.danger);
      expect(_pushed, isEmpty);
      expect(_button(tester, _verify).busy, isFalse);
      expect(_textField(tester).enabled, isTrue);

      // A retry is a fresh check, and success clears the message.
      await tester.enterText(_field, '111111');
      await tester.pump();
      expect(tf.inputs, ['000000', '111111']);
      expect(find.text(TwoFactorGatePage.wrongCode), findsNothing);
      tf.checks.last.complete(_ok);
      await tester.pumpAndSettle();
      expect(_pushed, ['/mainpage']);
    });

    testWidgets('too many wrong tries lock the field and Verify',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);

      await tester.enterText(_field, '000000');
      await tester.pump();
      tf.checks.single.complete(const TwoFactorCheck(TwoFactorResult.locked,
          retryAfter: Duration(seconds: 30)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_locked, findsOneWidget);
      expect(tester.widget<AtomicBanner>(_locked).tone, BannerTone.danger);
      expect(find.textContaining('Too many wrong tries'), findsOneWidget);
      expect(_button(tester, _verify).onPressed, isNull);
      expect(_textField(tester).enabled, isFalse);
      await tester.tap(_verify);
      await tester.pump();
      expect(tf.inputs, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('repeat submission', () {
    testWidgets('Done and Verify while a check runs start no second check',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);

      // The sixth digit auto-submits; Done arrives in the same frame, before
      // the field rebuilds as disabled.
      await tester.enterText(_field, '123456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(_verify, warnIfMissed: false);
      await tester.pump();
      expect(tf.inputs, ['123456']);
      expect(_button(tester, _toggle).onPressed, isNull);

      tf.checks.single.complete(_ok);
      await tester.pumpAndSettle();
      expect(_pushed, ['/mainpage']);
    });
  });

  group('route disposal and stale results', () {
    testWidgets('a result after the page has gone does nothing',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);
      await tester.enterText(_field, '123456');
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      tf.checks.single.complete(_ok);
      await tester.pumpAndSettle();
      expect(_pushed, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an old account\'s success never opens the new account',
        (tester) async {
      Object? account = 'account-a';
      final tf = _HeldTwoFactor();
      await _pump(tester, tf, identity: () => account);
      await tester.enterText(_field, '123456');
      await tester.pump();

      account = 'account-b';
      tf.checks.single.complete(_ok);
      await tester.pumpAndSettle();

      expect(_pushed, isEmpty);
      expect(find.text(TwoFactorGatePage.signInChanged), findsOneWidget);
      expect(_textField(tester).controller!.text, isEmpty);
      expect(tf.probeCount, 2, reason: 'reads the new account again');

      // The new account's own code works.
      await tester.enterText(_field, '654321');
      await tester.pump();
      tf.checks.last.complete(_ok);
      await tester.pumpAndSettle();
      expect(_pushed, ['/mainpage']);
    });

    testWidgets('an old account\'s lock is not shown to the new account',
        (tester) async {
      Object? account = 'account-a';
      final tf = _HeldTwoFactor();
      await _pump(tester, tf, identity: () => account);
      await tester.enterText(_field, '000000');
      await tester.pump();

      account = 'account-b';
      tf.checks.single.complete(const TwoFactorCheck(TwoFactorResult.locked,
          retryAfter: Duration(seconds: 30)));
      await tester.pumpAndSettle();

      expect(_locked, findsNothing);
      expect(_textField(tester).enabled, isTrue);
      expect(_button(tester, _verify).onPressed, isNotNull);
    });

    testWidgets('an old account\'s probe is read again for the new account',
        (tester) async {
      Object? account = 'account-a';
      final tf = _HeldTwoFactor()..holdProbes = true;
      await _pump(tester, tf, identity: () => account, settle: false);
      await tester.pump();

      account = 'account-b';
      tf.probes.first.complete(false);
      await tester.pump();
      expect(_unavailable, findsNothing);
      expect(tf.probes, hasLength(2));

      tf.probes.last.complete(true);
      await tester.pumpAndSettle();
      expect(_unavailable, findsNothing);
      expect(_field, findsOneWidget);
    });
  });

  group('recovery code', () {
    testWidgets('the toggle switches to one recovery field and back',
        (tester) async {
      final tf = _HeldTwoFactor();
      await _pump(tester, tf);

      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(find.text(TwoFactorGatePage.recoveryHint), findsOneWidget);
      expect(find.text(TwoFactorCodeField.recoveryLabel), findsOneWidget);
      expect(_cell(0), findsNothing);
      expect(_field, findsOneWidget);
      expect(_textField(tester).autofillHints ?? const <String>[],
          isNot(contains(AutofillHints.oneTimeCode)));

      await tester.enterText(_field, 'abcde-23456');
      await tester.pump();
      expect(_textField(tester).controller!.text, 'ABCDE-23456');
      expect(tf.checks, isEmpty, reason: 'recovery codes never auto-submit');

      await tester.tap(_verify);
      await tester.pump();
      expect(tf.inputs, ['ABCDE-23456']);
      tf.checks.single.complete(_wrong);
      await tester.pumpAndSettle();
      expect(find.text(TwoFactorGatePage.wrongRecovery), findsOneWidget);

      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(find.text(TwoFactorGatePage.useRecovery), findsOneWidget);
      expect(find.text(TwoFactorGatePage.wrongRecovery), findsNothing);
      expect(_cell(0), findsOneWidget);
    });
  });

  group('key unavailable', () {
    testWidgets('a banner, Try again re-reads, Turn off asks first',
        (tester) async {
      final tf = _HeldTwoFactor()..readable = false;
      await _pump(tester, tf);

      expect(_unavailable, findsOneWidget);
      expect(find.text(TwoFactorGatePage.unavailableTitle), findsOneWidget);
      expect(find.text(TwoFactorGatePage.unavailableBody), findsOneWidget);
      expect(_field, findsNothing);

      await tester.tap(_retry);
      await tester.pumpAndSettle();
      expect(tf.probeCount, 2);

      await tester.tap(_turnOff);
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
      expect(find.text(TwoFactorGatePage.turnOffBody), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tf.resets, 0);
      expect(_pushed, isEmpty);

      await tester.tap(_turnOff);
      await tester.pumpAndSettle();
      await tester.tap(find.text(TwoFactorGatePage.turnOffConfirm));
      await tester.pumpAndSettle();
      expect(tf.resets, 1);
      expect(_pushed, ['/mainpage']);
    });

    testWidgets('a sign-in change while confirming resets nothing',
        (tester) async {
      Object? account = 'account-a';
      final tf = _HeldTwoFactor()..readable = false;
      await _pump(tester, tf, identity: () => account);

      await tester.tap(_turnOff);
      await tester.pumpAndSettle();
      account = 'account-b';
      await tester.tap(find.text(TwoFactorGatePage.turnOffConfirm));
      await tester.pumpAndSettle();
      expect(tf.resets, 0);
      expect(_pushed, isEmpty);
    });
  });
}
