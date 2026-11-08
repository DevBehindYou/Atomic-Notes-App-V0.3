import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/recovery/record_integrity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

String _id(int i) => '0000000$i-0000-4000-8000-00000000000$i';

/// A row as the repository writes it without a vault: Note.toMap plus
/// `enc_v: 0, payload: null`.
Map<String, Object?> _plain(Note note) =>
    {...note.toMap(), 'enc_v': 0, 'payload': null};

/// A sealed row: readable fields emptied, content in the vault payload.
Map<String, Object?> _sealed(String id) => {
      ...Note(id: id).toMap(),
      'enc_v': 1,
      'payload': 'c2VhbGVkLXBheWxvYWQ=',
    };

Map<Object?, Object?> _store() {
  final rich = NoteDocument.fromNote(Note(id: _id(3), body: 'Rich'));
  rich.setTags(['work']);
  rich.insertImageAfter(
      0, base64Encode(image.encodeJpg(image.Image(width: 8, height: 8))));
  return {
    // Repository bookkeeping is not a note and is never reported.
    '__cache_owner__': 'user-1',
    '__sync_cursor__': {'user': 'user-1', 'after': 42},
    _id(1): _plain(Note(id: _id(1), title: 'Plain')),
    _id(2): _plain(
        Note(id: _id(2), kind: NoteKind.todo, items: [TodoItem(text: 'Task')])),
    _id(3): _plain(rich.toNote(Note(id: _id(3)))),
    _id(4): _plain(Note(id: _id(4), title: 'Binned', deleted: true)),
    _id(5): _sealed(_id(5)),
    // A legacy row from an older App: no flags, no vault fields, old item keys.
    _id(6): {
      'id': _id(6),
      'title': 'Legacy',
      'items': [
        {'text': 'old', 'done': true}
      ]
    },
  };
}

void main() {
  test('sound rows of every stored shape are readable as stored', () {
    final report = RecordIntegrity.scan(_store());
    expect(report.clean, isTrue,
        reason: '${report.findings.map((f) => f.problem)}');
    expect(report.scanned, 6, reason: 'reserved keys are skipped');
    expect(report.sound, [_id(1), _id(2), _id(3), _id(4), _id(5), _id(6)]);
  });

  test('each kind of corruption is reported with counts', () {
    final damagedRich = _plain(Note(
        id: _id(7),
        body: '{"v":2,"tags":[],"blocks":[{"text":"x","image":"bad"}]}',
        items: [TodoItem(text: NoteDocument.richFormatMarker)]));
    final store = {
      ..._store(),
      'not-a-note-id': _plain(Note(id: _id(8))),
      _id(9): 'just a string',
      'aaaaaaaa-0000-4000-8000-00000000000a': {'title': 'no id'},
      'bbbbbbbb-0000-4000-8000-00000000000b':
          _plain(Note(id: 'cccccccc-0000-4000-8000-00000000000c')),
      'dddddddd-0000-4000-8000-00000000000d': {
        ..._plain(Note(id: 'dddddddd-0000-4000-8000-00000000000d')),
        'deleted': 'yes',
      },
      'eeeeeeee-0000-4000-8000-00000000000e': {
        ..._plain(Note(id: 'eeeeeeee-0000-4000-8000-00000000000e')),
        'updatedAt': 'yesterday',
      },
      _id(7): damagedRich,
      'ffffffff-0000-4000-8000-00000000000f': {
        ..._sealed('ffffffff-0000-4000-8000-00000000000f'),
        'title': 'readable beside a payload',
      },
      '11111111-2222-4333-8444-555555555555': {
        ...Note(id: '11111111-2222-4333-8444-555555555555').toMap(),
        'enc_v': 1,
      },
      '22222222-2222-4333-8444-555555555555': {
        ...Note(id: '22222222-2222-4333-8444-555555555555').toMap(),
        'payload': 'orphan',
      },
      // The same id in two cases.
      'ABCDEF01-0000-4000-8000-000000000000':
          _plain(Note(id: 'ABCDEF01-0000-4000-8000-000000000000')),
      'abcdef01-0000-4000-8000-000000000000':
          _plain(Note(id: 'abcdef01-0000-4000-8000-000000000000')),
    };
    final report = RecordIntegrity.scan(store);
    expect(report.counts, {
      IntegrityProblem.invalidKey: 1,
      IntegrityProblem.notARecord: 2,
      IntegrityProblem.idMismatch: 1,
      IntegrityProblem.duplicateId: 2,
      IntegrityProblem.malformedFields: 2,
      IntegrityProblem.malformedRichContent: 1,
      IntegrityProblem.contradictorySealing: 3,
    });
    // Every good row is still reported readable.
    expect(report.sound,
        containsAll([_id(1), _id(2), _id(3), _id(4), _id(5), _id(6)]));
    expect(report.sound, isNot(contains(_id(7))));
    expect(report.quarantine, hasLength(12));
  });

  test('scanning and preserving never change the source', () async {
    final store = {
      ..._store(),
      _id(9): 'just a string',
      'bbbbbbbb-0000-4000-8000-00000000000b': _plain(Note(id: _id(8))),
    };
    final before = jsonEncode(store);
    final report = RecordIntegrity.scan(store);
    final port = _Port();
    expect(await RecordIntegrity.preserveCopies(store, report, port), 2);
    expect(jsonEncode(store), before, reason: 'originals retained as stored');
    expect(port.copies.keys,
        ['s:${_id(9)}', 's:bbbbbbbb-0000-4000-8000-00000000000b']);
    expect(port.copies['s:${_id(9)}'], 'just a string');
    expect(port.why['s:bbbbbbbb-0000-4000-8000-00000000000b'],
        [IntegrityProblem.idMismatch]);
    // A preserved copy is independent of the source.
    (port.copies['s:bbbbbbbb-0000-4000-8000-00000000000b'] as Map)['title'] =
        'x';
    expect(jsonEncode(store), before);
  });

  test('int and String keys that print alike stay distinct', () async {
    final intValue = {'id': 'int row', 'title': 'one'};
    final stringValue = {'id': 'string row', 'title': 'uno'};
    final store = <Object?, Object?>{
      1: intValue,
      '1': stringValue,
      // A String key shaped like another key's locator must not collide.
      'i:1': 'forged int locator',
      's:1': 'forged string locator',
    };
    final before = store.toString();
    final report = RecordIntegrity.scan(store);
    expect(report.scanned, 4);
    expect(report.findings.map((f) => f.rawKey), [1, '1', 'i:1', 's:1']);
    expect(report.findings.map((f) => f.rawKey.runtimeType),
        [int, String, String, String]);
    expect(report.quarantine, ['i:1', 's:1', 's:i:1', 's:s:1']);

    final port = _Port();
    expect(await RecordIntegrity.preserveCopies(store, report, port), 4);
    expect(store.toString(), before, reason: 'source unchanged');
    expect(port.copies, {
      'i:1': intValue,
      's:1': stringValue,
      's:i:1': 'forged int locator',
      's:s:1': 'forged string locator',
    });
    expect(port.rawKeys['i:1'], isA<int>().having((k) => k, 'key', 1));
    expect(port.rawKeys['s:1'], isA<String>().having((k) => k, 'key', '1'));
    expect(port.why['i:1'], [IntegrityProblem.invalidKey]);
  });

  test('keys of other types get unique ordinal locators', () async {
    final store = <Object?, Object?>{null: 'a', 2.0: 'b', const _Key(): 'c'};
    final report = RecordIntegrity.scan(store);
    expect(report.quarantine, ['o:0:Null', 'o:1:double', 'o:2:_Key']);
    final port = _Port();
    expect(await RecordIntegrity.preserveCopies(store, report, port), 3);
    expect(port.copies.values, ['a', 'b', 'c']);
  });

  test('findings carry ids and codes only, never content', () {
    final store = {
      _id(1): {
        ..._plain(Note(id: _id(1), title: 'Secret title')),
        'pinned': 'nope',
      },
    };
    final report = RecordIntegrity.scan(store);
    final rendered =
        report.findings.map((f) => '${f.key} ${f.problem.name}').join(' ');
    expect(rendered, isNot(contains('Secret')));
    expect(report.findings.single.problem, IntegrityProblem.malformedFields);
  });
}

class _Port implements QuarantinePort {
  final copies = <String, Object?>{};
  final rawKeys = <String, Object?>{};
  final why = <String, List<IntegrityProblem>>{};
  @override
  Future<void> preserve(String locator, Object? rawKey, Object? original,
      List<IntegrityProblem> problems) async {
    expect(copies.containsKey(locator), isFalse,
        reason: 'locators never collide');
    copies[locator] = original;
    rawKeys[locator] = rawKey;
    why[locator] = problems;
  }
}

class _Key {
  const _Key();
  @override
  String toString() => '1';
}
