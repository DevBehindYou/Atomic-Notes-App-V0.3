// The Recycle Bin and Danger Zone screens on top of their cubits, with a fake store. They need
// neither Hive nor the network.

import 'package:atomic_notes/page/endpage/danger_zone_page.dart';
import 'package:atomic_notes/page/endpage/recycle_bin_page.dart';
import 'package:atomic_notes/theme/editorial.dart';
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
    testWidgets('lists the deleted notes with their count, not the live ones', (tester) async {
      _tall(tester);
      await tester.pumpWidget(MaterialApp(home: RecycleBinPage(source: _withBin())));

      expect(find.text('TRIP PLAN'), findsOneWidget);
      expect(find.text('OLD SHOPPING LIST'), findsOneWidget);
      expect(find.text('STILL HERE'), findsNothing);
      expect(find.text('RESTORE'), findsNWidgets(2));
      expect(find.text('DELETE FOREVER'), findsNWidgets(2));
      expect(find.text('EMPTY BIN'), findsOneWidget);
    });

    testWidgets('restoring a note moves it out of the bin and says so', (tester) async {
      _tall(tester);
      final source = _withBin();
      await tester.pumpWidget(MaterialApp(home: RecycleBinPage(source: source)));

      await tester.tap(find.text('RESTORE').first);
      await tester.pump();
      await tester.pump();

      expect(find.text('Note restored'), findsOneWidget);
      expect(find.text('RESTORE'), findsOneWidget);
      expect(source.count, 2);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('a restore at the limit is refused and the note stays in the bin', (tester) async {
      _tall(tester);
      final source = _withBin()..limit = 1;
      await tester.pumpWidget(MaterialApp(home: RecycleBinPage(source: source)));

      await tester.tap(find.text('RESTORE').first);
      await tester.pump();
      await tester.pump();

      expect(find.text('Note limit reached (1). Delete a note to make room.'), findsOneWidget);
      expect(find.text('RESTORE'), findsNWidgets(2));
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('emptying the bin needs the slide, then removes the deleted notes', (tester) async {
      _tall(tester);
      final source = _withBin();
      await tester.pumpWidget(MaterialApp(home: RecycleBinPage(source: source)));

      await tester.tap(find.widgetWithText(InkActionButton, 'EMPTY BIN'));
      await tester.pumpAndSettle();
      expect(find.byType(SlideToConfirm), findsOneWidget);
      expect(source.binNotes, hasLength(2)); // nothing has run yet

      await tester.drag(find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(find.byType(SlideToConfirm), findsNothing);
      expect(find.text('Recycle Bin emptied'), findsOneWidget);
      expect(find.text('BIN IS EMPTY'), findsOneWidget);
      expect(source.byId('live'), isNotNull);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });

  group('Danger Zone', () {
    testWidgets('says how many notes a local wipe removes and warns about the unsynced ones', (tester) async {
      _tall(tester);
      final source = FakeNotesSource(notes: [
        syncedNote('a', title: 'A'),
        syncedNote('b', title: 'B')..touch(),
      ]);
      await tester.pumpWidget(MaterialApp(home: DangerZonePage(source: source)));

      expect(find.text('2 notes stored on this device.'), findsOneWidget);

      await tester.tap(find.widgetWithText(InkActionButton, 'WIPE LOCAL NOTES'));
      await tester.pumpAndSettle();
      expect(find.text('2 notes are removed from this device.'), findsOneWidget);
      expect(
          find.text('1 note has not been uploaded yet. It exists only on this device and '
              'will be lost for good.'),
          findsOneWidget);
    });

    testWidgets('the local wipe runs after the slide and reports the count', (tester) async {
      _tall(tester);
      final source = FakeNotesSource(notes: [syncedNote('a'), syncedNote('b')]);
      await tester.pumpWidget(MaterialApp(home: DangerZonePage(source: source)));

      await tester.tap(find.widgetWithText(InkActionButton, 'WIPE LOCAL NOTES'));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(source.count, 0);
      expect(find.textContaining('Removed 2 notes from this device'), findsOneWidget);
      expect(find.text('0 notes stored on this device.'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('a cloud wipe leaves the device alone', (tester) async {
      _tall(tester);
      final source = FakeNotesSource(notes: [syncedNote('a')]);
      await tester.pumpWidget(MaterialApp(home: DangerZonePage(source: source)));

      await tester.tap(find.widgetWithText(InkActionButton, 'WIPE CLOUD NOTES'));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(source.count, 1);
      expect(find.text('Cloud notes wiped. The notes on this device are untouched.'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
