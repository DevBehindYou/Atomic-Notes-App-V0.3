import 'dart:async';

import 'package:atomic_notes/database/sync_report.dart';
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

class _Counts extends FakeNotesSource implements SyncReportSource {
  _Counts() : super(notes: [syncedNote('local')..dirty = true]);
  int lifecycle = 0;
  int session = 0;
  int countCalls = 0;
  final answers = <Future<int?>>[];

  @override
  Object get syncReportIdentity => (lifecycle, session);

  @override
  Future<int?> cloudCount() {
    countCalls++;
    return answers.removeAt(0);
  }

  @override
  Future<SyncAttemptReport> syncWithReport({bool instant = false}) async =>
      SyncAttemptReport(completed: true, activity: SyncAttemptActivity.started);

  void retire({bool sessionOnly = false, bool notify = true}) {
    if (sessionOnly) {
      session++;
    } else {
      lifecycle++;
    }
    if (notify) poke();
  }
}

CloudNotesCubit _cubit(_Counts source) {
  final cubit = CloudNotesCubit(source: source);
  addTearDown(source.dispose);
  addTearDown(cubit.close);
  return cubit;
}

Future<void> _mount(WidgetTester tester, _Counts source) async {
  tester.view.physicalSize = const Size(375, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(source.dispose);
  await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: CloudNotesPage(source: source)));
}

void main() {
  setUp(() => SyncStatusHelper.syncBox = _SyncBox());

  for (final sessionOnly in [false, true]) {
    test('retired count and timestamp clear (sessionOnly=$sessionOnly)',
        () async {
      final source = _Counts()..answers.add(Future.value(71));
      final cubit = _cubit(source);
      await cubit.check();
      await cubit.sync(uploadAll: false);
      expect(cubit.state.checkedAt, isNotNull);
      expect(cubit.state.lastReport, isNotNull);
      source.retire(sessionOnly: sessionOnly);
      expect(cubit.state.cloud, isNull);
      expect(cubit.state.checked, isFalse);
      expect(cubit.state.checking, isFalse);
      expect(cubit.state.checkedAt, isNull);
      expect(cubit.state.lastReport, isNull);
      expect(cubit.state.onDevice, 1);
      expect(cubit.state.waiting, 1);
    });
  }

  test('a retired response cannot repopulate count state', () async {
    final gate = Completer<int?>();
    final source = _Counts()..answers.add(gate.future);
    final cubit = _cubit(source);
    final check = cubit.check();
    source.retire();
    gate.complete(71);
    await check;
    expect(cubit.state.cloud, isNull);
    expect(cubit.state.checked, isFalse);
    expect(cubit.state.checkedAt, isNull);
    expect(cubit.state.checking, isFalse);
  });

  test('old completion cannot release a newer check busy state', () async {
    final old = Completer<int?>(), current = Completer<int?>();
    final source = _Counts()..answers.addAll([old.future, current.future]);
    final cubit = _cubit(source);
    final first = cubit.check();
    source.retire();
    final second = cubit.check();
    old.complete(71);
    await first;
    expect(cubit.state.checking, isTrue);
    expect(cubit.state.cloud, isNull);
    expect(cubit.state.checkedAt, isNull);
    current.complete(2);
    await second;
    expect(source.countCalls, 2);
    expect(cubit.state.cloud, 2);
    expect(cubit.state.checking, isFalse);
  });

  test('late old completion cannot overwrite the new count and timestamp',
      () async {
    final old = Completer<int?>(), current = Completer<int?>();
    final source = _Counts()..answers.addAll([old.future, current.future]);
    final cubit = _cubit(source);
    final first = cubit.check();
    source.retire();
    final second = cubit.check();
    current.complete(2);
    await second;
    final acceptedAt = cubit.state.checkedAt;
    old.complete(71);
    await first;
    expect(cubit.state.cloud, 2);
    expect(cubit.state.checkedAt, acceptedAt);
    expect(cubit.state.checked, isTrue);
    expect(cubit.state.checking, isFalse);
  });

  test('identity change before notification also retires the response',
      () async {
    final gate = Completer<int?>();
    final source = _Counts()..answers.add(gate.future);
    final cubit = _cubit(source);
    final first = cubit.check();
    source.retire(sessionOnly: true, notify: false);
    gate.complete(71);
    await first;
    expect(cubit.state.cloud, isNull);
    expect(cubit.state.checkedAt, isNull);
    expect(cubit.state.checked, isFalse);
    expect(cubit.state.checking, isFalse);
  });

  test('new check detects identity change without a listener event', () async {
    final gate = Completer<int?>();
    final source = _Counts()..answers.addAll([gate.future, Future.value(2)]);
    final cubit = _cubit(source);
    final first = cubit.check();
    source.retire(notify: false);
    await cubit.check();
    expect(source.countCalls, 2);
    expect(cubit.state.cloud, 2);
    gate.complete(71);
    await first;
    expect(cubit.state.cloud, 2);
  });

  test('unexpected count error finishes and permits a retry', () async {
    final source = _Counts()..answers.add(Future.value(71));
    final cubit = _cubit(source);
    await cubit.check();
    source.answers.add(Future<int?>.error(StateError('fixture count failure')));
    await expectLater(cubit.check(), completes);
    expect(cubit.state.checking, isFalse);
    expect(cubit.state.checked, isTrue);
    expect(cubit.state.cloud, isNull);
    source.answers.add(Future.value(2));
    await cubit.check();
    expect(source.countCalls, 3);
    expect(cubit.state.cloud, 2);
  });

  test('ordinary note change retains a valid count and receipt', () async {
    final source = _Counts()..answers.add(Future.value(2));
    final cubit = _cubit(source);
    await cubit.check();
    await cubit.sync(uploadAll: false);
    final before = cubit.state;
    source.changeBehindTheScenes(() => source.all.add(syncedNote('another')));
    expect(cubit.state.onDevice, 2);
    expect(cubit.state.cloud, 2);
    expect(cubit.state.checkedAt, before.checkedAt);
    expect(cubit.state.lastReport, same(before.lastReport));
    expect(source.countCalls, 1);
  });

  test('duplicate current-identity checks share one in-flight action',
      () async {
    final gate = Completer<int?>();
    final source = _Counts()..answers.add(gate.future);
    final cubit = _cubit(source);
    final first = cubit.check();
    await cubit.check();
    expect(source.countCalls, 1);
    expect(cubit.state.checking, isTrue);
    gate.complete(2);
    await first;
    expect(cubit.state.cloud, 2);
    expect(cubit.state.checking, isFalse);
  });

  test('null count clears the previous count without changing notes', () async {
    final source = _Counts()..answers.addAll([Future.value(2), Future.value()]);
    final cubit = _cubit(source);
    final before = source.all.map((note) => note.toMap()).toList();
    await cubit.check();
    await cubit.check();
    expect(cubit.state.cloud, isNull);
    expect(cubit.state.checked, isTrue);
    expect(cubit.state.checkedAt, isNotNull);
    expect(cubit.state.checking, isFalse);
    expect(source.all.map((note) => note.toMap()).toList(), before);
    expect(source.saveCalls, 0);
    expect(source.syncCalls, 0);
    expect(source.markAllCalls, 0);
    expect(source.deletedIds, isEmpty);
  });

  test('closing while a count is pending ignores its result', () async {
    final gate = Completer<int?>();
    final source = _Counts()..answers.add(gate.future);
    final cubit = CloudNotesCubit(source: source);
    addTearDown(source.dispose);
    final first = cubit.check();
    await cubit.close();
    gate.complete(2);
    await expectLater(first, completes);
    await expectLater(cubit.check(), completes);
    expect(source.countCalls, 1);
  });

  test('legacy source count remains read-only and retryable', () async {
    final source = FakeNotesSource(notes: [syncedNote('local')..dirty = true])
      ..cloudNotes = 2;
    final cubit = CloudNotesCubit(source: source);
    addTearDown(source.dispose);
    addTearDown(cubit.close);
    await cubit.check();
    expect(cubit.state.cloud, 2);
    source.cloudNotes = null;
    await cubit.check();
    expect(cubit.state.cloud, isNull);
    expect(cubit.state.checking, isFalse);
    expect(source.all.single.dirty, isTrue);
    expect(source.syncCalls, 0);
    expect(source.markAllCalls, 0);
  });

  testWidgets('retired count is visibly unchecked and can be checked again',
      (tester) async {
    final source = _Counts()..answers.add(Future.value(71));
    await _mount(tester, source);
    await tester.pumpAndSettle();
    expect(find.text('71'), findsOneWidget);
    source.retire();
    await tester.pumpAndSettle();
    expect(find.text('71'), findsNothing);
    expect(find.text('NOT CHECKED'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    source.answers.add(Future.value(2));
    final button = find.text('CHECK CLOUD');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(source.countCalls, 2);
    expect(source.syncCalls, 0);
  });

  testWidgets('failed count displays the existing failure verdict and retries',
      (tester) async {
    final gate = Completer<int?>();
    final source = _Counts()..answers.add(gate.future);
    await _mount(tester, source);
    await tester.pump();
    gate.completeError(StateError('fixture count failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('CHECK FAILED'), findsOneWidget);
    expect(find.textContaining('Your local notes remain on this device.'),
        findsOneWidget);
    expect(find.textContaining('fixture count failure'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    source.answers.add(Future.value(1));
    final button = find.text('CHECK CLOUD');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(source.countCalls, 2);
    expect(find.text('CHECK FAILED'), findsNothing);
    expect(source.all.single.dirty, isTrue);
  });
}
