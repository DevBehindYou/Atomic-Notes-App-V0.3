import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/editor/note_image_viewer.dart';
import 'package:atomic_notes/editor/rich_selection_toolbar.dart';
import 'package:atomic_notes/editor/rich_text_controller.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

// C10: semantics, target size, contrast, large text and keyboard order for the
// editor, its formatting bar, image controls and dialogs. These run in the
// widget tester only; TalkBack and VoiceOver on devices remain unverified.

String _jpeg() =>
    base64Encode(image.encodeJpg(image.Image(width: 16, height: 12)));

/// Prose, one checklist item and one image, with one tag.
Note _mixed() => Note(
      id: 'a11y',
      title: 'Groceries',
      body: jsonEncode({
        'v': 2,
        'tags': ['keep'],
        'blocks': [
          {'text': 'Prose', 'checklist': false, 'done': false, 'styles': []},
          {'text': 'Item', 'checklist': true, 'done': false, 'styles': []},
          {
            'text': '',
            'checklist': false,
            'done': false,
            'styles': [],
            'image': _jpeg()
          },
        ],
      }),
      items: [TodoItem(text: NoteDocument.richFormatMarker)],
    );

Widget _scaled(double scale, Widget home) => MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: home,
    );

Future<void> _open(WidgetTester tester, Note note,
    {double scale = 1, Size size = const Size(390, 844)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_scaled(
      scale,
      Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => NotesCreaterPage(note: note)),
                  child: const Text('Open'),
                ),
              ))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Scrolls the editor's lazy list until [target] is built and visible.
Future<void> _reveal(WidgetTester tester, Finder target,
    {double delta = 100}) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, delta,
        scrollable: find
            .descendant(
                of: find.byType(NotesCreaterPage),
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _expectGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// What a keyboard user lands on: a field's position name, a control's
/// tooltip or checkbox label, or a button's text.
String _describe(FocusNode? node) {
  final context = node?.context;
  if (context == null) return 'none';
  final field = context.findAncestorWidgetOfExactType<TextField>();
  if (field != null) return 'field ${field.key}';
  final tip = context.findAncestorWidgetOfExactType<Tooltip>();
  if (tip != null) return tip.message!;
  final box = context.findAncestorWidgetOfExactType<Checkbox>();
  if (box != null) return box.semanticLabel!;
  String? text;
  void visit(Element element) {
    final widget = element.widget;
    if (text == null && widget is Text) text = widget.data;
    if (text == null) element.visitChildElements(visit);
  }

  (context as Element).visitChildElements(visit);
  return text ?? context.widget.runtimeType.toString();
}

void main() {
  testWidgets('editor controls meet target, label and contrast guidelines',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, _mixed());
    await _expectGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('formatting buttons are named by style, not by glyph',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = RichNoteController(text: 'hello');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(child: NoteFormatBar(controller: controller)))));
    for (final (glyph, name) in [
      ('B', 'Bold'),
      ('I', 'Italic'),
      ('U', 'Underline'),
      ('S', 'Strikethrough'),
      ('H', 'Heading'),
    ]) {
      expect(
          tester.getSemantics(find.byTooltip(name)),
          isSemantics(
              label: '',
              tooltip: name,
              isButton: true,
              hasTapAction: true,
              hasToggledState: true,
              isToggled: false),
          reason: '$name must not also be announced as "$glyph"');
      expect(find.bySemanticsLabel(glyph), findsNothing);
    }
    // The on/off state is reported on the button node and follows the style.
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();
    expect(controller.hasStyle(NoteTextStyle.bold), isTrue);
    expect(tester.getSemantics(find.byTooltip('Bold')),
        isSemantics(tooltip: 'Bold', isButton: true, isToggled: true));
    await _expectGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('image thumbnail is one named button', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, _mixed());
    expect(
        tester.getSemantics(find.byTooltip('View note image')),
        isSemantics(
            label: 'View note image',
            tooltip: '',
            isButton: true,
            hasTapAction: true));
    // No second, inert "Note image" stop inside the button.
    expect(find.bySemanticsLabel('Note image'), findsNothing);
    expect(tester.getSemantics(find.widgetWithText(TextButton, 'Remove image')),
        isSemantics(label: 'Remove image', isButton: true, hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('add tag control announces its action', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, _mixed());
    expect(tester.getSemantics(find.widgetWithText(TextButton, 'Tag')),
        isSemantics(label: 'Add tag', isButton: true, hasTapAction: true));
    expect(
        tester.getSemantics(find.byTooltip('Remove tag keep')),
        isSemantics(
            tooltip: 'Remove tag keep', isButton: true, hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('filled fields keep their names once the hint is hidden',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, _mixed());
    final key = find.byKey;
    expect(tester.getSemantics(key(const ValueKey('note-title'))),
        isSemantics(label: 'Title', value: 'Groceries', isTextField: true));
    expect(tester.getSemantics(key(const ValueKey('note-body'))),
        isSemantics(label: 'Note text', value: 'Prose', isTextField: true));
    expect(tester.getSemantics(key(const ValueKey('note-item-1'))),
        isSemantics(label: 'List item', value: 'Item', isTextField: true));
    expect(
        tester.getSemantics(find.byType(Checkbox)),
        isSemantics(
            label: 'Complete item 2', hasCheckedState: true, isChecked: false));

    // An empty field is named once, by its visible hint.
    await tester.enterText(key(const ValueKey('note-title')), '');
    // The hint fades back in before it is reported.
    await tester.pumpAndSettle();
    expect(tester.getSemantics(key(const ValueKey('note-title'))),
        isSemantics(label: 'Title', value: '', isTextField: true));
    semantics.dispose();
  });

  testWidgets('empty new note names its fields by their hints', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, Note.create());
    expect(tester.getSemantics(find.byKey(const ValueKey('note-title'))),
        isSemantics(label: 'Title', isTextField: true));
    expect(tester.getSemantics(find.byKey(const ValueKey('note-body'))),
        isSemantics(label: 'Start writing…', isTextField: true));
    semantics.dispose();
  });

  testWidgets('2x text: editor, dialogs and format bar fit and stay usable',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, _mixed(), scale: 2, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(find.text('Done').hitTestable(), findsOneWidget);
    await _expectGuidelines(tester);

    await _reveal(tester, find.text('Tag'));
    await tester.tap(find.text('Tag'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add').hitTestable(), findsOneWidget);
    await _expectGuidelines(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await _reveal(tester, find.byKey(const ValueKey('note-title')),
        delta: -100);
    await tester.enterText(find.byKey(const ValueKey('note-title')), 'Edited');
    await tester.pump();
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final action in ['Keep editing', 'Discard', 'Save']) {
      await tester.ensureVisible(find.text(action));
      await tester.pumpAndSettle();
      expect(find.text(action).hitTestable(), findsOneWidget);
    }
    await _expectGuidelines(tester);

    final controller = RichNoteController(text: 'hello');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_scaled(
        2,
        Scaffold(
            body: Center(
                child: SizedBox(
                    width: 304,
                    child: NoteFormatBar(controller: controller))))));
    expect(tester.takeException(), isNull);
    await _expectGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('image viewer controls are named and meet guidelines at 2x',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    final bytes = base64Decode(_jpeg());
    await tester.pumpWidget(_scaled(
        2,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => NoteImageViewer(bytes: bytes)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pump();
    final full = find.bySemanticsLabel('Full size note image');
    for (var attempt = 0; attempt < 100 && full.evaluate().isEmpty; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(full, findsOneWidget);
    for (final name in ['Close image', 'Zoom in', 'Reset zoom']) {
      expect(find.byTooltip(name), findsOneWidget);
    }
    await _expectGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('Tab moves header, title, tags, lines, then bottom controls',
      (tester) async {
    await _open(tester, _mixed());
    final order = <String>[];
    for (var step = 0; step < 19; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(_describe(FocusManager.instance.primaryFocus));
    }
    expect(order, [
      'Back to notes',
      'Pin note',
      'Mark important',
      'Copy note',
      "field [<'note-title'>]",
      'Remove tag keep',
      'Add tag',
      'field [_LineKey note-body]',
      'Complete item 2',
      'field [_LineKey note-item-1]',
      'Remove item 2',
      'View note image',
      'Remove image',
      'Add text line',
      'Add checklist line',
      'Add image',
      'Dictate text',
      'Delete note',
      'Done',
    ]);
    // Focus wraps back to the first header control.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_describe(FocusManager.instance.primaryFocus), 'Back to notes');
  });
}
