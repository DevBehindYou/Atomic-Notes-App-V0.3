import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy literal Markdown stays plain text until explicit insertion', () {
    final note = Note(id: 'legacy', body: '- [ ] literal\n- [x] example');
    final document = NoteDocument.fromNote(note);
    expect(document.hasChecklist, isFalse);
    expect(document.lines.single.text, note.body);
    document.insertChecklistAfter(0);
    document.replaceText(1, 'New actual task');
    final reopened = NoteDocument.fromNote(document.toNote(note));
    expect(reopened.lines.first.text, note.body);
    expect(reopened.lines.first.isChecklist, isFalse);
    expect(reopened.lines.last.isChecklist, isTrue);
  });
  test('unchanged plain text and legacy todo retain exact wire content', () {
    final text = Note(id: 'text', body: 'A\r\n\r\nA\n');
    final todo = Note(
        id: 'todo',
        kind: NoteKind.todo,
        body: 'legacy body\n',
        items: [
          TodoItem(text: ''),
          TodoItem(text: 'A', done: true),
          TodoItem(text: 'A')
        ]);
    expect(
        NoteDocument.fromNote(text).toNote(text).contentSig, text.contentSig);
    expect(
        NoteDocument.fromNote(todo).toNote(todo).contentSig, todo.contentSig);
  });

  test('insert checklist after caret line without splitting existing words',
      () {
    final note = Note(id: 'text', body: 'BeforeAfter\n\nDuplicate\nDuplicate');
    final document = NoteDocument.fromNote(note);
    document.insertChecklistAfter(0, caretOffset: 6);
    document.replaceText(1, 'Task');
    document.setDone(1, true);
    final saved = document.toNote(note);
    expect(saved.kind, NoteKind.text);
    expect(NoteDocument.isEncoded(saved), isTrue);
    expect(saved.body, 'BeforeAfter\n- [x] Task\n\nDuplicate\nDuplicate');
    final reopened = NoteDocument.fromNote(saved);
    expect(reopened.lines[1].isChecklist, isTrue);
    expect(reopened.lines[1].done, isTrue);
    expect(reopened.lines[2].text, '\nDuplicate\nDuplicate');
  });

  test('mixing legacy checklist with text preserves done order and blanks', () {
    final note =
        Note(id: 'todo', kind: NoteKind.todo, body: 'legacy body', items: [
      TodoItem(text: 'Same', done: true),
      TodoItem(text: ''),
      TodoItem(text: 'Same'),
    ]);
    final document = NoteDocument.fromNote(note);
    document.insertTextAfter(1);
    document.replaceText(2, 'Context');
    final saved = document.toNote(note);
    expect(saved.kind, NoteKind.text);
    expect(NoteDocument.isEncoded(saved), isTrue);
    expect(saved.body, 'legacy body\n- [x] Same\nContext\n- [ ] \n- [ ] Same');
  });

  test('multiline and escaped marker content survives mixed save and reopen',
      () {
    final note = Note(id: 'todo', kind: NoteKind.todo, items: [
      TodoItem(text: 'First\nSecond', done: true),
    ]);
    final document = NoteDocument.fromNote(note);
    document.insertTextAfter(0);
    document.replaceText(1, '  prose\n\\\\- [ ] literal\n- [ ] also literal');
    final reopened = NoteDocument.fromNote(document.toNote(note));
    expect(reopened.lines[0].text, 'First\nSecond');
    expect(reopened.lines[0].done, isTrue);
    expect(reopened.lines[1].text,
        '  prose\n\\\\- [ ] literal\n- [ ] also literal');
    expect(reopened.lines[1].isChecklist, isFalse);
  });

  test('undoing a draft edit leaves original wire representation unchanged',
      () {
    final note = Note(id: 'literal', body: r'\- [ ] literal');
    final document = NoteDocument.fromNote(note);
    final original = document.lines.single.text;
    document.replaceText(0, 'changed');
    document.replaceText(0, original);
    expect(document.toNote(note).toMap(), note.toMap());
  });

  test('literal marker lines use an explicit backslash escape', () {
    final note = Note(
        id: 'literal',
        body: r'\- [ ] this is text',
        items: [TodoItem(text: NoteDocument.formatMarker)]);
    final document = NoteDocument.fromNote(note);
    expect(document.lines.single.isChecklist, isFalse);
    expect(document.lines.single.text, '- [ ] this is text');
    expect(document.toNote(note).body, note.body);
  });
}
