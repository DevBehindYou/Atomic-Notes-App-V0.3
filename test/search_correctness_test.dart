import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/note_projection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

Note _rich(String body,
    {List<String> tags = const [], bool withImage = false}) {
  final original = Note(id: 'n', body: body);
  final document = NoteDocument.fromNote(original);
  if (tags.isNotEmpty) document.setTags(tags);
  if (withImage) {
    document.insertImageAfter(
        0, base64Encode(image.encodeJpg(image.Image(width: 4, height: 4))));
  }
  return document.toNote(original);
}

bool _matches(Note note, String query) =>
    NoteProjection.fromNote(note).matches(query.trim().toLowerCase());

void main() {
  group('C09 search matches what the note says, not display placeholders', () {
    test('an image never matches "image" or the [Image] placeholder', () {
      final note = _rich('Trip plan', withImage: true);
      expect(NoteDocument.fromNote(note).plainText, contains('[Image]'),
          reason: 'the card preview keeps its placeholder');
      expect(_matches(note, 'image'), isFalse);
      expect(_matches(note, '[im'), isFalse);
      expect(_matches(note, 'trip'), isTrue);
    });

    test('words a user wrote about images still match', () {
      expect(_matches(_rich('Image ideas', withImage: true), 'image'), isTrue);
    });

    test('a #tag query finds the tag it names', () {
      final note = _rich('Body', tags: ['work', 'Morning']);
      expect(_matches(note, '#work'), isTrue);
      expect(_matches(note, '#mor'), isTrue, reason: 'tags match by prefix');
      expect(_matches(note, '#ork'), isFalse,
          reason: 'a hashtag names a tag from its start');
      expect(_matches(note, '#home'), isFalse);
      expect(_matches(note, 'work'), isTrue, reason: 'plain queries unchanged');
    });

    test('a literal # in the text still matches', () {
      expect(_matches(_rich('Ticket #4512 open'), '#4512'), isTrue);
    });
  });

  group('existing behavior kept', () {
    test('an unreadable note is found by the text its card shows', () {
      final broken = Note(
          id: 'b',
          body: '{"v":2,"tags":[],"blocks":[{"text":"x","image":"bad"}]}',
          items: [TodoItem(text: NoteDocument.richFormatMarker)]);
      expect(NoteDocument.fromNote(broken).isReadOnly, isTrue);
      expect(_matches(broken, 'unsupported note format'), isTrue);
    });

    test('body, checklist and tag substrings match case-insensitively', () {
      final todo = Note(
          id: 't',
          kind: NoteKind.todo,
          items: [TodoItem(text: 'Buy Milk'), TodoItem(text: 'Eggs')]);
      expect(_matches(todo, 'milk'), isTrue);
      expect(_matches(todo, 'EGG'), isTrue);
      expect(_matches(_rich('Body', tags: ['Planning']), 'lann'), isTrue);
      expect(_matches(_rich('Hello world'), 'lo wo'), isTrue);
      expect(_matches(_rich('Hello world'), 'absent'), isFalse);
    });
  });
}
