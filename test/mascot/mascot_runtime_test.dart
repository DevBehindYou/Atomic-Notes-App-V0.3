import 'dart:async';
import 'dart:io';
import 'package:atomic_notes/mascot/mascot_asset_resolver.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_preferences.dart';
import 'package:atomic_notes/mascot/mascot_runtime.dart';
import 'package:atomic_notes/mascot/mascot_view.dart';
import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bundle extends CachingAssetBundle {
  int reads = 0;
  bool corrupt = false;
  @override
  Future<ByteData> load(String key) async {
    reads++;
    final bytes = await File(key).readAsBytes();
    if (corrupt) bytes[bytes.length - 1] ^= 1;
    return ByteData.sublistView(bytes);
  }
}

class _PendingStore implements MascotPreferencesStore {
  final result = Completer<MascotPreferenceRead>();
  @override
  Future<MascotPreferenceRead> read() => result.future;
  @override
  Future<void> write(MascotPreferences value) async {}
}

class _Unavailable implements MascotAssetResolver {
  @override
  Future<MascotAssetLease> openVerifiedClip(MascotClip clip) async =>
      throw StateError('test-no-codec');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all 52 original clips resolve offline with a bounded encoded cache',
      () async {
    final bundle = _Bundle();
    final resolver = BundledMascotResolver(bundle: bundle);
    for (final mascot in MascotCatalog.all) {
      for (final clip in mascot.clips) {
        final lease = await resolver.openVerifiedClip(clip);
        expect(lease.bytes.length, clip.bytes);
        expect(() => lease.bytes[0] = 0, throwsUnsupportedError);
        expect(resolver.cachedBytes,
            lessThanOrEqualTo(BundledMascotResolver.maxCachedBytes));
        await lease.close();
      }
    }
    expect(bundle.reads, 52);
  });
  test('concurrent requests share one local read', () async {
    final bundle = _Bundle();
    final resolver = BundledMascotResolver(bundle: bundle);
    final clip = MascotCatalog.defaultMascot.clips.first;
    final leases = await Future.wait(
        List.generate(4, (_) => resolver.openVerifiedClip(clip)));
    expect(bundle.reads, 1);
    for (final lease in leases) {
      await lease.close();
    }
  });
  test('changed local bytes are rejected and explicit retry can recover',
      () async {
    final bundle = _Bundle()..corrupt = true;
    final resolver = BundledMascotResolver(bundle: bundle);
    final clip = MascotCatalog.all.first.clips.first;
    await expectLater(resolver.openVerifiedClip(clip), throwsStateError);
    bundle.corrupt = false;
    final lease = await resolver.openVerifiedClip(clip);
    expect(lease.bytes.length, clip.bytes);
    expect(bundle.reads, 2);
    await lease.close();
  });
  testWidgets('preference reads do not delay the app child', (tester) async {
    final store = _PendingStore();
    await tester.pumpWidget(MascotScope(
        preferencesStore: store,
        resolver: _Unavailable(),
        child: const MaterialApp(home: Text('notes-ready'))));
    expect(find.text('notes-ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.result.complete(const MascotPreferenceRead.missing());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('a non-default favorite updates the live app artwork',
      (tester) async {
    final store = _PendingStore()
      ..result.complete(const MascotPreferenceRead.missing());
    final scope = GlobalKey<MascotScopeState>();
    await tester.pumpWidget(MascotScope(
        key: scope,
        preferencesStore: store,
        resolver: _Unavailable(),
        child: const MaterialApp(home: DevBehindYouMascot())));
    await tester.pump();
    expect(MascotScope.maybeOf(tester.element(find.byType(DevBehindYouMascot))),
        same(scope.currentState));
    scope.currentState!.preferences.selectMascot('051-blink');
    expect(
        scope.currentState!.preferences.state.desired.selectedId, '051-blink');
    await tester.pump();
    await tester.pump();
    expect(tester.widget<MascotView>(find.byType(MascotView)).mascot.id,
        '051-blink');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
