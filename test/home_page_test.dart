// The notes screen, driven through the Bloc with a fake store: what it shows, what a tap does,
// and how little it rebuilds. It needs neither Hive nor the network.

import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/notes_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

FakeNotesSource _source({int limit = 30, bool empty = false}) => FakeNotesSource(
      limit: limit,
      notes: empty
          ? []
          : [
              syncedNote('a',
                  title: 'Groceries',
                  kind: NoteKind.todo,
                  items: [TodoItem(text: 'milk'), TodoItem(text: 'bread')],
                  createdAt: DateTime.utc(2026, 9, 3)),
              syncedNote('b',
                  title: 'Ideas',
                  body: 'Build a rocket',
                  createdAt: DateTime.utc(2026, 9, 2)),
              syncedNote('c', title: 'Trip', createdAt: DateTime.utc(2026, 9, 1)),
            ],
    );

Future<NotesBloc> _open(WidgetTester tester, FakeNotesSource source) async {
  // Tall, so everything is on view and nothing has to be scrolled to.
  tester.view.physicalSize = const Size(1290, 2700);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final bloc = NotesBloc(
    source: source,
    isSyncEnabled: () => true,
    isOnline: () async => true,
    instantSyncCost: () => 10,
  );
  addTearDown(bloc.close);
  await tester.pumpWidget(MaterialApp(
    home: BlocProvider<NotesBloc>.value(value: bloc, child: const HomePage()),
  ));
  await tester.pump();
  return bloc;
}

void main() {
  group('what the screen shows', () {
    testWidgets('a card for each note and the usage in the header', (tester) async {
      await _open(tester, _source());
      expect(find.byType(NotesBulder), findsNWidgets(3));
      expect(find.text('3 / 30'), findsOneWidget);
      // Card titles are set in capitals by the design system.
      expect(find.text('GROCERIES'), findsOneWidget);
      // The date/time moved into the editor; the card no longer carries it.
      expect(find.textContaining('2026-09'), findsNothing);
    });

    testWidgets('tapping the mascot opens a chat bubble that closes by itself', (tester) async {
      await _open(tester, _source());
      await tester.tap(find.byType(Image));
      await tester.pump();
      expect(find.text('All notes synced.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      expect(find.text('All notes synced.'), findsNothing);
    });

    testWidgets('a second tap closes the bubble', (tester) async {
      await _open(tester, _source());
      await tester.tap(find.byType(Image));
      await tester.pump();
      await tester.tap(find.byType(Image));
      await tester.pump();
      expect(find.text('All notes synced.'), findsNothing);
    });

    testWidgets('the bubble names the wait when automatic sync is closed', (tester) async {
      final source = _source()
        ..nextAutoSyncAt = DateTime.now().add(const Duration(minutes: 40));
      await _open(tester, source);
      await tester.tap(find.byType(Image));
      await tester.pump();
      expect(find.text('All synced. Next sync in 40 min.'), findsOneWidget);
    });

    testWidgets('the bubble counts changes that are waiting', (tester) async {
      final source = _source();
      await _open(tester, source);
      source.byId('c')!.touch();
      source.poke();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byType(Image));
      await tester.pump();
      // Nothing is running: the change waits (offline, or for the few seconds before auto-sync).
      expect(find.text('1 change waiting. It syncs by itself when you are online.'), findsOneWidget);
      expect(find.text('Syncing 1 change now.'), findsNothing);
    });

    testWidgets('on a short screen the header scrolls away with the notes', (tester) async {
      // A phone on its side: 800 x 360 logical pixels.
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bloc = NotesBloc(
        source: _source(),
        isSyncEnabled: () => true,
        isOnline: () async => true,
        instantSyncCost: () => 10,
      );
      addTearDown(bloc.close);
      await tester.pumpWidget(MaterialApp(
        home: BlocProvider<NotesBloc>.value(value: bloc, child: const HomePage()),
      ));
      await tester.pump();
      expect(find.byType(NestedScrollView), findsOneWidget);
      expect(find.text('NOTES').hitTestable(), findsWidgets);
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      // The title has scrolled off; the cards now have the screen.
      expect(find.text('NOTES').hitTestable(), findsNothing);
      expect(find.byType(NotesBulder).hitTestable(), findsWidgets);
    });

    testWidgets('on a tall screen the header stays put', (tester) async {
      await _open(tester, _source());
      expect(find.byType(NestedScrollView), findsNothing);
    });

    testWidgets('while a sync runs the bubble says it is syncing', (tester) async {
      final source = _source()..syncGate = Completer<void>();
      final bloc = await _open(tester, source);
      source.byId('c')!.touch();
      source.poke();
      await tester.pump();
      bloc.add(const NotesSyncRequested(instant: true));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byType(Image));
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
      expect(find.text('3 / 30 · 1 UNSYNCED'), findsOneWidget);
    });

    testWidgets('at the limit the header and the add menu say so', (tester) async {
      await _open(tester, _source(limit: 3));
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('3 NOTE LIMIT REACHED'), findsOneWidget);
    });

    testWidgets('a bought limit reaches the screen at once', (tester) async {
      final source = _source(limit: 3);
      await _open(tester, source);
      source.changeBehindTheScenes(() => source.limit = 30);
      await tester.pump();
      await tester.pump();
      expect(find.text('3 / 30'), findsOneWidget);
      expect(find.text('3 NOTE LIMIT REACHED'), findsNothing);
    });

    testWidgets('an empty account shows the invitation', (tester) async {
      await _open(tester, _source(empty: true));
      expect(find.byType(NotesBulder), findsNothing);
      expect(find.text('INDEX / EMPTY'), findsOneWidget);
    });
  });

  group('filter and search', () {
    testWidgets('the to-dos chip keeps only checklists', (tester) async {
      await _open(tester, _source());
      await tester.tap(find.text('TO-DOS'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(NotesBulder), findsOneWidget);
      expect(find.text('GROCERIES'), findsOneWidget);
    });

    testWidgets('a filter with no match says so', (tester) async {
      final source = FakeNotesSource(notes: [syncedNote('x', title: 'Only text')]);
      await _open(tester, source);
      await tester.tap(find.text('TO-DOS'));
      await tester.pump();
      await tester.pump();
      expect(find.text('FILTER / NO MATCH'), findsOneWidget);
    });

    testWidgets('typing narrows the list, the cross clears it', (tester) async {
      await _open(tester, _source());
      expect(find.byIcon(Icons.close), findsNothing);

      await tester.enterText(find.byType(TextField), 'rocket');
      await tester.pump();
      await tester.pump();
      expect(find.byType(NotesBulder), findsOneWidget);
      expect(find.text('IDEAS'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump();
      expect(find.byType(NotesBulder), findsNWidgets(3));
      expect(find.byIcon(Icons.close), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });
  });

  group('selecting', () {
    testWidgets('a long press starts selecting: the count, the actions, no chips, no add menu',
        (tester) async {
      await _open(tester, _source());
      expect(find.text('NEW NOTE'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.longPress(find.byType(NotesBulder).first);
      // The add menu slides out with the Scaffold's own animation.
      await tester.pumpAndSettle();

      expect(find.text('1 SELECTED'), findsOneWidget);
      expect(find.text('ALL'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('NEW NOTE'), findsNothing);
    });

    testWidgets('cancel ends it', (tester) async {
      await _open(tester, _source());
      await tester.longPress(find.byType(NotesBulder).first);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(find.text('NEW NOTE'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('3 / 30'), findsOneWidget);
    });

    testWidgets('delete moves the selection to the bin and says so', (tester) async {
      final source = _source();
      await _open(tester, source);
      await tester.longPress(find.byType(NotesBulder).first);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('DELETE'));
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
    testWidgets('a store that only says "syncing" rebuilds no card; a changed note rebuilds the cards',
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
    });

    /// Counts how often each named part of the screen is rebuilt while [act] runs.
    ///
    /// `_TitleRow`, `_FilterChips`, `_NotesGrid` and `_AddMenu` are built once in
    /// [_HomePageState.initState] and never touched again; the Bloc widgets rebuild
    /// *inside* them, so their own elements never go through `rebuild()`. Instead this
    /// watches what each part actually draws: the cards, the "Notes" / "N selected"
    /// heading, the filter chips and the "NEW NOTE" label.
    Future<Map<String, int>> rebuilds(
      WidgetTester tester,
      Future<void> Function() act,
    ) async {
      final counts = <String, int>{};
      void mark(String name) => counts[name] = (counts[name] ?? 0) + 1;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final widget = element.widget;
        if (widget is NotesBulder) mark('cards');
        if (widget is EditorialHeading && widget.style == AppType.headlineLg) {
          mark('heading');
        }
        if (widget is DataChip) mark('chips');
        if (widget is MonoLabel && widget.text == 'NEW NOTE') mark('newNote');
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      await act();
      await tester.pump();
      await tester.pump();
      return counts;
    }

    testWidgets('typing in the search box rebuilds the list and nothing else', (tester) async {
      await _open(tester, _source());

      final counts = await rebuilds(
          tester, () => tester.enterText(find.byType(TextField), 'rocket'));

      expect(counts['cards'], greaterThan(0));
      expect(counts['heading'], isNull);
      expect(counts['chips'], isNull);
      expect(counts['newNote'], isNull);
    });

    testWidgets('ticking a checklist row rebuilds the list and the count, not the chips or the add menu',
        (tester) async {
      await _open(tester, _source());

      final counts = await rebuilds(tester, () => tester.tap(find.text('milk')));

      expect(counts['cards'], greaterThan(0));
      expect(counts['heading'], greaterThan(0)); // "1 UNSYNCED" appears
      expect(counts['chips'], isNull);
      expect(counts['newNote'], isNull);
    });

    testWidgets('changing the filter rebuilds the chips and the list, not the count or the add menu',
        (tester) async {
      await _open(tester, _source());

      final counts = await rebuilds(tester, () => tester.tap(find.widgetWithText(DataChip, 'NOTES')));

      expect(counts['chips'], greaterThan(0));
      expect(counts['cards'], greaterThan(0));
      expect(counts['heading'], isNull);
      expect(counts['newNote'], isNull);
    });
  });
}
