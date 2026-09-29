import 'package:atomic_notes/profile/profile_source.dart';
import 'package:atomic_notes/profile/profile_store.dart' show Avatars;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// The profile choices kept on this device.
final class ProfileState extends Equatable {
  const ProfileState({
    this.avatarAsset = Avatars.defaultAsset,
    this.publicProfile = true,
  });

  final String avatarAsset;
  final bool publicProfile;

  bool get hasCustomAvatar => avatarAsset != Avatars.defaultAsset;

  @override
  List<Object?> get props => [avatarAsset, publicProfile];
}

/// State of the profile picture and the Public Profile switch. The choices are kept per account,
/// so [refresh] must run when a different account signs in: nothing tells the store that the
/// account changed.
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({required ProfileSource store})
      : _store = store,
        super(_read(store)) {
    _store.addListener(refresh);
  }

  final ProfileSource _store;

  static ProfileState _read(ProfileSource store) => ProfileState(
        avatarAsset: store.avatarAsset,
        publicProfile: store.publicProfile,
      );

  /// Reads the store again and emits when anything differs.
  void refresh() {
    if (isClosed) return;
    final next = _read(_store);
    if (next != state) emit(next);
  }

  @override
  Future<void> close() {
    _store.removeListener(refresh);
    return super.close();
  }

  /// Pass null to go back to the default photo.
  Future<void> setAvatar(String? asset) => _store.setAvatar(asset);

  Future<void> setPublicProfile(bool value) => _store.setPublicProfile(value);
}
