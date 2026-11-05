import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';

void main() {
  test('catalog has seven immutable four-clip definitions', () {
    expect(MascotCatalog.all, hasLength(7));
    expect(MascotCatalog.all.map((m) => m.id).toSet(), hasLength(7));
    expect(() => MascotCatalog.all.clear(), throwsUnsupportedError);
    expect(MascotCatalog.all.map((m) => m.displayName).toSet(),
        {'Tilde', 'Antimatter', 'Rocco', 'Lappy', 'Pocket', 'Hoot', 'Vaulty'});
    final ids = <String>{};
    for (final mascot in MascotCatalog.all) {
      expect(mascot.clips.map((c) => c.slot), [1, 2, 3, 4]);
      expect(() => mascot.clips.clear(), throwsUnsupportedError);
      for (final clip in mascot.clips) {
        expect(ids.add(clip.id), isTrue);
        expect(clip.sourcePath, startsWith('assets/Atomic Notes Mascot/'));
        expect(clip.sourcePath.contains('..'), isFalse);
        expect(clip.originalFilename, '${clip.id}.gif');
        expect(clip.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(clip.bytes, greaterThan(0));
        expect(clip.width, 480);
        expect(clip.height, 480);
        expect(clip.frameCount, greaterThan(0));
        expect(clip.encodedCycleDuration.inMilliseconds, greaterThan(0));
        expect(clip.bundledAssetPath, clip.sourcePath);
      }
    }
    expect(ids, hasLength(28));
    expect(MascotCatalog.all.fold<int>(0, (sum, m) => sum + m.encodedBytes),
        9906906);
  });
  test('Hoot is the default and every supplied clip is bundled', () {
    expect(MascotCatalog.defaultMascot.id, '066-hoot');
    expect(MascotCatalog.defaultMascot.encodedBytes, 2987001);
    expect(MascotCatalog.findById('unknown'), isNull);
    expect(
        MascotCatalog.findById('066-hoot'), same(MascotCatalog.defaultMascot));
  });
}
