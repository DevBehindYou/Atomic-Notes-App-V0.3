import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/security/vault_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

// A storage-validator fixture only; rendering tests use real encoded JPEGs.
String _jpeg(int length) => base64Encode([
      0xff,
      0xd8,
      0xff,
      0xc0,
      0,
      8,
      8,
      0,
      1,
      0,
      1,
      1,
      ...List<int>.filled(length - 14, 0),
      0xff,
      0xd9,
    ]);

void main() {
  test('three 60000-byte images fit plaintext and real encrypted note budgets',
      () async {
    final original = Note.create()..body = 'Keep image details';
    final document = NoteDocument.fromNote(original);
    final jpeg = _jpeg(60000);
    for (var index = 0; index < 3; index++) {
      document.insertImageAfter(document.lines.length - 1, jpeg);
    }
    final note = document.toNote(original);
    expect(document.imageBytes, 180000);
    expect(NoteContentBudget.errorFor(note), isNull);
    final restored = NoteDocument.fromNote(Note.fromMap(note.toMap()));
    expect(restored.isReadOnly, isFalse);
    expect(restored.imageCount, 3);
    expect(
        restored.lines
            .where((line) => line.isImage)
            .every((line) => line.imageBase64 == jpeg),
        isTrue);

    final content = <String, dynamic>{
      'title': note.title,
      'body': note.body,
      'items': note.items.map((item) => item.toMap()).toList(),
    };
    final key = SecretKey(List<int>.generate(32, (index) => index));
    final payload = await VaultCrypto.sealJson(content, key);
    expect(
        payload.length, lessThanOrEqualTo(NoteContentBudget.maxPayloadLength));
    expect(await VaultCrypto.openJson(payload, key), content);
    final sealedRow = {
      ...note.toRemote(''),
      'title': '',
      'body': '',
      'items': <dynamic>[],
      'enc_v': 1,
      'encV': 1,
      'payload': payload
    };
    sealedRow.remove('user_id');
    expect(utf8.encode(jsonEncode(sealedRow)).length,
        lessThanOrEqualTo(NoteContentBudget.maxWireBytes));
    expect(() => document.insertImageAfter(0, jpeg), throwsFormatException);
  });

  test('legacy JPEG decode bound remains compatible while total stays bounded',
      () {
    final legacy = _jpeg(NoteImageContent.maxBytes);
    expect(NoteImageContent.decode(legacy).length, 61440);
    final document = NoteDocument.fromNote(Note.create());
    document.insertImageAfter(0, legacy);
    document.insertImageAfter(1, legacy);
    expect(() => document.insertImageAfter(2, legacy), throwsFormatException);
    expect(document.imageCount, 2);
  });
}
