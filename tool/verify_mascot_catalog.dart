// Run: dart run tool/verify_mascot_catalog.dart [authoritative-manifest.json]
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main(List<String> args) async {
  Future<String> digest(List<int> bytes) async => (await Sha256().hash(bytes))
      .bytes
      .map((v) => v.toRadixString(16).padLeft(2, '0'))
      .join();
  final pinned =
      jsonDecode(File('docs/mascot/catalog-v1.json').readAsStringSync()) as Map;
  final records = pinned['clips'] as List;
  final clips = MascotCatalog.all.expand((m) => m.clips).toList();
  require(
      MascotCatalog.all.length == 13 && clips.length == 52, '13 x 4 required');
  final ids = <String>{};
  for (var i = 0; i < clips.length; i++) {
    final c = clips[i];
    final m = records[i] as Map;
    require(ids.add(c.id), 'duplicate clip');
    require(
        c.sourcePath.startsWith('assets/Atomic Notes Mascot/') &&
            !c.sourcePath.contains('..') &&
            !c.sourcePath.contains('\\'),
        'unsafe path');
    final actual = {
      'mascot_id': MascotCatalog.all.firstWhere((d) => d.clips.contains(c)).id,
      'asset_id': c.id,
      'slot': c.slot,
      'bytes': c.bytes,
      'sha256': c.sha256,
      'width': c.width,
      'height': c.height,
      'frame_count': c.frameCount,
      'total_cycle_ms': c.encodedCycleDuration.inMilliseconds,
      'asset_path_from_app_root': c.sourcePath,
    };
    require(jsonEncode(actual) == jsonEncode(m),
        'catalog metadata mismatch: ${c.id}');
    require(c.originalFilename == '${c.id}.gif', 'filename mismatch');
    require(c.bundledAssetPath == c.sourcePath, 'every clip must be bundled');
    {
      final bytes = File(c.bundledAssetPath).readAsBytesSync();
      require(bytes.length == c.bytes && await digest(bytes) == c.sha256,
          'bundled hash mismatch: ${c.id}');
    }
  }
  final expected = clips.map((c) => c.sourcePath).toSet();
  final actual = Directory('assets/Atomic Notes Mascot')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/'))
      .toSet();
  require(
      expected.length == 52 &&
          actual.length == 52 &&
          actual.containsAll(expected),
      'unexpected bundled mascot files');
  final yaml = File('pubspec.yaml').readAsStringSync();
  for (final directory
      in expected.map((p) => p.substring(0, p.lastIndexOf('/') + 1)).toSet()) {
    require(yaml.contains('    - $directory'),
        'bundle declaration missing: $directory');
  }
  if (args.isNotEmpty) {
    final source = File(args.single).readAsBytesSync();
    require(await digest(source) == pinned['sourceManifestSha256'],
        'source manifest changed');
    final sourceRecords =
        (jsonDecode(utf8.decode(source)) as Map)['assets'] as List;
    require(sourceRecords.length == records.length, 'source record count');
    for (var i = 0; i < records.length; i++) {
      for (final key in (records[i] as Map).keys) {
        require(records[i][key] == sourceRecords[i][key],
            'source mismatch: $i $key');
      }
    }
  }
  stdout.writeln(
      'Verified 13 mascots / 52 clips; all 52 GIFs bundled / 18721297 bytes.');
}
