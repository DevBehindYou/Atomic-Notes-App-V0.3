import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/editor/editor_media.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import '../notes_editor_page_test.dart' show openEditor, field;

String _words(int count) => List.filled(count, 'word').join(' ');
const _newLimitMessage =
    'Use up to 3000 words per note. Your draft is still here.';

class _SpeechInput implements EditorSpeechInput {
  void Function(String, bool)? result;
  int cancels = 0;

  @override
  Future<bool> start({
    required void Function(String, bool) onResult,
    required void Function(String) onError,
    required void Function() onStopped,
  }) async {
    result = onResult;
    return true;
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> stop() async {}
}

void main() {
  for (final count in [2999, 3000]) {
    testWidgets('$count-word new note saves with Done', (tester) async {
      final note = Note(id: 'boundary-$count');
      await openEditor(tester, note);
      await tester.enterText(field('note-body'), _words(count));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(note.body, _words(count));
      expect(find.byType(NotesCreaterPage), findsNothing);
    });
  }

  testWidgets('3001-word paste stays intact when Done rejects it',
      (tester) async {
    final note = Note(id: 'paste-limit');
    await openEditor(tester, note);
    final body = _words(3001);
    // A complete platform editing-value replacement exercises paste input.
    await tester.enterText(field('note-body'), body);
    await tester.pump();
    expect(find.text('3001 WORDS'), findsOneWidget);
    expect(find.text('3000 MAX'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.byType(NotesCreaterPage), findsOneWidget);
    expect(find.text(_newLimitMessage), findsWidgets);
    expect(tester.widget<TextField>(field('note-body')).controller!.text, body);
    expect(note.body, isEmpty);
    await tester.enterText(field('note-body'), _words(2999));
    await tester.enterText(field('note-title'), 'Title');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.title, 'Title');
    expect(note.body, _words(2999));
  });

  testWidgets('back Save counts title and checklist, excluding images and tags',
      (tester) async {
    final original = Note(id: 'mixed-limit', title: 'Title', body: 'Heading');
    final document = NoteDocument.fromNote(original);
    document
        .replaceStyles(0, [const NoteStyleRun(0, 7, NoteTextStyle.heading)]);
    document.insertChecklistAfter(0);
    document.replaceText(1, 'Task');
    document.setTags(['Not counted']);
    document.insertImageAfter(
        1, base64Encode(image.encodeJpg(image.Image(width: 2, height: 2))));
    final note = document.toNote(original);
    final before = note.toMap();
    await openEditor(tester, note);
    expect(find.text('3 WORDS'), findsOneWidget);
    await tester.enterText(field('note-body'), _words(2999));
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesCreaterPage), findsOneWidget);
    expect(find.text(_newLimitMessage), findsWidgets);
    expect(note.toMap(), before);
    expect(tester.widget<TextField>(field('note-body')).controller!.text,
        _words(2999));
    // Discard remains available after failed Save.
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(note.toMap(), before);
  });

  testWidgets('typing a word past 3000 blocks save without changing the caret',
      (tester) async {
    final note = Note(id: 'typing-limit');
    await openEditor(tester, note);
    await tester.enterText(field('note-body'), _words(3000));
    final controller = tester.widget<TextField>(field('note-body')).controller!;
    final text = '${controller.text} extra';
    final selection = TextSelection.collapsed(offset: text.length);
    final composing = TextRange(start: text.length - 5, end: text.length);
    tester.testTextInput.updateEditingValue(TextEditingValue(
        text: text, selection: selection, composing: composing));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesCreaterPage), findsOneWidget);
    expect(find.text(_newLimitMessage), findsWidgets);
    expect(controller.text, text);
    expect(controller.selection, selection);
    expect(controller.value.composing, composing);
    expect(note.body, isEmpty);
  });

  for (final current in [3001, 3002, 3003]) {
    testWidgets('legacy 3002-word note edited to $current words',
        (tester) async {
      final note = Note(id: 'legacy-$current', body: _words(3002));
      await openEditor(tester, note);
      expect(find.text('3002 LEGACY MAX'), findsOneWidget);
      await tester.enterText(field('note-body'), _words(current));
      await tester.tap(find.text('Done'));
      await tester.pump();
      if (current <= 3002) {
        await tester.pumpAndSettle();
        expect(find.byType(NotesCreaterPage), findsNothing);
        expect(note.body, _words(current));
      } else {
        expect(find.byType(NotesCreaterPage), findsOneWidget);
        expect(find.textContaining('up to 3002 words'), findsWidgets);
        expect(note.body, _words(3002));
        expect(tester.widget<TextField>(field('note-body')).controller!.text,
            _words(3003));
      }
    });
  }

  testWidgets('dictation beyond the cap stays editable and cannot save',
      (tester) async {
    final speech = _SpeechInput();
    final note = Note(id: 'dictation-limit', body: _words(2999));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) =>
                            NotesCreaterPage(note: note, speechInput: speech)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(field('note-body')).controller!;
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    await tester.tap(find.byTooltip('Dictate text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start dictation'));
    await tester.pumpAndSettle();
    speech.result!('two words', false);
    await tester.pump();
    final fullDraft = controller.text;
    expect(find.text('3001 WORDS'), findsOneWidget);
    final cancellations = speech.cancels;
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.byType(NotesCreaterPage), findsOneWidget);
    expect(find.text(_newLimitMessage), findsWidgets);
    expect(speech.cancels, greaterThan(cancellations));
    speech.result!('late result', true);
    await tester.pump();
    expect(controller.text, fullDraft);
    expect(note.body, _words(2999));
  });

  testWidgets('compact editor still displays the cap', (tester) async {
    await openEditor(tester, Note(id: 'compact-limit'),
        size: const Size(390, 844), keyboard: 560);
    expect(find.text('3000 MAX'), findsOneWidget);
  });
}
