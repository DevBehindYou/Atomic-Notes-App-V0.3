// Settings on lib/ui components (screens spec, Settings): the account card,
// the three "At a glance" tiles, the Notes, Privacy and security, Appearance
// and About groups, Log out with its confirmation and live progress, and
// Danger Zone. Every row must still open its route; the summaries come from
// injected state; the theme picker shows only while the AppearanceController
// allows switching; logout keeps its confirmation text, calls the injected
// operation exactly once and blocks touches, Back and row actions while it
// runs. Plus the layout checks every redesigned page passes: 320 dp at 2.0
// text in light and dark, LTR and RTL, 48 dp targets, spoken labels and
// reduced motion. Synthetic data only; no Hive, network or real account.

import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/appearance/appearance_controller.dart';
import 'package:atomic_notes/appearance/appearance_preferences.dart';
import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart' show LogoutBlocked;
import 'package:atomic_notes/page/settings_page.dart';
import 'package:atomic_notes/profile/profile_source.dart';
import 'package:atomic_notes/profile/profile_store.dart' show Avatars;
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/controls/segmented.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/ui/rows/settings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_energy_store.dart';
import 'support/fake_notes_source.dart';

class _Api implements ApiClient {
  _Api(this.email);

  final String? email;

  @override
  String? get currentUserEmail => email;

  @override
  int get sessionRevision => 7;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profile extends ChangeNotifier implements ProfileSource {
  @override
  String get avatarAsset => Avatars.defaultAsset;

  @override
  bool get publicProfile => true;

  @override
  Future<void> setAvatar(String? asset) async {}

  @override
  Future<void> setPublicProfile(bool value) async {}
}

class _Pushes extends NavigatorObserver {
  final List<String> names = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null && name != '/') names.add(name);
  }
}

const _routes = [
  '/editprofilepage',
  '/energypage',
  '/cloudsyncpage',
  '/encryptionpage',
  '/recyclebin',
  '/biompage',
  '/twofactor',
  '/usersessions',
  '/mascot',
  '/appinfo',
  '/tcpage',
  '/dangerzone',
];

/// Everything the page reads, synthetic and adjustable per test.
class _Rig {
  _Rig({
    int deleted = 0,
    int dirty = 0,
    this.syncOn = true,
    this.encryption = false,
    this.email = 'reader@example.test',
    this.appearance,
  }) : notes = FakeNotesSource(notes: [
          for (var i = 0; i < deleted; i++)
            Note(id: 'bin-$i', title: 'Binned $i', deleted: true),
          for (var i = 0; i < dirty; i++)
            Note(id: 'dirty-$i', title: 'Edited $i', dirty: true),
        ]);

  final FakeNotesSource notes;
  final FakeEnergyStore energy = FakeEnergyStore(
      wallet: const Wallet(
          coins: 3, energy: 110, energyCap: 120, lastDailyGrantAt: null));
  bool? syncOn;
  bool encryption;
  final String? email;
  final AppearanceController? appearance;
  final _Pushes pushes = _Pushes();

  int logoutCalls = 0;
  int finished = 0;
  Completer<void>? logoutGate;
  Object? logoutError;
  final List<String> progress = [
    'Emergency InstaSync for logout — no Energy used…'
  ];

  Future<void> logout({
    required Future<void> Function(void Function() checkCurrent) finishLocal,
    void Function(String message)? onProgress,
  }) async {
    logoutCalls++;
    for (final p in progress) {
      onProgress?.call(p);
    }
    await logoutGate?.future;
    final error = logoutError;
    if (error != null) throw error;
    await finishLocal(() {});
  }

  SettingsPage page() => SettingsPage(
        api: _Api(email),
        energy: energy,
        isSyncOn: () {
          final on = syncOn;
          if (on == null) throw StateError('sync box not open');
          return on;
        },
        isEncryptionOn: () => encryption,
        handle: () => '@reader',
        appearance: appearance,
        logoutOperation: logout,
        finishLogout: (check) async {
          check();
          finished++;
        },
      );
}

void _view(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_Rig> _pump(
  WidgetTester tester, {
  _Rig? rig,
  double width = 412,
  double height = 915,
  double textScale = 1,
  ThemeData? theme,
  TextDirection direction = TextDirection.ltr,
  bool reduced = false,
  bool settle = true,
  AppearanceController? scope,
}) async {
  final r = rig ?? _Rig();
  _view(tester, width, height);
  final bloc = NotesBloc(
      source: r.notes, isSyncEnabled: () => true, isOnline: () async => true);
  final profile = ProfileCubit(store: _Profile());
  addTearDown(() async {
    await bloc.close();
    await profile.close();
    r.notes.dispose();
    r.energy.dispose();
  });
  Widget app = MaterialApp(
    theme: theme ?? AtomicTheme.light,
    navigatorObservers: [r.pushes],
    routes: {
      for (final name in _routes)
        name: (_) => Scaffold(body: Center(child: Text('route $name'))),
    },
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduced,
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: const Scaffold(body: Center(child: Text('root'))),
  );
  if (scope != null) app = AppearanceScope(controller: scope, child: app);
  await tester.pumpWidget(MultiBlocProvider(
    providers: [
      BlocProvider<NotesBloc>.value(value: bloc),
      BlocProvider<ProfileCubit>.value(value: profile),
    ],
    child: app,
  ));
  _navigator(tester).push(MaterialPageRoute<void>(builder: (_) => r.page()));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return r;
}

NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

Finder get _list => find
    .descendant(
        of: find.byKey(const ValueKey('settings-list')),
        matching: find.byType(Scrollable))
    .first;

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: _list);
  await tester.pumpAndSettle();
}

Future<void> _revealUp(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, -300, scrollable: _list);
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));

String _tileValue(WidgetTester tester, String key) {
  final texts = tester
      .widgetList<Text>(
          find.descendant(of: _key(key), matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  return texts.first!;
}

/// Scrolls from the top to the bottom, failing on any layout exception.
Future<void> _scrollThrough(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  for (var i = 0; i < 60; i++) {
    final position = tester.state<ScrollableState>(_list).position;
    if (position.pixels >= position.maxScrollExtent) break;
    await tester.drag(_list, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
  expect(find.byKey(const ValueKey('settings-dangerzone')), findsOneWidget);
}

/// Frames for a page with a spinning progress ring, which never settles.
Future<void> _busy(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

AtomicColors _colors(ThemeData theme) => theme.extension<AtomicColors>()!;

void main() {
  group('structure', () {
    testWidgets('groups follow the approved order under one large title',
        (tester) async {
      await _pump(tester);
      expect(find.byType(PageTitle), findsOneWidget);
      expect(find.text('Settings'), findsNWidgets(2)); // large + collapsed
      final labels = <String>[];
      final order = [
        'At a glance',
        'Notes',
        'Privacy and security',
        'Appearance',
        'About',
      ];
      for (final label in order) {
        await _reveal(tester, find.text(label));
        labels.add(label);
      }
      expect(labels, order);
      await _reveal(tester, _key('settings-dangerzone'));
      final logout = tester.getTopLeft(_key('settings-logout-card')).dy;
      final danger = tester.getTopLeft(_key('settings-dangerzone')).dy;
      final about = tester.getTopLeft(_key('settings-terms')).dy;
      expect(about < logout && logout < danger, isTrue);
      // The old colophon and logo block are gone.
      expect(find.text('Local-first notes'), findsNothing);
      expect(find.text('ABOUT ATOMIC'), findsNothing);
    });

    testWidgets(
        'the collapsed header title appears once the title scrolls away',
        (tester) async {
      await _pump(tester);
      bool shown() => tester
          .widget<AtomicPageHeader>(find.byType(AtomicPageHeader))
          .showTitle;
      expect(shown(), isFalse);
      await tester.drag(_list, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(shown(), isTrue);
    });

    testWidgets('every row and tile opens its route, and Back returns',
        (tester) async {
      final rig = await _pump(tester);
      final targets = {
        'settings-account': '/editprofilepage',
        'glance-energy': '/energypage',
        'glance-sync': '/cloudsyncpage',
        'glance-encryption': '/encryptionpage',
        'settings-cloudsync': '/cloudsyncpage',
        'settings-recyclebin': '/recyclebin',
        'settings-security': '/biompage',
        'settings-encryption': '/encryptionpage',
        'settings-twofactor': '/twofactor',
        'settings-signins': '/usersessions',
        'settings-mascot': '/mascot',
        'settings-appinfo': '/appinfo',
        'settings-terms': '/tcpage',
        'settings-dangerzone': '/dangerzone',
      };
      for (final MapEntry(:key, :value) in targets.entries) {
        await _reveal(tester, _key(key));
        await tester.tap(_key(key));
        await tester.pumpAndSettle();
        expect(rig.pushes.names.last, value, reason: key);
        expect(find.text('route $value'), findsOneWidget, reason: key);
        _navigator(tester).pop();
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);
      }
      expect(rig.pushes.names, targets.values.toList());
    });
  });

  group('account card and summaries', () {
    testWidgets('the account card shows the handle and email and reads both',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      expect(find.text('@reader'), findsOneWidget);
      expect(find.text('reader@example.test'), findsOneWidget);
      expect(find.bySemanticsLabel('Profile. @reader. reader@example.test'),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets('without an email the card shows only the handle',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, rig: _Rig(email: null));
      expect(find.text('@reader'), findsOneWidget);
      expect(find.bySemanticsLabel('Profile. @reader'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('tiles show energy, sync and encryption from state',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final rig = await _pump(tester, rig: _Rig(dirty: 2, encryption: true));
      expect(_tileValue(tester, 'glance-energy'), '110 / 120');
      expect(_tileValue(tester, 'glance-sync'), 'On · 2 waiting');
      expect(_tileValue(tester, 'glance-encryption'), 'On');
      expect(find.bySemanticsLabel('Energy. 110 of 120'), findsOneWidget);
      expect(find.bySemanticsLabel('Sync. On. 2 note changes waiting to sync'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Encryption. On'), findsOneWidget);
      // A new balance redraws the tile.
      rig.energy.wallet = const Wallet(
          coins: 3, energy: 40, energyCap: 120, lastDailyGrantAt: null);
      rig.energy.notifyListeners();
      await tester.pump();
      expect(_tileValue(tester, 'glance-energy'), '40 / 120');
      semantics.dispose();
    });

    testWidgets('unknown or off states are stated, never guessed',
        (tester) async {
      final rig = _Rig(syncOn: null);
      rig.energy.hasLoaded = false;
      await _pump(tester, rig: rig);
      expect(_tileValue(tester, 'glance-energy'), 'Not loaded');
      expect(_tileValue(tester, 'glance-sync'), 'Unknown');
      expect(_tileValue(tester, 'glance-encryption'), 'Off');
    });

    testWidgets('sync off reads Off, and one waiting change is singular',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, rig: _Rig(syncOn: false, dirty: 1));
      expect(_tileValue(tester, 'glance-sync'), 'Off · 1 waiting');
      expect(find.bySemanticsLabel('Sync. Off. 1 note change waiting to sync'),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets('summaries are read again on return from a page',
        (tester) async {
      final rig = await _pump(tester);
      expect(_tileValue(tester, 'glance-encryption'), 'Off');
      await tester.tap(_key('glance-encryption'));
      await tester.pumpAndSettle();
      rig.encryption = true;
      rig.syncOn = false;
      _navigator(tester).pop();
      await tester.pumpAndSettle();
      expect(_tileValue(tester, 'glance-encryption'), 'On');
      expect(_tileValue(tester, 'glance-sync'), 'Off');
    });

    testWidgets('Recycle Bin shows a count bubble, or Empty', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, rig: _Rig(deleted: 3));
      await _reveal(tester, _key('settings-recyclebin'));
      final row = tester.widget<SettingsRow>(_key('settings-recyclebin'));
      expect(row.count, 3);
      expect(row.caption, isNull);
      expect(find.bySemanticsLabel('Recycle Bin. 3 deleted notes'),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets('an empty Recycle Bin says Empty with no bubble',
        (tester) async {
      await _pump(tester);
      await _reveal(tester, _key('settings-recyclebin'));
      final row = tester.widget<SettingsRow>(_key('settings-recyclebin'));
      expect(row.count, isNull);
      expect(row.caption, 'Empty');
    });
  });

  group('theme', () {
    testWidgets('hidden without a controller', (tester) async {
      await _pump(tester);
      await _reveal(tester, find.text('Appearance'));
      expect(_key('settings-theme'), findsNothing);
      expect(_key('settings-mascot'), findsOneWidget);
    });

    testWidgets('hidden while the controller does not allow switching',
        (tester) async {
      await _pump(tester,
          scope: AppearanceController(store: MemoryAppearanceStore()));
      await _reveal(tester, _key('settings-mascot'));
      expect(_key('settings-theme'), findsNothing);
    });

    testWidgets('the app scope shows the picker, and a choice is kept',
        (tester) async {
      final store = MemoryAppearanceStore();
      final controller =
          AppearanceController(store: store, themeSwitchingEnabled: true);
      addTearDown(controller.dispose);
      await _pump(tester, scope: controller);
      await _reveal(tester, _key('settings-theme-segmented'));
      expect(
          tester
              .widget<Segmented<AppearanceMode>>(
                  _key('settings-theme-segmented'))
              .value,
          AppearanceMode.system);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(controller.value, AppearanceMode.dark);
      expect(store.value, AppearanceMode.dark);
      expect(store.writes, 1);
      expect(
          tester
              .widget<Segmented<AppearanceMode>>(
                  _key('settings-theme-segmented'))
              .value,
          AppearanceMode.dark);
      expect(find.textContaining("Couldn't save your theme"), findsNothing);
    });

    testWidgets('a choice that cannot be kept still applies and says so',
        (tester) async {
      final store = MemoryAppearanceStore()..failWrites = true;
      final controller =
          AppearanceController(store: store, themeSwitchingEnabled: true);
      addTearDown(controller.dispose);
      await _pump(tester, rig: _Rig(appearance: controller));
      await _reveal(tester, _key('settings-theme-segmented'));
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(controller.value, AppearanceMode.light);
      expect(
          find.text(
              "Couldn't save your theme. It applies until you close the app."),
          findsOneWidget);
    });

    for (final direction in TextDirection.values) {
      testWidgets('the highlight sits on the chosen segment, ${direction.name}',
          (tester) async {
        final controller = AppearanceController(
            store: MemoryAppearanceStore(AppearanceMode.system),
            themeSwitchingEnabled: true);
        addTearDown(controller.dispose);
        await _pump(tester,
            rig: _Rig(appearance: controller), direction: direction);
        await _reveal(tester, _key('settings-theme-segmented'));
        final system = tester.getCenter(find.text('System')).dx;
        final dark = tester.getCenter(find.text('Dark')).dx;
        // RTL mirrors the order: System starts on the right.
        expect(system < dark, direction == TextDirection.ltr);
        final c = _colors(AtomicTheme.light);
        final highlight = find.descendant(
            of: _key('settings-theme-segmented'),
            matching: find.byWidgetPredicate((w) =>
                w is DecoratedBox &&
                (w.decoration as BoxDecoration).color == c.inverseSurface));
        expect(highlight, findsOneWidget);
        expect(
            tester
                .getRect(highlight)
                .contains(tester.getCenter(find.text('System'))),
            isTrue);
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        expect(
            tester
                .getRect(highlight)
                .contains(tester.getCenter(find.text('Dark'))),
            isTrue);
      });
    }

    testWidgets('at 320 dp and 2.0 text the choices stack and still choose',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final store = MemoryAppearanceStore();
      final controller =
          AppearanceController(store: store, themeSwitchingEnabled: true);
      addTearDown(controller.dispose);
      await _pump(tester,
          rig: _Rig(appearance: controller),
          width: 320,
          height: 640,
          textScale: 2);
      await _reveal(tester, _key('settings-theme-stacked'));
      expect(_key('settings-theme-segmented'), findsNothing);
      // "System" keeps one line inside the screen.
      final paragraph =
          tester.renderObject<RenderParagraph>(find.text('System'));
      expect(paragraph.size.height, lessThan(13 * 2 * 1.25 * 1.5));
      final rect = tester.getRect(find.text('System'));
      expect(rect.left >= 0 && rect.right <= 320, isTrue);
      expect(
          tester.getSemantics(_key('settings-theme-System')),
          isSemantics(
              label: 'System',
              isButton: true,
              isSelected: true,
              hasTapAction: true));
      await tester.tap(_key('settings-theme-Dark'));
      await tester.pumpAndSettle();
      expect(controller.value, AppearanceMode.dark);
      expect(store.value, AppearanceMode.dark);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  });

  group('logout', () {
    Future<void> openConfirmation(WidgetTester tester) async {
      await _reveal(tester, _key('settings-logout'));
      await tester.tap(_key('settings-logout'));
      await tester.pumpAndSettle();
    }

    testWidgets('keeps today\'s confirmation text, and Cancel does nothing',
        (tester) async {
      final rig = await _pump(tester);
      await openConfirmation(tester);
      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
      expect(find.text('Log out?'), findsOneWidget);
      expect(
          find.text(
              'Atomic will sync unsent changes before logging out. Instant Sync uses Energy; if you cannot cover it, Emergency InstaSync for this logout uses no Energy. If sync fails, you stay signed in and your notes are kept.'),
          findsOneWidget);
      // Only the buttons close it.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
      await tester.tap(find.widgetWithText(AtomicButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(rig.logoutCalls, 0);
      expect(rig.finished, 0);
    });

    testWidgets('a second tap while confirming opens no second dialog',
        (tester) async {
      await _pump(tester);
      await _reveal(tester, _key('settings-logout'));
      final row = tester.widget<SettingsRow>(_key('settings-logout'));
      row.onTap!();
      row.onTap!();
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
    });

    testWidgets(
        'confirming runs logout once with live progress and blocks Back, '
        'touches and row actions until it ends', (tester) async {
      final semantics = tester.ensureSemantics();
      final rig = _Rig()..logoutGate = Completer<void>();
      await _pump(tester, rig: rig);
      await openConfirmation(tester);
      await tester.tap(find.widgetWithText(AtomicButton, 'Log out'));
      await _busy(tester);
      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(rig.logoutCalls, 1);
      expect(find.text('Emergency InstaSync for logout — no Energy used…'),
          findsOneWidget);
      expect(
          tester
              .getSemantics(
                  find.text('Emergency InstaSync for logout — no Energy used…'))
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue);
      expect(find.text('Signing out…'), findsOneWidget);
      expect(
          tester.widget<PopScope>(find.byType(PopScope).first).canPop, isFalse);
      expect(
          tester
              .widgetList<AbsorbPointer>(find.descendant(
                  of: find.byType(SettingsPage),
                  matching: find.byType(AbsorbPointer)))
              .any((a) => a.absorbing),
          isTrue);
      expect(tester.widget<SettingsRow>(_key('settings-logout')).onTap, isNull);
      // Back from the header and from the system both stay on Settings.
      await tester.binding.handlePopRoute();
      await _busy(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
      // A screen reader's tap goes around AbsorbPointer; the row ignores it.
      await tester.scrollUntilVisible(_key('settings-dangerzone'), 200,
          scrollable: _list);
      await _busy(tester);
      tester.widget<SettingsRow>(_key('settings-dangerzone')).onTap!();
      await _busy(tester);
      expect(rig.pushes.names, isEmpty);
      expect(rig.finished, 0);

      rig.logoutGate!.complete();
      await tester.pumpAndSettle();
      expect(rig.finished, 1);
      expect(rig.logoutCalls, 1);
      expect(
          tester.widget<PopScope>(find.byType(PopScope).first).canPop, isTrue);
      expect(find.text('Signing out…'), findsNothing);
      semantics.dispose();
    });

    testWidgets('a blocked logout explains why and keeps Settings usable',
        (tester) async {
      final rig = _Rig()
        ..logoutError =
            const LogoutBlocked('Sync could not finish. Try again.');
      await _pump(tester, rig: rig);
      await openConfirmation(tester);
      await tester.tap(find.widgetWithText(AtomicButton, 'Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Sync could not finish. Try again.'), findsOneWidget);
      expect(rig.finished, 0);
      expect(
          tester.widget<SettingsRow>(_key('settings-logout')).onTap, isNotNull);
    });

    testWidgets('any other failure keeps the unsynced-notes message',
        (tester) async {
      final rig = _Rig()..logoutError = StateError('synthetic');
      await _pump(tester, rig: rig);
      await openConfirmation(tester);
      await tester.tap(find.widgetWithText(AtomicButton, 'Log out'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Logout could not finish. Your unsynced notes remain on this device.'),
          findsOneWidget);
      expect(rig.finished, 0);
    });
  });

  group('layout and accessibility', () {
    for (final theme in ['light', 'dark']) {
      for (final direction in TextDirection.values) {
        testWidgets('320 dp at 2.0 text, $theme, ${direction.name}',
            (tester) async {
          final controller = AppearanceController(
              store: MemoryAppearanceStore(), themeSwitchingEnabled: true);
          addTearDown(controller.dispose);
          final data = theme == 'light' ? AtomicTheme.light : AtomicTheme.dark;
          await _pump(tester,
              rig: _Rig(dirty: 2, deleted: 3, appearance: controller),
              width: 320,
              height: 640,
              textScale: 2,
              theme: data,
              direction: direction);
          // The tiles stack at large text.
          final energy = tester.getRect(_key('glance-energy'));
          await _reveal(tester, _key('glance-encryption'));
          expect(tester.getRect(_key('glance-sync')).left,
              moreOrLessEquals(tester.getRect(_key('glance-energy')).left));
          expect(energy.width, greaterThan(250));
          await _reveal(tester, _key('settings-theme-stacked'));
          final system = tester.getRect(find.text('System'));
          expect(system.left >= 0 && system.right <= 320, isTrue);
          await _scrollThrough(tester);
          final rect = tester.getRect(find.text('Danger Zone'));
          expect(rect.left >= 0 && rect.right <= 320, isTrue);
        });
      }
    }

    testWidgets('normal text keeps three tiles in one row of equal height',
        (tester) async {
      await _pump(tester, width: 320, height: 640);
      final a = tester.getRect(_key('glance-energy'));
      final b = tester.getRect(_key('glance-sync'));
      final c = tester.getRect(_key('glance-encryption'));
      expect(a.top, b.top);
      expect(b.top, c.top);
      expect(a.height, b.height);
      expect(b.height, c.height);
      expect(tester.takeException(), isNull);
    });

    for (final name in ['light', 'dark']) {
      testWidgets('$name roles pair surfaces with their foregrounds',
          (tester) async {
        final theme = name == 'light' ? AtomicTheme.light : AtomicTheme.dark;
        final c = _colors(theme);
        await _pump(tester, theme: theme);
        final scaffold = tester.widget<Scaffold>(find
            .ancestor(
                of: find.byType(PageTitle), matching: find.byType(Scaffold))
            .first);
        expect(scaffold.backgroundColor, c.canvas);
        final title = tester.widget<Text>(find.descendant(
            of: find.byType(PageTitle), matching: find.byType(Text)));
        expect(title.style!.color, c.textPrimary);
        final energyCard = tester.widget<AtomicCard>(find.descendant(
            of: _key('glance-energy'), matching: find.byType(AtomicCard)));
        expect(energyCard.color, c.accent);
        final energyText = tester.widget<Text>(find.text('110 / 120'));
        expect(energyText.style!.color, c.onAccent);
        final syncCard = tester.widget<AtomicCard>(find.descendant(
            of: _key('glance-sync'), matching: find.byType(AtomicCard)));
        expect(syncCard.color, isNull); // surface
        expect(
            tester.widget<Text>(find.text('On')).style!.color, c.textPrimary);
        await _reveal(tester, _key('settings-logout-card'));
        final border = (tester
                .widget<DecoratedBox>(_key('settings-logout-card'))
                .decoration as BoxDecoration)
            .border as Border;
        expect(border.top.color, c.danger);
        final dangerTile = tester.widget<Icon>(find
            .descendant(
                of: _key('settings-dangerzone'), matching: find.byType(Icon))
            .first);
        expect(dangerTile.color, c.onDanger);
      });
    }

    testWidgets('every target is at least 48 dp and labelled', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = AppearanceController(
          store: MemoryAppearanceStore(), themeSwitchingEnabled: true);
      addTearDown(controller.dispose);
      await _pump(tester,
          rig: _Rig(appearance: controller), width: 320, height: 640);
      for (var i = 0; i < 12; i++) {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        final position = tester.state<ScrollableState>(_list).position;
        if (position.pixels >= position.maxScrollExtent) break;
        await tester.drag(_list, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      semantics.dispose();
    });

    testWidgets('rows read title, caption and value as one button',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      for (final label in [
        'Cloud sync. Sync with your Google Drive',
        'Recycle Bin. Empty',
        'Security. App lock, screenshots',
        'Encryption. Optional protection before upload',
        'Two-factor. A code to open the app on this device',
        'Sign-ins. Review other sign-ins',
        'Mascot. Choose a character and motion',
        'Terms. Terms and conditions',
        'Log out',
        'Danger Zone. Remove cloud or device notes',
      ]) {
        await _reveal(tester, find.bySemanticsLabel(label));
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      await _revealUp(tester, find.bySemanticsLabel('Energy. 110 of 120'));
      expect(find.bySemanticsLabel('Energy. 110 of 120'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('reduced motion shows every block at once', (tester) async {
      await _pump(tester, reduced: true, settle: false);
      await tester.pump();
      final fades = tester.widgetList<FadeTransition>(find.descendant(
          of: find.byType(Entrance), matching: find.byType(FadeTransition)));
      expect(fades, isNotEmpty);
      expect(fades.every((f) => f.opacity.value == 1), isTrue);
    });

    testWidgets('full motion keeps the entrance', (tester) async {
      await _pump(tester, settle: false);
      // Let the page route finish, then catch the entrance mid-way.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 60));
      final fades = tester.widgetList<FadeTransition>(find.descendant(
          of: find.byType(Entrance), matching: find.byType(FadeTransition)));
      expect(fades.any((f) => f.opacity.value < 1), isTrue);
      await tester.pumpAndSettle();
      final settled = tester.widgetList<FadeTransition>(find.descendant(
          of: find.byType(Entrance), matching: find.byType(FadeTransition)));
      expect(settled.every((f) => f.opacity.value == 1), isTrue);
    });
  });
}
