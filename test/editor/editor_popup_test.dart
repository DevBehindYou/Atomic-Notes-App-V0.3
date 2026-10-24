import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/editor/editor_media.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Speech implements EditorSpeechInput {
  int starts = 0;
  @override
  Future<bool> start(
      {required void Function(String, bool) onResult,
      required void Function(String) onError,
      required void Function() onStopped}) async {
    starts++;
    return true;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> stop() async {}
}

Future<void> _open(WidgetTester tester, Note note,
    {double scale = 1,
    double keyboard = 0,
    VoidCallback? onDelete,
    _Speech? speech}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 760);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => NotesCreaterPage(
                          note: note,
                          speechInput: speech ?? _Speech(),
                          onDelete: onDelete)),
                  child: const Text('Open'))))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _action(WidgetTester tester, String label) async {
  final target = find.byTooltip(label);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 100,
        scrollable: find
            .descendant(
                of: find.byType(NotesCreaterPage),
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder get _body => find.byKey(const ValueKey('note-body'));

Future<void> _edit(WidgetTester tester, String text) async {
  if (_body.evaluate().isEmpty) {
    await tester.scrollUntilVisible(_body, 100,
        scrollable: find
            .descendant(
                of: find.byType(NotesCreaterPage),
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(_body);
  await tester.enterText(_body, text);
}

void main() {
  testWidgets('tag popup allows 15 characters and disables adding after five',
      (tester) async {
    final original = Note(id: 'five-tag-popup', body: 'Body');
    final document = NoteDocument.fromNote(original)
      ..setTags(['one', 'two', 'three', 'four', 'five']);
    await _open(tester, document.toNote(original));
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Tag'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('Remove tag five'));
    await tester.pumpAndSettle();
    await _action(tester, 'Add tag');
    final field = find.byKey(const ValueKey('note-tag-input'));
    expect(tester.widget<TextField>(field).maxLength, 15);
    await tester.enterText(field, '123456789012345');
    await _tap(tester, 'Add');
    expect(find.text('#123456789012345'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Tag'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'save confirmation has a full-size primary action and saves only on Save',
      (tester) async {
    final note = Note(id: 'save-popup', body: 'Original');
    await _open(tester, note);
    await _edit(tester, 'Edited');
    await _action(tester, 'Back to notes');
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(save, findsOneWidget);
    expect(tester.getSize(save).height, greaterThanOrEqualTo(48));
    expect(note.body, 'Original');
    await _tap(tester, 'Save');
    expect(note.body, 'Edited');
    expect(find.byType(NotesCreaterPage), findsNothing);
  });

  testWidgets(
      'large-text save dialog keeps draft on Keep editing or back; Discard preserves original',
      (tester) async {
    final note = Note(id: 'discard-popup', body: 'Original');
    await _open(tester, note, scale: 2, keyboard: 280);
    await _edit(tester, 'Edited');
    await _action(tester, 'Back to notes');
    await _tap(tester, 'Keep editing');
    expect(tester.widget<TextField>(_body).controller!.text, 'Edited');
    await _action(tester, 'Back to notes');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_body).controller!.text, 'Edited');
    await _action(tester, 'Back to notes');
    await _tap(tester, 'Discard');
    expect(note.body, 'Original');
    expect(find.byType(NotesCreaterPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large-text tag popup supports cancel and saves the entered tag',
      (tester) async {
    final note = Note(id: 'tag-popup', body: 'Original');
    await _open(tester, note, scale: 2, keyboard: 280);
    await _action(tester, 'Add tag');
    await tester.enterText(
        find.byKey(const ValueKey('note-tag-input')), 'cancelled');
    await _tap(tester, 'Cancel');
    expect(find.text('#cancelled'), findsNothing);
    await _action(tester, 'Add tag');
    await tester.enterText(
        find.byKey(const ValueKey('note-tag-input')), 'planning');
    await _tap(tester, 'Add');
    expect(find.text('#planning'), findsOneWidget);
    await _tap(tester, 'Done');
    expect(NoteDocument.fromNote(note).tags, ['planning']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'large-text delete confirmation cancels safely and routes confirmed deletion',
      (tester) async {
    var deleted = 0;
    final note = Note(id: 'delete-popup', body: 'Saved content');
    await _open(tester, note,
        scale: 2, keyboard: 280, onDelete: () => deleted++);
    await _edit(tester, 'Unsaved draft');
    await _action(tester, 'Delete note');
    await _tap(tester, 'Cancel');
    expect(deleted, 0);
    expect(tester.widget<TextField>(_body).controller!.text, 'Unsaved draft');
    await _action(tester, 'Delete note');
    await _tap(tester, 'Move to Recycle Bin');
    expect(deleted, 1);
    expect(note.body, 'Saved content');
    expect(find.byType(NotesCreaterPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsaved note deletion discards only after confirmation',
      (tester) async {
    final note = Note(id: 'unsaved-delete', body: 'Original');
    await _open(tester, note);
    await _edit(tester, 'Unsaved changes');
    await _action(tester, 'Delete note');
    expect(find.text('Discard this note?'), findsOneWidget);
    await _tap(tester, 'Cancel');
    expect(tester.widget<TextField>(_body).controller!.text, 'Unsaved changes');
    await _action(tester, 'Delete note');
    await _tap(tester, 'Discard');
    expect(note.body, 'Original');
    expect(find.byType(NotesCreaterPage), findsNothing);
  });

  testWidgets(
      'large-text dictation disclosure starts only after explicit action',
      (tester) async {
    final speech = _Speech();
    await _open(tester, Note(id: 'speech-popup', body: 'Original'),
        scale: 2, keyboard: 280, speech: speech);
    await _action(tester, 'Dictate text');
    await _tap(tester, 'Cancel');
    expect(speech.starts, 0);
    await _action(tester, 'Dictate text');
    await _tap(tester, 'Start dictation');
    expect(speech.starts, 1);
    expect(tester.takeException(), isNull);
  });
}
