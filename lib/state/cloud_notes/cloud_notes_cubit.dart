import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_report.dart';
import 'package:atomic_notes/state/ui_message.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// This device against the cloud.
final class CloudNotesState extends Equatable {
  const CloudNotesState({
    this.onDevice = 0,
    this.waiting = 0,
    this.waitingDeletions = 0,
    this.cloud,
    this.checked = false,
    this.checking = false,
    this.working = false,
    this.checkedAt,
    this.lastSyncedAt,
    this.nextAutoSyncAt,
    this.lastReport,
  });

  final int onDevice;

  /// Dirty changes on this device, including pending deletions.
  final int waiting;

  final int waitingDeletions;

  int get waitingNotes => (waiting - waitingDeletions).clamp(0, onDevice);

  /// Notes in the cloud. Null until a check succeeds, or when it failed.
  final int? cloud;
  final bool checked;
  final bool checking;

  /// A sync or an upload is running.
  final bool working;
  final DateTime? checkedAt;
  final DateTime? lastSyncedAt;
  final DateTime? nextAutoSyncAt;

  /// This screen's last request only. Cleared on another attempt or session change.
  final SyncAttemptReport? lastReport;

  /// Live notes with no local changes waiting. Does not verify cloud content.
  int get synced => onDevice - waitingNotes;

  CloudNotesState copyWith({
    int? onDevice,
    int? waiting,
    int? waitingDeletions,
    int? cloud,
    bool clearCloud = false,
    bool? checked,
    bool? checking,
    bool? working,
    DateTime? checkedAt,
    SyncAttemptReport? lastReport,
    bool clearReport = false,
  }) =>
      CloudNotesState(
        onDevice: onDevice ?? this.onDevice,
        waiting: waiting ?? this.waiting,
        waitingDeletions: waitingDeletions ?? this.waitingDeletions,
        cloud: clearCloud ? null : (cloud ?? this.cloud),
        checked: checked ?? this.checked,
        checking: checking ?? this.checking,
        working: working ?? this.working,
        checkedAt: checkedAt ?? this.checkedAt,
        lastSyncedAt: lastSyncedAt,
        nextAutoSyncAt: nextAutoSyncAt,
        lastReport: clearReport ? null : (lastReport ?? this.lastReport),
      );

  @override
  List<Object?> get props => [
        onDevice,
        waiting,
        waitingDeletions,
        cloud,
        checked,
        checking,
        working,
        checkedAt,
        lastSyncedAt,
        nextAutoSyncAt,
        lastReport,
      ];
}

/// State and actions of the Cloud Notes screen. Checking the cloud only counts its notes: it never
/// pulls or merges anything, so looking can never change what is on this device.
class CloudNotesCubit extends Cubit<CloudNotesState> {
  CloudNotesCubit({required NotesSource source})
      : _source = source,
        super(_read(source, const CloudNotesState())) {
    _source.addListener(_sourceChanged);
    _reportIdentity = _identity;
  }

  final NotesSource _source;
  Object? _reportIdentity;
  Object? get _identity {
    final source = _source;
    return source is SyncReportSource
        ? (source as SyncReportSource).syncReportIdentity
        : null;
  }

  /// [base] with the numbers the store holds now.
  static CloudNotesState _read(NotesSource source, CloudNotesState base) =>
      CloudNotesState(
        onDevice: source.count,
        waiting: source.pendingCount,
        waitingDeletions: source.binNotes.where((note) => note.dirty).length,
        cloud: base.cloud,
        checked: base.checked,
        checking: base.checking,
        working: base.working,
        checkedAt: base.checkedAt,
        lastSyncedAt: source.lastSyncedAt,
        nextAutoSyncAt: source.nextAutoSyncAt,
        lastReport: base.lastReport,
      );

  void _sourceChanged() {
    if (isClosed) return;
    final identity = _identity;
    final base =
        identity == _reportIdentity ? state : state.copyWith(clearReport: true);
    _reportIdentity = identity;
    final next = _read(_source, base);
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
  /// sync: Server pricing applies per charged upload batch. Answers with the message to show,
  /// or null when a sync was already running or the screen has gone.
  Future<UiMessage?> sync({required bool uploadAll}) async {
    if (state.working) return null;
    final identity = _identity;
    emit(state.copyWith(working: true, clearReport: true));
    try {
      if (uploadAll) await _source.markAllForUpload();
      if (isClosed || _identity != identity) return null;
      final source = _source;
      final SyncAttemptReport? report = source is SyncReportSource
          ? await (source as SyncReportSource).syncWithReport(instant: true)
          : null;
      final bool ok = report?.completed ?? await _source.syncNow(instant: true);
      if (isClosed || _identity != identity) return null;
      if (report?.activity == SyncAttemptActivity.retired ||
          report?.activity == SyncAttemptActivity.joined) return null;
      emit(state.copyWith(lastReport: report));
      final error = report == null ? _source.lastError : report.errorMessage;
      return UiMessage(
        ok
            ? (uploadAll
                ? 'All notes uploaded to the cloud'
                : 'Synced with the cloud')
            : (error ?? 'Sync failed. Check your connection.'),
        3000,
      );
    } catch (_) {
      if (isClosed || _identity != identity) return null;
      // No totals are confirmed when the capability itself throws.
      return const UiMessage(
          'Sync could not finish. Your notes remain on this device.', 3000);
    } finally {
      if (!isClosed) emit(state.copyWith(working: false));
    }
  }
}
