import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';

import 'hive_mascot_preferences.dart';
import 'mascot_asset_resolver.dart';
import 'mascot_catalog.dart';
import 'mascot_cubit.dart';
import 'mascot_preferences.dart';

/// Reads only app-bundled, catalog-pinned bytes. No network or native storage.
class BundledMascotResolver implements MascotAssetResolver {
  BundledMascotResolver({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  static final BundledMascotResolver instance = BundledMascotResolver();
  static const maxCachedBytes = 4 * 1024 * 1024;
  final AssetBundle _bundle;
  final _cache = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List>>{};
  int _cachedBytes = 0;
  @visibleForTesting
  int get cachedBytes => _cachedBytes;

  @override
  Future<MascotAssetLease> openVerifiedClip(MascotClip clip) async {
    if (!MascotCatalog.all.any((m) => m.clips.contains(clip))) {
      throw ArgumentError.value(
          clip.id, 'clip', 'Not an app-pinned mascot clip');
    }
    final cached = _cache.remove(clip.id);
    if (cached != null) {
      _cache[clip.id] = cached;
      return _MemoryMascotLease(cached);
    }
    final bytes = await (_pending[clip.id] ??= _load(clip).whenComplete(() {
      _pending.remove(clip.id);
    }));
    return _MemoryMascotLease(bytes);
  }

  Future<Uint8List> _load(MascotClip clip) async {
    final data = await _bundle.load(clip.bundledAssetPath);
    final raw = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (raw.length != clip.bytes) throw StateError('bundled_clip_corrupt');
    final digest = (await Sha256().hash(raw))
        .bytes
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    if (digest != clip.sha256) throw StateError('bundled_clip_corrupt');
    final bytes = Uint8List.fromList(raw).asUnmodifiableView();
    while (_cache.isNotEmpty && _cachedBytes + bytes.length > maxCachedBytes) {
      _cachedBytes -= _cache.remove(_cache.keys.first)!.length;
    }
    if (bytes.length <= maxCachedBytes) {
      _cache[clip.id] = bytes;
      _cachedBytes += bytes.length;
    }
    return bytes;
  }
}

class _MemoryMascotLease implements MascotAssetLease {
  const _MemoryMascotLease(this.bytes);
  @override
  final Uint8List bytes;
  @override
  Future<void> close() async {}
}

/// Preference reads never delay navigation or require an account or connection.
class MascotScope extends StatefulWidget {
  const MascotScope(
      {super.key, required this.child, this.preferencesStore, this.resolver});
  final Widget child;
  final MascotPreferencesStore? preferencesStore;
  final MascotAssetResolver? resolver;
  static MascotScopeState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<MascotScopeState>();
  @override
  State<MascotScope> createState() => MascotScopeState();
}

class MascotScopeState extends State<MascotScope> {
  late final MascotPreferencesStore _store;
  late final MascotCubit preferences;
  late final MascotAssetResolver resolver;
  @override
  void initState() {
    super.initState();
    _store = widget.preferencesStore ??
        HiveMascotPreferencesStore.openBox(
            () => Hive.openBox<dynamic>(HiveMascotPreferencesStore.boxName));
    preferences = MascotCubit(_store);
    resolver = widget.resolver ?? BundledMascotResolver.instance;
    unawaited(preferences.load());
  }

  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    unawaited(preferences.close().catchError((Object _) {}));
    final store = _store;
    if (widget.preferencesStore == null &&
        store is HiveMascotPreferencesStore) {
      unawaited(store.close().catchError((Object _) {}));
    }
    super.dispose();
  }
}
