// The Recycle Bin on lib/ui components (screens spec, Recycle Bin): compact
// cards with Restore and Delete forever buttons, Empty bin in the header's
// "…" menu, the shared empty state, and the layout checks every redesigned
// page passes. A fake store; no Hive or network.

import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/page/endpage/recycle_bin_page.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/feedback/empty_state.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/utility/component/slide_to_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

final DateTime _now = DateTime(2026, 11, 17, 12);

Note _binned(String id,
    {String title = '',
    String body = '',
    NoteKind kind = NoteKind.text,
    List<TodoItem>? items,
    required DateTime deletedAt}) {
  final n = syncedNote(id, title: title, body: body, kind: kind, items: items)
    ..deleted = true;
  n.updatedAt = deletedAt;
  return n;
}

FakeNotesSource _withBin({int extra = 0}) => FakeNotesSource(notes: [
      syncedNote('live', title: 'Still here'),
      _binned('trip',
          title: 'Trip plan',
          body: 'Pack the bags',
          deletedAt: DateTime(2026, 9, 2, 10)),
      _binned('list',
          title: 'Groceries',
          kind: NoteKind.todo,
          items: [TodoItem(text: 'Milk')],
          deletedAt: DateTime(2025, 12, 31, 23)),
      _binned('blank', deletedAt: DateTime(2026, 11, 9, 8)),
      for (var i = 0; i < extra; i++)
        _binned('extra$i',
            title: 'Extra note $i', deletedAt: DateTime(2026, 10, 1)),
    ]);

/// A store whose restores wait for [gate], counting each call.
class _GatedSource extends FakeNotesSource {
  _GatedSource({super.notes});

  final Completer<void> gate = Completer<void>();
  int restores = 0;

  @override
  Future<bool> restoreNote(String id) async {
    restores++;
    await gate.future;
    return super.restoreNote(id);
  }
}

Future<void> _pump(
  WidgetTester tester,
  FakeNotesSource source, {
  ThemeData? theme,
  double width = 412,
  double height = 915,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: RecycleBinPage(source: source, now: () => _now),
  ));
  await tester.pumpAndSettle();
}

Future<void> _settleSnackBar(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(seconds: 4));

/// The [label] button on the card of the note [id]. The bin lists the
/// newest deletion first, as the store returns it.
Finder _button(String id, String label) => find.descendant(
    of: find.byKey(ValueKey('bin-$id')),
    matching: find.widgetWithText(AtomicButton, label));

void main() {
  group('deletedLabel', () {
    test('day and month in the current year', () {
      expect(RecycleBinPage.deletedLabel(DateTime(2026, 11, 9, 8), _now),
          'Deleted 9 Nov');
      expect(RecycleBinPage.deletedLabel(DateTime(2026, 1, 1), _now),
          'Deleted 1 Jan');
    });

    test('the year is added for another year', () {
      expect(RecycleBinPage.deletedLabel(DateTime(2025, 12, 31, 23), _now),
          'Deleted 31 Dec 2025');
      expect(RecycleBinPage.deletedLabel(DateTime(2027, 2, 3), _now),
          'Deleted 3 Feb 2027');
    });

    test('reads a UTC time in local time', () {
      final utc = DateTime.utc(2026, 9, 2, 10);
      final local = utc.toLocal();
      expect(RecycleBinPage.deletedLabel(utc, _now),
          RecycleBinPage.deletedLabel(local, _now));
    });
  });

  group('cards', () {
    testWidgets('each deleted note shows its title, date and preview line',
        (tester) async {
      await _pump(tester, _withBin());

      expect(find.text('Trip plan'), findsOneWidget);
      expect(find.text('Deleted 2 Sep'), findsOneWidget);
      expect(find.text('Pack the bags'), findsOneWidget);
      // A checklist says so; another year shows the year.
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Checklist · Deleted 31 Dec 2025'), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);
      // A note without a title.
      expect(find.text('Untitled'), findsOneWidget);
      expect(find.text('Deleted 9 Nov'), findsOneWidget);
      // Live notes are not in the bin.
      expect(find.text('Still here'), findsNothing);
    });

    testWidgets('Restore is tonal and Delete forever is danger',
        (tester) async {
      await _pump(tester, _withBin());

      final restore = tester.widget<AtomicButton>(_button('trip', 'Restore'));
      final delete =
          tester.widget<AtomicButton>(_button('trip', 'Delete forever'));
      expect(restore.variant, AtomicButtonVariant.tonal);
      expect(restore.size, AtomicButtonSize.compact);
      expect(restore.onCard, isTrue);
      expect(delete.variant, AtomicButtonVariant.danger);
      expect(delete.size, AtomicButtonSize.compact);
      expect(find.widgetWithText(AtomicButton, 'Restore'), findsNWidgets(3));
      expect(find.widgetWithText(AtomicButton, 'Delete forever'),
          findsNWidgets(3));
    });

    testWidgets('a second tap while a restore runs does not restore twice',
        (tester) async {
      final source = _GatedSource(notes: _withBin().all.toList());
      await _pump(tester, source);

      final restore = _button('trip', 'Restore');
      await tester.tap(restore);
      await tester.pump();
      expect(tester.widget<AtomicButton>(restore).busy, isTrue);
      // The other action waits too.
      expect(
          tester
              .widget<AtomicButton>(_button('trip', 'Delete forever'))
              .onPressed,
          isNull);
      await tester.tap(restore, warnIfMissed: false);
      await tester.pump();
      expect(source.restores, 1);

      source.gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Note restored'), findsOneWidget);
      expect(find.text('Trip plan'), findsNothing);
      expect(source.restores, 1);
      await _settleSnackBar(tester);
    });
  });

  group('delete forever', () {
    testWidgets('asks first, names the note, and Cancel keeps it',
        (tester) async {
      final source = _withBin();
      await _pump(tester, source);

      await tester.tap(_button('trip', 'Delete forever'));
      await tester.pumpAndSettle();

      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
      expect(find.text('Delete "Trip plan" for good?'), findsOneWidget);
      expect(
          find.text('It is removed from this device. Its cloud copy stays in '
              'your Google Drive trash until Drive empties it.'),
          findsOneWidget);
      final dialog =
          tester.widget<AtomicDialog<bool>>(find.byType(AtomicDialog<bool>));
      expect(dialog.destructive, isTrue);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(source.byId('trip'), isNotNull);
      expect(find.text('Trip plan'), findsOneWidget);
    });

    testWidgets('a tap on the scrim does not dismiss it', (tester) async {
      final source = _withBin();
      await _pump(tester, source);

      await tester.tap(_button('trip', 'Delete forever'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
      expect(source.byId('trip'), isNotNull);
    });

    testWidgets('confirming deletes the note and says so', (tester) async {
      final source = _withBin();
      await _pump(tester, source);

      await tester.tap(_button('trip', 'Delete forever'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AtomicDialog<bool>),
          matching: find.text('Delete forever')));
      await tester.pumpAndSettle();

      expect(source.byId('trip'), isNull);
      expect(find.text('Deleted for good'), findsOneWidget);
      expect(find.text('Trip plan'), findsNothing);
      await _settleSnackBar(tester);
    });

    testWidgets('a deletion that has not reached the cloud keeps the note',
        (tester) async {
      final source = _withBin()..deleteForeverWorks = false;
      await _pump(tester, source);

      await tester.tap(_button('trip', 'Delete forever'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AtomicDialog<bool>),
          matching: find.text('Delete forever')));
      await tester.pumpAndSettle();

      expect(source.byId('trip'), isNotNull);
      expect(
          find.text('Could not delete yet. Turn on Cloud Sync and sync first.'),
          findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('an untitled note is "this note"', (tester) async {
      await _pump(tester, _withBin());

      await tester.tap(_button('blank', 'Delete forever'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this note for good?'), findsOneWidget);
    });
  });

  group('header menu', () {
    testWidgets('Empty bin is in the "…" menu and needs the slide',
        (tester) async {
      final source = _withBin();
      await _pump(tester, source);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Empty bin'), findsOneWidget);

      await tester.tap(find.text('Empty bin'));
      await tester.pumpAndSettle();
      expect(find.text('Empty bin'), findsNothing); // the sheet closed
      expect(find.byType(SlideToConfirm), findsOneWidget);
      expect(
          find.text('3 deleted notes are removed from this device for good.'),
          findsOneWidget);
      expect(source.binNotes, hasLength(3)); // nothing has run yet

      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(source.binNotes, isEmpty);
      expect(source.byId('live'), isNotNull);
      expect(find.text('Recycle Bin emptied'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
      // Nothing destructive is left to offer.
      expect(find.byTooltip('More options'), findsNothing);
      await _settleSnackBar(tester);
    });

    testWidgets('closing the menu does nothing', (tester) async {
      final source = _withBin();
      await _pump(tester, source);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Empty bin'), findsNothing);
      expect(find.byType(SlideToConfirm), findsNothing);
      expect(source.binNotes, hasLength(3));
    });

    testWidgets('a bin emptied while the menu was open skips the slide',
        (tester) async {
      final source = _withBin();
      await _pump(tester, source);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await source.deleteForever(source.binNotes.map((n) => n.id).toList());
      await tester.pump();
      await tester.tap(find.text('Empty bin'));
      await tester.pumpAndSettle();
      expect(find.byType(SlideToConfirm), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);
    });
  });

  group('page', () {
    testWidgets('the empty state names the space', (tester) async {
      await _pump(tester, FakeNotesSource(notes: [syncedNote('live')]));

      expect(find.text('Recycle Bin is empty'), findsOneWidget);
      expect(find.text('Notes you delete wait here first.'), findsOneWidget);
      expect(find.byTooltip('More options'), findsNothing);
    });

    testWidgets('the back button leaves the page', (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AtomicTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) =>
                        RecycleBinPage(source: _withBin(), now: () => _now))),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Trip plan'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Trip plan'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('the header shows the title once the large one scrolls away',
        (tester) async {
      await _pump(tester, _withBin(extra: 12), height: 700);

      AtomicPageHeader header() =>
          tester.widget<AtomicPageHeader>(find.byType(AtomicPageHeader));
      expect(header().showTitle, isFalse);

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(header().showTitle, isTrue);

      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(header().showTitle, isFalse);
    });

    for (final (name, theme) in [
      ('light', AtomicTheme.light),
      ('dark', AtomicTheme.dark),
    ]) {
      for (final direction in TextDirection.values) {
        testWidgets(
            'fits 320 dp at 2.0 text ($name, ${direction.name}), '
            'down to the last card', (tester) async {
          await _pump(tester, _withBin(extra: 3),
              theme: theme,
              width: 320,
              height: 640,
              textScale: 2,
              direction: direction);
          expect(tester.takeException(), isNull);

          for (var i = 0; i < 12; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -400));
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // The oldest deletion is the last card.
          expect(find.text('Groceries'), findsOneWidget);

          // The dialog and the menu fit as well.
          await tester.tap(_button('list', 'Delete forever'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('More options'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('targets are at least 48 dp', (tester) async {
      await _pump(tester, _withBin());

      for (final finder in [
        _button('trip', 'Restore'),
        _button('trip', 'Delete forever'),
        find.byTooltip('More options'),
        find.byTooltip('Back'),
      ]) {
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
      }
    });

    testWidgets('screen readers hear the buttons and the menu', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _withBin());

      expect(find.bySemanticsLabel('Restore'), findsNWidgets(3));
      expect(find.bySemanticsLabel('Delete forever'), findsNWidgets(3));
      expect(find.bySemanticsLabel('More options'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('reduced motion shows everything at once', (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AtomicTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: RecycleBinPage(source: _withBin(), now: () => _now),
      ));
      await tester.pump();

      for (final opacity in tester.widgetList<FadeTransition>(find.ancestor(
          of: find.text('Trip plan'), matching: find.byType(FadeTransition)))) {
        expect(opacity.opacity.value, 1);
      }
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('without reduced motion the cards rise in', (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AtomicTheme.light,
        home: RecycleBinPage(source: _withBin(), now: () => _now),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final fades = tester
          .widgetList<FadeTransition>(find.ancestor(
              of: find.text('Trip plan'),
              matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value);
      expect(fades.any((v) => v < 1), isTrue);
      await tester.pumpAndSettle();
      final settled = tester
          .widgetList<FadeTransition>(find.ancestor(
              of: find.text('Trip plan'),
              matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value);
      expect(settled.every((v) => v == 1), isTrue);
    });
  });
}
