import 'package:flutter/material.dart';
import 'atomic_brand.dart';

abstract final class AtomicSplashAssets {
  static const lightAnimation =
      'assets/new-atomic-icons/gif/atomic-spin-on-light.gif';
  static const darkAnimation =
      'assets/new-atomic-icons/gif/atomic-spin-on-dark.gif';
  static const lightStill =
      'assets/atomic-splash/atomic-spin-on-light-static.png';
  static const darkStill =
      'assets/atomic-splash/atomic-spin-on-dark-static.png';
}

/// Static supplied Atomic artwork. Rendering never controls startup routing.
class AtomicSplashMark extends StatelessWidget {
  const AtomicSplashMark({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final asset =
        dark ? AtomicSplashAssets.darkStill : AtomicSplashAssets.lightStill;
    return Semantics(
      label: 'Atomic Notes',
      image: true,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: Image.asset(
            asset,
            key: ValueKey(asset),
            width: size,
            height: size,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                .ceil()
                .clamp(1, 480),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) =>
                AtomicBrandMark(size: size, onDark: dark),
          ),
        ),
      ),
    );
  }
}
