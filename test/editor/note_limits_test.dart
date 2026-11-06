import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/note_word_limit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../notes_editor_page_test.dart' show openEditor, field;

Future<void> _addTag(WidgetTester tester, String text) async {
  await tester.tap(find.byTooltip('Add tag'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('note-tag-input')), text);
  await tester.tap(find.text('Add'));
  await tester.pumpAndSettle();
}

void main() {
  group('C08 tag limits are rejected, never silently truncated', () {
    testWidgets('a pasted 20-character tag is refused with a message',
        (tester) async {
      final note = Note(id: 'tag-paste', body: 'Body');
      await openEditor(tester, note);
      await _addTag(tester, 'abcdefghijklmnopqrst');
      expect(find.textContaining('#abcdefghijklmno'), findsNothing,
          reason: 'a cut-down tag would be a silent change');
      expect(find.text('Tags must be 15 characters or less'), findsWidgets);
    });

    testWidgets('a leading # does not count against the 15 characters',
        (tester) async {
      final note = Note(id: 'tag-hash', body: 'Body');
      await openEditor(tester, note);
      await _addTag(tester, '#morningroutine1');
      expect(find.text('#morningroutine1'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(NoteDocument.fromNote(note).tags, ['morningroutine1']);
    });

    testWidgets('15 visible characters are accepted even when wider in UTF-16',
        (tester) async {
      final note = Note(id: 'tag-emoji', body: 'Body');
      await openEditor(tester, note);
      final tag = List.filled(15, '\u{1F468}‍\u{1F469}').join();
      expect(tag.length, greaterThan(15));
      await _addTag(tester, tag);
      expect(find.text('#$tag'), findsOneWidget);
    });
  });

  testWidgets('an over-long title names the title, not images or the body',
      (tester) async {
    final note = Note(id: 'title-limit', body: 'Body');
    await openEditor(tester, note);
    await tester.enterText(field('note-title'), 'T' * 301);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(
        find.text(
            'Keep the title within 300 characters. Your draft is still here.'),
        findsWidgets);
    expect(note.title, isEmpty, reason: 'nothing is saved');
  });

  testWidgets('a legacy note over the word limit, with three images, is kept',
      (tester) async {
    final jpeg =
        base64Encode(image.encodeJpg(image.Image(width: 8, height: 8)));
    final document = NoteDocument.fromNote(Note(id: 'legacy-over'));
    for (var i = 0; i < NoteDocument.maxImagesPerNote; i++) {
      document.insertImageAfter(i, jpeg);
    }
    final original = document.toNote(Note(id: 'legacy-over'));
    // An older App could save more than 3,000 words.
    final legacy = NoteDocument.fromNote(original);
    final words = List.filled(NoteWordLimit.maxWords + 200, 'word').join(' ');
    legacy.replaceText(0, words);
    final note = legacy.toNote(original);
    final saved = NoteDocument.fromNote(note);
    expect(saved.imageCount, NoteDocument.maxImagesPerNote);
    final before = note.toMap();

    await openEditor(tester, note);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.toMap(), before, reason: 'unchanged legacy note untouched');
    final reopened = NoteDocument.fromNote(note);
    expect(reopened.imageCount, NoteDocument.maxImagesPerNote);
    expect(reopened.lines.first.text, words);
  });
}
