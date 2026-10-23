import 'package:atomic_notes/database/note_rich_content.dart';
import 'package:atomic_notes/editor/rich_text_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<int>> runs(RichNoteController c) =>
    c.styles.map((r) => [r.start, r.end, r.flags]).toList();

void main() {
  test('selected toggles combine, split, and preserve selection', () {
    final c = RichNoteController(text: 'abcdef');
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    c.toggleStyle(NoteTextStyle.bold);
    c.toggleStyle(NoteTextStyle.italic);
    expect(c.hasStyle(NoteTextStyle.bold), isTrue);
    expect(runs(c), [
      [1, 5, 3]
    ]);
    expect(c.selection, const TextSelection(baseOffset: 1, extentOffset: 5));
    c.selection = const TextSelection(baseOffset: 2, extentOffset: 4);
    c.toggleStyle(NoteTextStyle.bold);
    expect(runs(c), [
      [1, 2, 3],
      [2, 4, 2],
      [4, 5, 3]
    ]);
  });

  test('caret style applies to typing until moved', () {
    final c = RichNoteController(text: 'ab');
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 1);
    c.toggleStyle(NoteTextStyle.underline);
    expect(c.hasStyle(NoteTextStyle.underline), isTrue);
    c.value = const TextEditingValue(
        text: 'aXYb', selection: TextSelection.collapsed(offset: 3));
    expect(runs(c), [
      [1, 3, 4]
    ]);
    c.selection = const TextSelection.collapsed(offset: 0);
    expect(c.hasStyle(NoteTextStyle.underline), isFalse);
    c.value = const TextEditingValue(
        text: '!aXYb', selection: TextSelection.collapsed(offset: 1));
    expect(runs(c), [
      [2, 4, 4]
    ]);
  });

  test('replacement and backspace transform ranges at actual caret', () {
    final c = RichNoteController(
        text: 'aaaa', styles: const [NoteStyleRun(1, 3, NoteTextStyle.bold)]);
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 2);
    c.value = const TextEditingValue(
        text: 'aaa', selection: TextSelection.collapsed(offset: 1));
    expect(runs(c), [
      [1, 2, 1]
    ]);
    c.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    c.value = const TextEditingValue(
        text: 'aHELLOa', selection: TextSelection.collapsed(offset: 6));
    expect(runs(c), [
      [1, 6, 1]
    ]);
  });

  test('UTF16 emoji offsets remain intact through insertion and deletion', () {
    final c = RichNoteController(
        text: 'a😀b', styles: const [NoteStyleRun(1, 3, NoteTextStyle.strike)]);
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 0);
    c.value = const TextEditingValue(
        text: '!a😀b', selection: TextSelection.collapsed(offset: 1));
    expect(runs(c), [
      [2, 4, 8]
    ]);
    c.selection = const TextSelection.collapsed(offset: 4);
    c.value = const TextEditingValue(
        text: '!ab', selection: TextSelection.collapsed(offset: 2));
    expect(c.styles, isEmpty);
  });

  test('heading toggles complete paragraphs without changing selection', () {
    final c = RichNoteController(text: 'one\ntwo\nthree');
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 1, extentOffset: 6);
    c.toggleStyle(NoteTextStyle.heading);
    expect(runs(c), [
      [0, 7, 16]
    ]);
    expect(c.selection, const TextSelection(baseOffset: 1, extentOffset: 6));
    c.selection = const TextSelection.collapsed(offset: 5);
    c.toggleStyle(NoteTextStyle.heading);
    expect(runs(c), [
      [0, 4, 16]
    ]);
  });

  test('selection ending at next paragraph start excludes that paragraph', () {
    final c = RichNoteController(text: 'one\ntwo');
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    c.toggleStyle(NoteTextStyle.heading);
    expect(runs(c), [
      [0, 3, 16]
    ]);
  });

  test(
      'empty paragraph can start heading and ordinary caret toggles twice cancel',
      () {
    final c = RichNoteController();
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 0);
    c.toggleStyle(NoteTextStyle.bold);
    c.toggleStyle(NoteTextStyle.bold);
    expect(c.hasStyle(NoteTextStyle.bold), isFalse);
    c.toggleStyle(NoteTextStyle.heading);
    c.value = const TextEditingValue(
        text: 'title', selection: TextSelection.collapsed(offset: 5));
    expect(runs(c), [
      [0, 5, 16]
    ]);
  });

  test('forward delete keeps the surviving identical characters styles', () {
    final c =
        RichNoteController(text: 'aaaa', styles: const [NoteStyleRun(1, 2, 1)]);
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 1);
    c.value = const TextEditingValue(
        text: 'aaa', selection: TextSelection.collapsed(offset: 1));
    expect(c.styles, isEmpty);
  });

  test('IME replacement inherits styles without losing the composing range',
      () {
    final c =
        RichNoteController(text: 'a', styles: const [NoteStyleRun(0, 1, 3)]);
    addTearDown(c.dispose);
    c.value = const TextEditingValue(
        text: 'a',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1));
    c.value = const TextEditingValue(
        text: 'あ',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1));
    expect(runs(c), [
      [0, 1, 3]
    ]);
    expect(c.value.composing, const TextRange(start: 0, end: 1));
  });

  test('format-only actions notify listeners while preserving editing value',
      () {
    final c = RichNoteController(text: 'hello');
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    final before = c.value;
    var notified = 0;
    c.addListener(() => notified++);
    c.toggleStyle(NoteTextStyle.bold);
    c.toggleStyle(NoteTextStyle.underline);
    expect(notified, 2);
    expect(c.value, before);
    expect(runs(c), [
      [0, 5, 5]
    ]);
  });

  testWidgets('heading renders at 1.25 size and composing can be hidden',
      (tester) async {
    final c = RichNoteController(
        text: 'title', styles: const [NoteStyleRun(0, 5, 16)]);
    addTearDown(c.dispose);
    c.value = c.value.copyWith(composing: const TextRange(start: 0, end: 5));
    late BuildContext context;
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        })));
    final span = c.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 16),
        withComposing: false);
    final child = span.children!.single as TextSpan;
    expect(child.style!.fontSize, 20);
    expect(child.style!.fontWeight, FontWeight.bold);
    expect(child.style!.decoration, isNull);
  });

  test('constructor canonicalizes overlaps invalid ranges and emoji boundaries',
      () {
    final c = RichNoteController(text: 'a😀b', styles: const [
      NoteStyleRun(-2, 1, 1),
      NoteStyleRun(1, 3, 1),
      NoteStyleRun(2, 10, 2),
      NoteStyleRun(4, 2, 8),
    ]);
    addTearDown(c.dispose);
    expect(runs(c), [
      [0, 1, 1],
      [1, 3, 3],
      [3, 4, 2]
    ]);
    expect(() => c.styles.add(const NoteStyleRun(0, 1, 4)),
        throwsUnsupportedError);
  });

  testWidgets('rendering combines composing and strike decorations',
      (tester) async {
    final c =
        RichNoteController(text: 'abc', styles: const [NoteStyleRun(0, 3, 8)]);
    addTearDown(c.dispose);
    c.value = c.value.copyWith(composing: const TextRange(start: 1, end: 2));
    late BuildContext context;
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        })));
    final before = c.value;
    c.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    c.toggleStyle(NoteTextStyle.bold);
    expect(c.value.composing, before.composing);
    final span = c.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 16),
        withComposing: true);
    expect(span.toPlainText(), 'abc');
    final middle =
        span.children!.cast<TextSpan>().firstWhere((s) => s.text == 'b');
    expect(middle.style!.fontWeight, FontWeight.bold);
    expect(
        middle.style!.decoration!.contains(TextDecoration.underline), isTrue);
    expect(
        middle.style!.decoration!.contains(TextDecoration.lineThrough), isTrue);
  });
}
