import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/recovery/archive_manifest.dart';
import 'package:atomic_notes/recovery/export_writer.dart';
import 'package:atomic_notes/recovery/import_preview_view.dart';
import 'package:atomic_notes/recovery/import_validator.dart';
import 'package:atomic_notes/security/vault_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

final _time = DateTime.utc(2026, 11, 7, 10);
const _vault = ArchiveVault(
    encVersion: 1, kdfMemory: 65536, kdfIterations: 3, kdfParallelism: 1);
const _secretTitle = 'Private title that must not show';

String _id(int i) => '0000000$i-0000-4000-8000-00000000000$i';

Note _plain(int i,
        {String? title, String body = 'Body', bool deleted = false}) =>
    Note(
        id: _id(i),
        title: title ?? '$_secretTitle $i',
        body: body,
        deleted: deleted,
        createdAt: _time,
        updatedAt: _time);

Note _withImage(int i, {bool damaged = false}) {
  final document = NoteDocument.fromNote(_plain(i));
  document.insertImageAfter(
      0, base64Encode(image.encodeJpg(image.Image(width: 8, height: 8))));
  final note = document.toNote(_plain(i));
  if (damaged) {
    // A valid archive entry whose embedded image is not a JPEG.
    final rich = jsonDecode(note.body) as Map<String, dynamic>;
    final block = (rich['blocks'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((b) => b.containsKey('image'));
    block['image'] = base64Encode(List<int>.filled(64, 7));
    note.body = jsonEncode(rich);
  }
  return note;
}

class _MemoryTarget implements ExportTarget {
  final _bytes = BytesBuilder();
  Uint8List? committed;
  @override
  Future<void> open() async {}
  @override
  Future<void> write(List<int> bytes) async => _bytes.add(bytes);
  @override
  Future<void> commit() async => committed = _bytes.toBytes();
  @override
  Future<void> abort() async {}
}

Future<Uint8List> _archive(List<ArchiveSource> sources,
    {ArchiveKey? key}) async {
  final target = _MemoryTarget();
  await ExportWriter(clock: () => _time)
      .write(target, sources, key: key, vault: _vault);
  return target.committed!;
}

/// A plain container built frame by frame, for manifests the writer would
/// never produce.
Uint8List _raw(Object? manifest, List<List<int>> entries) {
  final out = BytesBuilder()..add([0x41, 0x54, 0x4e, 0x41, 1, 0]);
  void frame(List<int> payload) {
    out.add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List());
    out.add(payload);
  }

  frame(utf8.encode(jsonEncode(manifest)));
  entries.forEach(frame);
  frame(utf8.encode(jsonEncode({'entries': entries.length})));
  return out.toBytes();
}

class _Local implements LocalNotesView {
  _Local([List<Note> notes = const []])
      : notes = {for (final n in notes) n.id: n};
  final Map<String, Note> notes;
  int reads = 0;
  @override
  Note? byId(String id) {
    reads++;
    return notes[id];
  }
}

ArchiveKey _key([int seed = 1]) {
  final random = Random(seed);
  return ArchiveKey.forTesting(
      SecretKey(List<int>.generate(32, (_) => random.nextInt(256))),
      List<int>.generate(16, (_) => random.nextInt(256)));
}

Matcher _code(String code) =>
    throwsA(isA<ArchiveFormatException>().having((e) => e.code, 'code', code));

Future<ImportPreview> _inspect(List<int> bytes,
        {_Local? local, ArchiveKey? key}) =>
    ImportValidator.inspect(ArchiveByteSource.bytes(bytes),
        local: local ?? _Local(),
        unlock: key == null ? null : (_) async => key);

/// Every kind of readable note, with no sealed rows.
List<ArchiveSource> _readable() =>
    _mixed().where((s) => s.sealedPayload == null).toList();

List<ArchiveSource> _mixed() => [
      ArchiveSource(_plain(1)),
      ArchiveSource(_plain(2, deleted: true)),
      ArchiveSource(Note(
          id: _id(3),
          kind: NoteKind.todo,
          items: [TodoItem(text: 'Task')],
          createdAt: _time,
          updatedAt: _time)),
      ArchiveSource(_withImage(4)),
      ArchiveSource(Note(id: _id(5), createdAt: _time, updatedAt: _time),
          sealedPayload: 'sealed-vault-payload'),
    ];

void main() {
  group('valid archives', () {
    test('counts, comparison with this device, and restore offered', () async {
      final local = _Local([
        _plain(1), // identical
        _plain(3, title: 'Changed here'), // same id, different content
      ]);
      final preview = await _inspect(await _archive(_readable()), local: local);
      expect(preview.locked, isFalse);
      expect([
        preview.total,
        preview.live,
        preview.deleted,
        preview.checklists,
        preview.images,
        preview.sealed
      ], [
        4,
        3,
        1,
        1,
        1,
        0
      ]);
      expect(preview.unchanged, [_id(1)]);
      expect(preview.added, [_id(2), _id(4)]);
      expect(preview.conflicts, [_id(3)]);
      expect(preview.issues, isEmpty);
      expect(preview.canRestore, isTrue);
    });

    test('a sealed row blocks restore and is still counted', () async {
      final local = _Local(
          [Note(id: _id(5), createdAt: _time, updatedAt: _time)]); // sealed id
      final preview = await _inspect(await _archive(_mixed()), local: local);
      expect([preview.total, preview.sealed], [5, 1]);
      expect(preview.conflicts, [_id(5)]);
      expect({for (final i in preview.issues) i.id: i.code},
          {_id(5): 'sealed_unsupported'});
      expect(preview.canRestore, isFalse);
    });

    test(
        'real vault ciphertext is bound to its source account, so a sealed '
        'row is never offered for restore', () async {
      // Two accounts that chose the same recovery phrase.
      const phrase = 'alpha bravo charlie delta echo foxtrot';
      Future<SecretKey> vaultKey(String userId) async =>
          VaultCrypto.deriveKey(phrase, await VaultCrypto.saltForUser(userId),
              memory: 65536, iterations: 3, parallelism: 1);
      final source = await vaultKey('source-account');
      final other = await vaultKey('other-account');
      final content = {'title': _secretTitle, 'body': 'Vault body'};
      final payload = await VaultCrypto.sealJson(content, source);

      // The payload opens only with the source account's key: the export
      // password cannot change that.
      expect(await VaultCrypto.openJson(payload, source), content);
      await expectLater(VaultCrypto.openJson(payload, other),
          throwsA(isA<SecretBoxAuthenticationError>()));

      final key = ArchiveKey.forTesting(
          SecretKey(List<int>.generate(32, (i) => i)), List.filled(16, 3));
      final bytes = await _archive([
        ArchiveSource(_plain(1)),
        ArchiveSource(Note(id: _id(5), createdAt: _time, updatedAt: _time),
            sealedPayload: payload),
      ], key: key);
      // Whether this device is the source account or another one, the archive
      // carries no verified source context, so restore is refused.
      for (final local in [
        _Local(),
        _Local([Note(id: _id(5), createdAt: _time, updatedAt: _time)]),
      ]) {
        final preview = await _inspect(bytes, local: local, key: key);
        expect(preview.sealed, 1);
        expect(preview.issues.single.code, 'sealed_unsupported');
        expect(preview.issues.single.message, isNot(contains(_secretTitle)));
        expect(preview.canRestore, isFalse);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an encrypted archive reveals nothing until it is unlocked', () async {
      final key = _key();
      final bytes = await _archive(_readable(), key: key);
      final local = _Local([_plain(1)]);
      final locked = await _inspect(bytes, local: local);
      expect(locked.locked, isTrue);
      expect(locked.canRestore, isFalse);
      expect(
          [locked.total, locked.added, locked.issues], [0, isEmpty, isEmpty]);
      expect(local.reads, 0, reason: 'not even ids are compared');
      final open = await _inspect(bytes, local: local, key: key);
      expect(open.total, 4);
      expect(open.canRestore, isTrue);
    });
  });

  group('refused without any write', () {
    test('a wrong password fails authentication before anything is read',
        () async {
      final local = _Local([_plain(1)]);
      final bytes = await _archive(_mixed(), key: _key());
      await expectLater(_inspect(bytes, local: local, key: _key(2)),
          _code('authentication_failed'));
      expect(local.reads, 0);
    });

    test('corruption and truncation are refused', () async {
      final bytes = await _archive(_mixed());
      final at = _indexOf(bytes, utf8.encode('Task'));
      await expectLater(_inspect(Uint8List.fromList(bytes)..[at] ^= 1),
          _code('invalid_checksum'));
      await expectLater(
          _inspect(bytes.sublist(0, bytes.length - 3)), _code('truncated'));
    });

    test('unsupported container and manifest versions are refused', () async {
      final bytes = await _archive(_mixed());
      await expectLater(_inspect(Uint8List.fromList(bytes)..[4] = 2),
          _code('unsupported_version'));
      final manifest =
          ArchiveManifest(createdAt: _time, entries: const [], vault: _vault)
              .toJson()
            ..['version'] = 2;
      await expectLater(
          _inspect(_raw(manifest, [])), _code('unsupported_version'));
    });

    test('duplicate ids in the manifest are refused', () async {
      final (bytes, entry) = ArchiveNoteCodec.encode(_plain(1));
      final manifest = ArchiveManifest(
          createdAt: _time, entries: [entry, entry], vault: _vault);
      await expectLater(_inspect(_raw(manifest.toJson(), [bytes, bytes])),
          _code('duplicate_id'));
    });

    test('a damaged image or over-limit note blocks restore with a reason',
        () async {
      final preview = await _inspect(await _archive([
        ArchiveSource(_plain(1)),
        ArchiveSource(_withImage(2, damaged: true)),
        ArchiveSource(_plain(3, title: 'T' * 301)),
        ArchiveSource(_plain(4, body: 'x' * 262145)),
      ]));
      expect(preview.canRestore, isFalse);
      expect({
        for (final i in preview.issues) i.id: i.code
      }, {
        _id(2): 'unsupported_format',
        _id(3): 'title_too_long',
        _id(4): 'too_large',
      });
      for (final issue in preview.issues) {
        expect(issue.message, isNot(contains('T' * 20)));
      }
    });
  });

  group('preview view', () {
    Future<void> show(WidgetTester tester, ImportPreview preview,
        {VoidCallback? onRestore}) {
      return tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ImportPreviewView(
                      preview: preview, onRestore: onRestore)))));
    }

    testWidgets('shows counts, never note content, and offers restore',
        (tester) async {
      final preview = await tester.runAsync(
          () async => _inspect(await _archive(_readable()), local: _Local()));
      var restored = 0;
      await show(tester, preview!, onRestore: () => restored++);
      expect(find.text('4 notes'), findsOneWidget);
      expect(find.textContaining(_secretTitle), findsNothing);
      expect(find.textContaining('4 new to this device'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('import-preview-restore')));
      expect(restored, 1);
    });

    testWidgets('locked and invalid archives cannot be restored',
        (tester) async {
      await show(tester, ImportPreview.locked(), onRestore: () => fail('no'));
      expect(find.textContaining('export password'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('import-preview-restore')), findsNothing);

      final invalid = await tester.runAsync(() async => _inspect(
          await _archive([ArchiveSource(_plain(1, title: 'T' * 301))])));
      await show(tester, invalid!, onRestore: () => fail('no'));
      expect(
          find.byKey(const ValueKey('import-preview-issues')), findsOneWidget);
      final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('import-preview-restore')));
      expect(button.onPressed, isNull);
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
