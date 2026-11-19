import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/database/sync_report.dart';
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

/// What deleting a bin note for good has to do first, read from its sync flag alone. It says
/// nothing about the note's past in the cloud: a version number of 0 is no proof that the note
/// never synced (a cloud wipe resets it), and a waiting change is no proof of what the cloud holds.
enum BinRemovalStep {
  /// Nothing about the note waits to sync, so removing it sends nothing: it is only forgotten
  /// on this device.
  removeNow,

  /// The note has a change that has not finished syncing. It syncs first, and the note is kept
  /// when that sync cannot finish.
  syncFirst;

  static BinRemovalStep of(Note note) =>
      note.dirty ? BinRemovalStep.syncFirst : BinRemovalStep.removeNow;
}

/// One confirmed "delete for good", frozen when its confirmation opened: exactly which notes it
/// showed, what it said removing each one does, and whose session it was. Notes are edited in
/// place, so it keeps copies of those facts, never the notes. A note that reaches the bin later
/// is not part of it.
final class BinRemoval {
  BinRemoval._(this._facts, this._identity, {required this.wholeBin});

  final Map<String, (BinRemovalStep, String)> _facts;
  final Object? _identity;

  /// Confirmed from "Empty bin" rather than from one note's card.
  final bool wholeBin;

  /// The confirmed notes, in the order they were shown.
  List<String> get ids => List.unmodifiable(_facts.keys);

  int get length => _facts.length;

  /// How many confirmed notes were shown with [step].
  int count(BinRemovalStep step) => _facts.values.where((f) => f.$1 == step).length;
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

  /// A removal is running; another one waits for it to answer.
  bool _removing = false;

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

  /// The account session and store lifetime, when the store can tell them apart.
  Object? get _identity {
    final source = _source;
    return source is SyncReportSource
        ? (source as SyncReportSource).syncReportIdentity
        : null;
  }

  /// Freezes what a confirmation is about to show for [notes]. Build it from the same notes the
  /// confirmation's words are built from, at the same moment.
  BinRemoval confirm(Iterable<Note> notes, {bool wholeBin = false}) => BinRemoval._(
      Map.unmodifiable({
        for (final n in notes) n.id: (BinRemovalStep.of(n), n.title),
      }),
      _identity,
      wholeBin: wholeBin);

  /// Deletes [note] for good, as confirmed now.
  Future<UiMessage> deleteForever(Note note) => remove(confirm([note]));

  /// Deletes for good the notes in the bin now.
  Future<UiMessage> emptyBin() => remove(confirm(_source.binNotes, wholeBin: true));

  static const UiMessage _changed = UiMessage(
      'The Recycle Bin changed before this could finish. Nothing was deleted for good. '
      'Check it and try again.',
      4000);

  /// Whether [removal] no longer matches what its confirmation showed.
  /// Each confirmed note must still be in the bin, unchanged, in the same session. The one change
  /// allowed is the one the confirmation announced: a change that had to sync first has synced.
  bool _drifted(BinRemoval removal) {
    if (removal._identity != _identity) return true;
    for (final MapEntry(key: id, value: (step, title)) in removal._facts.entries) {
      final note = _source.byId(id);
      if (note == null || !note.deleted || note.title != title) return true;
      final now = BinRemovalStep.of(note);
      if (now != step && step != BinRemovalStep.syncFirst) return true;
    }
    return false;
  }

  bool _waitsToSync(BinRemoval removal) => removal._facts.keys
      .any((id) => _source.byId(id)?.dirty ?? false);

  /// Deletes for good exactly the notes [removal] confirmed, and only while they are as it showed
  /// them. A change that must sync first syncs here, before the store is asked, so the store never
  /// has to sync (and wait) between choosing its notes and removing them. The check right before
  /// the store's call has no wait in between, so nothing can change in that gap.
  Future<UiMessage> remove(BinRemoval removal) async {
    if (_removing) {
      return const UiMessage(
          'Another removal is still running. Try again when it finishes.', 3000);
    }
    _removing = true;
    try {
      if (removal.length == 0 || _drifted(removal)) return _changed;
      if (_waitsToSync(removal)) {
        final synced = await _source.syncNow();
        if (_drifted(removal)) return _changed;
        // Like the store, judge the confirmed notes, not the whole sync: other changes may
        // still wait (an automatic sync sends one batch an hour) once these have gone.
        if (_waitsToSync(removal)) {
          return synced ? _changed : UiMessage(_notSentYet(), 3000);
        }
      }
      final removed = await _source.deleteForever(removal.ids);
      return _outcome(removal, removed);
    } catch (_) {
      return _unfinished(removal);
    } finally {
      _removing = false;
    }
  }

  /// What happened, read from the store afterwards rather than assumed.
  UiMessage _outcome(BinRemoval removal, int removed) {
    final left = removal.ids.where((id) => _source.byId(id) != null).length;
    if (removed == 0 && left == removal.length) return UiMessage(_notSentYet(), 3000);
    if (left == removal.length) return _unfinished(removal);
    if (left > 0) {
      final gone = removal.length - left;
      return UiMessage(
          'Deleted $gone of ${removal.length} notes for good. '
          '${left == 1 ? 'One is' : '$left are'} still in the Recycle Bin.',
          4000);
    }
    if (!removal.wholeBin) return const UiMessage('Deleted for good', 3000);
    if (_source.binNotes.isEmpty) return const UiMessage('Recycle Bin emptied', 3000);
    return UiMessage(
        '${removal.length == 1 ? '1 note' : '${removal.length} notes'} deleted for good. '
        'Notes deleted after you confirmed are still in the Recycle Bin.',
        4000);
  }

  /// A removal that stopped part way, said only as far as the store confirms it.
  UiMessage _unfinished(BinRemoval removal) {
    final all = removal.ids.every((id) => _source.byId(id)?.deleted ?? false);
    if (!all) {
      return const UiMessage(
          "Couldn't confirm the removal. Check the Recycle Bin before trying again.", 4000);
    }
    return UiMessage(
        removal.length == 1
            ? "Couldn't finish removing this note. It remains in the Recycle Bin."
            : "Couldn't finish removing these notes. They remain in the Recycle Bin.",
        4000);
  }

  /// Why a delete could not go through: a change must reach the cloud first, or the note would
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
