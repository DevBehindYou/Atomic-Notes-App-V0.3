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

/// A deleted note. By default it was uploaded (version 4) and has nothing
/// left to send.
Note _binned(String id,
    {String title = '',
    String body = '',
    NoteKind kind = NoteKind.text,
    List<TodoItem>? items,
    int serverVersion = 4,
    bool dirty = false,
    required DateTime deletedAt}) {
  final n = syncedNote(id, title: title, body: body, kind: kind, items: items)
    ..deleted = true
    ..serverVersion = serverVersion
    ..dirty = dirty;
  n.updatedAt = deletedAt;
  return n;
}

/// Version 0 and nothing waiting to sync: never uploaded, or reset by a
/// cloud wipe. The page cannot tell which, so it claims neither.
Note _localOnly(String id, {String title = '', required DateTime deletedAt}) =>
    _binned(id, title: title, serverVersion: 0, deletedAt: deletedAt);

/// Uploaded before, with a change (its deletion) still waiting to sync.
Note _pending(String id, {String title = '', required DateTime deletedAt}) =>
    _binned(id, title: title, dirty: true, deletedAt: deletedAt);

/// One note of each kind, newest deletion first: pending, local-only, synced.
FakeNotesSource _mixed() => FakeNotesSource(notes: [
      syncedNote('live', title: 'Still here'),
      _binned('synced', title: 'Old receipt', deletedAt: DateTime(2026, 11, 1)),
      _localOnly('local',
          title: 'Only on this device', deletedAt: DateTime(2026, 11, 5)),
      _pending('pending',
          title: 'Unsent delete', deletedAt: DateTime(2026, 11, 9)),
    ]);

const String _removeNowBody = 'It is removed from this device now and '
    'cannot be brought back from the Recycle Bin. It has no changes waiting to '
    'sync, so this sends nothing to the cloud.';
const String _syncFirstBody = 'It has changes that have not finished '
    'syncing. They sync first, and only then is the note removed from this '
    'device. Without Cloud Sync, or if the sync fails, it stays in the Recycle '
    'Bin.';
const String _changed = 'The Recycle Bin changed before this could finish. '
    'Nothing was deleted for good. Check it and try again.';

Finder _dialogDelete() => find.descendant(
    of: find.byType(AtomicDialog<bool>), matching: find.text('Delete forever'));

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
      expect(find.text(_removeNowBody), findsOneWidget);
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

  group('what removal does', () {
    test('each note says what removing it does, from its sync flag only', () {
      final at = DateTime(2026, 11, 1);
      // Version 0 is no proof of anything: both clean notes are removed now.
      expect(RecycleBinPage.removalStep(_localOnly('a', deletedAt: at)),
          BinRemovalStep.removeNow);
      expect(RecycleBinPage.removalStep(_binned('b', deletedAt: at)),
          BinRemovalStep.removeNow);
      expect(RecycleBinPage.removalStep(_pending('c', deletedAt: at)),
          BinRemovalStep.syncFirst);
      // A waiting change syncs first, whatever its version.
      expect(
          RecycleBinPage.removalStep(
              _binned('d', serverVersion: 0, dirty: true, deletedAt: at)),
          BinRemovalStep.syncFirst);
      // No body claims a past the page cannot prove.
      for (final note in [
        _localOnly('e', deletedAt: at),
        _binned('f', deletedAt: at),
        _pending('g', deletedAt: at),
        _binned('h', serverVersion: 0, dirty: true, deletedAt: at),
      ]) {
        final body = RecycleBinPage.deleteForeverBody(note);
        expect(body, isNot(contains('never synced')));
        expect(body, isNot(contains('no cloud copy')));
        expect(body, isNot(contains('Drive')));
        expect(body, isNot(contains('already synced')));
      }
    });

    test('Empty bin counts each kind and words plurals', () {
      final at = DateTime(2026, 11, 1);
      final notes = [
        _localOnly('l1', deletedAt: at),
        _localOnly('l2', deletedAt: at),
        _binned('s1', deletedAt: at),
        _binned('s2', deletedAt: at),
        _pending('p1', deletedAt: at),
        _pending('p2', deletedAt: at),
      ];
      expect(RecycleBinPage.emptyBinConsequences(notes), [
        '6 deleted notes are removed from this device for good.',
        '4 have no changes waiting to sync, so nothing is sent for them.',
      ]);
      expect(
          RecycleBinPage.emptyBinWarning(notes),
          '2 notes have changes that have not finished syncing. They sync '
          'first. Without Cloud Sync, or if the sync fails, nothing is deleted '
          'for good.');

      // Only clean notes: nothing about Drive, and no warning.
      final local = [_localOnly('l1', deletedAt: at)];
      expect(RecycleBinPage.emptyBinConsequences(local), [
        '1 deleted note is removed from this device for good.',
        '1 has no changes waiting to sync, so nothing is sent for it.',
      ]);
      expect(RecycleBinPage.emptyBinWarning(local), isNull);
      expect(
          RecycleBinPage.emptyBinWarning([_pending('p', deletedAt: at)]),
          '1 note has changes that have not finished syncing. They sync '
          'first. Without Cloud Sync, or if the sync fails, nothing is deleted '
          'for good.');
      // Only notes to sync: no "nothing is sent" line.
      expect(
          RecycleBinPage.emptyBinConsequences([_pending('p', deletedAt: at)]),
          ['1 deleted note is removed from this device for good.']);
    });

    testWidgets('the explanation says what removal does, and claims no past',
        (tester) async {
      await _pump(tester, _mixed());

      expect(
          find.text('Deleted notes wait here. Restore one to put it back, or '
              'delete it for good to remove it from this device. A note with '
              'changes still waiting to sync is synced first, and stays here '
              'if that sync cannot finish. Deleting here does not promise to '
              'remove every copy kept elsewhere.'),
          findsOneWidget);
      expect(find.textContaining('cloud copies sit in'), findsNothing);
      expect(find.textContaining('never synced'), findsNothing);
      expect(find.textContaining('Drive'), findsNothing);
    });

    testWidgets('a local-only note is removed locally, with no Drive promise',
        (tester) async {
      final source = _mixed();
      await _pump(tester, source);

      await tester.tap(_button('local', 'Delete forever'));
      await tester.pumpAndSettle();
      expect(
          find.text('Delete "Only on this device" for good?'), findsOneWidget);
      expect(find.text(_removeNowBody), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AtomicDialog<bool>),
              matching: find.textContaining('Drive')),
          findsNothing);

      await tester.tap(_dialogDelete());
      await tester.pumpAndSettle();
      expect(source.byId('local'), isNull);
      expect(source.byId('pending'), isNotNull);
      expect(source.byId('synced'), isNotNull);
      expect(find.text('Deleted for good'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a pending deletion says it must sync first, and stays if not',
        (tester) async {
      final source = _mixed()..deleteForeverWorks = false;
      await _pump(tester, source);

      await tester.tap(_button('pending', 'Delete forever'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Unsent delete" for good?'), findsOneWidget);
      expect(find.text(_syncFirstBody), findsOneWidget);

      await tester.tap(_dialogDelete());
      await tester.pumpAndSettle();
      expect(source.byId('pending'), isNotNull);
      expect(find.text('Unsent delete'), findsOneWidget);
      expect(
          find.text('Could not delete yet. Turn on Cloud Sync and sync first.'),
          findsOneWidget);
      await _settleSnackBar(tester);

      // With an automatic sync coming, the store's answer says when.
      source.nextAutoSyncAt = DateTime.now().add(const Duration(minutes: 5));
      await tester.tap(_button('pending', 'Delete forever'));
      await tester.pumpAndSettle();
      await tester.tap(_dialogDelete());
      await tester.pumpAndSettle();
      expect(source.byId('pending'), isNotNull);
      expect(
          find.textContaining('This deletion has not reached the cloud yet.'),
          findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a pending deletion that syncs is then removed',
        (tester) async {
      final source = _mixed();
      await _pump(tester, source);

      await tester.tap(_button('pending', 'Delete forever'));
      await tester.pumpAndSettle();
      await tester.tap(_dialogDelete());
      await tester.pumpAndSettle();
      expect(source.byId('pending'), isNull);
      expect(find.text('Deleted for good'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('Cancel keeps a pending deletion', (tester) async {
      final source = _mixed();
      await _pump(tester, source);

      await tester.tap(_button('pending', 'Delete forever'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(source.byId('pending'), isNotNull);
      expect(source.binNotes, hasLength(3));
    });

    testWidgets('Empty bin on a mixed bin says what happens to each kind',
        (tester) async {
      final source = _mixed()..deleteForeverWorks = false;
      await _pump(tester, source);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty bin'));
      await tester.pumpAndSettle();

      expect(find.byType(SlideToConfirm), findsOneWidget);
      expect(
          find.text('3 deleted notes are removed from this device for good.'),
          findsOneWidget);
      expect(
          find.text(
              '2 have no changes waiting to sync, so nothing is sent for them.'),
          findsOneWidget);
      expect(find.text('NOT UPLOADED'), findsOneWidget);
      expect(
          find.text('1 note has changes that have not finished syncing. They '
              'sync first. Without Cloud Sync, or if the sync fails, nothing '
              'is deleted for good.'),
          findsOneWidget);
      expect(find.textContaining('never synced'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(Dialog), matching: find.textContaining('Drive')),
          findsNothing);
      expect(find.textContaining('Their cloud copies'), findsNothing);

      // The pending deletion cannot sync: nothing is removed.
      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(source.binNotes, hasLength(3));
      expect(
          find.text('Could not delete yet. Turn on Cloud Sync and sync first.'),
          findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('Cancel on Empty bin removes nothing', (tester) async {
      final source = _mixed();
      await _pump(tester, source);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty bin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(find.byType(SlideToConfirm), findsNothing);
      expect(source.binNotes, hasLength(3));
      expect(find.text('Recycle Bin emptied'), findsNothing);
    });

    testWidgets('a bin of local-only notes empties with no Drive promise',
        (tester) async {
      final source = FakeNotesSource(notes: [
        _localOnly('a', title: 'Draft A', deletedAt: DateTime(2026, 11, 2)),
        _localOnly('b', title: 'Draft B', deletedAt: DateTime(2026, 11, 3)),
      ]);
      await _pump(tester, source);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty bin'));
      await tester.pumpAndSettle();
      expect(
          find.text('2 deleted notes are removed from this device for good.'),
          findsOneWidget);
      expect(
          find.text(
              '2 have no changes waiting to sync, so nothing is sent for them.'),
          findsOneWidget);
      expect(find.text('NOT UPLOADED'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(Dialog), matching: find.textContaining('Drive')),
          findsNothing);

      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(source.binNotes, isEmpty);
      expect(find.text('Recycle Bin emptied'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a local-only note restores, and is refused at the limit',
        (tester) async {
      final source = _mixed();
      await _pump(tester, source);

      source.limit = 1; // the live note fills it
      await tester.tap(_button('local', 'Restore'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Note limit reached (1). Delete a note to make room.'),
          findsOneWidget);
      expect(source.byId('local')!.deleted, isTrue);
      await _settleSnackBar(tester);

      source.limit = 30;
      await tester.tap(_button('local', 'Restore'));
      // The refusal's message makes way for the next one.
      await tester.pumpAndSettle();
      expect(find.text('Note restored'), findsOneWidget);
      expect(source.byId('local')!.deleted, isFalse);
      expect(find.text('Only on this device'), findsNothing);
      await _settleSnackBar(tester);
    });

    testWidgets('the cloud-copy dialogs fit 320 dp at 2.0 text',
        (tester) async {
      await _pump(tester, _mixed(), width: 320, height: 640, textScale: 2);

      // The long explanation pushes the first card below the fold.
      await tester.scrollUntilVisible(_button('pending', 'Delete forever'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(_button('pending', 'Delete forever'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty bin'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('NOT UPLOADED'), findsOneWidget);
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

  // Each confirmation covers exactly the notes it showed, only while they are
  // as it showed them (Codex R33).
  group('confirmed scope', () {
    Future<void> openEmptyBin(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty bin'));
      await tester.pumpAndSettle();
    }

    Future<void> slide(WidgetTester tester) async {
      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();
    }

    testWidgets('a note deleted while the slide is open is not removed',
        (tester) async {
      final source = _mixed();
      await _pump(tester, source);
      await openEmptyBin(tester);
      expect(
          find.text('3 deleted notes are removed from this device for good.'),
          findsOneWidget);

      // Another device's deletion arrives: one clean, one still to sync.
      source.changeBehindTheScenes(() {
        source.all
            .add(_binned('late', title: 'Arrived later', deletedAt: _now));
        source.all
            .add(_pending('late2', title: 'Arrived too', deletedAt: _now));
      });
      await tester.pumpAndSettle();
      await slide(tester);

      expect(source.byId('synced'), isNull);
      expect(source.byId('local'), isNull);
      expect(source.byId('pending'), isNull);
      expect(source.byId('late')!.deleted, isTrue);
      expect(source.byId('late2')!.deleted, isTrue);
      expect(source.byId('live'), isNotNull);
      expect(find.byType(SlideToConfirm), findsNothing);
      expect(
          find.text('3 notes deleted for good. Notes deleted after you '
              'confirmed are still in the Recycle Bin.'),
          findsOneWidget);
      // The newer notes stay on screen, and can still be acted on.
      expect(find.text('Arrived later'), findsOneWidget);
      expect(find.text('Arrived too'), findsOneWidget);
      expect(find.byTooltip('More options'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a confirmed note that now must sync stops Empty bin',
        (tester) async {
      final source = _mixed();
      await _pump(tester, source);
      await openEmptyBin(tester);

      source.changeBehindTheScenes(() => source.byId('local')!.dirty = true);
      await slide(tester);

      expect(source.binNotes, hasLength(3));
      expect(source.syncCalls, 0);
      expect(find.byType(SlideToConfirm), findsNothing);
      expect(find.text(_changed), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a confirmed note restored while the slide is open is kept',
        (tester) async {
      final source = _mixed();
      await _pump(tester, source);
      await openEmptyBin(tester);

      await source.restoreNote('synced');
      await tester.pumpAndSettle();
      await slide(tester);

      expect(source.byId('synced')!.deleted, isFalse);
      expect(source.binNotes, hasLength(2));
      expect(find.text(_changed), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a confirmed note that disappears stops Empty bin',
        (tester) async {
      final source = _mixed();
      await _pump(tester, source);
      await openEmptyBin(tester);

      await source.deleteForever(['local']);
      await tester.pumpAndSettle();
      await slide(tester);

      expect(source.byId('synced'), isNotNull);
      expect(source.byId('pending'), isNotNull);
      expect(find.text(_changed), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('Cancel after the bin changed removes nothing', (tester) async {
      final source = _mixed();
      await _pump(tester, source);
      await openEmptyBin(tester);

      source.changeBehindTheScenes(() =>
          source.all.add(_binned('late', title: 'Arrived', deletedAt: _now)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(source.binNotes, hasLength(4));
      expect(source.syncCalls, 0);
    });

    testWidgets('a mixed bin syncs once, then everything confirmed goes',
        (tester) async {
      final source = _mixed();
      await _pump(tester, source);
      await openEmptyBin(tester);
      await slide(tester);

      expect(source.syncCalls, 1);
      expect(source.binNotes, isEmpty);
      expect(source.byId('live'), isNotNull);
      expect(find.text('Recycle Bin emptied'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a failed sync on Empty bin deletes nothing', (tester) async {
      final source = _mixed()..syncResult = false;
      await _pump(tester, source);
      await openEmptyBin(tester);
      await slide(tester);

      expect(source.syncCalls, 1);
      expect(source.binNotes, hasLength(3));
      expect(
          find.text('Could not delete yet. Turn on Cloud Sync and sync first.'),
          findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a note that now must sync stops its own Delete forever',
        (tester) async {
      final source = _mixed();
      await _pump(tester, source);

      await tester.tap(_button('local', 'Delete forever'));
      await tester.pumpAndSettle();
      expect(find.text(_removeNowBody), findsOneWidget);
      source.changeBehindTheScenes(() => source.byId('local')!.dirty = true);
      await tester.tap(_dialogDelete());
      await tester.pumpAndSettle();

      expect(source.byId('local'), isNotNull);
      expect(source.syncCalls, 0);
      expect(find.text(_changed), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a note restored while its dialog is open is kept',
        (tester) async {
      final source = _mixed();
      await _pump(tester, source);

      await tester.tap(_button('local', 'Delete forever'));
      await tester.pumpAndSettle();
      await source.restoreNote('local');
      await tester.tap(_dialogDelete());
      await tester.pumpAndSettle();

      expect(source.byId('local')!.deleted, isFalse);
      expect(find.text(_changed), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a single delete removes that note only', (tester) async {
      final source = _mixed();
      await _pump(tester, source);

      await tester.tap(_button('local', 'Delete forever'));
      await tester.pumpAndSettle();
      source.changeBehindTheScenes(() =>
          source.all.add(_binned('late', title: 'Arrived', deletedAt: _now)));
      await tester.tap(_dialogDelete());
      await tester.pumpAndSettle();

      expect(source.byId('local'), isNull);
      expect(source.binNotes.map((n) => n.id).toSet(),
          {'synced', 'pending', 'late'});
      expect(find.text('Deleted for good'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a single delete that waits for its sync runs once',
        (tester) async {
      final source = _mixed()..syncGate = Completer<void>();
      await _pump(tester, source);

      await tester.tap(_button('pending', 'Delete forever'));
      await tester.pumpAndSettle();
      expect(find.text(_syncFirstBody), findsOneWidget);
      await tester.tap(_dialogDelete());
      // The busy spinner keeps animating, so step time instead of settling.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(source.syncCalls, 1);
      final button = _button('pending', 'Delete forever');
      expect(tester.widget<AtomicButton>(button).busy, isTrue);
      expect(
          tester.widget<AtomicButton>(_button('pending', 'Restore')).onPressed,
          isNull);

      // A second tap opens nothing and starts nothing.
      await tester.tap(button, warnIfMissed: false);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(source.syncCalls, 1);

      source.syncGate!.complete();
      await tester.pumpAndSettle();
      expect(source.byId('pending'), isNull);
      expect(source.syncCalls, 1);
      expect(find.text('Deleted for good'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a failed sync keeps the note and frees its buttons',
        (tester) async {
      final source = _mixed()..syncResult = false;
      await _pump(tester, source);

      await tester.tap(_button('pending', 'Delete forever'));
      await tester.pumpAndSettle();
      await tester.tap(_dialogDelete());
      await tester.pumpAndSettle();

      expect(source.byId('pending')!.dirty, isTrue);
      expect(
          find.text('Could not delete yet. Turn on Cloud Sync and sync first.'),
          findsOneWidget);
      final button =
          tester.widget<AtomicButton>(_button('pending', 'Delete forever'));
      expect(button.busy, isFalse);
      expect(button.onPressed, isNotNull);
      await _settleSnackBar(tester);
    });
  });
}
