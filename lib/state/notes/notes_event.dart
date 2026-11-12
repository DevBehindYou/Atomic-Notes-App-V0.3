part of 'notes_bloc.dart';

/// Everything that can happen on the notes screens.
sealed class NotesEvent {
  const NotesEvent();
}

/// The notes screen was opened afresh: clear the filter, the search and the selection.
final class NotesViewReset extends NotesEvent {
  const NotesViewReset();
}

/// Legacy: sets the type and the order together, with the old meaning of
/// [NoteFilter]. Kept until the Home screen moves to the three events below.
final class NotesFilterChanged extends NotesEvent {
  const NotesFilterChanged(this.filter);
  final NoteFilter filter;
}

/// Changes the order only; the type, tag, search and selection stay.
final class NotesSortChanged extends NotesEvent {
  const NotesSortChanged(this.sort);
  final NoteSort sort;
}

/// Changes which kinds of note are on view.
final class NotesTypeFilterChanged extends NotesEvent {
  const NotesTypeFilterChanged(this.type);
  final NoteTypeFilter type;
}

/// Shows only notes carrying exactly [tag]; null shows every tag.
final class NotesTagFilterChanged extends NotesEvent {
  const NotesTagFilterChanged(this.tag);
  final String? tag;
}

final class NotesQueryChanged extends NotesEvent {
  const NotesQueryChanged(this.query);
  final String query;
}

final class NoteSelectionToggled extends NotesEvent {
  const NoteSelectionToggled(this.id);
  final String id;
}

final class NoteSelectionCleared extends NotesEvent {
  const NoteSelectionCleared();
}

/// Selects every note on view, or clears the selection when they are all selected.
final class NoteSelectionAllToggled extends NotesEvent {
  const NoteSelectionAllToggled();
}

/// Moves the selected notes to the Recycle Bin.
final class NotesDeleteSelected extends NotesEvent {
  const NotesDeleteSelected();
}

/// Saves [note] locally through the repository. With [ack], the caller learns
/// the outcome of this exact attempt (the local save, not a later cloud
/// sync), for the [context] its editor captured when it opened.
final class NoteSaved extends NotesEvent {
  const NoteSaved(this.note, {this.ack, this.context});
  final Note note;
  final NoteSaveAck? ack;
  final NoteEditorContext? context;
}

/// The outcome of one local save attempt.
sealed class NoteSaveResult {
  const NoteSaveResult();
}

/// The store confirmed this attempt's note was written on this device for
/// the editor's account. Syncing it is separate.
final class NoteSaveSucceeded extends NoteSaveResult {
  const NoteSaveSucceeded();
}

/// The store deliberately did not keep this attempt ([reason]).
final class NoteSaveRetired extends NoteSaveResult {
  const NoteSaveRetired(this.reason);
  final NoteSaveRetirement reason;
}

/// The local write failed. Memory may already hold the change, but the
/// device's store does not have it confirmed; the draft is still needed.
final class NoteSaveFailed extends NoteSaveResult {
  const NoteSaveFailed(this.error);
  final Object error;
}

/// Nothing was attempted: the notes screen or its bloc is gone, or the store
/// cannot acknowledge an editor's save.
final class NoteSaveRejected extends NoteSaveResult {
  const NoteSaveRejected();
}

/// Nothing to save: an empty new draft is discarded instead.
final class NoteSaveSkipped extends NoteSaveResult {
  const NoteSaveSkipped();
}

/// The acknowledgement of one save attempt. It completes exactly once.
final class NoteSaveAck {
  final _result = Completer<NoteSaveResult>();

  Future<NoteSaveResult> get result => _result.future;

  void _complete(NoteSaveResult value) {
    if (!_result.isCompleted) _result.complete(value);
  }
}

/// Moves one existing note to the Recycle Bin through the repository.
final class NoteDeleted extends NotesEvent {
  const NoteDeleted(this.id);
  final String id;
}

/// Ticks or unticks one checklist row straight from a card.
final class NoteItemToggled extends NotesEvent {
  const NoteItemToggled(this.note, this.index);
  final Note note;
  final int index;
}

/// The sync button. [instant] is the paid, always-open sync.
final class NotesSyncRequested extends NotesEvent {
  const NotesSyncRequested({required this.instant});
  final bool instant;
}

/// The store changed. Only ever added by the bloc itself.
final class _NotesSourceChanged extends NotesEvent {
  const _NotesSourceChanged();
}
