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
  final pushModes = <bool>[];
  List<Map<String, dynamic>>? pushResults;
  Future<void> Function()? beforePush;
  int sequence = 0;
  List<Map<String, dynamic>> pullRows = [];
  Object? pullFailure;
  final pullCursors = <int?>[];
  @override
  String? get currentUserId => user;
  @override
  Future<List<Map<String, dynamic>>> pushNotes(List<Map<String, dynamic>> rows,
      {required String requestId, bool instant = false}) async {
    pushes.add(rows);
    requestIds.add(requestId);
    pushModes.add(instant);
    await beforePush?.call();
    if (pushResults != null) return pushResults!;
    return rows.map((row) => <String, dynamic>{
      'id': row['id'], 'ok': true, 'version': (row['base_version'] as int) + 1,
      'seq': ++sequence, 'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).toList();
  }
  @override
  Future<Map<String, dynamic>> pullNotes({int? after, bool encOnly = false}) async {
    pullCursors.add(after);
    if (pullFailure != null) throw pullFailure!;
    return {
      'rows': pullRows, 'nextCursor': sequence, 'hasMore': false,
      'cursor': DateTime.now().toUtc().toIso8601String(),
    };
  }
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

  test('R19 offline automatic attempt notifies its failure without a note change', () async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    repository = NotesRepository.forTest(box: box, api: api, vault: vault,
      checkConnectivity: () async => [ConnectivityResult.none]);
    await repository.start();
    final seen = <String?>[];
    repository.addListener(() => seen.add(repository.lastError));
    expect(await repository.syncNow(), false);
    expect(seen, contains('Offline — changes are saved on this device'));
    expect(api.pushes, isEmpty);
    expect(api.pullCursors, isEmpty);
  });

  test('R19 retiring a session clears and suppresses a late sync failure', () async {
    final note = Note.create(kind: NoteKind.text)..title = 'local work';
    await repository.save(note);
    final entered = Completer<void>(), release = Completer<void>();
    api.beforePush = () async {
      entered.complete();
      await release.future;
      throw ApiException('fixture_failure', 500);
    };
    final sync = repository.syncNow(instant: true);
    await entered.future;
    await repository.stop();
    repository.clearMemory();
    api.user = null;
    release.complete();
    expect(await sync, false);
    expect(repository.lastError, isNull);
    expect(repository.count, 0);
    expect(box.get(note.id), isNotNull, reason: 'failure status never deletes local work');
  });

  for (final encrypted in [false, true]) {
    test('conflict contract preserves both contents and uploads the copy later (encrypted=$encrypted)', () async {
      vault.unlocked = encrypted;
      final seed = Note.create(kind: NoteKind.todo)
        ..title = 'shared'
        ..body = 'base content'
        ..items = [TodoItem(text: 'base task', done: false)];
      Future<Map<String, dynamic>> wire(Note note, int version) async {
        final row = {...note.toRemote(api.user!), 'version': version,
          'updated_at': DateTime.utc(2026, 9, 1).toIso8601String()};
        if (encrypted) {
          row['payload'] = await vault.encryptContent({
            'title': note.title, 'body': note.body,
            'items': note.items.map((i) => i.toMap()).toList(),
          });
          row['enc_v'] = 1;
          row['title'] = ''; row['body'] = ''; row['items'] = <dynamic>[];
        }
        return row;
      }
      api.pullRows = [await wire(seed, 3)]; api.sequence = 3;
      expect(await repository.syncNow(), isTrue);
      final local = repository.byId(seed.id)!
        ..body = 'offline device B'
        ..items = [TodoItem(text: 'B task', done: true)];
      await repository.save(local);
      local.updatedAt = DateTime.utc(2099); // skew does not decide the version conflict
      final remote = seed.copy()..body = 'device A accepted';
      api.pullRows = [await wire(remote, 4)]; api.sequence = 4;
      api.pushResults = [{'id': seed.id, 'ok': false, 'error': 'note_conflict', 'version': 4}];

      expect(await repository.syncNow(instant: true), isFalse);
      expect(api.pushes.single.single['base_version'], 3);
      expect(api.pullCursors, [null, null], reason: 'conflict resets the old cursor');
      expect(repository.byId(seed.id)!.body, 'device A accepted');
      expect(repository.byId(seed.id)!.serverVersion, 4);
      final copy = repository.visible().singleWhere((n) => n.id != seed.id);
      expect(copy.title, 'shared (conflict copy)');
      expect(copy.body, 'offline device B');
      expect(copy.items.single.text, 'B task');
      expect(copy.items.single.done, isTrue);
      expect(copy.dirty, isTrue, reason: 'conflict copy is initially local, not uploaded');
      expect(copy.serverVersion, 0);
      expect(repository.pendingCount, 1);
      final stored = box.get(copy.id) as Map;
      expect(stored['dirty'], isTrue);
      if (encrypted) {
        expect(stored['enc_v'], 1);
        expect(stored['body'], '');
        expect((await vault.decryptContent(stored['payload'] as String))['body'], 'offline device B');
      } else {
        expect(stored['body'], 'offline device B');
      }
      await repository.stop(); repository.clearMemory(); await repository.start();
      expect(repository.byId(copy.id)!.body, 'offline device B');
      api.pushResults = null;
      expect(await repository.syncNow(instant: true), isTrue);
      expect(api.pushes.last.single['id'], copy.id);
      expect(repository.pendingCount, 0);
      expect(repository.byId(seed.id)!.body, 'device A accepted');
    });
  }

  test('conflict contract preserves the local copy even when the following pull fails', () async {
    final note = Note.create()..body = 'base';
    final row = {...note.toRemote(api.user!), 'version': 3,
      'updated_at': DateTime.now().toUtc().toIso8601String()};
    api.pullRows = [row]; api.sequence = 3;
    expect(await repository.syncNow(), isTrue);
    await repository.save(repository.byId(note.id)!..body = 'B saved edit');
    api.pushResults = [{'id': note.id, 'ok': false, 'error': 'note_conflict', 'version': 4}];
    api.pullFailure = ApiException('note_content_unavailable', 409);
    expect(await repository.syncNow(instant: true), isFalse);
    final copy = repository.visible().singleWhere((n) => n.id != note.id);
    expect(copy.body, 'B saved edit');
    expect((box.get(copy.id) as Map)['dirty'], isTrue);
    expect(box.get('__sync_cursor__'), isNull);
    await repository.stop(); repository.clearMemory(); await repository.start();
    expect(repository.byId(copy.id)!.body, 'B saved edit');
    expect(repository.byId(copy.id)!.dirty, isTrue);
  });

  test('conflict contract stale deletion becomes a live copy while the remote edit survives', () async {
    final note = Note.create()..title = 'shared'..body = 'base';
    final row = {...note.toRemote(api.user!), 'version': 3,
      'updated_at': DateTime.now().toUtc().toIso8601String()};
    api.pullRows = [row]; api.sequence = 3;
    expect(await repository.syncNow(), isTrue);
    await repository.deleteNotes([note.id]);
    api.pushResults = [{'id': note.id, 'ok': false, 'error': 'note_conflict', 'version': 4}];
    api.pullRows = [{...row, 'version': 4, 'body': 'remote edit'}]; api.sequence = 4;
    expect(await repository.syncNow(instant: true), isFalse);
    expect(api.pushes.single.single['deleted'], isTrue);
    expect(repository.byId(note.id)!.body, 'remote edit');
    expect(repository.byId(note.id)!.deleted, isFalse);
    final copy = repository.visible().singleWhere((n) => n.id != note.id);
    expect(copy.body, 'base');
    expect(copy.deleted, isFalse, reason: 'current implementation preserves content, not deletion intent');
    expect(copy.dirty, isTrue);
  });

  test('billing contract instant sync with 100 small notes sends two distinct requests', () async {
    for (var i = 0; i < 100; i++) {
      await repository.save(Note.create()..title = 'fixture $i');
    }
    expect(await repository.syncNow(instant: true), isTrue);
    expect(api.pushes.map((rows) => rows.length), [50, 50]);
    expect(api.requestIds.toSet().length, 2);
    expect(api.pushModes, [true, true]);
    expect(repository.pendingCount, 0);
  });

  test('billing contract standard sync sends 50 of 100 notes then waits for the hourly window', () async {
    for (var i = 0; i < 100; i++) {
      await repository.save(Note.create()..title = 'fixture $i');
    }
    expect(await repository.syncNow(), isFalse);
    expect(api.pushes.single.length, 50);
    expect(api.pushModes, [false]);
    expect(repository.pendingCount, 50);
    expect(repository.nextAutoSyncAt, isNotNull);
    expect(await repository.syncNow(), isFalse);
    expect(api.pushes.length, 1, reason: 'second standard request waits');
    expect(repository.pendingCount, 50);
  });

  test('billing contract receive-only sync makes no push request', () async {
    final note = Note.create()..title = 'other device';
    api.pullRows = [{...note.toRemote(api.user!), 'version': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String()}];
    api.sequence = 1;
    expect(await repository.syncNow(instant: true), isTrue);
    expect(repository.byId(note.id)!.title, 'other device');
    expect(api.pushes, isEmpty);
  });

  test('R16 unavailable cloud note keeps the cursor and cached notes until retry succeeds', () async {
    final cached = Note.create()..title = 'already downloaded';
    final missing = Note.create()..title = 'recovered cloud note';
    final cachedRow = {...cached.toRemote(api.user!), 'version': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String()};
    final missingRow = {...missing.toRemote(api.user!), 'version': 2,
      'updated_at': DateTime.now().toUtc().toIso8601String()};
    api.pullRows = [cachedRow]; api.sequence = 1;
    expect(await repository.syncNow(), isTrue);
    final stored = Map.from(box.get(cached.id) as Map);
    api.pullFailure = ApiException('note_content_unavailable', 409);
    for (var attempt = 0; attempt < 2; attempt++) {
      expect(await repository.syncNow(), isFalse);
      expect(repository.byId(cached.id)!.title, 'already downloaded');
      expect(box.get(cached.id), stored);
      expect(repository.byId(missing.id), isNull);
      expect(box.get('__sync_cursor__'), 1);
      expect(repository.lastError,
        'A cloud note is missing or unreadable in Google Drive. Sync cannot finish until it is restored.');
    }
    api.pullFailure = null;
    api.pullRows = [missingRow]; api.sequence = 2;
    expect(await repository.syncNow(), isTrue);
    expect(api.pullCursors, [null, 1, 1, 1]);
    expect(repository.byId(missing.id)!.title, 'recovered cloud note');
    expect(box.get(cached.id), stored);
    expect(box.get('__sync_cursor__'), 2);
    expect(repository.lastError, isNull);
    expect(api.pushes, isEmpty);
  });

  test('R11 inconsistent cloud read preserves the cache and cursor and explains retry', () async {
    final note = Note.create()..title = 'committed copy';
    final row = {...note.toRemote(api.user!), 'version': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String()};
    api.pullRows = [row]; api.sequence = 1;
    expect(await repository.syncNow(), isTrue);
    final stored = Map.from(box.get(note.id) as Map);
    api.pullRows = [{...row, 'version': 2, 'title': 'consistent new copy'}];
    api.sequence = 2;
    api.pullFailure = ApiException('note_content_mismatch', 409);
    expect(await repository.syncNow(), isFalse);
    expect(repository.byId(note.id)!.title, 'committed copy');
    expect(box.get(note.id), stored);
    expect(box.get('__sync_cursor__'), 1);
    expect(repository.lastError, 'A cloud note could not be read safely. Try syncing again.');
    api.pullFailure = null;
    expect(await repository.syncNow(), isTrue);
    expect(api.pullCursors, [null, 1, 1]);
    expect(repository.byId(note.id)!.title, 'consistent new copy');
    expect(box.get('__sync_cursor__'), 2);
    expect(repository.lastError, isNull);
    expect(api.pushes, isEmpty);
  });

  test('R5 empty cloud preserves local notes and a newer recreation replaces a clean copy', () async {
    final note = Note.create()..title = 'cached before wipe';
    final before = {...note.toRemote(api.user!), 'version': 5,
      'updated_at': DateTime.now().toUtc().toIso8601String()};
    api.pullRows = [before]; api.sequence = 5;
    expect(await repository.syncNow(), isTrue);
    expect(repository.byId(note.id)!.serverVersion, 5);
    api.pullRows = [];
    expect(await repository.syncNow(), isTrue);
    expect(repository.byId(note.id)!.title, 'cached before wipe');
    expect(box.containsKey(note.id), isTrue);
    api.pullRows = [{...before, 'version': 6, 'title': 'recreated on another device'}];
    api.sequence = 6;
    expect(await repository.syncNow(), isTrue);
    expect(repository.byId(note.id)!.title, 'recreated on another device');
    expect(repository.byId(note.id)!.serverVersion, 6);
    expect((box.get(note.id) as Map)['serverVersion'], 6);
    expect(box.get('__sync_cursor__'), 6);
    expect(api.pushes, isEmpty);
  });

  test('R5 newer recreation never overwrites an unsent local edit', () async {
    final note = Note.create()..title = 'cached before wipe';
    final before = {...note.toRemote(api.user!), 'version': 5,
      'updated_at': DateTime.now().toUtc().toIso8601String()};
    api.pullRows = [before]; api.sequence = 5;
    expect(await repository.syncNow(), isTrue);
    final local = repository.byId(note.id)!..title = 'unsent edit';
    await repository.save(local);
    api.beforePush = () async { throw ApiException('sync_cooldown', 429, retryAfterSeconds: 3600); };
    api.pullRows = [{...before, 'version': 6, 'title': 'recreated on another device'}];
    api.sequence = 6;
    expect(await repository.syncNow(), isFalse);
    expect(repository.byId(note.id)!.title, 'unsent edit');
    expect(repository.byId(note.id)!.serverVersion, 5);
    expect(repository.byId(note.id)!.dirty, isTrue);
    expect((box.get(note.id) as Map)['dirty'], isTrue);
    expect(api.pushes.length, 1, reason: 'cooldown refused the attempted upload');
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
