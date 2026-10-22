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

/// Supplied Atomic icon animation. Playback never controls startup routing.
class AtomicSplashMark extends StatefulWidget {
  const AtomicSplashMark({super.key, this.size = 96});
  final double size;

  @override
  State<AtomicSplashMark> createState() => _AtomicSplashMarkState();
}

class _AtomicSplashMarkState extends State<AtomicSplashMark>
    with WidgetsBindingObserver {
  late bool _resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _resumed = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final animate = _resumed &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    final asset = animate
        ? (dark
            ? AtomicSplashAssets.darkAnimation
            : AtomicSplashAssets.lightAnimation)
        : (dark ? AtomicSplashAssets.darkStill : AtomicSplashAssets.lightStill);
    // Flutter streams frames from one codec. Replacing the animated Image
    // removes its listener and stops frame scheduling while hidden or paused.
    return Semantics(
      label: 'Atomic Notes',
      image: true,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: Image.asset(
            asset,
            key: ValueKey(asset),
            width: widget.size,
            height: widget.size,
            cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context))
                .ceil()
                .clamp(1, 480),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) =>
                AtomicBrandMark(size: widget.size, onDark: dark),
          ),
        ),
      ),
    );
  }
}
