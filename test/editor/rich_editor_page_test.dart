import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../notes_editor_page_test.dart' show openEditor, field;

void main() {
  testWidgets('removing earlier row keeps insertion beside the active row',
      (tester) async {
    final note = Note(id: 'active-row', kind: NoteKind.todo, items: [
      for (final text in ['A', 'B', 'C', 'D']) TodoItem(text: text),
    ]);
    await openEditor(tester, note);
    await tester.tap(field('note-item-2'));
    await tester.tap(find.byTooltip('Remove item 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add text line'));
    await tester.pumpAndSettle();
    await tester.enterText(field('note-text-2'), 'After C');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(NoteDocument.fromNote(note).lines.map((l) => l.text),
        ['B', 'C', 'After C', 'D']);
  });
  testWidgets('tags and combined formatting survive Save and reopen',
      (tester) async {
    final note = Note(id: 'rich-editor', body: 'Protect the morning');
    await openEditor(tester, note);
    await tester.tap(find.byTooltip('Add tag'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('note-tag-input')), 'Morning');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('#Morning'), findsOneWidget);
    await tester.tap(field('note-body'));
    final controller = tester.widget<TextField>(field('note-body')).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    final editable = tester.state<EditableTextState>(find.descendant(
        of: field('note-body'), matching: find.byType(EditableText)));
    editable.showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();
    await tester.tap(find.byTooltip('Italic'));
    await tester.pump();
    expect(controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final doc = NoteDocument.fromNote(note);
    expect(doc.tags, ['Morning']);
    expect(doc.lines.single.styles, [const NoteStyleRun(0, 7, 3)]);
    await openEditor(tester, note);
    expect(find.text('#Morning'), findsOneWidget);
    expect(tester.widget<TextField>(field('note-body')).controller!.text,
        'Protect the morning');
  });

  testWidgets('footer media/delete actions and reading time are available',
      (tester) async {
    await openEditor(tester, Note(id: 'footer', body: 'One two'));
    expect(find.byTooltip('Add image'), findsOneWidget);
    expect(find.byTooltip('Dictate text'), findsOneWidget);
    expect(find.byTooltip('Delete note'), findsOneWidget);
    expect(find.text('1 MIN READ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown rich format is read-only and opaque body is hidden',
      (tester) async {
    final note = Note(
        id: 'future',
        body: '{"private":"opaque"}',
        items: [TodoItem(text: 'atomic-notes:rich-document:v99')]);
    final before = note.contentSig;
    await openEditor(tester, note);
    expect(find.textContaining('opaque'), findsNothing);
    expect(find.textContaining('READ-ONLY'), findsOneWidget);
    expect(tester.widget<TextField>(field('note-title')).readOnly, isTrue);
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pumpAndSettle();
    expect(note.contentSig, before);
    expect(tester.takeException(), isNull);
  });
}
