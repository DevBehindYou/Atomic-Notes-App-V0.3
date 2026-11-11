import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Code points a TrueType font maps to a real glyph, read from its `cmap`
/// table (formats 4 and 12). Offline, so CI needs no network to check that the
/// generated `atomic_icons.dart` matches the committed fonts.
Set<int> mappedCodePoints(String path) {
  final data = ByteData.sublistView(File(path).readAsBytesSync());
  final numTables = data.getUint16(4);
  int? cmap;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(
        [for (var j = 0; j < 4; j++) data.getUint8(rec + j)]);
    if (tag == 'cmap') cmap = data.getUint32(rec + 8);
  }
  if (cmap == null) throw StateError('no cmap table in $path');

  final points = <int>{};
  final subtables = data.getUint16(cmap + 2);
  for (var i = 0; i < subtables; i++) {
    final sub = cmap + data.getUint32(cmap + 4 + i * 8 + 4);
    final format = data.getUint16(sub);
    if (format == 4) {
      final segCount = data.getUint16(sub + 6) ~/ 2;
      final ends = sub + 14;
      final starts = ends + segCount * 2 + 2;
      final deltas = starts + segCount * 2;
      final ranges = deltas + segCount * 2;
      for (var s = 0; s < segCount; s++) {
        final end = data.getUint16(ends + s * 2);
        final start = data.getUint16(starts + s * 2);
        final delta = data.getInt16(deltas + s * 2);
        final rangeOffset = data.getUint16(ranges + s * 2);
        if (start == 0xFFFF) continue;
        for (var c = start; c <= end; c++) {
          int glyph;
          if (rangeOffset == 0) {
            glyph = (c + delta) & 0xFFFF;
          } else {
            final at = ranges + s * 2 + rangeOffset + (c - start) * 2;
            final g = data.getUint16(at);
            glyph = g == 0 ? 0 : (g + delta) & 0xFFFF;
          }
          if (glyph != 0) points.add(c);
        }
      }
    } else if (format == 12) {
      final groups = data.getUint32(sub + 12);
      for (var g = 0; g < groups; g++) {
        final rec = sub + 16 + g * 12;
        final start = data.getUint32(rec);
        final end = data.getUint32(rec + 4);
        final glyph = data.getUint32(rec + 8);
        for (var c = start; c <= end; c++) {
          if (glyph + (c - start) != 0) points.add(c);
        }
      }
    }
  }
  return points;
}

void main() {
  final source = File('lib/theme/atomic_icons.dart').readAsStringSync();
  final pattern = RegExp(
      r'IconData\(\s*0x([0-9a-fA-F]+),\s*fontFamily:\s*(fontFamily|filledFontFamily)');
  final outline = <int>[];
  final filled = <int>[];
  for (final m in pattern.allMatches(source)) {
    final cp = int.parse(m.group(1)!, radix: 16);
    (m.group(2) == 'fontFamily' ? outline : filled).add(cp);
  }

  test('the generated file declares the 92 canvas glyphs', () {
    expect(outline.length + filled.length, 92);
  });

  test('code points are unique within each font', () {
    expect(outline.toSet().length, outline.length);
    expect(filled.toSet().length, filled.length);
  });

  test('every outline icon has a glyph in AtomicIcons.ttf', () {
    final mapped = mappedCodePoints('assets/fonts/AtomicIcons.ttf');
    final missing = outline.where((c) => !mapped.contains(c)).toList();
    expect(missing, isEmpty, reason: missing.map((c) => c.toRadixString(16)).join(', '));
  });

  test('every filled icon has a glyph in AtomicIconsFilled.ttf', () {
    final mapped = mappedCodePoints('assets/fonts/AtomicIconsFilled.ttf');
    final missing = filled.where((c) => !mapped.contains(c)).toList();
    expect(missing, isEmpty, reason: missing.map((c) => c.toRadixString(16)).join(', '));
  });

  test('declared fonts exist and licences ship with them; no Satoshi', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = RegExp(r'asset:\s*(assets/fonts/\S+)')
        .allMatches(pubspec)
        .map((m) => m.group(1)!)
        .toList();
    expect(assets, isNotEmpty);
    for (final asset in assets) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    for (final family in ['Figtree', 'AtomicIcons', 'AtomicIconsFilled']) {
      expect(pubspec, contains('family: $family'));
    }
    expect(File('assets/fonts/Figtree-OFL.txt').existsSync(), isTrue);
    expect(File('assets/fonts/AtomicIcons-LICENSE.txt').existsSync(), isTrue);
    final satoshi = Directory('assets/fonts')
        .listSync()
        .where((f) => f.path.toLowerCase().contains('satoshi'));
    expect(satoshi, isEmpty);
  });
}
