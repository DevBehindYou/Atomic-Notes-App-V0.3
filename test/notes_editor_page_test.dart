import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openEditor(
  WidgetTester tester,
  Note note, {
  double scale = 1,
  Size size = const Size(390, 844),
  double keyboard = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => NotesCreaterPage(note: note),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder field(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets('editor_text_save', (tester) async {
    final note = Note.create();
    await openEditor(tester, note);
    await tester.enterText(field('note-title'), 'Morning');
    await tester.enterText(field('note-body'), 'Three things to protect');
    await tester.tap(find.byTooltip('Pin note'));
    await tester.pump();
    expect(note.title, isEmpty);
    expect(note.pinned, isFalse);
    expect(find.text('5 WORDS'), findsOneWidget);
    expect(find.text('SAVE WITH DONE'), findsOneWidget);
    expect(find.text('Saved on device'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.title, 'Morning');
    expect(note.body, 'Three things to protect');
    expect(note.pinned, isTrue);
    expect(find.byType(NotesCreaterPage), findsNothing);
  });

  testWidgets('editor_cancel_preserves_original', (tester) async {
    final note = Note(id: 'existing', title: 'Original', body: 'Keep me');
    final before = note.toMap();
    await openEditor(tester, note);
    await tester.enterText(field('note-body'), 'Draft');
    await tester.tap(find.byTooltip('Pin note'));
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('note-body')).controller!.text,
      'Draft',
    );
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(note.toMap(), before);
    expect(find.byType(NotesCreaterPage), findsNothing);
  });

  testWidgets('editor_system_back_save', (tester) async {
    final note = Note.create();
    await openEditor(tester, note);
    await tester.enterText(field('note-body'), 'Keep this draft');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Save your changes?'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(note.body, 'Keep this draft');
    expect(find.byType(NotesCreaterPage), findsNothing);
  });

  testWidgets('editor_mode_switch_preserves_latest_rows', (tester) async {
    final note = Note(id: 'existing', body: 'Old first\nSecond');
    await openEditor(tester, note);
    await tester.tap(find.byTooltip('Switch to checklist'));
    await tester.pumpAndSettle();
    await tester.enterText(field('note-item-0'), 'Edited first');
    await tester.tap(find.byType(Checkbox).first);
    await tester.tap(find.byTooltip('Switch to text'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('note-body')).controller!.text,
      'Edited first\nSecond',
    );
    await tester.tap(find.byTooltip('Switch to checklist'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.kind, NoteKind.todo);
    expect(note.items.map((item) => item.text), ['Edited first', 'Second']);
    expect(note.items.first.done, isTrue);
  });

  testWidgets('editor_copy_blank_row_does_not_mutate_draft', (tester) async {
    final note = Note(
      id: 'existing',
      kind: NoteKind.todo,
      items: [
        TodoItem(text: 'First'),
        TodoItem(text: ''),
        TodoItem(text: 'Last', done: true),
      ],
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openEditor(tester, note);
    await tester.tap(find.byTooltip('Copy note'));
    await tester.pump();
    expect(copied, '[ ] First\n[x] Last');
    expect(note.items, hasLength(3));
    await tester.enterText(field('note-item-2'), 'Edited last');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.items.map((item) => item.text), ['First', 'Edited last']);
    expect(note.items.last.done, isTrue);
  });

  testWidgets('editor_small_keyboard_large_text', (tester) async {
    final note = Note.create();
    await openEditor(
      tester,
      note,
      scale: 2,
      size: const Size(320, 640),
      keyboard: 260,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Done').hitTestable(), findsOneWidget);
    await tester.enterText(field('note-title'), 'A long title that wraps');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.title, 'A long title that wraps');
  });

  testWidgets('editor_unchanged_back', (tester) async {
    final note = Note(id: 'existing', title: 'Untouched', body: 'Keep');
    await openEditor(tester, note);
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pumpAndSettle();
    expect(find.text('Save your changes?'), findsNothing);
    expect(find.byType(NotesCreaterPage), findsNothing);
  });

  testWidgets('editor_repeated_back_opens_one_prompt', (tester) async {
    final note = Note.create();
    await openEditor(tester, note);
    await tester.enterText(field('note-body'), 'A draft');
    // Deliver both commands before a new frame, as two queued back actions.
    final back = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back),
    );
    back.onPressed!();
    back.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesCreaterPage), findsNothing);
    expect(note.isEmpty, isTrue);
  });
}
