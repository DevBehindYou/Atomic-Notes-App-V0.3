import 'package:flutter/material.dart';

/// Runtime branding paths are intentionally separate from native/store artwork.
abstract final class AtomicBrandAssets {
  static const lightLogo =
      'assets/new-atomic-icons/png/atomic-icon-on-light.png';
  static const darkLogo = 'assets/new-atomic-icons/png/atomic-icon-on-dark.png';
  static const worker = 'assets/Atomic Icons/devbehindyou-worker.gif';
  static const dotgrid = 'assets/Atomic Icons/dotgrid-blink-transparent.gif';
  static const workerStatic =
      'assets/new-atomic-icons/png/devbehindyou-worker-static.png';
  static const dotgridStatic = 'assets/new-atomic-icons/png/dotgrid-static.png';
}

int _decodeWidth(BuildContext context, double size) =>
    (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 1024).toInt();

class AtomicBrandMark extends StatelessWidget {
  const AtomicBrandMark({super.key, this.size = 44, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Image.asset(
    onDark ? AtomicBrandAssets.darkLogo : AtomicBrandAssets.lightLogo,
    width: size,
    height: size,
    cacheWidth: _decodeWidth(context, size),
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    filterQuality: FilterQuality.medium,
  );
}

/// DevBehindYou is the primary mascot; dotgrid is a secondary activity accent.
/// Decode at display resolution, and use static frames for reduced motion and
/// inactive routes. Neither rendering nor animation gates navigation or sync.
class DevBehindYouMascot extends StatelessWidget {
  const DevBehindYouMascot({super.key, this.size = 72, this.secondary = false});

  final double size;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final still =
        MediaQuery.disableAnimationsOf(context) || !TickerMode.of(context);
    final fallback = secondary
        ? AtomicBrandAssets.dotgridStatic
        : AtomicBrandAssets.workerStatic;
    final source = still
        ? fallback
        : secondary
        ? AtomicBrandAssets.dotgrid
        : AtomicBrandAssets.worker;
    return Image.asset(
      source,
      width: size,
      height: size,
      cacheWidth: _decodeWidth(context, size),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => Image.asset(
        fallback,
        width: size,
        height: size,
        cacheWidth: _decodeWidth(context, size),
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}
