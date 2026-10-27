import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/utility/component/notes_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

void main() {
  testWidgets('cards hide tags while tag search and task toggles retain them',
      (tester) async {
    tester.view.physicalSize = const Size(1290, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final original = Note(
        id: 'tagged-card',
        title: 'Release plan',
        body: 'Keep the body preview',
        pinned: true,
        important: true);
    final document = NoteDocument.fromNote(original)
      ..setTags(['Milestone', 'Work', 'Launch'])
      ..insertChecklistAfter(0)
      ..replaceText(1, 'Ship the release');
    final note = document.toNote(original);
    final source = FakeNotesSource(notes: [
      note,
      Note(id: 'other', title: 'Unrelated', body: 'Another note'),
    ]);
    final bloc = NotesBloc(
        source: source, isSyncEnabled: () => false, isOnline: () async => true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await bloc.close();
      source.dispose();
    });
    await tester.pumpWidget(MaterialApp(
        home: BlocProvider.value(value: bloc, child: const HomePage())));
    await tester.pump();
    final card = find.byWidgetPredicate(
        (widget) => widget is NotesBulder && widget.note.id == note.id);
    expect(card, findsOneWidget);
    expect(find.textContaining('#Milestone'), findsNothing);
    expect(find.text('Keep the body preview'), findsOneWidget);
    expect(find.text('Ship the release'), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byIcon(Icons.push_pin)),
        findsOneWidget);
    expect(
        find.descendant(of: card, matching: find.byIcon(Icons.label_important)),
        findsOneWidget);

    bloc.add(const NotesQueryChanged('mIlEsToNe'));
    await tester.pump();
    await tester.pump();
    expect(bloc.state.notes.map((note) => note.id), ['tagged-card']);
    expect(find.text('UNRELATED'), findsNothing);
    expect(card, findsOneWidget);
    expect(find.textContaining('#Milestone'), findsNothing);

    await tester.tap(find.text('Ship the release'));
    await tester.pump();
    await tester.pump();
    final saved = source.byId(note.id)!;
    final reopened = NoteDocument.fromNote(saved);
    expect(reopened.tags, ['Milestone', 'Work', 'Launch']);
    expect(reopened.lines.first.text, 'Keep the body preview');
    expect(reopened.lines[1].done, isTrue);
    expect(saved.pinned, isTrue);
    expect(saved.important, isTrue);
    expect(find.text('1 / 1 DONE'), findsOneWidget);
    expect(find.textContaining('#Milestone'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
