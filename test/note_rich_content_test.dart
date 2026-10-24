import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('three image insertion cap is atomic and removal restores a slot', () {
    final original = Note(id: 'three-image-model', body: 'Keep text');
    final doc = NoteDocument.fromNote(original);
    for (var i = 0; i < 3; i++) {
      doc.insertImageAfter(doc.lines.length - 1, _jpeg());
    }
    final before = doc.toNote(original).toMap();
    expect(() => doc.insertImageAfter(0, _jpeg()), throwsFormatException);
    expect(doc.toNote(original).toMap(), before);
    doc.removeAt(doc.lines.indexWhere((line) => line.isImage));
    doc.insertImageAfter(doc.lines.length - 1, _jpeg());
    expect(doc.lines.where((line) => line.isImage), hasLength(3));
  });

  test('literal rich marker tasks remain legacy content outside an envelope',
      () {
    for (final note in [
      Note(id: 'todo-single', kind: NoteKind.todo, items: [
        TodoItem(text: NoteDocument.richFormatMarker),
      ]),
      Note(id: 'todo-many', kind: NoteKind.todo, items: [
        TodoItem(text: 'atomic-notes:rich-document:v99'),
        TodoItem(text: 'Normal task'),
      ]),
      Note(id: 'text-many', body: 'Legacy prose', items: [
        TodoItem(text: NoteDocument.richFormatMarker),
        TodoItem(text: 'Normal task'),
      ]),
      Note(id: 'text-checked', body: 'Legacy prose', items: [
        TodoItem(text: NoteDocument.richFormatMarker, done: true),
      ]),
    ]) {
      expect(NoteDocument.hasRichContent(note), isFalse);
      final document = NoteDocument.fromNote(note);
      expect(document.isReadOnly, isFalse);
      expect(document.plainText, contains(note.items.first.text));
      expect(document.toNote(note).toMap(), note.toMap());
      expect(NoteContentBudget.errorFor(note), isNull);
      final task = document.lines.indexWhere((line) => line.isChecklist);
      document.setDone(task, !document.lines[task].done);
      expect(document.lines[task].done, !note.items.first.done);
    }
  });

  test('reserved corrupt rich document never exposes opaque JSON as prose', () {
    final note = Note(
      id: 'corrupt-rich',
      body: '{not valid JSON: secret image bytes}',
      items: [TodoItem(text: 'atomic-notes:rich-document:v2')],
    );
    final document = NoteDocument.fromNote(note);
    expect(document.lines.map((line) => line.text).join('\n'),
        'Unsupported note format');
    expect(document.toNote(note).toMap(), note.toMap());
  });

  test('rich styles tags task state and image survive storage and task toggles',
      () {
    final original = Note.create()..body = 'Visible text';
    final document = NoteDocument.fromNote(original);
    document.replaceStyles(0,
        [const NoteStyleRun(0, 7, NoteTextStyle.bold | NoteTextStyle.italic)]);
    document.setTags([' Work ', 'work', 'Release']);
    final task = document.insertChecklistAfter(0);
    document.replaceText(task, 'Ship it');
    document.replaceStyles(
        task, [const NoteStyleRun(0, 4, NoteTextStyle.underline)]);
    document.insertImageAfter(task, _jpeg());
    final saved = document.toNote(original, removeEmptyLines: true);
    expect(saved.items.single.text, NoteDocument.richFormatMarker);
    expect(original.body, 'Visible text');
    final disk = Note.fromMap(saved.toMap());
    final cloud = Note.fromRemote({...saved.toRemote('owner'), 'version': 2});
    for (final restored in [disk, cloud]) {
      final reopened = NoteDocument.fromNote(restored);
      expect(reopened.isReadOnly, isFalse);
      expect(reopened.tags, ['Work', 'Release']);
      expect(reopened.lines[0].styles.single.flags,
          NoteTextStyle.bold | NoteTextStyle.italic);
      expect(reopened.imageBytes, NoteImageContent.decode(_jpeg()).length);
      expect(reopened.plainText, 'Visible text\nShip it\n[Image]');
      reopened.setDone(1, true);
      final toggled = reopened.toNote(restored);
      expect(toggled.doneCount, 1);
      expect(NoteDocument.fromNote(toggled).lines[1].styles.single,
          const NoteStyleRun(0, 4, NoteTextStyle.underline));
      expect(NoteDocument.fromNote(toggled).lines.last.imageBase64, _jpeg());
      expect(NoteContentBudget.errorFor(toggled), isNull);
      expect(toggled.preview, 'Visible text\nShip it\n[Image]');
      expect(toggled.isEmpty, isFalse);
    }
  });

  test('legacy corpus is unchanged on open and no-op save or undone rich edit',
      () {
    final corpus = [
      Note(id: 'literal', body: '**plain** _text_\n- [x] literal\n{"v":2}'),
      Note(id: 'crlf', body: 'A\r\n\r\nA\n'),
      Note(id: 'todo', kind: NoteKind.todo, body: 'legacy body', items: [
        TodoItem(text: ''),
        TodoItem(text: 'Duplicate', done: true),
        TodoItem(text: 'Duplicate')
      ]),
      Note(
          id: 'v1',
          body: 'Context\n- [x] Task\n  continued',
          items: [TodoItem(text: NoteDocument.formatMarker)]),
    ];
    for (final original in corpus) {
      final doc = NoteDocument.fromNote(original);
      expect(doc.toNote(original).toMap(), original.toMap());
      doc.setTags(['temporary']);
      doc.setTags([]);
      expect(doc.toNote(original).toMap(), original.toMap());
    }
  });

  test(
      'tags-only and image-only notes survive cleanup, clearing removes envelope',
      () {
    final note = Note.create();
    final tags = NoteDocument.fromNote(note)..setTags(['Inbox']);
    final tagged = tags.toNote(note, removeEmptyLines: true);
    expect(tagged.isEmpty, isFalse);
    final reopened = NoteDocument.fromNote(tagged)..setTags([]);
    final empty = reopened.toNote(tagged, removeEmptyLines: true);
    expect(empty.isEmpty, isTrue);
    expect(empty.items, isEmpty);
    final image = NoteDocument.fromNote(note)..insertImageAfter(0, _jpeg());
    final imaged = image.toNote(note, removeEmptyLines: true);
    expect(NoteDocument.fromNote(imaged).lines.single.isImage, isTrue);
    expect(imaged.isEmpty, isFalse);
  });

  test(
      'unsupported or corrupt versions refuse every mutation and preserve bytes',
      () {
    for (final body in [
      '{bad',
      jsonEncode({'v': 3, 'tags': [], 'blocks': []}),
      jsonEncode({
        'v': 2,
        'tags': [],
        'blocks': [
          {
            'text': 'x',
            'checklist': false,
            'done': false,
            'styles': [
              [0, 2, 1]
            ]
          }
        ]
      }),
      jsonEncode({
        'v': 2,
        'tags': [],
        'blocks': [
          {
            'text': 'x',
            'checklist': false,
            'done': false,
            'styles': [],
            'future': true
          }
        ]
      }),
      jsonEncode({
        'v': 2,
        'tags': [],
        'blocks': [
          {
            'text': '',
            'checklist': false,
            'done': false,
            'styles': [],
            'image': base64Encode([1, 2, 3])
          }
        ]
      }),
    ]) {
      final note = Note(
          id: 'unsupported',
          body: body,
          items: [TodoItem(text: NoteDocument.richFormatMarker)]);
      final doc = NoteDocument.fromNote(note);
      expect(doc.isReadOnly, isTrue);
      expect(doc.toNote(note, removeEmptyLines: true).toMap(), note.toMap());
      expect(doc.plainText, 'Unsupported note format');
      expect(() => doc.replaceText(0, 'overwrite'), throwsStateError);
      expect(() => doc.replaceStyles(0, []), throwsStateError);
      expect(() => doc.setDone(0, true), throwsStateError);
      expect(() => doc.setTags([]), throwsStateError);
      expect(() => doc.insertTextAfter(0), throwsStateError);
      expect(() => doc.insertChecklistAfter(0), throwsStateError);
      expect(() => doc.insertImageAfter(0, _jpeg()), throwsStateError);
      expect(() => doc.removeAt(0), throwsStateError);
      expect(note.isEmpty, isFalse);
      expect(note.preview, 'Unsupported note format');
    }
    final future = Note(
        id: 'future',
        body: 'opaque future body',
        items: [TodoItem(text: 'atomic-notes:rich-document:v99')]);
    expect(NoteDocument.fromNote(future).isReadOnly, isTrue);
  });

  test('text shortening clamps styles and split preserves styles on both sides',
      () {
    final note = Note.create()..body = 'Alpha\nBeta';
    final doc = NoteDocument.fromNote(note);
    doc.replaceStyles(0, [const NoteStyleRun(0, 10, NoteTextStyle.bold)]);
    doc.insertChecklistAfter(0, caretOffset: 2);
    expect(doc.lines[0].styles, [const NoteStyleRun(0, 5, NoteTextStyle.bold)]);
    expect(doc.lines[2].styles, [const NoteStyleRun(0, 4, NoteTextStyle.bold)]);
    doc.replaceText(2, 'Be');
    expect(doc.lines[2].styles, [const NoteStyleRun(0, 2, NoteTextStyle.bold)]);
    expect(() => doc.replaceStyles(2, [const NoteStyleRun(0, 3, 1)]),
        throwsFormatException);
    expect(() => doc.replaceStyles(2, [const NoteStyleRun(0, 2, 32)]),
        throwsFormatException);
  });

  test(
      'image validation rejects wrong type dimensions and aggregate size atomically',
      () {
    final doc = NoteDocument.fromNote(Note.create());
    for (final invalid in [
      'bad base64',
      base64Encode([0x89, 0x50, 0x4e, 0x47]),
      _jpeg(width: 5000),
      _jpeg(width: 4096, height: 4096)
    ]) {
      expect(() => doc.insertImageAfter(0, invalid), throwsFormatException);
      expect(doc.lines, hasLength(1));
    }
    final large = _jpeg(padding: NoteImageContent.maxBytes - 14);
    doc.insertImageAfter(0, large);
    doc.insertImageAfter(1, large);
    expect(() => doc.insertImageAfter(2, large), throwsFormatException);
    expect(doc.lines, hasLength(3));
  });

  test(
      'budget checks UTF8 encryption expansion and complete row rather than text alone',
      () {
    expect(
        NoteContentBudget.errorFor(
            Note.create()..body = 'x' * NoteContentBudget.maxBodyLength),
        isNull);
    expect(
        NoteContentBudget.errorFor(
            Note.create()..body = 'x' * (NoteContentBudget.maxBodyLength + 1)),
        isNotNull);
    // Within UTF-16 body length, but three UTF-8 bytes each overflow sealed payload.
    expect(NoteContentBudget.errorFor(Note.create()..body = '\u20ac' * 100000),
        isNotNull);
    expect(NoteContentBudget.errorFor(Note.create()..title = 'x' * 301),
        isNotNull);
    // Checklist content also counts toward the sealed and wire budgets.
    final todo = Note.create(kind: NoteKind.todo)
      ..items = [TodoItem(text: 'x' * 300000)];
    expect(NoteContentBudget.errorFor(todo), isNotNull);
  });
}

// Minimal SOF header for the pure storage validator, never passed to an image
// renderer. UI tests use actual decoded JPEG fixtures separately.
String _jpeg({int width = 1, int height = 1, int padding = 0}) => base64Encode([
      0xff,
      0xd8,
      0xff,
      0xc0,
      0,
      8,
      8,
      height >> 8,
      height & 255,
      width >> 8,
      width & 255,
      1,
      ...List.filled(padding, 0),
      0xff,
      0xd9,
    ]);
