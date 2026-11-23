// UX-08-intro: the onboarding tour and the Energy intro on the redesign
// tokens (screens spec, Onboarding and Energy intro), in both themes, with
// semantics, 48 dp targets and reduced motion. Behaviour and persistence are
// pinned separately in intro_pages_characterization_test.dart. Synthetic
// data only; Hive runs in a temp directory.
// Widget tests use an in-memory authBox (the editor_owned_save_test
// pattern): a disk write awaited by the page never completes inside the
// widget test's fake async zone.
import 'dart:io';
import 'dart:typed_data';

import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/ambient.dart';
import 'package:atomic_notes/utility/intropages/energy_intro_screen.dart';
import 'package:atomic_notes/utility/intropages/intro_art.dart';
import 'package:atomic_notes/utility/intropages/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const _themes = {'light': AtomicColors.light, 'dark': AtomicColors.dark};

/// The fixed legacy colours these pages used to set.
const _legacy = <Color>[
  AppColors.ink,
  AppColors.paper,
  AppColors.signal,
  AppColors.slateData,
  AppColors.outlineVariant,
];

int _mainStubs = 0;

class _MainStub extends StatefulWidget {
  const _MainStub();
  @override
  State<_MainStub> createState() => _MainStubState();
}

class _MainStubState extends State<_MainStub> {
  @override
  void initState() {
    super.initState();
    _mainStubs++;
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('Main page stub'));
}

class _Pops extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

void _view(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester,
  String screen, {
  AtomicColors colors = AtomicColors.light,
  double textScale = 1,
  bool reduceMotion = false,
  NavigatorObserver? observer,
}) async {
  final intro = screen == 'onboarding'
      ? const OnBoardingScreen()
      : const EnergyIntroScreen();
  await tester.pumpWidget(MaterialApp(
    theme: AtomicTheme.build(colors),
    navigatorObservers: [if (observer != null) observer],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion),
      child: child!,
    ),
    routes: {
      '/intro': (_) => intro,
      '/mainpage': (_) => const _MainStub(),
    },
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).pushNamed('/intro'),
          child: const Text('Home stub'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Home stub'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('intro-next')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

String? _indicator(WidgetTester tester) => tester
    .widget<Semantics>(find.byKey(const ValueKey('intro-indicator')))
    .properties
    .label;

double _page(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

TextStyle _style(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).style!;

const _screens = ['onboarding', 'energy'];

void main() {
  late Directory directory;

  setUp(() async {
    AmbientBudget.reset();
    directory = await Directory.systemTemp.createTemp('atomic-intro-ui-');
    Hive.init(directory.path);
    await Hive.openBox<bool>('authBox', bytes: Uint8List(0));
    EnergyService.instance.debugSet(limits: const EnergyLimits());
  });

  tearDown(() async {
    EnergyService.instance
        .debugSet(wallet: Wallet.empty, limits: const EnergyLimits());
    AmbientBudget.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final MapEntry(key: theme, value: c) in _themes.entries) {
    for (final screen in _screens) {
      testWidgets('$screen reads the $theme tokens on every page',
          (tester) async {
        _view(tester, const Size(400, 860));
        await _pump(tester, screen, colors: c);
        final scaffold = tester.widget<Scaffold>(find
            .descendant(
                of: find.byType(IntroTour), matching: find.byType(Scaffold))
            .first);
        expect(scaffold.backgroundColor, c.canvas);
        for (var i = 0; i < 4; i++) {
          final title = _style(tester, 'intro-title-$i');
          expect(title.color, c.textPrimary);
          expect(title.fontSize, AtomicType.display.fontSize);
          expect(title.fontWeight, AtomicType.display.fontWeight);
          expect(title.fontFamily, AtomicFonts.sans);
          final body = _style(tester, 'intro-body-$i');
          expect(body.color, c.textSecondary);
          expect(body.fontSize, AtomicType.bodyLarge.fontSize);
          expect(_style(tester, 'intro-eyebrow-$i').color, c.accentText);
          for (final key in ['title', 'body', 'eyebrow']) {
            expect(
                _legacy, isNot(contains(_style(tester, 'intro-$key-$i').color)),
                reason: '$key $i');
          }
          final frame = tester
              .widget<DecoratedBox>(find.byKey(ValueKey('intro-art-frame-$i')));
          final deco = frame.decoration as BoxDecoration;
          expect(deco.borderRadius, AtomicRadius.xLargeAll);
          expect(deco.color, c.surfaceInset);
          if (i < 3) await _next(tester);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('copy is sentence case, not upper-cased', (tester) async {
    _view(tester, const Size(400, 860));
    await _pump(tester, 'onboarding');
    expect(find.text('Your notes,\nat a glance.'), findsOneWidget);
    expect(find.text('Everything in one place'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('SKIP'), findsNothing);
    expect(find.text('EVERYTHING IN ONE PLACE'), findsNothing);
    for (var i = 0; i < 3; i++) {
      await _next(tester);
    }
    expect(find.text('Start'), findsOneWidget);
    expect(
        find.textContaining('uses its server to sync them with your Google '
            'Drive'),
        findsOneWidget);
    expect(find.textContaining('sync only to your account'), findsNothing);
  });

  for (final screen in _screens) {
    testWidgets('$screen semantics: art labels, headers, Next and the pager',
        (tester) async {
      _view(tester, const Size(400, 860));
      final handle = tester.ensureSemantics();
      await _pump(tester, screen);
      expect(_indicator(tester), 'Page 1 of 4');
      final next =
          tester.getSemantics(find.byKey(const ValueKey('intro-next')));
      expect(next.label, 'Next');
      expect(next.flagsCollection.isButton, isTrue);
      expect(next.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final artLabels = screen == 'onboarding'
          ? IntroArtKind.values.map(IntroArt.labelOf).toList()
          : const [
              'An atom forming',
              'The Atomic Energy mark',
              'An atom turning into a coin',
              'The Atomic Coin mark',
            ];
      for (var i = 0; i < 4; i++) {
        expect(find.bySemanticsLabel(artLabels[i]), findsOneWidget,
            reason: 'art $i');
        expect(
            tester
                .getSemantics(find.byKey(ValueKey('intro-title-$i')))
                .flagsCollection
                .isHeader,
            isTrue);
        expect(_indicator(tester), 'Page ${i + 1} of 4');
        if (i < 3) await _next(tester);
      }
      handle.dispose();
    });

    testWidgets('$screen targets: Skip and done are 48 high, Next is 64',
        (tester) async {
      _view(tester, const Size(400, 860));
      await _pump(tester, screen);
      final skip = tester.getSize(find.byKey(const ValueKey('intro-skip')));
      expect(skip.height, greaterThanOrEqualTo(48));
      expect(skip.width, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byKey(const ValueKey('intro-next'))),
          const Size(64, 64));
      for (var i = 0; i < 3; i++) {
        await _next(tester);
      }
      expect(find.byKey(const ValueKey('intro-next')), findsNothing);
      final done = tester.getSize(find.byKey(const ValueKey('intro-done')));
      expect(done.height, greaterThanOrEqualTo(48));
    });

    testWidgets('$screen motion: Next slides, and jumps under reduced motion',
        (tester) async {
      _view(tester, const Size(400, 860));
      await _pump(tester, screen);
      await tester.tap(find.byKey(const ValueKey('intro-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_page(tester), allOf(greaterThan(0), lessThan(1)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_page(tester), 1);

      await tester.pumpWidget(const SizedBox.shrink());
      AmbientBudget.reset();
      await _pump(tester, screen, reduceMotion: true);
      await tester.tap(find.byKey(const ValueKey('intro-next')));
      await tester.pump();
      expect(_page(tester), 1);
      expect(_indicator(tester), 'Page 2 of 4');
    });

    testWidgets('$screen art floats, and holds still under reduced motion',
        (tester) async {
      _view(tester, const Size(400, 860));
      Offset drift() => tester
          .widget<Transform>(find
              .descendant(
                  of: find.byKey(const ValueKey('intro-art-frame-0')),
                  matching: find.byType(Transform))
              .first)
          .transform
          .getTranslation()
          .let((v) => Offset(v.x, v.y));
      await _pump(tester, screen);
      await tester.pump(const Duration(seconds: 3));
      expect(drift().dy, lessThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      AmbientBudget.reset();
      await _pump(tester, screen, reduceMotion: true);
      await tester.pump(const Duration(seconds: 3));
      expect(drift(), Offset.zero);
    });

    for (final MapEntry(key: theme, value: c) in _themes.entries) {
      testWidgets('$screen at 320 dp / 2x in $theme lays out on every page',
          (tester) async {
        _view(tester, const Size(320, 640));
        await _pump(tester, screen, colors: c, textScale: 2);
        for (var i = 0; i < 4; i++) {
          expect(tester.takeException(), isNull, reason: 'page ${i + 1}');
          expect(find.byKey(const ValueKey('intro-skip')).hitTestable(),
              findsOneWidget);
          if (i < 3) {
            expect(find.byKey(const ValueKey('intro-next')).hitTestable(),
                findsOneWidget);
            await _next(tester);
          }
        }
        expect(find.byKey(const ValueKey('intro-done')).hitTestable(),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('energy: animated art under motion, still marks when reduced',
      (tester) async {
    _view(tester, const Size(400, 860));
    bool gif() => find
        .byWidgetPredicate((w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName.endsWith('atom-formation.gif'))
        .evaluate()
        .isNotEmpty;
    await _pump(tester, 'energy');
    expect(gif(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    AmbientBudget.reset();
    await _pump(tester, 'energy', reduceMotion: true);
    expect(gif(), isFalse);
    expect(find.bySemanticsLabel('An atom forming'), findsOneWidget);
  });

  testWidgets('energy: the cap comes from the wallet', (tester) async {
    _view(tester, const Size(400, 860));
    EnergyService.instance.debugSet(
        wallet: const Wallet(
            coins: 0, energy: 0, energyCap: 150, lastDailyGrantAt: null));
    await _pump(tester, 'energy');
    expect(find.textContaining('up to 150.'), findsOneWidget);
    expect(find.textContaining('up to 120'), findsNothing);
  });

  for (final screen in _screens) {
    testWidgets('$screen: a double tap on Skip leaves once', (tester) async {
      _view(tester, const Size(400, 860));
      final pops = _Pops();
      _mainStubs = 0;
      await _pump(tester, screen, observer: pops);
      final skip = find.byKey(const ValueKey('intro-skip'));
      await tester.tap(skip);
      await tester.tap(skip, warnIfMissed: false);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      if (screen == 'energy') {
        expect(pops.pops, 1);
        expect(find.text('Home stub'), findsOneWidget);
      } else {
        expect(find.text('Main page stub'), findsOneWidget);
        expect(find.byType(OnBoardingScreen), findsNothing);
        expect(_mainStubs, 1);
      }
    });
  }
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
