// The debug-only component gallery.

import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/gallery/component_gallery.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

void main() {
  test('the route exists in debug builds only', () {
    expect(ComponentGallery.debugRoutes.keys,
        kDebugMode ? [ComponentGallery.route] : isEmpty);
  });

  testWidgets('renders every section and switches theme', (tester) async {
    await tester.pumpWidget(
        MaterialApp(theme: AtomicTheme.light, home: const ComponentGallery()));
    expect(find.text('Components'), findsOneWidget);
    await tester.tap(find.byTooltip('Dark theme'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Light theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits 2.0 text in 320 dp', (tester) async {
    await pumpNarrow(
        tester, const SizedBox(height: 600, child: ComponentGallery()),
        theme: AtomicTheme.light);
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
