part of 'notes_bloc.dart';

/// One short message for the person, shown as a snack bar. [id] makes two messages with the
/// same words count as two, so the second one is shown too.
final class NotesNotice extends Equatable {
  const NotesNotice({
    required this.id,
    required this.text,
    required this.millis,
    this.fromSync = false,
  });

  final int id;
  final String text;
  final int millis;

  /// True for the answer to the sync button (shown by the app bar), false for the notes list.
  final bool fromSync;

  @override
  List<Object?> get props => [id, text, millis, fromSync];
}

/// What the notes screens show. Immutable, and equal to the previous state when nothing that is
/// shown changed, so a store that only says "I am syncing" rebuilds nothing.
final class NotesState extends Equatable {
  const NotesState({
    this.notes = const [],
    this.signature = 0,
    this.filter = NoteFilter.newest,
    this.query = '',
    this.selected = const {},
    this.count = 0,
    this.limit = NoteQuota.freeLimit,
    this.pending = 0,
    this.binCount = 0,
    this.syncing = false,
    this.notice,
    this.nextAutoSyncAt,
  });

  /// The notes on view: filtered, searched and ordered. The notes themselves are edited in place
  /// by the store, so equality uses [signature], not the list.
  final List<Note> notes;

  /// Changes whenever a note on view changes (its text, ticks, pin, deleted flag or sync state).
  final int signature;
  final NoteFilter filter;
  final String query;
  final Set<String> selected;

  /// Live notes, and the most the account may hold.
  final int count;
  final int limit;

  /// Notes waiting to be sent to the cloud.
  final int pending;

  /// Notes in the Recycle Bin.
  final int binCount;

  /// The sync button was pressed and has not finished.
  final bool syncing;
  final NotesNotice? notice;

  /// When the next automatic sync can send changes, or null when it is open now.
  final DateTime? nextAutoSyncAt;

  bool get selecting => selected.isNotEmpty;
  bool get isAtLimit => count >= limit;
  int get remaining => (limit - count).clamp(0, limit);
  String get usageLabel => '$count / $limit';

  /// True when a filter or a search narrows the list.
  bool get narrowed =>
      filter == NoteFilter.todos ||
      filter == NoteFilter.notes ||
      query.trim().isNotEmpty;

  NotesState copyWith({
    List<Note>? notes,
    int? signature,
    NoteFilter? filter,
    String? query,
    Set<String>? selected,
    int? count,
    int? limit,
    int? pending,
    int? binCount,
    bool? syncing,
    NotesNotice? notice,
    DateTime? nextAutoSyncAt,
  }) =>
      NotesState(
        notes: notes ?? this.notes,
        signature: signature ?? this.signature,
        filter: filter ?? this.filter,
        query: query ?? this.query,
        selected: selected ?? this.selected,
        count: count ?? this.count,
        limit: limit ?? this.limit,
        pending: pending ?? this.pending,
        binCount: binCount ?? this.binCount,
        syncing: syncing ?? this.syncing,
        notice: notice ?? this.notice,
        nextAutoSyncAt: nextAutoSyncAt ?? this.nextAutoSyncAt,
      );

  @override
  List<Object?> get props => [
        signature,
        filter,
        query,
        selected,
        count,
        limit,
        pending,
        binCount,
        syncing,
        notice,
        nextAutoSyncAt,
      ];
}
