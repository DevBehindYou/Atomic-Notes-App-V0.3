import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final themes = {'dark': AtomicColors.dark, 'light': AtomicColors.light};

  for (final entry in themes.entries) {
    final c = entry.value;
    final name = entry.key;

    group('$name theme', () {
      // Text and icons that carry meaning: WCAG AA 4.5:1.
      final textPairs = <String, (Color, Color)>{
        'textPrimary on canvas': (c.textPrimary, c.canvas),
        'textPrimary on surface': (c.textPrimary, c.surface),
        'textPrimary on surfaceInset': (c.textPrimary, c.surfaceInset),
        'textPrimary on surfaceRaised': (c.textPrimary, c.surfaceRaised),
        'textSecondary on canvas': (c.textSecondary, c.canvas),
        'textSecondary on surface': (c.textSecondary, c.surface),
        'textSecondary on surfaceInset': (c.textSecondary, c.surfaceInset),
        'onAccent on accent': (c.onAccent, c.accent),
        'onDanger on danger': (c.onDanger, c.danger),
        'onInfo on info': (c.onInfo, c.info),
        'onInverse on inverseSurface': (c.onInverse, c.inverseSurface),
        'importantTitle on inverseSurface': (c.importantTitle, c.inverseSurface),
        'accentText on canvas': (c.accentText, c.canvas),
        'accentText on surface': (c.accentText, c.surface),
        'dangerText on canvas': (c.dangerText, c.canvas),
        'dangerText on surface': (c.dangerText, c.surface),
        'infoText on canvas': (c.infoText, c.canvas),
        'infoText on surface': (c.infoText, c.surface),
      };
      for (final pair in textPairs.entries) {
        test('${pair.key} is at least 4.5:1', () {
          final (fg, bg) = pair.value;
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5));
        });
      }

      // Component boundaries and focus indicators: WCAG 1.4.11, 3:1.
      final nonTextPairs = <String, (Color, Color)>{
        'outlineStrong on canvas': (c.outlineStrong, c.canvas),
        'outlineStrong on surface': (c.outlineStrong, c.surface),
        'focus on canvas': (c.focus, c.canvas),
        'focus on surface': (c.focus, c.surface),
      };
      for (final pair in nonTextPairs.entries) {
        test('${pair.key} is at least 3:1', () {
          final (fg, bg) = pair.value;
          expect(contrast(fg, bg), greaterThanOrEqualTo(3.0));
        });
      }

      test('saturated fills carry the specified content colour', () {
        expect(c.onAccent, AtomicPalette.black);
        expect(c.onDanger, AtomicPalette.black);
        expect(c.onInfo, AtomicPalette.white);
        expect(c.accent, AtomicPalette.orange500);
      });

      test('the mascot stage is the light grey disc in both themes', () {
        expect(c.mascotStage, AtomicPalette.gray200);
      });
    });
  }

  test('brightness matches each palette', () {
    expect(AtomicColors.dark.brightness, Brightness.dark);
    expect(AtomicColors.light.brightness, Brightness.light);
  });

  test('important cards: light theme black with white title, dark theme '
      'inverted (ADR-009)', () {
    expect(AtomicColors.light.inverseSurface, AtomicPalette.black);
    expect(AtomicColors.light.importantTitle, AtomicPalette.white);
    expect(AtomicColors.dark.inverseSurface.computeLuminance(),
        greaterThan(AtomicColors.dark.canvas.computeLuminance()));
  });

  test('lerp returns the endpoints', () {
    expect(AtomicColors.dark.lerp(AtomicColors.light, 0).canvas,
        AtomicColors.dark.canvas);
    expect(AtomicColors.dark.lerp(AtomicColors.light, 1).canvas,
        AtomicColors.light.canvas);
    expect(AtomicColors.dark.lerp(null, 0.5), same(AtomicColors.dark));
  });

  test('orange and red cannot be told apart by luminance alone', () {
    // Spec 01 rule 4: destructive actions also need an icon, a label and
    // their own placement. Keep the measured value honest (1.35:1).
    final ratio = contrast(AtomicPalette.orange500, AtomicPalette.red500);
    expect(ratio, closeTo(1.35, 0.01));
  });
}
