import 'package:atomic_notes/database/notes_source.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// What the Danger Zone shows about the notes on this device.
final class DangerZoneState extends Equatable {
  const DangerZoneState({this.onDevice = 0, this.unsynced = 0});

  final int onDevice;

  /// Notes that exist only on this device, so a local wipe would lose them for good.
  final int unsynced;

  @override
  List<Object?> get props => [onDevice, unsynced];
}

/// The two ways to destroy notes. They are independent: wiping the cloud never touches this
/// device, and wiping this device never touches the cloud.
class DangerZoneCubit extends Cubit<DangerZoneState> {
  DangerZoneCubit({required NotesSource source})
      : _source = source,
        super(_read(source)) {
    _source.addListener(_sourceChanged);
  }

  final NotesSource _source;

  static DangerZoneState _read(NotesSource source) => DangerZoneState(
      onDevice: source.count, unsynced: source.pendingCount);

  void _sourceChanged() {
    if (isClosed) return;
    final next = _read(_source);
    if (next != state) emit(next);
  }

  @override
  Future<void> close() {
    _source.removeListener(_sourceChanged);
    return super.close();
  }

  Future<WipeOutcome> wipeCloud() => _source.wipeRemote();

  Future<WipeOutcome> wipeLocal() async {
    final removed = await _source.wipeLocalNotes();
    return WipeOutcome(
      true,
      removed == 1
          ? 'Removed 1 note from this device. Cloud notes are untouched and download again on the next sync.'
          : 'Removed $removed notes from this device. Cloud notes are untouched and download again on the next sync.',
    );
  }
}
