import 'dart:collection';
import 'note.dart';

/// One visible row in a note. Its position is its position in [NoteDocument].
class NoteLine {
  const NoteLine.text(this.text)
      : isChecklist = false,
        done = false;
  const NoteLine.checklist(this.text, {this.done = false}) : isChecklist = true;

  final String text;
  final bool isChecklist;
  final bool done;

  NoteLine withText(String value) => isChecklist
      ? NoteLine.checklist(value, done: done)
      : NoteLine.text(value);
  NoteLine withDone(bool value) => NoteLine.checklist(text, done: value);
}

/// An editable line projection over the existing `kind/body/items` schema.
/// Unchanged notes retain their original fields, including legacy oddities.
class NoteDocument {
  // A reserved content record in the existing item schema, sealed with the
  // body by the vault. It opts in explicitly; legacy prose is never parsed.
  static const formatMarker = 'atomic-notes:task-lines:v1';
  static bool isEncoded(Note note) =>
      note.kind == NoteKind.text &&
      note.items.length == 1 &&
      note.items.single.text == formatMarker &&
      !note.items.single.done;
  NoteDocument._(this._sourceKind, this._lines) : _initial = List.of(_lines);

  final NoteKind _sourceKind;
  final List<NoteLine> _lines;
  final List<NoteLine> _initial;

  factory NoteDocument.fromNote(Note note) {
    if (note.kind == NoteKind.todo) {
      return NoteDocument._(NoteKind.todo, [
        if (note.body.isNotEmpty) NoteLine.text(note.body),
        for (final item in note.items)
          NoteLine.checklist(item.text, done: item.done),
      ]);
    }
    if (isEncoded(note)) {
      return NoteDocument._(NoteKind.text, _decodeBody(note.body));
    }
    return NoteDocument._(NoteKind.text, [
      NoteLine.text(note.body),
      for (final item in note.items)
        NoteLine.checklist(item.text, done: item.done),
    ]);
  }

  List<NoteLine> get lines => UnmodifiableListView(_lines);
  bool get isMixed =>
      _lines.any((line) => line.isChecklist) &&
      _lines.any((line) => !line.isChecklist);
  bool get hasChecklist => _lines.any((line) => line.isChecklist);
  bool get hasChanges =>
      _lines.length != _initial.length ||
      List.generate(_lines.length, (i) => i).any((i) =>
          _lines[i].text != _initial[i].text ||
          _lines[i].isChecklist != _initial[i].isChecklist ||
          _lines[i].done != _initial[i].done);

  void replaceText(int index, String text) {
    final line = _lines[index];
    if (line.text == text) return;
    _lines[index] = line.withText(text);
  }

  void setDone(int index, bool done) {
    final line = _lines[index];
    if (!line.isChecklist) throw StateError('not_checklist');
    if (line.done == done) return;
    _lines[index] = line.withDone(done);
  }

  int insertChecklistAfter(int index, {int? caretOffset}) =>
      _insertAfter(index, const NoteLine.checklist(''), caretOffset);

  int insertTextAfter(int index, {int? caretOffset}) =>
      _insertAfter(index, const NoteLine.text(''), caretOffset);

  int _insertAfter(int index, NoteLine newLine, int? caretOffset) {
    if (index < -1 || index >= _lines.length) {
      throw RangeError.index(index, _lines);
    }
    var insertAt = index + 1;
    if (index >= 0 && caretOffset != null && !_lines[index].isChecklist) {
      final line = _lines[index];
      final caret = caretOffset.clamp(0, line.text.length);
      final nextBreak = line.text.indexOf('\n', caret);
      if (nextBreak >= 0) {
        _lines[index] = NoteLine.text(line.text.substring(0, nextBreak));
        _lines.insert(
            insertAt, NoteLine.text(line.text.substring(nextBreak + 1)));
      }
    }
    _lines.insert(insertAt, newLine);
    return insertAt;
  }

  void removeAt(int index) {
    _lines.removeAt(index);
  }

  Note toNote(Note original) {
    final result = original.copy();
    if (!hasChanges) return result;
    if (_sourceKind == NoteKind.todo &&
        original.body.isEmpty &&
        _lines.every((line) => line.isChecklist)) {
      result.kind = NoteKind.todo;
      result.items = [
        for (final line in _lines) TodoItem(text: line.text, done: line.done),
      ];
      return result;
    }
    result.kind = NoteKind.text;
    result.body = hasChecklist
        ? _lines.map(_encode).join('\n')
        : _lines.map((line) => line.text).join('\n');
    result.items = hasChecklist ? [TodoItem(text: formatMarker)] : [];
    return result;
  }

  // Readable task-list syntax; two-space continuation lines belong to the
  // preceding checklist row. A backslash escapes marker/continuation prefixes.
  static final _escapable = RegExp(r'^\\*(?:- \[[ x]\] |  )');

  static List<NoteLine> _decodeBody(String body) {
    final result = <NoteLine>[];
    final prose = <String>[];
    void flush() {
      if (prose.isNotEmpty) {
        result.add(NoteLine.text(prose.join('\n')));
        prose.clear();
      }
    }

    for (final raw in body.split('\n')) {
      if (raw.startsWith(r'\') && _escapable.hasMatch(raw.substring(1))) {
        prose.add(raw.substring(1));
      } else if (raw.startsWith('- [ ] ') || raw.startsWith('- [x] ')) {
        flush();
        result.add(NoteLine.checklist(raw.substring(6),
            done: raw.startsWith('- [x] ')));
      } else if (raw.startsWith('  ') &&
          prose.isEmpty &&
          result.isNotEmpty &&
          result.last.isChecklist) {
        result[result.length - 1] =
            result.last.withText('${result.last.text}\n${raw.substring(2)}');
      } else {
        prose.add(raw);
      }
    }
    flush();
    return result;
  }

  static String _encode(NoteLine line) {
    if (line.isChecklist) {
      final parts = line.text.split('\n');
      final continuation = parts.skip(1).map((part) => '\n  $part').join();
      return '${line.done ? '- [x] ' : '- [ ] '}${parts.first}$continuation';
    }
    return line.text
        .split('\n')
        .map((text) => _escapable.hasMatch(text) ? '\\$text' : text)
        .join('\n');
  }
}
