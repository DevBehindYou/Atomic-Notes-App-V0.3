// Mascot settings on lib/ui components (screens spec, Mascot settings): the
// hero stage, the animate switch and the seven mascot cards, over a fake
// preference store and synthetic mascot frames. No Hive files, no bundled
// clip decoding.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:atomic_notes/mascot/mascot_asset_resolver.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_cubit.dart';
import 'package:atomic_notes/mascot/mascot_frame_source.dart';
import 'package:atomic_notes/mascot/mascot_preferences.dart';
import 'package:atomic_notes/mascot/mascot_view.dart';
import 'package:atomic_notes/page/endpage/mascot_settings_page.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/controls/atomic_switch.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/ambient.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The stored preferences, with an optional future-version read, failing
/// writes or a gate on writes.
class _Store implements MascotPreferencesStore {
  _Store({this.read_ = const MascotPreferenceRead.missing()});

  final MascotPreferenceRead read_;
  final List<MascotPreferences> writes = [];
  int failures = 0;
  Completer<void>? gate;

  @override
  Future<MascotPreferenceRead> read() async => read_;

  @override
  Future<void> write(MascotPreferences value) async {
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (failures > 0) {
      failures--;
      throw StateError('write failed');
    }
    writes.add(value);
  }
}

class _NoFetchResolver implements MascotAssetResolver {
  @override
  Future<MascotAssetLease> openVerifiedClip(MascotClip clip) =>
      throw StateError('frames come from the synthetic source');
}

/// Synthetic frames: every clip has three 100 ms frames of a 1 px image.
class _Frames implements MascotFrameSource {
  final List<_Session> sessions = [];

  int get reads => sessions.fold(0, (sum, s) => sum + s.reads);
  int get openSessions => sessions.where((s) => !s.closed).length;

  @override
  Future<MascotFrameSession> open(MascotClip clip, int pixels) async {
    final session = _Session(clip.id);
    sessions.add(session);
    return session;
  }
}

class _Session implements MascotFrameSession {
  _Session(this.clipId);

  final String clipId;
  int reads = 0;
  bool closed = false;

  @override
  int get frameCount => 3;

  @override
  Future<OwnedMascotFrame> nextFrame() async {
    reads++;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1, 1);
    picture.dispose();
    return OwnedMascotFrame(image, const Duration(milliseconds: 100));
  }

  @override
  Future<void> close() async => closed = true;
}

Finder _card(MascotDefinition m) => find.byKey(ValueKey('choose-${m.id}'));
final Finder _toggle = find.byKey(const ValueKey('mascot-animate'));
final Finder _heroName = find.byKey(const ValueKey('mascot-hero-name'));

MascotView _hero(WidgetTester tester) => tester
    .widgetList<MascotView>(find.byType(MascotView))
    .singleWhere((v) => v.interactive);

double _offset(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

/// Lets the entrance finish without waiting for the looping mascot, which
/// never settles while it animates.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _Store store;
  late MascotCubit preferences;
  late _Frames frames;

  Future<void> start({MascotPreferenceRead? read}) async {
    store = _Store(read_: read ?? const MascotPreferenceRead.missing());
    preferences = MascotCubit(store);
    await preferences.load();
  }

  setUp(() async {
    frames = _Frames();
    await start();
  });
  tearDown(() async => preferences.close());

  Widget page({Key? key}) => MascotSettingsPage(
      key: key,
      preferences: preferences,
      resolver: _NoFetchResolver(),
      frameSource: frames);

  Future<void> pump(
    WidgetTester tester, {
    ThemeData? theme,
    double width = 412,
    double height = 915,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
    bool disableAnimations = false,
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
      routes: {
        '/': (_) => page(),
        '/other': (_) => const Scaffold(body: Text('other page')),
      },
    ));
    await _settle(tester);
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  /// From the top, down until [finder] is built, then fully into view.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  group('choices', () {
    testWidgets('each of the seven mascots can be chosen and is stored',
        (tester) async {
      await pump(tester);
      expect(MascotCatalog.all, hasLength(7));
      // The default (Hoot) last, so every tap changes the choice.
      final order = [
        ...MascotCatalog.all.where((m) => m.id != MascotCatalog.defaultId),
        MascotCatalog.defaultMascot,
      ];
      for (final mascot in order) {
        await scrollTo(tester, _card(mascot));
        await tester.tap(_card(mascot));
        await tester.pump();
        await tester.pump();
        expect(preferences.state.desired.selectedId, mascot.id);
        expect(store.writes.last.selectedId, mascot.id);
        await tester.drag(find.byType(ListView), const Offset(0, 3000));
        await tester.pump();
        expect(tester.widget<Text>(_heroName).data, mascot.displayName);
        expect(_hero(tester).mascot.id, mascot.id);
      }
      expect(store.writes.map((w) => w.selectedId),
          order.map((m) => m.id).toList());
      await leave(tester);
    });

    testWidgets('the seven bundled mascots are offered in catalog order',
        (tester) async {
      await pump(tester);
      const names = ['Tilde', 'Antimatter', 'Rocco', 'Lappy', 'Pocket'];
      for (final name in [...names, 'Hoot', 'Vaulty']) {
        expect(MascotCatalog.all.map((m) => m.displayName), contains(name));
      }
      double? lastTop;
      double? lastLeft;
      for (final mascot in MascotCatalog.all) {
        await scrollTo(tester, _card(mascot));
        final rect = tester.getRect(_card(mascot));
        // Position in the list, independent of the scroll offset.
        final y = rect.top + _offset(tester);
        if (lastTop != null) {
          expect(y > lastTop || (y == lastTop && rect.left > lastLeft!), isTrue,
              reason: '${mascot.displayName} follows the previous card');
        }
        lastTop = y;
        lastLeft = rect.left;
      }
      expect(find.textContaining('Download'), findsNothing);
      await leave(tester);
    });

    testWidgets('the animate switch turns motion off and on and stores it',
        (tester) async {
      await pump(tester);
      expect(
          tester
              .widget<AtomicSwitchTrack>(find.descendant(
                  of: _toggle, matching: find.byType(AtomicSwitchTrack)))
              .value,
          isTrue);
      await scrollTo(tester, _toggle);
      await tester.tap(_toggle);
      await tester.pump();
      await tester.pump();
      expect(preferences.state.desired.animationsEnabled, isFalse);
      expect(store.writes.last.animationsEnabled, isFalse);
      expect(_hero(tester).animationsEnabled, isFalse);

      await tester.tap(_toggle);
      await tester.pump();
      await tester.pump();
      expect(preferences.state.desired.animationsEnabled, isTrue);
      expect(store.writes.last.animationsEnabled, isTrue);
      expect(_hero(tester).animationsEnabled, isTrue);
      await leave(tester);
    });

    testWidgets('saving, then saved on this device', (tester) async {
      await pump(tester);
      store.gate = Completer<void>();
      final tilde = MascotCatalog.findById('052-tilde')!;
      await scrollTo(tester, _card(tilde));
      await tester.tap(_card(tilde));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pump();
      expect(find.text('Saving your choice…'), findsOneWidget);
      store.gate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Saved on this device'), findsOneWidget);
      expect(store.writes.last.selectedId, tilde.id);
      await leave(tester);
    });

    testWidgets('a failed save says so and Retry save stores it',
        (tester) async {
      await pump(tester);
      store.failures = 1;
      final rocco = MascotCatalog.findById('047-rocco')!;
      await scrollTo(tester, _card(rocco));
      await tester.tap(_card(rocco));
      await tester.pump();
      await tester.pump();
      expect(preferences.state.saveState, MascotSaveState.error);
      expect(store.writes, isEmpty);
      final retry = find.byKey(const ValueKey('mascot-retry-save'));
      await scrollTo(tester, retry);
      expect(find.text('Your choice could not be saved yet.'), findsOneWidget);
      await tester.tap(retry);
      await tester.pump();
      await tester.pump();
      expect(store.writes.single.selectedId, rocco.id);
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pump();
      expect(find.text('Your choice could not be saved yet.'), findsNothing);
      expect(find.text('Saved on this device'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('settings from a newer app are read-only and say why',
        (tester) async {
      await preferences.close();
      await start(read: const MascotPreferenceRead.futureVersion());
      await pump(tester);
      expect(
          find.text('These settings were saved by a newer app. '
              'Update the app to change them.'),
          findsOneWidget);
      final tilde = MascotCatalog.findById('052-tilde')!;
      await scrollTo(tester, _card(tilde));
      await tester.tap(_card(tilde), warnIfMissed: false);
      await scrollTo(tester, _toggle);
      await tester.tap(_toggle, warnIfMissed: false);
      await tester.pump();
      expect(preferences.state.desired.selectedId, MascotCatalog.defaultId);
      expect(preferences.state.desired.animationsEnabled, isTrue);
      expect(store.writes, isEmpty);
      await leave(tester);
    });
  });

  group('semantics', () {
    testWidgets('the chosen mascot is marked selected, the others offer Use',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      for (final mascot in MascotCatalog.all) {
        await scrollTo(tester, _card(mascot));
        final chosen = mascot.id == MascotCatalog.defaultId;
        expect(
            tester.getSemantics(_card(mascot)),
            isSemantics(
                label:
                    chosen ? mascot.displayName : 'Use ${mascot.displayName}',
                isButton: true,
                hasSelectedState: true,
                isSelected: chosen,
                hasEnabledState: true,
                isEnabled: true,
                hasTapAction: true),
            reason: mascot.displayName);
      }
      handle.dispose();
      await leave(tester);
    });

    testWidgets('the switch row is one toggle and the hero mascot a button',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      expect(
          tester.getSemantics(_toggle),
          isSemantics(
              label: 'Animate mascot. ${MascotSettingsPage.animateCaption}',
              hasToggledState: true,
              isToggled: true,
              hasEnabledState: true,
              isEnabled: true,
              hasTapAction: true));
      expect(
          tester.getSemantics(find.byWidget(_hero(tester))),
          isSemantics(
              label: 'Hoot, change animation',
              isButton: true,
              hasTapAction: true));
      handle.dispose();
      await leave(tester);
    });
  });

  group('motion', () {
    testWidgets('only the hero mascot animates, at 64 dp or more',
        (tester) async {
      await pump(tester);
      final views = tester.widgetList<MascotView>(find.byType(MascotView));
      final animated = views.where((v) => v.animationsEnabled).toList();
      expect(animated, hasLength(1));
      expect(animated.single.interactive, isTrue);
      expect(animated.single.size, greaterThanOrEqualTo(64));
      // The stage's art (spec: 160 stage, 6 dp padding, less the focus
      // border the tappable mascot draws).
      expect(tester.getSize(find.byWidget(animated.single)).width,
          greaterThanOrEqualTo(MascotSettingsPage.heroStage - 16));
      for (final card in views.where((v) => !v.animationsEnabled)) {
        expect(card.interactive, isFalse);
        expect(card.size, greaterThanOrEqualTo(64));
      }
      // No decorative loop of its own: the mascot is the one ambient effect.
      expect(AmbientBudget.active, 0);

      final before = frames.reads;
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(frames.reads, greaterThan(before), reason: 'the hero plays');
      await leave(tester);
    });

    testWidgets('tapping the hero mascot changes its animation',
        (tester) async {
      await pump(tester);
      final opens = frames.sessions.length;
      await tester.tap(find.byWidget(_hero(tester)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(frames.sessions.length, greaterThan(opens));
      expect(preferences.state.desired.selectedId, MascotCatalog.defaultId);
      await leave(tester);
    });

    testWidgets('reduced motion: nothing runs and the caption says why',
        (tester) async {
      await pump(tester, disableAnimations: true);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      final reads = frames.reads;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(frames.reads, reads, reason: 'no new mascot frames');
      expect(frames.openSessions, 0);
      expect(find.text(MascotSettingsPage.reducedCaption), findsOneWidget);
      // The switch still stores the choice for when motion returns.
      await tester.tap(_toggle);
      await tester.pump();
      expect(store.writes.last.animationsEnabled, isFalse);
      await leave(tester);
    });

    testWidgets('scrolled off screen the mascot pauses; back in view it plays',
        (tester) async {
      await pump(tester);
      final heroFinder = find.byWidgetPredicate(
          (w) => w is MascotView && w.interactive,
          skipOffstage: false);
      final card = find
          .ancestor(
              of: heroFinder,
              matching: find.byType(AtomicCard, skipOffstage: false))
          .first;
      final away = tester.getRect(card).bottom -
          tester.getTopLeft(find.byType(ListView)).dy +
          AtomicSpace.x5;
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      position.jumpTo(position.pixels + away);
      await _settle(tester);
      // Just out of view and still built in the list's cache, so only the
      // pause stops it.
      expect(heroFinder, findsOneWidget);
      expect(tester.getRect(card).bottom,
          lessThan(tester.getTopLeft(find.byType(ListView)).dy));
      final reads = frames.reads;
      await tester.pump(const Duration(seconds: 2));
      expect(frames.reads, reads);
      expect(frames.openSessions, 0);

      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await _settle(tester);
      expect(frames.reads, greaterThan(reads));
      await leave(tester);
    });

    // At 320 dp and 2.0 text the list drops the hero once it is far away,
    // and rebuilds it when a jump brings it back.
    final heroBuilt = find.byWidgetPredicate(
        (w) => w is MascotView && w.interactive,
        skipOffstage: false);
    ScrollPosition list(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    testWidgets('jumping back from beyond the list cache, the mascot plays',
        (tester) async {
      await pump(tester, width: 320, height: 640, textScale: 2);
      // Twice: the second return needs the first one's measurement done.
      for (var round = 0; round < 2; round++) {
        list(tester).jumpTo(list(tester).maxScrollExtent);
        await _settle(tester);
        expect(heroBuilt, findsNothing, reason: 'round $round: dropped');
        final reads = frames.reads;
        await tester.pump(const Duration(seconds: 2));
        expect(frames.reads, reads, reason: 'round $round: nothing plays');
        expect(frames.openSessions, 0);

        list(tester).jumpTo(0);
        await _settle(tester);
        expect(heroBuilt, findsOneWidget);
        expect(frames.reads, greaterThan(reads),
            reason: 'round $round: back in view it plays');
      }
      await leave(tester);
    });

    testWidgets('rebuilt off screen in the list cache, the mascot stays paused',
        (tester) async {
      await pump(tester, width: 320, height: 640, textScale: 2);
      final card = find
          .ancestor(
              of: heroBuilt,
              matching: find.byType(AtomicCard, skipOffstage: false))
          .first;
      final listTop = tester.getTopLeft(find.byType(ListView)).dy;
      final away = tester.getRect(card).bottom - listTop + AtomicSpace.x5;
      list(tester).jumpTo(list(tester).maxScrollExtent);
      await _settle(tester);
      expect(heroBuilt, findsNothing);

      list(tester).jumpTo(away);
      await _settle(tester);
      expect(heroBuilt, findsOneWidget, reason: 'built again in the cache');
      expect(tester.getRect(card).bottom, lessThan(listTop));
      final reads = frames.reads;
      await tester.pump(const Duration(seconds: 2));
      expect(frames.reads, reads, reason: 'off screen it stays paused');
      expect(frames.openSessions, 0);

      list(tester).jumpTo(0);
      await _settle(tester);
      expect(frames.reads, greaterThan(reads));
      await leave(tester);
    });

    testWidgets('reduced motion: a rebuilt mascot stays still', (tester) async {
      await pump(tester,
          width: 320, height: 640, textScale: 2, disableAnimations: true);
      list(tester).jumpTo(list(tester).maxScrollExtent);
      await _settle(tester);
      expect(heroBuilt, findsNothing);
      list(tester).jumpTo(0);
      await tester.pumpAndSettle();
      expect(heroBuilt, findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      final reads = frames.reads;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(frames.reads, reads, reason: 'no new mascot frames');
      expect(frames.openSessions, 0);
      await leave(tester);
    });

    testWidgets('a route on top stops the mascot; coming back resumes it',
        (tester) async {
      await pump(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(nav.pushNamed('/other'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final reads = frames.reads;
      await tester.pump(const Duration(seconds: 2));
      expect(frames.reads, reads);
      expect(frames.openSessions, 0);

      nav.pop();
      await _settle(tester);
      expect(frames.reads, greaterThan(reads));
      await leave(tester);
    });

    testWidgets('leaving the page leaves no ticker, timer or open clip',
        (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AtomicTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute<void>(builder: (_) => page())),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(find.byType(MascotView), findsWidgets);

      await tester.tap(find.byTooltip('Back'));
      await _settle(tester);
      expect(find.text('open'), findsOneWidget);
      expect(find.byType(MascotView), findsNothing);
      expect(frames.openSessions, 0);
      final reads = frames.reads;
      await tester.pump(const Duration(seconds: 2));
      expect(frames.reads, reads);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.hasRunningAnimations, isFalse);
      // A pending Timer would also fail this test when it ends.
    });
  });

  group('layout', () {
    testWidgets('the header shows the title once the large one scrolls away',
        (tester) async {
      await pump(tester, height: 640);
      AtomicPageHeader header() =>
          tester.widget<AtomicPageHeader>(find.byType(AtomicPageHeader));
      expect(header().showTitle, isFalse);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await _settle(tester);
      expect(header().showTitle, isTrue);
      await leave(tester);
    });

    testWidgets('two cards to a row on a phone at normal text', (tester) async {
      await pump(tester);
      final first = MascotCatalog.all[0], second = MascotCatalog.all[1];
      await scrollTo(tester, _card(second));
      expect(tester.getTopLeft(_card(first)).dy,
          tester.getTopLeft(_card(second)).dy);
      expect(tester.getTopLeft(_card(first)).dx,
          lessThan(tester.getTopLeft(_card(second)).dx));
      expect(tester.getSize(_card(first)).height,
          tester.getSize(_card(second)).height);
      await leave(tester);
    });

    for (final (name, theme) in [
      ('light', AtomicTheme.light),
      ('dark', AtomicTheme.dark),
    ]) {
      for (final direction in TextDirection.values) {
        testWidgets(
            'fits 320 dp at 2.0 text ($name, ${direction.name}) to the end',
            (tester) async {
          await pump(tester,
              theme: theme,
              width: 320,
              height: 640,
              textScale: 2,
              direction: direction);
          expect(tester.takeException(), isNull);
          for (var i = 0; i < 12; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -400));
            await tester.pump();
          }
          await _settle(tester);
          expect(tester.takeException(), isNull);
          final last = MascotCatalog.all.last;
          expect(_card(last).hitTestable(), findsOneWidget);
          expect(
              find.descendant(
                  of: _card(last), matching: find.text(last.displayName)),
              findsOneWidget);
          // One card to a row: every card sits below the one before it,
          // at the same start edge, and spans the list's width.
          final list = tester.getRect(find.byType(ListView));
          final cards = MascotCatalog.all.map(_card).toList();
          for (var i = 1; i < cards.length; i++) {
            final above = tester.getRect(cards[i - 1]);
            final rect = tester.getRect(cards[i]);
            expect(rect.top, greaterThan(above.bottom),
                reason: 'card $i is below card ${i - 1}');
            expect(rect.left, above.left, reason: 'card $i');
            expect(rect.width, greaterThan(list.width / 2),
                reason: 'card $i fills the row');
          }
          await leave(tester);
        });
      }
    }

    testWidgets('targets are at least 48 dp', (tester) async {
      await pump(tester);
      store.failures = 1;
      final lappy = MascotCatalog.findById('073-lappy')!;
      await scrollTo(tester, _card(lappy));
      await tester.tap(_card(lappy));
      await tester.pump();
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pump();
      final targets = <Finder>[
        find.byTooltip('Back'),
        find.byWidget(_hero(tester)),
        find.byKey(const ValueKey('mascot-retry-save')),
        _toggle,
        for (final m in MascotCatalog.all) _card(m),
      ];
      for (final finder in targets) {
        await scrollTo(tester, finder);
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(AtomicSpace.minTarget),
            reason: '$finder');
        expect(size.width, greaterThanOrEqualTo(AtomicSpace.minTarget),
            reason: '$finder');
      }
      await leave(tester);
    });
  });

  testWidgets('without reduced motion the blocks rise in', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(theme: AtomicTheme.light, home: page()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    Iterable<double> fades() => tester
        .widgetList<FadeTransition>(find.ancestor(
            of: find.byKey(const ValueKey('mascot-animate')),
            matching: find.byType(FadeTransition)))
        .map((f) => f.opacity.value);
    expect(fades().any((v) => v < 1), isTrue);
    await _settle(tester);
    expect(fades().every((v) => v == 1), isTrue);
    await leave(tester);
  });
}
