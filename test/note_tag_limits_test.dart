import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:flutter_test/flutter_test.dart';

Note _legacy(List<String> tags) => Note(
      id: 'legacy-tags',
      body: jsonEncode({
        'v': 2,
        'tags': tags,
        'blocks': [
          {
            'text': 'Keep this text',
            'checklist': false,
            'done': false,
            'styles': []
          }
        ],
      }),
      items: [TodoItem(text: NoteDocument.richFormatMarker)],
    );

void main() {
  test('three tags fit; a fourth is rejected without changing the draft', () {
    final note = Note(id: 'tag-count', body: 'Keep this text');
    final doc = NoteDocument.fromNote(note)..setTags(['one', 'two', 'three']);
    final before = doc.toNote(note).toMap();
    expect(
        () => doc.setTags([...doc.tags, 'four']),
        throwsA(isA<FormatException>().having(
            (error) => error.message, 'message', 'Use up to 3 tags per note')));
    expect(doc.toNote(note).toMap(), before);
    doc.setTags([' one ', 'ONE', 'two', 'three']);
    expect(doc.tags, ['one', 'two', 'three']);
    expect(NoteDocument.fromNote(doc.toNote(note)).tags, doc.tags);
  });

  test('15 characters fit; a 16-character tag is rejected atomically', () {
    final doc = NoteDocument.fromNote(Note(id: 'tag-length'))
      ..setTags(['123456789012345']);
    expect(() => doc.setTags(['1234567890123456']), throwsFormatException);
    expect(doc.tags, ['123456789012345']);
  });

  test('tag length counts complete visible Unicode characters across storage',
      () {
    final note = Note(id: 'unicode-tags');
    final tag = List.filled(15, '👨‍👩‍👧‍👦').join();
    final doc = NoteDocument.fromNote(note)..setTags([tag]);
    final saved = doc.toNote(note);
    final reopened = NoteDocument.fromNote(Note.fromMap(saved.toMap()));
    expect(reopened.isReadOnly, isFalse);
    expect(reopened.tags, [tag]);
    expect(() => doc.setTags(['${tag}a']), throwsFormatException);
    expect(doc.tags, [tag]);
  });

  for (final count in [5, 12]) {
    test('$count legacy tags remain editable and removable without truncation',
        () {
      final tags = [
        List.filled(40, 'a').join(),
        for (var i = 1; i < count; i++) 'tag$i',
      ];
      final original = _legacy(tags);
      final doc = NoteDocument.fromNote(original);
      expect(doc.isReadOnly, isFalse);
      doc.setTags(tags);
      expect(doc.toNote(original).toMap(), original.toMap());
      doc.replaceText(0, 'Updated text');
      final edited = NoteDocument.fromNote(doc.toNote(original));
      expect(edited.lines.single.text, 'Updated text');
      expect(edited.tags, tags);
      while (doc.tags.length > 2) {
        final before = doc.tags.toList();
        expect(() => doc.setTags([...doc.tags, 'new']), throwsFormatException);
        expect(doc.tags, before);
        doc.setTags(doc.tags.take(doc.tags.length - 1).toList());
        expect(NoteDocument.fromNote(doc.toNote(original)).tags, doc.tags);
      }
      // New tags fit again below the cap, even beside a retained long tag.
      doc.setTags([...doc.tags, 'new']);
      expect(doc.tags, [tags.first, 'tag1', 'new']);
      expect(NoteDocument.fromNote(doc.toNote(original)).tags, doc.tags);
      doc.setTags([]);
      expect(NoteDocument.fromNote(doc.toNote(original)).tags, isEmpty);
    });
  }
}
