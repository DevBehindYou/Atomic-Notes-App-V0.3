import 'dart:async';

import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_report.dart';
import 'package:atomic_notes/page/endpage/danger_zone_page.dart';
import 'package:atomic_notes/ui/motion/slide_to_confirm.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notes_source.dart';

const _local = 'Remove local notes';
const _cloud = 'Remove cloud notes';
const _review = 'Review removal';
const _localSuccess =
    'Local notes removed. Existing cloud copies, your account and settings were kept.';
const _cloudSuccess = 'Cloud-note records removed. Device notes were kept.';
const _cloudUnconfirmed =
    'Cloud removal wasn’t confirmed. Some files may already have moved to '
    'Drive trash. Device notes were kept. Check your connection and retry the same action.';

class _Source extends FakeNotesSource implements SyncReportSource {
  _Source({super.notes});

  int session = 0;
  int localCalls = 0;
  int cloudCalls = 0;
  Completer<int>? localGate;
  Completer<WipeOutcome>? cloudGate;

  @override
  Object get syncReportIdentity => session;

  @override
  Future<SyncAttemptReport> syncWithReport({bool instant = false}) =>
      throw UnimplementedError();

  @override
  Future<int> wipeLocalNotes() {
    localCalls++;
    return localGate?.future ?? super.wipeLocalNotes();
  }

  @override
  Future<WipeOutcome> wipeRemote() {
    cloudCalls++;
    return cloudGate?.future ?? super.wipeRemote();
  }
}

Future<void> _open(WidgetTester tester, _Source source, String label) async {
  tester.view.physicalSize = const Size(360, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: DangerZonePage(source: source)));
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Finder _dialogText(String label) => find.descendant(
    of: find.byType(AtomicDialog<void>), matching: find.text(label));

void main() {
  testWidgets('review and removal are separate accessible actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final source = _Source(notes: [syncedNote('bin')..deleted = true]);
    await _open(tester, source, _local);

    expect(_dialogText(_local), findsNothing);
    tester.semantics.tap(find.semantics.byLabel(_review));
    await tester.pumpAndSettle();
    expect(source.localCalls, 0);
    expect(find.textContaining('This removes notes stored in this app'),
        findsOneWidget);

    final confirm = _dialogText(_local);
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(confirm),
        isSemantics(isButton: true, hasTapAction: true));
    tester.semantics.tap(find.semantics.byLabel(_local));
    await tester.pumpAndSettle();
    expect(source.localCalls, 1);
    expect(source.binNotes, isEmpty);
    expect(find.text(_localSuccess), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('pending edits and deletions are described as unsynced changes',
      (tester) async {
    final source = _Source(notes: [
      syncedNote('edited')..touch(),
      syncedNote('deleted')
        ..deleted = true
        ..touch(),
    ]);
    await _open(tester, source, _local);

    expect(
      find.text(
        '2 note changes haven’t finished syncing. Removing local notes can '
        'lose unsynced content and discard pending deletions. Sync first if '
        'you want to keep those changes.',
      ),
      findsOneWidget,
    );
    expect(
        find.text('Notes or changes that have no other copy cannot be '
            'recovered after removal.'),
        findsOneWidget);
    final cancel = find.text('Cancel');
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(source.localCalls, 0);
    expect(find.byType(SlideToConfirm), findsNothing);
  });

  testWidgets('slide and accessible confirmation admit one cloud request',
      (tester) async {
    final source = _Source(notes: [syncedNote('device')])
      ..cloudGate = Completer<WipeOutcome>();
    await _open(tester, source, _cloud);
    await tester.tap(find.text(_review));
    await tester.pumpAndSettle();
    final confirm = _dialogText(_cloud);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.drag(
        find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
    await tester.pump();

    expect(source.cloudCalls, 1);
    expect(source.localCalls, 0);
    expect(source.count, 1);
    source.cloudGate!.complete(const WipeOutcome(true, 'raw service result'));
    await tester.pumpAndSettle();
    expect(find.text(_cloudSuccess), findsOneWidget);
  });

  testWidgets('an account change invalidates a previously opened local slide',
      (tester) async {
    final source = _Source();
    await _open(tester, source, _local);
    source.session++;

    final thumb = find.byKey(SlideToConfirm.thumbKey);
    await tester.ensureVisible(thumb);
    await tester.drag(thumb, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(source.localCalls, 0);
    expect(find.textContaining('session changed'), findsOneWidget);
  });

  testWidgets('an account change after review invalidates cloud confirmation',
      (tester) async {
    final source = _Source();
    await _open(tester, source, _cloud);
    await tester.tap(find.text(_review));
    await tester.pumpAndSettle();
    source.session++;

    final confirm = _dialogText(_cloud);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(source.cloudCalls, 0);
    expect(find.textContaining('session changed'), findsOneWidget);
  });

  testWidgets('an old cloud result is retired after a session change',
      (tester) async {
    final source = _Source()..cloudGate = Completer<WipeOutcome>();
    await _open(tester, source, _cloud);
    final thumb = find.byKey(SlideToConfirm.thumbKey);
    await tester.ensureVisible(thumb);
    await tester.drag(thumb, const Offset(600, 0));
    await tester.pump();
    expect(source.cloudCalls, 1);

    source.session++;
    source.cloudGate!.complete(const WipeOutcome(true, 'raw service result'));
    await tester.pumpAndSettle();
    expect(find.text(_cloudSuccess), findsNothing);
    expect(find.text('raw service result'), findsNothing);
    expect(find.byType(SlideToConfirm), findsNothing);
  });

  for (final throws in [false, true]) {
    testWidgets('cloud removal remains unconfirmed when throws = $throws',
        (tester) async {
      final source = _Source()..cloudGate = Completer<WipeOutcome>();
      await _open(tester, source, _cloud);
      final thumb = find.byKey(SlideToConfirm.thumbKey);
      await tester.ensureVisible(thumb);
      await tester.drag(thumb, const Offset(600, 0));
      await tester.pump();
      if (throws) {
        source.cloudGate!.completeError(TimeoutException('provider timeout'));
      } else {
        source.cloudGate!.complete(const WipeOutcome(false, 'raw error'));
      }
      await tester.pumpAndSettle();

      expect(find.text(_cloudUnconfirmed), findsOneWidget);
      expect(find.text(_cloudSuccess), findsNothing);
    });
  }

  testWidgets('a changed pending warning must be reviewed before local removal',
      (tester) async {
    final note = syncedNote('device');
    final source = _Source(notes: [note]);
    await _open(tester, source, _local);
    source.changeBehindTheScenes(note.touch);
    final thumb = find.byKey(SlideToConfirm.thumbKey);
    await tester.ensureVisible(thumb);
    await tester.pumpAndSettle();

    await tester.drag(thumb, const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(source.localCalls, 0);
    expect(find.textContaining('Review the removal again'), findsOneWidget);
  });

  testWidgets('a local exception reports that removal was unconfirmed',
      (tester) async {
    final source = _Source()..localGate = Completer<int>();
    await _open(tester, source, _local);
    final thumb = find.byKey(SlideToConfirm.thumbKey);
    await tester.ensureVisible(thumb);
    await tester.pumpAndSettle();
    await tester.drag(thumb, const Offset(600, 0));
    await tester.pump();

    source.localGate!.completeError(StateError('unconfirmed storage write'));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Local removal wasn’t confirmed'), findsOneWidget);
    expect(find.text(_localSuccess), findsNothing);
  });
}
