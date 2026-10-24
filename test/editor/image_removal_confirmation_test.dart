import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/editor/editor_popup.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

String _jpeg(int width) =>
    base64Encode(image.encodeJpg(image.Image(width: width, height: 12)));

Note _note({bool checklistFirst = false}) => Note(
      id: 'remove-images',
      title: 'Images',
      body: jsonEncode({
        'v': 2,
        'tags': ['keep'],
        'blocks': [
          {
            'text': 'Keep prose',
            'checklist': checklistFirst,
            'done': false,
            'styles': []
          },
          for (final width in [16, 24])
            {
              'text': '',
              'checklist': false,
              'done': false,
              'styles': [],
              'image': _jpeg(width)
            },
        ],
      }),
      items: [TodoItem(text: NoteDocument.richFormatMarker)],
    );

Future<void> _open(WidgetTester tester, Note note,
    {double scale = 1, double keyboard = 0}) async {
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
                onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => NotesCreaterPage(note: note)),
                child: const Text('Open'),
              ),
            )),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder get _remove => find.widgetWithText(TextButton, 'Remove image').first;
Finder get _confirm => find.widgetWithText(FilledButton, 'Remove image');
Future<void> _requestRemoval(WidgetTester tester) async {
  final candidates = find.widgetWithText(TextButton, 'Remove image');
  if (candidates.evaluate().isEmpty) {
    await tester.scrollUntilVisible(candidates, 100,
        scrollable: find
            .descendant(
                of: find.byType(NotesCreaterPage),
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(_remove);
  await tester.pumpAndSettle();
  await tester.tap(_remove);
  await tester.pumpAndSettle();
}

Future<void> _done(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Done'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('image removal requires a themed explicit decision',
      (tester) async {
    final note = _note();
    final before = note.toMap();
    await _open(tester, note);
    await _requestRemoval(tester);
    expect(find.widgetWithText(EditorPopup, 'Remove image?'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Keep image'), findsOneWidget);
    expect(_confirm, findsOneWidget);
    final destructive = tester.widget<FilledButton>(_confirm);
    expect(destructive.style!.backgroundColor!.resolve({}), AppColors.error);
    expect(note.toMap(), before);
  });

  testWidgets('keep, Back and barrier preserve all image bytes and prose',
      (tester) async {
    final note = _note();
    final before = note.toMap();
    await _open(tester, note);
    for (final dismiss in ['keep', 'back', 'barrier']) {
      await _requestRemoval(tester);
      expect(find.text('Remove image?'), findsOneWidget);
      if (dismiss == 'keep') {
        await tester.tap(find.text('Keep image'));
      } else if (dismiss == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(2, 24));
      }
      await tester.pumpAndSettle();
      expect(find.text('Remove image?'), findsNothing);
      expect(note.toMap(), before);
    }
    await _done(tester);
    expect(note.toMap(), before);
  });

  testWidgets('keeping an image preserves unsaved prose and text selection',
      (tester) async {
    final note = _note();
    final before = note.toMap();
    await _open(tester, note);
    final body = find.byKey(const ValueKey('note-body'));
    await tester.enterText(body, 'Unsaved prose stays');
    final controller = tester.widget<TextField>(body).controller!;
    const selection = TextSelection(baseOffset: 2, extentOffset: 7);
    controller.selection = selection;
    await tester.pump();
    await _requestRemoval(tester);
    await tester.tap(find.text('Keep image'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Unsaved prose stays');
    expect(controller.selection, selection);
    expect(note.toMap(), before);
  });

  testWidgets('confirm removes only selected image and persists only on Done',
      (tester) async {
    final note = _note();
    final before = note.toMap();
    await _open(tester, note);
    await _requestRemoval(tester);
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    expect(find.text('Remove image?'), findsNothing);
    expect(note.toMap(), before, reason: 'confirmation changes only the draft');
    await _done(tester);
    final saved = NoteDocument.fromNote(note);
    expect(saved.lines.first.text, 'Keep prose');
    expect(saved.tags, ['keep']);
    expect(
        saved.lines
            .where((line) => line.isImage)
            .map((line) => line.imageBase64),
        [_jpeg(24)]);
  });

  testWidgets('removal follows image identity when an earlier row changes',
      (tester) async {
    final note = _note(checklistFirst: true);
    await _open(tester, note);
    final removeEarlier = tester
        .widget<IconButton>(find.byWidgetPredicate((widget) =>
            widget is IconButton && widget.tooltip == 'Remove item 1'))
        .onPressed!;
    await _requestRemoval(tester);
    // Simulate an independent row mutation while the asynchronous decision is
    // pending. The original image, rather than its now-stale index, is removed.
    removeEarlier();
    await tester.pumpAndSettle();
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    await _done(tester);
    final saved = NoteDocument.fromNote(note);
    expect(
        saved.lines
            .where((line) => line.isImage)
            .map((line) => line.imageBase64),
        [_jpeg(24)]);
  });

  testWidgets('repeated requests open one image decision only', (tester) async {
    final note = _note();
    final before = note.toMap();
    await _open(tester, note);
    final request = tester.widget<TextButton>(_remove).onPressed!;
    request();
    request();
    await tester.pumpAndSettle();
    expect(find.text('Remove image?'), findsOneWidget);
    await tester.tap(find.text('Keep image'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorPopup), findsNothing);
    expect(note.toMap(), before);
  });

  testWidgets('large-text narrow popup keeps both decisions reachable',
      (tester) async {
    final note = _note();
    final before = note.toMap();
    await _open(tester, note, scale: 2, keyboard: 260);
    await _requestRemoval(tester);
    for (final target in [
      find.widgetWithText(OutlinedButton, 'Keep image'),
      _confirm
    ]) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(find.text('Keep image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep image'));
    await tester.pumpAndSettle();
    expect(note.toMap(), before);
  });
}
