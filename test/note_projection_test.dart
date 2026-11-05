import 'dart:convert';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/note_projection.dart';
import 'package:flutter_test/flutter_test.dart';

Note rich() {
  final original = Note(id: 'rich', body: 'Visible prose');
  final document = NoteDocument.fromNote(original)
    ..setTags(['Work', 'Launch', 'Plans'])
    ..insertChecklistAfter(0)
    ..replaceText(1, 'Ship task');
  document.replaceStyles(0, [const NoteStyleRun(0, 7, NoteTextStyle.bold)]);
  return document.toNote(original);
}

void main() {
  test(
      'unchanged rich card and search work validate once; no mutable draft escapes',
      () {
    var parses = 0;
    final cache = NoteProjectionCache(decode: (note) {
      parses++;
      return NoteDocument.fromNote(note);
    });
    final note = rich();
    final saved = jsonEncode(note.toMap());
    final first = cache.get(note);
    for (var i = 0; i < 8; i++) {
      expect(cache.get(note).matches('launch'), isTrue);
      expect(cache.get(note).matches('visible'), isTrue);
      expect(cache.get(note).matches('styles'), isFalse);
      expect(cache.get(note), same(first));
    }
    expect(parses, 1);
    expect(first.checklistCount, 1);
    expect(first.doneCount, 0);
    expect(() => first.previewLines.clear(), throwsUnsupportedError);
    expect(() => first.tags.clear(), throwsUnsupportedError);
    final editor = NoteDocument.fromNote(note)..replaceText(0, 'Unsaved draft');
    expect(editor.lines.first.text, 'Unsaved draft');
    expect(cache.get(note).matches('visible'), isTrue);
    expect(jsonEncode(note.toMap()), saved);
  });

  test(
      'in-place body kind item text done list and marker changes invalidate exactly',
      () {
    var parses = 0;
    final cache = NoteProjectionCache(decode: (n) {
      parses++;
      return NoteDocument.fromNote(n);
    });
    final note =
        Note(id: 'mutable', body: 'Original', items: [TodoItem(text: 'Task')]);
    expect(cache.get(note).matches('original'), isTrue);
    note.title = 'Title only';
    note.pinned = true;
    note.touch();
    cache.get(note);
    expect(parses, 1);
    note.body = 'Changed';
    expect(cache.get(note).matches('changed'), isTrue);
    note.kind = NoteKind.todo;
    cache.get(note);
    note.items.single.done = true;
    expect(cache.get(note).doneCount, 1);
    note.items.single.text = 'Renamed';
    expect(cache.get(note).matches('renamed'), isTrue);
    note.items.add(TodoItem(text: 'Added'));
    expect(cache.get(note).checklistCount, 2);
    note.items = [TodoItem(text: 'Replacement')];
    expect(cache.get(note).matches('replacement'), isTrue);
    note.kind = NoteKind.text;
    note.body = '- [x] Encoded';
    note.items = [TodoItem(text: NoteDocument.formatMarker)];
    expect(cache.get(note).doneCount, 1);
    note.items.single.done = true;
    expect(
        cache.get(note).doneCount, 1); // ordinary legacy item, no encoded task
    expect(cache.get(note).checklistCount, 1);
    expect(parses, 9);
  });

  test(
      'malformed rich images and styles stay unsupported and recover after body edit',
      () {
    final cache = NoteProjectionCache();
    final note = rich();
    final raw = jsonDecode(note.body) as Map<String, dynamic>;
    (raw['blocks'] as List).add({
      'text': '',
      'checklist': false,
      'done': false,
      'styles': [],
      'image': 'not-a-jpeg'
    });
    note.body = jsonEncode(raw);
    final invalid = cache.get(note);
    expect(invalid.isReadOnly, isTrue);
    expect(invalid.matches('unsupported note format'), isTrue);
    expect(invalid.tags, isEmpty);
    expect(invalid.matches('launch'), isFalse);
    note.body = rich().body;
    expect(cache.get(note).isReadOnly, isFalse);
    expect(cache.get(note).matches('launch'), isTrue);
    final badStyle = jsonDecode(note.body) as Map<String, dynamic>;
    badStyle['blocks'][0]['styles'] = [
      [0, 9999, 1]
    ];
    note.body = jsonEncode(badStyle);
    expect(cache.get(note).isReadOnly, isTrue);
  });

  test('legacy todo body remains searchable with original checklist indices',
      () {
    final note = Note(
        id: 'legacy',
        kind: NoteKind.todo,
        body: 'Legacy intro',
        items: [TodoItem(text: 'First', done: true), TodoItem(text: 'Second')]);
    final projection = NoteProjectionCache().get(note);
    expect(projection.matches('legacy intro'), isTrue);
    expect(projection.matches('second'), isTrue);
    expect(projection.previewLines.first.text, 'Legacy intro');
    expect(projection.checklistCount, 2);
    expect(projection.doneCount, 1);
  });

  test(
      'LRU entry and text budgets evict; prune and clear release former owners',
      () {
    var parses = 0;
    final cache = NoteProjectionCache(
        maxEntries: 2,
        maxTextUnits: 80,
        decode: (n) {
          parses++;
          return NoteDocument.fromNote(n);
        });
    final a = Note(id: 'same', body: 'Owner A');
    final b = Note(id: 'b', body: 'B');
    final c = Note(id: 'c', body: 'C');
    final first = cache.get(a);
    cache.get(b);
    cache.get(a);
    cache.get(c);
    expect(cache.get(a), same(first));
    cache.get(b);
    expect(parses, 4);
    cache.retainNotes({b.id: b});
    expect(cache.length, 1);
    cache.clear();
    expect(cache.length, 0);
    final ownerB = Note(id: 'same', body: 'Owner B');
    expect(cache.get(ownerB).matches('owner a'), isFalse);
    expect(cache.get(ownerB).matches('owner b'), isTrue);
    cache.get(Note(id: 'huge', body: 'x' * 100));
    expect(cache.length, 1); // oversized projection is never retained
    cache.clear();
    final again = cache.get(b);
    expect(again, isNot(same(first)));
  });

  test('scans larger than the cache leave visible card entries warm', () {
    final cache = NoteProjectionCache(maxEntries: 2);
    final notes = [for (var i = 0; i < 4; i++) Note(id: '$i', body: 'Note $i')];
    final card = cache.get(notes.last);
    for (var i = 0; i < 2; i++) {
      for (final note in notes) {
        expect(cache.get(note, evict: false).matches('note'), isTrue);
      }
    }
    expect(cache.length, 2);
    expect(cache.get(notes.last), same(card));
  });
}
