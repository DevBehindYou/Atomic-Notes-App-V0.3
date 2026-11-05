import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/utility/component/notes_builder.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('prose card saves vertical space without shrinking body type',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 350,
                child: NotesBulder(
                    note:
                        Note(id: 'prose', title: 'Title', body: 'Visible body'),
                    selected: false,
                    selectionMode: false,
                    onTap: () {},
                    onLongPress: () {},
                    onToggleItem: (_) {})))));
    final card = find.byType(NotesBulder);
    expect(tester.getSize(card).height, lessThan(100));
    expect(tester.widget<Text>(find.text('Visible body')).style!.fontSize,
        AppType.bodyMd.fontSize);
  });

  testWidgets(
      'checklist row has a 48 pixel toggle target and selection keeps card control',
      (tester) async {
    var toggles = 0;
    var selections = 0;
    final note =
        Note(id: 'todo', kind: NoteKind.todo, items: [TodoItem(text: 'Task')]);
    Future<void> pump(bool selecting) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 350,
                child: NotesBulder(
                    note: note,
                    selected: selecting,
                    selectionMode: selecting,
                    onTap: () => selections++,
                    onLongPress: () {},
                    onToggleItem: (_) => toggles++)))));
    await pump(false);
    final row = find
        .ancestor(of: find.text('Task'), matching: find.byType(GestureDetector))
        .first;
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    await tester.tapAt(tester.getTopLeft(row) + const Offset(20, 44));
    expect(toggles, 1);
    await pump(true);
    await tester.tap(find.text('Task'));
    expect(toggles, 1);
    expect(selections, 1);
  });
}
