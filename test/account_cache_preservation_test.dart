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
  late TestVault vault;
  late NotesRepository repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-owner-proof-');
    Hive.init(directory.path);
    box = await Hive.openBox('owner-proof');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('owner-sync');
    api = TestApi();
    vault = TestVault();
    repository = NotesRepository.forTest(
        box: box,
        api: api,
        vault: vault,
        checkConnectivity: () async => [ConnectivityResult.wifi]);
    await repository.start();
  });
  tearDown(() async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    await Hive.close();
    final resolved = await directory.resolveSymbolicLinks();
    expect(Directory(resolved).parent.path,
        await Directory.systemTemp.resolveSymbolicLinks());
    expect(
        Directory(resolved)
            .uri
            .pathSegments
            .where((part) => part.isNotEmpty)
            .last,
        startsWith('atomic-owner-proof-'));
    await Directory(resolved).delete(recursive: true);
  });
  Future<Note> save() async {
    final note = Note.create()..title = 'Synthetic owner fixture';
    await repository.save(note);
    return note;
  }

  Future<void> retire(String nextUser) async {
    await repository.stop(waitForSync: true);
    repository.clearMemory();
    api.user = nextUser;
    api.sessionRevision++;
  }

  test('same owner can reload unsynced work', () async {
    final note = await save();
    final stored = Map.from(box.get(note.id) as Map);
    await retire('user-a');
    await repository.start();
    expect(repository.byId(note.id)!.dirty, isTrue);
    expect(box.get(note.id), stored);
  });
  test(
      'another owner receives an empty cache when previous work is acknowledged',
      () async {
    final note = await save();
    expect(await repository.syncNow(instant: true), isTrue);
    await retire('user-b');
    await repository.start();
    expect(repository.count, 0);
    expect(box.get(note.id), isNull);
    expect(box.get('__cache_owner__'), 'user-b');
  });
  for (final encrypted in [false, true]) {
    test('foreign sign-in refuses deletion of pending work (sealed=$encrypted)',
        () async {
      vault.unlocked = encrypted;
      final note = await save();
      final stored = Map.from(box.get(note.id) as Map);
      await retire('user-b');
      vault.unlocked = false;
      await expectLater(repository.start(), throwsStateError);
      expect(repository.count, 0,
          reason: 'Never display previous-account content');
      expect(box.get(note.id), stored);
      expect(box.get('__cache_owner__'), 'user-a');
      await expectLater(repository.save(Note.create()), throwsStateError);
      api.user = 'user-a';
      api.sessionRevision++;
      vault.unlocked = encrypted;
      await repository.start();
      expect(repository.byId(note.id)!.dirty, isTrue);
      expect(repository.byId(note.id)!.title, note.title);
    });
  }
  test('foreign sign-in preserves an unresolved request even with clean rows',
      () async {
    final note = await save();
    expect(await repository.syncNow(instant: true), isTrue);
    final pending = {
      'requestId': newId(),
      'userId': 'user-a',
      'instant': true,
      'rows': [note.toRemote('user-a')],
      'versions': {},
      'sigs': {},
      'conflictIds': {}
    };
    await box.put('__pending_sync_operation', pending);
    await retire('user-b');
    await expectLater(repository.start(), throwsStateError);
    expect(box.get('__pending_sync_operation'), pending);
    expect(box.get(note.id), isNotNull);
    expect(box.get('__cache_owner__'), 'user-a');
  });
}
