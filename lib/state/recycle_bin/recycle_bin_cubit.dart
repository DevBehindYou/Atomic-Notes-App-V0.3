import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/state/ui_message.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// The notes waiting in the Recycle Bin.
final class RecycleBinState extends Equatable {
  const RecycleBinState({this.notes = const [], this.signature = 0});

  final List<Note> notes;

  /// See [noteSignature]: the notes are edited in place, so states compare this, not the list.
  final int signature;

  @override
  List<Object?> get props => [signature];
}

/// State and actions of the Recycle Bin screen. Each action answers with the message to show, so
/// the screen can show it once its dialog has closed.
class RecycleBinCubit extends Cubit<RecycleBinState> {
  RecycleBinCubit({required NotesSource source})
      : _source = source,
        super(_snapshot(source)) {
    _source.addListener(_sourceChanged);
  }

  final NotesSource _source;

  static RecycleBinState _snapshot(NotesSource source) {
    final notes = List<Note>.unmodifiable(source.binNotes);
    return RecycleBinState(notes: notes, signature: noteSignature(notes));
  }

  void _sourceChanged() {
    if (isClosed) return;
    final next = _snapshot(_source);
    if (next != state) emit(next);
  }

  @override
  Future<void> close() {
    _source.removeListener(_sourceChanged);
    return super.close();
  }

  Future<UiMessage> restore(Note note) async {
    if (_source.count >= _source.limit) {
      return UiMessage(
          'Note limit reached (${_source.limit}). Delete a note to make room.',
          3000);
    }
    final ok = await _source.restoreNote(note.id);
    return UiMessage(ok ? 'Note restored' : 'Could not restore this note', 2000);
  }

  Future<UiMessage> deleteForever(Note note) async {
    final removed = await _source.deleteForever([note.id]);
    return UiMessage(removed > 0 ? 'Deleted for good' : _notSentYet(), 3000);
  }

  Future<UiMessage> emptyBin() async {
    final removed =
        await _source.deleteForever(_source.binNotes.map((n) => n.id).toList());
    return UiMessage(removed > 0 ? 'Recycle Bin emptied' : _notSentYet(), 3000);
  }

  /// Why a delete could not go through: a deletion must reach the cloud first, or the note would
  /// come back.
  String _notSentYet() {
    final next = _source.nextAutoSyncAt;
    if (next == null) {
      return 'Could not delete yet. Turn on Cloud Sync and sync first.';
    }
    final int minutes =
        (next.difference(DateTime.now()).inSeconds / 60).ceil().clamp(1, 60);
    return 'This deletion has not reached the cloud yet. It sends in $minutes min, '
        'or use Sync now in Cloud Notes.';
  }
}
