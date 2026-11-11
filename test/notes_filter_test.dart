// The Home filter, order and count contract (redesign ADR-012; review
// CX-C-4/C-5; corrections package risks R01–R06). The store is a fake in
// memory; the repository's own visible() is covered by its lifecycle and
// persistence tests.

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

Note _note(
  String id, {
  String title = '',
  NoteKind kind = NoteKind.text,
  List<TodoItem>? items,
  List<String> tags = const [],
  bool checklist = false,
  bool pinned = false,
  required int day,
}) {
  final base = syncedNote(id,
      title: title,
      kind: kind,
      items: items,
      createdAt: DateTime.utc(2026, 9, day))
    ..pinned = pinned;
  if (tags.isEmpty && !checklist) return base;
  final document = NoteDocument.fromNote(base);
  if (tags.isNotEmpty) document.setTags(tags);
  if (checklist) {
    document
      ..insertChecklistAfter(0)
      ..replaceText(1, 'a task');
  }
  final note = document.toNote(base)..dirty = false;
  return note;
}

/// a: plain to-do, b: text (#work #personal), m: text with a checklist
/// (#personal), p: pinned text, oldest, t: text (#work), newest.
/// (Tags live in the rich document, which turns a to-do into a text note
/// with a checklist, so the plain to-do carries no tag.)
FakeNotesSource _source() => FakeNotesSource(notes: [
      _note('a',
          title: 'Groceries',
          kind: NoteKind.todo,
          items: [TodoItem(text: 'milk')],
          day: 3),
      _note('b', title: 'Ideas', tags: ['work', 'personal'], day: 2),
      _note('m', title: 'Mixed', tags: ['personal'], checklist: true, day: 4),
      _note('p', title: 'Pinned', pinned: true, day: 1),
      _note('t', title: 'Trip', tags: ['work'], day: 5),
    ]);

NotesBloc _bloc(FakeNotesSource source) => NotesBloc(
    source: source, isSyncEnabled: () => true, isOnline: () async => true);

List<String> _ids(NotesState s) => s.notes.map((n) => n.id).toList();

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeNotesSource source;
  late NotesBloc bloc;

  setUp(() {
    source = _source();
    bloc = _bloc(source);
  });
  tearDown(() async {
    await bloc.close();
    source.dispose();
  });

  group('counts', () {
    test('a mixed note counts under Notes and To-dos but once in All', () {
      expect(bloc.state.typeCounts, {
        NoteTypeFilter.all: 5,
        NoteTypeFilter.notes: 4, // b, m, p, t
        NoteTypeFilter.todos: 2, // a, m
      });
      expect(bloc.state.tagCounts, {'work': 2, 'personal': 2});
    });

    test('chip counts ignore search and filters; the result count follows them', () async {
      bloc.add(const NotesTypeFilterChanged(NoteTypeFilter.todos));
      bloc.add(const NotesQueryChanged('groc'));
      await _settle();
      expect(_ids(bloc.state), ['a']);
      expect(bloc.state.resultCount, 1);
      expect(bloc.state.typeCounts[NoteTypeFilter.all], 5);
      expect(bloc.state.tagCounts['personal'], 2);
    });

    test('R01: counts change when a hidden note changes and the list on view does not', () async {
      bloc.add(const NotesQueryChanged('groc'));
      await _settle();
      final before = bloc.state;
      expect(_ids(before), ['a']);

      source.changeBehindTheScenes(() => source.all
          .add(_note('x', title: 'Hidden', tags: ['work'], day: 5)));
      await _settle();

      expect(_ids(bloc.state), ['a']);
      expect(bloc.state.signature, before.signature);
      expect(bloc.state.typeCounts[NoteTypeFilter.all], 6);
      expect(bloc.state.tagCounts['work'], 3);
    });

    test('R02: when the store no longer serves the notes, counts and tags empty', () async {
      bloc.add(const NotesTagFilterChanged('work'));
      await _settle();
      source.changeBehindTheScenes(() => source.all.clear());
      await _settle();
      expect(bloc.state.typeCounts[NoteTypeFilter.all], 0);
      expect(bloc.state.tagCounts, isEmpty);
      expect(bloc.state.tag, isNull);
      expect(bloc.state.notes, isEmpty);
    });
  });

  group('filters and order', () {
    test('type, tag, order and search compose independently', () async {
      bloc.add(const NotesTypeFilterChanged(NoteTypeFilter.notes));
      bloc.add(const NotesTagFilterChanged('personal'));
      await _settle();
      expect(_ids(bloc.state), ['m', 'b']);

      bloc.add(const NotesSortChanged(NoteSort.oldest));
      await _settle();
      expect(_ids(bloc.state), ['b', 'm']);
      expect(bloc.state.type, NoteTypeFilter.notes);
      expect(bloc.state.tag, 'personal');

      bloc.add(const NotesQueryChanged('mix'));
      await _settle();
      expect(_ids(bloc.state), ['m']);
      expect(bloc.state.sort, NoteSort.oldest);
      expect(bloc.state.narrowed, isTrue);
    });

    test('a tag matches exactly', () async {
      source.changeBehindTheScenes(() => source.all
          .add(_note('w', title: 'Workshop', tags: ['workshop'], day: 6)));
      await _settle();
      bloc.add(const NotesTagFilterChanged('work'));
      await _settle();
      expect(_ids(bloc.state), unorderedEquals(['b', 't']));
    });

    test('pinned notes come first in both orders', () async {
      expect(_ids(bloc.state).first, 'p');
      bloc.add(const NotesSortChanged(NoteSort.oldest));
      await _settle();
      expect(_ids(bloc.state), ['p', 'b', 'a', 'm', 't']);
    });

    test('R04: when the selected tag disappears only the tag clears', () async {
      bloc.add(const NotesTypeFilterChanged(NoteTypeFilter.notes));
      bloc.add(const NotesSortChanged(NoteSort.oldest));
      bloc.add(const NotesTagFilterChanged('personal'));
      bloc.add(const NotesQueryChanged('i'));
      await _settle();

      source.changeBehindTheScenes(() {
        source.all.removeWhere((n) => n.id == 'b' || n.id == 'm');
      });
      await _settle();

      expect(bloc.state.tag, isNull);
      expect(bloc.state.type, NoteTypeFilter.notes);
      expect(bloc.state.sort, NoteSort.oldest);
      expect(bloc.state.query, 'i');
      expect(_ids(bloc.state), ['p', 't']);
    });

    test('a tag missing only from the search results stays selected', () async {
      bloc.add(const NotesTagFilterChanged('personal'));
      bloc.add(const NotesQueryChanged('nothing matches this'));
      await _settle();
      expect(bloc.state.notes, isEmpty);
      expect(bloc.state.tag, 'personal');
    });

    test('reset clears order, type, tag, search and selection', () async {
      bloc.add(const NotesSortChanged(NoteSort.oldest));
      bloc.add(const NotesTypeFilterChanged(NoteTypeFilter.todos));
      bloc.add(const NotesTagFilterChanged('work'));
      bloc.add(const NotesQueryChanged('groc'));
      bloc.add(const NoteSelectionToggled('a'));
      await _settle();

      bloc.add(const NotesViewReset());
      await _settle();
      expect(bloc.state.sort, NoteSort.newest);
      expect(bloc.state.type, NoteTypeFilter.all);
      expect(bloc.state.tag, isNull);
      expect(bloc.state.query, isEmpty);
      expect(bloc.state.selecting, isFalse);
      expect(bloc.state.narrowed, isFalse);
    });
  });

  group('R05: the legacy filter keeps its meaning', () {
    test('NotesFilterChanged sets the old type and order', () async {
      bloc.add(const NotesFilterChanged(NoteFilter.oldest));
      await _settle();
      expect(bloc.state.sort, NoteSort.oldest);
      expect(bloc.state.type, NoteTypeFilter.all);
      expect(bloc.state.filter, NoteFilter.oldest);
      expect(bloc.state.narrowed, isFalse);

      bloc.add(const NotesFilterChanged(NoteFilter.todos));
      await _settle();
      expect(bloc.state.type, NoteTypeFilter.todos);
      expect(bloc.state.sort, NoteSort.newest);
      expect(bloc.state.filter, NoteFilter.todos);
      expect(_ids(bloc.state), ['m', 'a']);
    });

    test('visible(filter:) equals visible(type:, sort:) for every old value', () {
      for (final f in NoteFilter.values) {
        expect(source.visible(filter: f).map((n) => n.id).toList(),
            source.visible(type: f.type, sort: f.sort).map((n) => n.id).toList(),
            reason: f.name);
      }
    });

    test('the old value for each type and order', () {
      expect(NoteFilterParts.of(NoteTypeFilter.all, NoteSort.newest), NoteFilter.newest);
      expect(NoteFilterParts.of(NoteTypeFilter.all, NoteSort.oldest), NoteFilter.oldest);
      expect(NoteFilterParts.of(NoteTypeFilter.todos, NoteSort.oldest), NoteFilter.todos);
      expect(NoteFilterParts.of(NoteTypeFilter.notes, NoteSort.newest), NoteFilter.notes);
    });
  });

  group('R06: selection never reaches a note off screen', () {
    test('a search or filter change clears the selection and says so', () async {
      bloc.add(const NoteSelectionToggled('a'));
      bloc.add(const NoteSelectionToggled('b'));
      await _settle();
      expect(bloc.state.selected, {'a', 'b'});

      bloc.add(const NotesQueryChanged('ideas'));
      await _settle();
      expect(bloc.state.selected, isEmpty);
      expect(bloc.state.notice?.text, 'Selection cleared');

      bloc.add(const NoteSelectionToggled('b'));
      await _settle();
      bloc.add(const NotesTagFilterChanged('work'));
      await _settle();
      expect(bloc.state.selected, isEmpty);
    });

    test('a change of order keeps the selection', () async {
      bloc.add(const NoteSelectionToggled('a'));
      await _settle();
      bloc.add(const NotesSortChanged(NoteSort.oldest));
      await _settle();
      expect(bloc.state.selected, {'a'});
    });

    test('Delete after a search acts only on notes still on view', () async {
      bloc.add(const NoteSelectionToggled('a'));
      await _settle();
      bloc.add(const NotesQueryChanged('ideas'));
      await _settle();
      bloc.add(const NoteSelectionToggled('b'));
      await _settle();

      bloc.add(const NotesDeleteSelected());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.deletedIds, ['b']);
    });

    test('an outside change keeps only selected notes still on view', () async {
      bloc.add(const NotesTagFilterChanged('personal'));
      await _settle();
      bloc.add(const NoteSelectionToggled('b'));
      bloc.add(const NoteSelectionToggled('m'));
      await _settle();
      expect(bloc.state.selected, {'b', 'm'});

      source.changeBehindTheScenes(() {
        final i = source.all.indexWhere((n) => n.id == 'm');
        source.all[i] = _note('m', title: 'Mixed', tags: ['work'], checklist: true, day: 4);
      });
      await _settle();
      expect(bloc.state.selected, {'b'});
    });
  });
}
