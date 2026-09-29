import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:flutter/foundation.dart';

/// A notes store in memory, for tests of the state layer and the screens. It keeps the same
/// promises as the real one: a save marks the note as waiting to sync, a delete keeps a
/// tombstone, and every change (and every sync) tells the listeners.
class FakeNotesSource extends ChangeNotifier implements NotesSource {
  FakeNotesSource({List<Note>? notes, this.limit = 30}) {
    if (notes != null) all.addAll(notes);
  }

  final List<Note> all = [];

  @override
  int limit;

  @override
  String? lastError;

  @override
  DateTime? lastSyncedAt;

  @override
  DateTime? nextAutoSyncAt;

  /// What the next [cloudCount] answers (null: the cloud cannot be reached).
  int? cloudNotes = 0;

  /// When false, [deleteForever] removes nothing, like a deletion that has not reached the cloud.
  bool deleteForeverWorks = true;
  bool wipeRemoteWorks = true;
  int markAllCalls = 0;

  /// What the next [syncNow] answers.
  bool syncResult = true;

  /// When set, [syncNow] waits for it, so a test can look at the screen mid-sync.
  Completer<void>? syncGate;
  int syncCalls = 0;
  bool? lastSyncInstant;
  int saveCalls = 0;
  final List<String> deletedIds = [];

  @override
  List<Note> visible({NoteFilter filter = NoteFilter.newest}) {
    final list = all.where((n) => !n.deleted).toList();
    switch (filter) {
      case NoteFilter.todos:
        list.retainWhere((n) => n.kind == NoteKind.todo);
      case NoteFilter.notes:
        list.retainWhere((n) => n.kind == NoteKind.text);
      case NoteFilter.newest:
      case NoteFilter.oldest:
        break;
    }
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return filter == NoteFilter.oldest
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  @override
  Note? byId(String id) {
    for (final n in all) {
      if (n.id == id) return n;
    }
    return null;
  }

  @override
  List<Note> get binNotes {
    final list = all.where((n) => n.deleted).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  int get count => all.where((n) => !n.deleted).length;

  @override
  int get pendingCount => all.where((n) => n.dirty).length;

  @override
  Future<void> save(Note note) async {
    saveCalls++;
    note.touch();
    if (byId(note.id) == null) all.add(note);
    notifyListeners();
  }

  @override
  Future<void> deleteNotes(Iterable<String> ids) async {
    for (final id in ids) {
      final n = byId(id);
      if (n == null) continue;
      deletedIds.add(id);
      n.deleted = true;
      n.touch();
    }
    notifyListeners();
  }

  @override
  Future<bool> syncNow({bool instant = false}) async {
    syncCalls++;
    lastSyncInstant = instant;
    if (syncGate != null) await syncGate!.future;
    // A real sync clears the waiting notes when it works.
    if (syncResult) {
      for (final n in all) {
        n.dirty = false;
      }
    }
    notifyListeners();
    return syncResult;
  }

  @override
  Future<bool> restoreNote(String id) async {
    final n = byId(id);
    if (n == null || !n.deleted || count >= limit) return false;
    n.deleted = false;
    n.touch();
    notifyListeners();
    return true;
  }

  @override
  Future<int> deleteForever(Iterable<String> ids) async {
    if (!deleteForeverWorks) return 0;
    final targets = ids.where((id) => byId(id)?.deleted == true).toList();
    all.removeWhere((n) => targets.contains(n.id));
    notifyListeners();
    return targets.length;
  }

  @override
  Future<int?> cloudCount() async => cloudNotes;

  @override
  Future<int> markAllForUpload() async {
    markAllCalls++;
    var marked = 0;
    for (final n in all.where((n) => !n.deleted)) {
      n.dirty = true;
      marked++;
    }
    notifyListeners();
    return marked;
  }

  @override
  Future<WipeOutcome> wipeRemote() async => wipeRemoteWorks
      ? const WipeOutcome(true, 'Cloud notes wiped. The notes on this device are untouched.')
      : const WipeOutcome(false, 'Could not wipe the cloud.');

  @override
  Future<int> wipeLocalNotes() async {
    final removed = all.length;
    all.clear();
    notifyListeners();
    return removed;
  }

  /// Tells the listeners without changing anything, like a sync starting or ending.
  void poke() => notifyListeners();

  /// A change made behind the screen's back, for example a note deleted on another device.
  void changeBehindTheScenes(void Function() change) {
    change();
    notifyListeners();
  }
}

/// A note that is already synced, like one that came from the cloud.
Note syncedNote(
  String id, {
  String title = '',
  String body = '',
  NoteKind kind = NoteKind.text,
  List<TodoItem>? items,
  DateTime? createdAt,
}) {
  final n = Note(
    id: id,
    kind: kind,
    title: title,
    body: body,
    items: items ?? [],
    createdAt: createdAt ?? DateTime.utc(2026, 9, 1),
  );
  n.dirty = false;
  return n;
}
