// The entry routes on lib/ui components (UX-08-entry, screens spec: Login,
// Splash, Logged out, Account cache recovery): look in both themes, 320 dp
// at 2.0 text, semantics, 48 dp targets, keyboard activation, reduced
// motion, and one navigation per action, including late answers after the
// page has gone. The route decisions are pinned separately in
// entry_routes_characterization_test.dart. Every value here is synthetic.

import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/authentication/auth_pages/login_page.dart';
import 'package:atomic_notes/page/account_cache_recovery_page.dart';
import 'package:atomic_notes/page/logout_screen.dart';
import 'package:atomic_notes/page/splash_screen.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/mascot/mascot_stage.dart';
import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:atomic_notes/utility/component/atomic_splash_mark.dart';
import 'package:atomic_notes/utility/component/login_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsData;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every route pushed by a page under test, in order.
final List<String?> _pushed = [];

Route<void> _record(RouteSettings settings) {
  _pushed.add(settings.name);
  return PageRouteBuilder<void>(
    settings: settings,
    transitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) => Scaffold(body: Text('Ready ${settings.name}')),
  );
}

final _themes = [('light', AtomicTheme.light), ('dark', AtomicTheme.dark)];

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  ThemeData? theme,
  double width = 412,
  double height = 915,
  double textScale = 1,
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
      child: child!,
    ),
    home: page,
    onGenerateRoute: _record,
  ));
  if (settle) await tester.pumpAndSettle();
}

Color? _scaffoldColor(WidgetTester tester, Finder inside) => tester
    .widget<Scaffold>(find.ancestor(of: inside, matching: find.byType(Scaffold)))
    .backgroundColor;

/// The combined opacity of the entrance fades above [finder].
double _opacity(WidgetTester tester, Finder finder) {
  var value = 1.0;
  for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(of: finder, matching: find.byType(FadeTransition)))) {
    value *= fade.opacity.value;
  }
  return value;
}

SemanticsData _node(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData();

void _fits(WidgetTester tester, Finder target, double width) {
  final rect = tester.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
}

final Finder _google = find.byKey(const ValueKey('login-google'));
final Finder _googleFace = find.byKey(const ValueKey('login-google-face'));
final Finder _guest = find.byKey(const ValueKey('login-guest'));
final Finder _terms = find.byKey(const ValueKey('login-terms'));

/// A Google sign-in the test answers.
class _SignIn {
  final List<Completer<void>> calls = [];
  Future<void> call() {
    final c = Completer<void>();
    calls.add(c);
    return c.future;
  }
}

void main() {
  setUp(_pushed.clear);

  group('login', () {
    for (final (name, theme) in _themes) {
      testWidgets('look on $name: canvas, mark, headline and Google style',
          (tester) async {
        await _pump(tester, const LoginPage(), theme: theme);
        final c = theme.extension<AtomicColors>()!;
        final dark = theme.brightness == Brightness.dark;
        expect(_scaffoldColor(tester, _google), c.canvas);

        final mark = find.byType(AtomicBrandMark);
        expect(tester.getSize(mark), const Size(64, 64));
        expect(tester.widget<AtomicBrandMark>(mark).onDark, dark);

        final title = tester.widget<Text>(find.text(LoginPage.title));
        expect(title.style!.fontSize, AtomicType.display.fontSize);
        expect(title.style!.color, c.textPrimary);
        final subtitle = tester.widget<Text>(find.text(LoginPage.subtitle));
        expect(subtitle.style!.fontSize, AtomicType.bodyLarge.fontSize);
        expect(subtitle.style!.color, c.textSecondary);

        // Google's dark button on the light theme, light on the dark one.
        final style = dark ? LoginButton.onDark : LoginButton.onLight;
        final face = tester.widget<DecoratedBox>(_googleFace).decoration
            as BoxDecoration;
        expect(face.color, style.fill);
        expect((face.border! as Border).top.color, style.stroke);
        expect(
            tester.widget<Text>(find.text(LoginPage.googleLabel)).style!.color,
            style.label);
        // The official mark, in its own colours, never tinted.
        final svg = tester.widget<SvgPicture>(
            find.byKey(const ValueKey('login-google-mark')));
        expect(svg.colorFilter, isNull);
        expect(googleMark, contains('#4285F4'));
        expect(googleMark, contains('#EA4335'));
        expect(googleMark, contains('#FBBC05'));
        expect(googleMark, contains('#34A853'));

        final link = tester.widget<Text>(find.text(LoginPage.termsLink));
        expect(link.style!.color, c.infoText);
        expect(find.text(LoginPage.termsLine), findsOneWidget);
        // The editorial copy is gone; the Guest entry stays gated.
        expect(find.text('WELCOME'), findsNothing);
        expect(find.text('SIGN IN WITH GOOGLE'), findsNothing);
        expect(_guest, findsNothing);
      });
    }

    testWidgets('success navigates once to the splash; a second tap in the '
        'same frame does not sign in twice', (tester) async {
      final signIn = _SignIn();
      await _pump(tester, LoginPage(signIn: signIn.call));
      await tester.tap(_google);
      await tester.tap(_google, warnIfMissed: false);
      await tester.pump();
      expect(signIn.calls, hasLength(1));
      await tester.tap(_google, warnIfMissed: false);
      await tester.pump();
      expect(signIn.calls, hasLength(1));
      signIn.calls.single.complete();
      await tester.pumpAndSettle();
      expect(_pushed, ['/splashpage']);
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('busy: spinner in the button, no tap action, Guest disabled',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final signIn = _SignIn();
      await _pump(tester, LoginPage(signIn: signIn.call, guestEntry: true));
      expect(_node(tester, _google).hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(_google);
      await tester.pump();
      expect(
          find.descendant(
              of: _google, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(_node(tester, _google).hasAction(SemanticsAction.tap), isFalse);
      expect(tester.widget<AtomicButton>(_guest).onPressed, isNull);
      signIn.calls.single.completeError(ApiException('cancelled', 0));
      await tester.pumpAndSettle();
      expect(_node(tester, _google).hasAction(SemanticsAction.tap), isTrue);
      expect(tester.widget<AtomicButton>(_guest).onPressed, isNotNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(_pushed, isEmpty);
      semantics.dispose();
    });

    testWidgets('a server failure shows the mapped copy in the error snackbar',
        (tester) async {
      final signIn = _SignIn();
      await _pump(tester, LoginPage(signIn: signIn.call));
      await tester.tap(_google);
      await tester.pump();
      signIn.calls.single.completeError(ApiException('http_503', 503));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'The Atomic Notes server had a problem. Please try again shortly.'),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SnackBar),
              matching: find.byIcon(AtomicIcons.alertCircle)),
          findsOneWidget);
      expect(_pushed, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('an offline failure keeps the page and can be retried',
        (tester) async {
      final signIn = _SignIn();
      await _pump(tester, LoginPage(signIn: signIn.call));
      await tester.tap(_google);
      await tester.pump();
      signIn.calls.single.completeError(StateError('synthetic offline'));
      await tester.pumpAndSettle();
      expect(find.text('Unknown error occurred!'), findsOneWidget);
      expect(find.textContaining('synthetic offline'), findsNothing);
      expect(_pushed, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(_google);
      await tester.pump();
      expect(signIn.calls, hasLength(2));
      signIn.calls.last.complete();
      await tester.pumpAndSettle();
      expect(_pushed, ['/splashpage']);
    });

    testWidgets('a sign-in finishing after the page is gone does not navigate',
        (tester) async {
      for (final fail in [false, true]) {
        _pushed.clear();
        final signIn = _SignIn();
        await _pump(tester, LoginPage(signIn: signIn.call));
        await tester.tap(_google);
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        if (fail) {
          signIn.calls.single.completeError(ApiException('http_500', 500));
        } else {
          signIn.calls.single.complete();
        }
        await tester.pumpAndSettle();
        expect(_pushed, isEmpty, reason: 'fail=$fail');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('keyboard: Tab reaches the Google button and Enter signs in',
        (tester) async {
      final signIn = _SignIn();
      await _pump(tester, LoginPage(signIn: signIn.call));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
          find
              .ancestor(of: find.byWidget(focused.widget), matching: _google)
              .evaluate(),
          isNotEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(signIn.calls, hasLength(1));
      signIn.calls.single.complete();
      await tester.pumpAndSettle();
      expect(_pushed, ['/splashpage']);
    });

    testWidgets('semantics: one header, named buttons, a labelled mark',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, const LoginPage(guestEntry: true));
      final google = _node(tester, _google);
      expect(google.label, LoginPage.googleLabel);
      expect(google.flagsCollection.isButton, isTrue);
      expect(_node(tester, _guest).label, LoginPage.guestLabel);
      final terms = _node(tester, _terms);
      expect(terms.label, LoginPage.termsLink);
      expect(terms.flagsCollection.isButton, isTrue);
      expect(find.bySemanticsLabel(LoginPage.title), findsOneWidget);
      expect(
          _node(tester, find.text(LoginPage.title))
              .flagsCollection.isHeader,
          isTrue);
      expect(find.bySemanticsLabel('Atomic Notes'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('every target is at least 48 dp', (tester) async {
      await _pump(tester, const LoginPage(guestEntry: true),
          width: 320, height: 640);
      for (final target in [_google, _guest, _terms]) {
        await tester.ensureVisible(target);
        final size = tester.getSize(target);
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('the terms link opens the terms once', (tester) async {
      await _pump(tester, const LoginPage());
      await tester.ensureVisible(_terms);
      await tester.tap(_terms);
      await tester.pumpAndSettle();
      expect(_pushed, ['/tcpage']);
    });

    for (final (name, theme) in _themes) {
      testWidgets('fits 320 dp at 2.0 text ($name)', (tester) async {
        final signIn = _SignIn();
        await _pump(tester, LoginPage(signIn: signIn.call, guestEntry: true),
            theme: theme, width: 320, height: 640, textScale: 2);
        expect(tester.takeException(), isNull);
        for (final target in [_google, _guest, _terms]) {
          await tester.ensureVisible(target);
          await tester.pump();
          expect(tester.takeException(), isNull);
          _fits(tester, target, 320);
        }
        await tester.ensureVisible(_google);
        await tester.pump();
        await tester.tap(_google);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        signIn.calls.single.completeError(ApiException('cancelled', 0));
        await tester.pumpAndSettle();
      });
    }

    testWidgets('motion: blocks rise in, and reduced motion shows them at once',
        (tester) async {
      await _pump(tester, const LoginPage(), settle: false);
      await tester.pump();
      expect(_opacity(tester, find.text(LoginPage.title)), lessThan(1));
      await tester.pumpAndSettle();
      expect(_opacity(tester, find.text(LoginPage.title)), 1);

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, const LoginPage(),
          disableAnimations: true, settle: false);
      await tester.pump();
      expect(_opacity(tester, find.text(LoginPage.title)), 1);
      expect(_opacity(tester, _google), 1);
    });
  });

  group('splash', () {
    final status = find.byKey(const ValueKey('splash-status'));

    for (final (name, theme) in _themes) {
      testWidgets('look on $name: the static mark on canvas and the status',
          (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, const SplashView(), theme: theme);
        final c = theme.extension<AtomicColors>()!;
        expect(_scaffoldColor(tester, status), c.canvas);
        expect(
            tester.getSize(find.byKey(const ValueKey('splash-mark'))),
            const Size(120, 120));
        expect(find.byType(AtomicSplashMark), findsOneWidget);
        final text = tester.widget<Text>(status);
        expect(text.data, 'Getting things ready…');
        expect(text.style!.fontSize, AtomicType.bodySmall.fontSize);
        expect(text.style!.color, c.textSecondary);
        expect(_node(tester, status).flagsCollection.isLiveRegion,
            isTrue);
        expect(find.text('INITIALISING · CHECKING SESSION'), findsNothing);
        expect(find.byKey(const ValueKey('splash-version')), findsOneWidget);
        semantics.dispose();
      });

      testWidgets('fits 320 dp at 2.0 text ($name)', (tester) async {
        await _pump(tester, const SplashView(),
            theme: theme, width: 320, height: 640, textScale: 2);
        expect(tester.takeException(), isNull);
        _fits(tester, status, 320);
      });
    }

    testWidgets('the splash page draws the splash view', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashPage.forTest(startup: _NeverStartup()),
        onGenerateRoute: _record,
      ));
      expect(find.byType(SplashView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('reduced motion shows the mark and status at once',
        (tester) async {
      await _pump(tester, const SplashView(),
          disableAnimations: true, settle: false);
      await tester.pump();
      expect(_opacity(tester, status), 1);
      expect(_opacity(tester, find.byType(AtomicSplashMark)), 1);
    });
  });

  group('logged out', () {
    final signIn = find.byKey(const ValueKey('loggedout-sign-in'));

    for (final (name, theme) in _themes) {
      testWidgets('look on $name: mascot, title and a primary Sign in',
          (tester) async {
        await _pump(tester, const LoggedOutScreen(),
            theme: theme, settle: false);
        await tester.pump();
        final c = theme.extension<AtomicColors>()!;
        expect(_scaffoldColor(tester, signIn), c.canvas);
        expect(tester.getSize(find.byType(MascotStage)), const Size(96, 96));
        expect(find.text(LoggedOutScreen.title), findsOneWidget);
        expect(find.text(LoggedOutScreen.body), findsOneWidget);
        final button = tester.widget<AtomicButton>(signIn);
        expect(button.variant, AtomicButtonVariant.primary);
        expect(button.label, LoggedOutScreen.signInLabel);
        final size = tester.getSize(signIn);
        expect(size.height, greaterThanOrEqualTo(48));
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('fits 320 dp at 2.0 text ($name)', (tester) async {
        await _pump(tester, const LoggedOutScreen(),
            theme: theme,
            width: 320,
            height: 640,
            textScale: 2,
            settle: false);
        await tester.pump();
        expect(tester.takeException(), isNull);
        _fits(tester, signIn, 320);
        await tester.pump(const Duration(seconds: 1));
      });
    }

    testWidgets('Sign in goes now, and the beat does not navigate again',
        (tester) async {
      await _pump(tester, const LoggedOutScreen(), settle: false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_pushed, isEmpty);
      await tester.tap(signIn);
      await tester.tap(signIn, warnIfMissed: false);
      await tester.pump();
      expect(_pushed, ['/loginpage']);
      await tester.pump(const Duration(seconds: 2));
      expect(_pushed, ['/loginpage']);
      expect(
          tester.state<NavigatorState>(find.byType(Navigator)).canPop(), false);
    });

    testWidgets('semantics: a header and a named button', (tester) async {
      final semantics = tester.ensureSemantics();
      // Reduced motion, so every block is shown before the beat ends.
      await _pump(tester, const LoggedOutScreen(),
          disableAnimations: true, settle: false);
      await tester.pump();
      expect(
          _node(tester, find.text(LoggedOutScreen.title))
              .flagsCollection.isHeader,
          isTrue);
      final button = _node(tester, signIn);
      expect(button.label, LoggedOutScreen.signInLabel);
      expect(button.hasAction(SemanticsAction.tap), isTrue);
      await tester.pump(const Duration(seconds: 1));
      semantics.dispose();
    });
  });

  group('account cache recovery', () {
    final action = find.byKey(const ValueKey('recovery-sign-in'));
    final warning = find.byKey(const ValueKey('recovery-warning'));
    final failed = find.byKey(const ValueKey('recovery-failed'));

    for (final (name, theme) in _themes) {
      testWidgets('look on $name: title, attention warning, primary action',
          (tester) async {
        await _pump(tester, AccountCacheRecoveryPage(signOut: () async {}),
            theme: theme);
        final c = theme.extension<AtomicColors>()!;
        expect(_scaffoldColor(tester, action), c.canvas);
        final title =
            tester.widget<Text>(find.text(AccountCacheRecoveryPage.title));
        expect(title.style!.fontSize, AtomicType.headlineLarge.fontSize);
        final banner = tester.widget<AtomicBanner>(warning);
        expect(banner.tone, BannerTone.attention);
        expect(banner.title, AccountCacheRecoveryPage.warningTitle);
        expect(failed, findsNothing);
        final button = tester.widget<AtomicButton>(action);
        expect(button.variant, AtomicButtonVariant.primary);
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
      });

      testWidgets('fits 320 dp at 2.0 text with the failure shown ($name)',
          (tester) async {
        await _pump(
            tester,
            AccountCacheRecoveryPage(
                signOut: () async => throw StateError('synthetic')),
            theme: theme,
            width: 320,
            height: 640,
            textScale: 2);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(action);
        await tester.pump();
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.ensureVisible(failed);
        await tester.pump();
        expect(tester.takeException(), isNull);
        _fits(tester, action, 320);
        _fits(tester, failed, 320);
      });
    }

    testWidgets('progress uses the existing text; failure is a danger banner '
        'in a live region', (tester) async {
      final semantics = tester.ensureSemantics();
      final gate = Completer<void>();
      await _pump(tester, AccountCacheRecoveryPage(signOut: () => gate.future));
      await tester.ensureVisible(action);
      await tester.pump();
      await tester.tap(action);
      await tester.pump();
      expect(_node(tester, action).label, AccountCacheRecoveryPage.busyLabel);
      expect(_node(tester, action).hasAction(SemanticsAction.tap), isFalse);
      gate.completeError(StateError('synthetic'));
      await tester.pumpAndSettle();
      final banner = tester.widget<AtomicBanner>(failed);
      expect(banner.tone, BannerTone.danger);
      expect(banner.body, contains('stored notes are unchanged'));
      final live = find.ancestor(
          of: failed,
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && (w.properties.liveRegion ?? false)));
      expect(live, findsOneWidget);
      expect(_node(tester, action).label, AccountCacheRecoveryPage.signInLabel);
      expect(_node(tester, action).hasAction(SemanticsAction.tap), isTrue);
      expect(_pushed, isEmpty);
      semantics.dispose();
    });

    testWidgets('reduced motion shows the page at once', (tester) async {
      await _pump(tester, AccountCacheRecoveryPage(signOut: () async {}),
          disableAnimations: true, settle: false);
      await tester.pump();
      expect(_opacity(tester, warning), 1);
      expect(_opacity(tester, action), 1);
    });
  });
}

/// Splash services that never finish, so the page stays on its view.
class _NeverStartup extends SplashStartupServices {
  @override
  bool get isSignedIn => true;
  @override
  int get sessionRevision => 0;
  @override
  void discardStartupVault() {}
}
