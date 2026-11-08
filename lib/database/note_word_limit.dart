import 'note_document.dart';

/// Save-time policy only: old notes remain readable and drafts are never cut.
class NoteWordLimit {
  const NoteWordLimit({required this.originalWords})
      : assert(originalWords >= 0);

  static const maxWords = 3000;
  final int originalWords;

  int get ceiling => originalWords > maxWords ? originalWords : maxWords;
  String get label =>
      ceiling > maxWords ? '$ceiling LEGACY MAX' : '$maxWords MAX';

  String? errorFor(int words) {
    if (words <= ceiling) return null;
    return ceiling > maxWords
        ? 'This existing note can keep up to $ceiling words. Shorten it before saving; your draft is still here.'
        : 'Use up to $maxWords words per note. Your draft is still here.';
  }

  /// Same whitespace-separated words as the editor footer, without a joined
  /// full-document string, rich JSON, image decoding, or tag serialization.
  static int count({required String title, required Iterable<NoteLine> lines}) {
    var words = 0, gapWords = 0;
    String? pending;
    for (final text in _visibleText(title, lines)) {
      // Dart trim also recognizes Unicode NEL, which RegExp whitespace does
      // not. Trim only the document edges, preserving interior block gaps as
      // the previous footer's join(' ').trim().split(whitespace) did.
      if (text.trim().isEmpty) {
        if (pending != null) gapWords += _words(text);
        continue;
      }
      if (pending != null) words += _words(pending) + gapWords;
      pending = pending == null ? text.trimLeft() : text;
      gapWords = 0;
    }
    return words + _words(pending?.trimRight() ?? '');
  }

  /// The number of `\S+` runs (Unicode RegExp semantics) in [text].
  ///
  /// A code-unit scan instead of `RegExp(r'\S+', unicode: true).allMatches`:
  /// the same count, about 16x faster on a 3,000-word line, which the editor
  /// recounts on every keystroke. The whitespace set is exactly RegExp's
  /// `\s` (ECMAScript WhiteSpace and LineTerminator); U+0085 is not in it.
  /// Surrogates are never whitespace, so an astral character counts once.
  static int _words(String text) {
    var words = 0;
    var inWord = false;
    for (var i = 0; i < text.length; i++) {
      final space = _isSpace(text.codeUnitAt(i));
      if (!space && !inWord) words++;
      inWord = !space;
    }
    return words;
  }

  static bool _isSpace(int c) =>
      c == 0x20 ||
      (c >= 0x09 && c <= 0x0d) ||
      c == 0xa0 ||
      c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200a) ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x202f ||
      c == 0x205f ||
      c == 0x3000 ||
      c == 0xfeff;

  static Iterable<String> _visibleText(
      String title, Iterable<NoteLine> lines) sync* {
    yield title;
    for (final line in lines) {
      if (!line.isImage) yield line.text;
    }
  }
}
