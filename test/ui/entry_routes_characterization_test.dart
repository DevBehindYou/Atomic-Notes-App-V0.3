// Characterization of the entry routes (UX-08-entry), written against the
// base page APIs only so it runs unchanged before and after the redesign:
// sign-in, splash, logged out, account cache recovery and the startup
// failure screen. It pins route selection through the real resolver, the
// splash's startup ordering, one navigation per action, offline and error
// recovery, and that late async work after dispose or a session change
// never navigates. Every credential and account value here is synthetic.

import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/authentication/auth_pages/login_page.dart';
import 'package:atomic_notes/main.dart' show StartupFailedApp;
import 'package:atomic_notes/page/account_cache_recovery_page.dart';
import 'package:atomic_notes/page/logout_screen.dart';
import 'package:atomic_notes/page/splash_screen.dart';
import 'package:atomic_notes/utility/splash_route_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Splash services whose every slow step waits for the test, and which log
/// the order the splash reaches them in.
class _Startup extends SplashStartupServices {
  _Startup({this.signedIn = true});
  bool signedIn;
  @override
  int sessionRevision = 0;
  final List<String> log = [];
  final vaultReady = Completer<void>();
  final notesReady = Completer<void>();
  final stopReady = Completer<void>();
  final onboardingSaved = Completer<void>();
  bool foreignCache = false;
  bool locked = false;
  bool armed = false;
  int discards = 0;

  @override
  bool get isSignedIn => signedIn;
  @override
  bool get hasForeignPendingCache => foreignCache;
  @override
  bool get vaultLocked => locked;
  @override
  bool get twoFactorArmed => armed;
  @override
  Future<void> initVault() {
    log.add('vault');
    return vaultReady.future;
  }

  @override
  Future<void> startNotes() {
    log.add('notes');
    return notesReady.future;
  }

  @override
  Future<void> stopNotes() {
    log.add('stop');
    return stopReady.future;
  }

  @override
  void clearNotesMemory() => log.add('clear');

  @override
  Future<void> markOnboardingSeen(Box<bool> authBox) {
    log.add('onboarding-write');
    return onboardingSaved.future;
  }

  @override
  void startAccountServices() => log.add('services');

  @override
  void discardStartupVault() => discards++;
}

/// Every route pushed by a page under test, in order, with its arguments.
final List<RouteSettings> _pushed = [];

Route<void> _record(RouteSettings settings) {
  _pushed.add(settings);
  return PageRouteBuilder<void>(
    settings: settings,
    transitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) => Scaffold(body: Text('Ready ${settings.name}')),
  );
}

List<String?> get _names => [for (final s in _pushed) s.name];

Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

const _google = MethodChannel('plugins.flutter.io/google_sign_in');

/// Answers the Google Sign-In channel. [answer] decides each sign-in.
void _mockGoogle(Future<Object?> Function() answer, List<String> calls) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_google, (call) async {
    calls.add(call.method);
    if (call.method == 'signIn') return answer();
    return null;
  });
}

/// The Google action and the terms link, by their whole label in either
/// case (the base page uppercases both).
final Finder _googleButton =
    find.textContaining(RegExp(r'^sign in with google$', caseSensitive: false));
final Finder _termsLink =
    find.textContaining(RegExp(r'^read (the )?terms', caseSensitive: false));

void main() {
  setUp(_pushed.clear);

  group('splash', () {
    late Directory directory;
    late Box<bool> auth;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('atomic-entry-char-');
      Hive.init(directory.path);
      auth = await Hive.openBox<bool>('authBox');
    });
    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    Future<void> open(WidgetTester tester, _Startup startup) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashPage.forTest(startup: startup),
        onGenerateRoute: _record,
      ));
      await _flush(tester);
    }

    testWidgets(
        'every gate combination routes once, through the real resolver, '
        'in the fixed startup order', (tester) async {
      for (final isAuthOn in [false, true]) {
        for (final armed in [false, true]) {
          for (final locked in [false, true]) {
            for (final seen in [false, true]) {
              _pushed.clear();
              await tester.runAsync(() async {
                await auth.put('isAuthOn', isAuthOn);
                await auth.put('hasSeenOnboarding', seen);
              });
              final startup = _Startup()
                ..armed = armed
                ..locked = locked;
              await open(tester, startup);
              expect(startup.log, ['vault'], reason: 'vault first');
              expect(_pushed, isEmpty, reason: 'waits for the vault');
              startup.vaultReady.complete();
              await _flush(tester);
              final expected = const SplashRouteResolver().resolve(
                isSignedIn: true,
                isAuthOn: isAuthOn,
                twoFactorArmed: armed,
                vaultLocked: locked,
                hasSeenOnboarding: seen,
              );
              final combo = 'lock=$isAuthOn 2fa=$armed vault=$locked '
                  'seen=$seen';
              if (expected == SplashRoute.onboarding) {
                expect(_pushed, isEmpty, reason: combo);
                startup.onboardingSaved.complete();
                await _flush(tester);
              }
              expect(_names, [expected.routeName], reason: combo);
              expect(_pushed.single.arguments,
                  expected == SplashRoute.vaultUnlock ? true : isNull,
                  reason: combo);
              expect(startup.log, [
                'vault',
                'notes',
                'services',
                if (expected == SplashRoute.onboarding) 'onboarding-write',
              ], reason: combo);
              await tester.pumpWidget(const SizedBox());
              startup.notesReady.complete();
              expect(startup.discards, 1, reason: combo);
            }
          }
        }
      }
    });

    testWidgets('signed out routes once to sign-in with no account work',
        (tester) async {
      final startup = _Startup(signedIn: false);
      await open(tester, startup);
      expect(_names, ['/loginpage']);
      expect(startup.log, isEmpty);
    });

    testWidgets('offline: notes that never start do not hold the route',
        (tester) async {
      await tester.runAsync(() => auth.put('hasSeenOnboarding', true));
      final startup = _Startup();
      await open(tester, startup);
      startup.vaultReady.complete();
      await _flush(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(_names, ['/mainpage']);
      expect(startup.notesReady.isCompleted, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed vault check falls back once to sign-in; a retry '
        'from a fresh splash routes normally', (tester) async {
      await tester.runAsync(() => auth.put('hasSeenOnboarding', true));
      final failing = _Startup();
      await open(tester, failing);
      failing.vaultReady.completeError(StateError('synthetic vault failure'));
      await _flush(tester);
      expect(_names, ['/loginpage']);
      expect(failing.log, ['vault']);
      expect(find.textContaining('synthetic vault failure'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      _pushed.clear();
      final retry = _Startup();
      await open(tester, retry);
      retry.vaultReady.complete();
      await _flush(tester);
      expect(_names, ['/mainpage']);
      await tester.pumpWidget(const SizedBox());
      retry.notesReady.complete();
    });

    testWidgets('a notes start failure during the onboarding write routes '
        'once to sign-in', (tester) async {
      await tester.runAsync(() => auth.put('hasSeenOnboarding', false));
      final startup = _Startup();
      await open(tester, startup);
      startup.vaultReady.complete();
      await _flush(tester);
      expect(_pushed, isEmpty);
      startup.notesReady.completeError(StateError('synthetic offline'));
      await _flush(tester);
      startup.onboardingSaved.complete();
      await _flush(tester);
      expect(_names, ['/loginpage']);
    });

    testWidgets('disposed during the cache stop: no route, no memory clear',
        (tester) async {
      final startup = _Startup()..foreignCache = true;
      await open(tester, startup);
      expect(startup.log, ['stop']);
      await tester.pumpWidget(const SizedBox());
      expect(startup.discards, 1);
      startup.stopReady.complete();
      await _flush(tester);
      expect(_pushed, isEmpty);
      expect(startup.log, ['stop']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposed during the onboarding write: no route',
        (tester) async {
      await tester.runAsync(() => auth.put('hasSeenOnboarding', false));
      final startup = _Startup();
      await open(tester, startup);
      startup.vaultReady.complete();
      await _flush(tester);
      await tester.pumpWidget(const SizedBox());
      startup.onboardingSaved.complete();
      startup.notesReady.complete();
      await _flush(tester);
      expect(_pushed, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a session change during the vault check restarts the splash '
        'once', (tester) async {
      final startup = _Startup();
      await open(tester, startup);
      startup.sessionRevision++;
      startup.vaultReady.complete();
      await _flush(tester);
      expect(_names, ['/splashpage']);
      expect(startup.log, ['vault']);
    });
  });

  group('sign-in', () {
    late List<String> calls;

    setUp(() => calls = []);
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_google, null));

    Future<void> open(WidgetTester tester) async {
      // The base page's Google row needs a wide view with the test font.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        home: LoginPage(),
        onGenerateRoute: _record,
      ));
      await tester.pump();
    }

    int signIns() => calls.where((c) => c == 'signIn').length;

    Future<void> clearSnackBar(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    // The Google plugin keeps one call chain for the life of the process,
    // and a chain started inside one test's fake clock cannot finish inside
    // the next test's. So every channel scenario runs in this one test.
    testWidgets(
        'Google answers: cancel is quiet and retryable, a platform failure '
        'and a missing server code show mapped copy, a late answer does '
        'nothing',
        (tester) async {
      Future<Object?> Function() answer = () async => null;
      _mockGoogle(() => answer(), calls);

      // Cancelled picker: no message, no navigation, ready again.
      await open(tester);
      await tester.tap(_googleButton);
      await tester.pumpAndSettle();
      expect(signIns(), 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(_pushed, isEmpty);
      await tester.tap(_googleButton);
      await tester.pumpAndSettle();
      expect(signIns(), 2);
      expect(_pushed, isEmpty);

      // Platform failure: generic copy, never the raw detail.
      answer = () async => throw PlatformException(
          code: 'sign_in_failed', message: 'synthetic raw detail');
      await tester.tap(_googleButton);
      await tester.pumpAndSettle();
      expect(signIns(), 3);
      expect(find.text('Unknown error occurred!'), findsOneWidget);
      expect(find.textContaining('synthetic raw detail'), findsNothing);
      expect(_pushed, isEmpty);
      await clearSnackBar(tester);

      // A late answer after the page is gone: nothing happens.
      final lateAnswer = Completer<Object?>();
      answer = () => lateAnswer.future;
      await tester.tap(_googleButton);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(signIns(), 4);
      await tester.pumpWidget(const SizedBox());
      lateAnswer.complete(null);
      await tester.pumpAndSettle();
      expect(_pushed, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);

      // No server auth code: the mapped sentence. Last, because the plugin
      // then keeps that account as its current user.
      await open(tester);
      answer = () async => <String, Object?>{
            'email': 'synthetic-user',
            'id': 'synthetic-id',
            'serverAuthCode': null,
          };
      await tester.tap(_googleButton);
      await tester.pumpAndSettle();
      expect(signIns(), 5);
      expect(find.text("Couldn't complete Google sign-in. Please try again."),
          findsOneWidget);
      expect(_pushed, isEmpty);
      expect(_googleButton, findsOneWidget, reason: 'ready again');
      await clearSnackBar(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the terms link opens the terms once', (tester) async {
      await open(tester);
      await tester.ensureVisible(_termsLink);
      await tester.tap(_termsLink);
      await tester.pumpAndSettle();
      expect(_names, ['/tcpage']);
    });
  });

  group('logged out', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: LoggedOutScreen(),
        onGenerateRoute: _record,
      ));
    }

    testWidgets('forwards once to sign-in after its beat, clearing the stack',
        (tester) async {
      await open(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(_pushed, isEmpty, reason: 'not before the beat');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(_names, ['/loginpage']);
      expect(find.byType(LoggedOutScreen), findsNothing);
      expect(
          tester.state<NavigatorState>(find.byType(Navigator)).canPop(), false);
      await tester.pump(const Duration(seconds: 2));
      expect(_names, ['/loginpage']);
    });

    testWidgets('gone before its beat: no navigation', (tester) async {
      await open(tester);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(_pushed, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('account cache recovery', () {
    const signInLabel = 'Sign in to previous account';

    /// Scrolls the label into view, as a person would, then taps it.
    Future<void> reach(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pump();
    }

    Future<void> open(
        WidgetTester tester, Future<void> Function() signOut) async {
      await tester.pumpWidget(MaterialApp(
        home: AccountCacheRecoveryPage(signOut: signOut),
        onGenerateRoute: _record,
      ));
    }

    testWidgets('repeated taps sign out once and navigate once',
        (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      await open(tester, () {
        calls++;
        return gate.future;
      });
      await reach(tester, signInLabel);
      await tester.tap(find.text(signInLabel));
      await tester.tap(find.text(signInLabel), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.text('Returning to sign-in…'), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(_names, ['/loginpage']);
    });

    testWidgets('offline sign-out failure stays put, then a retry navigates '
        'once', (tester) async {
      var calls = 0;
      await open(tester, () async {
        if (++calls == 1) throw const SocketException('synthetic offline');
      });
      await reach(tester, signInLabel);
      await tester.tap(find.text(signInLabel));
      await tester.pumpAndSettle();
      expect(_pushed, isEmpty);
      expect(find.textContaining('stored notes are unchanged'), findsOneWidget);
      expect(find.textContaining('synthetic offline'), findsNothing);
      await reach(tester, signInLabel);
      await tester.tap(find.text(signInLabel));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(_names, ['/loginpage']);
    });

    testWidgets('a sign-out finishing after the page is gone does nothing',
        (tester) async {
      final gate = Completer<void>();
      await open(tester, () => gate.future);
      await reach(tester, signInLabel);
      await tester.tap(find.text(signInLabel));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pumpAndSettle();
      expect(_pushed, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failure after the page is gone does nothing',
        (tester) async {
      final gate = Completer<void>();
      await open(tester, () => gate.future);
      await reach(tester, signInLabel);
      await tester.tap(find.text(signInLabel));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      gate.completeError(StateError('synthetic late failure'));
      await tester.pumpAndSettle();
      expect(_pushed, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('startup failure', () {
    testWidgets('explains itself with the trace and fits 320 dp at 2.0 text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(
            size: Size(320, 640), textScaler: TextScaler.linear(2)),
        child: StartupFailedApp(error: 'synthetic startup failure'),
      ));
      expect(tester.takeException(), isNull);
      expect(
          find.textContaining(
              RegExp(r"^atomic couldn't start$", caseSensitive: false)),
          findsOneWidget);
      expect(find.textContaining('reopen the app'), findsOneWidget);
      expect(find.text('synthetic startup failure'), findsOneWidget);
    });
  });
}
