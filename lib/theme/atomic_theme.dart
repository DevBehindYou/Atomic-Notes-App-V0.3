import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/material.dart';

/// Builds the redesign's light and dark [ThemeData] from one set of tokens.
///
/// Stock Material widgets that a screen does not style itself (dialogs,
/// fields, switches, scrollbars, selection handles) still land inside the
/// system. The colour scheme keeps orange off text: `primary` is the inverse
/// neutral, and orange reaches only the controls that fill with it.
abstract final class AtomicTheme {
  static ThemeData get light => build(AtomicColors.light);
  static ThemeData get dark => build(AtomicColors.dark);

  static ThemeData build(AtomicColors c) {
    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.inverseSurface,
      onPrimary: c.onInverse,
      primaryContainer: c.inverseSurface,
      onPrimaryContainer: c.onInverse,
      secondary: c.accent,
      onSecondary: c.onAccent,
      secondaryContainer: c.surfaceInset,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.info,
      onTertiary: c.onInfo,
      error: c.danger,
      onError: c.onDanger,
      errorContainer: c.surface,
      onErrorContainer: c.dangerText,
      surface: c.canvas,
      onSurface: c.textPrimary,
      surfaceContainerLowest: c.canvas,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceInset,
      surfaceContainerHighest: c.badge,
      onSurfaceVariant: c.textSecondary,
      outline: c.outlineStrong,
      outlineVariant: c.outline,
      inverseSurface: c.inverseSurface,
      onInverseSurface: c.onInverse,
      inversePrimary: c.accent,
      shadow: AtomicPalette.black,
      scrim: AtomicPalette.black,
      surfaceTint: Colors.transparent,
    );

    TextStyle ink(TextStyle style, [Color? color]) =>
        style.copyWith(color: color ?? c.textPrimary);

    final textTheme = TextTheme(
      displayLarge: ink(AtomicType.display),
      displayMedium: ink(AtomicType.headlineLarge),
      displaySmall: ink(AtomicType.headlineMedium),
      headlineLarge: ink(AtomicType.headlineLarge),
      headlineMedium: ink(AtomicType.headlineMedium),
      headlineSmall: ink(AtomicType.titleLarge),
      titleLarge: ink(AtomicType.titleLarge),
      titleMedium: ink(AtomicType.titleMedium),
      titleSmall: ink(AtomicType.labelMedium),
      bodyLarge: ink(AtomicType.bodyLarge),
      bodyMedium: ink(AtomicType.bodyMedium),
      bodySmall: ink(AtomicType.bodySmall, c.textSecondary),
      labelLarge: ink(AtomicType.labelLarge),
      labelMedium: ink(AtomicType.labelMedium),
      labelSmall: ink(AtomicType.labelSmall, c.textSecondary),
    );

    const pill = StadiumBorder();
    final fieldBorder = OutlineInputBorder(
      borderRadius: AtomicRadius.mediumAll,
      borderSide: BorderSide(color: c.outlineStrong),
    );
    WidgetStateProperty<T> selected<T>(T on, T off) =>
        WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? on : off,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      extensions: [c],
      fontFamily: AtomicFonts.sans,
      textTheme: textTheme,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconTheme: IconThemeData(color: c.textPrimary, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: ink(AtomicType.titleMedium),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AtomicRadius.largeAll,
          side: c.isDark ? BorderSide.none : BorderSide(color: c.outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: c.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius: AtomicRadius.xLargeAll,
        ),
        titleTextStyle: ink(AtomicType.titleLarge),
        contentTextStyle: ink(AtomicType.bodyMedium, c.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: c.scrim,
        showDragHandle: true,
        dragHandleColor: c.badge,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(borderRadius: AtomicRadius.sheet),
      ),
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.inverseSurface,
        contentTextStyle: ink(AtomicType.bodyMedium, c.onInverse),
        // Orange on the light inverse (near-white) fails contrast, so the
        // dark theme's action uses the darker orange.
        actionTextColor: c.isDark
            ? AtomicPalette.orange700
            : AtomicPalette.orange500,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: pill,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.inverseSurface,
          borderRadius: AtomicRadius.pill,
        ),
        textStyle: ink(AtomicType.bodySmall, c.onInverse),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: AtomicRadius.mediumAll,
        ),
        textStyle: ink(AtomicType.bodyMedium),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textPrimary,
        textColor: c.textPrimary,
        titleTextStyle: ink(AtomicType.titleMedium),
        subtitleTextStyle: ink(AtomicType.bodySmall, c.textSecondary),
        shape: const RoundedRectangleBorder(
          borderRadius: AtomicRadius.mediumAll,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceInset,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: ink(AtomicType.bodyMedium, c.textSecondary),
        labelStyle: ink(AtomicType.bodySmall, c.textSecondary),
        floatingLabelStyle: ink(AtomicType.bodySmall),
        helperStyle: ink(AtomicType.bodySmall, c.textSecondary),
        errorStyle: ink(AtomicType.bodySmall, c.dangerText),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        disabledBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: c.outline),
        ),
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: c.focus, width: 2),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: c.danger, width: 2),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: c.danger, width: 2),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accentText,
        selectionColor: c.selection,
        selectionHandleColor: c.accent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.surfaceInset,
          disabledForegroundColor: c.textDisabled,
          minimumSize: const Size(64, AtomicSpace.minTarget),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: pill,
          textStyle: AtomicType.labelLarge,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.inverseSurface,
          foregroundColor: c.onInverse,
          disabledBackgroundColor: c.surfaceInset,
          disabledForegroundColor: c.textDisabled,
          minimumSize: const Size(64, AtomicSpace.minTarget),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: pill,
          textStyle: AtomicType.labelLarge,
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.outlineStrong),
          minimumSize: const Size(64, AtomicSpace.minTarget),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: pill,
          textStyle: AtomicType.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(48, AtomicSpace.minTarget),
          shape: pill,
          textStyle: AtomicType.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(AtomicSpace.minTarget, AtomicSpace.minTarget),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: selected(c.onAccent, c.outlineStrong),
        trackColor: selected(c.accent, c.badge),
        trackOutlineColor: selected(Colors.transparent, c.outlineStrong),
        trackOutlineWidth: const WidgetStatePropertyAll(1.5),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        fillColor: selected(c.accent, Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.onAccent),
        side: BorderSide(color: c.outlineStrong, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: selected(c.textPrimary, c.outlineStrong),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceInset,
        circularTrackColor: c.surfaceInset,
        linearMinHeight: 8,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(c.outlineStrong),
        radius: const Radius.circular(AtomicRadius.full),
        thickness: const WidgetStatePropertyAll(4),
      ),
    );
  }
}
