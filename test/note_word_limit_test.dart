import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/note_word_limit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new-note boundaries are 2999, 3000, then rejection at 3001', () {
    const limit = NoteWordLimit(originalWords: 0);
    expect(limit.ceiling, 3000);
    expect(limit.errorFor(2999), isNull);
    expect(limit.errorFor(3000), isNull);
    expect(limit.errorFor(3001), contains('up to 3000 words'));
  });

  test('existing notes below the cap may grow up to 3000', () {
    const limit = NoteWordLimit(originalWords: 2999);
    expect(limit.errorFor(3000), isNull);
    expect(limit.errorFor(3001), isNotNull);
  });

  test('legacy notes may keep or shrink their word count but cannot grow', () {
    const limit = NoteWordLimit(originalWords: 4000);
    expect(limit.ceiling, 4000);
    expect(limit.label, '4000 LEGACY MAX');
    for (final count in [0, 2999, 3000, 3999, 4000]) {
      expect(limit.errorFor(count), isNull);
    }
    expect(limit.errorFor(4001), contains('up to 4000 words'));
  });

  test('count uses whitespace words for title and all visible text blocks', () {
    expect(
        NoteWordLimit.count(title: '  My\t title\n', lines: [
          const NoteLine.text('one\r\n two\u00a0three'),
          const NoteLine.checklist('  नमस्ते 世界 café 👨‍👩‍👧‍👦 ', done: true),
          const NoteLine.text('heading words',
              styles: [NoteStyleRun(0, 13, NoteTextStyle.heading)]),
          const NoteLine.image('image bytes and metadata are not words'),
          const NoteLine.text(' \n\t\r\u00a0'),
        ]),
        11);
  });

  test('empty text, punctuation and Unicode match the existing footer rule',
      () {
    for (final value in [
      '',
      ' \r\n\t ',
      'one   two\tthree\n',
      'नमस्ते\u2003世界\u2028café 👩🏽‍💻',
      '\u0085word\u0085',
      '\u0085',
      "can't-stop [marker] punctuation...",
    ]) {
      final trimmed = value.trim();
      final footerWords =
          trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
      expect(
          NoteWordLimit.count(title: value, lines: const [NoteLine.text('')]),
          footerWords,
          reason: value);
    }
  });

  test('block boundaries separate words without joining the full document', () {
    expect(
        NoteWordLimit.count(title: 'Title', lines: const [
          NoteLine.text('first'),
          NoteLine.checklist('second'),
          NoteLine.text('third'),
        ]),
        4);
  });

  test('Unicode trim at document edges matches the footer across blocks', () {
    for (final texts in [
      ['\u0085', 'first', '\u0085'],
      ['first', '\u0085', 'last'],
      ['\u0085first\u0085', '\u0085', '\u0085last\u0085'],
    ]) {
      final footerText = texts.join(' ').trim();
      final footerWords =
          footerText.isEmpty ? 0 : footerText.split(RegExp(r'\s+')).length;
      expect(
          NoteWordLimit.count(
              title: texts.first,
              lines: texts.skip(1).map((text) => NoteLine.text(text))),
          footerWords);
    }
  });
}
