// The notes state: what the screens show, and when it changes. The store is a fake in memory,
// so these need neither Hive nor the network.

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

NotesBloc _bloc(
  FakeNotesSource source, {
  bool syncOn = true,
  bool online = true,
}) =>
    NotesBloc(
      source: source,
      isSyncEnabled: () => syncOn,
      isOnline: () async => online,
      instantSyncCost: () => 10,
    );

FakeNotesSource _source() => FakeNotesSource(notes: [
      syncedNote('a',
          title: 'Groceries',
          kind: NoteKind.todo,
          items: [TodoItem(text: 'milk'), TodoItem(text: 'bread')],
          createdAt: DateTime.utc(2026, 9, 3)),
      syncedNote('b',
          title: 'Ideas',
          body: 'Build a Rocket',
          createdAt: DateTime.utc(2026, 9, 2)),
      syncedNote('c', title: 'Trip', createdAt: DateTime.utc(2026, 9, 1)),
    ]);

List<String> _ids(NotesState s) => s.notes.map((n) => n.id).toList();

void main() {
  group('what is shown', () {
    test('starts from the store: newest first, with the counts', () {
      final bloc = _bloc(_source());
      addTearDown(bloc.close);
      expect(_ids(bloc.state), ['a', 'b', 'c']);
      expect(bloc.state.count, 3);
      expect(bloc.state.limit, 30);
      expect(bloc.state.pending, 0);
      expect(bloc.state.usageLabel, '3 / 30');
      expect(bloc.state.isAtLimit, isFalse);
    });

    blocTest<NotesBloc, NotesState>(
      'the oldest filter reverses the order',
      build: () => _bloc(_source()),
      act: (bloc) => bloc.add(const NotesFilterChanged(NoteFilter.oldest)),
      expect: () => [
        isA<NotesState>()
            .having((s) => s.filter, 'filter', NoteFilter.oldest)
            .having(_ids, 'ids', ['c', 'b', 'a']),
      ],
    );

    blocTest<NotesBloc, NotesState>(
      'the to-dos filter keeps only checklists',
      build: () => _bloc(_source()),
      act: (bloc) => bloc.add(const NotesFilterChanged(NoteFilter.todos)),
      expect: () => [
        isA<NotesState>()
            .having(_ids, 'ids', ['a'])
            .having((s) => s.narrowed, 'narrowed', isTrue),
      ],
    );

    blocTest<NotesBloc, NotesState>(
      'the notes filter keeps only text notes',
      build: () => _bloc(_source()),
      act: (bloc) => bloc.add(const NotesFilterChanged(NoteFilter.notes)),
      expect: () => [
        isA<NotesState>().having(_ids, 'ids', ['b', 'c']),
      ],
    );

    blocTest<NotesBloc, NotesState>(
      'search looks in the title, the body and the checklist items, without caring about case',
      build: () => _bloc(_source()),
      act: (bloc) async {
        bloc.add(const NotesQueryChanged('ROCKET')); // body
        await Future<void>.delayed(Duration.zero);
        bloc.add(const NotesQueryChanged('milk')); // item
        await Future<void>.delayed(Duration.zero);
        bloc.add(const NotesQueryChanged('trip')); // title
      },
      expect: () => [
        isA<NotesState>().having(_ids, 'body match', ['b']),
        isA<NotesState>().having(_ids, 'item match', ['a']),
        isA<NotesState>().having(_ids, 'title match', ['c']),
      ],
    );

    blocTest<NotesBloc, NotesState>(
      'a search that matches nothing leaves an empty, narrowed list',
      build: () => _bloc(_source()),
      act: (bloc) => bloc.add(const NotesQueryChanged('zebra')),
      expect: () => [
        isA<NotesState>()
            .having((s) => s.notes, 'notes', isEmpty)
            .having((s) => s.narrowed, 'narrowed', isTrue),
      ],
    );

    test('the limit and the counts follow the store', () async {
      final source = FakeNotesSource(notes: _source().all, limit: 3);
      final bloc = _bloc(source);
      addTearDown(bloc.close);
      expect(bloc.state.isAtLimit, isTrue);

      source.changeBehindTheScenes(() => source.limit = 30);
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.limit, 30);
      expect(bloc.state.isAtLimit, isFalse);
      expect(bloc.state.usageLabel, '3 / 30');
    });
  });

  group('when the screen rebuilds', () {
    test('a poke without a change emits no state', () async {
      final source = _source();
      final bloc = _bloc(source);
      addTearDown(bloc.close);
      final seen = <NotesState>[];
      final sub = bloc.stream.listen(seen.add);
      addTearDown(sub.cancel);

      source.poke();
      source.poke();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(seen, isEmpty);
    });

    test('an edit is one new state, with the note waiting to sync', () async {
      final source = _source();
      final bloc = _bloc(source);
      addTearDown(bloc.close);
      final seen = <NotesState>[];
      final sub = bloc.stream.listen(seen.add);
      addTearDown(sub.cancel);
      final before = bloc.state.signature;

      final note = source.byId('c')!..title = 'Trip to the sea';
      bloc.add(NoteSaved(note));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(seen, hasLength(1));
      expect(seen.single.pending, 1);
      expect(seen.single.signature, isNot(before));
    });

    test('ticking a checklist row saves the note once', () async {
      final source = _source();
      final bloc = _bloc(source);
      addTearDown(bloc.close);
      final note = source.byId('a')!;

      bloc.add(NoteItemToggled(note, 1));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(note.items[1].done, isTrue);
      expect(note.items[0].done, isFalse);
      expect(source.saveCalls, 1);
      expect(bloc.state.pending, 1);
    });
  });

  group('selection', () {
    blocTest<NotesBloc, NotesState>(
      'a long press selects, a second one on the same note unselects',
      build: () => _bloc(_source()),
      act: (bloc) async {
        bloc.add(const NoteSelectionToggled('a'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const NoteSelectionToggled('a'));
      },
      expect: () => [
        isA<NotesState>()
            .having((s) => s.selected, 'selected', {'a'})
            .having((s) => s.selecting, 'selecting', isTrue),
        isA<NotesState>().having((s) => s.selecting, 'selecting', isFalse),
      ],
    );

    blocTest<NotesBloc, NotesState>(
      '"all" selects everything on view, and a second "all" clears it',
      build: () => _bloc(_source()),
      act: (bloc) async {
        bloc.add(const NoteSelectionAllToggled());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const NoteSelectionAllToggled());
      },
      expect: () => [
        isA<NotesState>().having((s) => s.selected, 'selected', {'a', 'b', 'c'}),
        isA<NotesState>().having((s) => s.selected, 'selected', isEmpty),
      ],
    );

    blocTest<NotesBloc, NotesState>(
      '"all" only takes what the search shows',
      build: () => _bloc(_source()),
      act: (bloc) async {
        bloc.add(const NotesQueryChanged('o')); // Groceries, Ideas' body, not Trip
        await Future<void>.delayed(Duration.zero);
        bloc.add(const NoteSelectionAllToggled());
      },
      verify: (bloc) {
        final shown = bloc.state.notes.map((n) => n.id).toSet();
        expect(bloc.state.selected, shown);
        expect(shown, isNot(contains('c')));
      },
    );

    blocTest<NotesBloc, NotesState>(
      'cancel clears the selection',
      build: () => _bloc(_source()),
      seed: () => const NotesState(selected: {'a', 'b'}),
      act: (bloc) => bloc.add(const NoteSelectionCleared()),
      expect: () => [
        isA<NotesState>().having((s) => s.selected, 'selected', isEmpty),
      ],
    );

    test('a note deleted behind the screen leaves the selection', () async {
      final source = _source();
      final bloc = _bloc(source);
      addTearDown(bloc.close);
      bloc.add(const NoteSelectionToggled('a'));
      bloc.add(const NoteSelectionToggled('b'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.selected, {'a', 'b'});

      source.changeBehindTheScenes(() => source.byId('a')!.deleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.selected, {'b'});
      expect(_ids(bloc.state), ['b', 'c']);
    });

    test('deleting the selection moves the notes to the bin and says how many', () async {
      final source = _source();
      final bloc = _bloc(source);
      addTearDown(bloc.close);
      bloc.add(const NoteSelectionToggled('a'));
      bloc.add(const NoteSelectionToggled('b'));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const NotesDeleteSelected());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(source.deletedIds, unorderedEquals(['a', 'b']));
      expect(bloc.state.selecting, isFalse);
      expect(_ids(bloc.state), ['c']);
      expect(bloc.state.notice?.text, '2 notes moved to the Recycle Bin');
      expect(bloc.state.notice?.fromSync, isFalse);
    });

    test('one deleted note is worded in the singular', () async {
      final source = _source();
      final bloc = _bloc(source);
      addTearDown(bloc.close);
      bloc.add(const NoteSelectionToggled('c'));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const NotesDeleteSelected());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.notice?.text, 'Note moved to the Recycle Bin');
    });

    test('opening the screen afresh resets the filter, the search and the selection', () async {
      final bloc = _bloc(_source());
      addTearDown(bloc.close);
      bloc.add(const NotesFilterChanged(NoteFilter.todos));
      bloc.add(const NotesQueryChanged('milk'));
      bloc.add(const NoteSelectionToggled('a'));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const NotesViewReset());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.filter, NoteFilter.newest);
      expect(bloc.state.query, isEmpty);
      expect(bloc.state.selecting, isFalse);
      expect(_ids(bloc.state), ['a', 'b', 'c']);
    });
  });

  group('the sync button', () {
    Future<NotesState> press(
      FakeNotesSource source, {
      bool syncOn = true,
      bool online = true,
    }) async {
      final bloc = _bloc(source, syncOn: syncOn, online: online);
      addTearDown(bloc.close);
      bloc.add(const NotesSyncRequested(instant: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return bloc.state;
    }

    test('with cloud sync off it says so and does not sync', () async {
      final source = _source();
      final state = await press(source, syncOn: false);
      expect(state.notice?.text, 'Cloud Sync is Off');
      expect(state.notice?.millis, 1000);
      expect(state.notice?.fromSync, isTrue);
      expect(state.syncing, isFalse);
      expect(source.syncCalls, 0);
    });

    test('offline it says so and does not sync', () async {
      final source = _source();
      final state = await press(source, online: false);
      expect(state.notice?.text, 'No Internet Connection!');
      expect(state.syncing, isFalse);
      expect(source.syncCalls, 0);
    });

    test('with changes waiting it syncs instantly and names the price', () async {
      final source = _source();
      source.byId('c')!.touch();
      final state = await press(source);
      expect(source.syncCalls, 1);
      expect(source.lastSyncInstant, isTrue);
      expect(state.notice?.text, 'Instant sync  ·  -10 energy');
      expect(state.notice?.millis, 1600);
      expect(state.pending, 0);
      expect(state.syncing, isFalse);
    });

    test('with nothing waiting it says the notes are up to date', () async {
      final state = await press(_source());
      expect(state.notice?.text, 'Already up to date');
    });

    test('a failed sync shows the reason the store gave', () async {
      final source = _source()
        ..syncResult = false
        ..lastError = 'Not enough Atomic Energy for this sync.';
      final state = await press(source);
      expect(state.notice?.text, 'Not enough Atomic Energy for this sync.');
      expect(state.notice?.millis, 3000);
    });

    test('a failed sync with no reason gets the general words', () async {
      final state = await press(_source()..syncResult = false);
      expect(state.notice?.text,
          'Sync failed — changes are still only on this device');
    });

    test('the button shows its spinner from the press until the sync ends', () async {
      final source = _source();
      final bloc = _bloc(source);
      addTearDown(bloc.close);
      final spinner = <bool>[];
      final sub = bloc.stream.map((s) => s.syncing).listen(spinner.add);
      addTearDown(sub.cancel);

      bloc.add(const NotesSyncRequested(instant: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(spinner.first, isTrue);
      expect(spinner.last, isFalse);
    });

    test('a second press while syncing does nothing', () async {
      final source = _source();
      final bloc = _bloc(source);
      addTearDown(bloc.close);

      bloc.add(const NotesSyncRequested(instant: true));
      bloc.add(const NotesSyncRequested(instant: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(source.syncCalls, 1);
    });

    test('two identical answers are two notices, so both are shown', () async {
      final source = _source();
      final bloc = _bloc(source);
      addTearDown(bloc.close);

      bloc.add(const NotesSyncRequested(instant: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final first = bloc.state.notice;
      bloc.add(const NotesSyncRequested(instant: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(bloc.state.notice?.text, first?.text);
      expect(bloc.state.notice, isNot(first));
    });
  });

  test('a closed bloc stops listening to the store', () async {
    final source = _source();
    final bloc = _bloc(source);
    await bloc.close();
    // Would throw if the closed bloc still added events.
    source.poke();
    await Future<void>.delayed(Duration.zero);
    expect(bloc.isClosed, isTrue);
  });
}
