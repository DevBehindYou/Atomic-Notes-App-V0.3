// A confirmed "delete for good" is judged and guarded by the notes store
// itself (Codex R38, R39). The store says which bin notes must sync first,
// with the same may-have-reached-cloud rule its removal applies, and freezes
// each confirmed tombstone with the account, session and store lifecycle.
// After its sync, and through every later wait, nothing is removed unless
// each confirmed note is still that tombstone: an acknowledgement may settle
// its sync flag and version, while a restored, replaced or newer tombstone,
// or another session, needs a fresh confirmation. Real repository on an
// isolated Hive box with a fake API. All notes and keys are synthetic.

import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/endpage/recycle_bin_page.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/security/vault_crypto.dart';
import 'package:atomic_notes/state/recycle_bin/recycle_bin_cubit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

const String _changed = 'The Recycle Bin changed before this could finish. '
    'Nothing was deleted for good. Check it and try again.';

/// A fake API: pushes are accepted at the next version unless told
/// otherwise, pulls return [pullRows].
class _Api implements ApiClient {
  String? user = 'synthetic-user';
  @override
  int sessionRevision = 0;
  int pushCalls = 0;
  int sequence = 0;
  Future<void> Function()? beforePush;
  Object? pushFailure;
  List<Map<String, dynamic>> pullRows = [];

  @override
  String? get currentUserId => user;

  @override
  Future<PushReply> pushNotes(List<Map<String, dynamic>> rows,
      {required String requestId, bool instant = false}) async {
    pushCalls++;
    await beforePush?.call();
    if (pushFailure != null) throw pushFailure!;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;
  late _Api api;
  late _Vault vault;
  late NotesRepository repository;
  late BinRemover remover;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-bin-consent-');
    Hive.init(directory.path);
    box = await Hive.openBox('isolated-notes');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('isolated-sync');
    api = _Api();
    vault = _Vault();
    repository = NotesRepository.forTest(
        box: box,
        api: api,
        vault: vault,
        checkConnectivity: () async => [ConnectivityResult.wifi]);
    await repository.start();
    remover = BinRemover(repository);
  });

  tearDown(() async {
    await repository.stop(waitForSync: true);
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<Note> synced(String body, {String title = ''}) async {
    final note = Note.create()
      ..title = title
      ..body = body;
    await repository.save(note);
    expect(await repository.syncNow(instant: true), isTrue);
    return repository.byId(note.id)!;
  }

  /// A deleted note whose deletion has reached the cloud.
  Future<Note> settledTombstone(String body) async {
    final note = await synced(body);
    await repository.deleteNotes([note.id]);
    expect(await repository.syncNow(instant: true), isTrue);
    expect(repository.byId(note.id)!.dirty, isFalse);
    return repository.byId(note.id)!;
  }

  /// A deleted note whose deletion still has to reach the cloud.
  Future<Note> pendingTombstone(String body) async {
    final note = await synced(body);
    await repository.deleteNotes([note.id]);
    expect(repository.byId(note.id)!.dirty, isTrue);
    return repository.byId(note.id)!;
  }

  /// A cloud row for [note] at [version] with [body] and [deleted].
  Map<String, dynamic> remoteRow(Note note, int version,
          {String? body, bool deleted = true}) =>
      {
        ...(note.copy()
              ..body = body ?? note.body
              ..deleted = deleted)
            .toRemote('synthetic-user'),
        'version': version,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  group('classification', () {
    test('the page step is the store judgement, not the sync flag alone',
        () async {
      final clean = await settledTombstone('Synthetic clean');
      final pending = await pendingTombstone('Synthetic pending');
      // A local-only tombstone left dirty by a rejected first upload (R38).
      final local = Note.create()..body = 'Synthetic local';
      await repository.save(local);
      final entered = Completer<void>();
      final release = Completer<void>();
      api.beforePush = () async {
        entered.complete();
        await release.future;
        throw ApiException('http_413', 413);
      };
      final upload = repository.syncNow(instant: true);
      await entered.future;
      await repository.deleteNotes([local.id]);
      // In flight: the cloud may be receiving it.
      expect(
          remover.stepOf(repository.byId(local.id)!), BinRemovalStep.syncFirst);
      release.complete();
      expect(await upload, isFalse);
      api.beforePush = null;
      final tomb = repository.byId(local.id)!;
      expect(tomb.dirty, isTrue);
      expect(tomb.serverVersion, 0);

      expect(remover.stepOf(clean), BinRemovalStep.removeNow);
      expect(remover.stepOf(pending), BinRemovalStep.syncFirst);
      expect(remover.stepOf(tomb), BinRemovalStep.removeNow,
          reason: 'Nothing of it can have reached the cloud.');
      expect(RecycleBinPage.removalStep(tomb), BinRemovalStep.syncFirst,
          reason: 'The flag-only fallback, kept for other stores.');
      final removal = remover.confirm([clean, pending, tomb], wholeBin: true);
      expect(removal.count(BinRemovalStep.syncFirst), 1);
      expect(removal.count(BinRemovalStep.removeNow), 2);
      expect(
          RecycleBinPage.emptyBinWarning([clean, pending, tomb],
              stepOf: (n) => removal.stepOf(n.id)!),
          startsWith('1 note has changes'));
      expect(
          RecycleBinPage.deleteForeverBody(tomb, step: removal.stepOf(tomb.id)),
          contains('sends nothing to the cloud'));
    });

    test('classifying changes nothing', () async {
      final pending = await pendingTombstone('Synthetic pending');
      final before = Map.of(box.toMap());
      final pushes = api.pushCalls;
      var notified = 0;
      void count() => notified++;
      repository.addListener(count);
      final consent = repository.binPurgeConsent([pending.id, 'absent']);
      remover.confirm(repository.binNotes, wholeBin: true);
      remover.stepOf(pending);
      repository.removeListener(count);
      expect(consent.needsSync, isTrue);
      expect(consent.factOf('absent'), isNull);
      expect(notified, 0);
      expect(api.pushCalls, pushes);
      expect(box.toMap(), before);
      expect(repository.byId(pending.id)!.dirty, isTrue);
    });
  });

  group('acknowledgement-only changes', () {
    test('a pending deletion acknowledged by the required sync is removed',
        () async {
      final a = await pendingTombstone('Synthetic A');
      final before = repository.byId(a.id)!;
      final version = before.serverVersion;
      final removal = remover.confirm([before]);
      var acknowledged = false;
      void observe() {
        final n = repository.byId(a.id);
        if (n != null && !n.dirty && n.serverVersion > version) {
          acknowledged = true;
        }
      }

      repository.addListener(observe);
      final message = await remover.remove(removal);
      repository.removeListener(observe);

      expect(acknowledged, isTrue,
          reason: 'The sync settled its flag and version before removal.');
      expect(message.text, 'Deleted for good');
      expect(repository.byId(a.id), isNull);
      expect(box.containsKey(a.id), isFalse);
    });

    test('a mixed confirmed batch with only acknowledgements empties the bin',
        () async {
      final a = await settledTombstone('Synthetic A');
      final b = await pendingTombstone('Synthetic B');
      final c = await pendingTombstone('Synthetic C');
      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      final message = await remover.remove(removal);
      expect(message.text, 'Recycle Bin emptied');
      for (final id in [a.id, b.id, c.id]) {
        expect(repository.byId(id), isNull);
        expect(box.containsKey(id), isFalse);
      }
    });

    test('allows() accepts the settled sync facts only', () {
      final at = DateTime.utc(2026, 11, 1);
      BinPurgeFact fact(
              {bool needsSync = false,
              bool deleted = true,
              String sig = 's1',
              int version = 3,
              bool dirty = false,
              DateTime? updatedAt}) =>
          BinPurgeFact(
              needsSync: needsSync,
              deleted: deleted,
              contentSig: sig,
              serverVersion: version,
              dirty: dirty,
              updatedAt: updatedAt ?? at);
      BinPurgeConsent of(BinPurgeFact? f, [Object identity = 'session-1']) =>
          BinPurgeConsent(identity, {'n': f});
      final pending = of(fact(needsSync: true, dirty: true));
      final acked =
          of(fact(version: 4, updatedAt: at.add(const Duration(minutes: 1))));
      expect(pending.allows(acked), isTrue);
      expect(pending.allows(pending), isTrue);
      expect(pending.allows(of(fact(version: 4, sig: 's2'))), isFalse);
      expect(pending.allows(of(fact(version: 4, deleted: false))), isFalse);
      expect(pending.allows(of(fact(version: 0))), isFalse,
          reason: 'A version moving back is no acknowledgement.');
      expect(
          pending.allows(of(fact(
              needsSync: true,
              dirty: true,
              updatedAt: at.add(const Duration(seconds: 1))))),
          isFalse,
          reason: 'Deleted again without any acknowledgement.');
      expect(pending.allows(of(null)), isFalse);
      expect(pending.allows(of(fact(version: 4), 'session-2')), isFalse);
      final clean = of(fact());
      expect(clean.allows(of(fact(version: 5))), isFalse,
          reason: 'Nothing of a clean note can be acknowledged.');
      expect(clean.allows(of(fact(needsSync: true, dirty: true))), isFalse);
      expect(
          clean
              .allows(BinPurgeConsent('session-1', {'n': fact(), 'm': fact()})),
          isFalse);
    });
  });

  group('a replaced tombstone or a restored note needs fresh consent', () {
    test('a pending tombstone replaced by a different remote one is kept',
        () async {
      final a = await pendingTombstone('Old synthetic A');
      final removal = remover.confirm([repository.byId(a.id)!]);
      api.beforePush = () async {
        api.pullRows = [
          remoteRow(a, a.serverVersion + 3, body: 'New remote A')
        ];
      };
      final message = await remover.remove(removal);
      expect(message.text, _changed);
      expect(repository.byId(a.id)?.body, 'New remote A');
      expect(box.containsKey(a.id), isTrue);
    });

    test('a clean tombstone replaced by a same-content newer one is kept',
        () async {
      final a = await settledTombstone('Synthetic A');
      final b = await pendingTombstone('Synthetic B');
      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      api.beforePush = () async {
        api.pullRows = [remoteRow(a, a.serverVersion + 2)];
      };
      final message = await remover.remove(removal);
      expect(message.text, _changed);
      expect(repository.byId(a.id), isNotNull);
      expect(repository.byId(b.id), isNotNull,
          reason: 'All or nothing: the acknowledged one stays too.');
    });

    test('a note restored on another device is kept', () async {
      final a = await settledTombstone('Synthetic A');
      final b = await pendingTombstone('Synthetic B');
      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      api.beforePush = () async {
        api.pullRows = [remoteRow(a, a.serverVersion + 1, deleted: false)];
      };
      final message = await remover.remove(removal);
      expect(message.text, _changed);
      expect(repository.byId(a.id)!.deleted, isFalse);
      expect(repository.byId(b.id), isNotNull);
    });

    test('a clean note restored here during the sync is kept', () async {
      final a = await settledTombstone('Synthetic A');
      final b = await pendingTombstone('Synthetic B');
      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      api.beforePush = () async {
        expect(await repository.restoreNote(a.id), isTrue);
      };
      final message = await remover.remove(removal);
      expect(message.text, _changed);
      expect(repository.byId(a.id)!.deleted, isFalse);
      expect(repository.byId(b.id), isNotNull);
    });

    test('a note restored and deleted again before removal is kept', () async {
      final a = await settledTombstone('Synthetic A');
      final removal = remover.confirm([a]);
      expect(await repository.restoreNote(a.id), isTrue);
      await repository.deleteNotes([a.id]);
      final message = await remover.remove(removal);
      expect(message.text, _changed);
      expect(repository.byId(a.id)!.deleted, isTrue);
    });

    test('the store refuses a stale confirmation on its own', () async {
      final a = await settledTombstone('Synthetic A');
      final consent = repository.binPurgeConsent([a.id]);
      await repository.restoreNote(a.id);
      await repository.deleteNotes([a.id]);
      expect(await repository.deleteForever([a.id], consent: consent), 0);
      expect(repository.byId(a.id), isNotNull);
      expect(
          await repository.deleteForever([a.id, 'other'], consent: consent), 0,
          reason: 'A confirmation covers exactly its own notes.');
    });
  });

  group('session and owner', () {
    test('a session change before the removal sends and deletes nothing',
        () async {
      final a = await pendingTombstone('Synthetic A');
      final removal = remover.confirm([repository.byId(a.id)!]);
      api.sessionRevision++;
      final pushes = api.pushCalls;
      final message = await remover.remove(removal);
      expect(message.text, _changed);
      expect(api.pushCalls, pushes);
      expect(repository.byId(a.id), isNotNull);
    });

    test('a session change during the required sync deletes nothing', () async {
      final a = await settledTombstone('Synthetic A');
      final b = await pendingTombstone('Synthetic B');
      final consent = repository.binPurgeConsent([a.id, b.id]);
      api.beforePush = () async => api.sessionRevision++;
      expect(await repository.deleteForever([a.id, b.id], consent: consent), 0);
      expect(repository.byId(a.id), isNotNull);
      expect(box.containsKey(a.id), isTrue);
    });

    test('another account during the required sync deletes nothing', () async {
      final a = await settledTombstone('Synthetic A');
      final b = await pendingTombstone('Synthetic B');
      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      api.beforePush = () async => api.user = 'synthetic-other';
      await remover.remove(removal);
      api.user = 'synthetic-user';
      expect(box.containsKey(a.id), isTrue);
      expect(box.containsKey(b.id), isTrue);
    });
  });

  group('revalidation through every wait', () {
    /// Holds the store's write queue open with a sealed write of another
    /// note, so a removal waits there between memory and storage.
    Future<(Future<void>,)> holdWrites() async {
      vault.unlocked = true;
      vault.sealGate = Completer<void>();
      vault.sealEntered = Completer<void>();
      final other = Note.create()..body = 'Synthetic other';
      final save = repository.save(other);
      await vault.sealEntered!.future;
      return (save,);
    }

    test('a session change while stored copies wait keeps them', () async {
      final a = await settledTombstone('Synthetic A');
      final consent = repository.binPurgeConsent([a.id]);
      final (save,) = await holdWrites();
      final removal = repository.deleteForever([a.id], consent: consent);
      await Future<void>.delayed(Duration.zero);
      expect(repository.byId(a.id), isNull, reason: 'Waiting on the queue.');
      api.sessionRevision++;
      vault.sealGate!.complete();
      await save;
      await removal;
      expect(box.containsKey(a.id), isTrue,
          reason: 'The persisted delete is guarded too.');
    });

    test('a lifecycle change while stored copies wait keeps them', () async {
      final a = await settledTombstone('Synthetic A');
      final consent = repository.binPurgeConsent([a.id]);
      final (save,) = await holdWrites();
      final removal = repository.deleteForever([a.id], consent: consent);
      await Future<void>.delayed(Duration.zero);
      repository.clearMemory();
      vault.sealGate!.complete();
      await save;
      await removal;
      expect(box.containsKey(a.id), isTrue);
    });

    test('with nothing changed the stored copies are dropped after the wait',
        () async {
      final a = await settledTombstone('Synthetic A');
      final consent = repository.binPurgeConsent([a.id]);
      final (save,) = await holdWrites();
      final removal = repository.deleteForever([a.id], consent: consent);
      await Future<void>.delayed(Duration.zero);
      vault.sealGate!.complete();
      await save;
      expect(await removal, 1);
      expect(box.containsKey(a.id), isFalse);
    });
  });

  group('existing callers and batch semantics', () {
    test('without a confirmation deleteForever behaves as before', () async {
      final a = await settledTombstone('Synthetic A');
      final b = await pendingTombstone('Synthetic B');
      final live = await synced('Synthetic live');
      expect(
          await repository.deleteForever([a.id, b.id, live.id, 'absent']), 2);
      expect(repository.byId(a.id), isNull);
      expect(repository.byId(b.id), isNull);
      expect(repository.byId(live.id), isNotNull);
      expect(box.containsKey(a.id), isFalse);
      expect(box.containsKey(b.id), isFalse);
    });

    test('the cubit still syncs first and removes through the same store',
        () async {
      final a = await pendingTombstone('Synthetic A');
      final cubit = RecycleBinCubit(source: repository);
      addTearDown(cubit.close);
      final pushes = api.pushCalls;
      final message = await cubit.deleteForever(repository.byId(a.id)!);
      expect(message.text, isNotEmpty);
      expect(api.pushCalls, pushes + 1);
      expect(repository.byId(a.id), isNull);
    });

    test('a failed sync deletes nothing, not even notes that need none',
        () async {
      final a = await settledTombstone('Synthetic A');
      final b = await pendingTombstone('Synthetic B');
      api.pushFailure = ApiException('http_503', 503);
      final message = await remover
          .remove(remover.confirm(repository.binNotes, wholeBin: true));
      expect(message.text, isNot(_changed));
      expect(repository.byId(a.id), isNotNull);
      expect(repository.byId(b.id)!.dirty, isTrue);
    });
  });

  group('pending operations are preserved', () {
    test('a refused removal leaves other waiting changes waiting', () async {
      final a = await settledTombstone('Synthetic A');
      final edited = await synced('Synthetic edited');
      final b = await pendingTombstone('Synthetic B');
      edited.body = 'Synthetic edited again';
      await repository.save(edited);
      final pending = repository.pendingCount;
      final removal = remover.confirm(repository.binNotes, wholeBin: true);
      api.sessionRevision++;
      expect((await remover.remove(removal)).text, _changed);
      expect(repository.pendingCount, pending);
      expect(repository.byId(edited.id)!.dirty, isTrue);
      expect(repository.byId(b.id)!.dirty, isTrue);
      expect(repository.byId(a.id), isNotNull);
    });

    test('offline removal of a local-only tombstone leaves others waiting',
        () async {
      final edited = await synced('Synthetic edited');
      edited.body = 'Synthetic edited again';
      await repository.save(edited);
      final local = Note.create()..body = 'Synthetic local';
      await repository.save(local);
      final entered = Completer<void>();
      final release = Completer<void>();
      api.beforePush = () async {
        entered.complete();
        await release.future;
        throw ApiException('http_413', 413);
      };
      final upload = repository.syncNow(instant: true);
      await entered.future;
      await repository.deleteNotes([local.id]);
      release.complete();
      expect(await upload, isFalse);
      api.beforePush = null;
      await SyncStatusHelper.setSyncStatus(false);
      final pushes = api.pushCalls;

      final message =
          await remover.remove(remover.confirm([repository.byId(local.id)!]));
      expect(message.text, 'Deleted for good');
      expect(repository.byId(local.id), isNull);
      expect(box.containsKey(local.id), isFalse);
      expect(api.pushCalls, pushes, reason: 'Nothing was sent.');
      expect(repository.byId(edited.id)!.dirty, isTrue);
    });
  });
}
