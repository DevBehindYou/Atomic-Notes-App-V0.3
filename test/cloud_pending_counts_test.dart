import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/endpage/cloud_notes_page.dart';
import 'package:atomic_notes/state/cloud_notes/cloud_notes_cubit.dart';
import 'package:atomic_notes/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'support/fake_notes_source.dart';

class _SyncBox implements Box<bool> {
  @override
  bool? get(dynamic key, {bool? defaultValue}) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SyncStatusHelper.syncBox = _SyncBox());

  for (final edited in [false, true]) {
    test('dirty deletions do not subtract from live counts (edited=$edited)',
        () {
      final source = FakeNotesSource(notes: [
        syncedNote('clean'),
        if (edited) syncedNote('edit')..dirty = true,
        syncedNote('delete-one')
          ..deleted = true
          ..dirty = true,
        syncedNote('delete-two')
          ..deleted = true
          ..dirty = true,
      ]);
      final cubit = CloudNotesCubit(source: source);
      addTearDown(cubit.close);
      addTearDown(source.dispose);
      expect(cubit.state.onDevice, edited ? 2 : 1);
      expect(cubit.state.waiting, edited ? 3 : 2);
      expect(cubit.state.synced, 1);
      expect(source.syncCalls, 0);
      expect(source.markAllCalls, 0);
      source.changeBehindTheScenes(() => source.all.last.dirty = false);
      expect(cubit.state.waiting, edited ? 2 : 1);
      expect(cubit.state.synced, 1);
    });
  }

  testWidgets('Cloud Notes identifies pending deletions and local-only counts',
      (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = FakeNotesSource(notes: [
      syncedNote('local'),
      syncedNote('delete')
        ..deleted = true
        ..dirty = true,
    ])
      ..cloudNotes = 2;
    addTearDown(source.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light, home: CloudNotesPage(source: source)));
    await tester.pumpAndSettle();
    expect(find.text('UNCHANGED 1'), findsOneWidget);
    expect(find.text('EDITED 0'), findsOneWidget);
    expect(find.text('1 deletion waiting'), findsOneWidget);
    expect(find.textContaining('including edited notes or deletions'),
        findsOneWidget);
    expect(
        find.textContaining('does not compare cloud contents'), findsOneWidget);
    expect(source.syncCalls, 0);
    expect(source.markAllCalls, 0);
    expect(source.byId('delete')?.dirty, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
