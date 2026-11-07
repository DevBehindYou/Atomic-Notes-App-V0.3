import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/recovery/archive_manifest.dart';
import 'package:atomic_notes/recovery/export_writer.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

final _time = DateTime.utc(2026, 11, 7, 10);
const _vault = ArchiveVault(
    encVersion: 1, kdfMemory: 65536, kdfIterations: 3, kdfParallelism: 1);

List<ArchiveSource> _sources() => [
      for (var i = 1; i <= 3; i++)
        ArchiveSource(Note(
            id: '0000000$i-0000-4000-8000-00000000000$i',
            title: 'Note $i',
            body: 'Body $i ${'x' * (i * 100)}',
            createdAt: _time,
            updatedAt: _time)),
      ArchiveSource(
          Note(
              id: '00000009-0000-4000-8000-000000000009',
              createdAt: _time,
              updatedAt: _time),
          sealedPayload: 'sealed-vault-payload'),
    ];

ArchiveKey _key([int seed = 1]) {
  final random = Random(seed);
  return ArchiveKey.forTesting(
      SecretKey(List<int>.generate(32, (_) => random.nextInt(256))),
      List<int>.generate(16, (_) => random.nextInt(256)));
}

/// A file target that fails like a full disk once [budget] bytes are written,
/// and can run [onWrite] before each write.
class _LimitedTarget extends FileExportTarget {
  _LimitedTarget(super.file, {this.budget = 1 << 30, this.onWrite});
  final int budget;
  final void Function(int written)? onWrite;
  int written = 0;
  int largestWrite = 0;
  @override
  Future<void> write(List<int> bytes) async {
    onWrite?.call(written);
    if (written + bytes.length > budget) {
      throw const FileSystemException('No space left on device');
    }
    written += bytes.length;
    largestWrite = max(largestWrite, bytes.length);
    await super.write(bytes);
  }
}

typedef _Read = ({
  ArchiveHeader header,
  ArchiveManifest manifest,
  List<ArchivedNote> notes,
});

Future<_Read> _read(List<int> bytes, {ArchiveKey? key}) async {
  final reader = ArchiveReader(ArchiveByteSource.bytes(bytes));
  final header = await reader.readHeader();
  if (key != null) reader.useKey(key);
  final manifest = await reader.readManifest();
  final notes = [
    for (final entry in manifest.entries) await reader.readEntry(entry)
  ];
  await reader.readTrailer(manifest);
  return (header: header, manifest: manifest, notes: notes);
}

Matcher _code(String code) =>
    throwsA(isA<ArchiveFormatException>().having((e) => e.code, 'code', code));

void main() {
  late Directory directory;
  late File target;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-export-');
    target = File('${directory.path}/notes.atna');
  });
  tearDown(() => directory.delete(recursive: true));

  List<String> leftovers() => directory
      .listSync()
      .map((e) => e.uri.pathSegments.last)
      .where((name) => name.contains(ArchiveContainer.partialSuffix))
      .toList();

  Future<Uint8List> export({ArchiveKey? key}) async {
    await ExportWriter(clock: () => _time)
        .write(FileExportTarget(target), _sources(), key: key, vault: _vault);
    return target.readAsBytes();
  }

  group('round trip', () {
    test('plain export reads back exactly, from the file, in order', () async {
      final result = await ExportWriter(clock: () => _time)
          .write(FileExportTarget(target), _sources(), vault: _vault);
      expect(result.bytesWritten, await target.length());
      expect(leftovers(), isEmpty);
      final handle = await target.open();
      addTearDown(handle.close);
      final reader = ArchiveReader(ArchiveByteSource.file(handle));
      expect((await reader.readHeader()).encrypted, isFalse);
      final manifest = await reader.readManifest();
      expect(manifest.toJson(), result.manifest.toJson());
      final sources = _sources();
      for (var i = 0; i < manifest.entries.length; i++) {
        final note = await reader.readEntry(manifest.entries[i]);
        expect(note.note.title, sources[i].note.title);
        expect(note.note.body, sources[i].note.body);
        expect(note.payload, sources[i].sealedPayload);
      }
      await reader.readTrailer(manifest);
    });

    test('encrypted export needs the same key and stores no secret', () async {
      final key = _key();
      final bytes = await export(key: key);
      final read = await _read(bytes, key: key);
      expect(read.header.encrypted, isTrue);
      expect(read.header.salt, key.salt);
      expect(read.notes.map((n) => n.note.title),
          ['Note 1', 'Note 2', 'Note 3', '']);
      final text = latin1.decode(bytes);
      expect(text, isNot(contains('Note 1')));
      expect(text, isNot(contains('sealed-vault-payload')));
      final keyBytes = await key.key.extractBytes();
      expect(_indexOf(bytes, keyBytes), -1);

      final reader = ArchiveReader(ArchiveByteSource.bytes(bytes));
      await reader.readHeader();
      await expectLater(reader.readManifest(), _code('key_required'));
      await expectLater(
          _read(bytes, key: _key(2)), _code('authentication_failed'));
    });

    test('a real export password derives the same key from the header',
        () async {
      final key =
          await ArchiveKey.create('correct horse battery', random: Random(7));
      final bytes = await export(key: key);
      final reader = ArchiveReader(ArchiveByteSource.bytes(bytes));
      final header = await reader.readHeader();
      expect([header.memory, header.iterations, header.parallelism],
          [65536, 3, 1]);
      final again = await ArchiveKey.derive(
          'correct horse battery', header.salt!,
          memory: header.memory,
          iterations: header.iterations,
          parallelism: header.parallelism);
      expect((await _read(bytes, key: again)).notes, hasLength(4));
      final wrong = await ArchiveKey.derive('wrong password', header.salt!,
          memory: header.memory,
          iterations: header.iterations,
          parallelism: header.parallelism);
      await expectLater(
          _read(bytes, key: wrong), _code('authentication_failed'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('tamper and truncation', () {
    test('any changed byte of an encrypted archive is detected', () async {
      final key = _key();
      final bytes = await export(key: key);
      // Every 37th byte plus the last, covering header, lengths, every frame
      // and the trailer.
      for (final i in [
        for (var i = 0; i < bytes.length; i += 37) i,
        bytes.length - 1
      ]) {
        final changed = Uint8List.fromList(bytes)..[i] ^= 0x01;
        await expectLater(
            _read(changed, key: key), throwsA(isA<ArchiveFormatException>()),
            reason: 'byte $i');
      }
    });

    test('a changed entry in a plain archive fails its checksum', () async {
      final bytes = await export();
      final at = _indexOf(bytes, utf8.encode('Body 2'));
      final changed = Uint8List.fromList(bytes)..[at] ^= 0x01;
      await expectLater(_read(changed), _code('invalid_checksum'));
    });

    test('swapped frames are refused in both modes', () async {
      for (final key in [null, _key()]) {
        final bytes = await export(key: key);
        final frames = _frames(bytes, headerLength: key == null ? 6 : 32);
        final swapped = [
          ...bytes.sublist(0, key == null ? 6 : 32),
          ...frames[0],
          ...frames[2],
          ...frames[1],
          ...frames.skip(3).expand((f) => f),
        ];
        await expectLater(
            _read(swapped, key: key), throwsA(isA<ArchiveFormatException>()));
      }
    });

    test('a truncated archive or trailing data is refused', () async {
      for (final key in [null, _key()]) {
        final bytes = await export(key: key);
        for (final cut in [3, 20, bytes.length ~/ 2, bytes.length - 1]) {
          await expectLater(_read(bytes.sublist(0, cut), key: key),
              throwsA(isA<ArchiveFormatException>()),
              reason: 'cut at $cut');
        }
        // Dropping the trailer frame leaves a structurally valid prefix.
        final frames = _frames(bytes, headerLength: key == null ? 6 : 32);
        final withoutTrailer =
            bytes.sublist(0, bytes.length - frames.last.length);
        await expectLater(_read(withoutTrailer, key: key), _code('truncated'));
        await expectLater(_read([...bytes, 0], key: key), _code('malformed'));
      }
    });

    test('hostile lengths and key settings are refused before allocating',
        () async {
      final plain = await export();
      final huge = Uint8List.fromList(plain)
        ..setRange(6, 10, [0xff, 0xff, 0xff, 0xff]);
      await expectLater(_read(huge), _code('limit_exceeded'));
      final encrypted = await export(key: _key());
      final heavy = Uint8List.fromList(encrypted)
        ..setRange(7, 11, [0xff, 0xff, 0xff, 0xff]); // Argon2 memory
      final reader = ArchiveReader(ArchiveByteSource.bytes(heavy));
      await expectLater(reader.readHeader(), _code('malformed'));
      await expectLater(
          _read(utf8.encode('PK\u0003\u0004 not ours')), _code('malformed'));
    });
  });

  group('failure never leaves a partial backup', () {
    test('a full disk keeps the previous export and leaves no partial file',
        () async {
      await target.writeAsString('previous export');
      for (final budget in [0, 10, 300, 900]) {
        await expectLater(
            ExportWriter(clock: () => _time).write(
                _LimitedTarget(target, budget: budget), _sources(),
                vault: _vault),
            throwsA(isA<ExportFailed>()));
        expect(await target.readAsString(), 'previous export');
        expect(leftovers(), isEmpty, reason: 'budget $budget');
      }
    });

    test('an invalid export is refused before any file is created', () async {
      // A sealed note without vault parameters could never be restored.
      await expectLater(
          ExportWriter(clock: () => _time)
              .write(FileExportTarget(target), _sources()),
          _code('malformed'));
      expect(await target.exists(), isFalse);
      expect(leftovers(), isEmpty);
    });

    test('cancel stops between entries and leaves nothing behind', () async {
      final cancel = ExportCancel();
      final writer = ExportWriter(clock: () => _time);
      await expectLater(
          writer.write(
              _LimitedTarget(target, onWrite: (written) {
                if (written > 200) cancel.cancel();
              }),
              _sources(),
              vault: _vault,
              cancel: cancel),
          throwsA(isA<ExportCancelled>()));
      expect(await target.exists(), isFalse);
      expect(leftovers(), isEmpty);
    });

    test('edits after the export starts do not change it', () async {
      final sources = _sources();
      final writer = ExportWriter(clock: () => _time);
      final export = writer.write(
          _LimitedTarget(target, onWrite: (_) {
            sources.first.note.title = 'Edited during export';
          }),
          sources,
          vault: _vault);
      await export;
      final read = await _read(await target.readAsBytes());
      expect(read.notes.first.note.title, 'Note 1');
    });

    test('writes are one frame at a time, bounded by the largest entry',
        () async {
      final measuring = _LimitedTarget(target);
      await ExportWriter(clock: () => _time)
          .write(measuring, _sources(), key: _key(), vault: _vault);
      expect(measuring.largestWrite,
          lessThanOrEqualTo(ArchiveLimits.maxManifestBytes + 28));
      expect(measuring.largestWrite, lessThan(4096),
          reason: 'small notes produce small frames');
    });
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

/// Splits the frames after a header of [headerLength] bytes.
List<List<int>> _frames(List<int> bytes, {required int headerLength}) {
  final frames = <List<int>>[];
  var offset = headerLength;
  while (offset < bytes.length) {
    final length =
        ByteData.sublistView(Uint8List.fromList(bytes), offset, offset + 4)
            .getUint32(0);
    frames.add(bytes.sublist(offset, offset + 4 + length));
    offset += 4 + length;
  }
  return frames;
}
