import 'package:atomic_notes/theme/app_theme.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

void main() {
  test('both redesign themes build with their palette', () {
    final light = AtomicTheme.light;
    final dark = AtomicTheme.dark;
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.extension<AtomicColors>(), same(AtomicColors.light));
    expect(dark.extension<AtomicColors>(), same(AtomicColors.dark));
    expect(light.scaffoldBackgroundColor, AtomicColors.light.canvas);
    expect(dark.scaffoldBackgroundColor, AtomicColors.dark.canvas);
  });

  test('text theme uses the static AtomicType scale coloured by the theme', () {
    for (final theme in [AtomicTheme.light, AtomicTheme.dark]) {
      final body = theme.textTheme.bodyMedium!;
      final c = theme.extension<AtomicColors>()!;
      expect(body.fontFamily, AtomicFonts.sans);
      expect(body.fontSize, AtomicType.bodyMedium.fontSize);
      expect(body.color, c.textPrimary);
    }
  });

  group('compatibility light theme bridge (ADR-011)', () {
    test('AppTheme.light carries AtomicColors.light explicitly', () {
      expect(AppTheme.light.extension<AtomicColors>(), same(AtomicColors.light));
    });

    test('AppTheme.light keeps the shipped look until pages migrate', () {
      expect(AppTheme.light.scaffoldBackgroundColor, AppColors.paper);
      expect(AppTheme.light.colorScheme.primary, AppColors.ink);
    });

    testWidgets('context.colors resolves the real extension under AppTheme.light',
        (tester) async {
      late AtomicColors seen;
      await pumpThemed(
        tester,
        Builder(builder: (context) {
          seen = context.colors;
          return const SizedBox();
        }),
        theme: AppTheme.light,
      );
      expect(seen, same(AtomicColors.light));
    });
  });

  for (final entry in atomicThemes.entries) {
    testWidgets('dialogs and sheets resolve the ${entry.key} palette', (tester) async {
      late AtomicColors seen;
      await pumpThemed(
        tester,
        Builder(builder: (context) {
          seen = context.colors;
          return const SizedBox();
        }),
        theme: entry.value,
      );
      expect(seen, same(entry.value.extension<AtomicColors>()));
      expect(entry.value.dialogTheme.backgroundColor, seen.surface);
      expect(entry.value.bottomSheetTheme.backgroundColor, seen.surface);
    });
  }
}
