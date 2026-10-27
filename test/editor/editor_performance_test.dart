import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/editor/rich_text_controller.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../notes_editor_page_test.dart' show openEditor, field;

Finder get _editorScaffold => find.descendant(
    of: find.byType(NotesCreaterPage), matching: find.byType(Scaffold));

class _SignatureCountingNote extends Note {
  _SignatureCountingNote()
      : super(id: 'dirty-metadata', title: 'Title', body: 'Original body');

  int signatureReads = 0;

  @override
  String get contentSig {
    signatureReads++;
    return super.contentSig;
  }
}

void main() {
  testWidgets('long-note selection and composing updates keep editor intact',
      (tester) async {
    // Comparable to the largest staging note (65,714 plain-text characters).
    final text = List.filled(6571, 'word').join(' ');
    await openEditor(tester, Note(id: 'long-selection', body: '$text $text'));
    final controller = tester.widget<TextField>(field('note-body')).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(_editorScaffold);
    var parentRebuilds = 0;
    var previous = scaffold;
    for (var i = 1; i <= 24; i++) {
      controller.value = controller.value.copyWith(
        selection: TextSelection.collapsed(offset: i),
        composing: TextRange(start: 0, end: i),
      );
      await tester.pump();
      final current = tester.widget<Scaffold>(_editorScaffold);
      if (!identical(previous, current)) parentRebuilds++;
      previous = current;
    }
    // Count rebuilt page widgets, not machine-dependent timing or device FPS.
    // ignore: avoid_print
    print(
        'long-note selection/composition: $parentRebuilds page rebuilds / 24 updates');
    expect(parentRebuilds, 0);
    expect(controller.selection, const TextSelection.collapsed(offset: 24));
    expect(controller.value.composing, const TextRange(start: 0, end: 24));
    expect(find.text('ON DEVICE'), findsOneWidget);
    expect(find.text('SAVE WITH DONE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing updates metadata and statistics without rebuilding rows',
      (tester) async {
    final note = Note(id: 'local-typing', kind: NoteKind.todo, items: [
      TodoItem(text: 'First item', done: true),
      TodoItem(text: 'Untouched item'),
    ]);
    await openEditor(tester, note);
    final controller =
        tester.widget<TextField>(field('note-item-0')).controller!;
    final scaffold = tester.widget<Scaffold>(_editorScaffold);
    final otherField = tester.widget<TextField>(field('note-item-1'));
    controller.value = const TextEditingValue(
      text: 'First item now longer',
      selection: TextSelection.collapsed(offset: 21),
      composing: TextRange(start: 15, end: 21),
    );
    await tester.pump();
    expect(find.text('6 WORDS'), findsOneWidget);
    expect(find.text('1 / 2 DONE'), findsOneWidget);
    expect(find.text('SAVE WITH DONE'), findsOneWidget);
    expect(tester.widget<Scaffold>(_editorScaffold), same(scaffold));
    expect(tester.widget<TextField>(field('note-item-1')), same(otherField));
    expect(controller.value.composing, const TextRange(start: 15, end: 21));
    // Saving immediately must include the edit, with no debounce window.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.items.first.text, 'First item now longer');
    expect(note.items.first.done, isTrue);
  });

  testWidgets('format-only edits save without rebuilding the editor',
      (tester) async {
    final note = Note(id: 'local-format', body: 'Style this text');
    await openEditor(tester, note);
    final controller = tester.widget<TextField>(field('note-body')).controller!
        as RichNoteController;
    controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
        composing: const TextRange(start: 0, end: 5));
    await tester.pump();
    final scaffold = tester.widget<Scaffold>(_editorScaffold);
    controller.toggleStyle(NoteTextStyle.bold);
    controller.toggleStyle(NoteTextStyle.italic);
    await tester.pump();
    expect(find.text('SAVE WITH DONE'), findsOneWidget);
    expect(tester.widget<Scaffold>(_editorScaffold), same(scaffold));
    expect(controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5));
    expect(controller.value.composing, const TextRange(start: 0, end: 5));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(NoteDocument.fromNote(note).lines.single.styles,
        [const NoteStyleRun(0, 5, 3)]);
  });

  testWidgets('dirty metadata tracks reverted edits without content hashing',
      (tester) async {
    final note = _SignatureCountingNote();
    await openEditor(tester, note);
    final body = tester.widget<TextField>(field('note-body')).controller!
        as RichNoteController;
    for (final text in ['Changed body', 'Original body']) {
      body.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
      await tester.pump();
      expect(
          find.text(text == 'Original body' ? 'ON DEVICE' : 'SAVE WITH DONE'),
          findsOneWidget);
    }
    for (final title in ['Changed title', 'Title']) {
      await tester.enterText(field('note-title'), title);
      await tester.pump();
      expect(find.text(title == 'Title' ? 'ON DEVICE' : 'SAVE WITH DONE'),
          findsOneWidget);
    }
    body.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
    for (var i = 0; i < 2; i++) {
      body.toggleStyle(NoteTextStyle.underline);
      await tester.pump();
      expect(
          find.text(i == 1 ? 'ON DEVICE' : 'SAVE WITH DONE'), findsOneWidget);
    }
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip(i == 0 ? 'Pin note' : 'Unpin note'));
      await tester.pump();
      expect(
          find.text(i == 1 ? 'ON DEVICE' : 'SAVE WITH DONE'), findsOneWidget);
    }
    for (var i = 0; i < 2; i++) {
      await tester
          .tap(find.byTooltip(i == 0 ? 'Mark important' : 'Unmark important'));
      await tester.pump();
      expect(
          find.text(i == 1 ? 'ON DEVICE' : 'SAVE WITH DONE'), findsOneWidget);
    }
    // ignore: avoid_print
    print(
        'dirty metadata: ${note.signatureReads} original-note signature reads');
    expect(note.signatureReads, 0,
        reason: 'Editor dirty metadata must not hash the full note per edit');
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pumpAndSettle();
    expect(find.text('Save your changes?'), findsNothing);
    expect(find.byType(NotesCreaterPage), findsNothing);
  });

  testWidgets('legacy todo and mixed dirty state clears after reverting text',
      (tester) async {
    final original = Note(id: 'mixed-dirty', body: 'Paragraph');
    final mixed = NoteDocument.fromNote(original);
    mixed.insertChecklistAfter(0);
    mixed.replaceText(1, 'Task');
    for (final note in [
      Note(id: 'legacy-dirty', kind: NoteKind.todo, body: 'Context', items: [
        TodoItem(text: 'Task', done: true),
        TodoItem(text: ''),
        TodoItem(text: 'Task'),
      ]),
      mixed.toNote(original),
    ]) {
      final before = note.toMap();
      await openEditor(tester, note);
      expect(find.text('ON DEVICE'), findsOneWidget);
      final body = tester.widget<TextField>(field('note-body')).controller!;
      final initial = body.text;
      body.text = 'Changed';
      await tester.pump();
      expect(find.text('SAVE WITH DONE'), findsOneWidget);
      body.text = initial;
      await tester.pump();
      expect(find.text('ON DEVICE'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to notes'));
      await tester.pumpAndSettle();
      expect(find.text('Save your changes?'), findsNothing);
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(note.toMap(), before);
    }
  });

  testWidgets('removing the last legacy task keeps its empty todo count',
      (tester) async {
    await openEditor(
        tester,
        Note(
            id: 'empty-todo-count',
            kind: NoteKind.todo,
            items: [TodoItem(text: 'Task')]));
    await tester.tap(find.byTooltip('Remove item 1'));
    await tester.pump();
    expect(find.text('0 / 0 DONE'), findsOneWidget);
    await tester.tap(find.byTooltip('Add text line'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 0 DONE'), findsNothing);
  });
}
