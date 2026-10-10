import 'dart:async';

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

class _ActivitySource extends FakeNotesSource {
  _ActivitySource() : super(notes: [syncedNote('local')]);
  int countCalls = 0;

  @override
  Future<int?> cloudCount() {
    countCalls++;
    return super.cloudCount();
  }
}

CloudNotesCubit _cubit(FakeNotesSource source) {
  final cubit = CloudNotesCubit(source: source);
  addTearDown(source.dispose);
  addTearDown(cubit.close);
  return cubit;
}

void main() {
  setUp(() => SyncStatusHelper.syncBox = _SyncBox());

  test(
    'opening during automatic sync is busy without starting another request',
    () async {
      final source = FakeNotesSource()..isSyncing = true;
      final cubit = _cubit(source);
      expect(cubit.state.working, isTrue);
      expect(await cubit.sync(uploadAll: true), isNull);
      expect(source.syncCalls, 0);
      expect(source.markAllCalls, 0);
      expect(cubit.state.lastReport, isNull);
    },
  );

  test('automatic sync activity starts and ends with source notifications', () {
    final source = FakeNotesSource();
    final cubit = _cubit(source);
    expect(cubit.state.working, isFalse);
    source.changeBehindTheScenes(() => source.isSyncing = true);
    expect(cubit.state.working, isTrue);
    source.changeBehindTheScenes(() => source.isSyncing = false);
    expect(cubit.state.working, isFalse);
    expect(source.syncCalls, 0);
    expect(source.markAllCalls, 0);
  });

  test('an idle source notification cannot release a manual request', () async {
    final source = FakeNotesSource()..syncGate = Completer<void>();
    final cubit = _cubit(source);
    final request = cubit.sync(uploadAll: false);
    source.changeBehindTheScenes(() => source.isSyncing = false);
    expect(cubit.state.working, isTrue);
    expect(await cubit.sync(uploadAll: true), isNull);
    expect(source.syncCalls, 1);
    expect(source.markAllCalls, 0);
    source.syncGate!.complete();
    expect((await request)?.text, 'Synced with the cloud');
    expect(cubit.state.working, isFalse);
  });

  test('manual completion cannot hide current source activity', () async {
    final source = FakeNotesSource()..syncGate = Completer<void>();
    final cubit = _cubit(source);
    final request = cubit.sync(uploadAll: false);
    source.changeBehindTheScenes(() => source.isSyncing = true);
    source.syncGate!.complete();
    await request;
    expect(cubit.state.working, isTrue);
    source.changeBehindTheScenes(() => source.isSyncing = false);
    expect(cubit.state.working, isFalse);
  });

  testWidgets(
    'Cloud Notes shows background activity and disables overlapping actions',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = _ActivitySource()..cloudNotes = 0;
      addTearDown(source.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CloudNotesPage(source: source),
        ),
      );
      await tester.pumpAndSettle();
      debugPrint('atomic_cloud_activity_phase:mounted');
      source.changeBehindTheScenes(() => source.isSyncing = true);
      await tester.pump();
      // Cubit delivery schedules BlocBuilder's next frame asynchronously.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      debugPrint('atomic_cloud_activity_phase:automatic_indicator');
      for (final label in ['CHECK CLOUD', 'SYNC NOW  ·', 'UPLOAD ALL  ·']) {
        final button = find.textContaining(label);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
      }
      expect(source.syncCalls, 0);
      expect(source.markAllCalls, 0);
      expect(source.countCalls, 1);
      final context = tester.element(find.byType(Scaffold).first);
      expect(context.read<CloudNotesCubit>().state.checking, isFalse);
      debugPrint('atomic_cloud_activity_phase:disabled_controls');
      source.changeBehindTheScenes(() => source.isSyncing = false);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      debugPrint('atomic_cloud_activity_phase:idle_indicator');
      final sync = find.textContaining('SYNC NOW  ·');
      await tester.ensureVisible(sync);
      await tester.tap(sync);
      await tester.pumpAndSettle();
      expect(source.syncCalls, 1);
      expect(source.markAllCalls, 0);
      debugPrint('atomic_cloud_activity_phase:retry_action');
      expect(tester.takeException(), isNull);
      expect(source.all.single.dirty, isFalse);
      debugPrint('atomic_cloud_activity_phase:complete');
    },
  );
}
