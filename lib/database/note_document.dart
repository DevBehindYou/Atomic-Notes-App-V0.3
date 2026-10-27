import 'dart:collection';
import 'dart:convert';
import 'package:characters/characters.dart';
import 'note.dart';
import 'note_rich_content.dart';
export 'note_rich_content.dart';

/// One visible row in a note. Its position is its position in [NoteDocument].
class NoteLine {
  const NoteLine.text(this.text, {this.styles = const []})
      : isChecklist = false,
        done = false,
        imageBase64 = null;
  const NoteLine.checklist(this.text,
      {this.done = false, this.styles = const []})
      : isChecklist = true,
        imageBase64 = null;
  const NoteLine.image(String base64)
      : text = '',
        isChecklist = false,
        done = false,
        styles = const [],
        imageBase64 = base64;

  final String text;
  final bool isChecklist;
  final bool done;
  final List<NoteStyleRun> styles;
  final String? imageBase64;
  bool get isImage => imageBase64 != null;

  NoteLine withText(String value) {
    if (isImage) throw StateError('not_text');
    final clamped = styles
        .where((r) => r.start < value.length)
        .map((r) =>
            NoteStyleRun(r.start, r.end.clamp(r.start, value.length), r.flags))
        .toList();
    return isChecklist
        ? NoteLine.checklist(value,
            done: done, styles: List.unmodifiable(clamped))
        : NoteLine.text(value, styles: List.unmodifiable(clamped));
  }

  NoteLine withDone(bool value) =>
      NoteLine.checklist(text, done: value, styles: styles);
  NoteLine withStyles(List<NoteStyleRun> value) {
    if (isImage || value.any((r) => !r.validFor(text))) {
      throw const FormatException('Invalid note formatting');
    }
    return isChecklist
        ? NoteLine.checklist(text, done: done, styles: List.unmodifiable(value))
        : NoteLine.text(text, styles: List.unmodifiable(value));
  }
}

/// An editable line projection over the existing `kind/body/items` schema.
/// Unchanged notes retain their original fields, including legacy oddities.
class NoteDocument {
  // A reserved content record in the existing item schema, sealed with the
  // body by the vault. It opts in explicitly; legacy prose is never parsed.
  static const formatMarker = 'atomic-notes:task-lines:v1';
  static const richFormatMarker = 'atomic-notes:rich-document:v2';
  // Insertion policy only; the decoder still accepts existing legacy tags.
  static const maxTagsPerNote = 3;
  static const maxTagCharacters = 15;

  // An insertion rule, not a decoder/save bound: older notes may contain more
  // images and must remain editable without losing existing content.
  static const maxImagesPerNote = 3;
  static const imageLimitMessage =
      'Use up to 3 images per note. Remove an image first.';
  static const _richPrefix = 'atomic-notes:rich-document:';
  static bool hasRichContent(Note note) =>
      note.kind == NoteKind.text &&
      note.items.length == 1 &&
      !note.items.single.done &&
      note.items.single.text.startsWith(_richPrefix);
  static bool isEncoded(Note note) =>
      note.kind == NoteKind.text &&
      note.items.length == 1 &&
      note.items.single.text == formatMarker &&
      !note.items.single.done;
  NoteDocument._(this._sourceKind, this._lines,
      {List<String> tags = const [],
      this.isReadOnly = false,
      bool rich = false})
      : _initial = List.of(_lines),
        _tags = List.of(tags),
        _initialTags = List.of(tags),
        _wasRich = rich;

  final NoteKind _sourceKind;
  final List<NoteLine> _lines;
  final List<NoteLine> _initial;
  final List<String> _tags;
  final List<String> _initialTags;
  final bool _wasRich;
  final bool isReadOnly;

  factory NoteDocument.fromNote(Note note) {
    final reserved = hasRichContent(note);
    if (reserved) {
      try {
        if (note.kind != NoteKind.text ||
            note.items.length != 1 ||
            note.items.single.done ||
            note.items.single.text != richFormatMarker ||
            note.body.length > NoteContentBudget.maxBodyLength) {
          throw const FormatException('Unsupported rich format');
        }
        final raw = jsonDecode(note.body);
        if (raw is! Map ||
            raw['v'] != 2 ||
            raw['tags'] is! List ||
            raw['blocks'] is! List ||
            raw.keys.any((k) => !['v', 'tags', 'blocks'].contains(k))) {
          throw const FormatException('Invalid rich document');
        }
        final tags = _checkedTags((raw['tags'] as List).cast<String>());
        final lines = <NoteLine>[];
        var bytes = 0;
        for (final block in raw['blocks'] as List) {
          if (block is! Map ||
              block['text'] is! String ||
              block['checklist'] is! bool ||
              block['done'] is! bool ||
              block['styles'] is! List ||
              block.keys.any((k) => ![
                    'text',
                    'checklist',
                    'done',
                    'styles',
                    'image'
                  ].contains(k))) {
            throw const FormatException('Invalid rich block');
          }
          final text = block['text'] as String;
          final styles =
              (block['styles'] as List).map(NoteStyleRun.fromJson).toList();
          if (styles.any((r) => !r.validFor(text))) {
            throw const FormatException('Invalid style range');
          }
          if (block.containsKey('image')) {
            if (block['image'] is! String ||
                text.isNotEmpty ||
                block['checklist'] == true ||
                block['done'] == true ||
                styles.isNotEmpty) {
              throw const FormatException('Invalid image block');
            }
            bytes += NoteImageContent.decode(block['image'] as String).length;
            if (bytes > NoteContentBudget.maxImageBytes) {
              throw const FormatException('Images too large');
            }
            lines.add(NoteLine.image(block['image'] as String));
          } else if (block['checklist'] == true) {
            lines.add(NoteLine.checklist(text,
                done: block['done'] as bool,
                styles: List.unmodifiable(styles)));
          } else {
            if (block['done'] == true) {
              throw const FormatException('Invalid prose status');
            }
            lines.add(NoteLine.text(text, styles: List.unmodifiable(styles)));
          }
        }
        return NoteDocument._(NoteKind.text, lines, tags: tags, rich: true);
      } on Object {
        return NoteDocument._(
            NoteKind.text, [const NoteLine.text('Unsupported note format')],
            isReadOnly: true);
      }
    }
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
  List<String> get tags => UnmodifiableListView(_tags);
  String get plainText =>
      _lines.map((line) => line.isImage ? '[Image]' : line.text).join('\n');
  int get imageCount => _lines.where((line) => line.isImage).length;
  int get imageBytes => _lines
      .where((line) => line.isImage)
      .fold(0, (sum, line) => sum + base64Decode(line.imageBase64!).length);
  bool get isMixed =>
      _lines.any((line) => line.isChecklist) &&
      _lines.any((line) => !line.isChecklist);
  bool get hasChecklist => _lines.any((line) => line.isChecklist);
  bool get hasChanges =>
      !_same(_tags, _initialTags) ||
      _lines.length != _initial.length ||
      List.generate(_lines.length, (i) => i).any((i) =>
          _lines[i].text != _initial[i].text ||
          _lines[i].isChecklist != _initial[i].isChecklist ||
          _lines[i].done != _initial[i].done ||
          _lines[i].imageBase64 != _initial[i].imageBase64 ||
          !_same(_lines[i].styles, _initial[i].styles));

  static bool _same<T>(List<T> a, List<T> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => i).every((i) => a[i] == b[i]);
  void _assertEditable() {
    if (isReadOnly) throw StateError('Unsupported note format is read-only');
  }

  static List<String> _checkedTags(List<String> input) {
    final result = <String>[];
    for (final raw in input) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      // Read old tags up to their original 40 UTF-16 units, as well as new
      // tags with up to 15 complete visible characters (including emoji).
      if ((tag.length > 40 && tag.characters.length > maxTagCharacters) ||
          tag.contains(RegExp(r'[\r\n\u0000-\u001f]'))) {
        throw const FormatException(
            'Tags must be single lines of 40 characters or less');
      }
      if (!result.any((v) => v.toLowerCase() == tag.toLowerCase())) {
        result.add(tag);
      }
    }
    if (result.length > 12) throw const FormatException('Use up to 12 tags');
    return result;
  }

  void setTags(List<String> value) {
    _assertEditable();
    final checked = _checkedTags(value);
    final additions = checked.where((tag) => !_tags.contains(tag)).toList();
    if (additions.isNotEmpty && checked.length > maxTagsPerNote) {
      throw const FormatException('Use up to 3 tags per note');
    }
    if (additions.any((tag) => tag.characters.length > maxTagCharacters)) {
      throw const FormatException('Tags must be 15 characters or less');
    }
    // Retained legacy tags are never truncated. Removal is always possible,
    // including while the remaining old tags still exceed the new limits.
    _tags
      ..clear()
      ..addAll(checked);
  }

  void replaceStyles(int index, List<NoteStyleRun> value) {
    _assertEditable();
    _lines[index] = _lines[index].withStyles(value);
  }

  int insertImageAfter(int index, String base64) {
    _assertEditable();
    if (imageCount >= maxImagesPerNote) {
      throw const FormatException(imageLimitMessage);
    }
    final bytes = NoteImageContent.decode(base64);
    if (imageBytes + bytes.length > NoteContentBudget.maxImageBytes) {
      throw const FormatException('Images must total 180 KB or less');
    }
    return _insertAfter(index, NoteLine.image(base64), null);
  }

  void replaceText(int index, String text) {
    _assertEditable();
    final line = _lines[index];
    if (line.text == text) return;
    _lines[index] = line.withText(text);
  }

  void setDone(int index, bool done) {
    _assertEditable();
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
    _assertEditable();
    if (index < -1 || index >= _lines.length) {
      throw RangeError.index(index, _lines);
    }
    var insertAt = index + 1;
    if (index >= 0 &&
        caretOffset != null &&
        !_lines[index].isChecklist &&
        !_lines[index].isImage) {
      final line = _lines[index];
      final caret = caretOffset.clamp(0, line.text.length);
      final nextBreak = line.text.indexOf('\n', caret);
      if (nextBreak >= 0) {
        _lines[index] = line.withText(line.text.substring(0, nextBreak));
        final remainingStyles = line.styles
            .where((r) => r.end > nextBreak + 1)
            .map((r) => NoteStyleRun(
                (r.start - nextBreak - 1).clamp(0, line.text.length),
                r.end - nextBreak - 1,
                r.flags))
            .toList();
        _lines.insert(
            insertAt,
            NoteLine.text(line.text.substring(nextBreak + 1),
                styles: List.unmodifiable(remainingStyles)));
      }
    }
    _lines.insert(insertAt, newLine);
    return insertAt;
  }

  void removeAt(int index) {
    _assertEditable();
    _lines.removeAt(index);
  }

  Note toNote(Note original, {bool removeEmptyLines = false}) {
    final result = original.copy();
    if (isReadOnly) return result;
    final lines = removeEmptyLines
        ? _lines
            .where((line) => line.isImage || line.text.trim().isNotEmpty)
            .toList()
        : _lines;
    final removedEmpty = lines.length != _lines.length;
    if (!hasChanges && !removedEmpty) return result;
    final rich = _wasRich ||
        _tags.isNotEmpty ||
        lines.any((line) => line.isImage || line.styles.isNotEmpty);
    if (rich) {
      result.kind = NoteKind.text;
      if (lines.isEmpty && _tags.isEmpty) {
        result.body = '';
        result.items = [];
      } else {
        result.body = jsonEncode({
          'v': 2,
          'tags': _tags,
          'blocks': [
            for (final line in lines)
              {
                'text': line.text,
                'checklist': line.isChecklist,
                'done': line.done,
                'styles': line.styles.map((r) => r.toJson()).toList(),
                if (line.isImage) 'image': line.imageBase64
              }
          ]
        });
        result.items = [TodoItem(text: richFormatMarker)];
      }
      return result;
    }
    // Cleanup alone must not recode an otherwise untouched legacy checklist.
    if (!hasChanges && _sourceKind == NoteKind.todo) {
      result.items =
          result.items.where((item) => item.text.trim().isNotEmpty).toList();
      if (result.body.trim().isEmpty) result.body = '';
      return result;
    }
    if (_sourceKind == NoteKind.todo &&
        original.body.isEmpty &&
        lines.every((line) => line.isChecklist)) {
      result.kind = NoteKind.todo;
      result.items = [
        for (final line in lines) TodoItem(text: line.text, done: line.done),
      ];
      return result;
    }
    result.kind = NoteKind.text;
    final hasSavedChecklist = lines.any((line) => line.isChecklist);
    result.body = hasSavedChecklist
        ? lines.map(_encode).join('\n')
        : lines.map((line) => line.text).join('\n');
    result.items = hasSavedChecklist ? [TodoItem(text: formatMarker)] : [];
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
