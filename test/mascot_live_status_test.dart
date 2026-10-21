import 'dart:io';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'notes_repository_lifecycle_test.dart' show TestApi, TestVault;
import 'support/fake_notes_source.dart';

Future<void> _open(
  WidgetTester tester,
  NotesSource source,
  String code, {
  bool ownsSource = true,
}) async {
  tester.view.physicalSize = const Size(1290, 2700);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final bloc = NotesBloc(
    source: source,
    isSyncEnabled: () => true,
    isOnline: () async => true,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await bloc.close();
    if (ownsSource) {
      (source as FakeNotesSource).dispose();
      debugPrint('atomic_mascot_cleanup:$code');
    }
  });
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<NotesBloc>.value(value: bloc, child: const HomePage()),
    ),
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('mascot-character')));
  await tester.pump();
}

Future<void> _deliver(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('idle local notes do not claim cloud equality', (tester) async {
    final source = FakeNotesSource(notes: [syncedNote('local')])
      ..cloudNotes = 0;
    await _open(tester, source, 'idle_local');
    await _tap(tester);
    expect(find.text('No local changes waiting.'), findsOneWidget);
    expect(find.textContaining('All notes synced'), findsNothing);
    expect(source.count, 1);
    expect(source.pendingCount, 0);
    expect(source.cloudNotes, 0);
    expect(source.syncCalls, 0);
  });

  testWidgets('cloud wipe retains local notes without a synced verdict', (
    tester,
  ) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('atomic-mascot-wipe-'),
    );
    final ownedDirectory = directory!;
    final api = TestApi();
    final vault = TestVault();
    NotesRepository? ownedRepository;
    addTearDown(() async {
      await tester.runAsync(() async {
        await ownedRepository?.stop(waitForSync: true);
        ownedRepository?.dispose();
        await Hive.close();
        final resolved = ownedDirectory.absolute.path;
        final tempRoot = Directory.systemTemp.absolute.path;
        if (!resolved.startsWith('$tempRoot${Platform.pathSeparator}') ||
            !ownedDirectory.uri.pathSegments
                .where((part) => part.isNotEmpty)
                .last
                .startsWith('atomic-mascot-wipe-')) {
          throw StateError('disposable_cleanup_refused');
        }
        await ownedDirectory.delete(recursive: true);
        expect(await ownedDirectory.exists(), isFalse);
      });
      debugPrint('atomic_mascot_cleanup:post_wipe');
    });
    late Note note;
    await tester.runAsync(() async {
      Hive.init(ownedDirectory.path);
      final box = await Hive.openBox('mascot-isolated-notes');
      SyncStatusHelper.syncBox = await Hive.openBox<bool>(
        'mascot-isolated-sync',
      );
      final repository = NotesRepository.forTest(
        box: box,
        api: api,
        vault: vault,
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
      ownedRepository = repository;
      await repository.start();
      note = Note.create()..title = 'Public synthetic retained note';
      await repository.save(note);
      expect(await repository.syncNow(instant: true), isTrue);
    });
    final repository = ownedRepository!;
    await _open(tester, repository, 'post_wipe', ownsSource: false);
    final wiped = await tester.runAsync(repository.wipeRemote);
    expect(wiped!.ok, isTrue);
    await _deliver(tester);
    expect(repository.byId(note.id)!.title, 'Public synthetic retained note');
    expect(repository.byId(note.id)!.serverVersion, 0);
    expect(repository.byId(note.id)!.syncedSig, isEmpty);
    expect(repository.pendingCount, 0);
    expect(repository.lastSyncedAt, isNull);
    expect(api.wipeCalls, 1);
    await _tap(tester);
    expect(find.text('No local changes waiting.'), findsOneWidget);
    expect(find.textContaining('All notes synced'), findsNothing);
  });

  testWidgets('an open bubble follows activity errors and successful retry', (
    tester,
  ) async {
    final source = FakeNotesSource(notes: [syncedNote('local')]);
    source.byId('local')!.touch();
    await _open(tester, source, 'live_activity');
    await _tap(tester);
    expect(find.textContaining('1 change waiting.'), findsOneWidget);
    source.changeBehindTheScenes(() => source.isSyncing = true);
    await _deliver(tester);
    expect(find.text('Syncing 1 change now.'), findsOneWidget);
    source.changeBehindTheScenes(() => source.lastError = 'Public retry error');
    await _deliver(tester);
    expect(find.text('Syncing 1 change now.'), findsOneWidget);
    expect(find.text('Public retry error'), findsNothing);
    source.changeBehindTheScenes(() => source.isSyncing = false);
    await _deliver(tester);
    expect(find.text('Public retry error'), findsOneWidget);
    source.changeBehindTheScenes(() {
      source.lastError = null;
      source.byId('local')!.dirty = false;
      source.isSyncing = true;
    });
    await _deliver(tester);
    expect(find.text('Checking for cloud changes…'), findsOneWidget);
    expect(find.text('Public retry error'), findsNothing);
    source.changeBehindTheScenes(() => source.isSyncing = false);
    await _deliver(tester);
    expect(find.text('No local changes waiting.'), findsOneWidget);
    expect(source.syncCalls, 0);
  });

  testWidgets('an open bubble follows pending edits and cleared cooldown', (
    tester,
  ) async {
    final source = FakeNotesSource(notes: [syncedNote('local')])
      ..nextAutoSyncAt = DateTime.now().add(const Duration(minutes: 40));
    await _open(tester, source, 'live_pending');
    await _tap(tester);
    expect(
      find.text('No local changes waiting. Next sync in 40 min.'),
      findsOneWidget,
    );
    source.changeBehindTheScenes(() => source.byId('local')!.touch());
    await _deliver(tester);
    expect(find.text('1 change waiting. Next sync in 40 min.'), findsOneWidget);
    source.changeBehindTheScenes(() => source.nextAutoSyncAt = null);
    await _deliver(tester);
    expect(
      find.textContaining('1 change waiting. It syncs by itself'),
      findsOneWidget,
    );
    expect(find.textContaining('Next sync in'), findsNothing);
    expect(source.syncCalls, 0);
  });

  testWidgets('live updates do not extend the original bubble lifetime', (
    tester,
  ) async {
    final source = FakeNotesSource(notes: [syncedNote('local')]);
    await _open(tester, source, 'auto_hide');
    await _tap(tester);
    await tester.pump(const Duration(seconds: 1));
    source.changeBehindTheScenes(() => source.isSyncing = true);
    await _deliver(tester);
    expect(find.text('Checking for cloud changes…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(find.text('Checking for cloud changes…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Checking for cloud changes…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing an open bubble cancels its hide timer', (
    tester,
  ) async {
    final source = FakeNotesSource(notes: [syncedNote('local')]);
    await _open(tester, source, 'dispose_timer');
    await _tap(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    source.changeBehindTheScenes(() => source.isSyncing = true);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(OverlayPortal), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
