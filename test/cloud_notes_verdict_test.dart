import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/endpage/cloud_notes_page.dart';
import 'package:atomic_notes/theme/app_theme.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'support/fake_notes_source.dart';

class _SyncBox implements Box<bool> {
  bool enabled = true;
  @override
  bool? get(dynamic key, {bool? defaultValue}) => enabled;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(WidgetTester tester, FakeNotesSource source) async {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: CloudNotesPage(source: source)));
  await tester.pumpAndSettle();
}

String _verdict(WidgetTester tester) =>
    tester.widget<DataChip>(find.byType(DataChip)).label;

void main() {
  late _SyncBox syncBox;
  setUp(() {
    syncBox = _SyncBox();
    SyncStatusHelper.syncBox = syncBox;
  });
  for (final scenario in [
    (cloud: 1, label: 'Counts match'),
    (cloud: 0, label: 'Fewer in cloud'),
    (cloud: 2, label: 'More in cloud'),
  ]) {
    testWidgets('R19 cloud count ${scenario.cloud} reports only count evidence',
        (tester) async {
      final source = FakeNotesSource(notes: [syncedNote('local-only-id')])
        ..cloudNotes = scenario.cloud;
      addTearDown(source.dispose);
      await _open(tester, source);
      expect(_verdict(tester), scenario.label);
      expect(find.textContaining('This check does not compare note contents.'),
          findsOneWidget);
      expect(source.syncCalls, 0);
      expect(source.markAllCalls, 0);
      expect(source.all.single.id, 'local-only-id');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('R19 failed count does not diagnose the cause as offline',
      (tester) async {
    final source = FakeNotesSource(notes: [syncedNote('local')])
      ..cloudNotes = null;
    addTearDown(source.dispose);
    await _open(tester, source);
    expect(_verdict(tester), 'Check failed');
    expect(find.textContaining('Try Check cloud again.'), findsOneWidget);
    expect(source.syncCalls, 0);
    expect(source.all.single.id, 'local');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('sync-off control stays explicit', (tester) async {
    syncBox.enabled = false;
    final source = FakeNotesSource(notes: [syncedNote('local')])
      ..cloudNotes = 1;
    addTearDown(source.dispose);
    await _open(tester, source);
    expect(_verdict(tester), 'Sync off');
    expect(source.syncCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
