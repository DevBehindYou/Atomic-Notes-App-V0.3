@TestOn('browser')
library;

import 'package:atomic_notes/main.dart' as app;
import 'package:atomic_notes/platform/browser_preview_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  testWidgets('actual browser entry stays outside native startup and routes', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(find.byType(BrowserPreviewGate), findsOneWidget);
    expect(find.text('WEBAPP IN DEVELOPMENT'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final box in ['authBox', 'syncBox', 'notesBox']) {
      expect(Hive.isBoxOpen(box), isFalse);
    }
    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.routes, isEmpty);
    expect(material.onGenerateRoute, isNull);
    expect(material.onUnknownRoute, isNull);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
