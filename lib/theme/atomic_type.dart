import 'package:flutter/painting.dart';

/// Font families bundled in pubspec.yaml for the redesign.
abstract final class AtomicFonts {
  /// UI and note content. SIL Open Font License 1.1 (assets/fonts/Figtree-OFL.txt).
  static const String sans = 'Figtree';

  /// Only where fixed-width glyphs help accuracy: recovery phrases, setup
  /// keys, recovery codes and build identifiers.
  static const String mono = 'JetBrainsMono';
}

/// The redesign's type scale. Styles carry no colour: the theme's text theme
/// and `DefaultTextStyle` supply it, so one style serves both themes.
///
/// Sentence case everywhere; nothing here upper-cases text.
abstract final class AtomicType {
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Home title, onboarding headlines.
  static const TextStyle display = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 40,
    height: 1.10,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.5,
  );

  /// Screen titles, the editor title, the energy balance.
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 32,
    height: 1.15,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.3,
  );

  /// Hero card titles, empty-state headlines.
  static const TextStyle headlineMedium = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
  );

  /// Dialog titles, the featured card title.
  static const TextStyle titleLarge = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 20,
    height: 1.30,
    fontWeight: FontWeight.w500,
  );

  /// Card and list row titles.
  static const TextStyle titleMedium = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );

  /// Editor body.
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 17,
    height: 1.60,
    fontWeight: FontWeight.w400,
  );

  /// General body text and card previews.
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 15,
    height: 1.50,
    fontWeight: FontWeight.w400,
  );

  /// Metadata, captions and helper text.
  static const TextStyle bodySmall = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  /// Buttons.
  static const TextStyle labelLarge = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 15,
    height: 1.30,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Chips and segmented controls.
  static const TextStyle labelMedium = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 13,
    height: 1.25,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// Count bubbles and badges. The smallest size used anywhere.
  static const TextStyle labelSmall = TextStyle(
    fontFamily: AtomicFonts.sans,
    fontSize: 11,
    height: 1.20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    fontFeatures: tabular,
  );

  /// Recovery phrase words, setup keys and codes.
  static const TextStyle mono = TextStyle(
    fontFamily: AtomicFonts.mono,
    fontSize: 15,
    height: 1.50,
    fontWeight: FontWeight.w500,
  );

  /// Every style in the scale, for tests and the component gallery.
  static const Map<String, TextStyle> scale = {
    'display': display,
    'headlineLarge': headlineLarge,
    'headlineMedium': headlineMedium,
    'titleLarge': titleLarge,
    'titleMedium': titleMedium,
    'bodyLarge': bodyLarge,
    'bodyMedium': bodyMedium,
    'bodySmall': bodySmall,
    'labelLarge': labelLarge,
    'labelMedium': labelMedium,
    'labelSmall': labelSmall,
    'mono': mono,
  };

  /// [style] with tabular figures, for counts, energy, coins and times.
  static TextStyle numeric(TextStyle style) =>
      style.copyWith(fontFeatures: tabular);
}
