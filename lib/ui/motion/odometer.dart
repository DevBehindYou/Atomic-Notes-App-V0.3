import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/widgets.dart';

/// A number whose digits roll like an odometer: each digit column slides to
/// its value over `roll` with the expressive curve, 90 ms after the digit to
/// its right. Other characters ("," or "−") stand still. Under reduced
/// motion the number changes at once.
///
/// Screen readers hear [text] (or [semanticsLabel]) once, not each column.
class Odometer extends StatelessWidget {
  const Odometer({
    super.key,
    required this.text,
    required this.style,
    this.rollOnEntry = true,
    this.semanticsLabel,
  });

  /// Already formatted, for example "1,250".
  final String text;
  final TextStyle style;

  /// Roll up from zero when first shown.
  final bool rollOnEntry;
  final String? semanticsLabel;

  static const Duration digitDelay = Duration(milliseconds: 90);

  @override
  Widget build(BuildContext context) {
    final numeric = AtomicType.numeric(style);
    final chars = text.split('');
    final children = <Widget>[];
    var position = 0;
    for (var i = chars.length - 1; i >= 0; i--) {
      final digit = int.tryParse(chars[i]);
      if (digit == null) {
        children.add(Text(chars[i], style: numeric));
      } else {
        children.add(_DigitColumn(
          // Keyed from the right, so 99 -> 100 keeps the columns it shares.
          key: ValueKey('digit-$position'),
          digit: digit,
          delay: digitDelay * position,
          rollOnEntry: rollOnEntry,
          style: numeric,
        ));
        position++;
      }
    }
    return Semantics(
      label: semanticsLabel ?? text,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children.reversed.toList(),
        ),
      ),
    );
  }
}

class _DigitColumn extends StatelessWidget {
  const _DigitColumn({
    super.key,
    required this.digit,
    required this.delay,
    required this.rollOnEntry,
    required this.style,
  });

  final int digit;
  final Duration delay;
  final bool rollOnEntry;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final total = AtomicMotion.roll + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: rollOnEntry ? 0 : null, end: digit.toDouble()),
      duration: AtomicMotion.move(context, total),
      curve: Interval(start, 1, curve: AtomicMotion.expressiveCurve),
      builder: (context, t, _) => ClipRect(
        child: Stack(
          children: [
            // Sizes the window to one digit.
            Opacity(opacity: 0, child: Text('0', style: style)),
            Positioned.fill(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: double.infinity,
                child: FractionalTranslation(
                  translation: Offset(0, -t / 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var d = 0; d < 10; d++) Text('$d', style: style),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
