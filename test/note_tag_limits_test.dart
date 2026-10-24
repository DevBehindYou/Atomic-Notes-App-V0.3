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
  test('five tags fit; a sixth is rejected without changing the draft', () {
    final note = Note(id: 'tag-count', body: 'Keep this text');
    final doc = NoteDocument.fromNote(note)
      ..setTags(['one', 'two', 'three', 'four', 'five']);
    final before = doc.toNote(note).toMap();
    expect(() => doc.setTags([...doc.tags, 'six']), throwsFormatException);
    expect(doc.toNote(note).toMap(), before);
    doc.setTags([' one ', 'ONE', 'two', 'three', 'four', 'five']);
    expect(doc.tags, ['one', 'two', 'three', 'four', 'five']);
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

  test('legacy tags remain readable and removable without silent truncation',
      () {
    final tags = [
      '12345678901234567890',
      'two',
      'three',
      'four',
      'five',
      'six'
    ];
    final original = _legacy(tags);
    final doc = NoteDocument.fromNote(original);
    expect(doc.isReadOnly, isFalse);
    expect(doc.toNote(original).toMap(), original.toMap());
    doc.replaceText(0, 'Updated text');
    expect(NoteDocument.fromNote(doc.toNote(original)).tags, tags);
    doc.setTags(tags.take(5).toList());
    expect(doc.tags, tags.take(5).toList());
    expect(() => doc.setTags([...doc.tags, 'new']), throwsFormatException);
    doc.setTags(doc.tags.skip(1).toList());
    doc.setTags([...doc.tags, 'new']);
    expect(doc.tags, ['two', 'three', 'four', 'five', 'new']);
  });
}
