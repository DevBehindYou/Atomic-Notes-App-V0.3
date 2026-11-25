// A confirmed "delete for good" accepts an acknowledgement only when the
// store can tie it to the confirmed tombstone (Codex R45). An acknowledgement
// of the store's own upload settles the same record in place; a note pulled
// from the cloud is a new record, even with the same content. A restore and
// re-delete inside the acknowledgement window, or an acknowledgement the
// store saw while another note change ran, needs a fresh confirmation. The
// count is what was removed from storage for good, a batch that stops part
// way says so, and the notes it did not remove stay in their own session.
// Real repository on an isolated Hive box with a fake API. All notes and keys
// are synthetic.

import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/endpage/recycle_bin_page.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/security/vault_crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

const String _changed = 'The Recycle Bin changed before this could finish. '
    'Nothing was deleted for good. Check it and try again.';

/// A fake API: pushes are accepted at the next version, pulls return
/// [pullRows].
class _Api implements ApiClient {
  String? user = 'synthetic-user';
  @override
  int sessionRevision = 0;
  int pushCalls = 0;
  int sequence = 0;
  Future<void> Function()? beforePush;
  List<Map<String, dynamic>> pullRows = [];

  @override
  String? get currentUserId => user;

  @override
  Future<PushReply> pushNotes(List<Map<String, dynamic>> rows,
      {required String requestId, bool instant = false}) async {
    pushCalls++;
    await beforePush?.call();
    return PushReply(requestId: requestId, instant: instant, results: [
      for (final row in rows)
        {
          'id': row['id'],
          'ok': true,
          'version': (row['base_version'] as int) + 1,
          'seq': ++sequence,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
    ]);
  }

  @override
  Future<Map<String, dynamic>> pullNotes(
          {int? after, bool encOnly = false}) async =>
      {
        'rows': pullRows,
        'nextCursor': sequence,
        'hasMore': false,
        'cursor': DateTime.now().toUtc().toIso8601String(),
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A vault that starts locked. Unlocked, its sealing can be held open, which
/// holds the store's write queue.
class _Vault implements Vault {
  bool unlocked = false;
  final SecretKey key = SecretKey(List.generate(32, (i) => i)); // synthetic
  Completer<void>? sealGate;
  Completer<void>? sealEntered;

  @override
  bool get isUnlocked => unlocked;

  @override
  Future<String> encryptContent(Map<String, dynamic> content) async {
    if (!(sealEntered?.isCompleted ?? true)) sealEntered!.complete();
    await sealGate?.future;
    return VaultCrypto.sealJson(content, key);
  }

  @override
  Future<Map<String, dynamic>> decryptContent(String payload) =>
      VaultCrypto.openJson(payload, key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The isolated box, with a hook after each completed delete of a note.
class _HookBox implements Box<dynamic> {
  _HookBox(this.inner);
  final Box<dynamic> inner;
  Future<void> Function(dynamic key)? afterDelete;
  Object? Function(dynamic key)? failDelete;
  final List<dynamic> deleted = [];

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      inner.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) => inner.put(key, value);
  @override
  Future<void> delete(dynamic key) async {
    final failure = failDelete?.call(key);
    if (failure != null) throw failure;
    await inner.delete(key);
    // Only notes: the store also deletes its own bookkeeping keys.
    if (key is String && key.startsWith('__')) return;
    deleted.add(key);
    await afterDelete?.call(key);
  }

  @override
  bool containsKey(dynamic key) => inner.containsKey(key);
  @override
  Future<void> flush() => inner.flush();
  @override
  Future<int> clear() => inner.clear();
  @override
  Iterable<dynamic> get values => inner.values;
  @override
  Iterable<dynamic> get keys => inner.keys;
  @override
  Map<dynamic, dynamic> toMap() => inner.toMap();
  @override
  bool get isOpen => inner.isOpen;
  @override
  int get length => inner.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _HookBox box;
  late _Api api;
  late _Vault vault;
  late NotesRepository repository;
  late BinRemover remover;

  Completer<void>? nextConnectivity;

  setUp(() async {
    nextConnectivity = null;
    directory = await Directory.systemTemp.createTemp('atomic-bin-r45-');
    Hive.init(directory.path);
    box = _HookBox(await Hive.openBox('isolated-notes'));
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('isolated-sync');
    api = _Api();
    vault = _Vault();
    repository = NotesRepository.forTest(
        box: box,
        api: api,
        vault: vault,
        checkConnectivity: () async {
          final held = nextConnectivity;
          nextConnectivity = null;
          await held?.future;
          return [ConnectivityResult.wifi];
        });
    await repository.start();
    remover = BinRemover(repository);
  });

  tearDown(() async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<Note> synced(String body) async {
    final note = Note.create()..body = body;
    await repository.save(note);
    expect(await repository.syncNow(instant: true), isTrue);
    return repository.byId(note.id)!;
  }

  Future<Note> settledTombstone(String body) async {
    final note = await synced(body);
    await repository.deleteNotes([note.id]);
    expect(await repository.syncNow(instant: true), isTrue);
    expect(repository.byId(note.id)!.dirty, isFalse);
    return repository.byId(note.id)!;
  }

  Future<Note> pendingTombstone(String body) async {
    final note = await synced(body);
    await repository.deleteNotes([note.id]);
    expect(repository.byId(note.id)!.dirty, isTrue);
    return repository.byId(note.id)!;
  }

  Map<String, dynamic> remoteRow(Note note, int version) => {
        ...(note.copy()..deleted = true).toRemote('synthetic-user'),
        'version': version,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  group('acknowledgement provenance', () {
    test('an inbound same-content replacement is refused by the store',
        () async {
      final a = await pendingTombstone('Synthetic A');
      final version = a.serverVersion, sig = a.contentSig;
      final consent = repository.binPurgeConsent([a.id]);
      api.beforePush = () async {
        api.pullRows = [remoteRow(a, version + 3)];
      };
      expect(await repository.deleteForever([a.id], consent: consent), 0);
      final now = repository.byId(a.id)!;
      expect(now.contentSig, sig, reason: 'Same content.');
      expect(now.serverVersion, version + 3);
      expect(identical(now, a), isFalse, reason: 'A pulled record.');
      expect(box.containsKey(a.id), isTrue);
    });

    test(
        'the store\'s own acknowledgement of the confirmed tombstone is '
        'allowed', () async {
      final a = await pendingTombstone('Synthetic A');
      final consent = repository.binPurgeConsent([a.id]);
      Note? acked;
      void observe() {
        final n = repository.byId(a.id);
        if (n != null && !n.dirty) acked = n;
      }

      repository.addListener(observe);
      expect(await repository.deleteForever([a.id], consent: consent), 1);
      repository.removeListener(observe);
      expect(identical(acked, a), isTrue,
          reason: 'Settled in place by the acknowledgement.');
      expect(box.containsKey(a.id), isFalse);
    });

    test(
        'a restore and re-delete with identical content during the sync is '
        'refused', () async {
      final a = await pendingTombstone('Synthetic A');
      final consent = repository.binPurgeConsent([a.id]);
      api.beforePush = () async {
        expect(await repository.restoreNote(a.id), isTrue);
        await repository.deleteNotes([a.id]);
      };
      expect(await repository.deleteForever([a.id], consent: consent), 0);
      final now = repository.byId(a.id)!;
      // Afterwards the facts look exactly like a plain acknowledgement.
      expect(now.deleted, isTrue);
      expect(now.dirty, isFalse);
      expect(now.contentSig, a.contentSig);
      expect(consent.allows(repository.binPurgeConsent([a.id])), isTrue,
          reason: 'Only the store saw the restore.');
      expect(box.containsKey(a.id), isTrue);
    });

    test('an acknowledgement from before the call is not attributed', () async {
      final a = await pendingTombstone('Synthetic A');
      final removal = remover.confirm([repository.byId(a.id)!]);
      expect(await repository.syncNow(instant: true), isTrue);
      expect(repository.byId(a.id)!.dirty, isFalse);
      expect((await remover.remove(removal)).text, _changed);
      expect(box.containsKey(a.id), isTrue);
    });

    test('purge cannot use acknowledgement from a sync it joined', () async {
      final note = await pendingTombstone('Synthetic A');
      final consent = repository.binPurgeConsent([note.id]);
      final entered = Completer<void>();
      final release = Completer<void>();
      api.beforePush = () async {
        entered.complete();
        await release.future;
      };

      final background = repository.syncNow(instant: true);
      await entered.future;
      final purge = repository.deleteForever([note.id], consent: consent);
      release.complete();

      expect(await background, isTrue);
      expect(await purge, 0);
      final remaining = repository.byId(note.id)!;
      expect(remaining.deleted, isTrue);
      expect(remaining.dirty, isFalse);
      expect(box.containsKey(note.id), isTrue);
    });

    test('purge cannot use acknowledgement received before sync admission',
        () async {
      final note = await pendingTombstone('Synthetic A');
      final consent = repository.binPurgeConsent([note.id]);
      final held = Completer<void>();
      nextConnectivity = held;
      final purge = repository.deleteForever([note.id], consent: consent);
      try {
        expect(nextConnectivity, isNull, reason: 'Purge is waiting on network');
        expect(await repository.syncNow(instant: true), isTrue);
        expect(repository.byId(note.id)!.dirty, isFalse);
      } finally {
        held.complete();
      }

      expect(await purge, 0);
      expect(repository.byId(note.id)!.deleted, isTrue);
      expect(box.containsKey(note.id), isTrue);
    });

    test('an acknowledgement seen while another note change runs is refused',
        () async {
      final a = await pendingTombstone('Synthetic A');
      final version = a.serverVersion;
      final consent = repository.binPurgeConsent([a.id]);
      vault.unlocked = true;
      var ackedWhileHeld = false;
      api.beforePush = () async {
        api.beforePush = null;
        // Another note's save stays running through the acknowledgement.
        vault.sealGate = Completer<void>();
        vault.sealEntered = Completer<void>();
        unawaited(repository.save(Note.create()..body = 'Synthetic other'));
        await vault.sealEntered!.future;
        unawaited(() async {
          for (var i = 0; i < 200; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            if (repository.byId(a.id)!.serverVersion > version) {
              ackedWhileHeld = true;
              break;
            }
          }
          vault.sealGate!.complete();
        }());
      };
      expect(await repository.deleteForever([a.id], consent: consent), 0);
      expect(ackedWhileHeld, isTrue);
      expect(box.containsKey(a.id), isTrue);
    });
  });

  group('session drift and counting', () {
    /// Holds the store's write queue open with a sealed write of another
    /// note, so a removal waits there between memory and storage.
    Future<(Future<void>,)> holdWrites() async {
      vault.unlocked = true;
      vault.sealGate = Completer<void>();
      vault.sealEntered = Completer<void>();
      final save = repository.save(Note.create()..body = 'Synthetic other');
      await vault.sealEntered!.future;
      return (save,);
    }

    test(
        'a session change before the durable deletes removes and counts '
        'nothing', () async {
      final a = await settledTombstone('Synthetic A');
      final b = await settledTombstone('Synthetic B');
      final consent = repository.binPurgeConsent([a.id, b.id]);
      final (save,) = await holdWrites();
      final removal = repository.deleteForever([a.id, b.id], consent: consent);
      await Future<void>.delayed(Duration.zero);
      api.sessionRevision++;
      vault.sealGate!.complete();
      await save;
      expect(await removal, 0);
      expect(box.deleted, isEmpty);
      expect(box.containsKey(a.id), isTrue);
      expect(box.containsKey(b.id), isTrue);
      expect(repository.byId(a.id), isNull,
          reason: 'Another session: not put back into this memory.');
    });

    test(
        'a session change between durable deletes counts only the removed '
        'one', () async {
      final a = await settledTombstone('Synthetic A');
      final b = await settledTombstone('Synthetic B');
      final consent = repository.binPurgeConsent([a.id, b.id]);
      box.afterDelete = (key) async => api.sessionRevision++;
      expect(await repository.deleteForever([a.id, b.id], consent: consent), 1);
      expect(box.deleted, [a.id]);
      expect(box.containsKey(b.id), isTrue,
          reason: 'The other session keeps its stored copy.');
      expect(repository.byId(b.id), isNull);
    });

    test('a failed durable delete keeps the rest in the owning session',
        () async {
      final a = await settledTombstone('Synthetic A');
      final b = await settledTombstone('Synthetic B');
      final consent = repository.binPurgeConsent([a.id, b.id]);
      box.failDelete =
          (key) => key == b.id ? const FileSystemException('synthetic') : null;
      expect(await repository.deleteForever([a.id, b.id], consent: consent), 1);
      expect(box.deleted, [a.id]);
      expect(repository.byId(a.id), isNull);
      expect(repository.byId(b.id)?.deleted, isTrue,
          reason: 'Not removed, so back in this session\'s bin.');
      expect(box.containsKey(b.id), isTrue);
    });

    test('a note stored under a confirmed id meanwhile stops the whole batch',
        () async {
      final a = await settledTombstone('Synthetic A');
      final b = await settledTombstone('Synthetic B');
      final consent = repository.binPurgeConsent([a.id, b.id]);
      final (save,) = await holdWrites();
      final removal = repository.deleteForever([a.id, b.id], consent: consent);
      await Future<void>.delayed(Duration.zero);
      final replacement = Note(id: a.id, body: 'Synthetic live A', dirty: true);
      final stored = repository.save(replacement);
      vault.sealGate!.complete();
      await save;
      await stored;
      expect(await removal, 0);
      expect(box.deleted, isEmpty);
      expect(repository.byId(a.id)?.deleted, isFalse);
      expect(repository.byId(b.id)?.deleted, isTrue,
          reason: 'Not removed, so back in this session\'s bin.');
    });

    test('without a confirmation the count is still storage removals only',
        () async {
      final a = await settledTombstone('Synthetic A');
      final b = await settledTombstone('Synthetic B');
      box.afterDelete = (key) async => api.sessionRevision++;
      expect(await repository.deleteForever([a.id, b.id]), 1);
      expect(box.containsKey(b.id), isTrue);
    });
  });

  group('copy', () {
    test(
        'review R50: a second durable delete failure reports the first completed deletion',
        () async {
      final a = await settledTombstone('Synthetic A');
      final b = await settledTombstone('Synthetic B');
      final removal = remover.confirm(
          [repository.byId(a.id)!, repository.byId(b.id)!],
          wholeBin: true);
      box.failDelete =
          (key) => key == b.id ? const FileSystemException('synthetic') : null;
      final message = await remover.remove(removal);
      expect(box.deleted, [a.id]);
      expect(box.containsKey(b.id), isTrue);
      expect(message.text, startsWith('Deleted 1 of 2 notes for good'));
    });

    test('a batch interrupted part way says so', () async {
      await settledTombstone('Synthetic A');
      await settledTombstone('Synthetic B');
      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      box.afterDelete = (key) async => api.sessionRevision++;
      expect(
          (await remover.remove(removal)).text,
          'Deleted 1 of 2 notes for good, then the removal was interrupted. '
          'One deletion was not confirmed. Check the Recycle Bin.');
    });

    test('a local-only dirty tombstone says no sync is needed', () {
      final local = Note(id: 'local', deleted: true, dirty: true);
      final clean = Note(id: 'clean', deleted: true, serverVersion: 2);
      expect(
          RecycleBinPage.deleteForeverBody(local,
              step: BinRemovalStep.removeNow),
          'It is removed from this device now and cannot be brought back '
          'from the Recycle Bin. No sync is needed to remove this note from '
          'this device, so this sends nothing to the cloud.');
      expect(
          RecycleBinPage.deleteForeverBody(clean,
              step: BinRemovalStep.removeNow),
          contains('It has no changes waiting to sync'));
      expect(
          RecycleBinPage.emptyBinConsequences([local, clean],
              stepOf: (_) => BinRemovalStep.removeNow),
          [
            '2 deleted notes are removed from this device for good.',
            '1 has no changes waiting to sync, so nothing is sent for it.',
            'No sync is needed to remove 1 note from this device, so nothing '
                'is sent for it.',
          ]);
    });
  });
}
