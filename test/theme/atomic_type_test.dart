import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Spec 01 scale: size, line height, weight. labelSmall (11) is the smallest
  // style anywhere (ADR-011); readability is checked at runtime, not by a
  // blanket 12 sp rule.
  const expected = <String, (double, double, FontWeight)>{
    'display': (40, 1.10, FontWeight.w300),
    'headlineLarge': (32, 1.15, FontWeight.w300),
    'headlineMedium': (24, 1.25, FontWeight.w400),
    'titleLarge': (20, 1.30, FontWeight.w500),
    'titleMedium': (16, 1.35, FontWeight.w500),
    'bodyLarge': (17, 1.60, FontWeight.w400),
    'bodyMedium': (15, 1.50, FontWeight.w400),
    'bodySmall': (13, 1.45, FontWeight.w400),
    'labelLarge': (15, 1.30, FontWeight.w600),
    'labelMedium': (13, 1.25, FontWeight.w500),
    'labelSmall': (11, 1.20, FontWeight.w600),
    'mono': (15, 1.50, FontWeight.w500),
  };

  test('the scale has exactly the spec 01 styles', () {
    expect(AtomicType.scale.keys.toSet(), expected.keys.toSet());
  });

  for (final entry in expected.entries) {
    test('${entry.key} matches spec 01', () {
      final style = AtomicType.scale[entry.key]!;
      final (size, height, weight) = entry.value;
      expect(style.fontSize, size);
      expect(style.height, height);
      expect(style.fontWeight, weight);
    });
  }

  test('labelSmall is the smallest size', () {
    final sizes = AtomicType.scale.values.map((s) => s.fontSize!).toList();
    expect(sizes.reduce((a, b) => a < b ? a : b), 11);
    expect(AtomicType.labelSmall.fontSize, 11);
  });

  test('UI styles use Figtree; only mono uses JetBrains Mono', () {
    for (final entry in AtomicType.scale.entries) {
      expect(entry.value.fontFamily,
          entry.key == 'mono' ? AtomicFonts.mono : AtomicFonts.sans,
          reason: entry.key);
    }
    expect(AtomicFonts.sans, 'Figtree');
    expect(AtomicFonts.mono, 'JetBrainsMono');
  });

  test('styles carry no colour, so one style serves both themes', () {
    for (final entry in AtomicType.scale.entries) {
      expect(entry.value.color, isNull, reason: entry.key);
    }
  });

  test('numeric() adds tabular figures without changing the style', () {
    final numeric = AtomicType.numeric(AtomicType.headlineLarge);
    expect(numeric.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(numeric.fontSize, AtomicType.headlineLarge.fontSize);
  });
}
