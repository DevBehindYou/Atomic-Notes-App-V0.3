import 'package:atomic_notes/database/note.dart';
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
    required int Function() instantSyncCost,
  })  : _source = source,
        _isSyncEnabled = isSyncEnabled,
        _isOnline = isOnline,
        _instantSyncCost = instantSyncCost,
        super(_snapshot(source, const NotesState())) {
    on<_NotesSourceChanged>(_onSourceChanged);
    on<NotesViewReset>(_onViewReset);
    on<NotesFilterChanged>(_onFilterChanged);
    on<NotesQueryChanged>(_onQueryChanged);
    on<NoteSelectionToggled>(_onSelectionToggled);
    on<NoteSelectionCleared>(_onSelectionCleared);
    on<NoteSelectionAllToggled>(_onSelectionAllToggled);
    on<NotesDeleteSelected>(_onDeleteSelected);
    on<NoteSaved>(_onNoteSaved);
    on<NoteItemToggled>(_onItemToggled);
    on<NotesSyncRequested>(_onSyncRequested);
    _source.addListener(_sourceChanged);
  }

  final NotesSource _source;
  final bool Function() _isSyncEnabled;
  final Future<bool> Function() _isOnline;
  final int Function() _instantSyncCost;

  int _noticeCount = 0;

  void _sourceChanged() {
    if (!isClosed) add(const _NotesSourceChanged());
  }

  @override
  Future<void> close() {
    _source.removeListener(_sourceChanged);
    return super.close();
  }

  // ---- the snapshot -----------------------------------------------------

  /// The state for [base]'s filter, search and selection, read from [source] now.
  static NotesState _snapshot(NotesSource source, NotesState base) {
    final all = source.visible(filter: base.filter);
    final q = base.query.trim().toLowerCase();
    final shown = q.isEmpty
        ? all
        : all
            .where((n) =>
                n.title.toLowerCase().contains(q) ||
                n.body.toLowerCase().contains(q) ||
                n.items.any((it) => it.text.toLowerCase().contains(q)))
            .toList();
    // Drop selections for notes that vanished under us (deleted on another device, or pulled in
    // as a tombstone). The same set is kept when nothing was dropped.
    final stillThere =
        base.selected.where((id) => !(source.byId(id)?.deleted ?? true)).toSet();
    return base.copyWith(
      notes: List<Note>.unmodifiable(shown),
      signature: noteSignature(shown),
      selected: stillThere.length == base.selected.length ? base.selected : stillThere,
      count: source.count,
      limit: source.limit,
      pending: source.pendingCount,
      binCount: source.binNotes.length,
      nextAutoSyncAt: source.nextAutoSyncAt,
    );
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

  void _onSourceChanged(_NotesSourceChanged event, Emitter<NotesState> emit) =>
      _put(emit, _snapshot(_source, state));

  void _onViewReset(NotesViewReset event, Emitter<NotesState> emit) => _put(
      emit,
      _snapshot(
          _source,
          state.copyWith(
              filter: NoteFilter.newest, query: '', selected: const {})));

  void _onFilterChanged(NotesFilterChanged event, Emitter<NotesState> emit) =>
      _put(emit, _snapshot(_source, state.copyWith(filter: event.filter)));

  void _onQueryChanged(NotesQueryChanged event, Emitter<NotesState> emit) =>
      _put(emit, _snapshot(_source, state.copyWith(query: event.query)));

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

  Future<void> _onNoteSaved(NoteSaved event, Emitter<NotesState> emit) =>
      _source.save(event.note);

  Future<void> _onItemToggled(
      NoteItemToggled event, Emitter<NotesState> emit) async {
    final item = event.note.items[event.index];
    item.done = !item.done;
    await _source.save(event.note);
  }

  Future<void> _onSyncRequested(
      NotesSyncRequested event, Emitter<NotesState> emit) async {
    if (state.syncing) return;
    // Read the switch at the moment of use: it can be flipped on the settings screen at any time.
    if (!_isSyncEnabled()) {
      emit(state.copyWith(
          notice: _notice('Cloud Sync is Off', 1000, fromSync: true)));
      return;
    }
    emit(state.copyWith(syncing: true));
    if (!await _isOnline()) {
      emit(state.copyWith(
          syncing: false,
          notice: _notice('No Internet Connection!', 1000, fromSync: true)));
      return;
    }
    // The energy gate lives inside the sync: it charges only when there is something to upload
    // and refuses when the balance is short.
    final hadPending = _source.pendingCount > 0;
    final ok = await _source.syncNow(instant: event.instant);
    emit(state.copyWith(
      syncing: false,
      notice: ok
          ? _notice(
              hadPending
                  ? 'Instant sync  ·  -${_instantSyncCost()} energy'
                  : 'Already up to date',
              1600,
              fromSync: true)
          : _notice(
              _source.lastError ??
                  'Sync failed — changes are still only on this device',
              3000,
              fromSync: true),
    ));
  }
}
