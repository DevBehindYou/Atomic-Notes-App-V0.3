import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/recovery/archive_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

final _created = DateTime.utc(2026, 11, 1, 9, 30);
final _updated = DateTime.utc(2026, 11, 2, 18, 5, 7, 123);
const _vault = ArchiveVault(
    encVersion: 1, kdfMemory: 65536, kdfIterations: 3, kdfParallelism: 1);

Note _note(String id, {bool deleted = false}) => Note(
    id: id,
    title: 'Plan',
    body: 'First line',
    deleted: deleted,
    createdAt: _created,
    updatedAt: _updated,
    // Device sync state, which an archive must never carry.
    dirty: true,
    serverVersion: 41,
    syncedSig: 'device-sync-signature');

/// The fixtures cover each stored shape: plain text, checklist, rich mixed
/// document with tags and an image, tombstone and a sealed device row.
List<(Note, String?)> _fixtures() {
  final rich = NoteDocument.fromNote(Note(
      id: '33333333-3333-4333-8333-333333333333',
      title: 'Rich',
      body: 'Text then image',
      createdAt: _created,
      updatedAt: _updated));
  rich.setTags(['work', '\u{1F468}‍\u{1F469}']);
  rich.insertImageAfter(
      0, base64Encode(image.encodeJpg(image.Image(width: 16, height: 8))));
  final richNote = rich.toNote(Note(
      id: '33333333-3333-4333-8333-333333333333',
      title: 'Rich',
      createdAt: _created,
      updatedAt: _updated));
  return [
    (_note('11111111-1111-4111-8111-111111111111'), null),
    (
      Note(
          id: '22222222-2222-4222-8222-222222222222',
          kind: NoteKind.todo,
          items: [
            TodoItem(text: 'Buy milk'),
            TodoItem(text: 'Ship', done: true)
          ],
          pinned: true,
          important: true,
          createdAt: _created,
          updatedAt: _updated),
      null
    ),
    (richNote, null),
    (_note('44444444-4444-4444-8444-444444444444', deleted: true), null),
    (
      Note(
          id: '55555555-5555-4555-8555-555555555555',
          createdAt: _created,
          updatedAt: _updated),
      'sealed-vault-payload'
    ),
  ];
}

Map<String, Object?> _manifestJson() {
  final entries = [
    for (final (note, payload) in _fixtures())
      ArchiveNoteCodec.encode(note, sealedPayload: payload).$2
  ];
  return ArchiveManifest(
          createdAt: DateTime.utc(2026, 11, 7), entries: entries, vault: _vault)
      .toJson();
}

List<int> _bytes(Object? json) => utf8.encode(jsonEncode(json));

void _rejects(Object? json, String code) => expect(
    () => ArchiveManifest.parse(_bytes(json)),
    throwsA(isA<ArchiveFormatException>().having((e) => e.code, 'code', code)));

void main() {
  group('golden round trip', () {
    test('every stored shape survives encode, manifest and decode', () {
      final contents = <String, List<int>>{};
      final entries = <ArchiveEntry>[];
      for (final (note, payload) in _fixtures()) {
        final (bytes, entry) =
            ArchiveNoteCodec.encode(note, sealedPayload: payload);
        contents[entry.path] = bytes;
        entries.add(entry);
      }
      final manifest = ArchiveManifest(
          createdAt: DateTime.utc(2026, 11, 7),
          entries: entries,
          vault: _vault);
      final parsed = ArchiveManifest.parse(manifest.encode());
      expect(parsed.toJson(), manifest.toJson());
      expect(parsed.vault!.kdfMemory, 65536);

      final fixtures = _fixtures();
      for (var i = 0; i < parsed.entries.length; i++) {
        final entry = parsed.entries[i];
        final restored = ArchiveNoteCodec.decode(contents[entry.path]!, entry);
        final (original, payload) = fixtures[i];
        expect(restored.payload, payload);
        // Content, identity and dates are exact; device sync state is reset.
        final expected = original.toMap()
          ..['dirty'] = false
          ..['serverVersion'] = 0
          ..['syncedSig'] = '';
        expect(restored.note.toMap(), expected);
      }
      final rich = NoteDocument.fromNote(ArchiveNoteCodec.decode(
              contents[parsed.entries[2].path]!, parsed.entries[2])
          .note);
      expect(rich.tags, ['work', '\u{1F468}‍\u{1F469}']);
      expect(rich.imageCount, 1);
    });

    test('the entry format is pinned', () {
      final (bytes, entry) = ArchiveNoteCodec.encode(
          _note('11111111-1111-4111-8111-111111111111'));
      expect(
          utf8.decode(bytes),
          '{"id":"11111111-1111-4111-8111-111111111111","kind":"text",'
          '"title":"Plan","body":"First line","items":[],"pinned":false,'
          '"important":false,"deleted":false,'
          '"createdAt":"2026-11-01T09:30:00.000Z",'
          '"updatedAt":"2026-11-02T18:05:07.123Z"}');
      expect(entry.toJson(), {
        'id': '11111111-1111-4111-8111-111111111111',
        'path': 'notes/11111111-1111-4111-8111-111111111111.json',
        'kind': 'text',
        'deleted': false,
        'sealed': false,
        'bytes': bytes.length,
        'sha256': ArchiveNoteCodec.sha256Hex(bytes),
        'updatedAt': '2026-11-02T18:05:07.123Z',
      });
    });

    test('no device sync state, token or key material is written', () {
      final all = utf8.decode([
        ...ArchiveManifest(
                createdAt: DateTime.utc(2026, 11, 7),
                entries: const [],
                vault: _vault)
            .encode(),
        for (final (note, payload) in _fixtures())
          ...ArchiveNoteCodec.encode(note, sealedPayload: payload).$1,
      ]);
      for (final secret in [
        'device-sync-signature',
        'syncedSig',
        'serverVersion',
        'dirty',
        'token',
        'verifier',
        'phrase',
      ]) {
        expect(all, isNot(contains(secret)));
      }
    });
  });

  group('manifest rejection', () {
    test('a newer major version or unknown requirement is unsupported', () {
      _rejects({..._manifestJson(), 'version': 2}, 'unsupported_version');
      _rejects({
        ..._manifestJson(),
        'requires': ['delta-entries']
      }, 'unsupported_version');
      _rejects({..._manifestJson(), 'format': 'zip'}, 'malformed');
    });

    test('unknown fields are refused, except under ext', () {
      _rejects({..._manifestJson(), 'sessionToken': 'x'}, 'unknown_field');
      final json = _manifestJson();
      (json['entries'] as List).first['token'] = 'x';
      _rejects(json, 'unknown_field');
      expect(
          ArchiveManifest.parse(_bytes({
            ..._manifestJson(),
            'ext': {'futureOptionalData': true}
          })).entries,
          hasLength(5));
    });

    test('duplicate note ids are refused, including case variants', () {
      final json = _manifestJson();
      final entries = json['entries'] as List;
      entries.add(Map<String, Object>.from(entries.first as Map));
      _rejects(json, 'duplicate_id');
      final upper = Map<String, Object>.from(entries.first as Map);
      upper['id'] = (upper['id'] as String).toUpperCase();
      upper['path'] = 'notes/${upper['id']}.json';
      _rejects({
        ..._manifestJson(),
        'entries': [entries.first, upper]
      }, 'duplicate_id');
    });

    test('paths are derived from the id; traversal is refused', () {
      for (final path in [
        '../notes/11111111-1111-4111-8111-111111111111.json',
        '/notes/11111111-1111-4111-8111-111111111111.json',
        'notes\\11111111-1111-4111-8111-111111111111.json',
        'notes/22222222-2222-4222-8222-222222222222.json',
        'notes/11111111-1111-4111-8111-111111111111.json/../../x',
      ]) {
        final json = _manifestJson();
        (json['entries'] as List).first['path'] = path;
        _rejects(json, path.length > 64 ? 'malformed' : 'invalid_path');
      }
    });

    test('invalid ids, sizes, checksums and dates are refused', () {
      Map<String, Object?> withFirst(String key, Object? value) {
        final json = _manifestJson();
        (json['entries'] as List).first[key] = value;
        return json;
      }

      _rejects(withFirst('id', '../../etc'), 'invalid_id');
      _rejects(withFirst('bytes', 0), 'malformed');
      _rejects(
          withFirst('bytes', ArchiveLimits.maxEntryBytes + 1), 'malformed');
      _rejects(withFirst('bytes', 1.5), 'malformed');
      _rejects(withFirst('sha256', 'A' * 64), 'malformed');
      _rejects(withFirst('updatedAt', '2026-11-02T18:05:07'), 'malformed');
      _rejects(withFirst('kind', 'image'), 'malformed');
    });

    test('expansion bombs are bounded before any entry is read', () {
      final template =
          Map<String, Object?>.of((_manifestJson()['entries'] as List).first);
      List<Map<String, Object?>> entries(int count, int bytes) => [
            for (var i = 0; i < count; i++)
              {
                ...template,
                'id':
                    '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
                'path':
                    'notes/00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}.json',
                'bytes': bytes,
              }
          ];
      // Declared content beyond 256 MiB.
      _rejects({
        ..._manifestJson(),
        'entries': entries(257, ArchiveLimits.maxEntryBytes)
      }, 'limit_exceeded');
      // Too many entries.
      _rejects({
        ..._manifestJson(),
        'entries': entries(ArchiveLimits.maxEntries + 1, 10)
      }, 'limit_exceeded');
      // An oversized manifest is refused before JSON decoding.
      expect(
          () => ArchiveManifest.parse(
              List.filled(ArchiveLimits.maxManifestBytes + 1, 0x20)),
          throwsA(isA<ArchiveFormatException>()
              .having((e) => e.code, 'code', 'too_large')));
    });

    test('sealed entries need vault parameters; KDF bounds are checked', () {
      _rejects({..._manifestJson(), 'vault': null}, 'malformed');
      _rejects({
        ..._manifestJson(),
        'vault': {
          'encVersion': 1,
          'kdf': {'memory': 65536, 'iterations': 3, 'parallelism': 1},
          'key': 'x'
        }
      }, 'unknown_field');
      _rejects({
        ..._manifestJson(),
        'vault': {
          'encVersion': 2,
          'kdf': {'memory': 65536, 'iterations': 3, 'parallelism': 1}
        }
      }, 'malformed');
    });

    test('malformed JSON is refused', () {
      expect(
          () => ArchiveManifest.parse(utf8.encode('{"format":')),
          throwsA(isA<ArchiveFormatException>()
              .having((e) => e.code, 'code', 'malformed')));
      expect(
          () => ArchiveManifest.parse([0xff, 0xfe]),
          throwsA(isA<ArchiveFormatException>()
              .having((e) => e.code, 'code', 'malformed')));
    });
  });

  group('entry verification', () {
    final (bytes, entry) =
        ArchiveNoteCodec.encode(_note('11111111-1111-4111-8111-111111111111'));

    void rejectsEntry(List<int> content, ArchiveEntry against, String code) =>
        expect(
            () => ArchiveNoteCodec.decode(content, against),
            throwsA(isA<ArchiveFormatException>()
                .having((e) => e.code, 'code', code)));

    test('size and checksum are verified before decoding', () {
      rejectsEntry([...bytes, 0x20], entry, 'invalid_size');
      final flipped = List<int>.of(bytes)..[10] ^= 1;
      rejectsEntry(flipped, entry, 'invalid_checksum');
    });

    test('content must agree with its manifest record', () {
      ArchiveEntry against(List<int> content, {bool deleted = false}) =>
          ArchiveEntry(
              id: entry.id,
              kind: entry.kind,
              deleted: deleted,
              sealed: false,
              bytes: content.length,
              sha256: ArchiveNoteCodec.sha256Hex(content),
              updatedAt: entry.updatedAt);
      rejectsEntry(bytes, against(bytes, deleted: true), 'malformed');
      final extra = utf8.encode(
          utf8.decode(bytes).replaceFirst('"id"', '"syncedSig":"x","id"'));
      rejectsEntry(extra, against(extra), 'unknown_field');
    });

    test('a sealed entry carries only its payload', () {
      expect(
          () => ArchiveNoteCodec.encode(
              _note('66666666-6666-4666-8666-666666666666'),
              sealedPayload: 'payload'),
          throwsA(isA<ArchiveFormatException>()));
    });

    test('ids that the Server cannot hold are not archived', () {
      expect(
          () => ArchiveNoteCodec.encode(Note(id: 'not-a-uuid')),
          throwsA(isA<ArchiveFormatException>()
              .having((e) => e.code, 'code', 'invalid_id')));
    });
  });
}
