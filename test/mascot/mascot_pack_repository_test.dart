import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/mascot/file_mascot_pack_store.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_download_client.dart';
import 'package:atomic_notes/mascot/mascot_pack_repository.dart';
import 'package:atomic_notes/mascot/mascot_pack_state.dart';

class FailingDownloads extends MascotDownloadClient {
  FailingDownloads(this.failure)
      : super(
            releaseBase: Uri.parse(
                'https://github.com/DevBehindYou/Atomic-Notes-App-V0.3/releases/download/mascots-v1.0.0/'));
  final MascotDownloadException failure;
  int calls = 0;
  @override
  Future<void> download(
    MascotClip clip, {
    required Future<void> Function(List<int>) write,
    required MascotCancellation cancellation,
    void Function(int, int)? onProgress,
  }) async {
    calls++;
    throw failure;
  }
}

class FixtureDownloads extends MascotDownloadClient {
  FixtureDownloads({this.failOnceOnSlot, this.cancelOnSlot})
      : super(
            releaseBase: Uri.parse(
                'https://github.com/DevBehindYou/Atomic-Notes-App-V0.3/releases/download/mascots-v1.0.0/'));
  final int? failOnceOnSlot, cancelOnSlot;
  bool failed = false;
  final List<int> slots = [];
  @override
  Future<void> download(
    MascotClip clip, {
    required Future<void> Function(List<int>) write,
    required MascotCancellation cancellation,
    void Function(int, int)? onProgress,
  }) async {
    slots.add(clip.slot);
    if (cancelOnSlot == clip.slot) {
      cancellation.cancel();
      cancellation.check();
    }
    if (failOnceOnSlot == clip.slot && !failed) {
      failed = true;
      throw const MascotDownloadException('offline');
    }
    final fixture = clip.id.startsWith('022-') ? '022 Antimatter' : '051 Blink';
    final source =
        File('test/fixtures/mascots/$fixture/${clip.originalFilename}');
    final bytes = await source.readAsBytes();
    await write(bytes);
    onProgress?.call(bytes.length, clip.bytes);
  }
}

class PausingRepositoryStore extends FileMascotPackStore {
  PausingRepositoryStore({required super.root});
  final entered = Completer<void>();
  final release = Completer<void>();
  bool pause = false;
  @override
  Future<bool> isInstalled(String id) async {
    final installed = await super.isInstalled(id);
    if (pause && id == '051-blink') {
      entered.complete();
      await release.future;
    }
    return installed;
  }
}

class PausingRemovalStore extends FileMascotPackStore {
  PausingRemovalStore({required super.root});
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> removePack(String id, {bool Function()? canRemove}) async {
    entered.complete();
    await release.future;
    await super.removePack(id, canRemove: canRemove);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FileMascotPackStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mascot-repository-');
    store = FileMascotPackStore(root: root);
  });
  tearDown(() async => root.delete(recursive: true));

  test('default is included and never downloaded', () async {
    final downloads =
        FailingDownloads(const MascotDownloadException('offline'));
    final repo = MascotPackRepository(store: store, downloads: downloads);
    await repo.initialize();
    expect(repo.stateFor(MascotCatalog.defaultId).status,
        MascotPackStatus.included);
    await repo.downloadAndInstall(MascotCatalog.defaultId);
    expect(downloads.calls, 0);
    await repo.close();
  });

  test('transient failure gets two retries then fails with stable code',
      () async {
    final downloads = FailingDownloads(
        const MascotDownloadException('connection_failed', retryable: true));
    final repo = MascotPackRepository(store: store, downloads: downloads);
    await repo.initialize();
    await repo.downloadAndInstall('051-blink');
    expect(downloads.calls, 3);
    expect(repo.stateFor('051-blink').status, MascotPackStatus.failed);
    expect(repo.stateFor('051-blink').errorCode, 'connection_failed');
    await repo.close();
  });

  test('integrity failure is not retried and partial pack stays unavailable',
      () async {
    final downloads =
        FailingDownloads(const MascotDownloadException('integrity_mismatch'));
    final repo = MascotPackRepository(store: store, downloads: downloads);
    await repo.initialize();
    await repo.downloadAndInstall('051-blink');
    expect(downloads.calls, 1);
    expect(await store.isInstalled('051-blink'), isFalse);
    await repo.close();
  });

  test('explicit retry reuses verified files and installs all four atomically',
      () async {
    final downloads = FixtureDownloads(failOnceOnSlot: 3);
    final repo = MascotPackRepository(store: store, downloads: downloads);
    await repo.initialize();
    await repo.downloadAndInstall('051-blink');
    expect(repo.stateFor('051-blink').status, MascotPackStatus.failed);
    expect(await store.isInstalled('051-blink'), isFalse);
    await repo.downloadAndInstall('051-blink');
    expect(downloads.slots, [1, 2, 3, 3, 4]);
    expect(repo.stateFor('051-blink').status, MascotPackStatus.installed);
    final lease = await repo
        .openVerifiedClip(MascotCatalog.findById('051-blink')!.clips.first);
    expect(lease.bytes.length, 43975);
    await lease.close();
    await repo.close();
  });

  test('cancellation leaves partial pack unavailable', () async {
    final downloads = FixtureDownloads(cancelOnSlot: 2);
    final repo = MascotPackRepository(store: store, downloads: downloads);
    await repo.initialize();
    await repo.downloadAndInstall('051-blink');
    expect(repo.stateFor('051-blink').status, MascotPackStatus.absent);
    expect(await store.isInstalled('051-blink'), isFalse);
    await repo.close();
  });

  test('evicting a disk preview releases the older preview from state',
      () async {
    final repo =
        MascotPackRepository(store: store, downloads: FixtureDownloads());
    await repo.initialize();
    await repo.preview('051-blink');
    expect(repo.stateFor('051-blink').previewBytes, isNotNull);
    await repo.preview('022-antimatter');
    expect(
        await store
            .readPreview(MascotCatalog.findById('051-blink')!.clips.first),
        isNull);
    expect(repo.stateFor('051-blink').previewBytes, isNull);
    expect(repo.stateFor('051-blink').status, MascotPackStatus.absent);
    expect(repo.stateFor('022-antimatter').previewBytes, isNotNull);
    await repo.close();
  });

  test('removal rechecks the selected identity before deletion', () async {
    var selected = MascotCatalog.defaultId;
    final repo = MascotPackRepository(
        store: store,
        downloads: FixtureDownloads(),
        selectedId: () => selected);
    await repo.initialize();
    await repo.downloadAndInstall('051-blink');
    final removing =
        repo.remove('051-blink', selectedId: MascotCatalog.defaultId);
    selected = '051-blink';
    await expectLater(removing, throwsStateError);
    expect(await store.isInstalled('051-blink'), isTrue);
    await repo.close();
  });

  test('close waits for a pending verified lease acquisition', () async {
    final setup =
        MascotPackRepository(store: store, downloads: FixtureDownloads());
    await setup.initialize();
    await setup.downloadAndInstall('051-blink');
    await setup.close();

    final slow = PausingRepositoryStore(root: root);
    final repo =
        MascotPackRepository(store: slow, downloads: FixtureDownloads());
    await repo.initialize();
    slow.pause = true;
    final opening =
        repo.openVerifiedClip(MascotCatalog.findById('051-blink')!.clips.first);
    await slow.entered.future;
    var closed = false;
    final closing = repo.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    slow.release.complete();
    final lease = await opening;
    await closing;
    await lease.close();
    expect(closed, isTrue);
  });

  test('a download listener cannot start removal before operation ownership',
      () async {
    final repo =
        MascotPackRepository(store: store, downloads: FixtureDownloads());
    await repo.initialize();
    Future<bool>? removalRejected;
    repo.addListener(() {
      if (removalRejected == null &&
          repo.stateFor('051-blink').status == MascotPackStatus.downloading) {
        removalRejected = repo
            .remove('051-blink', selectedId: MascotCatalog.defaultId)
            .then((_) => false, onError: (Object _) => true);
      }
    });
    await repo.downloadAndInstall('051-blink');
    expect(await removalRejected, isTrue);
    expect(await store.isInstalled('051-blink'), isTrue);
    await repo.close();
  });

  test('a pack reserved for removal is unavailable until removal settles',
      () async {
    final setup =
        MascotPackRepository(store: store, downloads: FixtureDownloads());
    await setup.initialize();
    await setup.downloadAndInstall('051-blink');
    await setup.close();

    var selected = MascotCatalog.defaultId;
    final slow = PausingRemovalStore(root: root);
    final repo = MascotPackRepository(
        store: slow, downloads: FixtureDownloads(), selectedId: () => selected);
    await repo.initialize();
    final removing = repo.remove('051-blink', selectedId: selected);
    await slow.entered.future;
    expect(repo.stateFor('051-blink').isReady, isFalse);
    selected = '051-blink';
    slow.release.complete();
    await expectLater(removing, throwsStateError);
    expect(repo.stateFor('051-blink').isReady, isTrue);
    await repo.close();
  });
}
