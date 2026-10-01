import 'package:atomic_notes/utility/component/cloud_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

// Match MainPage's composition, with counters instead of network/UI work.
Widget control(
        {required bool busy,
        required VoidCallback sync,
        required VoidCallback energy}) =>
    MaterialApp(
        home: Scaffold(
            body: CloudButton(
      ico: 'assets/sync.svg',
      action: sync,
      clr: 0xff5F5EF7,
      isLoading: busy,
      onLongPress: energy,
    )));

void main() {
  testWidgets(
      'sync control exposes one named button and both accessible actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var syncs = 0, energies = 0;
      await tester.pumpWidget(
          control(busy: false, sync: () => syncs++, energy: () => energies++));
      expect(find.bySemanticsLabel('Sync now'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('Sync now'));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      expect(data.hint, 'Long press to open Atomic Energy');
      tester.semantics.tap(find.semantics.byLabel('Sync now'));
      tester.semantics.longPress(find.semantics.byLabel('Sync now'));
      await tester.pump();
      expect(syncs, 1);
      expect(energies, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('busy sync remains named and exposes only its Energy action',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var syncs = 0, energies = 0;
      await tester.pumpWidget(
          control(busy: true, sync: () => syncs++, energy: () => energies++));
      expect(find.bySemanticsLabel('Sync now'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('Sync now'));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.value, 'Syncing');
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      tester.semantics.longPress(find.semantics.byLabel('Sync now'));
      await tester.pump();
      expect(syncs, 0);
      expect(energies, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'pointer tap is blocked while busy and long press remains available',
      (tester) async {
    var syncs = 0, energies = 0;
    for (final busy in [false, true]) {
      await tester.pumpWidget(
          control(busy: busy, sync: () => syncs++, energy: () => energies++));
      await tester.tap(find.byType(CloudButton));
      await tester.pump();
      await tester.longPress(find.byType(CloudButton));
      await tester.pump();
    }
    expect(syncs, 1);
    expect(energies, 2);
  });
}
