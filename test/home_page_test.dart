// The notes screen, driven through the Bloc with a fake store: what it shows, what a tap does,
// and how little it rebuilds. It needs neither Hive nor the network.

import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/mascot/mascot_view.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/ui/buttons/atomic_fab.dart';
import 'package:atomic_notes/ui/chips/atomic_filter_chip.dart';
import 'package:atomic_notes/ui/feedback/status_strip.dart';
import 'package:atomic_notes/utility/component/notes_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';
import 'notes_editor_page_test.dart' show field;

void _stage(String value) {
  // Fixed public fixture markers only; the CI runner never exports test text.
  // ignore: avoid_print
  print('atomic_ui_stage:welcome_collapse:$value');
}

FakeNotesSource _source({int limit = 30, bool empty = false}) =>
    FakeNotesSource(
      limit: limit,
      notes: empty
          ? []
          : [
              syncedNote(
                'a',
                title: 'Groceries',
                kind: NoteKind.todo,
                items: [
                  TodoItem(text: 'milk'),
                  TodoItem(text: 'bread'),
                ],
                createdAt: DateTime.utc(2026, 9, 3),
              ),
              syncedNote(
                'b',
                title: 'Ideas',
                body: 'Build a rocket',
                createdAt: DateTime.utc(2026, 9, 2),
              ),
              syncedNote(
                'c',
                title: 'Trip',
                createdAt: DateTime.utc(2026, 9, 1),
              ),
            ],
    );

Future<NotesBloc> _open(
  WidgetTester tester,
  FakeNotesSource source, {
  DateTime Function()? now,
}) async {
  // Tall, so everything is on view and nothing has to be scrolled to.
  tester.view.physicalSize = const Size(1290, 2700);
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
      home: BlocProvider<NotesBloc>.value(
        value: bloc,
        child: HomePage(now: now),
      ),
    ),
  );
  await tester.pump();
  return bloc;
}

// UX-03-home: the search field opens from the header's search button.
Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search notes'));
  await tester.pump();
  await tester.pumpAndSettle();
}

final _newNote = find.byTooltip('New note');
final _searchButton = find.byTooltip('Search notes');

void main() {
  testWidgets('mascot alone opens status without starting sync',
      (tester) async {
    final source = _source();
    await _open(tester, source);
    expect(tester.widget<MascotView>(find.byType(MascotView)).clipRest,
        const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('mascot-sync-status')), findsNothing);
    expect(find.byTooltip('Sync status'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mascot-character')));
    await tester.pump();
    expect(find.textContaining('No local changes waiting.'), findsOneWidget);
    expect(source.syncCalls, 0);
  });

  group('welcome', () {
    for (final entry in [
      (DateTime(2026, 10, 14, 8), 'Good morning'),
      (DateTime(2026, 10, 14, 13), 'Good afternoon'),
      (DateTime(2026, 10, 14, 20), 'Good evening'),
    ]) {
      testWidgets('uses local greeting ${entry.$2} and current date', (
        tester,
      ) async {
        await _open(tester, _source(), now: () => entry.$1);
        // The status strip greets by the local hour (no date line).
        expect(find.text(entry.$2), findsOneWidget);
        final strip = tester.widget<StatusStrip>(
          find.byKey(const ValueKey('notes-usage')),
        );
        expect(strip.greeting, entry.$2);
        expect(strip.quotaLevel, QuotaLevel.normal);
        expect(find.textContaining('3 of 30 notes'), findsOneWidget);
        expect(find.textContaining('IN CLOUD'), findsNothing);
      });
    }

    // Spec (Home status strip): the greeting no longer collapses on a 4 s
    // timer; the strip scrolls away with the notes instead.
    testWidgets('four-second welcome no longer collapses; controls stay', (
      tester,
    ) async {
      // testWidgets owns its enabled semantics handle and disposes it before
      // end-of-test verification; addTearDown would dispose an extra one late.
      await _open(tester, _source(), now: () => DateTime(2026, 10, 14, 20));
      _stage('mounted');
      final welcome = find.byKey(const ValueKey('notes-welcome-section'));
      final search = _searchButton;
      final originalHeight = tester.getSize(welcome).height;
      final originalSearchTop = tester.getTopLeft(search).dy;
      await tester.pump(const Duration(milliseconds: 3999));
      expect(tester.getSize(welcome).height, originalHeight);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 140));
      _stage('mid_animation');
      expect(tester.getSize(welcome).height, greaterThan(0));
      expect(tester.getSize(welcome).height, originalHeight);
      final opacity = tester.widget<Opacity>(
        find.descendant(of: welcome, matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, 1.0);
      await tester.pump(const Duration(milliseconds: 160));
      _stage('collapsed');
      expect(tester.getSize(welcome).height, originalHeight);
      expect(
        tester.getTopLeft(search).dy,
        closeTo(originalSearchTop, 0.01),
      );
      expect(
          find.textContaining('3 of 30 notes').hitTestable(), findsOneWidget);
      _stage('controls');
      expect(_newNote.hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('mascot-character')).hitTestable(),
          findsOneWidget);
      expect(find.byType(AtomicFilterChip).hitTestable(), findsWidgets);
      _stage('semantics');
      expect(
        find.semantics.byLabel('Good evening'),
        findsOneWidget,
      );
      _stage('clean');
      expect(tester.takeException(), isNull);
    });

    testWidgets('background pause and resume reset the greeting', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var localTime = DateTime(2026, 10, 14, 20);
      await _open(tester, _source(), now: () => localTime);
      final welcome = find.byKey(const ValueKey('notes-welcome-section'));
      await tester.pump(const Duration(seconds: 3));
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(seconds: 10));
      expect(tester.getSize(welcome).height, greaterThan(0));
      localTime = DateTime(2026, 10, 15, 8);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(find.text('Good morning'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 3999));
      expect(tester.getSize(welcome).height, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(welcome).height, greaterThan(0));
    });

    testWidgets('muted home reads the greeting clock when shown', (
      tester,
    ) async {
      final source = _source();
      final bloc = await _open(tester, source);
      final visible = ValueNotifier<bool>(false);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, enabled, __) => TickerMode(
              enabled: enabled,
              child: BlocProvider<NotesBloc>.value(
                value: bloc,
                child: const HomePage(),
              ),
            ),
          ),
        ),
      );
      final welcome = find.byKey(const ValueKey('notes-welcome-section'));
      await tester.pump(const Duration(seconds: 10));
      expect(tester.getSize(welcome).height, greaterThan(0));
      visible.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3999));
      expect(tester.getSize(welcome).height, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(welcome).height, greaterThan(0));
    });

    testWidgets('reduced motion keeps the strip in place after four seconds', (
      tester,
    ) async {
      final bloc = await _open(tester, _source());
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: BlocProvider<NotesBloc>.value(
            value: bloc,
            child: const HomePage(),
          ),
        ),
      );
      final welcome = find.byKey(const ValueKey('notes-welcome-section'));
      await tester.pump(const Duration(milliseconds: 3999));
      expect(tester.getSize(welcome).height, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.getSize(welcome).height, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposing during welcome cancels timer and ticker', (
      tester,
    ) async {
      await _open(tester, _source());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '320px and 2x text keep 123 pending notes and controls visible',
      (tester) async {
        final source = FakeNotesSource(
          limit: 200,
          notes: List.generate(
            123,
            (i) => syncedNote('pending-$i', title: 'N$i', body: 'Pending')
              ..touch(),
          ),
        );
        final bloc = await _open(tester, source);
        tester.view.physicalSize = const Size(960, 2100);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: BlocProvider<NotesBloc>.value(
              value: bloc,
              child: HomePage(now: () => DateTime(2026, 10, 14, 20)),
            ),
          ),
        );
        await tester.pump();
        // The title row that used to be the shell's app bar is now part of
        // Home. Keep the same 700 dp below it that this page had before.
        final bar =
            tester.getSize(find.byKey(const ValueKey('home-top-bar'))).height;
        final viewHeight = 700 + bar;
        tester.view.physicalSize = Size(960, viewHeight * 3);
        await tester.pump();
        final welcome = find.byKey(const ValueKey('notes-welcome-section'));
        final usage =
            find.text('123 of 200 notes · 123 note changes waiting to sync');
        final usageText = tester.widget<Text>(usage);
        expect(usageText.maxLines, isNull);
        expect(MediaQuery.textScalerOf(tester.element(usage)).scale(11), 22);
        final initialHeight = tester.getSize(welcome).height;
        expect(initialHeight, greaterThan(0));
        expect(
          tester
              .widget<Opacity>(
                find
                    .descendant(of: welcome, matching: find.byType(Opacity))
                    .first,
              )
              .opacity,
          1,
        );
        void expectUsable() {
          expect(tester.takeException(), isNull);
          expect(find.textContaining('123 of 200 notes').hitTestable(),
              findsOneWidget);
          expect(usage.hitTestable(), findsOneWidget);
          final bounds = tester.getRect(usage);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
          expect(_searchButton.hitTestable(), findsOneWidget);
          expect(find.byKey(const ValueKey('mascot-character')).hitTestable(),
              findsOneWidget);
          final card = tester.getRect(find.byType(NotesBulder).first);
          expect(
            card.intersect(Rect.fromLTWH(0, 0, 320, viewHeight)).height,
            greaterThan(0),
          );
          expect(_newNote.hitTestable(), findsOneWidget);
          expect(bloc.state.pending, 123);
        }

        expectUsable();
        expect(find.byType(NestedScrollView), findsOneWidget);
        await tester.drag(find.byType(NestedScrollView), const Offset(0, -500));
        await tester.pump();
        expect(find.byType(NotesBulder).hitTestable().first, findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.drag(find.byType(NestedScrollView), const Offset(0, 500));
        await tester.pumpAndSettle();
        // No collapse: scrolled back, the strip is whole again.
        expect(tester.getSize(welcome).height, initialHeight);
        expectUsable();
        // The taller strip leaves the first card's top in view, not its centre.
        expect(
            find
                .byType(NotesBulder)
                .hitTestable(at: const Alignment(-0.9, -0.9))
                .first,
            findsOneWidget);
      },
    );

    testWidgets(
      'selection and responsive layout keep the strip, inert while selecting',
      (tester) async {
        await _open(tester, _source());
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 300));
        final welcome = find.byKey(const ValueKey('notes-welcome-section'));
        final height = tester.getSize(welcome).height;
        expect(height, greaterThan(0));
        await tester.longPress(find.byType(NotesBulder).first);
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
        // Spec: the strip stays in selection mode, dimmed and inert.
        expect(find.byKey(const ValueKey('mascot-character')).hitTestable(),
            findsNothing);
        await tester.tap(find.byTooltip('Cancel selection'));
        await tester.pumpAndSettle();
        expect(tester.getSize(welcome).height, height);
        tester.view.physicalSize = const Size(2400, 1080);
        await tester.pump();
        expect(find.byType(NestedScrollView), findsOneWidget);
        expect(tester.getSize(welcome).height, height);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('what the screen shows', () {
    for (final pending in [false, true]) {
      testWidgets('R19 mascot reports automatic failure (pending=$pending)', (
        tester,
      ) async {
        final source = _source();
        if (pending) source.byId('c')!.touch();
        await _open(tester, source);
        source.changeBehindTheScenes(
          () => source.lastError =
              'A cloud note could not be read safely. Try syncing again.',
        );
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('mascot-character')));
        await tester.pump();
        expect(
          find.text(
            'A cloud note could not be read safely. Try syncing again.',
          ),
          findsOneWidget,
        );
        expect(find.text('No local changes waiting.'), findsNothing);
        expect(source.syncCalls, 0);
        await tester.pump(const Duration(seconds: 4));
      });
    }
    testWidgets('R19 receive-only retry replaces its previous error', (
      tester,
    ) async {
      final source = _source()..lastError = 'Previous failure';
      await _open(tester, source);
      source.changeBehindTheScenes(() {
        source.lastError = null;
        source.isSyncing = true;
      });
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mascot-character')));
      await tester.pump();
      expect(find.text('Checking for cloud changes…'), findsOneWidget);
      expect(find.text('Previous failure'), findsNothing);
      expect(find.text('No local changes waiting.'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });
    testWidgets(
      'R19 automatic sync reaches the mascot without a button press',
      (tester) async {
        final source = _source();
        source.byId('c')!.touch();
        await _open(tester, source);
        source.changeBehindTheScenes(() => source.isSyncing = true);
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('mascot-character')));
        await tester.pump();
        expect(find.text('Syncing 1 change now.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
      },
    );
    testWidgets(
      'the mascot drops a future wait when the source clears its cooldown',
      (tester) async {
        final source = _source()
          ..nextAutoSyncAt = DateTime.now().add(const Duration(minutes: 40));
        await _open(tester, source);
        await tester.tap(find.byKey(const ValueKey('mascot-character')));
        await tester.pump();
        expect(
          find.text('No local changes waiting. Next sync in 40 min.'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('mascot-character')));
        await tester.pump();

        source.changeBehindTheScenes(() => source.nextAutoSyncAt = null);
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('mascot-character')));
        await tester.pump();
        expect(find.text('No local changes waiting.'), findsOneWidget);
        expect(find.textContaining('Next sync in'), findsNothing);
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets('a card for each note and the usage in the header', (
      tester,
    ) async {
      await _open(tester, _source());
      expect(find.byType(NotesBulder), findsNWidgets(3));
      expect(find.text('3 of 30 notes'), findsOneWidget);
      // Card titles are set in capitals by the design system.
      expect(find.text('GROCERIES'), findsOneWidget);
      expect(find.text('0 / 2 DONE'), findsOneWidget);
    });

    testWidgets(
      'tapping the mascot opens a chat bubble that closes by itself',
      (tester) async {
        await _open(tester, _source());
        await tester.tap(find.byKey(const ValueKey('mascot-character')));
        await tester.pump();
        expect(find.text('No local changes waiting.'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);

        await tester.pump(const Duration(seconds: 4));
        expect(find.text('No local changes waiting.'), findsNothing);
      },
    );

    testWidgets('a second tap closes the bubble', (tester) async {
      await _open(tester, _source());
      await tester.tap(find.byKey(const ValueKey('mascot-character')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mascot-character')));
      await tester.pump();
      expect(find.text('No local changes waiting.'), findsNothing);
    });

    testWidgets('the bubble names the wait when automatic sync is closed', (
      tester,
    ) async {
      final source = _source()
        ..nextAutoSyncAt = DateTime.now().add(const Duration(minutes: 40));
      await _open(tester, source);
      await tester.tap(find.byKey(const ValueKey('mascot-character')));
      await tester.pump();
      expect(
        find.text('No local changes waiting. Next sync in 40 min.'),
        findsOneWidget,
      );
    });

    testWidgets('the bubble counts changes that are waiting', (tester) async {
      final source = _source();
      await _open(tester, source);
      source.byId('c')!.touch();
      source.poke();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mascot-character')));
      await tester.pump();
      // Nothing is running: the change waits (offline, or for the few seconds before auto-sync).
      expect(
        find.text('1 change waiting. It syncs by itself when you are online.'),
        findsOneWidget,
      );
      expect(find.text('Syncing 1 change now.'), findsNothing);
    });

    testWidgets('on a short screen the header scrolls away with the notes', (
      tester,
    ) async {
      // A phone on its side: 800 x 360 logical pixels.
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bloc = NotesBloc(
        source: _source(),
        isSyncEnabled: () => true,
        isOnline: () async => true,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await bloc.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<NotesBloc>.value(
            value: bloc,
            child: const HomePage(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(NestedScrollView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notes-welcome-section')).hitTestable(),
        findsOneWidget,
      );
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      // The title has scrolled off; the cards now have the screen.
      expect(
        find.byKey(const ValueKey('notes-welcome-section')).hitTestable(),
        findsNothing,
      );
      expect(find.byType(NotesBulder).hitTestable(), findsWidgets);
    });

    testWidgets('on a tall screen the header stays put', (tester) async {
      await _open(tester, _source());
      expect(find.byType(NestedScrollView), findsNothing);
    });

    testWidgets('while a sync runs the bubble says it is syncing', (
      tester,
    ) async {
      final source = _source()..syncGate = Completer<void>();
      final bloc = await _open(tester, source);
      source.byId('c')!.touch();
      source.poke();
      await tester.pump();
      bloc.add(const NotesSyncRequested(instant: true));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mascot-character')));
      await tester.pump();
      expect(find.text('Syncing 1 change now.'), findsOneWidget);
      source.syncGate!.complete();
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('waiting notes are counted next to the usage', (tester) async {
      final source = _source();
      await _open(tester, source);
      source.byId('c')!.touch();
      source.poke();
      await tester.pump();
      await tester.pump();
      expect(find.text('3 of 30 notes · 1 note change waiting to sync'),
          findsOneWidget);
    });

    testWidgets('at the limit the header and the add menu say so', (
      tester,
    ) async {
      await _open(tester, _source(limit: 3));
      expect(find.text('Note limit reached'), findsOneWidget);
      expect(find.bySemanticsLabel('New note. Note limit reached'),
          findsOneWidget);
      expect(tester.widget<AtomicFab>(find.byType(AtomicFab)).atLimit, isTrue);
    });

    testWidgets('a bought limit reaches the screen at once', (tester) async {
      final source = _source(limit: 3);
      await _open(tester, source);
      source.changeBehindTheScenes(() => source.limit = 30);
      await tester.pump();
      await tester.pump();
      expect(find.text('3 of 30 notes'), findsOneWidget);
      expect(
          find.bySemanticsLabel('New note. Note limit reached'), findsNothing);
    });

    testWidgets('an empty account shows the invitation', (tester) async {
      await _open(tester, _source(empty: true));
      expect(find.byType(NotesBulder), findsNothing);
      expect(find.text('Write your first note'), findsOneWidget);
    });
  });

  group('filter and search', () {
    testWidgets('keyboard resizing keeps the search editor and input focus',
        (tester) async {
      await _open(tester, _source());
      // The 64 dp title row used to be the shell's app bar; keep the same
      // 900 dp for the rest of the page.
      tester.view.physicalSize = const Size(1290, 2700 + 64 * 3);
      await tester.pump();
      await _openSearch(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      expect(editor.widget.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      // A 500px logical IME makes the 900px-tall page cross the short-screen
      // breakpoint, matching Android's actual resize while opening its keyboard.
      tester.view.viewInsets = const FakeViewPadding(bottom: 1500);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump();
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(editor));
      expect(editor.widget.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(find.byType(TextField), 'rocket');
      await tester.pump();
      await tester.pump();
      expect(find.byType(NotesBulder), findsOneWidget);
      expect(find.text('IDEAS'), findsOneWidget);
      tester.view.resetViewInsets();
      await tester.pump();
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(editor));
      expect(editor.widget.controller.text, 'rocket');
      expect(editor.widget.focusNode.hasFocus, isTrue);
    });

    testWidgets('the to-dos chip keeps only checklists', (tester) async {
      await _open(tester, _source());
      await tester.tap(find.text('To-dos'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(NotesBulder), findsOneWidget);
      expect(find.text('GROCERIES'), findsOneWidget);
    });

    testWidgets('a filter with no match says so', (tester) async {
      final source = FakeNotesSource(
        notes: [syncedNote('x', title: 'Only text')],
      );
      await _open(tester, source);
      await tester.tap(find.text('To-dos'));
      await tester.pump();
      await tester.pump();
      expect(find.text('No notes match'), findsOneWidget);
    });

    testWidgets('typing narrows the list, the cross clears it', (tester) async {
      await _open(tester, _source());
      await _openSearch(tester);
      expect(find.byTooltip('Clear search'), findsNothing);

      await tester.enterText(find.byType(TextField), 'rocket');
      await tester.pump();
      await tester.pump();
      expect(find.byType(NotesBulder), findsOneWidget);
      expect(find.text('IDEAS'), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(NotesBulder), findsNWidgets(3));
      expect(find.byTooltip('Clear search'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });
  });

  group('selecting', () {
    testWidgets(
      'a long press starts selecting: the count, the actions, no chips, no add menu',
      (tester) async {
        await _open(tester, _source());
        expect(_newNote, findsOneWidget);
        expect(_searchButton, findsOneWidget);

        await tester.longPress(find.byType(NotesBulder).first);
        // The add menu slides out with the Scaffold's own animation.
        await tester.pumpAndSettle();

        expect(find.text('1 selected'), findsOneWidget);
        expect(find.text('Select all'), findsOneWidget);
        expect(find.byTooltip('Cancel selection'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(_searchButton, findsNothing);
        expect(_newNote, findsNothing);
      },
    );

    testWidgets('cancel ends it', (tester) async {
      await _open(tester, _source());
      await tester.longPress(find.byType(NotesBulder).first);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pumpAndSettle();

      expect(_newNote, findsOneWidget);
      expect(_searchButton, findsOneWidget);
      expect(find.text('3 of 30 notes'), findsOneWidget);
    });

    testWidgets('delete moves the selection to the bin and says so', (
      tester,
    ) async {
      final source = _source();
      await _open(tester, source);
      await tester.longPress(find.byType(NotesBulder).first);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(source.deletedIds, hasLength(1));
      expect(find.byType(NotesBulder), findsNWidgets(2));
      expect(find.text('Note moved to the Recycle Bin'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // let the snack bar go
    });
  });

  group('the cards', () {
    testWidgets('empty editor save cannot mutate the repository note', (
      tester,
    ) async {
      final source = _source();
      await _open(tester, source);
      final before = source.byId('b')!.toMap();
      await tester.tap(find.text('IDEAS'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('note-title')), '');
      await tester.enterText(field('note-body'), '');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(source.saveCalls, 0);
      expect(source.byId('b')!.toMap(), before);
      expect(find.text('IDEAS'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets(
      'accepted editor save reaches the repository as a replacement',
      (tester) async {
        final source = _source();
        await _open(tester, source);
        final original = source.byId('b')!;
        await tester.tap(find.text('IDEAS'));
        await tester.pumpAndSettle();
        await tester.enterText(
          field('note-body'),
          'New draft',
        );
        expect(original.body, 'Build a rocket');
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(source.saveCalls, 1);
        expect(source.byId('b')!.body, 'New draft');
        expect(source.byId('b')!.dirty, isTrue);
        expect(original.body, 'Build a rocket');
      },
    );

    testWidgets('first pinned card spans the grid without duplicating notes', (
      tester,
    ) async {
      final source = _source();
      source.byId('b')!.pinned = true;
      await _open(tester, source);
      final featured = find.byWidgetPredicate(
        (widget) => widget is NotesBulder && widget.featured,
      );
      expect(featured, findsOneWidget);
      expect(tester.widget<NotesBulder>(featured).note.id, 'b');
      expect(find.byType(NotesBulder), findsNWidgets(3));
      expect(
        tester.getSize(featured).width,
        greaterThan(
          tester.getSize(find.byKey(const ValueKey('a'))).width * 1.8,
        ),
      );
      await tester.longPress(featured);
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
    });

    // Spec (Home layout): search moves into the header, above the strip
    // that holds the mascot; the chips follow the strip.
    testWidgets('search sits in the header above the mascot and the filters', (
      tester,
    ) async {
      await _open(tester, _source());
      await tester.pumpAndSettle();
      final search = tester.getRect(_searchButton);
      final mascot =
          tester.getRect(find.byKey(const ValueKey('mascot-character')));
      final filter = tester.getRect(find.byType(AtomicFilterChip).first);
      expect(search.bottom, lessThanOrEqualTo(mascot.top));
      expect(search.left, greaterThan(mascot.right));
      expect(filter.top, greaterThanOrEqualTo(mascot.bottom));
      expect(find.text('CHECKLIST'), findsNothing);
      expect(_newNote, findsOneWidget);
    });

    testWidgets('one creation button still respects capacity', (tester) async {
      await _open(tester, _source(limit: 3));
      await tester.tap(_newNote);
      await tester.pump();
      expect(find.textContaining("You've reached 3 notes"), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('narrow large-text layout keeps search and cards usable', (
      tester,
    ) async {
      final source = _source();
      final bloc = await _open(tester, source);
      tester.view.physicalSize = const Size(960, 2100);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: BlocProvider<NotesBloc>.value(
            value: bloc,
            child: const HomePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final search = tester.getRect(_searchButton);
      final mascot =
          tester.getRect(find.byKey(const ValueKey('mascot-character')));
      expect(search.bottom, lessThanOrEqualTo(mascot.top));
      expect(
        tester.getSize(find.byType(NotesBulder).first).width,
        greaterThan(270),
      );
    });

    testWidgets('card date and checklist progress reflect local note data', (
      tester,
    ) async {
      final source = _source();
      source.byId('a')!.updatedAt = DateTime(2020, 9, 3, 7, 10);
      source.byId('a')!.items.first.done = true;
      await _open(tester, source);
      expect(find.text('2020-09-03'), findsOneWidget);
      expect(find.text('1 / 2 DONE'), findsOneWidget);
    });

    testWidgets('ticking a checklist row saves the note', (tester) async {
      final source = _source();
      await _open(tester, source);
      final note = source.byId('a')!;

      await tester.tap(find.text('milk'));
      await tester.pump();
      await tester.pump();

      expect(note.items.first.done, isTrue);
      expect(source.saveCalls, 1);
    });
  });

  group('how much it rebuilds', () {
    testWidgets(
      'a store that only says "syncing" rebuilds no card; a changed note rebuilds the cards',
      (tester) async {
        final source = _source();
        await _open(tester, source);

        var cardRebuilds = 0;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          if (element.widget is NotesBulder) cardRebuilds++;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = null);

        // What a real sync sends at its start and at its end, with nothing on screen changed.
        source.poke();
        await tester.pump();
        source.poke();
        await tester.pump();
        await tester.pump();
        expect(cardRebuilds, 0);

        // An edit changes what a card shows, so the cards are rebuilt.
        source.byId('c')!.title = 'Trip to the sea';
        await source.save(source.byId('c')!);
        await tester.pump();
        await tester.pump();
        expect(cardRebuilds, greaterThan(0));
      },
    );

    /// Counts how often each named part of the screen is rebuilt while [act] runs.
    ///
    /// The strip, chips, grid and new-note button are built once in
    /// [_HomePageState.initState] and never touched again; the Bloc widgets rebuild
    /// *inside* them, so their own elements never go through `rebuild()`. Instead this
    /// watches the cards, the status strip, the filter chips and the new-note button.
    Future<Map<String, int>> rebuilds(
      WidgetTester tester,
      Future<void> Function() act,
    ) async {
      final counts = <String, int>{};
      void mark(String name) => counts[name] = (counts[name] ?? 0) + 1;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final widget = element.widget;
        if (widget is NotesBulder) mark('cards');
        if (widget is StatusStrip &&
            widget.key == const ValueKey('notes-usage')) {
          mark('usage');
        }
        if (widget is AtomicFilterChip) mark('chips');
        if (widget is AtomicFab) mark('newNote');
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      await act();
      await tester.pump();
      await tester.pump();
      return counts;
    }

    testWidgets('typing in the search box rebuilds the list and nothing else', (
      tester,
    ) async {
      await _open(tester, _source());
      await _openSearch(tester);

      final counts = await rebuilds(
        tester,
        () => tester.enterText(find.byType(TextField), 'rocket'),
      );

      expect(counts['cards'], greaterThan(0));
      expect(counts['usage'], isNull);
      expect(counts['chips'], isNull);
      expect(counts['newNote'], isNull);
    });

    testWidgets(
      'ticking a checklist row rebuilds the list and the count, not the chips or the add menu',
      (tester) async {
        await _open(tester, _source());

        final counts = await rebuilds(
          tester,
          () => tester.tap(find.text('milk')),
        );

        expect(counts['cards'], greaterThan(0));
        expect(counts['usage'], greaterThan(0)); // "1 UNSYNCED" appears
        expect(counts['chips'], isNull);
        expect(counts['newNote'], isNull);
      },
    );

    testWidgets(
      'changing the filter rebuilds the chips and the list, not the count or the add menu',
      (tester) async {
        await _open(tester, _source());

        final counts = await rebuilds(
          tester,
          () => tester.tap(find.widgetWithText(AtomicFilterChip, 'Notes')),
        );

        expect(counts['chips'], greaterThan(0));
        expect(counts['cards'], greaterThan(0));
        expect(counts['usage'], isNull);
        expect(counts['newNote'], isNull);
      },
    );
  });
}
