import 'dart:async';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_notes_source.dart';

class _DelayedSource extends FakeNotesSource {
  _DelayedSource(Note note) : super(notes: [note]);
  final entered = Completer<void>();
  final release = Completer<void>();
  int attempts = 0;
  @override
  Future<void> save(Note note) async {
    attempts++;
    if (attempts == 1) {
      entered.complete();
      await release.future;
    }
    await super.save(note);
  }
}

void main() {
  test('rapid mixed checkbox taps preserve both changes while save is delayed',
      () async {
    final note = Note(
        id: 'mixed',
        body: '- [ ] First\n- [ ] Second',
        items: [TodoItem(text: NoteDocument.formatMarker)]);
    final source = _DelayedSource(note);
    final bloc = NotesBloc(
        source: source, isSyncEnabled: () => true, isOnline: () async => true);
    addTearDown(() async {
      if (!source.release.isCompleted) source.release.complete();
      await bloc.close();
      source.dispose();
    });
    bloc.add(NoteItemToggled(note, 0));
    await source.entered.future;
    bloc.add(NoteItemToggled(note, 1));
    await Future<void>.delayed(Duration.zero);
    source.release.complete();
    for (var i = 0; i < 20 && source.saveCalls < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(source.saveCalls, 2);
    expect(source.byId('mixed')!.body, '- [x] First\n- [x] Second');
  });
  testWidgets(
      'mixed note keeps text and tasks visible and toggles only its task',
      (tester) async {
    tester.view.physicalSize = const Size(1290, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final note = Note(
        id: 'mixed',
        title: 'Mixed',
        body: 'Context\n- [x] Finished\n- [ ] Pending\nConclusion',
        items: [TodoItem(text: NoteDocument.formatMarker)]);
    final source = FakeNotesSource(notes: [note]);
    final bloc = NotesBloc(
        source: source, isSyncEnabled: () => true, isOnline: () async => true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await bloc.close();
      source.dispose();
    });
    await tester.pumpWidget(MaterialApp(
        home: BlocProvider.value(value: bloc, child: const HomePage())));
    await tester.pump();
    expect(find.text('Context'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Conclusion'), findsOneWidget);
    expect(find.text('1 / 2 DONE'), findsOneWidget);
    await tester.tap(find.text('Pending'));
    await tester.pump();
    await tester.pump();
    expect(source.byId('mixed')!.body,
        'Context\n- [x] Finished\n- [x] Pending\nConclusion');
    expect(find.text('2 / 2 DONE'), findsOneWidget);
    bloc.add(const NotesFilterChanged(NoteFilter.todos));
    await tester.pump();
    expect(bloc.state.notes.map((n) => n.id), ['mixed']);
    expect(source.syncCalls, 0);
  });
}
