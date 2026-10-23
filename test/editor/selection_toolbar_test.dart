import 'package:atomic_notes/editor/rich_selection_toolbar.dart';
import 'package:atomic_notes/editor/rich_text_controller.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'selected styles keep black outer gutters and separate touch targets',
      (tester) async {
    final controller = RichNoteController(text: 'Selected words');
    addTearDown(controller.dispose);
    const selection = TextSelection(baseOffset: 0, extentOffset: 14);
    controller.selection = selection;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(child: NoteFormatBar(controller: controller)))));
    for (var cycle = 0; cycle < 2; cycle++) {
      for (final label in [
        'Bold',
        'Italic',
        'Underline',
        'Strikethrough',
        'Heading'
      ]) {
        await tester.tap(find.byTooltip(label));
        await tester.pump();
        expect(controller.selection, selection);
        final button = tester.widget<IconButton>(find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == label));
        expect(button.isSelected, isTrue);
      }
      final bar = tester.getRect(find.byKey(const ValueKey('note-format-bar')));
      Rect? previous;
      for (final label in [
        'Bold',
        'Italic',
        'Underline',
        'Strikethrough',
        'Heading'
      ]) {
        final target = tester.getRect(find.byTooltip(label));
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
        expect(target.left - bar.left, greaterThanOrEqualTo(AppSpace.sm));
        expect(bar.right - target.right, greaterThanOrEqualTo(AppSpace.sm));
        expect(target.top - bar.top, greaterThanOrEqualTo(AppSpace.sm));
        expect(bar.bottom - target.bottom, greaterThanOrEqualTo(AppSpace.sm));
        if (previous != null) {
          expect(
              target.left - previous.right, greaterThanOrEqualTo(AppSpace.xs));
        }
        previous = target;
      }
      expect(controller.styles.single.flags, NoteTextStyle.all);
      for (final label in [
        'Bold',
        'Italic',
        'Underline',
        'Strikethrough',
        'Heading'
      ]) {
        await tester.tap(find.byTooltip(label));
        await tester.pump();
        expect(controller.selection, selection);
      }
      expect(controller.styles, isEmpty);
    }
    expect(tester.takeException(), isNull);
  });
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
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
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
    await tester.ensureVisible(find.byTooltip('Heading'));
    await tester.tap(find.byTooltip('Heading'));
    await tester.pump();
    expect(controller.hasStyle(NoteTextStyle.heading), isTrue);
    expect(controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6));
    expect(find.text('Copy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
