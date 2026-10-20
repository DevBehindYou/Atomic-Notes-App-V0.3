import 'dart:typed_data';
import 'mascot_catalog.dart';

/// Returns verified local bytes only. Implementations must not download here.
abstract interface class MascotAssetResolver {
  Future<MascotAssetLease> openVerifiedClip(MascotClip clip);
}

/// The caller keeps this lease alive until its decoder has closed.
/// close is idempotent and waits for implementation-owned cleanup.
abstract interface class MascotAssetLease {
  Uint8List get bytes;
  Future<void> close();
}
