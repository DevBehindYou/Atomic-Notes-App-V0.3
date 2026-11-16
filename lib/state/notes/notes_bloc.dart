import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/note_projection.dart';
import 'package:atomic_notes/database/note_quota.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/state/ui_message.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'notes_event.dart';
part 'notes_state.dart';

/// State of the notes screens: the list on view (filtered and searched once, here, not on every
/// build), the selection, the counts in the header, and the sync button.
///
/// The notes and the sync engine stay in the [NotesSource]; this listens to it and turns every
/// change into one [NotesState]. A change that alters nothing on screen produces an equal state,
/// which [Bloc] drops, so the screens rebuild only when something they show has changed.
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  NotesBloc({
    required NotesSource source,
    required bool Function() isSyncEnabled,
    required Future<bool> Function() isOnline,
  })  : _source = source,
        _isSyncEnabled = isSyncEnabled,
        _isOnline = isOnline,
        super(_snapshot(source, const NotesState())) {
    on<_NotesSourceChanged>(_onSourceChanged);
    on<NotesViewReset>(_onViewReset);
    on<NotesFilterChanged>(_onFilterChanged);
    on<NotesSortChanged>(_onSortChanged);
    on<NotesTypeFilterChanged>(_onTypeChanged);
    on<NotesTagFilterChanged>(_onTagChanged);
    on<NotesQueryChanged>(_onQueryChanged);
    on<NoteSelectionToggled>(_onSelectionToggled);
    on<NoteSelectionCleared>(_onSelectionCleared);
    on<NoteSelectionAllToggled>(_onSelectionAllToggled);
    on<NotesDeleteSelected>(_onDeleteSelected);
    on<NoteSaved>(_onNoteSaved);
    on<NoteDeleted>(_onNoteDeleted);
    on<NoteItemToggled>(_onItemToggled,
        transformer: (events, mapper) => events.asyncExpand(mapper));
    on<NotesSyncRequested>(_onSyncRequested);
    _source.addListener(_sourceChanged);
  }

  final NotesSource _source;
  final bool Function() _isSyncEnabled;
  final Future<bool> Function() _isOnline;

  NoteProjection projectionFor(Note note) => projectNote(_source, note);

  /// Whether the store can acknowledge an editor's save (S1). Stores that
  /// cannot keep the earlier unacknowledged flow.
  bool get supportsOwnedSave => _source is EditorNoteSaveSource;

  /// The write context for an editor opening now, or null when nobody may
  /// write (or the store cannot acknowledge saves).
  NoteEditorContext? captureEditorContext() {
    final source = _source;
    return source is EditorNoteSaveSource
        ? (source as EditorNoteSaveSource).captureEditorContext()
        : null;
  }

  int _noticeCount = 0;
  bool _manualSyncInProgress = false;

  void _sourceChanged() {
    if (!isClosed) add(const _NotesSourceChanged());
  }

  @override
  Future<void> close() {
    _source.removeListener(_sourceChanged);
    return super.close();
  }

  // ---- the snapshot -----------------------------------------------------

  /// The state for [base]'s type, tag, order, search and selection, read from [source] now.
  ///
  /// Counts and the list on view come from the same read of the current
  /// owner's notes, on every source change, not only when the notes on view
  /// change: a note hidden by the search can still change the chip counts.
  ///
  /// Each of those notes is projected once, here, and that projection answers
  /// the to-do count, the tag counts, the to-do and tag filters and the
  /// search. (Beyond the projection cache's capacity, every extra scan
  /// decoded the overflow notes again on each source change.)
  static NotesState _snapshot(NotesSource source, NotesState base,
      {bool manualSyncInProgress = false}) {
    final eligible = source.visible();
    final projected = [
      for (final n in eligible) projectNote(source, n, evict: false),
    ];
    final projectionOf = Map<Note, NoteProjection>.identity();
    var noteCount = 0;
    var todoCount = 0;
    final tagCounts = <String, int>{};
    for (var i = 0; i < eligible.length; i++) {
      final n = eligible[i];
      final p = projected[i];
      projectionOf[n] = p;
      if (n.kind == NoteKind.text) noteCount++;
      if (_isTodo(n, p)) todoCount++;
      for (final t in p.tags.toSet()) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }
    final typeCounts = <NoteTypeFilter, int>{
      NoteTypeFilter.all: eligible.length,
      NoteTypeFilter.notes: noteCount,
      NoteTypeFilter.todos: todoCount,
    };
    // A tag that no live note carries any more falls back to every tag; the
    // type, order and search stay. A tag missing only from the search
    // results stays selected.
    final tag =
        base.tag != null && tagCounts.containsKey(base.tag) ? base.tag : null;

    final filtered =
        _onView(source, eligible, projected, base.type, base.sort, tag);
    final q = base.query.trim().toLowerCase();
    final shown = q.isEmpty
        ? filtered
        : filtered
            .where((n) =>
                n.title.toLowerCase().contains(q) ||
                (projectionOf[n] ?? projectNote(source, n, evict: false))
                    .matches(q))
            .toList();
    // Keep only selected notes that are still on view, so an action never
    // reaches a note the person can no longer see (deleted, pulled in as a
    // tombstone, retagged or locked elsewhere). The same set is kept when
    // nothing was dropped.
    final shownIds = {for (final n in shown) n.id};
    final stillThere = base.selected.where(shownIds.contains).toSet();
    final nextAutoSyncAt = source.nextAutoSyncAt;
    return base.copyWith(
      notes: List<Note>.unmodifiable(shown),
      signature: noteSignature(shown),
      tag: tag,
      clearTag: tag == null,
      typeCounts: Map.unmodifiable(typeCounts),
      tagCounts: Map.unmodifiable(tagCounts),
      selected: stillThere.length == base.selected.length
          ? base.selected
          : stillThere,
      count: source.count,
      limit: source.limit,
      pending: source.pendingCount,
      syncing: manualSyncInProgress || source.isSyncing,
      syncError: source.lastError,
      clearSyncError: source.lastError == null,
      binCount: source.binNotes.length,
      nextAutoSyncAt: nextAutoSyncAt,
      // A cleared source deadline is a change, not an omitted state update.
      clearNextAutoSyncAt: nextAutoSyncAt == null,
    );
  }

  /// The notes on view for [type], [sort] and [tag], in exactly the order
  /// `source.visible(type: type, sort: sort, tag: tag)` returns them.
  ///
  /// Without a to-do or tag filter no projection decides what is on view, so
  /// the source's own read answers (the eligible read itself for the default
  /// view). With one, the eligible notes' [projected] data decides, and the
  /// kept notes are sorted here. That order is unique only while no two kept
  /// notes compare equal. Equal ones are left in an order that depends on the
  /// store's insertion order and on the sort algorithm (List.sort is not
  /// stable above 32 items), which only the source can reproduce, so a tie
  /// reads the list from the source.
  static List<Note> _onView(NotesSource source, List<Note> eligible,
      List<NoteProjection> projected, NoteTypeFilter type, NoteSort sort,
      String? tag) {
    if (type != NoteTypeFilter.todos && tag == null) {
      return type == NoteTypeFilter.all && sort == NoteSort.newest
          ? eligible
          : source.visible(type: type, sort: sort);
    }
    final kept = [
      for (var i = 0; i < eligible.length; i++)
        if (_onViewFor(eligible[i], projected[i], type, tag)) eligible[i],
    ];
    int compare(Note a, Note b) => _compareForView(a, b, sort);
    kept.sort(compare);
    for (var i = 1; i < kept.length; i++) {
      if (compare(kept[i - 1], kept[i]) == 0) {
        return source.visible(type: type, sort: sort, tag: tag);
      }
    }
    return kept;
  }

  /// Whether [note], projected as [projection], is cut to [type] and [tag]
  /// the way [NotesSource.visible] cuts it.
  static bool _onViewFor(Note note, NoteProjection projection,
      NoteTypeFilter type, String? tag) {
    final ofType = switch (type) {
      NoteTypeFilter.all => true,
      NoteTypeFilter.notes => note.kind == NoteKind.text,
      NoteTypeFilter.todos => _isTodo(note, projection),
    };
    return ofType && (tag == null || projection.tags.contains(tag));
  }

  /// A legacy to-do, or any note with a checklist line (a mixed note is both
  /// a note and a to-do).
  static bool _isTodo(Note note, NoteProjection projection) =>
      note.kind == NoteKind.todo || projection.hasChecklist;

  /// [NotesSource.visible]'s order: pinned first, then by creation time.
  static int _compareForView(Note a, Note b, NoteSort sort) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return sort == NoteSort.oldest
        ? a.createdAt.compareTo(b.createdAt)
        : b.createdAt.compareTo(a.createdAt);
  }

  NotesNotice _notice(String text, int millis, {bool fromSync = false}) =>
      NotesNotice(
          id: ++_noticeCount, text: text, millis: millis, fromSync: fromSync);

  /// Emits [next] only when it differs from the current state. ([Bloc] itself drops an equal state
  /// too, but not the very first one, so a store that says nothing new would still cost one rebuild.)
  void _put(Emitter<NotesState> emit, NotesState next) {
    if (next != state) emit(next);
  }

  // ---- events -----------------------------------------------------------

  NotesState _currentSnapshot(NotesState base) =>
      _snapshot(_source, base, manualSyncInProgress: _manualSyncInProgress);

  void _onSourceChanged(_NotesSourceChanged event, Emitter<NotesState> emit) =>
      _put(emit, _currentSnapshot(state));

  void _onViewReset(NotesViewReset event, Emitter<NotesState> emit) => _put(
      emit,
      _currentSnapshot(state.copyWith(
          sort: NoteSort.newest,
          type: NoteTypeFilter.all,
          clearTag: true,
          query: '',
          selected: const {})));

  /// Applies a view change. A change of what is on view (type, tag or search)
  /// clears the selection and says so, so Delete never reaches a note the
  /// person stopped seeing; a change of order keeps it.
  void _changeView(Emitter<NotesState> emit, NotesState next,
      {required bool narrowsDifferently}) {
    if (narrowsDifferently && state.selected.isNotEmpty) {
      next = next.copyWith(
          selected: const {}, notice: _notice('Selection cleared', 1500));
    }
    _put(emit, _currentSnapshot(next));
  }

  void _onFilterChanged(NotesFilterChanged event, Emitter<NotesState> emit) =>
      _changeView(emit, state.copyWith(filter: event.filter),
          narrowsDifferently: event.filter.type != state.type);

  void _onSortChanged(NotesSortChanged event, Emitter<NotesState> emit) =>
      _changeView(emit, state.copyWith(sort: event.sort),
          narrowsDifferently: false);

  void _onTypeChanged(NotesTypeFilterChanged event, Emitter<NotesState> emit) =>
      _changeView(emit, state.copyWith(type: event.type),
          narrowsDifferently: event.type != state.type);

  void _onTagChanged(NotesTagFilterChanged event, Emitter<NotesState> emit) =>
      _changeView(
          emit,
          event.tag == null
              ? state.copyWith(clearTag: true)
              : state.copyWith(tag: event.tag),
          narrowsDifferently: event.tag != state.tag);

  void _onQueryChanged(NotesQueryChanged event, Emitter<NotesState> emit) =>
      _changeView(emit, state.copyWith(query: event.query),
          narrowsDifferently: event.query.trim() != state.query.trim());

  void _onSelectionToggled(
      NoteSelectionToggled event, Emitter<NotesState> emit) {
    final next = {...state.selected};
    if (!next.remove(event.id)) next.add(event.id);
    _put(emit, state.copyWith(selected: next));
  }

  void _onSelectionCleared(
          NoteSelectionCleared event, Emitter<NotesState> emit) =>
      _put(emit, state.copyWith(selected: const {}));

  void _onSelectionAllToggled(
      NoteSelectionAllToggled event, Emitter<NotesState> emit) {
    final shown = state.notes;
    _put(
        emit,
        state.copyWith(
            selected: state.selected.length == shown.length
                ? const {}
                : {for (final n in shown) n.id}));
  }

  Future<void> _onDeleteSelected(
      NotesDeleteSelected event, Emitter<NotesState> emit) async {
    final ids = state.selected.toList();
    if (ids.isEmpty) return;
    await _source.deleteNotes(ids);
    emit(state.copyWith(
      selected: const {},
      notice: _notice(
          ids.length == 1
              ? 'Note moved to the Recycle Bin'
              : '${ids.length} notes moved to the Recycle Bin',
          1500),
    ));
  }

  /// Saves locally. With an acknowledgement, the store's receipt for this
  /// attempt and its editor context decides the outcome: success only when
  /// the store confirms the write; a failure is reported to observers instead
  /// of rethrown. Without one, [NotesSource.save] runs as before.
  Future<void> _onNoteSaved(NoteSaved event, Emitter<NotesState> emit) async {
    final ack = event.ack;
    if (ack == null) return _source.save(event.note);
    final source = _source;
    final context = event.context;
    if (source is! EditorNoteSaveSource || context == null) {
      ack._complete(const NoteSaveRejected());
      return;
    }
    final receipt = await (source as EditorNoteSaveSource)
        .saveForEditor(event.note, context);
    switch (receipt) {
      case NoteLocalSaveStored():
        ack._complete(const NoteSaveSucceeded());
      case NoteLocalSaveRetired(:final reason):
        ack._complete(NoteSaveRetired(reason));
      case NoteLocalSaveFailed(:final error):
        ack._complete(NoteSaveFailed(error));
        onError(error, StackTrace.current);
    }
  }

  Future<void> _onNoteDeleted(
      NoteDeleted event, Emitter<NotesState> emit) async {
    if (_source.byId(event.id) == null) return;
    await _source.deleteNotes([event.id]);
    emit(_currentSnapshot(state).copyWith(
      selected: state.selected.where((id) => id != event.id).toSet(),
      notice: _notice('Note moved to the Recycle Bin', 1500),
    ));
  }

  Future<void> _onItemToggled(
      NoteItemToggled event, Emitter<NotesState> emit) async {
    final current = _source.byId(event.note.id);
    if (current == null || current.deleted) return;
    if (current.kind == NoteKind.text) {
      final document = NoteDocument.fromNote(current);
      if (document.isReadOnly ||
          event.index < 0 ||
          event.index >= document.lines.length ||
          !document.lines[event.index].isChecklist) {
        return;
      }
      document.setDone(event.index, !document.lines[event.index].done);
      await _source.save(document.toNote(current));
      return;
    }
    if (event.index < 0 || event.index >= current.items.length) {
      return;
    }
    final item = current.items[event.index];
    item.done = !item.done;
    await _source.save(current);
  }

  Future<void> _onSyncRequested(
      NotesSyncRequested event, Emitter<NotesState> emit) async {
    if (_manualSyncInProgress || _source.isSyncing) return;
    // Read the switch at the moment of use: it can be flipped on the settings screen at any time.
    if (!_isSyncEnabled()) {
      emit(state.copyWith(
          notice: _notice('Cloud Sync is Off', 1000, fromSync: true)));
      return;
    }
    _manualSyncInProgress = true;
    emit(state.copyWith(syncing: true));
    try {
      if (!await _isOnline()) {
        emit(state.copyWith(
            syncing: _source.isSyncing,
            notice: _notice('No Internet Connection!', 1000, fromSync: true)));
        return;
      }
      // Only the Server knows each operation's charge and refund. The bool
      // result confirms completion, not a balance change or an empty pull.
      final ok = await _source.syncNow(instant: event.instant);
      emit(state.copyWith(
        syncing: _source.isSyncing,
        notice: ok
            ? _notice('Sync finished', 1600, fromSync: true)
            : _notice(
                _source.lastError ??
                    'Sync did not finish. Your notes are saved on this device.',
                3000,
                fromSync: true),
      ));
    } finally {
      _manualSyncInProgress = false;
      if (!emit.isDone) _put(emit, state.copyWith(syncing: _source.isSyncing));
    }
  }
}
