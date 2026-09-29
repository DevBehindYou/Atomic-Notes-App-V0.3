import 'dart:async';
import 'dart:convert';
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
    await repository.stop(waitForSync: true);
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

  test('R2 a busy sync is not proof that a later edit is backed up', () async {
    final entered = Completer<void>(), release = Completer<void>();
    api.beforePush = () { entered.complete(); return release.future; };
    await repository.save(Note.create()..title = 'first');
    final syncing = repository.syncNow();
    await entered.future;
    final later = Note.create()..title = 'later';
    await repository.save(later);
    var finished = false;
    final logoutCheck = repository.syncNow().then((value) { finished = true; return value; });
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    release.complete();
    await syncing;
    expect(await logoutCheck, isFalse);
    await expectLater(repository.clearLocal(), throwsStateError);
    expect((box.get(later.id) as Map)['dirty'], isTrue);
  });

  test('R2 hidden sealed dirty rows also block destructive logout clearing', () async {
    vault.unlocked = true;
    final note = Note.create()..title = 'unsent protected note';
    await repository.save(note);
    await repository.lockVault();
    expect(repository.pendingCount, 0);
    await expectLater(repository.clearLocal(), throwsStateError);
    expect(box.containsKey(note.id), isTrue);
  });

  test('R3 same-user re-login reloads clean and dirty disk rows and cursor', () async {
    final clean = Note.create()..title = 'already synced';
    await repository.save(clean);
    expect(await repository.syncNow(), isTrue);
    final dirty = Note.create()..title = 'offline change';
    await repository.save(dirty);
    final cursor = box.get('__sync_cursor__');
    await repository.stop();
    repository.clearMemory();
    expect(repository.count, 0);
    await repository.start();
    expect(repository.count, 2);
    expect(repository.byId(dirty.id)!.dirty, isTrue);
    expect(repository.byId(clean.id)!.dirty, isFalse);
    expect(box.get('__sync_cursor__'), cursor);
  });

  test('R3 another account never receives the prior owner cache', () async {
    await repository.save(Note.create()..title = 'account a');
    await repository.stop();
    repository.clearMemory();
    api.user = 'user-b';
    await repository.start();
    expect(repository.visible(), isEmpty);
    expect(box.get('__cache_owner__'), 'user-b');
  });

  test('R3 session expiry during decryption cannot repopulate cleared memory', () async {
    vault.unlocked = true;
    await repository.save(Note.create()..title = 'old account');
    repository.clearMemory();
    vault.openEntered = Completer<void>();
    vault.openGate = Completer<void>();
    final loading = repository.start();
    await vault.openEntered!.future;
    api.user = null;
    await repository.stop();
    repository.clearMemory();
    vault.openGate!.complete();
    await loading;
    expect(repository.count, 0);
  });

  test('R2 clean acknowledged notes can still be cleared for logout', () async {
    await repository.save(Note.create()..title = 'backed up');
    expect(await repository.syncNow(), isTrue);
    await repository.stop(waitForSync: true);
    await repository.clearLocal();
    expect(box.isEmpty, isTrue);
  });

  test('R4 deletion during the first upload stays dirty after acknowledgement', () async {
    final entered = Completer<void>(), release = Completer<void>();
    api.beforePush = () { entered.complete(); return release.future; };
    final note = Note.create()..title = 'first upload';
    await repository.save(note);
    final syncing = repository.syncNow();
    await entered.future;
    await repository.deleteNotes([note.id]);
    release.complete();
    expect(await syncing, isFalse);
    expect(repository.byId(note.id)!.serverVersion, 1);
    expect(repository.byId(note.id)!.dirty, isTrue);
    expect(repository.byId(note.id)!.deleted, isTrue);
    api.beforePush = null;
    expect(await repository.syncNow(instant: true), isTrue);
    expect(api.pushes.last.single['deleted'], isTrue);
    expect(api.pushes.last.single['base_version'], 1);
  });

  test('R4 a genuinely never-uploaded deletion needs no cloud tombstone', () async {
    final note = Note.create()..title = 'local only';
    await repository.save(note);
    await repository.deleteNotes([note.id]);
    expect(repository.pendingCount, 0);
    expect(await repository.deleteForever([note.id]), 1);
    expect(api.pushes, isEmpty);
  });

  test('R4 deletion during snapshot sealing also requires a later tombstone', () async {
    final note = Note.create()..title = 'sealing race';
    await repository.save(note);
    vault.unlocked = true;
    vault.sealEntered = Completer<void>();
    vault.sealGate = Completer<void>();
    final syncing = repository.syncNow();
    await vault.sealEntered!.future;
    final deleting = repository.deleteNotes([note.id]);
    vault.sealGate!.complete();
    await deleting;
    await syncing;
    expect(repository.byId(note.id)!.deleted, isTrue);
    expect(repository.byId(note.id)!.dirty, isTrue);
    expect(repository.byId(note.id)!.serverVersion, 1);
  });

  test('R7 UTF-8 payload budget includes the complete request envelope', () async {
    for (var i = 0; i < 24; i++) {
      await repository.save(Note.create()..body = List.filled(60000, '界').join());
    }
    expect(await repository.syncNow(instant: true), isTrue);
    expect(api.pushes.length, greaterThan(1));
    for (var i = 0; i < api.pushes.length; i++) {
      final bytes = utf8.encode(jsonEncode({'rows': api.pushes[i],
        'requestId': api.requestIds[i], 'mode': 'instant'})).length;
      expect(bytes, lessThanOrEqualTo(2500000));
      expect(api.pushes[i].length, lessThanOrEqualTo(50));
    }
  });

  test('R7 an uncharged 413 forgets the poisoned request and resnapshots edits', () async {
    final note = Note.create()..title = 'initial';
    await repository.save(note);
    api.beforePush = () async { throw ApiException('http_413', 413); };
    expect(await repository.syncNow(), isFalse);
    expect(box.get('__pending_sync_operation'), isNull);
    note.title = 'corrected';
    await repository.save(note);
    api.beforePush = null;
    expect(await repository.syncNow(), isTrue);
    expect(api.requestIds.last, isNot(api.requestIds.first));
    expect(api.pushes.last.single['title'], 'corrected');
  });
}
