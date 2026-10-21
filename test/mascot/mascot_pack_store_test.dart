import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/mascot/file_mascot_pack_store.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';

class PausingStore extends FileMascotPackStore {
  PausingStore({required super.root});
  final entered = Completer<void>();
  final release = Completer<void>();
  bool pause = false;
  @override
  Future<bool> isInstalled(String id) async {
    final installed = await super.isInstalled(id);
    if (pause) {
      entered.complete();
      await release.future;
    }
    return installed;
  }
}

class PausedExistenceDirectory implements Directory {
  PausedExistenceDirectory(this.delegate, this.entered, this.release);
  final Directory delegate;
  final Completer<void> entered, release;
  @override
  String get path => delegate.path;
  @override
  Directory get absolute => delegate.absolute;
  @override
  Directory get parent => delegate.parent;
  @override
  Future<bool> exists() async {
    entered.complete();
    await release.future;
    return delegate.exists();
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      delegate.delete(recursive: recursive);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FileMascotPackStore store;
  final mascot = MascotCatalog.findById('051-blink')!;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mascot-store-');
    store = FileMascotPackStore(root: root);
    await store.initialize();
  });
  tearDown(() async => root.delete(recursive: true));

  Future<Uint8List> bytesFor(int slot) async {
    final source = File(
        'test/fixtures/mascots/051 Blink/${mascot.clips[slot].originalFilename}');
    return source.readAsBytes();
  }

  test('partial staging and interrupted promotion never make a pack ready',
      () async {
    await store.startPack(mascot);
    final writer = await store.beginClip(mascot.clips.first);
    await writer.write(await bytesFor(0));
    await writer.finish();
    expect(await store.isInstalled(mascot.id), isFalse);
    await expectLater(store.promotePack(mascot), throwsStateError);
    final reopened = FileMascotPackStore(root: root);
    await reopened.initialize();
    expect(await reopened.isInstalled(mascot.id), isFalse);
  });

  test('complete pack is readable and lease blocks removal', () async {
    await store.startPack(mascot);
    for (var index = 0; index < mascot.clips.length; index++) {
      final writer = await store.beginClip(mascot.clips[index]);
      await writer.write(await bytesFor(index));
      await writer.finish();
    }
    await store.promotePack(mascot);
    expect(await store.isInstalled(mascot.id), isTrue);
    final lease = await store.openVerifiedClip(mascot.clips.first);
    expect(lease.bytes.length, mascot.clips.first.bytes);
    await expectLater(store.removePack(mascot.id), throwsStateError);
    await lease.close();
    await store.removePack(mascot.id);
    expect(await store.isInstalled(mascot.id), isFalse);
  });

  test('tampered installed bytes fail verification on read', () async {
    await store.startPack(mascot);
    for (var index = 0; index < mascot.clips.length; index++) {
      final writer = await store.beginClip(mascot.clips[index]);
      await writer.write(await bytesFor(index));
      await writer.finish();
    }
    await store.promotePack(mascot);
    await File(
            '${root.path}/installed/v1/${mascot.id}/${mascot.clips.first.originalFilename}')
        .writeAsBytes([0], flush: true);
    await expectLater(
        store.openVerifiedClip(mascot.clips.first), throwsStateError);
  });

  test('verified preview cannot copy through a staged target link', () async {
    final clip = mascot.clips.first;
    final preview = await store.beginPreview(clip);
    await preview.write(await bytesFor(0));
    await preview.finish();
    await store.publishPreview(clip);
    await store.startPack(mascot);
    final outside = await File('${root.path}.outside').writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      if (await outside.exists()) await outside.delete();
    });
    final target =
        Link('${root.path}/staged/v1/${mascot.id}/${clip.originalFilename}');
    try {
      await target.create(outside.path);
    } on FileSystemException {
      markTestSkipped('This filesystem cannot create symlinks');
      return;
    }
    await expectLater(store.reusePreview(clip), throwsStateError);
    expect(await outside.readAsBytes(), [1, 2, 3]);
  });

  test('verification rejects a linked preview parent', () async {
    final clip = mascot.clips.first;
    final outside =
        await Directory.systemTemp.createTemp('mascot-preview-outside-');
    addTearDown(() => outside.delete(recursive: true));
    await File('${outside.path}/${clip.originalFilename}')
        .writeAsBytes(await bytesFor(0));
    final version = Directory('${root.path}/previews/v1');
    await version.create(recursive: true);
    final linked = Link('${version.path}/${mascot.id}');
    try {
      await linked.create(outside.path);
    } on FileSystemException {
      markTestSkipped('This filesystem cannot create symlinks');
      return;
    }
    await expectLater(store.readPreview(clip), throwsStateError);
  });

  test('removal waits for a pending lease acquisition', () async {
    await store.startPack(mascot);
    for (var index = 0; index < mascot.clips.length; index++) {
      final writer = await store.beginClip(mascot.clips[index]);
      await writer.write(await bytesFor(index));
      await writer.finish();
    }
    await store.promotePack(mascot);
    final slow = PausingStore(root: root);
    await slow.initialize();
    slow.pause = true;
    final opening = slow.openVerifiedClip(mascot.clips.first);
    await slow.entered.future;
    final removing = slow.removePack(mascot.id);
    slow.release.complete();
    final lease = await opening;
    await expectLater(removing, throwsStateError);
    expect(await store.isInstalled(mascot.id), isTrue);
    await lease.close();
  });

  test('promotion rejects a linked ready marker without touching its target',
      () async {
    await store.startPack(mascot);
    for (var index = 0; index < mascot.clips.length; index++) {
      final writer = await store.beginClip(mascot.clips[index]);
      await writer.write(await bytesFor(index));
      await writer.finish();
    }
    final outside = await File('${root.path}.ready-target')
        .writeAsString('outside unchanged', flush: true);
    addTearDown(() async {
      if (await outside.exists()) await outside.delete();
    });
    final marker = Link('${root.path}/staged/v1/${mascot.id}/ready');
    try {
      await marker.create(outside.path);
    } on FileSystemException {
      markTestSkipped('This filesystem cannot create symlinks');
      return;
    }
    await expectLater(store.promotePack(mascot), throwsStateError);
    expect(await outside.readAsString(), 'outside unchanged');
    expect(await store.isInstalled(mascot.id), isFalse);
  });

  test('removal checks live selection after waiting for directory existence',
      () async {
    await store.startPack(mascot);
    for (var index = 0; index < mascot.clips.length; index++) {
      final writer = await store.beginClip(mascot.clips[index]);
      await writer.write(await bytesFor(index));
      await writer.finish();
    }
    await store.promotePack(mascot);
    var selected = MascotCatalog.defaultId;
    final entered = Completer<void>();
    final release = Completer<void>();
    final installedPath =
        '${root.path}${Platform.pathSeparator}installed${Platform.pathSeparator}v1${Platform.pathSeparator}${mascot.id}';
    final removing = IOOverrides.runZoned(
      () => store.removePack(mascot.id, canRemove: () => selected != mascot.id),
      createDirectory: (path) {
        final real = Zone.root.run(() => Directory(path));
        if (path == installedPath) {
          return PausedExistenceDirectory(real, entered, release);
        }
        return real;
      },
    );
    await entered.future;
    selected = mascot.id;
    release.complete();
    await expectLater(removing, throwsStateError);
    expect(await store.isInstalled(mascot.id), isTrue);
  });
}
