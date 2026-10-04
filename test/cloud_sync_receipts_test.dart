import 'dart:async';

import 'package:atomic_notes/database/sync_report.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/endpage/cloud_notes_page.dart';
import 'package:atomic_notes/state/cloud_notes/cloud_notes_cubit.dart';
import 'package:atomic_notes/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'support/fake_notes_source.dart';

class _SyncBox implements Box<bool> {
  @override
  bool? get(dynamic key, {bool? defaultValue}) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reports extends FakeNotesSource implements SyncReportSource {
  _Reports(this.report) : super(notes: [syncedNote('fixture')]) {
    cloudNotes = 1;
  }
  SyncAttemptReport report;
  int reportCalls = 0;
  bool? reportInstant;
  Completer<void>? reportGate;
  Completer<void>? markGate;
  Object identity = Object();
  bool throwOnReport = false;
  bool throwOnMark = false;
  @override
  Object get syncReportIdentity => identity;
  @override
  Future<SyncAttemptReport> syncWithReport({bool instant = false}) async {
    reportCalls++;
    reportInstant = instant;
    if (throwOnReport) throw StateError('fixture failure');
    if (reportGate != null) await reportGate!.future;
    return report;
  }

  @override
  Future<int> markAllForUpload() async {
    if (throwOnMark) throw StateError('fixture marking failure');
    if (markGate != null) await markGate!.future;
    return super.markAllForUpload();
  }

  void changeSession() {
    identity = Object();
    changeBehindTheScenes(() {});
  }
}

SyncOperationReport operation(String id,
        {int? charge = 10,
        int? refund = 0,
        bool recovered = false,
        bool instant = true}) =>
    SyncOperationReport(
        requestId: id,
        instant: instant,
        recovered: recovered,
        charged: charge,
        refunded: refund);

SyncAttemptReport report(
        {bool completed = true,
        SyncAttemptActivity activity = SyncAttemptActivity.started,
        List<SyncOperationReport> operations = const [],
        String? error}) =>
    SyncAttemptReport(
        completed: completed,
        activity: activity,
        operations: operations,
        errorMessage: error);

Future<void> _mountCloud(WidgetTester tester, _Reports source,
    {double textScale = 1}) async {
  tester.view.physicalSize = const Size(375, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(source.dispose);
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: CloudNotesPage(source: source)));
  await tester.pumpAndSettle();
}

Future<void> _showReceipt(WidgetTester tester, _Reports source,
    {double textScale = 1}) async {
  await _mountCloud(tester, source, textScale: textScale);
  final context = tester.element(find.byType(Scaffold).first);
  await context.read<CloudNotesCubit>().sync(uploadAll: false);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SyncStatusHelper.syncBox = _SyncBox());

  testWidgets('confirmed instant cost is visible in Cloud Notes',
      (tester) async {
    final source = _Reports(report(operations: [operation('a')]));
    await _showReceipt(tester, source);
    expect(find.text('NET UPLOAD COST'), findsOneWidget);
    expect(find.text('10 energy'), findsNWidgets(2));
    expect(source.reportCalls, 1);
    expect(source.reportInstant, isTrue);
    expect(source.syncCalls, 0);
  });

  for (final uploadAll in [false, true]) {
    testWidgets(
        'the visible sync action displays its own receipt (uploadAll=$uploadAll)',
        (tester) async {
      final source = _Reports(report(operations: [operation('a')]))
        ..cloudNotes = 0;
      await _mountCloud(tester, source);
      final button =
          find.textContaining(uploadAll ? 'UPLOAD ALL  ·' : 'SYNC NOW  ·');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('NET UPLOAD COST'), findsOneWidget);
      expect(source.reportCalls, 1);
      expect(source.reportInstant, isTrue);
      expect(source.markAllCalls, uploadAll ? 1 : 0);
      expect(source.syncCalls, 0);
    });
  }

  testWidgets('multiple batches show confirmed refund and incomplete sync',
      (tester) async {
    final source = _Reports(report(
        completed: false,
        error: 'Pull unavailable',
        operations: [operation('a'), operation('b', refund: 10)]));
    await _showReceipt(tester, source);
    expect(find.text('Sync incomplete'), findsOneWidget);
    expect(find.text('Pull unavailable'), findsOneWidget);
    expect(find.text('20 energy'), findsOneWidget);
    expect(find.text('10 energy'), findsNWidgets(2));
    expect(find.text('2 upload batches'), findsOneWidget);
  });

  testWidgets(
      'recovered standard receipt is historical rather than new instant charge',
      (tester) async {
    final source = _Reports(report(operations: [
      operation('old', charge: 5, recovered: true, instant: false)
    ]));
    await _showReceipt(tester, source);
    expect(find.text('5 energy'), findsNWidgets(2));
    expect(
        find.textContaining('may already have been applied'), findsOneWidget);
    expect(find.text('10 energy'), findsNothing);
    expect(find.text('fixture'), findsNothing);
    expect(find.text('old'), findsNothing);
  });

  testWidgets('missing receipt stays unknown, never zero or free',
      (tester) async {
    await _showReceipt(
        tester,
        _Reports(
            report(operations: [operation('a', charge: null, refund: null)])));
    expect(find.text('Upload energy totals unavailable.'), findsOneWidget);
    expect(find.text('0 energy'), findsNothing);
    expect(find.textContaining('No upload energy was charged'), findsNothing);
  });

  testWidgets('partial receipts label only confirmed totals', (tester) async {
    await _showReceipt(
        tester,
        _Reports(report(
            completed: false,
            error: 'Connection lost',
            operations: [
              operation('a'),
              operation('b', charge: null, refund: null)
            ])));
    expect(find.text('1 of 2 upload batches confirmed'), findsOneWidget);
    expect(find.text('Confirmed totals only'), findsOneWidget);
    expect(find.text('NET UPLOAD COST'), findsNothing);
    expect(find.text('10 energy'), findsNWidgets(2));
  });

  testWidgets('receive-only cost is distinct from an offline attempt',
      (tester) async {
    await _showReceipt(tester, _Reports(report()));
    expect(find.text('No upload was sent. No upload energy was charged.'),
        findsOneWidget);
  });

  testWidgets('offline attempt does not claim zero charge', (tester) async {
    await _showReceipt(
        tester,
        _Reports(report(
            completed: false,
            activity: SyncAttemptActivity.notStarted,
            error: 'Offline')));
    expect(find.text('Sync did not start'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Upload energy totals unavailable.'), findsOneWidget);
    expect(find.text('0 energy'), findsNothing);
  });

  for (final activity in [
    SyncAttemptActivity.joined,
    SyncAttemptActivity.retired
  ]) {
    test('no receipt/message is borrowed for $activity', () async {
      final source = _Reports(report(activity: activity));
      final cubit = CloudNotesCubit(source: source);
      addTearDown(cubit.close);
      addTearDown(source.dispose);
      expect(await cubit.sync(uploadAll: false), isNull);
      expect(source.reportCalls, 1);
      expect(cubit.state.working, isFalse);
    });
  }

  test('session change during upload-all marking prevents sync in new session',
      () async {
    final source = _Reports(report(operations: [operation('a')]))
      ..markGate = Completer<void>();
    final cubit = CloudNotesCubit(source: source);
    addTearDown(cubit.close);
    addTearDown(source.dispose);
    final syncing = cubit.sync(uploadAll: true);
    source.changeSession();
    source.markGate!.complete();
    expect(await syncing, isNull);
    expect(source.reportCalls, 0);
    expect(source.syncCalls, 0);
    expect(cubit.state.working, isFalse);
  });

  test('a receipt arriving after session change is suppressed', () async {
    final source = _Reports(report(operations: [operation('a')]))
      ..reportGate = Completer<void>();
    final cubit = CloudNotesCubit(source: source);
    addTearDown(cubit.close);
    addTearDown(source.dispose);
    final syncing = cubit.sync(uploadAll: false);
    source.changeSession();
    source.reportGate!.complete();
    expect(await syncing, isNull);
    expect(source.reportCalls, 1);
    expect(cubit.state.working, isFalse);
  });

  testWidgets('a later account/session change removes the displayed receipt',
      (tester) async {
    final source = _Reports(report(operations: [operation('a')]));
    await _showReceipt(tester, source);
    expect(find.text('NET UPLOAD COST'), findsOneWidget);
    source.changeSession();
    await tester.pumpAndSettle();
    expect(find.text('NET UPLOAD COST'), findsNothing);
  });

  testWidgets('large-text receipt remains readable without layout exceptions',
      (tester) async {
    await _showReceipt(
        tester,
        _Reports(report(
            operations: [operation('a')],
            completed: false,
            error:
                'The pull could not finish. Your changes remain on this device.')),
        textScale: 2);
    await tester.ensureVisible(find.text('NET UPLOAD COST'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('10 energy'), findsNWidgets(2));
  });

  for (final marking in [false, true]) {
    test(
        'unexpected action failure resets working without inventing totals (marking=$marking)',
        () async {
      final source = _Reports(report(operations: [operation('a')]))
        ..throwOnReport = !marking
        ..throwOnMark = marking;
      final cubit = CloudNotesCubit(source: source);
      addTearDown(cubit.close);
      addTearDown(source.dispose);
      expect((await cubit.sync(uploadAll: marking))?.text,
          'Sync could not finish. Your notes remain on this device.');
      expect(cubit.state.working, isFalse);
      expect(cubit.state.lastReport, isNull);
      expect(source.syncCalls, 0);
    });
  }

  test('closing the page suppresses the late receipt and message', () async {
    final source = _Reports(report(operations: [operation('a')]))
      ..reportGate = Completer<void>();
    final cubit = CloudNotesCubit(source: source);
    addTearDown(source.dispose);
    final syncing = cubit.sync(uploadAll: false);
    await cubit.close();
    source.reportGate!.complete();
    expect(await syncing, isNull);
  });

  test('legacy source still uses existing completion message', () async {
    final source = FakeNotesSource();
    final cubit = CloudNotesCubit(source: source);
    addTearDown(cubit.close);
    addTearDown(source.dispose);
    expect((await cubit.sync(uploadAll: false))?.text, 'Synced with the cloud');
    expect(source.syncCalls, 1);
  });
}
