// S1 / review R09: an editor's save is acknowledged by the real repository
// only when this attempt's note was written for the editor's own account.
// Disposable Hive and the committed synthetic API/vault helpers only.

import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'notes_repository_lifecycle_test.dart' show TestApi, TestVault;

/// A vault whose sealing can be made to fail, counting every seal started.
/// [failure] fails at once; [failureAfterSeal] fails once a (held) seal ran.
class _FailingVault extends TestVault {
  Object? failure;
  Object? failureAfterSeal;
  int seals = 0;

  @override
  Future<String> encryptContent(Map<String, dynamic> content) async {
    seals++;
    final error = failure;
    if (error != null) throw error;
    final sealed = await super.encryptContent(content);
    final late = failureAfterSeal;
    if (late != null) throw late;
    return sealed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;
  late TestApi api;
  late _FailingVault vault;
  late NotesRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-editor-save-');
    Hive.init(directory.path);
    box = await Hive.openBox('editor-save-notes');
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('editor-save-sync');
    api = TestApi();
    vault = _FailingVault()..unlocked = true;
    repository = NotesRepository.forTest(
        box: box,
        api: api,
        vault: vault,
        checkConnectivity: () async => [ConnectivityResult.wifi]);
    await repository.start();
  });

  tearDown(() async {
    final gate = vault.sealGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await repository.stop(waitForSync: true);
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Note draft(String id, [String title = 'Synthetic draft']) =>
      Note(id: id, title: title, body: 'Disposable fixture');

  /// Holds every seal until [release]; completes [entered] at the first.
  void holdSeals() {
    vault
      ..sealGate = Completer<void>()
      ..sealEntered = Completer<void>();
  }

  void release() => vault.sealGate!.complete();

  void switchAccount() {
    api.user = 'user-b';
    api.sessionRevision++;
  }

  test('a stored attempt is acknowledged as stored', () async {
    final context = repository.captureEditorContext()!;
    final note = draft('n1');
    expect(await repository.saveForEditor(note, context),
        isA<NoteLocalSaveStored>());
    expect(box.containsKey('n1'), isTrue);
    expect(repository.byId('n1'), same(note));
  });

  test('review R09: an account change while sealing retires the write',
      () async {
    final context = repository.captureEditorContext()!;
    holdSeals();
    final receipt = repository.saveForEditor(draft('n1'), context);
    await vault.sealEntered!.future;
    switchAccount();
    release();
    final result = await receipt;
    expect(result, isA<NoteLocalSaveRetired>());
    expect((result as NoteLocalSaveRetired).reason,
        NoteSaveRetirement.contextChanged);
    expect(box.containsKey('n1'), isFalse);
  });

  test('review R09 through the bloc: a retired write is not "saved"', () async {
    final bloc = NotesBloc(
        source: repository,
        isSyncEnabled: () => false,
        isOnline: () async => true);
    final context = bloc.captureEditorContext()!;
    holdSeals();
    final ack = NoteSaveAck();
    bloc.add(NoteSaved(draft('n1'), ack: ack, context: context));
    await vault.sealEntered!.future;
    switchAccount();
    release();
    final result = await ack.result;
    await bloc.close();
    expect(result, isA<NoteSaveRetired>());
    expect(box.containsKey('n1'), isFalse);
  });

  test('a session change before Done writes nothing and changes no memory',
      () async {
    final context = repository.captureEditorContext()!;
    api.sessionRevision++; // same account, new session
    final result = await repository.saveForEditor(draft('n1'), context);
    expect((result as NoteLocalSaveRetired).reason,
        NoteSaveRetirement.contextChanged);
    expect(repository.byId('n1'), isNull);
    expect(box.containsKey('n1'), isFalse);
  });

  test('an account change while the write is queued retires it', () async {
    final context = repository.captureEditorContext()!;
    holdSeals();
    final earlier = repository.save(draft('other'));
    await vault.sealEntered!.future;
    final receipt = repository.saveForEditor(draft('n1'), context);
    switchAccount();
    release();
    await earlier;
    expect((await receipt as NoteLocalSaveRetired).reason,
        NoteSaveRetirement.contextChanged);
    expect(box.containsKey('n1'), isFalse);
  });

  test('a failed write is a failure, not a success', () async {
    final context = repository.captureEditorContext()!;
    vault.failure = StateError('synthetic seal failure');
    final result = await repository.saveForEditor(draft('n1'), context);
    expect(result, isA<NoteLocalSaveFailed>());
    expect((result as NoteLocalSaveFailed).error, same(vault.failure));
    expect(box.containsKey('n1'), isFalse);
  });

  test('a same-id replacement before the write runs retires this attempt',
      () async {
    final context = repository.captureEditorContext()!;
    holdSeals();
    final earlier = repository.save(draft('other'));
    await vault.sealEntered!.future;
    final mine = draft('n1', 'Editor draft');
    final receipt = repository.saveForEditor(mine, context);
    final newer = draft('n1', 'Newer change');
    final replacing = repository.save(newer);
    release();
    await Future.wait([earlier, replacing]);
    expect((await receipt as NoteLocalSaveRetired).reason,
        NoteSaveRetirement.replaced);
    expect(repository.byId('n1'), same(newer));
  });

  test('a deletion before the write runs retires this attempt', () async {
    final context = repository.captureEditorContext()!;
    holdSeals();
    final earlier = repository.save(draft('other'));
    await vault.sealEntered!.future;
    final receipt = repository.saveForEditor(draft('n1'), context);
    // Let the save queue its write, then delete before the chain runs it.
    await Future<void>.delayed(Duration.zero);
    final deleting = repository.deleteNotes(['n1']);
    release();
    await Future.wait([earlier, deleting]);
    expect((await receipt as NoteLocalSaveRetired).reason,
        NoteSaveRetirement.deleted);
  });

  test('a stopped store or another store\'s context writes nothing', () async {
    final context = repository.captureEditorContext()!;
    final otherBox = await Hive.openBox('editor-save-other');
    final other = NotesRepository.forTest(
        box: otherBox,
        api: api,
        vault: vault,
        checkConnectivity: () async => [ConnectivityResult.wifi]);
    await other.start();
    expect(await other.saveForEditor(draft('n1'), context),
        isA<NoteLocalSaveRetired>());
    await other.stop(waitForSync: true);
    other.dispose();
    await repository.stop(waitForSync: true);
    expect(repository.captureEditorContext(), isNull);
    expect(await repository.saveForEditor(draft('n2'), context),
        isA<NoteLocalSaveRetired>());
    expect(box.containsKey('n2'), isFalse);
  });

  group('review R13: the queued write checks its own context', () {
    test('a same-account session change while sealing retires before the box',
        () async {
      final context = repository.captureEditorContext()!;
      holdSeals();
      final receipt = repository.saveForEditor(draft('n1'), context);
      await vault.sealEntered!.future;
      api.sessionRevision++; // same account, new session
      release();
      expect((await receipt as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.contextChanged);
      expect(box.containsKey('n1'), isFalse);
    });

    test('a same-account session change while queued retires before sealing',
        () async {
      final context = repository.captureEditorContext()!;
      holdSeals();
      final earlier = repository.save(draft('other'));
      await vault.sealEntered!.future;
      final receipt = repository.saveForEditor(draft('n1'), context);
      api.sessionRevision++;
      release();
      await earlier;
      expect((await receipt as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.contextChanged);
      expect(vault.seals, 1, reason: 'only the earlier write was sealed');
      expect(box.containsKey('n1'), isFalse);
      expect(box.containsKey('other'), isTrue,
          reason: 'the regular save ahead of it is unchanged');
    });

    test('a store lifecycle change while sealing retires before the box',
        () async {
      final context = repository.captureEditorContext()!;
      holdSeals();
      final receipt = repository.saveForEditor(draft('n1'), context);
      await vault.sealEntered!.future;
      final stopping = repository.stop();
      release();
      await stopping;
      expect((await receipt as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.contextChanged);
      expect(box.containsKey('n1'), isFalse);
    });

    test('a regular save in the same race still writes (unchanged)', () async {
      holdSeals();
      final saving = repository.save(draft('n1'));
      await vault.sealEntered!.future;
      api.sessionRevision++;
      release();
      await saving;
      expect(box.containsKey('n1'), isTrue);
    });

    test('a write committed before a session change stays stored (ADR-018)',
        () async {
      final context = repository.captureEditorContext()!;
      // Runs after the write reached the box, before the receipt is made.
      void changeSession() {
        if (box.containsKey('n1')) api.sessionRevision++;
      }
      repository.addListener(changeSession);
      final result = await repository.saveForEditor(draft('n1'), context);
      repository.removeListener(changeSession);
      expect(result, isA<NoteLocalSaveStored>());
      expect(api.sessionRevision, 1);
      expect(box.containsKey('n1'), isTrue);
    });

    test('a lock while sealing drains the admitted write and stores it',
        () async {
      final context = repository.captureEditorContext()!;
      holdSeals();
      final receipt = repository.saveForEditor(draft('n1'), context);
      await vault.sealEntered!.future;
      final locking = repository.lockVault();
      expect(repository.captureEditorContext(), isNull);
      release();
      expect(await receipt, isA<NoteLocalSaveStored>());
      await locking;
      expect(box.containsKey('n1'), isTrue);
      expect(repository.byId('n1'), isNull,
          reason: 'the lock removed the plaintext from memory');
      expect(await repository.saveForEditor(draft('n2'), context),
          isA<NoteLocalSaveRetired>(),
          reason: 'the lock reloaded the store, so the old context is gone');
      expect(box.containsKey('n2'), isFalse);
    });

    test('logout while sealing is refused and the write stores', () async {
      final context = repository.captureEditorContext()!;
      holdSeals();
      final receipt = repository.saveForEditor(draft('n1'), context);
      await vault.sealEntered!.future;
      var tornDown = false;
      Object? refused;
      try {
        await repository.logoutSafely(finishLocal: (_) async => tornDown = true);
      } catch (error) {
        refused = error;
      }
      release();
      expect(await receipt, isA<NoteLocalSaveStored>());
      expect(refused, isNotNull);
      expect(tornDown, isFalse);
      expect(box.containsKey('n1'), isTrue);
    });

    test('two editors: the replaced one stores only on an explicit retry',
        () async {
      final firstContext = repository.captureEditorContext()!;
      final secondContext = repository.captureEditorContext()!;
      holdSeals();
      final earlier = repository.save(draft('other'));
      await vault.sealEntered!.future;
      final first = draft('n1', 'First editor');
      final firstReceipt = repository.saveForEditor(first, firstContext);
      final secondReceipt =
          repository.saveForEditor(draft('n1', 'Second editor'), secondContext);
      release();
      await earlier;
      expect((await firstReceipt as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.replaced);
      expect(await secondReceipt, isA<NoteLocalSaveStored>());
      expect(repository.byId('n1')!.title, 'Second editor');
      expect(await repository.saveForEditor(first, firstContext),
          isA<NoteLocalSaveStored>());
      expect(repository.byId('n1')!.title, 'First editor');
    });

    test('a retired attempt is never retried into another account', () async {
      final context = repository.captureEditorContext()!;
      holdSeals();
      final receipt = repository.saveForEditor(draft('n1'), context);
      await vault.sealEntered!.future;
      switchAccount();
      release();
      expect((await receipt as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.contextChanged);
      // Draining the store's queue writes nothing more: no retry, no copy.
      await repository.stop(waitForSync: true);
      expect(vault.seals, 1);
      expect(box.containsKey('n1'), isFalse);
    });

    test('a missing context is rejected at once: no seal and no write',
        () async {
      final bloc = NotesBloc(
          source: repository,
          isSyncEnabled: () => false,
          isOnline: () async => true);
      holdSeals();
      final ack = NoteSaveAck();
      bloc.add(NoteSaved(draft('n1'), ack: ack));
      final result = await ack.result.timeout(const Duration(seconds: 2));
      release();
      await bloc.close();
      expect(result, isA<NoteSaveRejected>());
      expect(vault.seals, 0);
      expect(box.containsKey('n1'), isFalse);
    });
  });

  group('review R16: a failed attempt for a changed context retires', () {
    /// Holds the seal, applies [change] while it is held, then makes the
    /// held seal throw on release. Returns the receipt.
    Future<NoteLocalSaveReceipt> failAfter(void Function() change) async {
      final context = repository.captureEditorContext()!;
      holdSeals();
      final receipt = repository.saveForEditor(draft('n1'), context);
      await vault.sealEntered!.future;
      change();
      vault.failureAfterSeal = StateError('synthetic seal failure');
      release();
      return receipt;
    }

    test('reviewer fixture: another account and a sealing failure retire', () async {
      final result = await failAfter(switchAccount);
      expect((result as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.contextChanged);
      expect(box.containsKey('n1'), isFalse);
    });

    test('a same-account session change and a sealing failure retire', () async {
      final result = await failAfter(() => api.sessionRevision++);
      expect((result as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.contextChanged);
      expect(box.containsKey('n1'), isFalse);
    });

    test('a lifecycle change and a sealing failure retire', () async {
      late Future<void> stopping;
      final result = await failAfter(() => stopping = repository.stop());
      await stopping;
      expect((result as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.contextChanged);
      expect(box.containsKey('n1'), isFalse);
    });

    test('the same context and a sealing failure stay a failure', () async {
      final result = await failAfter(() {});
      expect(result, isA<NoteLocalSaveFailed>());
      expect((result as NoteLocalSaveFailed).error, same(vault.failureAfterSeal));
      expect(box.containsKey('n1'), isFalse);
      expect(repository.captureEditorContext(), isNotNull,
          reason: 'the editor may retry for its own account');
    });

    test('a lock while sealing, then a failure, stays a failure', () async {
      final context = repository.captureEditorContext()!;
      holdSeals();
      final receipt = repository.saveForEditor(draft('n1'), context);
      await vault.sealEntered!.future;
      final locking = repository.lockVault();
      vault.failureAfterSeal = StateError('synthetic seal failure');
      release();
      expect(await receipt, isA<NoteLocalSaveFailed>(),
          reason: 'the lock drains admitted writes; it does not change the identity');
      await locking;
      expect(box.containsKey('n1'), isFalse);
    });

    test('through the bloc: retired, not a failure the editor offers to retry',
        () async {
      final bloc = NotesBloc(
          source: repository,
          isSyncEnabled: () => false,
          isOnline: () async => true);
      final context = bloc.captureEditorContext()!;
      holdSeals();
      final ack = NoteSaveAck();
      bloc.add(NoteSaved(draft('n1'), ack: ack, context: context));
      await vault.sealEntered!.future;
      api.sessionRevision++;
      vault.failureAfterSeal = StateError('synthetic seal failure');
      release();
      final result = await ack.result;
      await bloc.close();
      expect(result, isA<NoteSaveRetired>());
      expect((result as NoteSaveRetired).reason, NoteSaveRetirement.contextChanged);
      expect(box.containsKey('n1'), isFalse);
    });
  });

  group('review R18: the write decides the receipt, later errors do not', () {
    // A second store on the same box with automatic sync on, so a save
    // schedules sync after its write. Closing the sync settings box makes
    // that scheduling throw after the note is already in Hive.
    late NotesRepository auto;

    setUp(() async {
      await SyncStatusHelper.syncBox.put('isSyncOn', false);
      auto = NotesRepository.forTest(
          box: box,
          api: api,
          vault: vault,
          checkConnectivity: () async => [ConnectivityResult.wifi],
          automaticSync: true);
      await auto.start();
    });

    tearDown(() async {
      final gate = vault.sealGate;
      if (gate != null && !gate.isCompleted) gate.complete();
      await auto.stop(waitForSync: true);
      auto.dispose();
    });

    Future<void> breakScheduling() => SyncStatusHelper.syncBox.close();

    test('reviewer fixture: stored, then scheduling fails: still Stored', () async {
      final context = auto.captureEditorContext()!;
      await breakScheduling();
      final result = await auto.saveForEditor(draft('n1'), context);
      expect(result, isA<NoteLocalSaveStored>());
      expect(box.containsKey('n1'), isTrue);
      expect((box.get('n1') as Map)['enc_v'], greaterThan(0));
    });

    test('replaced, then scheduling fails: still Retired(replaced)', () async {
      final context = auto.captureEditorContext()!;
      holdSeals();
      final earlier = auto.save(draft('other'));
      await vault.sealEntered!.future;
      final receipt = auto.saveForEditor(draft('n1', 'Editor draft'), context);
      final newer = draft('n1', 'Newer change');
      final replacing = auto.save(newer);
      await breakScheduling();
      release();
      // The regular saves also schedule sync and throw; that path is
      // unchanged and outside the owned-save receipt.
      await expectLater(earlier, throwsA(isA<HiveError>()));
      expect((await receipt as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.replaced);
      await expectLater(replacing, throwsA(isA<HiveError>()));
      expect(auto.byId('n1'), same(newer));
    });

    test('deleted, then scheduling fails: still Retired(deleted)', () async {
      final context = auto.captureEditorContext()!;
      holdSeals();
      final earlier = auto.save(draft('other'));
      await vault.sealEntered!.future;
      // A note the cloud already has, so its tombstone stays dirty and the
      // save schedules sync after its write.
      final receipt = auto.saveForEditor(draft('n1')..serverVersion = 3, context);
      await Future<void>.delayed(Duration.zero); // let the save queue its write
      final deleting = auto.deleteNotes(['n1']);
      await breakScheduling();
      release();
      await expectLater(earlier, throwsA(isA<HiveError>()));
      expect((await receipt as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.deleted);
      await expectLater(deleting, throwsA(isA<HiveError>()));
    });

    test('a failure before the write still follows the identity (R16)', () async {
      final context = auto.captureEditorContext()!;
      vault.failure = StateError('synthetic seal failure');
      expect(await auto.saveForEditor(draft('n1'), context),
          isA<NoteLocalSaveFailed>());
      vault.failure = null;
      holdSeals();
      final receipt = auto.saveForEditor(draft('n2'), context);
      await vault.sealEntered!.future;
      api.sessionRevision++;
      vault.failureAfterSeal = StateError('synthetic seal failure');
      release();
      expect((await receipt as NoteLocalSaveRetired).reason,
          NoteSaveRetirement.contextChanged);
      expect(box.containsKey('n1'), isFalse);
      expect(box.containsKey('n2'), isFalse);
    });
  });

  group('review R19: admission errors become a receipt', () {
    test('reviewer fixture: a closed cache at admission retires, never throws',
        () async {
      final context = repository.captureEditorContext()!;
      await box.close();
      expect(await repository.saveForEditor(draft('n1'), context),
          isA<NoteLocalSaveRetired>());
    });

    test('a cache that closes during sealing retires', () async {
      final context = repository.captureEditorContext()!;
      holdSeals();
      final receipt = repository.saveForEditor(draft('n1'), context);
      await vault.sealEntered!.future;
      await box.close();
      release();
      expect(await receipt, isA<NoteLocalSaveRetired>());
    });

    test('a verified context still reports a real failure (protected note)',
        () async {
      final context = repository.captureEditorContext()!;
      expect(await repository.saveForEditor(draft('n1'), context),
          isA<NoteLocalSaveStored>());
      final before = Map<dynamic, dynamic>.from(box.get('n1') as Map);
      vault.unlocked = false;
      expect(await repository.saveForEditor(draft('n1', 'Changed'), context),
          isA<NoteLocalSaveFailed>());
      expect(box.get('n1'), before);
    });
  });

  test('signed out: no editor context', () async {
    api.user = null;
    expect(repository.captureEditorContext(), isNull);
  });

  test('the unacknowledged save keeps its behaviour', () async {
    final note = draft('n1');
    await repository.save(note);
    expect(box.containsKey('n1'), isTrue);
    expect(repository.byId('n1'), same(note));
  });
}
