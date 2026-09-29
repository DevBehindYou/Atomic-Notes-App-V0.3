import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/security/vault_crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

class TestApi implements ApiClient {
  String? user = 'user-a';
  final pushes = <List<Map<String, dynamic>>>[];
  final requestIds = <String>[];
  Future<void> Function()? beforePush;
  int sequence = 0;
  @override
  String? get currentUserId => user;
  @override
  Future<List<Map<String, dynamic>>> pushNotes(List<Map<String, dynamic>> rows,
      {required String requestId, bool instant = false}) async {
    pushes.add(rows);
    requestIds.add(requestId);
    await beforePush?.call();
    return rows.map((row) => <String, dynamic>{
      'id': row['id'], 'ok': true, 'version': (row['base_version'] as int) + 1,
      'seq': ++sequence, 'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).toList();
  }
  @override
  Future<Map<String, dynamic>> pullNotes({int? after, bool encOnly = false}) async => {
    'rows': <Map<String, dynamic>>[], 'nextCursor': sequence, 'hasMore': false,
    'cursor': DateTime.now().toUtc().toIso8601String(),
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestVault implements Vault {
  bool unlocked = false;
  final key = SecretKey(List.generate(32, (i) => i)); // disposable fixture only
  Completer<void>? sealGate;
  Completer<void>? sealEntered;
  Completer<void>? openGate;
  Completer<void>? openEntered;
  @override
  bool get isUnlocked => unlocked;
  @override
  Future<String> encryptContent(Map<String, dynamic> content) async {
    if (!(sealEntered?.isCompleted ?? true)) sealEntered!.complete();
    await sealGate?.future;
    return VaultCrypto.sealJson(content, key);
  }
  @override
  Future<Map<String, dynamic>> decryptContent(String payload) async {
    if (!(openEntered?.isCompleted ?? true)) openEntered!.complete();
    await openGate?.future;
    return VaultCrypto.openJson(payload, key);
  }
  @override
  Future<void> lockThisDevice() async { unlocked = false; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;
  late TestApi api;
  late TestVault vault;
  late NotesRepository repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-repository-test-');
    Hive.init(directory.path);
    box = await Hive.openBox('isolated-notes');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('isolated-sync');
    api = TestApi();
    vault = TestVault();
    repository = NotesRepository.forTest(box: box, api: api, vault: vault,
      checkConnectivity: () async => [ConnectivityResult.wifi]);
    await repository.start();
  });
  tearDown(() async {
    await repository.stop();
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('R1 lock hides protected rows and stale editors cannot downgrade them', () async {
    vault.unlocked = true;
    final note = Note.create()..title = 'protected test content';
    await repository.save(note);
    final sealed = Map.from(box.get(note.id) as Map);
    expect(sealed['enc_v'], 1);
    expect(sealed['title'], '');
    await repository.lockVault();
    expect(repository.visible(), isEmpty);
    expect(repository.byId(note.id), isNull);
    note.body = 'stale editor';
    await expectLater(repository.save(note), throwsStateError);
    expect(box.get(note.id), sealed);
    final plain = Note.create()..title = 'new T2T note';
    await repository.save(plain);
    expect((box.get(plain.id) as Map)['enc_v'], 0,
      reason: 'preserve existing new-note T2T behavior while locked');
    expect(repository.visible().single.id, plain.id);
  });


  test('R1 lock drains an asynchronous encrypted write before dropping the key', () async {
    vault.unlocked = true;
    vault.sealEntered = Completer<void>();
    vault.sealGate = Completer<void>();
    final note = Note.create()..title = 'queued encrypted note';
    final saving = repository.save(note);
    await vault.sealEntered!.future;
    var locked = false;
    final locking = repository.lockVault().then((_) => locked = true);
    await Future<void>.delayed(Duration.zero);
    expect(locked, isFalse);
    vault.sealGate!.complete();
    await saving;
    await locking;
    expect((box.get(note.id) as Map)['enc_v'], 1);
    expect(repository.count, 0);
  });


  test('R4 a genuinely never-uploaded deletion needs no cloud tombstone', () async {
    final note = Note.create()..title = 'local only';
    await repository.save(note);
    await repository.deleteNotes([note.id]);
    expect(repository.pendingCount, 0);
    expect(await repository.deleteForever([note.id]), 1);
    expect(api.pushes, isEmpty);
  });

}
