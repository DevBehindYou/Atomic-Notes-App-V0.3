// The Recycle Bin screen on top of its cubit, with a fake store. It needs
// neither Hive nor the network.

import 'package:atomic_notes/page/endpage/recycle_bin_page.dart';
import 'package:atomic_notes/utility/component/slide_to_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

FakeNotesSource _withBin() {
  final older = syncedNote('old', title: 'Old shopping list')..deleted = true;
  older.updatedAt = DateTime.utc(2026, 9, 1);
  final newer = syncedNote('new', title: 'Trip plan', body: 'Pack the bags')
    ..deleted = true;
  newer.updatedAt = DateTime.utc(2026, 9, 2);
  return FakeNotesSource(notes: [syncedNote('live', title: 'Still here'), older, newer]);
}

void main() {
  group('Recycle Bin', () {
    testWidgets('lists the deleted notes, not the live ones', (tester) async {
      _tall(tester);
      await tester.pumpWidget(MaterialApp(home: RecycleBinPage(source: _withBin())));

      expect(find.text('Trip plan'), findsOneWidget);
      expect(find.text('Old shopping list'), findsOneWidget);
      expect(find.text('Still here'), findsNothing);
      expect(find.text('Restore'), findsNWidgets(2));
      expect(find.text('Delete forever'), findsNWidgets(2));
      // Empty bin is in the header's "…" menu.
      expect(find.byTooltip('More options'), findsOneWidget);
    });

    testWidgets('restoring a note moves it out of the bin and says so', (tester) async {
      _tall(tester);
      final source = _withBin();
      await tester.pumpWidget(MaterialApp(home: RecycleBinPage(source: source)));

      await tester.tap(find.text('Restore').first);
      await tester.pump();
      await tester.pump();

      expect(find.text('Note restored'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
      expect(source.count, 2);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('a restore at the limit is refused and the note stays in the bin', (tester) async {
      _tall(tester);
      final source = _withBin()..limit = 1;
      await tester.pumpWidget(MaterialApp(home: RecycleBinPage(source: source)));

      await tester.tap(find.text('Restore').first);
      await tester.pump();
      await tester.pump();

      expect(find.text('Note limit reached (1). Delete a note to make room.'), findsOneWidget);
      expect(find.text('Restore'), findsNWidgets(2));
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('emptying the bin needs the slide, then removes the deleted notes', (tester) async {
      _tall(tester);
      final source = _withBin();
      await tester.pumpWidget(MaterialApp(home: RecycleBinPage(source: source)));

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty bin'));
      await tester.pumpAndSettle();
      expect(find.byType(SlideToConfirm), findsOneWidget);
      expect(source.binNotes, hasLength(2)); // nothing has run yet

      await tester.drag(find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(find.byType(SlideToConfirm), findsNothing);
      expect(find.text('Recycle Bin emptied'), findsOneWidget);
      expect(find.text('Recycle Bin is empty'), findsOneWidget);
      expect(source.byId('live'), isNotNull);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });

}
