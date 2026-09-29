part of 'notes_bloc.dart';

/// Everything that can happen on the notes screens.
sealed class NotesEvent {
  const NotesEvent();
}

/// The notes screen was opened afresh: clear the filter, the search and the selection.
final class NotesViewReset extends NotesEvent {
  const NotesViewReset();
}

final class NotesFilterChanged extends NotesEvent {
  const NotesFilterChanged(this.filter);
  final NoteFilter filter;
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

final class NoteSaved extends NotesEvent {
  const NoteSaved(this.note);
  final Note note;
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
