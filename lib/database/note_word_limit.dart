import 'note_document.dart';

/// Save-time policy only: old notes remain readable and drafts are never cut.
class NoteWordLimit {
  const NoteWordLimit({required this.originalWords})
      : assert(originalWords >= 0);

  static const maxWords = 3000;
  static final _word = RegExp(r'\S+', unicode: true);
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
        if (pending != null) gapWords += _word.allMatches(text).length;
        continue;
      }
      if (pending != null) words += _word.allMatches(pending).length + gapWords;
      pending = pending == null ? text.trimLeft() : text;
      gapWords = 0;
    }
    return words + _word.allMatches(pending?.trimRight() ?? '').length;
  }

  static Iterable<String> _visibleText(
      String title, Iterable<NoteLine> lines) sync* {
    yield title;
    for (final line in lines) {
      if (!line.isImage) yield line.text;
    }
  }
}
