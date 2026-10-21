import 'package:flutter/material.dart';
import '../../mascot/mascot_catalog.dart';
import '../../mascot/mascot_runtime.dart';
import '../../mascot/mascot_view.dart';

/// Runtime branding paths are intentionally separate from native/store artwork.
abstract final class AtomicBrandAssets {
  static const lightLogo =
      'assets/new-atomic-icons/png/atomic-icon-on-light.png';
  static const darkLogo = 'assets/new-atomic-icons/png/atomic-icon-on-dark.png';
}

int _decodeWidth(BuildContext context, double size) =>
    (size * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(1, 1024)
        .toInt();

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

/// Displays only the supplied catalog artwork. Small accents remain still.
class DevBehindYouMascot extends StatelessWidget {
  const DevBehindYouMascot({
    super.key,
    this.size = 72,
    this.secondary = false,
    this.interactive = false,
    this.onAdvance,
    this.semanticActionLabel = 'change animation',
  });
  final double size;
  final bool secondary;
  final bool interactive;
  final VoidCallback? onAdvance;
  final String semanticActionLabel;

  @override
  Widget build(BuildContext context) {
    final scope = MascotScope.maybeOf(context);
    Widget artwork() {
      final preferences = scope?.preferences.state.desired;
      final desired = MascotCatalog.findById(preferences?.selectedId ?? '');
      final mascot = desired ?? MascotCatalog.defaultMascot;
      return SizedBox(
        width: size,
        height: size,
        child: ClipRect(
            child: MascotView(
          mascot: mascot,
          resolver: scope?.resolver ?? BundledMascotResolver.instance,
          size: size,
          interactive: interactive,
          onAdvance: onAdvance,
          semanticActionLabel: semanticActionLabel,
          animationsEnabled: !secondary &&
              size >= 64 &&
              (preferences?.animationsEnabled ?? true),
          routeVisible: ModalRoute.of(context)?.isCurrent ?? true,
        )),
      );
    }

    if (scope == null) return artwork();
    return StreamBuilder(
      stream: scope.preferences.stream,
      builder: (context, _) => artwork(),
    );
  }
}
