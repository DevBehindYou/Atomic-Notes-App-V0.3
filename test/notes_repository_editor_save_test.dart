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

/// A vault whose sealing can be made to fail.
class _FailingVault extends TestVault {
  Object? failure;

  @override
  Future<String> encryptContent(Map<String, dynamic> content) async {
    final error = failure;
    if (error != null) throw error;
    return super.encryptContent(content);
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
