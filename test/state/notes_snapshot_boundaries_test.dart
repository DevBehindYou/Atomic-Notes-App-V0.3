// F09 characterization, boundary cases (Codex packet-4 follow-ups): what
// NotesBloc shows on main 9c2c23d for the cases the 148-state golden does not
// reach. Like the golden, these expectations are frozen before the
// single-pass snapshot refactor (F09 option A) and must hold unchanged after
// it. The real repository and disposable Hive are used wherever the
// repository decides what is visible; the shared in-memory source only for
// the sync fields that the repository sets from the network.

import 'dart:io';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/state/ui_message.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../notes_repository_lifecycle_test.dart' show TestApi, TestVault;
import '../support/fake_notes_source.dart';

final _t0 = DateTime.utc(2026, 1, 1);

Note _note(String id,
    {String? title,
    String body = '',
    List<String> tags = const [],
    int minute = 0,
    bool pinned = false}) {
  final base = Note(
      id: id,
      title: title ?? 'Synthetic $id',
      body: body,
      createdAt: _t0.add(Duration(minutes: minute)),
      pinned: pinned);
  if (tags.isEmpty) return base;
  return (NoteDocument.fromNote(base)..setTags(tags)).toNote(base);
}

Note _retagged(Note note, List<String> tags) =>
    (NoteDocument.fromNote(note)..setTags(tags)).toNote(note);

List<String> _ids(NotesState s) => [for (final n in s.notes) n.id];

Map<String, int> _types(NotesState s) =>
    {for (final e in s.typeCounts.entries) e.key.name: e.value};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late TestApi api;
  late TestVault vault;
  late NotesRepository repository;
  late NotesBloc bloc;

  Future<void> open({bool unlocked = false}) async {
    directory = await Directory.systemTemp.createTemp('atomic-f09-bounds-');
    Hive.init(directory.path);
    final box = await Hive.openBox('f09-bounds-notes');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('f09-bounds-sync');
    api = TestApi();
    vault = TestVault()..unlocked = unlocked;
    repository = NotesRepository.forTest(
        box: box,
        api: api,
        vault: vault,
        checkConnectivity: () async => [ConnectivityResult.wifi]);
    await repository.start();
    bloc = NotesBloc(
        source: repository,
        isSyncEnabled: () => false,
        isOnline: () async => true);
  }

  tearDown(() async {
    await bloc.close();
    await repository.stop(waitForSync: true);
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<NotesState> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return bloc.state;
  }

  Future<NotesState> send(NotesEvent event) {
    bloc.add(event);
    return settle();
  }

  test('an empty library: nothing on view, every count zero', () async {
    await open();
    var s = bloc.state;
    expect(_ids(s), isEmpty);
    expect(_types(s), {'all': 0, 'notes': 0, 'todos': 0});
    expect(s.tagCounts, isEmpty);
    expect([s.count, s.pending, s.binCount], [0, 0, 0]);
    expect(s.signature, noteSignature(const []));
    s = await send(const NotesTagFilterChanged('Work'));
    expect(s.tag, isNull, reason: 'no live note carries the tag');
    s = await send(const NotesTypeFilterChanged(NoteTypeFilter.todos));
    s = await send(const NotesSortChanged(NoteSort.oldest));
    s = await send(const NotesQueryChanged('anything'));
    expect(_ids(s), isEmpty);
    expect(
        [s.type, s.sort, s.tag, s.query],
        [NoteTypeFilter.todos, NoteSort.oldest, null, 'anything']);
  });

  test('vault-protected notes leave the view and the counts while locked',
      () async {
    await open(unlocked: true);
    await repository.save(_note('p1', tags: ['Work'], minute: 1));
    await repository.save(_note('p2', minute: 2));
    var s = await send(const NoteSelectionToggled('p1'));
    expect(_ids(s), ['p2', 'p1']);
    expect(s.selected, {'p1'});

    await repository.lockVault();
    s = await settle();
    expect(_ids(s), isEmpty, reason: 'sealed rows are not opened while locked');
    expect(_types(s), {'all': 0, 'notes': 0, 'todos': 0});
    expect(s.tagCounts, isEmpty);
    expect(s.count, 0);
    expect(s.selected, isEmpty, reason: 'a hidden note leaves the selection');

    await repository.save(_note('t1', minute: 3)); // new plaintext while locked
    s = await settle();
    expect(_ids(s), ['t1']);
    expect(s.count, 1);

    vault.unlocked = true;
    await repository.reloadAfterUnlock();
    s = await settle();
    expect(_ids(s), ['t1', 'p2', 'p1']);
    expect(s.count, 3);
    expect(s.tagCounts, {'Work': 1});
  });

  test('clearing memory or another account empties the view and the counts',
      () async {
    await open();
    await repository.save(_note('a', tags: ['Work']));
    await repository.save(_note('b', minute: 1));
    await repository.deleteNotes(['b']);
    var s = await settle();
    expect([s.count, s.binCount], [1, 1]);

    repository.clearMemory();
    s = await settle();
    expect(_ids(s), isEmpty);
    expect([s.count, s.pending, s.binCount], [0, 0, 0]);
    expect(s.tagCounts, isEmpty);
  });

  test('another account sees nothing of this cache', () async {
    await open();
    await repository.save(_note('a', tags: ['Work']));
    await send(const NotesTagFilterChanged('Work'));
    api.user = 'user-b';
    api.sessionRevision++;
    final s = await send(const NotesQueryChanged('synthetic'));
    expect(_ids(s), isEmpty);
    expect(_types(s), {'all': 0, 'notes': 0, 'todos': 0});
    expect(s.tagCounts, isEmpty);
    expect([s.count, s.pending, s.binCount], [0, 0, 0]);
    expect(s.tag, isNull);
  });

  test('a selected tag that no note carries any more falls back; the order '
      'and the search stay', () async {
    await open();
    final x = _note('x', title: 'Alpha one', tags: ['Work'], minute: 1);
    await repository.save(x);
    await repository.save(_note('y', title: 'Alpha two', tags: ['Home'], minute: 2));
    await send(const NotesSortChanged(NoteSort.oldest));
    await send(const NotesTagFilterChanged('Work'));
    var s = await send(const NotesQueryChanged('alpha'));
    expect(_ids(s), ['x']);

    await repository.save(_retagged(x, ['Home'])); // retag the only Work note
    s = await settle();
    expect(s.tag, isNull);
    expect([s.sort, s.query], [NoteSort.oldest, 'alpha']);
    expect(_ids(s), ['x', 'y']);
    expect(s.tagCounts, {'Home': 2});

    await send(const NotesTagFilterChanged('Home'));
    s = await send(const NotesQueryChanged('two'));
    expect(_ids(s), ['y']);
    await repository.deleteNotes(['x']); // Home is still carried by y
    s = await settle();
    expect(s.tag, 'Home');
    await repository.deleteNotes(['y']); // now nobody carries it
    s = await settle();
    expect(s.tag, isNull);
    expect([s.sort, s.query], [NoteSort.oldest, 'two']);
    expect(_ids(s), isEmpty);
  });

  test('a note hidden by the search still changes the counts', () async {
    await open();
    await repository.save(_note('z', title: 'Zebra', minute: 1));
    var s = await send(const NotesQueryChanged('zebra'));
    final before = s;
    expect(_ids(s), ['z']);

    await repository.save(_note('h', title: 'Hidden', tags: ['Plans'], minute: 2));
    s = await settle();
    expect(_ids(s), ['z'], reason: 'the search still hides it');
    expect(s.signature, before.signature);
    expect(s, isNot(before), reason: 'the counts are part of what is shown');
    expect(_types(s), {'all': 2, 'notes': 2, 'todos': 0});
    expect(s.tagCounts, {'Plans': 1});
    expect(s.count, 2);

    await repository.deleteNotes(['h']);
    s = await settle();
    expect(_ids(s), ['z']);
    expect(_types(s), {'all': 1, 'notes': 1, 'todos': 0});
    expect(s.tagCounts, isEmpty);
    expect([s.count, s.binCount], [1, 1]);
  });

  test('a content change with the same notes on view changes the signature',
      () async {
    await open();
    final a = _note('a', body: 'First words', minute: 1);
    await repository.save(a);
    await repository.save(_note('b', minute: 2));
    final before = await settle();
    a.body = 'Second words';
    await repository.save(a);
    final after = await settle();
    expect(_ids(after), _ids(before));
    expect(after.signature, isNot(before.signature));
    expect(after, isNot(before));
  });

  test('equal timestamps: pinned first, then the order notes were first saved',
      () async {
    await open();
    // Characterizes List.sort on today's small lists (ties keep the store's
    // insertion order); it is not a promise for large libraries.
    for (final id in ['u1', 'p2', 'u2', 'p1']) {
      await repository.save(_note(id, pinned: id.startsWith('p')));
    }
    var s = await settle();
    expect(_ids(s), ['p2', 'p1', 'u1', 'u2']);
    s = await send(const NotesSortChanged(NoteSort.oldest));
    expect(_ids(s), ['p2', 'p1', 'u1', 'u2']);
    await repository.save(_note('u1')); // saving again keeps its place
    s = await settle();
    expect(_ids(s), ['p2', 'p1', 'u1', 'u2']);
  });

  test('mixed rich and legacy notes: types, tags and search', () async {
    await open();
    await repository.save(Note(
        id: 'legacy-todo',
        kind: NoteKind.todo,
        title: 'Errands',
        createdAt: _t0,
        items: [TodoItem(text: 'Buy paint'), TodoItem(text: 'Post parcel', done: true)]));
    await repository.save(_note('legacy-text', title: 'Diary', body: 'Paint the fence', minute: 1));
    final mixedBase = Note(id: 'rich-mixed', title: 'Plan', body: 'Intro', createdAt: _t0.add(const Duration(minutes: 2)));
    final mixed = NoteDocument.fromNote(mixedBase)..setTags(['Home']);
    final row = mixed.insertChecklistAfter(0);
    mixed.replaceText(row, 'Sand the door');
    await repository.save(mixed.toNote(mixedBase));
    await repository.save(_note('rich-text', title: 'Ideas', body: 'Paint colours', tags: ['Home', 'Work'], minute: 3));

    var s = await settle();
    expect(_ids(s), ['rich-text', 'rich-mixed', 'legacy-text', 'legacy-todo']);
    expect(_types(s), {'all': 4, 'notes': 3, 'todos': 2});
    expect(s.tagCounts, {'Home': 2, 'Work': 1});
    s = await send(const NotesTypeFilterChanged(NoteTypeFilter.todos));
    expect(_ids(s), ['rich-mixed', 'legacy-todo']);
    s = await send(const NotesQueryChanged('paint'));
    expect(_ids(s), ['legacy-todo']);
    s = await send(const NotesTypeFilterChanged(NoteTypeFilter.all));
    expect(_ids(s), ['rich-text', 'legacy-text', 'legacy-todo']);
    s = await send(const NotesQueryChanged('door'));
    expect(_ids(s), ['rich-mixed']);
  });

  group('sync fields the golden summary omits (in-memory source)', () {
    test('a sync error reaches the state and clears, keeping the view',
        () async {
      // Set up the shared state only to satisfy tearDown.
      await open();
      final source = FakeNotesSource(notes: [
        _note('a', title: 'Trip'),
        _note('b', minute: 1),
      ]);
      final fake = NotesBloc(
          source: source,
          isSyncEnabled: () => true,
          isOnline: () async => true);
      addTearDown(fake.close);
      fake.add(const NotesQueryChanged('trip'));
      await Future<void>.delayed(Duration.zero);
      final states = <NotesState>[];
      final subscription = fake.stream.listen(states.add);
      addTearDown(subscription.cancel);

      source.changeBehindTheScenes(() => source.lastError = 'Synthetic failure');
      await Future<void>.delayed(Duration.zero);
      expect(fake.state.syncError, 'Synthetic failure');
      expect([fake.state.query, _ids(fake.state)], ['trip', ['a']]);
      source.poke();
      await Future<void>.delayed(Duration.zero);
      expect(states, hasLength(1), reason: 'an unchanged error is no new state');

      source.changeBehindTheScenes(() => source.lastError = null);
      await Future<void>.delayed(Duration.zero);
      expect(fake.state.syncError, isNull);
      expect(states, hasLength(2));
      expect(_ids(fake.state), ['a']);
    });
  });
}
