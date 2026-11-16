// F09 option A: NotesBloc._snapshot projects each eligible note once and
// derives the type counts, the tag counts, the to-do and tag filters and the
// search from that one pass. These tests count the projections one snapshot
// requests, for a library larger than the 64-entry projection cache, and
// compare every derived field with the snapshot as it was before the change
// (base 6c91580), kept below as `_before`.
//
// Set F09_PRINT_COUNTS=1 to print the per-view projection counts.

import 'dart:io';
import 'dart:math' as math;

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/note_projection.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../notes_repository_lifecycle_test.dart' show TestApi, TestVault;
import '../support/fake_notes_source.dart';

const _pool = ['Work', 'Launch', 'Plans', 'Home'];
const _tags = <String?>[null, 'Work', 'Missing'];
const _queries = ['', 'step', 'zebra'];
final _t0 = DateTime.utc(2026, 1, 1);

/// Note [i]: five kinds in turn (tagged rich prose, a tagged rich checklist,
/// a legacy to-do, legacy prose, a note only its title matches), created
/// [minute] minutes after _t0.
Note _note(int i, {required int minute, required bool pinned}) {
  final base = Note(
      id: 'n$i',
      title: 'Synthetic note $i',
      createdAt: _t0.add(Duration(minutes: minute)),
      pinned: pinned);
  List<String> tags(int count) =>
      [for (var t = 0; t < count; t++) _pool[(i + t) % _pool.length]];
  switch (i % 5) {
    case 0:
      base.body = 'Prose about launch plans for $i';
      return (NoteDocument.fromNote(base)..setTags(tags(2))).toNote(base);
    case 1:
      base.body = 'Steps for $i';
      final doc = NoteDocument.fromNote(base)..setTags(tags(1));
      final at = doc.insertChecklistAfter(0);
      doc.replaceText(at, 'Step one of $i');
      return doc.toNote(base);
    case 2:
      return Note(
          id: base.id,
          kind: NoteKind.todo,
          title: base.title,
          createdAt: base.createdAt,
          pinned: pinned,
          items: [TodoItem(text: 'Task step $i')]);
    case 3:
      base.body = 'Legacy prose $i about home and work';
      return base;
    default:
      base.title = 'Only title match zebra $i';
      return base;
  }
}

/// 103 notes with distinct creation times (no two compare equal), three of
/// them deleted: 100 eligible notes.
List<Note> _distinct() => [
      for (var i = 0; i < 103; i++)
        _note(i, minute: (i * 37) % 103, pinned: i % 7 == 0)
          ..deleted = i % 40 == 5,
    ];

/// [size] notes over three creation times, some pinned, shuffled: most of
/// them tie with others.
List<Note> _tied(int seed, int size) {
  final random = math.Random(seed);
  return [
    for (var i = 0; i < size; i++)
      _note(i, minute: random.nextInt(3), pinned: random.nextInt(4) == 0),
  ]..shuffle(random);
}

/// The shared in-memory source, projecting the way [NotesRepository] does: its
/// to-do and tag reads ask [projectionFor], and every request is counted.
/// Nothing is cached, like the notes beyond the repository's projection cache.
class _CountingSource extends FakeNotesSource implements NoteProjectionSource {
  _CountingSource(List<Note> notes) : super(notes: notes, limit: 1000);

  int projections = 0;

  @override
  NoteProjection projectionFor(Note note, {bool evict = true}) {
    projections++;
    return NoteProjection.fromNote(note);
  }

  /// [NotesRepository.visible], step for step, over this source's insertion
  /// order.
  @override
  List<Note> visible({
    NoteFilter? filter,
    NoteTypeFilter type = NoteTypeFilter.all,
    NoteSort sort = NoteSort.newest,
    String? tag,
  }) {
    final shownType = filter?.type ?? type;
    final order = filter?.sort ?? sort;
    final list = all.where((n) => !n.deleted).toList();
    switch (shownType) {
      case NoteTypeFilter.todos:
        list.retainWhere((n) =>
            n.kind == NoteKind.todo ||
            projectionFor(n, evict: false).hasChecklist);
      case NoteTypeFilter.notes:
        list.retainWhere((n) => n.kind == NoteKind.text);
      case NoteTypeFilter.all:
        break;
    }
    if (tag != null) {
      list.retainWhere(
          (n) => projectionFor(n, evict: false).tags.contains(tag));
    }
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return order == NoteSort.oldest
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }
}

/// The real repository, forwarded, recording what the bloc asks of it: the
/// projections it requests, and every visible() read (the repository
/// projects inside a to-do or tag read).
class _Recording implements NotesSource, NoteProjectionSource {
  _Recording(this.inner);

  final NotesRepository inner;
  int projections = 0;
  final reads = <String>[];

  @override
  NoteProjection projectionFor(Note note, {bool evict = true}) {
    projections++;
    return inner.projectionFor(note, evict: evict);
  }

  @override
  List<Note> visible({
    NoteFilter? filter,
    NoteTypeFilter type = NoteTypeFilter.all,
    NoteSort sort = NoteSort.newest,
    String? tag,
  }) {
    reads.add('${filter?.name ?? type.name}|${tag ?? '-'}');
    return inner.visible(filter: filter, type: type, sort: sort, tag: tag);
  }

  @override
  void addListener(VoidCallback listener) => inner.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      inner.removeListener(listener);
  @override
  Note? byId(String id) => inner.byId(id);
  @override
  int get count => inner.count;
  @override
  int get limit => inner.limit;
  @override
  int get pendingCount => inner.pendingCount;
  @override
  bool get isSyncing => inner.isSyncing;
  @override
  String? get lastError => inner.lastError;
  @override
  List<Note> get binNotes => inner.binNotes;
  @override
  DateTime? get lastSyncedAt => inner.lastSyncedAt;
  @override
  DateTime? get nextAutoSyncAt => inner.nextAutoSyncAt;
  @override
  Future<void> save(Note note) => inner.save(note);
  @override
  Future<void> deleteNotes(Iterable<String> ids) => inner.deleteNotes(ids);
  @override
  Future<bool> syncNow({bool instant = false}) =>
      inner.syncNow(instant: instant);
  @override
  Future<bool> restoreNote(String id) => inner.restoreNote(id);
  @override
  Future<int> deleteForever(Iterable<String> ids) => inner.deleteForever(ids);
  @override
  Future<int?> cloudCount() => inner.cloudCount();
  @override
  Future<int> markAllForUpload() => inner.markAllForUpload();
  @override
  Future<WipeOutcome> wipeRemote() => inner.wipeRemote();
  @override
  Future<int> wipeLocalNotes() => inner.wipeLocalNotes();
}

/// The derived fields as base 6c91580 computed them: four visible() reads, a
/// tag scan and a search scan, each projecting again.
Map<String, Object?> _before(NotesSource source, NoteTypeFilter type,
    NoteSort sort, String? selectedTag, String query) {
  final eligible = source.visible();
  final typeCounts = <NoteTypeFilter, int>{
    NoteTypeFilter.all: eligible.length,
    NoteTypeFilter.notes: source.visible(type: NoteTypeFilter.notes).length,
    NoteTypeFilter.todos: source.visible(type: NoteTypeFilter.todos).length,
  };
  final tagCounts = <String, int>{};
  for (final n in eligible) {
    for (final t in projectNote(source, n, evict: false).tags.toSet()) {
      tagCounts[t] = (tagCounts[t] ?? 0) + 1;
    }
  }
  final tag = selectedTag != null && tagCounts.containsKey(selectedTag)
      ? selectedTag
      : null;
  final filtered = source.visible(type: type, sort: sort, tag: tag);
  final q = query.trim().toLowerCase();
  final shown = q.isEmpty
      ? filtered
      : filtered
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              projectNote(source, n, evict: false).matches(q))
          .toList();
  return _fields(shown, typeCounts, tagCounts, tag);
}

/// The same fields from the bloc's state. Map entries keep their order.
Map<String, Object?> _after(NotesState s) =>
    _fields(s.notes, s.typeCounts, s.tagCounts, s.tag);

Map<String, Object?> _fields(List<Note> shown, Map<NoteTypeFilter, int> types,
        Map<String, int> tags, String? tag) =>
    {
      'notes': [for (final n in shown) n.id],
      'typeCounts': [for (final e in types.entries) '${e.key.name}=${e.value}'],
      'tagCounts': [for (final e in tags.entries) '${e.key}=${e.value}'],
      'tag': tag,
    };

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _send(NotesBloc bloc, NotesEvent event) {
  bloc.add(event);
  return _settle();
}

/// Every type, order, tag and search, in turn.
Iterable<(NoteTypeFilter, NoteSort, String?, String)> _views() sync* {
  for (final type in NoteTypeFilter.values) {
    for (final sort in NoteSort.values) {
      for (final tag in _tags) {
        for (final query in _queries) {
          yield (type, sort, tag, query);
        }
      }
    }
  }
}

void _report(String name, Map<String, String> rows) {
  if (Platform.environment['F09_PRINT_COUNTS'] != '1') return;
  final text = rows.entries.map((e) => '${e.key}: ${e.value}').join('; ');
  // ignore: avoid_print
  print('F09A_COUNTS $name $text');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      '100 eligible notes: one projection per note per snapshot, with and '
      'without a search, and the same state as before', () async {
    final source = _CountingSource(_distinct());
    final n = source.visible().length;
    expect(n, 100);
    final bloc = NotesBloc(
        source: source, isSyncEnabled: () => false, isOnline: () async => true);
    addTearDown(bloc.close);
    final rows = <String, String>{};
    for (final (type, sort, tag, query) in _views()) {
      final view = '${type.name}|${sort.name}|$tag|"$query"';
      await _send(bloc, NotesTypeFilterChanged(type));
      await _send(bloc, NotesSortChanged(sort));
      await _send(bloc, NotesTagFilterChanged(tag));
      source.projections = 0;
      await _send(bloc, NotesQueryChanged(query)); // one snapshot
      final onSearch = source.projections;
      source.projections = 0;
      source.poke(); // a source change that changes nothing: one snapshot
      await _settle();
      final onSourceChange = source.projections;
      source.projections = 0;
      final expected = _before(source, type, sort, tag, query);
      final before = source.projections;

      expect(_after(bloc.state), expected, reason: view);
      expect(onSearch, n, reason: '$view: projections for a search change');
      expect(onSourceChange, n, reason: '$view: projections for a poke');
      expect(before, greaterThan(n), reason: '$view: the earlier snapshot');
      rows[view] = 'before $before, now $onSourceChange';
    }
    _report('distinct n=$n', rows);
  });

  for (final seed in [1, 2, 3, 4]) {
    for (final size in [40, 90]) {
      test(
          'tied creation times (seed $seed, $size notes): every view equals '
          'the earlier snapshot exactly', () async {
        final source = _CountingSource(_tied(seed, size));
        final bloc = NotesBloc(
            source: source,
            isSyncEnabled: () => false,
            isOnline: () async => true);
        addTearDown(bloc.close);
        for (final (type, sort, tag, query) in _views()) {
          await _send(bloc, NotesTypeFilterChanged(type));
          await _send(bloc, NotesSortChanged(sort));
          await _send(bloc, NotesTagFilterChanged(tag));
          await _send(bloc, NotesQueryChanged(query));
          expect(_after(bloc.state), _before(source, type, sort, tag, query),
              reason: '${type.name}|${sort.name}|$tag|"$query"');
        }
      });
    }
  }

  test(
      'a single tie, at the front of the to-do view, keeps the order the '
      'source gives', () async {
    // Two pinned legacy to-dos created at the same instant lead the to-do
    // view; every other note has its own time. Look for an insertion order
    // in which the 60-note eligible read orders the pair differently from
    // the 26-note to-do read: only the source's to-do read is then right.
    for (var seed = 0; seed < 200; seed++) {
      final notes = [
        for (var i = 0; i < 58; i++) _note(i, minute: 10 + i, pinned: false),
        _note(1002, minute: 0, pinned: true),
        _note(1007, minute: 0, pinned: true),
      ]..shuffle(math.Random(seed));
      final source = _CountingSource(notes);
      List<String> pair(List<Note> read) => [
            for (final n in read)
              if (n.id == 'n1002' || n.id == 'n1007') n.id,
          ];
      final todos = pair(source.visible(type: NoteTypeFilter.todos));
      if (listEquals(pair(source.visible()), todos)) continue;
      final bloc = NotesBloc(
          source: source,
          isSyncEnabled: () => false,
          isOnline: () async => true);
      addTearDown(bloc.close);
      for (final sort in NoteSort.values) {
        await _send(bloc, NotesSortChanged(sort));
        await _send(bloc, const NotesTypeFilterChanged(NoteTypeFilter.todos));
        expect(_after(bloc.state),
            _before(source, NoteTypeFilter.todos, sort, null, ''),
            reason: 'seed $seed, ${sort.name}');
        expect([for (final n in bloc.state.notes.take(2)) n.id],
            pair(source.visible(type: NoteTypeFilter.todos, sort: sort)),
            reason: 'seed $seed, ${sort.name}');
        await _send(bloc, const NotesTypeFilterChanged(NoteTypeFilter.all));
      }
      _report('front tie', {
        'seed': '$seed',
        'eligible pair': '${pair(source.visible())}',
        'to-do pair': '$todos',
      });
      return;
    }
    fail('no insertion order separated the two reads: the case is vacuous');
  });

  group('the real repository beyond its projection cache', () {
    late Directory directory;
    late NotesRepository repository;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('atomic-f09a-');
      Hive.init(directory.path);
      final box = await Hive.openBox('f09a-notes');
      SyncStatusHelper.syncBox = await Hive.openBox<bool>('f09a-sync');
      repository = NotesRepository.forTest(
          box: box,
          api: TestApi(),
          vault: TestVault(),
          checkConnectivity: () async => [ConnectivityResult.wifi]);
      await repository.start();
      final notes = _distinct();
      for (final note in notes) {
        final deleted = note.deleted;
        note.deleted = false;
        await repository.save(note);
        if (deleted) await repository.deleteNotes([note.id]);
      }
    });

    tearDown(() async {
      await repository.stop(waitForSync: true);
      repository.dispose();
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test(
        'no to-do or tag read: the bloc requests one projection per eligible '
        'note, and shows what the earlier snapshot showed', () async {
      final source = _Recording(repository);
      final n = repository.visible().length;
      expect(n, 100);
      final bloc = NotesBloc(
          source: source,
          isSyncEnabled: () => false,
          isOnline: () async => true);
      addTearDown(bloc.close);
      final rows = <String, String>{};
      for (final (type, sort, tag, query) in _views()) {
        final view = '${type.name}|${sort.name}|$tag|"$query"';
        await _send(bloc, NotesTypeFilterChanged(type));
        await _send(bloc, NotesSortChanged(sort));
        await _send(bloc, NotesTagFilterChanged(tag));
        source
          ..projections = 0
          ..reads.clear();
        await _send(bloc, NotesQueryChanged(query)); // one snapshot
        final projections = source.projections;
        final reads = [...source.reads];
        source
          ..projections = 0
          ..reads.clear();
        final expected = _before(source, type, sort, tag, query);
        final beforeReads = [...source.reads];

        expect(_after(bloc.state), expected, reason: view);
        expect(projections, n, reason: '$view: projections requested');
        expect(
            reads.where((r) => r.startsWith('todos|') || !r.endsWith('|-')),
            isEmpty,
            reason: '$view: no read that projects inside the repository');
        expect(beforeReads, contains('todos|-'),
            reason: '$view: the earlier snapshot read the to-dos');
        rows[view] = 'reads before ${beforeReads.join(',')}; '
            'now ${reads.join(',')} + $projections projections';
      }
      _report('repository n=$n', rows);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
