// The device lock on lib/ui components (screens spec, Lock screen): the
// fingerprint circle, the title, the instruction and the Unlock button, over
// a fake device authenticator. The unlock logic is the one on main: one
// automatic prompt a second after opening, the button while idle, the
// splash gate order on success, and mapped copy for platform errors (CA18).

import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:atomic_notes/page/endpage/lock_screen.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/utility/splash_route_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

/// A device authenticator whose every prompt waits for the test to answer.
class _FakeAuth extends LocalAuthentication {
  _FakeAuth({this.supported = true});

  final bool supported;
  final List<Completer<bool>> prompts = [];
  final List<String> reasons = [];
  final List<AuthenticationOptions> options = [];

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    authMessages = const [],
    options = const AuthenticationOptions(),
  }) {
    reasons.add(localizedReason);
    this.options.add(options);
    final prompt = Completer<bool>();
    prompts.add(prompt);
    return prompt.future;
  }
}

const Duration _autoPrompt = Duration(seconds: 1);

final Finder _unlock = find.byKey(const ValueKey('lock-unlock'));
final Finder _badge = find.byKey(const ValueKey('lock-badge'));

/// Routes pushed from the lock screen, with the arguments they received.
final List<RouteSettings> _pushed = [];

Route<void> _route(RouteSettings settings, _FakeAuth auth) {
  if (settings.name == '/') {
    return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const Scaffold(body: Text('base page')));
  }
  if (settings.name == SplashRoute.lockScreen.routeName) {
    return MaterialPageRoute<void>(
        settings: settings, builder: (_) => LockScreen(localAuth: auth));
  }
  _pushed.add(settings);
  return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => Scaffold(body: Text('route ${settings.name}')));
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAuth auth, {
  ThemeData? theme,
  double width = 412,
  double height = 915,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    // '/' first, then the lock screen on top of it, as a deep link does.
    initialRoute: SplashRoute.lockScreen.routeName,
    onGenerateRoute: (settings) => _route(settings, auth),
  ));
  // Before the automatic prompt, which is one second after opening.
  if (settle) await tester.pump(const Duration(milliseconds: 900));
}

/// Lets the automatic prompt start.
Future<void> _toAutoPrompt(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 150));

/// Answers the latest prompt and lets the screen react.
Future<void> _answer(WidgetTester tester, _FakeAuth auth, bool result) async {
  auth.prompts.last.complete(result);
  await tester.pumpAndSettle();
}

Future<void> _fail(WidgetTester tester, _FakeAuth auth, Object error) async {
  auth.prompts.last.completeError(error);
  await tester.pumpAndSettle();
}

/// Runs the automatic prompt and refuses it, leaving the screen idle with
/// its entrance finished and no timer pending.
Future<void> _idle(WidgetTester tester, _FakeAuth auth) async {
  await _toAutoPrompt(tester);
  await _answer(tester, auth, false);
}

/// Lets a snackbar time out so no timer is left pending.
Future<void> _clearSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

String _buttonLabel(WidgetTester tester) =>
    tester.getSemantics(_unlock).getSemanticsData().label;

bool _hasTap(WidgetTester tester) => tester
    .getSemantics(_unlock)
    .getSemanticsData()
    .hasAction(SemanticsAction.tap);

void main() {
  setUp(_pushed.clear);

  group('unlock', () {
    testWidgets('prompts once on its own a second after opening',
        (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth);
      expect(auth.prompts, isEmpty);
      expect(find.text(LockScreen.unlockLabel), findsOneWidget);

      await _toAutoPrompt(tester);
      expect(auth.prompts, hasLength(1));
      // The same request as before the redesign.
      expect(auth.reasons.single, 'Privacy for AtomicNotes');
      expect(auth.options.single.stickyAuth, isTrue);
      expect(auth.options.single.biometricOnly, isFalse);
      // The button says it is busy and shows a spinner.
      expect(find.text(LockScreen.busyLabel), findsOneWidget);
      expect(
          find.descendant(
              of: _unlock, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);

      await _answer(tester, auth, false);
    });

    testWidgets('success continues the splash gate order', (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth);
      await _toAutoPrompt(tester);

      await _answer(tester, auth, true);

      // No two-factor and no locked vault for this signed-out test, so the
      // resolver sends the notes.
      const expected = SplashRouteResolver();
      final route = expected.resolve(
        isSignedIn: true,
        isAuthOn: false,
        twoFactorArmed: false,
        vaultLocked: false,
        hasSeenOnboarding: true,
      );
      expect(_pushed.single.name, route.routeName);
      expect(_pushed.single.arguments, isNull);
      expect(find.text('route ${route.routeName}'), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('a cancelled or refused check stays locked, quietly',
        (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth);
      await _toAutoPrompt(tester);

      await _answer(tester, auth, false);

      expect(find.byType(LockScreen), findsOneWidget);
      expect(_pushed, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(LockScreen.unlockLabel), findsOneWidget);
      expect(_hasTap(tester), isTrue);
    });

    testWidgets('Unlock tries again, and success then opens the notes',
        (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth);
      await _toAutoPrompt(tester);
      await _answer(tester, auth, false);

      await tester.tap(_unlock);
      await tester.pump();
      expect(auth.prompts, hasLength(2));
      expect(find.text(LockScreen.busyLabel), findsOneWidget);

      await _answer(tester, auth, true);
      expect(_pushed, hasLength(1));
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('a platform error shows plain copy, never the raw text',
        (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth);
      await _toAutoPrompt(tester);

      await _fail(
          tester,
          auth,
          PlatformException(
              code: 'NotAvailable', message: 'raw platform detail'));

      expect(find.text(LockScreen.failedMessage), findsOneWidget);
      expect(find.textContaining('raw platform detail'), findsNothing);
      expect(find.textContaining('PlatformException'), findsNothing);
      // The error form of the snackbar, with its alert icon.
      expect(
          find.descendant(
              of: find.byType(SnackBar),
              matching: find.byIcon(AtomicIcons.alertCircle)),
          findsOneWidget);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(_pushed, isEmpty);
      // The button is ready for another try.
      expect(find.text(LockScreen.unlockLabel), findsOneWidget);
      expect(_hasTap(tester), isTrue);

      await tester.tap(_unlock);
      await tester.pump();
      expect(auth.prompts, hasLength(2));
      await _answer(tester, auth, true);
      expect(_pushed, hasLength(1));
      await _clearSnackBar(tester);
    });

    testWidgets('the message stays long enough to read', (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth);
      await _toAutoPrompt(tester);
      auth.prompts.last.completeError(PlatformException(code: 'LockedOut'));
      // The snackbar's clock starts once it has slid in.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(LockScreen.failedMessage), findsOneWidget);
      await _clearSnackBar(tester);
      expect(find.text(LockScreen.failedMessage), findsNothing);
    });

    testWidgets('a tap while a check runs does not start a second one',
        (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth);
      await _toAutoPrompt(tester);
      expect(auth.prompts, hasLength(1));
      expect(_hasTap(tester), isFalse);

      await tester.tap(_unlock, warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.text(LockScreen.busyLabel), warnIfMissed: false);
      await tester.pump();
      expect(auth.prompts, hasLength(1));

      await _answer(tester, auth, false);
      expect(_hasTap(tester), isTrue);
    });

    testWidgets('Back leaves as before, and no prompt starts afterwards',
        (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth, settle: false);
      await tester.pump(const Duration(milliseconds: 100));

      // No back interception and no back button, as before the redesign.
      expect(find.byType(PopScope), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('base page'), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);

      await tester.pump(_autoPrompt);
      expect(auth.prompts, isEmpty);
    });
  });

  group('look', () {
    testWidgets('a 96 dp accent circle, the title and the instruction',
        (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth);
      await _idle(tester, auth);

      const c = AtomicColors.light;
      expect(
          tester
              .widget<Scaffold>(find.ancestor(
                  of: find.text(LockScreen.title),
                  matching: find.byType(Scaffold)))
              .backgroundColor,
          c.canvas);
      expect(tester.getSize(_badge), const Size(96, 96));
      final decoration =
          tester.widget<Container>(_badge).decoration! as BoxDecoration;
      expect(decoration.color, c.accent);
      expect(decoration.shape, BoxShape.circle);
      final icon = tester.widget<Icon>(
          find.descendant(of: _badge, matching: find.byType(Icon)));
      expect(icon.icon, AtomicIcons.fingerprint);
      expect(icon.color, c.onAccent);

      final title = tester.widget<Text>(find.text(LockScreen.title));
      expect(title.style!.fontSize, AtomicType.headlineLarge.fontSize);
      expect(title.style!.fontWeight, AtomicType.headlineLarge.fontWeight);
      expect(find.text(LockScreen.instruction), findsOneWidget);
      // The editorial labels are gone.
      expect(find.text('LOCKED'), findsNothing);
      expect(find.text('UNLOCK'), findsNothing);
    });

    testWidgets('a lock instead of a fingerprint when the device cannot check',
        (tester) async {
      final auth = _FakeAuth(supported: false);
      await _pump(tester, auth);
      await _idle(tester, auth);

      final icon = tester.widget<Icon>(
          find.descendant(of: _badge, matching: find.byType(Icon)));
      expect(icon.icon, AtomicIcons.lock);
    });

    for (final (name, theme) in [
      ('light', AtomicTheme.light),
      ('dark', AtomicTheme.dark),
    ]) {
      for (final direction in TextDirection.values) {
        for (final busy in [false, true]) {
          testWidgets(
              'fits 320 dp at 2.0 text ($name, ${direction.name}, '
              '${busy ? 'busy' : 'idle'})', (tester) async {
            final auth = _FakeAuth();
            await _pump(tester, auth,
                theme: theme,
                width: 320,
                height: 640,
                textScale: 2,
                direction: direction);
            if (busy) {
              await _toAutoPrompt(tester);
              await tester.pump(const Duration(milliseconds: 500));
            } else {
              await _idle(tester, auth);
            }
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(_unlock);
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(
                find.text(busy ? LockScreen.busyLabel : LockScreen.unlockLabel),
                findsOneWidget);
            final button = tester.getRect(_unlock);
            expect(button.left, greaterThanOrEqualTo(0));
            expect(button.right, lessThanOrEqualTo(320));
            if (busy) await _answer(tester, auth, false);
          });
        }
      }
    }

    testWidgets('the Unlock target is at least 48 dp', (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth, width: 320, height: 640);

      await _idle(tester, auth);

      final size = tester.getSize(_unlock);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('screen readers hear a heading and one button', (tester) async {
      final semantics = tester.ensureSemantics();
      final auth = _FakeAuth();
      await _pump(tester, auth);
      await _idle(tester, auth);

      expect(tester.getSemantics(find.text(LockScreen.title)),
          isSemantics(label: LockScreen.title, isHeader: true));
      expect(
          tester.getSemantics(_unlock),
          isSemantics(
              label: LockScreen.unlockLabel,
              isButton: true,
              isEnabled: true,
              hasEnabledState: true,
              hasTapAction: true));
      expect(find.bySemanticsLabel(LockScreen.unlockLabel), findsOneWidget);
      await tester.tap(_unlock);
      await tester.pump();
      // While a check runs the button says so and cannot be pressed.
      expect(_buttonLabel(tester), LockScreen.busyLabel);
      expect(_hasTap(tester), isFalse);

      await _answer(tester, auth, false);
      expect(_buttonLabel(tester), LockScreen.unlockLabel);
      semantics.dispose();
    });

    testWidgets('reduced motion shows everything at once', (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth, disableAnimations: true, settle: false);
      await tester.pump();
      for (final text in [LockScreen.title, LockScreen.unlockLabel]) {
        for (final fade in tester.widgetList<FadeTransition>(find.ancestor(
            of: find.text(text), matching: find.byType(FadeTransition)))) {
          expect(fade.opacity.value, 1, reason: text);
        }
      }
      // The fingerprint arrives with a cross-fade capped at 150 ms.
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pump(_autoPrompt);
      await _answer(tester, auth, false);
    });

    testWidgets('without reduced motion the blocks rise in', (tester) async {
      final auth = _FakeAuth();
      await _pump(tester, auth, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      Iterable<double> fades() => tester
          .widgetList<FadeTransition>(
              find.ancestor(of: _unlock, matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value);
      expect(fades(), isNotEmpty);
      expect(fades().any((v) => v < 1), isTrue);
      // The entrance outlasts the one-second wait, so it ends while the
      // automatic prompt runs.
      await tester.pump(const Duration(milliseconds: 1300));
      expect(auth.prompts, hasLength(1));
      expect(fades().every((v) => v == 1), isTrue);

      await _answer(tester, auth, false);
    });
  });
}
