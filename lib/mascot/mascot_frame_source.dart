import 'dart:ui' as ui;
import 'mascot_catalog.dart';

abstract interface class MascotFrameSource {
  Future<MascotFrameSession> open(MascotClip clip, int targetPhysicalPixels);
}

abstract interface class MascotFrameSession {
  int get frameCount;
  Future<OwnedMascotFrame> nextFrame();
  Future<void> close();
}

/// Exactly one owner must dispose this image, including stale decode results.
class OwnedMascotFrame {
  OwnedMascotFrame(this.image, this.duration);
  final ui.Image image;
  final Duration duration;
  bool _disposed = false;
  bool get isDisposed => _disposed;
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      image.dispose();
    }
  }
}
