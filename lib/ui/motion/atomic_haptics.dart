import 'package:flutter/services.dart';

/// The haptic a control plays when used (redesign D7).
enum AtomicHaptic { none, selection, light, medium }

/// The one place the app asks for haptics. Haptics are not motion: reduced
/// motion does not turn them off.
abstract final class AtomicHaptics {
  /// Turns every haptic off, for a future setting.
  static bool enabled = true;

  static Future<void> play(AtomicHaptic haptic) {
    if (!enabled) return Future<void>.value();
    return switch (haptic) {
      AtomicHaptic.none => Future<void>.value(),
      AtomicHaptic.selection => HapticFeedback.selectionClick(),
      AtomicHaptic.light => HapticFeedback.lightImpact(),
      AtomicHaptic.medium => HapticFeedback.mediumImpact(),
    };
  }
}
