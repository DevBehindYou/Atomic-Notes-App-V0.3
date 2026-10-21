import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import 'file_mascot_pack_store.dart';
import 'mascot_asset_resolver.dart';
import 'mascot_catalog.dart';
import 'mascot_download_client.dart';
import 'mascot_pack_state.dart';

/// One explicit user operation at a time. Playback always resolves local bytes.
class MascotPackRepository extends MascotPackSource {
  MascotPackRepository({
    required this.store,
    required this.downloads,
    AssetBundle? bundle,
    String Function()? selectedId,
  })  : _bundle = bundle ?? rootBundle,
        _selectedId = selectedId;

  final FileMascotPackStore store;
  final MascotDownloadClient downloads;
  final AssetBundle _bundle;
  final String Function()? _selectedId;
  final Map<String, MascotPackState> _states = {};
  MascotCancellation? _cancellation;
  Future<void>? _active;
  Completer<void>? _removeDone;
  Completer<void>? _opensDone;
  Completer<void>? _closeDone;
  int _pendingOpens = 0;
  bool _removing = false;
  String? _removingId;
  bool _closing = false;
  bool _initialized = false;
  bool _closed = false;

  MascotDefinition _known(String id) =>
      MascotCatalog.findById(id) ?? (throw ArgumentError.value(id, 'id'));

  @override
  MascotPackState stateFor(String id) {
    _known(id);
    if (id == MascotCatalog.defaultId) {
      return MascotPackState(id: id, status: MascotPackStatus.included);
    }
    if (id == _removingId) {
      return MascotPackState(id: id, status: MascotPackStatus.absent);
    }
    return _states[id] ??
        MascotPackState(id: id, status: MascotPackStatus.absent);
  }

  void _set(String id, MascotPackStatus status,
      {int received = 0,
      int total = 0,
      String? errorCode,
      Uint8List? previewBytes}) {
    if (_closed) return;
    _states[id] = MascotPackState(
        id: id,
        status: status,
        received: received,
        total: total,
        errorCode: errorCode,
        previewBytes: previewBytes);
    notifyListeners();
  }

  @override
  Future<void> initialize() async {
    if (_closed || _closing) throw StateError('repository_closed');
    if (_initialized) return;
    await store.initialize();
    for (final mascot in MascotCatalog.all) {
      if (mascot.id == MascotCatalog.defaultId) continue;
      if (await store.isInstalled(mascot.id)) {
        _set(mascot.id, MascotPackStatus.installed);
      } else {
        final bytes = await store.readPreview(mascot.clips.first);
        if (bytes != null) {
          _set(mascot.id, MascotPackStatus.previewed, previewBytes: bytes);
        }
      }
    }
    _initialized = true;
  }

  void _ready() {
    if (_closed || _closing) throw StateError('repository_closed');
    if (!_initialized) throw StateError('repository_not_initialized');
  }

  Future<void> _run(
      String id, Future<void> Function(MascotCancellation) work) async {
    _ready();
    if (_active != null || _removing) throw StateError('download_in_progress');
    final cancellation = MascotCancellation();
    final activeDone = Completer<void>();
    _cancellation = cancellation;
    _active = activeDone.future;
    try {
      await work(cancellation);
    } on MascotDownloadException catch (e) {
      if (e.code == 'cancelled') {
        _set(id, MascotPackStatus.absent);
      } else {
        _set(id, MascotPackStatus.failed, errorCode: e.code);
      }
    } on StateError catch (e) {
      _set(id, MascotPackStatus.failed, errorCode: e.message.toString());
    } catch (_) {
      _set(id, MascotPackStatus.failed, errorCode: 'storage_failed');
    } finally {
      _active = null;
      _cancellation = null;
      activeDone.complete();
    }
  }

  Future<void> _downloadClip(MascotClip clip, MascotCancellation cancellation,
      {required bool preview, void Function(int, int)? progress}) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      cancellation.check();
      final writer = preview
          ? await store.beginPreview(clip)
          : await store.beginClip(clip);
      try {
        await downloads.download(clip,
            write: writer.write,
            cancellation: cancellation,
            onProgress: progress);
        cancellation.check();
        await writer.finish();
        return;
      } on MascotDownloadException catch (e) {
        await writer.abort();
        if (!e.retryable || attempt == 2) rethrow;
        final delay = e.retryAfter > const Duration(seconds: 30)
            ? const Duration(seconds: 30)
            : e.retryAfter;
        await cancellation.race(Future<void>.delayed(delay));
      } catch (_) {
        await writer.abort();
        rethrow;
      }
    }
  }

  @override
  Future<void> preview(String id) async {
    final mascot = _known(id);
    if (id == MascotCatalog.defaultId) return;
    await _run(id, (cancellation) async {
      if (await store.isInstalled(id)) {
        _set(id, MascotPackStatus.installed);
        return;
      }
      final clip = mascot.clips.first;
      final cached = await store.readPreview(clip);
      if (cached != null) {
        _set(id, MascotPackStatus.previewed, previewBytes: cached);
        return;
      }
      _set(id, MascotPackStatus.downloading, total: clip.bytes);
      _dropOtherPreviews(id);
      await _downloadClip(clip, cancellation, preview: true,
          progress: (received, total) {
        _set(id, MascotPackStatus.downloading,
            received: received, total: total);
      });
      cancellation.check();
      _set(id, MascotPackStatus.verifying);
      await store.publishPreview(clip);
      cancellation.check();
      _set(id, MascotPackStatus.previewed,
          previewBytes: await store.readPreview(clip));
    });
  }

  @override
  Future<void> downloadAndInstall(String id) async {
    final mascot = _known(id);
    if (id == MascotCatalog.defaultId) return;
    await _run(id, (cancellation) async {
      if (await store.isInstalled(id)) {
        _set(id, MascotPackStatus.installed);
        return;
      }
      await store.startPack(mascot);
      var completed = 0;
      _set(id, MascotPackStatus.downloading, total: mascot.encodedBytes);
      for (final clip in mascot.clips) {
        cancellation.check();
        if (await store.hasStagedClip(clip) || await store.reusePreview(clip)) {
          completed += clip.bytes;
        } else {
          await store.discardStagedClip(clip);
          await _downloadClip(clip, cancellation, preview: false,
              progress: (received, total) {
            _set(id, MascotPackStatus.downloading,
                received: completed + received, total: mascot.encodedBytes);
          });
          completed += clip.bytes;
        }
        _set(id, MascotPackStatus.downloading,
            received: completed, total: mascot.encodedBytes);
      }
      cancellation.check();
      _set(id, MascotPackStatus.verifying,
          received: completed, total: mascot.encodedBytes);
      await store.promotePack(mascot);
      if (cancellation.isCancelled) {
        await store.removePack(id);
        cancellation.check();
      }
      _set(id, MascotPackStatus.installed,
          received: completed, total: mascot.encodedBytes);
    });
  }

  @override
  void cancel() => _cancellation?.cancel();

  void _dropOtherPreviews(String keepId) {
    for (final entry in _states.entries.toList()) {
      if (entry.key != keepId && entry.value.previewBytes != null) {
        _set(entry.key, MascotPackStatus.absent);
      }
    }
  }

  @override
  Future<void> remove(String id, {required String selectedId}) async {
    _ready();
    _known(id);
    if (id == MascotCatalog.defaultId ||
        id == selectedId ||
        id == _selectedId?.call()) {
      throw StateError('selected_pack');
    }
    if (_active != null || _removing) {
      throw StateError('download_in_progress');
    }
    _removing = true;
    _removingId = id;
    final done = Completer<void>();
    _removeDone = done;
    notifyListeners();
    try {
      await store.removePack(id,
          canRemove: () => id != selectedId && id != _selectedId?.call());
      final preview = await store.readPreview(_known(id).clips.first);
      _set(
          id,
          preview == null
              ? MascotPackStatus.absent
              : MascotPackStatus.previewed,
          previewBytes: preview);
    } finally {
      _removing = false;
      _removingId = null;
      _removeDone = null;
      if (!_closed && !_closing) notifyListeners();
      done.complete();
    }
  }

  @override
  Future<MascotAssetLease> openVerifiedClip(MascotClip clip) async {
    _ready();
    if (_pendingOpens++ == 0) _opensDone = Completer<void>();
    try {
      return await _openVerifiedClip(clip);
    } finally {
      if (--_pendingOpens == 0) {
        _opensDone?.complete();
        _opensDone = null;
      }
    }
  }

  Future<MascotAssetLease> _openVerifiedClip(MascotClip clip) async {
    final id = MascotCatalog.all
        .where((mascot) => mascot.clips.contains(clip))
        .map((mascot) => mascot.id)
        .firstOrNull;
    if (id == null) throw ArgumentError.value(clip.id, 'clip');
    if (id == MascotCatalog.defaultId) {
      final data = await _bundle.load(clip.bundledAssetPath!);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.length != clip.bytes) throw StateError('bundled_clip_corrupt');
      final digest = (await Sha256().hash(bytes))
          .bytes
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join();
      if (digest != clip.sha256) throw StateError('bundled_clip_corrupt');
      return _BundledLease(bytes);
    }
    try {
      return await store.openVerifiedClip(clip);
    } on StateError {
      _set(id, MascotPackStatus.failed, errorCode: 'pack_unavailable');
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    if (_closing) {
      await _closeDone?.future;
      return;
    }
    _closing = true;
    final done = Completer<void>();
    _closeDone = done;
    cancel();
    try {
      await _active;
    } catch (_) {
      // The public operation maps its error to state before close returns.
    }
    await _removeDone?.future;
    await _opensDone?.future;
    if (!_closed) {
      _closed = true;
      super.dispose();
    }
    if (!done.isCompleted) done.complete();
  }

  @override
  void dispose() {
    if (_closed) return;
    cancel();
    _closing = true;
    _closed = true;
    super.dispose();
    if (_closeDone != null && !_closeDone!.isCompleted) {
      _closeDone!.complete();
    }
  }
}

class _BundledLease implements MascotAssetLease {
  _BundledLease(this.bytes);
  @override
  final Uint8List bytes;
  @override
  Future<void> close() async {}
}
