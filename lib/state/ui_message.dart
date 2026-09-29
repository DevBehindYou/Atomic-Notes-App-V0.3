import 'package:atomic_notes/database/note.dart';
import 'package:equatable/equatable.dart';

/// A short message for the person, and how long to show it. Cubit methods that finish an action
/// return one, and the screen shows it when it is ready to (after a dialog has closed, say).
final class UiMessage extends Equatable {
  const UiMessage(this.text, this.millis);

  final String text;

  /// How long to show it, in milliseconds.
  final int millis;

  @override
  List<Object?> get props => [text, millis];
}

/// A number that changes whenever a note in [notes] changes what it shows (its text, ticks, pin,
/// deleted flag or sync state). The store edits notes in place, so comparing the notes themselves
/// would never see a change; states compare this instead.
int noteSignature(Iterable<Note> notes) => Object.hashAll(notes.map((n) =>
    Object.hash(n.id, n.updatedAt.microsecondsSinceEpoch, n.dirty, n.deleted,
        n.pinned, n.serverVersion)));
