import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'mascot_asset_resolver.dart';
import 'mascot_catalog.dart';

/// Owns only the v1 mascot subtree supplied by the app-support directory.
class FileMascotPackStore implements MascotAssetResolver {
  FileMascotPackStore({required Directory root, this.availableBytes})
      : root = root.absolute;

  final Directory root;
  final Future<int?> Function()? availableBytes;
  static const installedCap = 32 * 1024 * 1024;
  static const previewCap = 2 * 1024 * 1024;
  static const stagingCap = 6 * 1024 * 1024;
  static const reserve = 1024 * 1024;
  final Map<String, int> _leases = {};
  final Map<String, Future<void>> _packGates = {};
  bool _initialized = false;

  Future<T> _withPackGate<T>(String id, Future<T> Function() action) async {
    final previous = _packGates[id];
    final done = Completer<void>();
    final turn = done.future;
    _packGates[id] = turn;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      if (identical(_packGates[id], turn)) _packGates.remove(id);
      done.complete();
    }
  }

  Future<bool> _verified(File file, MascotClip clip) async {
    await _ensureSafe(file.parent);
    return _verify(file, clip);
  }

  Directory get _installed =>
      Directory('${root.path}${Platform.pathSeparator}installed');
  Directory get _stage =>
      Directory('${root.path}${Platform.pathSeparator}staged');
  Directory get _previews =>
      Directory('${root.path}${Platform.pathSeparator}previews');
  Directory _pack(Directory parent, String id) => Directory(
      '${parent.path}${Platform.pathSeparator}v1${Platform.pathSeparator}$id');
  File _clip(Directory parent, String id, MascotClip clip) => File(
      '${_pack(parent, id).path}${Platform.pathSeparator}${clip.originalFilename}');
  File _marker(Directory parent, String id) =>
      File('${_pack(parent, id).path}${Platform.pathSeparator}ready');

  MascotDefinition _known(String id) =>
      MascotCatalog.findById(id) ?? (throw ArgumentError.value(id, 'id'));
  String _owner(MascotClip clip) {
    for (final mascot in MascotCatalog.all) {
      if (mascot.clips.contains(clip)) return mascot.id;
    }
    throw ArgumentError.value(clip.id, 'clip');
  }

  Future<void> _ensureSafe(Directory directory) async {
    final base = root.path;
    if (directory.path != base &&
        !directory.path.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('path_outside_store');
    }
    // Check every existing component, including the injected root. A junction or
    // symlink may not redirect cosmetic writes outside this owned subtree.
    var current = directory.absolute;
    while (true) {
      final type =
          await FileSystemEntity.type(current.path, followLinks: false);
      if (type == FileSystemEntityType.link) throw StateError('unsafe_link');
      if (current.parent.path == current.path) break;
      current = current.parent;
    }
  }

  Future<void> _mkdir(Directory dir) async {
    await _ensureSafe(dir);
    await dir.create(recursive: true);
    await _ensureSafe(dir);
  }

  Future<void> initialize() async {
    await _mkdir(root);
    await _mkdir(_installed);
    await _mkdir(_stage);
    await _mkdir(_previews);
    _initialized = true;
    // Interrupted stages have no ready marker in installed. Keep only verified
    // previews; a later explicit retry can reuse them.
    await for (final child in _stage.list(followLinks: false)) {
      if (child is Link) throw StateError('unsafe_link');
    }
  }

  void _ready() {
    if (!_initialized) throw StateError('store_not_initialized');
  }

  Future<void> _space(int bytes) async {
    final remaining = await availableBytes?.call();
    if (remaining != null && remaining < bytes + reserve) {
      throw StateError('insufficient_space');
    }
  }

  Future<int> _installedBytes() async {
    var sum = 0;
    for (final mascot in MascotCatalog.all) {
      if (mascot.id != MascotCatalog.defaultId &&
          await isInstalled(mascot.id)) {
        sum += mascot.encodedBytes;
      }
    }
    return sum;
  }

  Future<void> startPack(MascotDefinition mascot) async {
    _ready();
    if (!identical(_known(mascot.id), mascot)) {
      throw ArgumentError('unknown_pack');
    }
    if (mascot.id == MascotCatalog.defaultId) throw StateError('bundled_pack');
    if (mascot.encodedBytes > stagingCap ||
        await _installedBytes() + mascot.encodedBytes > installedCap) {
      throw StateError('storage_cap');
    }
    await _space(mascot.encodedBytes);
    final stagedVersion =
        Directory('${_stage.path}${Platform.pathSeparator}v1');
    await _mkdir(stagedVersion);
    await for (final child in stagedVersion.list(followLinks: false)) {
      if (child is Link) throw StateError('unsafe_link');
      if (child is Directory && child.path != _pack(_stage, mascot.id).path) {
        await _ensureSafe(child);
        await child.delete(recursive: true);
      }
    }
    await _mkdir(_pack(_stage, mascot.id));
  }

  Future<MascotStagedClip> beginClip(MascotClip clip) async {
    _ready();
    final id = _owner(clip);
    final dir = _pack(_stage, id);
    await _ensureSafe(dir);
    if (!await dir.exists()) throw StateError('pack_not_staged');
    final file = _clip(_stage, id, clip);
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('unsafe_link');
    }
    return MascotStagedClip._(file, clip, _verified, _ensureSafe);
  }

  Future<bool> hasStagedClip(MascotClip clip) async {
    final id = _owner(clip);
    return _verified(_clip(_stage, id, clip), clip);
  }

  Future<void> discardStagedClip(MascotClip clip) async {
    final file = _clip(_stage, _owner(clip), clip);
    await _ensureSafe(file.parent);
    if (await file.exists()) await file.delete();
  }

  Future<void> discardStage(String id) async {
    _ready();
    _known(id);
    final dir = _pack(_stage, id);
    await _ensureSafe(dir);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> promotePack(MascotDefinition mascot) async {
    return _withPackGate(mascot.id, () => _promotePack(mascot));
  }

  Future<void> _promotePack(MascotDefinition mascot) async {
    _ready();
    if (!identical(_known(mascot.id), mascot)) {
      throw ArgumentError('unknown_pack');
    }
    final staged = _pack(_stage, mascot.id);
    await _ensureSafe(staged);
    for (final clip in mascot.clips) {
      if (!await _verified(_clip(_stage, mascot.id, clip), clip)) {
        throw StateError('incomplete_pack');
      }
    }
    final marker = _marker(_stage, mascot.id);
    final markerType =
        await FileSystemEntity.type(marker.path, followLinks: false);
    if (markerType != FileSystemEntityType.notFound &&
        markerType != FileSystemEntityType.file) {
      throw StateError('unsafe_marker');
    }
    await marker.writeAsString('mascot-v1\n', flush: true);
    final installed = _pack(_installed, mascot.id);
    await _ensureSafe(installed);
    if (await installed.exists()) {
      if (await isInstalled(mascot.id)) {
        await discardStage(mascot.id);
        return;
      }
      if ((_leases[mascot.id] ?? 0) > 0) throw StateError('pack_in_use');
      await installed.delete(recursive: true);
    }
    await _mkdir(installed.parent);
    await staged.rename(installed.path);
  }

  Future<bool> isInstalled(String id) async {
    _ready();
    final mascot = _known(id);
    final dir = _pack(_installed, id);
    await _ensureSafe(dir);
    final marker = _marker(_installed, id);
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await marker.readAsString() != 'mascot-v1\n') {
      return false;
    }
    for (final clip in mascot.clips) {
      if (!await _verified(_clip(_installed, id, clip), clip)) return false;
    }
    return true;
  }

  Future<MascotStagedClip> beginPreview(MascotClip clip) async {
    _ready();
    if (clip.slot != 1 || clip.bytes > previewCap) {
      throw StateError('preview_not_allowed');
    }
    final id = _owner(clip);
    await _space(clip.bytes);
    final version = Directory('${_previews.path}${Platform.pathSeparator}v1');
    await _mkdir(version);
    await for (final child in version.list(followLinks: false)) {
      if (child is Link) throw StateError('unsafe_link');
      if (child is Directory && child.path != _pack(_previews, id).path) {
        await _ensureSafe(child);
        await child.delete(recursive: true);
      }
    }
    await _mkdir(_pack(_previews, id));
    final existing = _clip(_previews, id, clip);
    if (await FileSystemEntity.type(existing.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('unsafe_link');
    }
    if (await existing.exists()) await existing.delete();
    final file = File('${_clip(_previews, id, clip).path}.part');
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('unsafe_link');
    }
    if (await file.exists()) await file.delete();
    return MascotStagedClip._(file, clip, _verified, _ensureSafe);
  }

  Future<Uint8List?> readPreview(MascotClip clip) async {
    _ready();
    final file = _clip(_previews, _owner(clip), clip);
    if (!await _verified(file, clip)) return null;
    return file.readAsBytes();
  }

  Future<void> publishPreview(MascotClip clip) async {
    _ready();
    final id = _owner(clip);
    final file = _clip(_previews, id, clip);
    final part = File('${file.path}.part');
    if (!await _verified(part, clip)) throw StateError('invalid_preview');
    // A single verified first GIF fits the entire bounded preview cache.
    final version = file.parent.parent;
    await for (final child in version.list(followLinks: false)) {
      if (child is Link) throw StateError('unsafe_link');
      if (child is Directory && child.path != file.parent.path) {
        await child.delete(recursive: true);
      }
    }
    if (await file.exists()) await file.delete();
    await part.rename(file.path);
  }

  Future<bool> reusePreview(MascotClip clip) async {
    _ready();
    if (clip.slot != 1) return false;
    final id = _owner(clip);
    final source = _clip(_previews, id, clip);
    if (!await _verified(source, clip)) return false;
    final target = _clip(_stage, id, clip);
    await _ensureSafe(target.parent);
    if (!await target.parent.exists()) return false;
    if (await FileSystemEntity.type(target.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('unsafe_link');
    }
    await source.copy(target.path);
    return _verified(target, clip);
  }

  @override
  Future<MascotAssetLease> openVerifiedClip(MascotClip clip) async {
    final id = _owner(clip);
    return _withPackGate(id, () => _openVerifiedClip(clip, id));
  }

  Future<MascotAssetLease> _openVerifiedClip(MascotClip clip, String id) async {
    _ready();
    if (!await isInstalled(id)) throw StateError('pack_unavailable');
    final bytes = await _clip(_installed, id, clip).readAsBytes();
    if (bytes.length != clip.bytes || await _digest(bytes) != clip.sha256) {
      throw StateError('clip_corrupt');
    }
    _leases[id] = (_leases[id] ?? 0) + 1;
    return _FileMascotLease(bytes, () {
      _leases[id] = (_leases[id] ?? 1) - 1;
    });
  }

  Future<void> removePack(String id, {bool Function()? canRemove}) async {
    return _withPackGate(id, () => _removePack(id, canRemove));
  }

  Future<void> _removePack(String id, bool Function()? canRemove) async {
    _ready();
    _known(id);
    if (id == MascotCatalog.defaultId) throw StateError('bundled_pack');
    if ((_leases[id] ?? 0) > 0) throw StateError('pack_in_use');
    final dir = _pack(_installed, id);
    await _ensureSafe(dir);
    final exists = await dir.exists();
    if (canRemove != null && !canRemove()) throw StateError('selected_pack');
    if (exists) await dir.delete(recursive: true);
  }
}

class MascotStagedClip {
  MascotStagedClip._(this._file, this._clip, this._verify, this._ensureSafe);
  final File _file;
  final MascotClip _clip;
  final Future<bool> Function(File, MascotClip) _verify;
  final Future<void> Function(Directory) _ensureSafe;
  RandomAccessFile? _handle;
  int _written = 0;
  bool _finished = false;

  Future<void> write(List<int> chunk) async {
    if (_finished) throw StateError('writer_closed');
    if (_written + chunk.length > _clip.bytes) {
      throw StateError('size_mismatch');
    }
    await _ensureSafe(_file.parent);
    _handle ??= await _file.open(mode: FileMode.write);
    await _handle!.writeFrom(chunk);
    _written += chunk.length;
  }

  Future<void> finish() async {
    if (_finished) throw StateError('writer_closed');
    _finished = true;
    await _handle?.flush();
    await _handle?.close();
    if (!await _verify(_file, _clip)) throw StateError('integrity_mismatch');
  }

  Future<void> abort() async {
    _finished = true;
    await _handle?.close();
    await _ensureSafe(_file.parent);
    if (await _file.exists()) await _file.delete();
  }
}

class _FileMascotLease implements MascotAssetLease {
  _FileMascotLease(this.bytes, this._release);
  @override
  final Uint8List bytes;
  final void Function() _release;
  bool _closed = false;
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _release();
  }
}

Future<bool> _verify(File file, MascotClip clip) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    return false;
  }
  if (await file.length() != clip.bytes) return false;
  return await _digest(await file.readAsBytes()) == clip.sha256;
}

Future<String> _digest(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
}
