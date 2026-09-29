import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/state/ui_message.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// This device against the cloud.
final class CloudNotesState extends Equatable {
  const CloudNotesState({
    this.onDevice = 0,
    this.waiting = 0,
    this.cloud,
    this.checked = false,
    this.checking = false,
    this.working = false,
    this.checkedAt,
    this.lastSyncedAt,
    this.nextAutoSyncAt,
  });

  final int onDevice;

  /// Notes edited on this device that have not reached the cloud.
  final int waiting;

  /// Notes in the cloud. Null until a check succeeds, or when it failed.
  final int? cloud;
  final bool checked;
  final bool checking;

  /// A sync or an upload is running.
  final bool working;
  final DateTime? checkedAt;
  final DateTime? lastSyncedAt;
  final DateTime? nextAutoSyncAt;

  int get synced => onDevice - waiting < 0 ? 0 : onDevice - waiting;

  CloudNotesState copyWith({
    int? onDevice,
    int? waiting,
    int? cloud,
    bool clearCloud = false,
    bool? checked,
    bool? checking,
    bool? working,
    DateTime? checkedAt,
  }) =>
      CloudNotesState(
        onDevice: onDevice ?? this.onDevice,
        waiting: waiting ?? this.waiting,
        cloud: clearCloud ? null : (cloud ?? this.cloud),
        checked: checked ?? this.checked,
        checking: checking ?? this.checking,
        working: working ?? this.working,
        checkedAt: checkedAt ?? this.checkedAt,
        lastSyncedAt: lastSyncedAt,
        nextAutoSyncAt: nextAutoSyncAt,
      );

  @override
  List<Object?> get props => [
        onDevice,
        waiting,
        cloud,
        checked,
        checking,
        working,
        checkedAt,
        lastSyncedAt,
        nextAutoSyncAt,
      ];
}

/// State and actions of the Cloud Notes screen. Checking the cloud only counts its notes: it never
/// pulls or merges anything, so looking can never change what is on this device.
class CloudNotesCubit extends Cubit<CloudNotesState> {
  CloudNotesCubit({required NotesSource source})
      : _source = source,
        super(_read(source, const CloudNotesState())) {
    _source.addListener(_sourceChanged);
  }

  final NotesSource _source;

  /// [base] with the numbers the store holds now.
  static CloudNotesState _read(NotesSource source, CloudNotesState base) =>
      CloudNotesState(
        onDevice: source.count,
        waiting: source.pendingCount,
        cloud: base.cloud,
        checked: base.checked,
        checking: base.checking,
        working: base.working,
        checkedAt: base.checkedAt,
        lastSyncedAt: source.lastSyncedAt,
        nextAutoSyncAt: source.nextAutoSyncAt,
      );

  void _sourceChanged() {
    if (isClosed) return;
    final next = _read(_source, state);
    if (next != state) emit(next);
  }

  @override
  Future<void> close() {
    _source.removeListener(_sourceChanged);
    return super.close();
  }

  /// Counts the notes in the cloud.
  Future<void> check() async {
    if (state.checking) return;
    emit(state.copyWith(checking: true));
    final int? count = await _source.cloudCount();
    if (isClosed) return;
    emit(state.copyWith(
      cloud: count,
      clearCloud: count == null,
      checked: true,
      checking: false,
      checkedAt: DateTime.now(),
    ));
  }

  /// Sends the edited notes now (or every note, with [uploadAll]). Both buttons are the instant
  /// sync: they cost 10 energy when there is something to send. Answers with the message to show,
  /// or null when a sync was already running or the screen has gone.
  Future<UiMessage?> sync({required bool uploadAll}) async {
    if (state.working) return null;
    emit(state.copyWith(working: true));
    if (uploadAll) await _source.markAllForUpload();
    final bool ok = await _source.syncNow(instant: true);
    if (isClosed) return null;
    emit(state.copyWith(working: false));
    return UiMessage(
      ok
          ? (uploadAll
              ? 'All notes uploaded to the cloud'
              : 'Synced with the cloud')
          : (_source.lastError ?? 'Sync failed. Check your connection.'),
      3000,
    );
  }
}
