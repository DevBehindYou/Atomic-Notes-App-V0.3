// Legacy slide-to-confirm tests for the control still used by the Recycle Bin.

import 'package:atomic_notes/utility/component/slide_to_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SlideToConfirm', () {
    Future<void> pumpSlider(
        WidgetTester tester, Future<void> Function() onConfirmed) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: SlideToConfirm(label: 'wipe', onConfirmed: onConfirmed),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a short slide snaps back and confirms nothing',
        (tester) async {
      var confirmed = 0;
      await pumpSlider(tester, () async => confirmed++);
      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 0);
    });

    testWidgets('sliding all the way confirms exactly once', (tester) async {
      var confirmed = 0;
      await pumpSlider(tester, () async => confirmed++);
      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
    });
  });

}
