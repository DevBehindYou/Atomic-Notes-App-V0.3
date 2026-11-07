import 'package:atomic_notes/database/note_rich_content.dart';
import 'package:flutter/widgets.dart';

/// Rich styles use the same UTF-16 offsets as Flutter text selections. Every
/// grapheme cluster (an emoji sequence, a letter with combining marks) carries
/// one style, so a style boundary never falls inside what the reader sees as a
/// single character.
class RichNoteController extends TextEditingController {
  RichNoteController({String text = '', List<NoteStyleRun> styles = const []})
      : super(text: text) {
    _flags = List.filled(text.length, 0, growable: true);
    for (final run in styles) {
      if (run.end <= run.start) continue;
      final start = _boundaryStart(text, run.start.clamp(0, text.length));
      final end = _boundaryEnd(text, run.end.clamp(0, text.length));
      for (var i = start; i < end; i++) {
        _flags[i] |= run.flags & NoteTextStyle.all;
      }
    }
  }

  List<int> _flags = [];
  int? _typingFlags;

  /// Disjoint, sorted, nonempty runs; adjacent identical styles are merged.
  List<NoteStyleRun> get styles {
    final result = <NoteStyleRun>[];
    var start = 0;
    while (start < _flags.length) {
      final flags = _flags[start];
      var end = start + 1;
      while (end < _flags.length && _flags[end] == flags) {
        end++;
      }
      if (flags != 0) result.add(NoteStyleRun(start, end, flags));
      start = end;
    }
    return List.unmodifiable(result);
  }

  void toggleStyle(int flag) {
    if (flag <= 0 || flag & ~NoteTextStyle.all != 0 || !selection.isValid) {
      return;
    }
    final range = _styleRange(flag);
    if (range.isCollapsed) {
      _typingFlags = (_typingFlags ?? _flagsAtCaret(range.start)) ^ flag;
    } else {
      final remove = _contains(range, flag);
      for (var i = range.start; i < range.end; i++) {
        _flags[i] = remove ? _flags[i] & ~flag : _flags[i] | flag;
      }
      _typingFlags = null;
    }
    // Styling must not change the selection or reset an IME composing range.
    notifyListeners();
  }

  bool hasStyle(int flag) {
    if (!selection.isValid) return false;
    final range = _styleRange(flag);
    return range.isCollapsed
        ? ((_typingFlags ?? _flagsAtCaret(range.start)) & flag) == flag
        : _contains(range, flag);
  }

  bool _contains(TextRange range, int flag) {
    for (var i = range.start; i < range.end; i++) {
      if (_flags[i] & flag != flag) return false;
    }
    return true;
  }

  TextRange _styleRange(int flag) {
    var start = selection.start.clamp(0, text.length);
    var end = selection.end.clamp(0, text.length);
    if (flag == NoteTextStyle.heading) {
      start = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
      final last = end > selection.start ? end - 1 : end;
      final newline = text.indexOf('\n', last);
      end = newline < 0 ? text.length : newline;
    }
    return TextRange(
        start: _boundaryStart(text, start), end: _boundaryEnd(text, end));
  }

  int _flagsAtCaret(int offset) {
    if (_flags.isEmpty) return 0;
    final at = offset.clamp(0, _flags.length);
    // At a paragraph start, new text takes that paragraph's own formatting, as
    // it already does at offset 0. Inheriting the previous paragraph through
    // its newline would, for example, put a heading into an ordinary line.
    final paragraphStart = at == 0 || text.codeUnitAt(at - 1) == _newline;
    if (paragraphStart &&
        at < _flags.length &&
        text.codeUnitAt(at) != _newline) {
      return _flags[at];
    }
    return _flags[at == 0 ? 0 : at - 1];
  }

  static const _newline = 0x0a;

  @override
  set value(TextEditingValue next) {
    final old = value;
    if (old.text != next.text) {
      final change = _changeRange(old, next);
      final inserted =
          next.text.length - (old.text.length - change.end + change.start);
      final inherit = _typingFlags ??
          (change.start < change.end
              ? _flags[change.start]
              : _flagsAtCaret(change.start));
      _flags.replaceRange(
          change.start, change.end, List.filled(inserted, inherit));
      // The edit can join or split clusters only around itself (and along a
      // run of regional indicators), so only that window is made uniform.
      _unifyClusters(next.text, change.start, change.start + inserted);
    } else if (old.selection != next.selection) {
      _typingFlags = null;
    }
    super.value = next;
  }

  /// Prefer the actual editing selection over ambiguous common prefixes (aaaa).
  static TextRange _changeRange(TextEditingValue old, TextEditingValue next) {
    final before = old.text;
    final after = next.text;
    bool matches(int start, int end) =>
        start >= 0 &&
        end >= start &&
        end <= before.length &&
        after.length >= before.length - end + start &&
        after.startsWith(before.substring(0, start)) &&
        after.endsWith(before.substring(end));
    if (old.selection.isValid) {
      var start = old.selection.start;
      var end = old.selection.end;
      final removed = before.length - after.length;
      if (old.selection.isCollapsed && removed > 0) {
        if (next.selection.isValid &&
            next.selection.extentOffset == start - removed) {
          start -= removed;
        } else {
          end += removed;
        }
      }
      if (matches(start, end)) {
        return TextRange(
            start: _boundaryStart(before, start),
            end: _boundaryEnd(before, end));
      }
    }
    var start = 0;
    while (start < before.length &&
        start < after.length &&
        before.codeUnitAt(start) == after.codeUnitAt(start)) {
      start++;
    }
    start = _boundaryStart(before, start);
    start = _boundaryStart(after, start);
    var end = before.length;
    var afterEnd = after.length;
    while (end > start &&
        afterEnd > start &&
        before.codeUnitAt(end - 1) == after.codeUnitAt(afterEnd - 1)) {
      end--;
      afterEnd--;
    }
    end = _boundaryEnd(before, end);
    return TextRange(start: start, end: end);
  }

  /// Gives each grapheme cluster overlapping [start, end) of [text] the union
  /// of its code units' styles.
  void _unifyClusters(String text, int start, int end) {
    if (text.isEmpty) return;
    var from = _boundaryStart(text, start.clamp(0, text.length));
    var to = _boundaryEnd(text, end.clamp(0, text.length));
    // Flags pair regional indicators from the start of their run, so one
    // inserted or removed indicator re-pairs the whole run.
    while (from >= 2 && _isRegionalIndicator(text, from - 2)) {
      from -= 2;
    }
    while (to + 2 <= text.length && _isRegionalIndicator(text, to)) {
      to += 2;
    }
    from = _boundaryStart(text, from);
    to = _boundaryEnd(text, to);
    final clusters = CharacterRange.at(text, from, to);
    var offset = clusters.stringBeforeLength;
    for (final cluster in clusters.current.characters) {
      final clusterEnd = offset + cluster.length;
      if (cluster.length > 1) {
        var flags = 0;
        for (var i = offset; i < clusterEnd; i++) {
          flags |= _flags[i];
        }
        _flags.fillRange(offset, clusterEnd, flags);
      }
      offset = clusterEnd;
    }
  }

  static bool _isRegionalIndicator(String text, int offset) =>
      offset + 1 < text.length &&
      text.codeUnitAt(offset) == 0xd83c &&
      text.codeUnitAt(offset + 1) >= 0xdde6 &&
      text.codeUnitAt(offset + 1) <= 0xddff;

  /// The start of the grapheme cluster containing [offset].
  static int _boundaryStart(String text, int offset) => text.isEmpty
      ? 0
      : CharacterRange.at(text, offset.clamp(0, text.length))
          .stringBeforeLength;

  /// The end of the grapheme cluster containing [offset].
  static int _boundaryEnd(String text, int offset) {
    if (text.isEmpty) return 0;
    final range = CharacterRange.at(text, offset.clamp(0, text.length));
    return range.stringBeforeLength + range.current.length;
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final composing = value.composing;
    final showComposing =
        withComposing && value.isComposingRangeValid && !composing.isCollapsed;
    bool isComposing(int i) =>
        showComposing && i >= composing.start && i < composing.end;
    final spans = <TextSpan>[];
    var start = 0;
    while (start < text.length) {
      final flags = _flags[start];
      final compose = isComposing(start);
      var end = start + 1;
      while (end < text.length &&
          _flags[end] == flags &&
          isComposing(end) == compose) {
        end++;
      }
      final decorations = <TextDecoration>[
        if (style?.decoration != null) style!.decoration!,
        if (flags & NoteTextStyle.underline != 0 || compose)
          TextDecoration.underline,
        if (flags & NoteTextStyle.strike != 0) TextDecoration.lineThrough,
      ];
      final heading = flags & NoteTextStyle.heading != 0;
      spans.add(TextSpan(
          text: text.substring(start, end),
          style: (style ?? const TextStyle()).copyWith(
            fontWeight: flags & NoteTextStyle.bold != 0 || heading
                ? FontWeight.bold
                : style?.fontWeight,
            fontStyle: flags & NoteTextStyle.italic != 0
                ? FontStyle.italic
                : style?.fontStyle,
            fontSize:
                heading ? (style?.fontSize ?? 14) * 1.25 : style?.fontSize,
            decoration: decorations.isEmpty
                ? null
                : TextDecoration.combine(decorations),
          )));
      start = end;
    }
    return TextSpan(style: style, children: spans);
  }
}
