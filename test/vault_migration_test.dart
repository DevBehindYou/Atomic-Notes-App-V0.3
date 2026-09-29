// Moving notes into the vault. A note that the cloud holds as plain text has to be
// sent again sealed once the vault is unlocked, whichever way it reached this device
// and whenever it arrived. Found on the phone: an unlock that happened while a pull was
// still running sealed only the rows it had seen and left the rest plain in the cloud.
// These need neither Hive nor the network.

import 'package:atomic_notes/database/note.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({int? encV}) => {
      'id': 'note-1',
      'kind': 'text',
      'title': 'title',
      'body': 'body',
      'items': const [],
      'pinned': false,
      'deleted': false,
      'created_at': '2026-09-20T10:00:00Z',
      'updated_at': '2026-09-20T10:00:00Z',
      'version': 3,
      if (encV != null) 'enc_v': encV,
    };

void main() {
  group('which pulled rows have to be sealed', () {
    test('a plain row, vault unlocked: yes', () {
      expect(rowNeedsSealing(_row(encV: 0), vaultUnlocked: true), isTrue);
    });

    test('a row without the flag counts as plain', () {
      expect(rowNeedsSealing(_row(), vaultUnlocked: true), isTrue);
    });

    test('a sealed row: no', () {
      expect(rowNeedsSealing(_row(encV: 1), vaultUnlocked: true), isFalse);
    });

    test('vault locked: no, there is nothing to seal with', () {
      expect(rowNeedsSealing(_row(encV: 0), vaultUnlocked: false), isFalse);
    });
  });

  group('sending a note again', () {
    test('a synced note is not waiting', () {
      final note = Note.fromRemote(_row(encV: 0));
      expect(note.dirty, isFalse);
    });

    test('requireResend makes it wait even though the content matches the cloud', () {
      final note = Note.fromRemote(_row(encV: 0))..requireResend();
      expect(note.dirty, isTrue);
      expect(note.syncedSig, isEmpty);
    });

    test('a note that must be resent is not settled as "nothing to send"', () {
      final note = Note.fromRemote(_row(encV: 0))..requireResend();
      expect(note.settleDirty(), isFalse);
      expect(note.dirty, isTrue);
    });

    test('once sent, the usual settling works again', () {
      final note = Note.fromRemote(_row(encV: 0))..requireResend();
      note.syncedSig = note.contentSig; // what a successful push records
      expect(note.settleDirty(), isTrue);
      expect(note.dirty, isFalse);
    });
  });
}
