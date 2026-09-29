import 'package:flutter/foundation.dart';

/// What the profile state needs from the place profile choices are kept.
///
/// [ProfileStore] is the real one (a small Hive box on the device; nothing is sent to the Server).
/// The state layer only sees this interface, so it is tested with a fake and no storage.
abstract interface class ProfileSource implements Listenable {
  /// The asset to draw: the chosen avatar, or the default photo.
  String get avatarAsset;

  /// A display-only switch: it changes nothing else in the app.
  bool get publicProfile;

  /// Pass null to go back to the default photo. Anything that is not one of the bundled avatars is
  /// ignored.
  Future<void> setAvatar(String? asset);

  Future<void> setPublicProfile(bool value);
}
