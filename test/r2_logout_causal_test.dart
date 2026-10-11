import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'notes_repository_lifecycle_test.dart' show TestApi, TestVault;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;
  late TestApi api;
  late NotesRepository repository;
  String? caseCode;

  setUp(() async {
    caseCode = null;
    final ownedRoot = Platform.environment['ATOMIC_R2_OWNED_ROOT'];
    directory =
        await (ownedRoot == null ? Directory.systemTemp : Directory(ownedRoot))
            .createTemp('atomic-r2-hive-');
    Hive.init(directory.path);
    box = await Hive.openBox('isolated-notes');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('isolated-sync');
    api = TestApi();
    repository = NotesRepository.forTest(
      box: box,
      api: api,
      vault: TestVault(),
      checkConnectivity: () async => [ConnectivityResult.wifi],
    );
    await repository.start();
  });

  tearDown(() async {
    // Every paused future is drained in its case's finally before teardown.
    await repository.stop();
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
    expect(directory.existsSync(), isFalse);
    if (caseCode != null) {
      // Fixed markers only. The runner discards all other test messages.
      print('atomic_r2_cleanup:$caseCode');
    }
  });

  test('R2 busy sync preserves a later local edit', () async {
    caseCode = 'busy_logout';
    final entered = Completer<void>(), release = Completer<void>();
    api.beforePush = () {
      if (!entered.isCompleted) entered.complete();
      return release.future;
    };
    final first = Note.create()..title = 'Public first fixture note';
    await repository.save(first);
    final syncing = repository.syncNow();
    Future<bool>? checking;
    bool completedEarly = false;
    bool? result;
    late Note later;
    try {
      await entered.future.timeout(const Duration(seconds: 5));
      later = Note.create()..title = 'Public later fixture note';
      await repository.save(later);
      expect(api.pushes.single.single['id'], first.id);
      checking = repository.syncNow().then((value) {
        completedEarly = true;
        result = value;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final wasEarly = completedEarly;
      print(
        'atomic_r2_observation:busy_logout:'
        '${wasEarly && result == true ? 'early_success' : 'waited'}',
      );
      if (wasEarly && result == true) {
        // Source-verified pre-fix SettingsPage ordering, not a widget test.
        // This calls the actual repository; no clear behavior is reimplemented.
        await repository.stop();
        await repository.clearLocal();
      }
      print(
        'atomic_r2_observation:busy_logout:'
        '${box.containsKey(later.id) ? 'preserved' : 'erased'}',
      );
      api.beforePush = null;
      release.complete();
      await syncing.timeout(const Duration(seconds: 5));
      await checking.timeout(const Duration(seconds: 5));
      expect(wasEarly, isFalse);
      expect(result, isFalse);
      expect((box.get(later.id) as Map)['dirty'], isTrue);
      expect(
        api.pushes.expand((rows) => rows).any((row) => row['id'] == later.id),
        isFalse,
      );
    } finally {
      api.beforePush = null;
      if (!release.isCompleted) release.complete();
      await syncing.timeout(const Duration(seconds: 5));
      if (checking != null) {
        await checking.timeout(const Duration(seconds: 5));
      }
    }
  });

  test('R2 paused upload excludes later snapshot content', () async {
    caseCode = 'snapshot_control';
    final entered = Completer<void>(), release = Completer<void>();
    api.beforePush = () {
      if (!entered.isCompleted) entered.complete();
      return release.future;
    };
    final first = Note.create()..title = 'Public paused fixture note';
    await repository.save(first);
    final syncing = repository.syncNow();
    try {
      await entered.future.timeout(const Duration(seconds: 5));
      final later = Note.create()..title = 'Public unsent fixture note';
      await repository.save(later);
      expect(api.pushes.single.single['id'], first.id);
      expect((box.get(later.id) as Map)['dirty'], isTrue);
      api.beforePush = null;
      release.complete();
      await syncing.timeout(const Duration(seconds: 5));
      expect((box.get(later.id) as Map)['dirty'], isTrue);
      expect(
        api.pushes.expand((rows) => rows).any((row) => row['id'] == later.id),
        isFalse,
      );
      print('atomic_r2_observation:snapshot_control:paused_snapshot');
    } finally {
      api.beforePush = null;
      if (!release.isCompleted) release.complete();
      await syncing.timeout(const Duration(seconds: 5));
    }
  });

  test('R2 clean acknowledged notes can be cleared', () async {
    caseCode = 'clean_control';
    await repository.save(Note.create()..title = 'Public acknowledged fixture');
    expect(await repository.syncNow(instant: true), isTrue);
    await repository.stop();
    await repository.clearLocal();
    expect(box.isEmpty, isTrue);
    print('atomic_r2_observation:clean_control:clean_clear');
  });
}
