import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('press follows ADR-011: 0.965 over 90 ms, 460 ms return', () {
    expect(AtomicMotion.pressScale, 0.965);
    expect(AtomicMotion.pressIn, const Duration(milliseconds: 90));
    expect(AtomicMotion.pressOut, const Duration(milliseconds: 460));
  });

  test('duration tokens match spec 04', () {
    expect(AtomicMotion.instant.inMilliseconds, 100);
    expect(AtomicMotion.quick.inMilliseconds, 150);
    expect(AtomicMotion.standard.inMilliseconds, 250);
    expect(AtomicMotion.emphasized.inMilliseconds, 350);
    expect(AtomicMotion.slow.inMilliseconds, 500);
    expect(AtomicMotion.entrance.inMilliseconds, inInclusiveRange(560, 620));
    expect(AtomicMotion.roll.inMilliseconds, inInclusiveRange(1100, 1300));
    expect(AtomicMotion.staggerMaxItems, 8);
    expect(AtomicMotion.maxAmbientLoops, 2);
  });

  test('the overshoot curve passes its target; the others do not', () {
    double peak(Curve curve) {
      var max = 0.0;
      for (var i = 0; i <= 100; i++) {
        final v = curve.transform(i / 100);
        if (v > max) max = v;
      }
      return max;
    }

    expect(peak(AtomicMotion.overshootCurve), greaterThan(1.0));
    expect(peak(AtomicMotion.standardCurve), lessThanOrEqualTo(1.0));
    expect(peak(AtomicMotion.ambientCurve), lessThanOrEqualTo(1.0));
  });

  Future<BuildContext> contextWith(WidgetTester tester, MediaQueryData data) async {
    late BuildContext captured;
    await tester.pumpWidget(MediaQuery(
      data: data,
      child: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      }),
    ));
    return captured;
  }

  testWidgets('full motion passes durations through', (tester) async {
    final context = await contextWith(tester, const MediaQueryData());
    expect(AtomicMotion.reduced(context), isFalse);
    expect(AtomicMotion.move(context, AtomicMotion.entrance), AtomicMotion.entrance);
    expect(AtomicMotion.fade(context, AtomicMotion.slow), AtomicMotion.slow);
  });

  for (final data in const [
    MediaQueryData(disableAnimations: true),
    MediaQueryData(accessibleNavigation: true),
  ]) {
    testWidgets('reduced motion zeroes movement and caps fades '
        '(disableAnimations=${data.disableAnimations}, '
        'accessibleNavigation=${data.accessibleNavigation})', (tester) async {
      final context = await contextWith(tester, data);
      expect(AtomicMotion.reduced(context), isTrue);
      expect(AtomicMotion.move(context, AtomicMotion.entrance), Duration.zero);
      expect(AtomicMotion.fade(context, AtomicMotion.slow), AtomicMotion.reducedFade);
      expect(AtomicMotion.fade(context, AtomicMotion.instant), AtomicMotion.instant);
    });
  }
}
