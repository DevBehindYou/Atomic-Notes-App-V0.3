import 'package:atomic_notes/editor/rich_selection_toolbar.dart';
import 'package:atomic_notes/editor/rich_text_controller.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('style row above native actions stays open for combined toggles',
      (tester) async {
    final controller = RichNoteController(text: 'Selected words');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TextField(
      controller: controller,
      contextMenuBuilder: (context, state) => RichSelectionToolbar(
        editable: state,
        controller: controller,
      ),
    ))));
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.showToolbar();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Bold'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(
        tester.getBottomLeft(find.byKey(const ValueKey('note-format-bar'))).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('Copy')).dy));
    for (final label in ['Bold', 'Italic', 'Underline', 'Strikethrough']) {
      await tester.tap(find.byTooltip(label));
      await tester.pump();
      expect(controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 8));
      expect(find.text('Copy'), findsOneWidget);
    }
    expect(
        controller.styles.single.flags,
        NoteTextStyle.bold |
            NoteTextStyle.italic |
            NoteTextStyle.underline |
            NoteTextStyle.strike);
    final span = controller.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        style: const TextStyle(fontSize: 17),
        withComposing: true);
    expect(span.toPlainText(), 'Selected words');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(controller.selection.end, controller.text.length);
  });

  testWidgets('stacked menu stays inside keyboard viewport on narrow display',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.reset);
    final controller = RichNoteController(text: 'Select me');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TextField(
      controller: controller,
      contextMenuBuilder: (context, state) => RichSelectionToolbar(
        editable: state,
        controller: controller,
      ),
    ))));
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();
    final rect =
        tester.getRect(find.byKey(const ValueKey('note-selection-menu')));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.bottom, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });
}
