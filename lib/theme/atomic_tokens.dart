import 'package:flutter/widgets.dart';

/// Spacing on a 4 dp grid.
abstract final class AtomicSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;

  /// Gap between note cards, both axes.
  static const double gridGap = 12;

  /// Standard card padding.
  static const double cardPadding = 16;

  /// Featured card, hero cards and dialogs.
  static const double heroPadding = 20;

  /// Between setting groups and page sections.
  static const double sectionGap = 32;

  /// Between chips.
  static const double chipGap = 8;

  /// Bottom padding under scrolling content so the new-note button never
  /// covers the last card.
  static const double fabClearance = 104;

  /// Minimum touch target in both dimensions.
  static const double minTarget = 48;

  /// Page side margin: 20 below 400 dp width, 24 from 400 dp.
  static double screenMargin(double width) => width < 400 ? 20 : 24;
}

/// Corner radii.
abstract final class AtomicRadius {
  static const double small = 12;
  static const double medium = 20;
  static const double large = 26;
  static const double xLarge = 32;
  static const double full = 999;

  static const BorderRadius smallAll = BorderRadius.all(Radius.circular(small));
  static const BorderRadius mediumAll = BorderRadius.all(
    Radius.circular(medium),
  );
  static const BorderRadius largeAll = BorderRadius.all(Radius.circular(large));
  static const BorderRadius xLargeAll = BorderRadius.all(
    Radius.circular(xLarge),
  );
  static const BorderRadius pill = BorderRadius.all(Radius.circular(full));

  /// Bottom sheets: rounded top corners only.
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(large),
  );
}

/// Durations and curves. No screen declares its own.
abstract final class AtomicMotion {
  /// Press feedback.
  static const Duration instant = Duration(milliseconds: 100);

  /// Chip and segmented highlights, switch colour, icon swaps.
  static const Duration quick = Duration(milliseconds: 150);

  /// Cards, sheets, dialogs, list insert and remove.
  static const Duration standard = Duration(milliseconds: 250);

  /// Page push and editor open or close.
  static const Duration emphasized = Duration(milliseconds: 350);

  /// Onboarding art and the first Home entrance.
  static const Duration slow = Duration(milliseconds: 500);

  /// Screen entrance cascade: each block rises 18 dp and fades in over this,
  /// [entranceStep] apart.
  static const Duration entrance = Duration(milliseconds: 620);
  static const Duration entranceStep = Duration(milliseconds: 60);
  static const double entranceRise = 18;

  /// List stagger inside a screen: at most [staggerMaxItems] items,
  /// [staggerStep] apart, starting [staggerDelay] into the entrance.
  static const Duration staggerStep = Duration(milliseconds: 45);
  static const Duration staggerDelay = Duration(milliseconds: 200);
  static const int staggerMaxItems = 8;

  /// Odometer digits and progress fills.
  static const Duration roll = Duration(milliseconds: 1200);

  /// Press feedback (ADR-011): scale to [pressScale] over [pressIn], then a
  /// bounded overshooting return over [pressOut]. The return never blocks the
  /// control, and the hit area does not scale.
  static const double pressScale = 0.965;
  static const Duration pressIn = Duration(milliseconds: 90);
  static const Duration pressOut = Duration(milliseconds: 460);

  /// The longest cross-fade allowed when reduced motion is on.
  static const Duration reducedFade = Duration(milliseconds: 150);

  /// At most this many continuously repeating effects may run at once.
  /// Finite transitions and interactive animations do not count.
  static const int maxAmbientLoops = 2;

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Entrances, odometer and bursts: fast start, long soft landing.
  static const Curve expressiveCurve = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Press release, check pops and icon swaps: a small bounce past the target.
  static const Curve overshootCurve = Cubic(0.34, 1.56, 0.64, 1.0);

  /// Ambient loops: float, scan, orbit breathing.
  static const Curve ambientCurve = Cubic(0.45, 0.0, 0.55, 1.0);

  /// Whether the platform asks for reduced motion.
  static bool reduced(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return false;
    return media.disableAnimations || media.accessibleNavigation;
  }

  /// Duration for movement: slides, scales, staggers, count-ups and pulses.
  /// Zero under reduced motion, so the change is instant.
  static Duration move(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  /// Duration for cross-fades. Capped at [reducedFade] under reduced motion.
  static Duration fade(BuildContext context, Duration duration) =>
      reduced(context) && duration > reducedFade ? reducedFade : duration;
}
