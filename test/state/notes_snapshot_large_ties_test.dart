// F09 characterization, follow-up from Codex's packet-5 and packet-6 rulings:
// equal timestamps in a library larger than 32 notes. Dart's List.sort is
// only stable for small lists, so this freezes today's exact order for 40
// tied notes (some pinned) through the real repository and NotesBloc, for
// both sort orders, a type filter, a tag filter and a second insertion
// order. Option A (one projection pass in `_snapshot`) must reproduce these
// lists exactly, or show that the sort input and comparator are unchanged.
// It is a characterization of current behaviour, not a promise of order.

import 'dart:io';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../notes_repository_lifecycle_test.dart' show TestApi, TestVault;

final _tied = DateTime.utc(2026, 1, 1);

/// Note [i] of 40: every one created at the same instant; every seventh
/// pinned; every third a legacy to-do; every fourth tagged `Work`.
Note _note(int i) {
  if (i % 3 == 0) {
    return Note(
        id: 't$i',
        kind: NoteKind.todo,
        title: 'Tied $i',
        createdAt: _tied,
        pinned: i % 7 == 0,
        items: [TodoItem(text: 'Task $i')]);
  }
  final base =
      Note(id: 't$i', title: 'Tied $i', body: 'Body $i', createdAt: _tied, pinned: i % 7 == 0);
  if (i % 4 != 0) return base;
  return (NoteDocument.fromNote(base)..setTags(['Work'])).toNote(base);
}

Future<Map<String, List<String>>> _orders(List<int> insertion) async {
  final dir = await Directory.systemTemp.createTemp('atomic-f09-ties-');
  Hive.init(dir.path);
  final box = await Hive.openBox('f09-ties-notes');
  SyncStatusHelper.syncBox = await Hive.openBox<bool>('f09-ties-sync');
  final repository = NotesRepository.forTest(
      box: box,
      api: TestApi(),
      vault: TestVault(),
      checkConnectivity: () async => [ConnectivityResult.wifi]);
  await repository.start();
  for (final i in insertion) {
    await repository.save(_note(i));
  }
  final bloc = NotesBloc(
      source: repository, isSyncEnabled: () => false, isOnline: () async => true);
  Future<List<String>> send(NotesEvent event) async {
    bloc.add(event);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return [for (final n in bloc.state.notes) n.id];
  }

  final out = <String, List<String>>{
    'newest': await send(const NotesSortChanged(NoteSort.newest)),
    'oldest': await send(const NotesSortChanged(NoteSort.oldest)),
  };
  await send(const NotesSortChanged(NoteSort.newest));
  out['todos'] = await send(const NotesTypeFilterChanged(NoteTypeFilter.todos));
  await send(const NotesTypeFilterChanged(NoteTypeFilter.all));
  out['tag Work'] = await send(const NotesTagFilterChanged('Work'));
  await bloc.close();
  await repository.stop(waitForSync: true);
  repository.dispose();
  await Hive.close();
  await dir.delete(recursive: true);
  return out;
}

// Captured on 59ea1b6 (main 9c2c23d behaviour), twice, identical.
const _ascending = <String, List<String>>{
  'newest': [
      't35', 't7', 't0', 't14', 't21', 't28', 't13', 't1',
      't8', 't9', 't10', 't11', 't12', 't2', 't3', 't15',
      't16', 't17', 't18', 't19', 't20', 't4', 't22', 't23',
      't24', 't39', 't26', 't27', 't5', 't29', 't30', 't31',
      't32', 't33', 't34', 't6', 't36', 't37', 't38', 't25',
  ],
  'oldest': [
      't35', 't7', 't0', 't14', 't21', 't28', 't13', 't1',
      't8', 't9', 't10', 't11', 't12', 't2', 't3', 't15',
      't16', 't17', 't18', 't19', 't20', 't4', 't22', 't23',
      't24', 't39', 't26', 't27', 't5', 't29', 't30', 't31',
      't32', 't33', 't34', 't6', 't36', 't37', 't38', 't25',
  ],
  'todos': [
      't0', 't21', 't3', 't6', 't9', 't12', 't15', 't18',
      't24', 't27', 't30', 't33', 't36', 't39',
  ],
  'tag Work': [
      't28', 't4', 't8', 't16', 't20', 't32',
  ],
};

const _scrambled = <String, List<String>>{
  'newest': [
      't35', 't28', 't21', 't0', 't14', 't7', 't22', 't39',
      't16', 't33', 't10', 't27', 't4', 't11', 't38', 't15',
      't32', 't9', 't26', 't3', 't20', 't37', 't17', 't31',
      't8', 't23', 't2', 't19', 't36', 't13', 't30', 't5',
      't24', 't1', 't18', 't34', 't12', 't29', 't6', 't25',
  ],
  'oldest': [
      't35', 't28', 't21', 't0', 't14', 't7', 't22', 't39',
      't16', 't33', 't10', 't27', 't4', 't11', 't38', 't15',
      't32', 't9', 't26', 't3', 't20', 't37', 't17', 't31',
      't8', 't23', 't2', 't19', 't36', 't13', 't30', 't5',
      't24', 't1', 't18', 't34', 't12', 't29', 't6', 't25',
  ],
  'todos': [
      't0', 't21', 't39', 't33', 't27', 't15', 't9', 't3',
      't36', 't30', 't24', 't18', 't12', 't6',
  ],
  'tag Work': [
      't28', 't16', 't4', 't32', 't20', 't8',
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('40 tied notes, ascending insertion: today\'s exact order', () async {
    final orders = await _orders([for (var i = 0; i < 40; i++) i]);
    expect(orders, _ascending);
  });

  test('40 tied notes, scrambled insertion: today\'s exact order', () async {
    final orders = await _orders([for (var i = 0; i < 40; i++) (i * 17) % 40]);
    expect(orders, _scrambled);
  });
}
