import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:flutter/widgets.dart';

/// The round light disc the mascot stands on (components spec, Mascot stage
/// and bubble), in the same colour in both themes, so the pixel art keeps
/// the light ground it was drawn for and never needs recolouring.
///
/// It only adds the disc: the page passes the mascot ([child]), so every
/// existing mascot rule (the 64 dp minimum to animate, `secondary` never
/// animating, reduced motion, tap behaviour) stays with `DevBehindYouMascot`.
/// Size the mascot with [artSize].
class MascotStage extends StatelessWidget {
  const MascotStage({super.key, required this.size, required this.child});

  /// 56 in the Home status strip, 96 in empty states, 160 on Mascot
  /// settings.
  final double size;
  final Widget child;

  static const double padding = 6;

  /// The mascot size that fits a stage of [size].
  static double artSize(double size) => size - padding * 2;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: context.colors.mascotStage,
        shape: BoxShape.circle,
      ),
      child: Center(child: child),
    );
  }
}
