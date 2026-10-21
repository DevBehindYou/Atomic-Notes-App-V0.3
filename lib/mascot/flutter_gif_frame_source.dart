import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'mascot_asset_resolver.dart';
import 'mascot_catalog.dart';
import 'mascot_frame_source.dart';

class FlutterGifFrameSource implements MascotFrameSource {
  FlutterGifFrameSource(this.resolver);
  final MascotAssetResolver resolver;
  @override
  Future<MascotFrameSession> open(
      MascotClip clip, int targetPhysicalPixels) async {
    final lease = await resolver.openVerifiedClip(clip);
    ui.Codec? codec;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(lease.bytes);
      // The SDK takes ownership of buffer, including its error path.
      codec =
          await ui.instantiateImageCodecWithSize(buffer, getTargetSize: (w, h) {
        final size = targetPhysicalPixels.clamp(1, 480);
        final scale = math.min(1.0, size / math.max(w, h));
        return ui.TargetImageSize(
            width: math.max(1, (w * scale).round()),
            height: math.max(1, (h * scale).round()));
      });
      if (codec.frameCount != clip.frameCount || codec.frameCount < 1) {
        throw StateError('mascot_frame_metadata');
      }
      return _GifSession(codec, lease);
    } catch (_) {
      codec?.dispose();
      await lease.close();
      rethrow;
    }
  }
}

class _GifSession implements MascotFrameSession {
  _GifSession(this.codec, this.lease);

  final ui.Codec codec;
  final MascotAssetLease lease;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  bool _closed = false, _codecDisposed = false, _leaseClosed = false;
  @override
  int get frameCount => codec.frameCount;
  @override
  Future<OwnedMascotFrame> nextFrame() {
    if (_closed) return Future.error(StateError('mascot_session_closed'));
    final result = _tail.then((_) async {
      final frame = await codec.getNextFrame();
      return OwnedMascotFrame(frame.image, frame.duration);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<void> close() {
    _closed = true;
    if (_leaseClosed) return Future.value();
    return _closing ??= _tail.then((_) async {
      if (!_codecDisposed) {
        codec.dispose();
        _codecDisposed = true;
      }
      await lease.close();
      _leaseClosed = true;
    }).whenComplete(() {
      _closing = null;
    });
  }
}
