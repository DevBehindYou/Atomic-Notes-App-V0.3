// The signed-in shell after UX-03 (screens spec, Shell and Home 1): Home is
// the only child, with no app bar, tab stack or bottom bar; Settings is a
// pushed route from the avatar in the Home header. The shell keeps Back twice
// to exit, the one-time Energy intro, the profile refresh, the handle refresh
// and the sync notices. Fakes only: no Hive, network or account data.

import 'dart:async';

import 'package:atomic_notes/database/notification_models.dart';
import 'package:atomic_notes/database/notifications_source.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/page/main_page.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/profile/profile_store.dart';
import 'package:atomic_notes/profile/profile_source.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/state/notifications/notifications_cubit.dart';
import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

AppNotification _n(String id, {bool read = false}) => AppNotification(
      id: id,
      type: 'general',
      subject: 'Subject $id',
      description: 'Body $id',
      priority: 'normal',
      status: 'active',
      action: null,
      actionUrl: null,
      icon: null,
      createdAt: DateTime(2026, 9, 27, 18, 3),
      expiresAt: null,
      isRead: read,
      dismissedAt: null,
      dismissible: true,
    );

class _Feed extends ChangeNotifier implements NotificationsSource {
  _Feed(this.items);

  @override
  List<AppNotification> items;
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
  @override
  Future<void> dismiss(String id) async {}
}

class _Profile extends ChangeNotifier implements ProfileSource {
  int reads = 0;

  @override
  String get avatarAsset {
    reads++;
    return Avatars.defaultAsset;
  }

  @override
  bool get publicProfile => true;
  @override
  Future<void> setAvatar(String? asset) async {}
  @override
  Future<void> setPublicProfile(bool value) async {}
}

class _Events extends BlocObserver {
  final List<Object?> seen = [];
  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    seen.add(event);
    super.onEvent(bloc, event);
  }
}

class _Routes extends NavigatorObserver {
  final List<String?> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route.settings.name);
}

class _Shell {
  _Shell(this.notes, this.bloc, this.profile, this.routes, this.events);
  final FakeNotesSource notes;
  final NotesBloc bloc;
  final _Profile profile;
  final _Routes routes;
  final _Events events;
  int handleRefreshes = 0;
}

Future<_Shell> _pump(
  WidgetTester tester, {
  Size size = const Size(400, 860),
  double textScale = 1,
  ThemeData? theme,
  bool introSeen = true,
  int unread = 0,
  List<String> pendingIds = const [],
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final events = _Events();
  final previousObserver = Bloc.observer;
  Bloc.observer = events;
  addTearDown(() => Bloc.observer = previousObserver);

  final notes = FakeNotesSource(notes: [
    syncedNote('a', title: 'Ideas', body: 'Build a rocket'),
    syncedNote('b', title: 'Trip'),
  ]);
  for (final note in notes.all) {
    if (pendingIds.contains(note.id)) note.dirty = true;
  }
  final bloc = NotesBloc(
    source: notes,
    isSyncEnabled: () => true,
    isOnline: () async => true,
  );
  final feed = _Feed([for (var i = 0; i < unread; i++) _n('n$i')]);
  final notifications = NotificationsCubit(source: feed);
  final profileSource = _Profile();
  final profile = ProfileCubit(store: profileSource);
  final routes = _Routes();
  final shell = _Shell(notes, bloc, profileSource, routes, events);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await bloc.close();
    await notifications.close();
    await profile.close();
    notes.dispose();
    feed.dispose();
  });

  Widget stub(String name) => Scaffold(body: Center(child: Text('stub $name')));

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<NotesBloc>.value(value: bloc),
        BlocProvider<NotificationsCubit>.value(value: notifications),
        BlocProvider<ProfileCubit>.value(value: profile),
      ],
      child: MaterialApp(
        theme: theme ?? AtomicTheme.light,
        navigatorObservers: [routes],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
          child: child!,
        ),
        routes: {
          '/': (_) => MainPage(
                refreshHandle: () async => shell.handleRefreshes++,
                energyIntroSeen: () => introSeen,
              ),
          '/settingspage': (_) => stub('settings'),
          '/notifications': (_) => stub('notifications'),
          '/energyintro': (_) => stub('energy intro'),
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return shell;
}

Finder _semantics(String label) => find.bySemanticsLabel(label);

void main() {
  group('shell', () {
    testWidgets('Home is the only child: no app bar, tabs or bottom bar',
        (tester) async {
      await _pump(tester);
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(IndexedStack), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.text('SETTINGS'), findsNothing);
      expect(find.byKey(const ValueKey('home-title')), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('entry refreshes the profile and the cached handle once',
        (tester) async {
      final shell = await _pump(tester);
      expect(shell.handleRefreshes, 1);
      // ProfileCubit reads the store when built and again on refresh().
      expect(shell.profile.reads, greaterThanOrEqualTo(2));
      expect(shell.routes.pushed.where((r) => r == '/energyintro'), isEmpty);
    });

    testWidgets('the Energy intro is pushed once when it was never seen',
        (tester) async {
      final shell = await _pump(tester, introSeen: false);
      await tester.pumpAndSettle();
      expect(
          shell.routes.pushed.where((r) => r == '/energyintro'), hasLength(1));
      expect(find.text('stub energy intro'), findsOneWidget);
      // Back from the intro returns to Home, not out of the app.
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(
          shell.routes.pushed.where((r) => r == '/energyintro'), hasLength(1));
    });

    testWidgets('Back once shows the hint; twice within 2 s exits',
        (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(calls, isNot(contains('SystemNavigator.pop')));
      expect(find.byType(HomePage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls, contains('SystemNavigator.pop'));
    });

    testWidgets('Back after the 2 s window only shows the hint again',
        (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2100)));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls, isNot(contains('SystemNavigator.pop')));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('Home header actions', () {
    testWidgets('the avatar opens Settings as a pushed route and Back returns',
        (tester) async {
      final shell = await _pump(tester);
      final avatar = _semantics('Settings and profile');
      expect(avatar, findsOneWidget);
      expect(tester.getSize(avatar).width, greaterThanOrEqualTo(48));
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(shell.routes.pushed.last, '/settingspage');
      expect(find.text('stub settings'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('stub settings'), findsNothing);
    });

    testWidgets(
        'the bell shows the unread count, 9+ above nine, and opens '
        'the Notification Center', (tester) async {
      final shell = await _pump(tester, unread: 3);
      expect(_semantics('Notifications, 3 unread'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(shell.routes.pushed.last, '/notifications');
    });

    testWidgets('a bell with more than nine unread shows 9+', (tester) async {
      await _pump(tester, unread: 12);
      expect(find.text('9+'), findsOneWidget);
      expect(_semantics('Notifications, 12 unread'), findsOneWidget);
    });

    testWidgets('no unread: plain label, no badge', (tester) async {
      await _pump(tester);
      expect(_semantics('Notifications'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets(
        'sync: a tap asks for an instant sync, the ring shows while '
        'it runs, and a second tap mid-sync does nothing', (tester) async {
      final shell = await _pump(tester);
      final gate = Completer<void>();
      shell.notes.syncGate = gate;
      expect(find.byIcon(AtomicIcons.cloudCheck), findsOneWidget);

      await tester.tap(find.byTooltip('Sync now'));
      await tester.pump();
      await tester.pump();
      final requests =
          shell.events.seen.whereType<NotesSyncRequested>().toList();
      expect(requests, hasLength(1));
      expect(requests.single.instant, isTrue);
      expect(find.byKey(const ValueKey('home-sync-ring')), findsOneWidget);
      expect(_semantics('Sync now, syncing'), findsOneWidget);

      await tester.tap(find.byTooltip('Sync now'), warnIfMissed: false);
      await tester.pump();
      expect(shell.events.seen.whereType<NotesSyncRequested>(), hasLength(1));

      gate.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('home-sync-ring')), findsNothing);
      expect(shell.notes.syncCalls, 1);
      // The shell's listener shows the answer to the sync.
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('changes waiting to sync: upload icon, dot and a counted label',
        (tester) async {
      await _pump(tester, pendingIds: const ['a', 'b']);
      expect(find.byIcon(AtomicIcons.cloudUpload), findsOneWidget);
      expect(_semantics('Sync now, 2 changes waiting'), findsOneWidget);
    });

    testWidgets('sync keeps its long press for the Energy popup',
        (tester) async {
      await _pump(tester);
      final node = tester.getSemantics(find.bySemanticsLabel('Sync now'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.longPress),
        isTrue,
      );
    });
  });

  group('header layout', () {
    for (final theme
        in {'light': AtomicTheme.light, 'dark': AtomicTheme.dark}.entries) {
      // The test font draws every glyph as a square, so "Notes" measures
      // twice its real width here; 480 dp leaves room for it either way.
      testWidgets(
          '${theme.key}: a wide screen keeps title and actions on one '
          'row', (tester) async {
        await _pump(tester, theme: theme.value, size: const Size(480, 860));
        expect(find.byKey(const ValueKey('home-top-bar')), findsOneWidget);
        final title = tester.getRect(find.byKey(const ValueKey('home-title')));
        final avatar = tester.getRect(_semantics('Settings and profile'));
        expect((title.center.dy - avatar.center.dy).abs(), lessThan(24));
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          '${theme.key}: 320 dp at 2.0 text puts the title on its own '
          'line and nothing overflows', (tester) async {
        await _pump(tester,
            theme: theme.value, size: const Size(320, 700), textScale: 2);
        expect(tester.takeException(), isNull);
        expect(
            find.byKey(const ValueKey('home-top-bar-stacked')), findsOneWidget);
        final title = tester.getRect(find.byKey(const ValueKey('home-title')));
        final avatar = tester.getRect(_semantics('Settings and profile'));
        expect(avatar.top, greaterThanOrEqualTo(title.bottom - 1));
        expect(title.right, lessThanOrEqualTo(320));
        expect(avatar.right, lessThanOrEqualTo(320));
        expect(_semantics('Sync now'), findsOneWidget);
        expect(_semantics('Notifications'), findsOneWidget);
      });
    }

    testWidgets('320 dp at normal text also stacks (spec: below 360 dp)',
        (tester) async {
      await _pump(tester, size: const Size(320, 700));
      expect(
          find.byKey(const ValueKey('home-top-bar-stacked')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the title is a heading for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      final data = tester
          .getSemantics(find.byKey(const ValueKey('home-title')))
          .getSemanticsData();
      expect(data.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });

    testWidgets(
        'a page under 544 dp scrolls its header with the notes, as a '
        '480 dp page under the old app bar did', (tester) async {
      await _pump(tester, size: const Size(800, 520));
      expect(find.byType(NestedScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a page of 544 dp or more keeps the header fixed',
        (tester) async {
      await _pump(tester, size: const Size(800, 600));
      expect(find.byType(NestedScrollView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the header clears the status bar', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 24 * 3);
      addTearDown(tester.view.resetPadding);
      await _pump(tester);
      expect(
        tester.getRect(find.byKey(const ValueKey('home-title'))).top,
        greaterThanOrEqualTo(24),
      );
    });
  });

  group('returning to Home', () {
    testWidgets('opening a note and coming back stays inside the shell',
        (tester) async {
      await _pump(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IDEAS'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsOneWidget);
      await tester.tap(find.byTooltip('Back to notes'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      // The editor's Back is the editor's: the shell's exit hint never shows.
      expect(find.text('Press back again to exit'), findsNothing);
      expect(find.byKey(const ValueKey('home-title')), findsOneWidget);
    });

    testWidgets('a search survives a visit to Settings', (tester) async {
      await _pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'rocket');
      await tester.pump();
      await tester.pump();
      expect(find.text('IDEAS'), findsOneWidget);
      expect(find.text('TRIP'), findsNothing);
      await tester.tap(_semantics('Settings and profile'));
      await tester.pumpAndSettle();
      expect(find.text('stub settings'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'rocket');
      expect(find.text('IDEAS'), findsOneWidget);
      expect(find.text('TRIP'), findsNothing);
    });

    testWidgets('opening the keyboard keeps the header and the search focus',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      expect(editor.widget.focusNode.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump();
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(editor));
      expect(editor.widget.focusNode.hasFocus, isTrue);
      expect(find.byKey(const ValueKey('home-title')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'selection mode keeps the header actions and the current '
        'selection row', (tester) async {
      await _pump(tester);
      await tester.longPress(find.text('IDEAS'));
      await tester.pumpAndSettle();
      expect(find.text('1 SELECTED'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-title')), findsOneWidget);
      expect(_semantics('Settings and profile'), findsOneWidget);
      expect(_semantics('Sync now'), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(find.text('1 SELECTED'), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets(
        'reduced motion: the header works and the sync ring still '
        'reports progress', (tester) async {
      final shell = await _pump(tester, disableAnimations: true);
      final gate = Completer<void>();
      shell.notes.syncGate = gate;
      await tester.tap(find.byTooltip('Sync now'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('home-sync-ring')), findsOneWidget);
      expect(_semantics('Sync now, syncing'), findsOneWidget);
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('home-sync-ring')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('every header action has a 48 dp target', (tester) async {
      await _pump(tester, unread: 2);
      for (final label in [
        'Sync now',
        'Notifications, 2 unread',
        'Settings and profile',
      ]) {
        final size = tester.getSize(_semantics(label));
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
      }
    });
  });

  group('Codex packet-9 findings', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    testWidgets(
        'R21: in the dark appearance the title keeps its contrast on '
        'the legacy Home page it is painted on', (tester) async {
      await _pump(tester, theme: AtomicTheme.dark, size: const Size(480, 860));
      final title =
          tester.widget<Text>(find.byKey(const ValueKey('home-title')));
      // Home's body is still the legacy light page in every appearance.
      final page = tester
          .widgetList<Scaffold>(find.ancestor(
              of: find.byKey(const ValueKey('home-title')),
              matching: find.byType(Scaffold)))
          .first
          .backgroundColor!;
      expect(page, AppColors.paper);
      expect(contrast(title.style!.color!, page), greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    });

    for (final flag in ['disableAnimations', 'accessibleNavigation']) {
      testWidgets('R22: with $flag the sync ring is a still arc',
          (tester) async {
        final shell = await _pump(tester,
            disableAnimations: flag == 'disableAnimations',
            accessibleNavigation: flag == 'accessibleNavigation');
        final gate = Completer<void>();
        shell.notes.syncGate = gate;
        await tester.tap(find.byTooltip('Sync now'));
        await tester.pump();
        await tester.pump();
        final ring = find.byKey(const ValueKey('home-sync-ring'));
        expect(tester.widget<ProgressRing>(ring).value, isNotNull);
        expect(
            find.descendant(of: ring, matching: find.byType(AnimatedBuilder)),
            findsNothing);
        gate.complete();
        await tester.pump();
        await tester.pump();
        expect(ring, findsNothing);
        await tester.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('R22: with full motion the ring still spins', (tester) async {
      final shell = await _pump(tester);
      final gate = Completer<void>();
      shell.notes.syncGate = gate;
      await tester.tap(find.byTooltip('Sync now'));
      await tester.pump();
      await tester.pump();
      final ring = find.byKey(const ValueKey('home-sync-ring'));
      expect(tester.widget<ProgressRing>(ring).value, isNull);
      gate.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
