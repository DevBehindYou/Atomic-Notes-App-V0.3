// UX-03-home: the rest of the Home screen on the redesign components (screens
// spec, Home; components spec, Home status strip, Chips, Search, Selection
// bar, FAB, Empty state, Mascot stage). Counts and rules come from NotesBloc;
// this checks that the page draws them, in both appearances, at 320 dp with
// 2x text, in RTL, with 48 dp targets, spoken labels and reduced motion.
// Fakes only: synthetic notes, no Hive, network or account data.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/notification_models.dart';
import 'package:atomic_notes/database/notifications_source.dart';
import 'package:atomic_notes/mascot/mascot_view.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/page/main_page.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/profile/profile_source.dart';
import 'package:atomic_notes/profile/profile_store.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/state/notifications/notifications_cubit.dart';
import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_fab.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/chips/atomic_filter_chip.dart';
import 'package:atomic_notes/ui/feedback/status_strip.dart';
import 'package:atomic_notes/ui/headers/selection_bar.dart';
import 'package:atomic_notes/ui/mascot/mascot_stage.dart';
import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:atomic_notes/utility/component/notes_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

Note _tagged(
  String id,
  String title,
  List<String> tags, {
  bool checklist = false,
  int day = 1,
}) {
  final base = Note(
    id: id,
    title: title,
    body: 'Body $id',
    createdAt: DateTime.utc(2026, 9, day),
  );
  final document = NoteDocument.fromNote(base)..setTags(tags);
  if (checklist) {
    document
      ..insertChecklistAfter(0)
      ..replaceText(1, 'Item $id');
  }
  final note = document.toNote(base);
  note.dirty = false;
  return note;
}

FakeNotesSource _three({int limit = 30}) => FakeNotesSource(
      limit: limit,
      notes: [
        syncedNote(
          'a',
          title: 'Groceries',
          kind: NoteKind.todo,
          items: [TodoItem(text: 'milk')],
          createdAt: DateTime.utc(2026, 9, 3),
        ),
        syncedNote(
          'b',
          title: 'Ideas',
          body: 'Build a rocket',
          createdAt: DateTime.utc(2026, 9, 2),
        ),
        syncedNote('c', title: 'Trip', createdAt: DateTime.utc(2026, 9, 1)),
      ],
    );

FakeNotesSource _tags() => FakeNotesSource(
      notes: [
        _tagged('w1', 'Plan', ['Work', 'Home'], day: 5),
        _tagged('w2', 'Tasks', ['Work'], checklist: true, day: 4),
        _tagged('z', 'Zoo', ['Zed'], day: 3),
        _tagged('al', 'Atlas', ['Alpha'], day: 2),
        syncedNote('plain',
            title: 'Plain', createdAt: DateTime.utc(2026, 9, 1)),
      ],
    );

FakeNotesSource _many(int n) => FakeNotesSource(
      limit: 200,
      notes: [
        for (var i = 0; i < n; i++)
          syncedNote(
            'n$i',
            title: 'Note $i',
            body: 'Line one\nLine two\nLine three',
            createdAt: DateTime.utc(2026, 9, 1).add(Duration(minutes: n - i)),
          ),
      ],
    );

Future<NotesBloc> _home(
  WidgetTester tester,
  FakeNotesSource source, {
  Size size = const Size(400, 860),
  double textScale = 1,
  ThemeData? theme,
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final bloc = NotesBloc(
    source: source,
    isSyncEnabled: () => true,
    isOnline: () async => true,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await bloc.close();
    source.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AtomicTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        ),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: BlocProvider<NotesBloc>.value(
        value: bloc,
        child: HomePage(now: () => DateTime(2026, 10, 14, 20)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return bloc;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search notes'));
  await _settle(tester);
}

final _title = find.byKey(const ValueKey('home-title'));
final _strip = find.byKey(const ValueKey('notes-welcome-section'));
final _mascot = find.byKey(const ValueKey('mascot-character'));

Finder _chip(String label) =>
    find.byWidgetPredicate((w) => w is AtomicFilterChip && w.label == label,
        description: 'chip $label');

/// Chips sit in a horizontally scrolling row; bring one into view first.
Future<void> _tapChip(WidgetTester tester, Finder chip) async {
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await _settle(tester);
}

List<String> _cardIds(WidgetTester tester) => tester
    .widgetList<NotesBulder>(find.byType(NotesBulder))
    .map((card) => card.note.id)
    .toList();

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

// ---- shell harness (fakes copied from the shell test's shape) ----------------

class _Feed extends ChangeNotifier implements NotificationsSource {
  @override
  List<AppNotification> items = const [];
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
  @override
  String get avatarAsset => Avatars.defaultAsset;
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

Future<(NotesBloc, _Routes, _Events)> _shell(
  WidgetTester tester,
  FakeNotesSource source, {
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(480, 860) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final events = _Events();
  final previous = Bloc.observer;
  Bloc.observer = events;
  addTearDown(() => Bloc.observer = previous);
  final bloc = NotesBloc(
    source: source,
    isSyncEnabled: () => true,
    isOnline: () async => true,
  );
  final feed = _Feed();
  final notifications = NotificationsCubit(source: feed);
  final profile = ProfileCubit(store: _Profile());
  final routes = _Routes();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await bloc.close();
    await notifications.close();
    await profile.close();
    source.dispose();
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
        routes: {
          '/': (_) => MainPage(
                refreshHandle: () async {},
                energyIntroSeen: () => true,
              ),
          '/settingspage': (_) => stub('settings'),
          '/notifications': (_) => stub('notifications'),
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (bloc, routes, events);
}

/// Records platform calls, so a test can see whether the shell asked
/// `SystemNavigator.pop` to leave the app.
List<String> _platformCalls(WidgetTester tester) {
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
  return calls;
}

/// A system Back press that reached Flutter (the platform has already used
/// any press that only hid the keyboard).
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

const _exitHint = 'Press back again to exit';
const _exit = 'SystemNavigator.pop';

void main() {
  // Codex R35: one Back path through the signed-in shell. Selection first,
  // then an open search, then the shell's two-press exit. A press that ends
  // a transient mode neither starts nor keeps an exit window.
  group('Back (Codex R35)', () {
    testWidgets(
        'Codex probe: Back clears active Home search after the keyboard is '
        'dismissed', (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, _, _) = await _shell(tester, _three());
      await _settle(tester);
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'one');
      await _settle(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);
      expect(bloc.state.query, 'one');
      await _back(tester);
      expect(bloc.state.query, isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect(_title, findsOneWidget);
      expect(find.text(_exitHint), findsNothing);
      expect(calls, isNot(contains(_exit)));
    });

    testWidgets(
        'Codex probe: Back clears the current Home selection without exiting',
        (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, _, _) = await _shell(tester, _three());
      await _settle(tester);
      await tester.longPress(find.byKey(const ValueKey('b')));
      await _settle(tester);
      expect(bloc.state.selected, {'b'});
      await _back(tester);
      expect(bloc.state.selected, isEmpty);
      expect(find.byType(SelectionBar), findsNothing);
      expect(_title, findsOneWidget);
      expect(find.text(_exitHint), findsNothing);
      expect(calls, isNot(contains(_exit)));
      // The press that ended the selection did not arm the exit.
      await _back(tester);
      expect(find.text(_exitHint), findsOneWidget);
      expect(calls, isNot(contains(_exit)));
    });

    testWidgets('with nothing to end, Back twice still exits', (tester) async {
      final calls = _platformCalls(tester);
      await _shell(tester, _three());
      await _settle(tester);
      await _back(tester);
      expect(find.text(_exitHint), findsOneWidget);
      expect(calls, isNot(contains(_exit)));
      await _back(tester);
      expect(calls, contains(_exit));
    });

    testWidgets(
        'ending a selection inside an armed window disarms it and hides the '
        'hint', (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, _, _) = await _shell(tester, _three());
      await _settle(tester);
      await _back(tester);
      expect(find.text(_exitHint), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('b')));
      await _settle(tester);
      expect(bloc.state.selected, {'b'});
      await _back(tester);
      expect(bloc.state.selected, isEmpty);
      expect(calls, isNot(contains(_exit)));
      expect(find.text(_exitHint), findsNothing);
      // The old window is gone: the next press only arms a new one.
      await _back(tester);
      expect(find.text(_exitHint), findsOneWidget);
      expect(calls, isNot(contains(_exit)));
      await _back(tester);
      expect(calls, contains(_exit));
    });

    testWidgets(
        'after an expired window, a press that ends a search does not arm '
        'the exit', (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, _, _) = await _shell(tester, _three());
      await _settle(tester);
      await _back(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2100)));
      await tester.pump(const Duration(seconds: 2));
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'rocket');
      await _settle(tester);
      await _back(tester);
      expect(bloc.state.query, isEmpty);
      expect(_title, findsOneWidget);
      expect(find.text(_exitHint), findsNothing);
      await _back(tester);
      expect(find.text(_exitHint), findsOneWidget);
      expect(calls, isNot(contains(_exit)));
    });

    testWidgets(
        'selection over a search: the first Back ends the selection, the '
        'next closes the search', (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, _, _) = await _shell(tester, _three());
      await _settle(tester);
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'rocket');
      await _settle(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);
      await tester.longPress(find.byKey(const ValueKey('b')));
      await _settle(tester);
      expect(bloc.state.selected, {'b'});
      expect(bloc.state.query, 'rocket');

      await _back(tester);
      expect(bloc.state.selected, isEmpty);
      expect(bloc.state.query, 'rocket');
      expect(find.byType(SelectionBar), findsNothing);
      expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'rocket');
      expect(_cardIds(tester), ['b']);
      expect(find.text(_exitHint), findsNothing);

      await _back(tester);
      expect(bloc.state.query, isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect(_title, findsOneWidget);
      expect(find.text(_exitHint), findsNothing);

      await _back(tester);
      expect(find.text(_exitHint), findsOneWidget);
      expect(calls, isNot(contains(_exit)));
    });

    testWidgets(
        'a search still holding focus (keyboard already hidden) closes on '
        'Back, empty or not', (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, _, _) = await _shell(tester, _three());
      await _settle(tester);
      await _openSearch(tester);
      expect(
          tester
              .state<EditableTextState>(find.byType(EditableText))
              .widget
              .focusNode
              .hasFocus,
          isTrue);
      await _back(tester);
      expect(find.byType(TextField), findsNothing);
      expect(_title, findsOneWidget);
      expect(find.text(_exitHint), findsNothing);

      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'rocket');
      await _settle(tester);
      await _back(tester);
      expect(bloc.state.query, isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(NotesBulder), findsNWidgets(3));
      expect(find.text(_exitHint), findsNothing);
      expect(calls, isNot(contains(_exit)));
    });

    testWidgets('Cancel selection hands the next Back to the exit path',
        (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, _, _) = await _shell(tester, _three());
      await _settle(tester);
      await tester.longPress(find.byKey(const ValueKey('c')));
      await _settle(tester);
      await tester.tap(find.byTooltip('Cancel selection'));
      await _settle(tester);
      expect(bloc.state.selecting, isFalse);
      await _back(tester);
      expect(find.text(_exitHint), findsOneWidget);
      expect(calls, isNot(contains(_exit)));
    });

    testWidgets('search Cancel hands the next Back to the exit path',
        (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, _, _) = await _shell(tester, _three());
      await _settle(tester);
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'rocket');
      await _settle(tester);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(bloc.state.query, isEmpty);
      expect(_title, findsOneWidget);
      await _back(tester);
      expect(find.text(_exitHint), findsOneWidget);
      expect(calls, isNot(contains(_exit)));
    });

    testWidgets(
        'Clear search empties the field but leaves it open; Back closes it',
        (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, _, _) = await _shell(tester, _three());
      await _settle(tester);
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'rocket');
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Clear search'));
      await _settle(tester);
      expect(bloc.state.query, isEmpty);
      expect(find.byType(TextField), findsOneWidget);
      await _back(tester);
      expect(find.byType(TextField), findsNothing);
      expect(_title, findsOneWidget);
      expect(find.text(_exitHint), findsNothing);
      expect(calls, isNot(contains(_exit)));
    });

    testWidgets(
        'Back on a pushed route or a dialog is theirs: Home keeps its search '
        'and selection', (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, routes, _) = await _shell(tester, _three());
      await _settle(tester);
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'rocket');
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Settings and profile'));
      await tester.pumpAndSettle();
      expect(routes.pushed.last, '/settingspage');
      await _back(tester);
      expect(find.text('stub settings'), findsNothing);
      expect(bloc.state.query, 'rocket');
      expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'rocket');
      expect(find.text(_exitHint), findsNothing);

      await tester.longPress(find.byKey(const ValueKey('b')));
      await _settle(tester);
      unawaited(showDialog<void>(
        context: tester.element(find.byType(HomePage)),
        builder: (_) => const AlertDialog(content: Text('probe dialog')),
      ));
      await _settle(tester);
      expect(find.text('probe dialog'), findsOneWidget);
      await _back(tester);
      expect(find.text('probe dialog'), findsNothing);
      expect(bloc.state.selected, {'b'});
      expect(bloc.state.query, 'rocket');
      expect(find.text(_exitHint), findsNothing);

      await _back(tester);
      expect(bloc.state.selected, isEmpty);
      expect(bloc.state.query, 'rocket');
      await _back(tester);
      expect(bloc.state.query, isEmpty);
      expect(_title, findsOneWidget);
      expect(find.text(_exitHint), findsNothing);
      expect(calls, isNot(contains(_exit)));
    });

    testWidgets(
        'returning from the editor: its Back closes it, and the search '
        'waits for the next press', (tester) async {
      final calls = _platformCalls(tester);
      final (bloc, _, _) = await _shell(tester, _three());
      await _settle(tester);
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'rocket');
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('b')));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsOneWidget);
      await _back(tester);
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(bloc.state.query, 'rocket');
      expect(find.text(_exitHint), findsNothing);
      await _back(tester);
      expect(bloc.state.query, isEmpty);
      expect(_title, findsOneWidget);
      expect(find.text(_exitHint), findsNothing);
      await _back(tester);
      expect(find.text(_exitHint), findsOneWidget);
      expect(calls, isNot(contains(_exit)));
      expect(tester.takeException(), isNull);
    });
  });

  group('header and search', () {
    testWidgets(
        'the search button swaps the title for a focused field; Cancel '
        'clears the query and gives the title back', (tester) async {
      final bloc = await _home(tester, _three());
      await _settle(tester);
      expect(find.byType(TextField), findsNothing);
      expect(_title, findsOneWidget);
      await _openSearch(tester);
      expect(_title, findsNothing);
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      expect(editor.widget.focusNode.hasFocus, isTrue);
      expect(find.text('Search notes or #tags'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'rocket');
      await tester.pump();
      await tester.pump();
      expect(bloc.state.query, 'rocket');
      expect(_cardIds(tester), ['b']);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(bloc.state.query, isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect(_title, findsOneWidget);
      expect(find.byType(NotesBulder), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('typing # matches tags, as the projection does', (
      tester,
    ) async {
      final bloc = await _home(tester, _tags());
      await _settle(tester);
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), '#zed');
      await tester.pump();
      await tester.pump();
      expect(bloc.state.notes.map((n) => n.id), ['z']);
      // The chips stay and combine with the query.
      expect(_chip('#Work'), findsOneWidget);
    });

    testWidgets('at full motion the swap is a 200 ms shared-axis transition', (
      tester,
    ) async {
      await _home(tester, _three());
      await _settle(tester);
      await tester.tap(find.byTooltip('Search notes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_title, findsOneWidget, reason: 'outgoing title mid-swap');
      expect(find.byType(TextField), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('home-top-bar')),
              matching: find.byType(SlideTransition)),
          findsWidgets);
      await tester.pump(const Duration(milliseconds: 120));
      expect(_title, findsNothing);
      await tester.pumpAndSettle();
    });

    for (final flag in ['disableAnimations', 'accessibleNavigation']) {
      testWidgets(
          'reduced motion ($flag): the swap only fades and the entrance is '
          'already complete', (tester) async {
        await _home(tester, _three(),
            disableAnimations: flag == 'disableAnimations',
            accessibleNavigation: flag == 'accessibleNavigation');
        final fade = tester.widget<FadeTransition>(find
            .ancestor(of: _strip, matching: find.byType(FadeTransition))
            .first);
        expect(fade.opacity.value, 1);
        await tester.tap(find.byTooltip('Search notes'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('home-top-bar')),
                matching: find.byType(SlideTransition)),
            findsNothing);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'RTL: search focus and the editor survive the keyboard moving the '
        'header into the scrolling layout and back', (tester) async {
      final bloc = await _home(tester, _three(),
          size: const Size(400, 700), direction: TextDirection.rtl);
      await _settle(tester);
      await _openSearch(tester);
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      expect(editor.widget.focusNode.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump();
      expect(find.byType(NestedScrollView), findsOneWidget);
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(editor));
      expect(editor.widget.focusNode.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'trip');
      await tester.pump();
      await tester.pump();
      expect(bloc.state.notes.map((n) => n.id), ['c']);
      tester.view.resetViewInsets();
      await tester.pump();
      expect(find.byType(NestedScrollView), findsNothing);
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(editor));
      expect(editor.widget.controller.text, 'trip');
      expect(editor.widget.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a tap outside the field dismisses the keyboard, keeps the query',
        (tester) async {
      final bloc = await _home(tester, _three());
      await _settle(tester);
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'i');
      await tester.pump();
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      expect(editor.widget.focusNode.hasFocus, isTrue);
      await tester.tap(find.text('Good evening'));
      await tester.pump();
      expect(editor.widget.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(bloc.state.query, 'i');
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('the title shrinks to titleLarge once notes scroll under it', (
      tester,
    ) async {
      await _home(tester, _many(20));
      await _settle(tester);
      TextStyle style() => tester
          .widget<AnimatedDefaultTextStyle>(find
              .ancestor(
                  of: _title, matching: find.byType(AnimatedDefaultTextStyle))
              .first)
          .style;
      expect(style().fontSize, AtomicType.display.fontSize);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await _settle(tester);
      expect(style().fontSize, AtomicType.titleLarge.fontSize);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await _settle(tester);
      expect(style().fontSize, AtomicType.display.fontSize);
    });
  });

  group('status strip', () {
    testWidgets(
        'ISS-014: an 84 dp stage with 72 dp animating art, 76/64 below 360 dp',
        (tester) async {
      await _home(tester, _three());
      await _settle(tester);
      final stage = find.byKey(const ValueKey('home-mascot-stage'));
      expect(tester.getSize(stage), const Size(84, 84));
      expect(tester.widget<MascotStage>(stage).size, 84);
      final art = tester.widget<DevBehindYouMascot>(find.descendant(
          of: _mascot, matching: find.byType(DevBehindYouMascot)));
      expect(art.size, 72);
      expect(art.secondary, isFalse);
      expect(
          tester.widget<MascotView>(find.byType(MascotView)).animationsEnabled,
          isTrue);

      tester.view.physicalSize = const Size(320, 700) * 3;
      await _settle(tester);
      expect(tester.getSize(stage), const Size(76, 76));
      final narrow = tester.widget<DevBehindYouMascot>(find.descendant(
          of: _mascot, matching: find.byType(DevBehindYouMascot)));
      expect(narrow.size, 64);
      expect(
          tester.widget<MascotView>(find.byType(MascotView)).animationsEnabled,
          isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'counts come from the bloc: quota, waiting changes, low and limit',
        (tester) async {
      final source = _three();
      final bloc = await _home(tester, source);
      StatusStrip strip() =>
          tester.widget<StatusStrip>(find.byKey(const ValueKey('notes-usage')));
      expect(strip().quota, '3 of 30 notes');
      expect(strip().quotaLevel, QuotaLevel.normal);
      expect(strip().detail, isNull);

      source.changeBehindTheScenes(() {
        source.limit = 8;
        source.byId('c')!.touch();
      });
      await tester.pump();
      await tester.pump();
      expect(strip().quota, '3 of 8 notes');
      expect(strip().quotaLevel, QuotaLevel.low);
      expect(strip().detail, '1 note change waiting to sync');
      expect(strip().detail, contains('${bloc.state.pending}'));

      source.changeBehindTheScenes(() {
        source.limit = 3;
        source.byId('b')!.touch();
      });
      await tester.pump();
      await tester.pump();
      expect(strip().quota, 'Note limit reached');
      expect(strip().quotaLevel, QuotaLevel.limit);
      expect(strip().detail, '2 note changes waiting to sync');
      expect(tester.widget<AtomicFab>(find.byType(AtomicFab)).atLimit, isTrue);
      await tester.tap(find.byType(AtomicFab));
      await tester.pump();
      expect(find.textContaining("You've reached 3 notes"), findsOneWidget);
      expect(find.byType(NotesCreaterPage), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'the mascot gets no frames while the strip is scrolled away, and '
        'resumes when it returns', (tester) async {
      await _home(tester, _many(24));
      await _settle(tester);
      bool ticking() => TickerMode.valuesOf(
              tester.element(find.byType(MascotView, skipOffstage: false)))
          .enabled;
      expect(ticking(), isTrue);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await _settle(tester);
      expect(_strip.hitTestable(), findsNothing);
      expect(ticking(), isFalse);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 800));
      await _settle(tester);
      expect(ticking(), isTrue);
    });

    testWidgets('sync failure reaches the bubble and a retry replaces it', (
      tester,
    ) async {
      final source = _three();
      final bloc = await _home(tester, source);
      source.changeBehindTheScenes(
          () => source.lastError = 'Synthetic sync failure. Try again.');
      await tester.pump();
      await tester.pump();
      await tester.tap(_mascot);
      await tester.pump();
      expect(find.text('Synthetic sync failure. Try again.'), findsOneWidget);
      source.syncGate = Completer<void>();
      bloc.add(const NotesSyncRequested(instant: true));
      await tester.pump();
      await tester.pump();
      expect(find.text('Checking for cloud changes…'), findsOneWidget);
      source.lastError = null;
      source.syncGate!.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(source.syncCalls, 1);
      expect(find.text('Synthetic sync failure. Try again.'), findsNothing);
      expect(find.text('No local changes waiting.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('chips', () {
    testWidgets(
        'type and tag chips show the bloc counts; tags by count, then name',
        (tester) async {
      final bloc = await _home(tester, _tags());
      await _settle(tester);
      final labels = tester
          .widgetList<AtomicFilterChip>(find.byType(AtomicFilterChip))
          .map((chip) => '${chip.label}:${chip.count}')
          .toList();
      final counts = bloc.state.typeCounts;
      expect(labels, [
        'All:${counts[NoteTypeFilter.all]}',
        'Notes:${counts[NoteTypeFilter.notes]}',
        'To-dos:${counts[NoteTypeFilter.todos]}',
        '#Work:2',
        '#Alpha:1',
        '#Home:1',
        '#Zed:1',
      ]);
      expect(counts[NoteTypeFilter.all], 5);
      expect(tester.widget<AtomicFilterChip>(_chip('All')).selected, isTrue);
    });

    testWidgets(
        'a tag chip shows notes of both kinds; a type chip clears the tag',
        (tester) async {
      final bloc = await _home(tester, _tags());
      await _settle(tester);
      await _tapChip(tester, _chip('To-dos'));
      expect(bloc.state.type, NoteTypeFilter.todos);
      await _tapChip(tester, _chip('#Work'));
      expect(bloc.state.tag, 'Work');
      expect(bloc.state.type, NoteTypeFilter.all);
      expect(_cardIds(tester)..sort(), ['w1', 'w2']);
      // The type chips keep counting every note, not the two on view.
      expect(tester.widget<AtomicFilterChip>(_chip('All')).count, 5);
      expect(tester.widget<AtomicFilterChip>(_chip('All')).count,
          bloc.state.typeCounts[NoteTypeFilter.all]);
      expect(tester.widget<AtomicFilterChip>(_chip('#Work')).selected, isTrue);
      expect(tester.widget<AtomicFilterChip>(_chip('All')).selected, isFalse);
      await _tapChip(tester, _chip('Notes'));
      expect(bloc.state.tag, isNull);
      expect(bloc.state.type, NoteTypeFilter.notes);
      expect(tester.widget<AtomicFilterChip>(_chip('Notes')).selected, isTrue);
    });

    testWidgets(
        'counts hold while searching and follow changes behind the scenes, '
        'so no stale chip survives', (tester) async {
      final source = _tags();
      final bloc = await _home(tester, source);
      await _settle(tester);
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      await tester.pump();
      expect(bloc.state.notes, isEmpty);
      expect(tester.widget<AtomicFilterChip>(_chip('All')).count, 5);
      expect(tester.widget<AtomicFilterChip>(_chip('#Work')).count, 2);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      await _tapChip(tester, _chip('#Zed'));
      expect(bloc.state.tag, 'Zed');
      source.changeBehindTheScenes(() => source.byId('z')!.deleted = true);
      await tester.pump();
      await tester.pump();
      expect(_chip('#Zed'), findsNothing);
      expect(bloc.state.tag, isNull);
      expect(tester.widget<AtomicFilterChip>(_chip('All')).selected, isTrue);
      expect(tester.widget<AtomicFilterChip>(_chip('All')).count, 4);
      expect(tester.widget<AtomicFilterChip>(_chip('All')).count,
          bloc.state.typeCounts[NoteTypeFilter.all]);

      source.changeBehindTheScenes(() => source.byId('w2')!.deleted = true);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<AtomicFilterChip>(_chip('#Work')).count, 1);
      expect(tester.widget<AtomicFilterChip>(_chip('To-dos')).count,
          bloc.state.typeCounts[NoteTypeFilter.todos]);
    });

    testWidgets(
        'the sort button opens the sheet; Oldest shows the dot and the '
        'order flips', (tester) async {
      final bloc = await _home(tester, _three());
      await _settle(tester);
      expect(_cardIds(tester), ['a', 'b', 'c']);
      await tester.ensureVisible(find.byTooltip('Sort notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sort notes'));
      await _settle(tester);
      expect(find.text('Sort notes'), findsOneWidget);
      expect(find.text('Newest'), findsOneWidget);
      await tester.tap(find.text('Oldest'));
      await _settle(tester);
      expect(bloc.state.sort, NoteSort.oldest);
      expect(_cardIds(tester), ['c', 'b', 'a']);
      final sort = find.byWidgetPredicate(
          (w) => w is AtomicIconButton && w.tooltip == 'Sort notes');
      expect(tester.widget<AtomicIconButton>(sort).dot, isTrue);
      expect(find.bySemanticsLabel('Sort notes, oldest first'), findsOneWidget);
      // Choosing the order keeps the type and tag.
      expect(bloc.state.type, NoteTypeFilter.all);
    });

    testWidgets('a long tag truncates at 160 dp; its full name is spoken', (
      tester,
    ) async {
      final long = 'L' * NoteDocument.maxTagCharacters;
      await _home(
          tester,
          FakeNotesSource(notes: [
            _tagged('x', 'Long', [long])
          ]));
      await _settle(tester);
      final chip = _chip('#$long');
      expect(tester.getSize(chip).width, lessThan(160 + 80));
      expect(find.bySemanticsLabel('#$long, 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('cards and empty states', () {
    testWidgets('the featured card spans the grid; columns follow the width', (
      tester,
    ) async {
      final source = _three();
      source.byId('b')!.pinned = true;
      await _home(tester, source);
      await _settle(tester);
      final featured = find.byWidgetPredicate(
          (w) => w is NotesBulder && w.featured && w.note.id == 'b');
      expect(featured, findsOneWidget);
      final a = tester.getRect(find.byKey(const ValueKey('a')));
      final c = tester.getRect(find.byKey(const ValueKey('c')));
      expect((a.top - c.top).abs(), lessThan(1), reason: 'two columns');
      expect(tester.getSize(featured).width, greaterThan(a.width * 1.8));

      tester.view.physicalSize = const Size(320, 860) * 3;
      await _settle(tester);
      final a1 = tester.getRect(find.byKey(const ValueKey('a')));
      final c1 = tester.getRect(find.byKey(const ValueKey('c')));
      expect(c1.top, greaterThan(a1.bottom), reason: 'one column below 340');
    });

    testWidgets('the last card scrolls clear of the new-note button', (
      tester,
    ) async {
      final bloc = await _home(tester, _many(16));
      await _settle(tester);
      // The masonry extent is estimated lazily: drag until the end is built.
      for (var i = 0; i < 6; i++) {
        await tester.drag(
            find.byType(CustomScrollView), const Offset(0, -1500));
        await _settle(tester);
      }
      final last =
          tester.getRect(find.byKey(ValueKey(bloc.state.notes.last.id)));
      final fab = tester.getRect(find.byType(AtomicFab));
      expect(last.bottom, lessThanOrEqualTo(fab.top));
    });

    testWidgets(
        'no notes: the invitation, with a still second mascot on its stage',
        (tester) async {
      await _home(tester, FakeNotesSource());
      await _settle(tester);
      final empty = find.byKey(const ValueKey('home-empty-first-note'));
      expect(empty, findsOneWidget);
      expect(find.text('Write your first note'), findsOneWidget);
      expect(
          find.text('Tap + to start. You can switch to a checklist in the '
              'editor.'),
          findsOneWidget);
      final still = tester.widget<DevBehindYouMascot>(find.descendant(
          of: empty, matching: find.byType(DevBehindYouMascot)));
      expect(still.secondary, isTrue);
      expect(
          tester
              .widgetList<MascotView>(find.byType(MascotView))
              .where((view) => view.animationsEnabled),
          hasLength(1));
      expect(find.byType(AtomicFab), findsOneWidget);
    });

    testWidgets('no match: Show all notes resets the chip and the search', (
      tester,
    ) async {
      final bloc = await _home(tester, _tags());
      await _settle(tester);
      await _tapChip(tester, _chip('#Alpha'));
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'nothing like this');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('home-empty-no-match')), findsOneWidget);
      expect(find.text('No notes match'), findsOneWidget);
      expect(find.text('Try another filter or search.'), findsOneWidget);
      await tester.tap(find.text('Show all notes'));
      await _settle(tester);
      expect(bloc.state.query, isEmpty);
      expect(bloc.state.tag, isNull);
      expect(bloc.state.type, NoteTypeFilter.all);
      expect(find.byType(TextField), findsNothing);
      expect(_title, findsOneWidget);
      expect(find.byType(NotesBulder), findsNWidgets(5));
    });
  });

  group('selection', () {
    testWidgets(
        'a long press: the selection bar replaces the header, the strip and '
        'chips dim to 40 % and ignore taps, the button hides', (tester) async {
      final bloc = await _home(tester, _three());
      await _settle(tester);
      await tester.longPress(find.byKey(const ValueKey('b')));
      await _settle(tester);
      expect(find.byType(SelectionBar), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(_title, findsNothing);
      expect(find.byTooltip('Search notes'), findsNothing);
      expect(find.byType(AtomicFab), findsNothing);
      final dims = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => o.opacity == 0.4);
      expect(dims, hasLength(2), reason: 'strip and chip row');
      await tester.tap(_chip('To-dos'), warnIfMissed: false);
      await tester.tap(_mascot, warnIfMissed: false);
      await tester.pump();
      expect(bloc.state.type, NoteTypeFilter.all);
      expect(find.text('No local changes waiting.'), findsNothing);
      expect(bloc.state.selected, {'b'});
    });

    testWidgets('Select all, then Delete moves them to the Recycle Bin', (
      tester,
    ) async {
      final source = _three();
      final bloc = await _home(tester, source);
      await _settle(tester);
      await tester.longPress(find.byKey(const ValueKey('a')));
      await _settle(tester);
      await tester.tap(find.text('Select all'));
      await tester.pump();
      expect(bloc.state.selected, {'a', 'b', 'c'});
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(source.deletedIds..sort(), ['a', 'b', 'c']);
      expect(bloc.state.selecting, isFalse);
      expect(find.byType(SelectionBar), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Cancel selection restores the header, strip, chips and button',
        (tester) async {
      final bloc = await _home(tester, _three());
      await _settle(tester);
      await tester.longPress(find.byKey(const ValueKey('c')));
      await _settle(tester);
      await tester.tap(find.byTooltip('Cancel selection'));
      await _settle(tester);
      expect(bloc.state.selecting, isFalse);
      expect(_title, findsOneWidget);
      expect(find.byType(AtomicFab), findsOneWidget);
      expect(
          tester
              .widgetList<Opacity>(find.byType(Opacity))
              .where((o) => o.opacity == 0.4),
          isEmpty);
      await tester.tap(_chip('To-dos'));
      await tester.pump();
      expect(bloc.state.type, NoteTypeFilter.todos);
    });

    testWidgets('the selected count is a live region for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _home(tester, _three());
      await _settle(tester);
      await tester.longPress(find.byKey(const ValueKey('a')));
      await _settle(tester);
      final data =
          tester.getSemantics(find.text('1 selected')).getSemanticsData();
      expect(data.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });
  });

  group('returning to Home', () {
    testWidgets(
        'header actions keep their endpoints: Settings, Notifications, sync '
        'and the Energy long press; the chip survives Settings',
        (tester) async {
      final (bloc, routes, events) = await _shell(tester, _tags());
      await _settle(tester);
      await _tapChip(tester, _chip('#Work'));
      await tester.tap(find.bySemanticsLabel('Settings and profile'));
      await tester.pumpAndSettle();
      expect(routes.pushed.last, '/settingspage');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(bloc.state.tag, 'Work');
      expect(tester.widget<AtomicFilterChip>(_chip('#Work')).selected, isTrue);
      expect(_strip, findsOneWidget);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(routes.pushed.last, '/notifications');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.bySemanticsLabel('Sync now'));
      expect(
          node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
      await tester.tap(find.byTooltip('Sync now'));
      await tester.pump();
      await tester.pump();
      final requests = events.seen.whereType<NotesSyncRequested>().toList();
      expect(requests, hasLength(1));
      expect(requests.single.instant, isTrue);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('sync failure from the header button, then a retry', (
      tester,
    ) async {
      final source = _three()
        ..syncResult = false
        ..lastError = 'Synthetic sync failure. Try again.';
      await _shell(tester, source);
      await _settle(tester);
      await tester.tap(find.byTooltip('Sync now'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Synthetic sync failure. Try again.'), findsWidgets);
      await tester.pump(const Duration(seconds: 4));
      source
        ..syncResult = true
        ..lastError = null;
      await tester.tap(find.byTooltip('Sync now'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // The earlier message leaves first; then the answer to the retry shows.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(source.syncCalls, 2);
      expect(find.text('Sync finished'), findsOneWidget);
      await tester.tap(_mascot);
      await tester.pump();
      expect(find.text('No local changes waiting.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('coming back from the editor keeps the chip and the strip', (
      tester,
    ) async {
      final bloc = await _home(tester, _tags());
      await _settle(tester);
      await _tapChip(tester, _chip('#Work'));
      await tester.tap(find.byKey(const ValueKey('w1')));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsOneWidget);
      await tester.tap(find.byTooltip('Back to notes'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(bloc.state.tag, 'Work');
      expect(_strip.hitTestable(), findsOneWidget);
      expect(_title, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('appearance and accessibility', () {
    for (final entry in {
      'light': (AtomicTheme.light, AtomicColors.light),
      'dark': (AtomicTheme.dark, AtomicColors.dark),
    }.entries) {
      final (theme, c) = entry.value;
      testWidgets(
          '${entry.key}: the canvas pairs with its foregrounds; no light '
          'override is left on the header', (tester) async {
        await _home(tester, _tags(), theme: theme);
        await _settle(tester);
        final page = tester
            .widgetList<Scaffold>(
                find.ancestor(of: _title, matching: find.byType(Scaffold)))
            .first
            .backgroundColor!;
        expect(page, c.canvas);
        final title = tester.widget<Text>(_title);
        expect(title.style!.color, c.textPrimary);
        expect(_contrast(title.style!.color!, page), greaterThanOrEqualTo(4.5));
        expect(Theme.of(tester.element(_title)).extension<AtomicColors>(), c);
        expect(Theme.of(tester.element(_strip)).extension<AtomicColors>(), c);
        expect(
            _contrast(c.textSecondary, c.surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.textPrimary, c.surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.onInverse, c.inverseSurface),
            greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
      });
    }

    for (final theme
        in {'light': AtomicTheme.light, 'dark': AtomicTheme.dark}.entries) {
      for (final direction in TextDirection.values) {
        testWidgets(
            '320 dp, 2.0 text, ${theme.key}, ${direction.name}: everything '
            'fits; search and selection still work', (tester) async {
          final bloc = await _home(tester, _tags(),
              size: const Size(320, 700),
              textScale: 2,
              theme: theme.value,
              direction: direction);
          await _settle(tester);
          expect(tester.takeException(), isNull);
          expect(find.byType(NestedScrollView), findsOneWidget);
          for (final finder in [
            _title,
            find.byTooltip('Search notes'),
            _mascot,
            find.byType(AtomicFab),
          ]) {
            final rect = tester.getRect(finder);
            expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$finder');
            expect(rect.right, lessThanOrEqualTo(320.5), reason: '$finder');
          }
          final strip = tester.getRect(_strip);
          expect(strip.width, lessThanOrEqualTo(320));
          expect(find.textContaining('5 of 30 notes'), findsOneWidget);
          await _openSearch(tester);
          final field = tester.getRect(find.byType(TextField));
          expect(field.left, greaterThanOrEqualTo(0));
          expect(field.right, lessThanOrEqualTo(320));
          await tester.tap(find.text('Cancel'));
          await _settle(tester);
          await tester.longPress(find.byType(NotesBulder).first);
          await _settle(tester);
          expect(find.byType(SelectionBar), findsOneWidget);
          expect(bloc.state.selecting, isTrue);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('every Home control has a 48 dp target', (tester) async {
      await _home(tester, _tags());
      await _settle(tester);
      void check(Finder finder) {
        final size = tester.getSize(finder);
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
      }

      check(find.bySemanticsLabel('Search notes'));
      check(find.bySemanticsLabel('Sort notes, newest first'));
      check(find.bySemanticsLabel('New note'));
      for (final chip in tester
          .widgetList<AtomicFilterChip>(find.byType(AtomicFilterChip))) {
        check(find.bySemanticsLabel('${chip.label}, ${chip.count}'));
      }
      await tester.longPress(find.byType(NotesBulder).first);
      await _settle(tester);
      check(find.bySemanticsLabel('Cancel selection'));
      check(find.bySemanticsLabel('Select all'));
      check(find.bySemanticsLabel('Delete'));
    });

    testWidgets('spoken labels: heading, chips with counts, sort, new note', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _home(tester, _tags());
      await _settle(tester);
      expect(
          tester
              .getSemantics(_title)
              .getSemanticsData()
              .flagsCollection
              .isHeader,
          isTrue);
      expect(find.bySemanticsLabel('All, 5'), findsOneWidget);
      expect(find.bySemanticsLabel('#Work, 2'), findsOneWidget);
      final all = tester.getSemantics(find.bySemanticsLabel('All, 5'));
      expect(
          all.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      expect(find.bySemanticsLabel('Sort notes, newest first'), findsOneWidget);
      expect(find.bySemanticsLabel('New note'), findsOneWidget);
      expect(find.bySemanticsLabel('Good evening'), findsOneWidget);
      handle.dispose();
    });
  });
}
