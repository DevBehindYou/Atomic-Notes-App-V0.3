// F09 characterization: what NotesBloc shows for every type, order, tag and
// search on main 9c2c23d, through the real repository (owner checks,
// tombstones and the 64-entry projection cache). The golden file is the
// oracle for the single-pass snapshot (F09 option A): the refactor must
// reproduce it exactly. Regenerate only on purpose:
//   F09_UPDATE_GOLDEN=1 flutter test test/state/notes_snapshot_characterization_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../notes_repository_lifecycle_test.dart' show TestApi, TestVault;

const _golden = 'test/state/notes_snapshot_golden.json';
const _tags = ['Work', 'Launch', 'Plans', 'Home'];
final _t0 = DateTime.utc(2026, 1, 1);

String _jpeg(int length) => base64Encode([
      0xff, 0xd8, 0xff, 0xc0, 0, 8, 8, 0, 1, 0, 1, 1, //
      ...List<int>.generate(length - 14, (i) => (i * 7) & 0xff),
      0xff, 0xd9,
    ]);

/// Six kinds in turn: tagged rich prose, a rich checklist (a mixed note),
/// rich prose with an image, a legacy to-do, legacy prose, and an untagged
/// note whose title is the only match for some queries.
Note _fixture(int i) {
  final base = Note(
      id: 'c$i',
      title: 'Synthetic note $i',
      createdAt: _t0.add(Duration(minutes: i)),
      pinned: i % 9 == 0);
  List<String> tags(int n) =>
      [for (var t = 0; t < n; t++) _tags[(i + t) % _tags.length]];
  switch (i % 6) {
    case 0:
      base.body = 'Prose about launch plans for $i';
      return (NoteDocument.fromNote(base)..setTags(tags(2))).toNote(base);
    case 1:
      base.body = 'Steps for $i';
      final doc = NoteDocument.fromNote(base)..setTags(tags(1));
      var at = 0;
      for (var c = 0; c < 3; c++) {
        at = doc.insertChecklistAfter(at);
        doc.replaceText(at, 'Step $c of $i');
        if (c == 0) doc.setDone(at, true);
      }
      return doc.toNote(base);
    case 2:
      base.body = 'Picture note $i';
      final doc = NoteDocument.fromNote(base)..setTags(tags(1));
      doc.insertImageAfter(0, _jpeg(20000 + i));
      return doc.toNote(base);
    case 3:
      return Note(
          id: base.id,
          kind: NoteKind.todo,
          title: base.title,
          createdAt: base.createdAt,
          pinned: base.pinned,
          items: [
            TodoItem(text: 'Task step $i', done: i.isEven),
            TodoItem(text: 'Second task $i'),
          ]);
    case 4:
      base.body = 'Legacy prose $i mentions home and work';
      return base;
    default:
      base.title = 'Only title match zebra $i';
      return base;
  }
}

/// A summary of everything the screen draws from the state.
Map<String, Object?> _summary(NotesState s) => {
      'notes': [for (final n in s.notes) n.id],
      'tag': s.tag,
      'type': s.type.name,
      'sort': s.sort.name,
      'query': s.query,
      'typeCounts': {for (final e in s.typeCounts.entries) e.key.name: e.value},
      'tagCounts': Map.fromEntries(
          s.tagCounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      'selected': s.selected.toList()..sort(),
      'count': s.count,
      'pending': s.pending,
      'binCount': s.binCount,
    };

Future<Map<String, Object?>> _characterize(int seed) async {
  final dir = await Directory.systemTemp.createTemp('atomic-f09-char-');
  Hive.init(dir.path);
  final box = await Hive.openBox('f09-char-notes');
  SyncStatusHelper.syncBox = await Hive.openBox<bool>('f09-char-sync');
  final api = TestApi();
  final repository = NotesRepository.forTest(
      box: box,
      api: api,
      vault: TestVault(),
      checkConnectivity: () async => [ConnectivityResult.wifi]);
  await repository.start();
  final order = List<int>.generate(72, (i) => i)..shuffle(math.Random(seed));
  for (final i in order) {
    await repository.save(_fixture(i));
  }
  await repository.deleteNotes(['c5', 'c12', 'c44']); // tombstones

  final bloc = NotesBloc(
      source: repository,
      isSyncEnabled: () => false,
      isOnline: () async => true);
  Future<NotesState> send(NotesEvent event) async {
    bloc.add(event);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return bloc.state;
  }

  final out = <String, Object?>{};
  for (final type in NoteTypeFilter.values) {
    await send(NotesTypeFilterChanged(type));
    for (final sort in NoteSort.values) {
      await send(NotesSortChanged(sort));
      for (final tag in <String?>[null, 'Work', 'Launch', 'Missing']) {
        await send(NotesTagFilterChanged(tag));
        for (final query in ['', 'launch', 'step', 'zebra', '/9j', 'aaaa']) {
          final state = await send(NotesQueryChanged(query));
          out['$type|$sort|$tag|$query'] = _summary(state);
        }
      }
    }
  }
  // Selection is kept only for notes still on view.
  await send(const NotesViewReset());
  for (final id in ['c0', 'c1', 'c6']) {
    await send(NoteSelectionToggled(id));
  }
  out['selection, all'] = _summary(bloc.state);
  // A source change keeps only the selected notes still on view.
  await repository.deleteNotes(['c6']);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  out['selection, after a selected note is deleted'] = _summary(bloc.state);
  // A change of search clears the selection.
  out['selection, narrowed'] =
      _summary(await send(const NotesQueryChanged('step')));
  // Another account: nothing of this one shows.
  api.user = 'user-b';
  api.sessionRevision++;
  out['after account change'] =
      _summary(await send(const NotesQueryChanged('')));

  await bloc.close();
  await repository.stop(waitForSync: true);
  repository.dispose();
  await Hive.close();
  await dir.delete(recursive: true);
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('snapshot outputs match the characterized golden, for two orderings',
      () async {
    final first = await _characterize(1);
    final second = await _characterize(2);
    expect(jsonEncode(second), jsonEncode(first),
        reason: 'insertion order (cache fill) must not change what is shown');
    final encoded = const JsonEncoder.withIndent(' ').convert(first);
    final file = File(_golden);
    if (Platform.environment['F09_UPDATE_GOLDEN'] == '1') {
      file.writeAsStringSync('$encoded\n');
    }
    // A checkout with core.autocrlf writes the golden with CRLF line
    // endings; the content, not the line endings, is the oracle.
    expect(encoded,
        file.readAsStringSync().replaceAll('\r\n', '\n').trimRight());
  }, timeout: const Timeout(Duration(minutes: 5)));
}
