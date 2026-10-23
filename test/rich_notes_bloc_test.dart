import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

void main() {
  test('rich search finds visible prose and tags but excludes storage keys',
      () async {
    final original = Note.create()..body = 'Rocket launch';
    final doc = NoteDocument.fromNote(original)..setTags(['Milestone']);
    final note = doc.toNote(original);
    final source = FakeNotesSource(notes: [note]);
    final bloc = NotesBloc(
        source: source, isSyncEnabled: () => false, isOnline: () async => true);
    addTearDown(bloc.close);
    for (final query in ['rocket', 'milestone', 'checklist']) {
      final changed = bloc.stream.firstWhere((s) => s.query == query);
      bloc.add(NotesQueryChanged(query));
      final state = await changed;
      expect(state.notes.map((n) => n.id),
          query == 'checklist' ? isEmpty : [note.id]);
    }
  });

  test('card toggle preserves rich styles tags and singleton delete recycles',
      () async {
    final original = Note.create()..body = 'Context';
    final doc = NoteDocument.fromNote(original)..setTags(['Inbox']);
    doc.replaceStyles(0, [const NoteStyleRun(0, 7, NoteTextStyle.bold)]);
    doc.insertChecklistAfter(0);
    doc.replaceText(1, 'Task');
    final note = doc.toNote(original);
    final source = FakeNotesSource(notes: [note]);
    final bloc = NotesBloc(
        source: source, isSyncEnabled: () => false, isOnline: () async => true);
    addTearDown(bloc.close);
    final toggled =
        bloc.stream.firstWhere((s) => s.notes.single.doneCount == 1);
    bloc.add(NoteItemToggled(note, 1));
    await toggled;
    final saved = source.byId(note.id)!;
    expect(NoteDocument.fromNote(saved).tags, ['Inbox']);
    expect(NoteDocument.fromNote(saved).lines.first.styles.single.flags,
        NoteTextStyle.bold);
    final deleted =
        bloc.stream.firstWhere((s) => s.binCount == 1 && s.notice != null);
    bloc.add(NoteDeleted(note.id));
    final state = await deleted;
    expect(state.notes, isEmpty);
    expect(source.deletedIds, [note.id]);
    expect(source.byId(note.id)!.deleted, isTrue);
    expect(source.byId(note.id)!.body, saved.body);
    expect(state.notice!.text, 'Note moved to the Recycle Bin');
  });
}
