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
/// shown changed. Sync activity changes the status controls without changing the note signature.
final class NotesState extends Equatable {
  const NotesState({
    this.notes = const [],
    this.signature = 0,
    this.sort = NoteSort.newest,
    this.type = NoteTypeFilter.all,
    this.tag,
    this.typeCounts = const {},
    this.tagCounts = const {},
    this.query = '',
    this.selected = const {},
    this.count = 0,
    this.limit = NoteQuota.freeLimit,
    this.pending = 0,
    this.binCount = 0,
    this.syncing = false,
    this.syncError,
    this.notice,
    this.nextAutoSyncAt,
  });

  /// The notes on view: filtered, searched and ordered. The notes themselves are edited in place
  /// by the store, so equality uses [signature], not the list.
  final List<Note> notes;

  /// Changes whenever a note on view changes (its text, ticks, pin, deleted flag or sync state).
  final int signature;

  /// The order, the kind of note and the exact tag on view. Independent of
  /// each other and of the search.
  final NoteSort sort;
  final NoteTypeFilter type;
  final String? tag;

  /// Chip counts over every live note of the current owner, before search
  /// and filters, so they stay put while typing. A mixed note counts under
  /// both Notes and To-dos; [NoteTypeFilter.all] counts each note once.
  final Map<NoteTypeFilter, int> typeCounts;

  /// How many live notes carry each tag.
  final Map<String, int> tagCounts;

  final String query;
  final Set<String> selected;

  /// Live notes, and the most the account may hold.
  final int count;
  final int limit;

  /// Notes waiting to be sent to the cloud.
  final int pending;

  /// Notes in the Recycle Bin.
  final int binCount;

  /// A repository sync or the manual button's connectivity check is in progress.
  final bool syncing;

  /// The latest repository failure, including automatic attempts; null after a retry starts.
  final String? syncError;
  final NotesNotice? notice;

  /// When the next automatic sync can send changes, or null when it is open now.
  final DateTime? nextAutoSyncAt;

  bool get selecting => selected.isNotEmpty;
  bool get isAtLimit => count >= limit;
  int get remaining => (limit - count).clamp(0, limit);
  String get usageLabel => '$count / $limit';

  /// How many notes are on view after the filters and the search.
  int get resultCount => notes.length;

  /// Legacy: the old one-value filter for the current type and order (see
  /// [NoteFilterParts]). Kept until the Home screen moves to [sort], [type]
  /// and [tag].
  NoteFilter get filter => NoteFilterParts.of(type, sort);

  /// True when a type, a tag or a search narrows the list.
  bool get narrowed =>
      type != NoteTypeFilter.all || tag != null || query.trim().isNotEmpty;

  /// [filter] is the legacy setter: it sets [type] and [sort] with its old
  /// meaning. [clearTag] removes the tag filter.
  NotesState copyWith({
    List<Note>? notes,
    int? signature,
    NoteFilter? filter,
    NoteSort? sort,
    NoteTypeFilter? type,
    String? tag,
    bool clearTag = false,
    Map<NoteTypeFilter, int>? typeCounts,
    Map<String, int>? tagCounts,
    String? query,
    Set<String>? selected,
    int? count,
    int? limit,
    int? pending,
    int? binCount,
    bool? syncing,
    String? syncError,
    bool clearSyncError = false,
    NotesNotice? notice,
    DateTime? nextAutoSyncAt,
    bool clearNextAutoSyncAt = false,
  }) =>
      NotesState(
        notes: notes ?? this.notes,
        signature: signature ?? this.signature,
        sort: sort ?? filter?.sort ?? this.sort,
        type: type ?? filter?.type ?? this.type,
        tag: clearTag ? null : (tag ?? this.tag),
        typeCounts: typeCounts ?? this.typeCounts,
        tagCounts: tagCounts ?? this.tagCounts,
        query: query ?? this.query,
        selected: selected ?? this.selected,
        count: count ?? this.count,
        limit: limit ?? this.limit,
        pending: pending ?? this.pending,
        binCount: binCount ?? this.binCount,
        syncing: syncing ?? this.syncing,
        syncError: clearSyncError ? null : (syncError ?? this.syncError),
        notice: notice ?? this.notice,
        nextAutoSyncAt:
            clearNextAutoSyncAt ? null : (nextAutoSyncAt ?? this.nextAutoSyncAt),
      );

  @override
  List<Object?> get props => [
        signature,
        sort,
        type,
        tag,
        typeCounts,
        tagCounts,
        query,
        selected,
        count,
        limit,
        pending,
        binCount,
        syncing,
        syncError,
        notice,
        nextAutoSyncAt,
      ];
}
