import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Decoded-size bounds for note images.
///
/// A note image is drawn in two places: the editor's 220-high thumbnail and
/// the full-size viewer. Decoding the thumbnail at the source size kept up to
/// width x height x 4 bytes per image for the editor's whole visit (16 MiB for
/// a legacy 4096 x 1024 attachment). The thumbnail now decodes no larger than
/// the box it is drawn in; the viewer decodes full size only while it is open.
abstract final class NoteImageDecode {
  /// A provider that decodes [bytes] to fit within [logicalWidth] x
  /// [logicalHeight] at [devicePixelRatio], keeping the aspect ratio and never
  /// upscaling. Reuse one instance per image and size: a new instance per
  /// build would re-resolve the image.
  static ResizeImage thumbnail(
    Uint8List bytes, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) =>
      ResizeImage(
        MemoryImage(bytes),
        width: _pixels(logicalWidth, devicePixelRatio),
        height: _pixels(logicalHeight, devicePixelRatio),
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      );

  /// Drops [provider]'s cached decode unless a widget still shows it.
  static void release(ImageProvider<Object> provider) {
    provider.obtainKey(ImageConfiguration.empty).then((key) {
      PaintingBinding.instance.imageCache.evict(key, includeLive: false);
    }, onError: (Object _) {});
  }

  static int _pixels(double logical, double ratio) =>
      (logical * ratio).ceil().clamp(1, 1 << 14);
}
