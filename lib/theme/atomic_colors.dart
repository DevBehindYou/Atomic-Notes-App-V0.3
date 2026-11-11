import 'package:flutter/material.dart';

/// Raw colours of the redesign. Components never read these directly; they
/// read the semantic roles in [AtomicColors], which differ per theme.
///
/// The first nine values are the "DevBehindYou / Color system" palette. The
/// derived values exist only because a palette colour fails WCAG AA in a
/// required pairing; each is checked in test/theme/atomic_contrast_test.dart.
/// See docs/planning/uiux-redesign-2026-11-09/01-design-tokens.md.
abstract final class AtomicPalette {
  // Palette.
  static const Color orange500 = Color(0xFFFE6902);
  static const Color black = Color(0xFF010101);
  static const Color gray900 = Color(0xFF1B1B1B);
  static const Color gray850 = Color(0xFF262626);
  static const Color gray800 = Color(0xFF393737);
  static const Color gray200 = Color(0xFFE5E5E5);
  static const Color red500 = Color(0xFFFF1500);
  static const Color blue500 = Color(0xFF1F1FFF);
  static const Color gray50 = Color(0xFFF6F6F6);
  static const Color white = Color(0xFFFFFFFF);

  // Derived, for contrast only.
  /// Secondary text on dark surfaces.
  static const Color gray500 = Color(0xFF9A9A9A);

  /// Secondary text on light surfaces.
  static const Color gray600 = Color(0xFF5C5C5C);

  /// Outlines and disabled content in both themes (3:1 against surfaces).
  static const Color gray450 = Color(0xFF757575);

  /// Orange as text or a thin line on light surfaces.
  static const Color orange700 = Color(0xFFB34700);

  /// Error text on dark surfaces.
  static const Color red400 = Color(0xFFFF4D3A);

  /// Error text on light surfaces.
  static const Color red700 = Color(0xFFD41100);

  /// Link and info text on dark surfaces.
  static const Color blue300 = Color(0xFF8C8CFF);
}

/// Semantic colour roles for one theme. Read them with `context.colors`.
@immutable
class AtomicColors extends ThemeExtension<AtomicColors> {
  const AtomicColors({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceInset,
    required this.surfaceRaised,
    required this.badge,
    required this.mascotStage,
    required this.inverseSurface,
    required this.onInverse,
    required this.importantTitle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.outline,
    required this.outlineStrong,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.danger,
    required this.onDanger,
    required this.dangerText,
    required this.info,
    required this.onInfo,
    required this.infoText,
    required this.focus,
    required this.selection,
    required this.scrim,
    required this.floatingShadow,
  });

  final Brightness brightness;

  /// Scaffold background.
  final Color canvas;

  /// Cards, list groups, dialogs and sheets.
  final Color surface;

  /// Pills inside cards, inputs, inactive chips on a card.
  final Color surfaceInset;

  /// Floating toolbar, menus, the search field over the canvas.
  final Color surfaceRaised;

  /// Count bubbles and switch tracks when off.
  final Color badge;

  /// The disc behind mascot art, light in both themes so dark pixel art
  /// stays visible.
  final Color mascotStage;

  /// Selected chip, snackbar and important note card.
  final Color inverseSurface;
  final Color onInverse;

  /// Title on an important note card: white in light (the accepted black
  /// card with a white title), black in dark.
  final Color importantTitle;

  final Color textPrimary;

  /// Dates, captions, counts and placeholders.
  final Color textSecondary;
  final Color textDisabled;

  /// Dividers and light-theme card edges.
  final Color outline;

  /// Input borders and unchecked checkbox rings (3:1 against surfaces).
  final Color outlineStrong;

  /// Orange fill only. Content on it uses [onAccent].
  final Color accent;
  final Color onAccent;

  /// Orange used as text or a line.
  final Color accentText;

  /// Red fill for destructive actions. Content on it uses [onDanger].
  final Color danger;
  final Color onDanger;
  final Color dangerText;

  /// Blue fill for information. Content on it uses [onInfo].
  final Color info;
  final Color onInfo;
  final Color infoText;

  /// Keyboard and switch-access focus ring.
  final Color focus;

  /// Text selection highlight.
  final Color selection;

  /// Behind dialogs and sheets.
  final Color scrim;

  /// Shadow colour for floating elements; transparent in dark, where depth
  /// is tonal only.
  final Color floatingShadow;

  bool get isDark => brightness == Brightness.dark;

  static const AtomicColors dark = AtomicColors(
    brightness: Brightness.dark,
    canvas: AtomicPalette.black,
    surface: AtomicPalette.gray900,
    surfaceInset: AtomicPalette.gray850,
    surfaceRaised: AtomicPalette.gray850,
    badge: AtomicPalette.gray800,
    mascotStage: AtomicPalette.gray200,
    inverseSurface: AtomicPalette.gray50,
    onInverse: AtomicPalette.black,
    importantTitle: AtomicPalette.black,
    textPrimary: AtomicPalette.gray50,
    textSecondary: AtomicPalette.gray500,
    textDisabled: AtomicPalette.gray450,
    outline: AtomicPalette.gray850,
    outlineStrong: AtomicPalette.gray450,
    accent: AtomicPalette.orange500,
    onAccent: AtomicPalette.black,
    accentText: AtomicPalette.orange500,
    danger: AtomicPalette.red500,
    onDanger: AtomicPalette.black,
    dangerText: AtomicPalette.red400,
    info: AtomicPalette.blue500,
    onInfo: AtomicPalette.white,
    infoText: AtomicPalette.blue300,
    focus: AtomicPalette.gray50,
    selection: Color(0x59FE6902), // orange500 at 35%
    scrim: Color(0x99010101), // black at 60%
    floatingShadow: Color(0x00000000),
  );

  static const AtomicColors light = AtomicColors(
    brightness: Brightness.light,
    canvas: AtomicPalette.gray50,
    surface: AtomicPalette.white,
    surfaceInset: AtomicPalette.gray50,
    surfaceRaised: AtomicPalette.white,
    badge: AtomicPalette.gray200,
    mascotStage: AtomicPalette.gray200,
    inverseSurface: AtomicPalette.black,
    onInverse: AtomicPalette.gray50,
    importantTitle: AtomicPalette.white,
    textPrimary: AtomicPalette.black,
    textSecondary: AtomicPalette.gray600,
    textDisabled: AtomicPalette.gray450,
    outline: AtomicPalette.gray200,
    outlineStrong: AtomicPalette.gray450,
    accent: AtomicPalette.orange500,
    onAccent: AtomicPalette.black,
    accentText: AtomicPalette.orange700,
    danger: AtomicPalette.red500,
    onDanger: AtomicPalette.black,
    dangerText: AtomicPalette.red700,
    info: AtomicPalette.blue500,
    onInfo: AtomicPalette.white,
    infoText: AtomicPalette.blue500,
    focus: AtomicPalette.black,
    selection: Color(0x4DFE6902), // orange500 at 30%
    scrim: Color(0x66010101), // black at 40%
    floatingShadow: Color(0x1A010101), // black at 10%
  );

  List<Color> get _values => [
    canvas,
    surface,
    surfaceInset,
    surfaceRaised,
    badge,
    mascotStage,
    inverseSurface,
    onInverse,
    importantTitle,
    textPrimary,
    textSecondary,
    textDisabled,
    outline,
    outlineStrong,
    accent,
    onAccent,
    accentText,
    danger,
    onDanger,
    dangerText,
    info,
    onInfo,
    infoText,
    focus,
    selection,
    scrim,
    floatingShadow,
  ];

  static AtomicColors _fromValues(Brightness brightness, List<Color> v) =>
      AtomicColors(
        brightness: brightness,
        canvas: v[0],
        surface: v[1],
        surfaceInset: v[2],
        surfaceRaised: v[3],
        badge: v[4],
        mascotStage: v[5],
        inverseSurface: v[6],
        onInverse: v[7],
        importantTitle: v[8],
        textPrimary: v[9],
        textSecondary: v[10],
        textDisabled: v[11],
        outline: v[12],
        outlineStrong: v[13],
        accent: v[14],
        onAccent: v[15],
        accentText: v[16],
        danger: v[17],
        onDanger: v[18],
        dangerText: v[19],
        info: v[20],
        onInfo: v[21],
        infoText: v[22],
        focus: v[23],
        selection: v[24],
        scrim: v[25],
        floatingShadow: v[26],
      );

  @override
  AtomicColors copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? surface,
    Color? surfaceInset,
    Color? surfaceRaised,
    Color? badge,
    Color? mascotStage,
    Color? inverseSurface,
    Color? onInverse,
    Color? importantTitle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? outline,
    Color? outlineStrong,
    Color? accent,
    Color? onAccent,
    Color? accentText,
    Color? danger,
    Color? onDanger,
    Color? dangerText,
    Color? info,
    Color? onInfo,
    Color? infoText,
    Color? focus,
    Color? selection,
    Color? scrim,
    Color? floatingShadow,
  }) => AtomicColors(
    brightness: brightness ?? this.brightness,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceInset: surfaceInset ?? this.surfaceInset,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    badge: badge ?? this.badge,
    mascotStage: mascotStage ?? this.mascotStage,
    inverseSurface: inverseSurface ?? this.inverseSurface,
    onInverse: onInverse ?? this.onInverse,
    importantTitle: importantTitle ?? this.importantTitle,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textDisabled: textDisabled ?? this.textDisabled,
    outline: outline ?? this.outline,
    outlineStrong: outlineStrong ?? this.outlineStrong,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    accentText: accentText ?? this.accentText,
    danger: danger ?? this.danger,
    onDanger: onDanger ?? this.onDanger,
    dangerText: dangerText ?? this.dangerText,
    info: info ?? this.info,
    onInfo: onInfo ?? this.onInfo,
    infoText: infoText ?? this.infoText,
    focus: focus ?? this.focus,
    selection: selection ?? this.selection,
    scrim: scrim ?? this.scrim,
    floatingShadow: floatingShadow ?? this.floatingShadow,
  );

  @override
  AtomicColors lerp(covariant AtomicColors? other, double t) {
    if (other == null) return this;
    final from = _values;
    final to = other._values;
    return _fromValues(t < 0.5 ? brightness : other.brightness, [
      for (var i = 0; i < from.length; i++) Color.lerp(from[i], to[i], t)!,
    ]);
  }
}

extension AtomicColorsContext on BuildContext {
  /// The current theme's colour roles. Falls back to the light roles when a
  /// widget is built under a theme without the extension, such as a bare
  /// test harness.
  AtomicColors get colors =>
      Theme.of(this).extension<AtomicColors>() ?? AtomicColors.light;
}
