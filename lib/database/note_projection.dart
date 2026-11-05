import 'note.dart';
import 'note_document.dart';

/// Immutable, validated display/search data. No image payloads or editor drafts.
class NoteProjection {
  factory NoteProjection.fromNote(Note note) =>
      NoteProjection._(NoteDocument.fromNote(note));

  NoteProjection._(NoteDocument document)
      : previewLines = List.unmodifiable(document.lines.take(4).map((line) =>
            line.isImage
                ? const NotePreviewLine.image()
                : NotePreviewLine(line.text,
                    isChecklist: line.isChecklist, done: line.done))),
        tags = List.unmodifiable(document.tags),
        plainText = document.plainText,
        lineCount = document.lines.length,
        checklistCount =
            document.lines.where((line) => line.isChecklist).length,
        doneCount = document.lines
            .where((line) => line.isChecklist && line.done)
            .length,
        isReadOnly = document.isReadOnly {
    _searchText = plainText.toLowerCase();
    _searchTags = tags.map((tag) => tag.toLowerCase()).toList(growable: false);
  }

  final List<NotePreviewLine> previewLines;
  final List<String> tags;
  final String plainText;
  final int lineCount;
  final int checklistCount;
  final int doneCount;
  final bool isReadOnly;
  late final String _searchText;
  late final List<String> _searchTags;
  bool get hasChecklist => checklistCount != 0;
  bool matches(String lowerCaseQuery) =>
      _searchText.contains(lowerCaseQuery) ||
      _searchTags.any((tag) => tag.contains(lowerCaseQuery));

  int get _textUnits =>
      plainText.length +
      _searchText.length +
      previewLines.fold<int>(0, (sum, line) => sum + line.text.length) +
      tags.fold<int>(0, (sum, tag) => sum + tag.length) +
      _searchTags.fold<int>(0, (sum, tag) => sum + tag.length);
}

class NotePreviewLine {
  const NotePreviewLine(this.text,
      {this.isChecklist = false, this.done = false})
      : isImage = false;
  const NotePreviewLine.image()
      : text = '',
        isChecklist = false,
        done = false,
        isImage = true;
  final String text;
  final bool isChecklist;
  final bool done;
  final bool isImage;
}

/// Owner-scoped LRU. The source key retains the existing immutable body string
/// reference (never a copy); separate source/text budgets bound its lifetime.
/// All display data goes through the normal document/image validator on a miss.
class NoteProjectionCache {
  NoteProjectionCache(
      {this.maxEntries = 64,
      this.maxTextUnits = 256 * 1024,
      this.maxSourceUnits = 16 * 1024 * 1024,
      NoteDocument Function(Note)? decode})
      : _decode = decode ?? NoteDocument.fromNote {
    if (maxEntries < 0 || maxTextUnits < 0 || maxSourceUnits < 0) {
      throw ArgumentError('Projection cache budgets must be nonnegative');
    }
  }
  final int maxEntries;
  final int maxTextUnits;
  final int maxSourceUnits;
  final NoteDocument Function(Note) _decode;
  final _entries = <String, _ProjectionEntry>{};
  int _textUnits = 0;
  int _sourceUnits = 0;

  /// Full-library scans can reuse entries without displacing visible cards.
  NoteProjection get(Note note, {bool evict = true}) {
    final previous = _remove(note.id);
    if (previous != null && previous.matches(note)) {
      _add(note.id, previous);
      return previous.projection;
    }
    final projection = NoteProjection._(_decode(note));
    final entry = _ProjectionEntry(note, projection);
    if (maxEntries == 0 ||
        entry.textUnits > maxTextUnits ||
        entry.sourceUnits > maxSourceUnits ||
        note.deleted) {
      return projection;
    }
    bool isFull() =>
        _entries.length >= maxEntries ||
        _textUnits + entry.textUnits > maxTextUnits ||
        _sourceUnits + entry.sourceUnits > maxSourceUnits;
    if (!evict && isFull()) return projection;
    while (isFull()) {
      _remove(_entries.keys.first);
    }
    _add(note.id, entry);
    return projection;
  }

  void _add(String id, _ProjectionEntry entry) {
    _entries[id] = entry;
    _textUnits += entry.textUnits;
    _sourceUnits += entry.sourceUnits;
  }

  _ProjectionEntry? _remove(String id) {
    final entry = _entries.remove(id);
    if (entry != null) {
      _textUnits -= entry.textUnits;
      _sourceUnits -= entry.sourceUnits;
    }
    return entry;
  }

  int get length => _entries.length;
  void clear() {
    _entries.clear();
    _textUnits = 0;
    _sourceUnits = 0;
  }

  /// Releases deleted/replaced source bodies before observers see new state.
  void retainNotes(Map<String, Note> notes) {
    for (final id in _entries.keys.toList()) {
      final note = notes[id];
      if (note == null || !_entries[id]!.matches(note)) _remove(id);
    }
  }
}

class _ProjectionEntry {
  _ProjectionEntry(Note note, this.projection)
      : kind = note.kind,
        body = note.body,
        items = [for (final item in note.items) (item.text, item.done)];
  final NoteKind kind;
  final String body;
  final List<(String, bool)> items;
  final NoteProjection projection;
  late final int textUnits = projection._textUnits;
  late final int sourceUnits =
      body.length + items.fold<int>(0, (sum, item) => sum + item.$1.length);

  bool matches(Note note) {
    if (note.deleted ||
        kind != note.kind ||
        body != note.body ||
        items.length != note.items.length) {
      return false;
    }
    for (var i = 0; i < items.length; i++) {
      if (items[i].$1 != note.items[i].text ||
          items[i].$2 != note.items[i].done) {
        return false;
      }
    }
    return true;
  }
}
