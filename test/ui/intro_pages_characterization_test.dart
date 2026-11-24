// UX-08-intro, step 01: what the onboarding tour and the Energy intro do
// today, written before the redesign and kept passing after it. Finders are
// deliberately presentation-neutral (case- and line-break-insensitive text,
// or a tooltip/semantics label) so the same assertions hold on the base and
// on the migrated pages. Synthetic data only; Hive runs in a temp directory.
// Widget tests use an in-memory authBox (the editor_owned_save_test
// pattern): a disk write awaited by the page never completes inside the
// widget test's fake async zone. The one plain test that proves a later
// launch skips reopens a real on-disk box.
import 'dart:io';
import 'dart:typed_data';

import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/page/splash_screen.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/utility/intropages/energy_intro_screen.dart';
import 'package:atomic_notes/utility/intropages/onboarding_screen.dart';
import 'package:atomic_notes/utility/splash_route_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

String _norm(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// The text of a [Text] widget. Its inner [RichText] is not matched again.
String? _plain(Widget w) =>
    w is Text ? (w.data ?? w.textSpan?.toPlainText()) : null;

/// Any text, tooltip or semantics label equal to [label], ignoring case and
/// line breaks.
Finder _labelled(String label) {
  final want = _norm(label);
  return find.byWidgetPredicate((w) {
    final text = _plain(w);
    if (text != null && _norm(text) == want) return true;
    if (w is Tooltip && w.message != null && _norm(w.message!) == want) {
      return true;
    }
    if (w is Semantics && w.properties.label != null) {
      return _norm(w.properties.label!) == want;
    }
    return false;
  }, skipOffstage: true);
}

/// Text containing [fragment], ignoring case and line breaks.
Finder _containing(String fragment) {
  final want = _norm(fragment);
  return find.byWidgetPredicate((w) {
    final text = _plain(w);
    return text != null && _norm(text).contains(want);
  });
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = _labelled(label).hitTestable();
  expect(target, findsWidgets, reason: 'no hit-testable "$label"');
  await tester.tap(target.first);
  await tester.pump();
  await _settleIo(tester);
}

/// Runs the frames after a tap (the Energy intro pops only after its
/// in-memory flag write completes).
Future<void> _settleIo(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void _view(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

const _onboardingTitles = [
  'Your notes, at a glance.',
  'Plain notes and checklists.',
  'Sync that keeps up.',
  'Local first, locked down.',
];

const _energyTitles = [
  'Energy powers your sync.',
  'Long-press the sync button.',
  'Coins top up your energy.',
  'Instant or automatic.',
];

/// Pumps the onboarding tour as the splash reaches it, by name, with a stub
/// home to land on.
Future<void> _pumpOnboarding(WidgetTester tester,
    {double textScale = 1, bool reduceMotion = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion),
      child: child!,
    ),
    initialRoute: '/onboardingscreen',
    routes: {
      '/onboardingscreen': (_) => const OnBoardingScreen(),
      '/mainpage': (_) => const Scaffold(body: Text('Main page stub')),
    },
  ));
  await tester.pump();
}

/// Pushes the Energy intro on top of a stub home, the way Home and the
/// Energy page open it.
Future<void> _pumpEnergy(WidgetTester tester,
    {double textScale = 1, bool reduceMotion = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion),
      child: child!,
    ),
    routes: {'/energyintro': (_) => const EnergyIntroScreen()},
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).pushNamed('/energyintro'),
          child: const Text('Home stub'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Home stub'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  late Directory directory;
  late Box<bool> auth;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-intro-');
    Hive.init(directory.path);
    auth = await Hive.openBox<bool>('authBox', bytes: Uint8List(0));
    EnergyService.instance.debugSet(limits: const EnergyLimits());
  });

  tearDown(() async {
    EnergyService.instance.debugSet(limits: const EnergyLimits());
    await Hive.close();
    await directory.delete(recursive: true);
  });

  group('first-run persistence (read only)', () {
    test('the keys are the ones on disk today', () {
      expect(EnergyIntroScreen.seenFlag, 'hasSeenEnergyIntro');
      expect(SplashRoute.onboarding.routeName, '/onboardingscreen');
    });

    test('onboarding flag: written by the splash once, a later launch skips',
        () async {
      const resolver = SplashRouteResolver();
      SplashRoute launch() => resolver.resolve(
            isSignedIn: true,
            isAuthOn: false,
            twoFactorArmed: false,
            vaultLocked: false,
            hasSeenOnboarding:
                auth.get('hasSeenOnboarding', defaultValue: false) ?? false,
          );
      // This test needs the real disk: swap the in-memory box for one.
      await auth.close();
      auth = await Hive.openBox<bool>('authBox');
      expect(launch(), SplashRoute.onboarding);
      await const SplashStartupServices().markOnboardingSeen(auth);
      expect(auth.get('hasSeenOnboarding'), isTrue);
      // A later launch reopens the box from disk.
      await auth.close();
      auth = await Hive.openBox<bool>('authBox');
      expect(auth.get('hasSeenOnboarding'), isTrue);
      expect(launch(), SplashRoute.mainPage);
    });

    testWidgets('the onboarding tour itself writes nothing to authBox',
        (tester) async {
      _view(tester, const Size(400, 860));
      await _pumpOnboarding(tester);
      for (var i = 0; i < 3; i++) {
        await _tap(tester, 'Next');
      }
      await _tap(tester, 'Start');
      expect(find.text('Main page stub'), findsOneWidget);
      expect(auth.keys, isEmpty);
    });

    testWidgets('Energy intro: Got it writes the flag', (tester) async {
      _view(tester, const Size(400, 860));
      await _pumpEnergy(tester);
      for (var i = 0; i < 3; i++) {
        await _tap(tester, 'Next');
      }
      await _tap(tester, 'Got it');
      expect(find.text('Home stub'), findsOneWidget);
      expect(auth.keys.toList(), ['hasSeenEnergyIntro']);
      expect(auth.get(EnergyIntroScreen.seenFlag), isTrue);
    });

    testWidgets('Energy intro: Skip writes the flag and pops', (tester) async {
      _view(tester, const Size(400, 860));
      await _pumpEnergy(tester);
      await _tap(tester, 'Skip');
      expect(find.text('Home stub'), findsOneWidget);
      expect(find.byType(EnergyIntroScreen), findsNothing);
      expect(auth.get(EnergyIntroScreen.seenFlag), isTrue);
    });

    testWidgets('Energy intro: system Back leaves the flag unset',
        (tester) async {
      _view(tester, const Size(400, 860));
      await _pumpEnergy(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Home stub'), findsOneWidget);
      expect(auth.get(EnergyIntroScreen.seenFlag), isNull);
    });

    testWidgets('Energy intro replay keeps the flag true', (tester) async {
      _view(tester, const Size(400, 860));
      await tester.runAsync(() => auth.put(EnergyIntroScreen.seenFlag, true));
      await _pumpEnergy(tester);
      expect(_containing(_energyTitles.first), findsOneWidget);
      await _tap(tester, 'Skip');
      expect(find.text('Home stub'), findsOneWidget);
      expect(auth.get(EnergyIntroScreen.seenFlag), isTrue);
      expect(auth.keys.toList(), ['hasSeenEnergyIntro']);
    });
  });

  group('page count and order', () {
    testWidgets('onboarding: four pages in order, Skip on every page',
        (tester) async {
      _view(tester, const Size(400, 860));
      await _pumpOnboarding(tester);
      for (var i = 0; i < _onboardingTitles.length; i++) {
        expect(_containing(_onboardingTitles[i]).hitTestable(), findsOneWidget,
            reason: 'page ${i + 1}');
        expect(_labelled('Skip').hitTestable(), findsWidgets);
        final last = i == _onboardingTitles.length - 1;
        expect(_labelled('Start').hitTestable(),
            last ? findsWidgets : findsNothing);
        expect(_labelled('Next').hitTestable(),
            last ? findsNothing : findsWidgets);
        if (!last) await _tap(tester, 'Next');
      }
    });

    testWidgets('onboarding: Skip on page one goes to the main page',
        (tester) async {
      _view(tester, const Size(400, 860));
      await _pumpOnboarding(tester);
      await _tap(tester, 'Skip');
      expect(find.text('Main page stub'), findsOneWidget);
      expect(find.byType(OnBoardingScreen, skipOffstage: false), findsNothing);
    });

    testWidgets('energy: four pages in order', (tester) async {
      _view(tester, const Size(400, 860));
      await _pumpEnergy(tester);
      for (var i = 0; i < _energyTitles.length; i++) {
        expect(_containing(_energyTitles[i]).hitTestable(), findsOneWidget,
            reason: 'page ${i + 1}');
        final last = i == _energyTitles.length - 1;
        expect(_labelled('Got it').hitTestable(),
            last ? findsWidgets : findsNothing);
        if (!last) await _tap(tester, 'Next');
      }
    });
  });

  group('Energy intro content', () {
    testWidgets('quotes the policy prices and the economy constants',
        (tester) async {
      _view(tester, const Size(400, 860));
      EnergyService.instance.debugSet(
          limits: const EnergyLimits(syncInstantCost: 13, syncStandardCost: 7));
      await _pumpEnergy(tester);
      expect(
          _containing('+${EnergyService.dailyGrant} Atomic Energy free every '
              '24 hours'),
          findsOneWidget);
      await _tap(tester, 'Next');
      await _tap(tester, 'Next');
      expect(
          _containing('1 Atomic Coin converts to '
              '${EnergyService.coinToEnergy} energy'),
          findsOneWidget);
      await _tap(tester, 'Next');
      expect(_containing('Each instant batch costs 13 energy'), findsOneWidget);
      expect(_containing('automatic batch costs 7'), findsOneWidget);
      expect(_containing('more than 13'), findsOneWidget);
      expect(_containing('Receive-only sync is free'), findsOneWidget);
      expect(_containing('costs 10 energy'), findsNothing);
    });
  });

  group('large text at 320 dp / 2x', () {
    for (final screen in ['onboarding', 'energy']) {
      testWidgets('$screen: every page lays out and its actions stay reachable',
          (tester) async {
        _view(tester, const Size(320, 640));
        if (screen == 'onboarding') {
          await _pumpOnboarding(tester, textScale: 2);
        } else {
          await _pumpEnergy(tester, textScale: 2);
        }
        final done = screen == 'onboarding' ? 'Start' : 'Got it';
        for (var i = 0; i < 4; i++) {
          expect(tester.takeException(), isNull, reason: 'page ${i + 1}');
          expect(_labelled('Skip').hitTestable(), findsWidgets);
          await _tap(tester, i == 3 ? done : 'Next');
        }
        expect(tester.takeException(), isNull);
        expect(
            find.text(screen == 'onboarding' ? 'Main page stub' : 'Home stub'),
            findsOneWidget);
      });
    }
  });

  group('reduced motion', () {
    for (final screen in ['onboarding', 'energy']) {
      testWidgets('$screen: Next still advances with animations disabled',
          (tester) async {
        _view(tester, const Size(400, 860));
        if (screen == 'onboarding') {
          await _pumpOnboarding(tester, reduceMotion: true);
        } else {
          await _pumpEnergy(tester, reduceMotion: true);
        }
        final titles =
            screen == 'onboarding' ? _onboardingTitles : _energyTitles;
        await _tap(tester, 'Next');
        expect(_containing(titles[1]).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
