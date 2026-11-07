import 'dart:math';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/note_word_limit.dart';
import 'package:flutter_test/flutter_test.dart';

/// The base revision's definition, kept here as the oracle.
int _reference({required String title, required Iterable<NoteLine> lines}) {
  final word = RegExp(r'\S+', unicode: true);
  final texts = [
    title,
    for (final line in lines)
      if (!line.isImage) line.text
  ];
  var words = 0, gapWords = 0;
  String? pending;
  for (final text in texts) {
    if (text.trim().isEmpty) {
      if (pending != null) gapWords += word.allMatches(text).length;
      continue;
    }
    if (pending != null) words += word.allMatches(pending).length + gapWords;
    pending = pending == null ? text.trimLeft() : text;
    gapWords = 0;
  }
  return words + word.allMatches(pending?.trimRight() ?? '').length;
}

List<NoteLine> _lines(List<String> texts) =>
    NoteDocument.fromNote(Note(id: 'w', body: texts.join('\n'))).lines;

void main() {
  test('every single code unit counts as RegExp \\S+ does', () {
    final word = RegExp(r'\S+', unicode: true);
    for (var c = 0; c < 0x10000; c++) {
      final unit = String.fromCharCode(c);
      final text = 'a${unit}b';
      expect(NoteWordLimit.count(title: text, lines: const []),
          word.allMatches(text).length,
          reason: 'U+${c.toRadixString(16)}');
    }
  });

  test('random documents count exactly as the RegExp definition', () {
    // Letters, an emoji, ZWJ, and every kind of space RegExp does and does
    // not treat as whitespace (U+0085 and U+200B are not whitespace).
    final alphabet = [
      for (final code in const [
        0x61, 0x5a, 0x37, 0xe9, 0x1f468, 0x200d, 0x20, 0x09, 0x0a, 0xa0, //
        0x85, 0x2003, 0x2028, 0x3000, 0xfeff, 0x200b,
      ])
        String.fromCharCode(code)
    ];
    final random = Random(42);
    String text() => List.generate(random.nextInt(40),
        (_) => alphabet[random.nextInt(alphabet.length)]).join();
    for (var i = 0; i < 2000; i++) {
      final title = text();
      final lines = _lines(List.generate(random.nextInt(6), (_) => text()));
      expect(NoteWordLimit.count(title: title, lines: lines),
          _reference(title: title, lines: lines),
          reason:
              'case $i: ${title.codeUnits} ${lines.map((l) => l.text.codeUnits)}');
    }
  });

  test('a 3,000-word note counts the same, much faster (informational)', () {
    final body = List.generate(3000, (i) => 'word$i').join(' ');
    final lines = _lines([body]);
    expect(NoteWordLimit.count(title: 'Title', lines: lines), 3001);
    expect(_reference(title: 'Title', lines: lines), 3001);
    double perCall(int Function() f) {
      for (var i = 0; i < 20; i++) {
        f();
      }
      final watch = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        f();
      }
      return watch.elapsedMicroseconds / 200;
    }

    final scan =
        perCall(() => NoteWordLimit.count(title: 'Title', lines: lines));
    final regex = perCall(() => _reference(title: 'Title', lines: lines));
    // Host-VM figures, recorded in the PR; not a device measurement.
    // ignore: avoid_print
    print('word count per keystroke: scan ${scan.toStringAsFixed(0)} us, '
        'regex ${regex.toStringAsFixed(0)} us');
    expect(scan, lessThan(regex), reason: 'the scan must not be slower');
  });
}
