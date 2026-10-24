import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A safe, displayable error. Never includes private paths or dictated words.
class EditorMediaException implements Exception {
  const EditorMediaException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class EditorSpeechInput {
  /// Results replace the previous partial result for this listening session.
  /// The caller owns inserting that segment at the original cursor position.
  /// Returns whether the session is still active after platform startup. A fast
  /// successful session can deliver its final result and onStopped first, then
  /// return false; callers must not treat that as a permission failure.
  Future<bool> start({
    required void Function(String words, bool finalResult) onResult,
    required void Function(String message) onError,
    required void Function() onStopped,
  });

  /// Allows the recognizer's final result to arrive before onStopped.
  Future<void> stop();

  /// Invalidates callbacks immediately, including pending permission requests.
  /// The returned Future waits for pending native work and cancellation to drain.
  Future<void> cancel();
}

class PlatformEditorSpeechInput implements EditorSpeechInput {
  // The platform plugin initializes once per application and retains its first
  // status/error listeners. Share their owner across editor routes as well.
  factory PlatformEditorSpeechInput({SpeechToText? speech}) =>
      speech == null ? _shared : PlatformEditorSpeechInput._(speech);
  PlatformEditorSpeechInput._(this._speech);
  static final _shared = PlatformEditorSpeechInput._(SpeechToText());

  final SpeechToText _speech;
  int _generation = 0;
  bool _active = false;
  int? _callbackGeneration;
  Future<void> _platformChain = Future.value();
  bool _stopping = false;
  bool _sawFinal = false;
  bool _sawDone = false;
  Timer? _watchdog;
  Timer? _finalGrace;
  void Function(String message)? _onError;
  void Function()? _onStopped;

  // A cancel invalidates the Dart session immediately, but the native speech
  // service must finish tearing down before another initialize/listen starts.
  // The plugin exposes no native session IDs. Unsolicited events after a fully
  // drained teardown and a later listen cannot be attributed more precisely.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _platformChain.then((_) => operation());
    _platformChain =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  bool get _acceptCallbacks => _active && _callbackGeneration == _generation;

  void _waitForFinal(int generation) {
    _finalGrace ??= Timer(const Duration(seconds: 3), () {
      if (!_active || generation != _generation) return;
      _onError?.call(
          'Dictation did not return a final result. You can keep editing the text already entered.');
      // The caller may have canceled synchronously from its error callback.
      if (_active && generation == _generation) unawaited(cancel());
    });
  }

  void _finish() {
    if (!_active) return;
    _active = false;
    _generation++;
    _callbackGeneration = null;
    _watchdog?.cancel();
    _watchdog = null;
    _finalGrace?.cancel();
    _finalGrace = null;
    final stopped = _onStopped;
    _onStopped = null;
    _onError = null;
    stopped?.call();
  }

  @override
  Future<bool> start({
    required void Function(String words, bool finalResult) onResult,
    required void Function(String message) onError,
    required void Function() onStopped,
  }) async {
    if (_active) {
      onError('Dictation is already listening. Stop it before starting again.');
      return false;
    }
    final generation = ++_generation;
    _active = true;
    _stopping = false;
    _sawFinal = false;
    _sawDone = false;
    _onError = onError;
    _onStopped = onStopped;
    try {
      final available = await _serialize(() async {
        if (!_active || generation != _generation) return false;
        _callbackGeneration = generation;
        return _speech.initialize(
          options: [SpeechToText.androidNoBluetooth],
          onError: (_) {
            if (!_acceptCallbacks) return;
            _onError?.call(
              'Dictation stopped. Check microphone permission and the device speech service, then try again.',
            );
            if (_acceptCallbacks) unawaited(cancel());
          },
          onStatus: (status) {
            if (!_acceptCallbacks || status != SpeechToText.doneStatus) return;
            // Android's doneNoResult is mapped to done by the Dart plugin even
            // when Stop preceded every partial. Keep a bounded window for that
            // session's final transcript instead of dropping it immediately.
            _sawDone = true;
            if (_sawFinal) {
              _finish();
            } else {
              _waitForFinal(_generation);
            }
          },
        );
      });
      if (!_active || generation != _generation) return false;
      if (!available) {
        onError(
          'Dictation is unavailable. Check microphone permission and install or enable a device speech service.',
        );
        _finish();
        return false;
      }
      _watchdog = Timer(const Duration(seconds: 65), () {
        if (!_active || generation != _generation) return;
        _onError
            ?.call('Dictation timed out. Tap the microphone to start again.');
        if (_active && generation == _generation) unawaited(cancel());
      });
      await _serialize(() async {
        if (!_active || generation != _generation) return;
        await _speech.listen(
          onResult: (result) {
            if (_acceptCallbacks && generation == _generation) {
              if (result.finalResult) _sawFinal = true;
              onResult(result.recognizedWords, result.finalResult);
              if (_active &&
                  generation == _generation &&
                  result.finalResult &&
                  (_stopping || _sawDone)) {
                _finish();
              }
            }
          },
          listenOptions: SpeechListenOptions(
            listenMode: ListenMode.dictation,
            partialResults: true,
            cancelOnError: true,
            listenFor: const Duration(minutes: 1),
            pauseFor: const Duration(seconds: 5),
          ),
        );
      });
      return _active && generation == _generation;
    } catch (_) {
      if (_active && generation == _generation) {
        onError(
            'Dictation could not start. Check microphone permission and try again.');
        _finish();
      }
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_active || _stopping) return;
    final generation = _generation;
    _stopping = true;
    _waitForFinal(generation);
    try {
      await _serialize(() async {
        if (!_active || generation != _generation) return;
        await _speech.stop();
      });
      if (_active && generation == _generation && _sawFinal) _finish();
    } catch (_) {
      if (!_active || generation != _generation) return;
      _onError?.call(
          'Dictation could not finish. You can keep editing the text already entered.');
      if (_active && generation == _generation) unawaited(cancel());
    }
  }

  @override
  Future<void> cancel() async {
    _finish();
    try {
      await _serialize(_speech.cancel);
    } catch (_) {
      // Cancellation is also used while disposing a route. Callbacks have
      // already been invalidated, so plugin teardown cannot touch that draft.
    }
  }
}

abstract class EditorImageInput {
  /// Returns only re-encoded JPEG bytes as base64; cancellation returns null.
  /// New attachments contain at most 23,999 raw bytes and respect maxBytes.
  Future<String?> pickJpeg({required int maxBytes});
}

class PlatformEditorImageInput implements EditorImageInput {
  PlatformEditorImageInput({ImagePicker? picker, bool? isAndroid})
      : _picker = picker ?? ImagePicker(),
        _isAndroid = isAndroid ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  // Strictly below 24,000 raw JPEG bytes. Wire base64/encryption adds overhead;
  // the editor separately checks aggregate and complete-note wire budgets.
  static const maxImageBytes = 23999;
  static const _maxSourceBytes = 8 * 1024 * 1024;
  final ImagePicker _picker;
  final bool _isAndroid;
  bool _picking = false;

  @override
  Future<String?> pickJpeg({required int maxBytes}) async {
    if (maxBytes <= 0) {
      throw const EditorMediaException(
          'This note has no room for another image.');
    }
    if (_picking) {
      throw const EditorMediaException(
          'Finish the current image selection first.');
    }
    _picking = true;
    try {
      if (_isAndroid) {
        final lost = await _picker.retrieveLostData();
        if (!lost.isEmpty) {
          // The previous editor's identity was lost with the activity. Consume
          // that result but never attach it to whichever note is open now.
          throw const EditorMediaException(
            'An earlier image selection was interrupted. Please select the image again for this note.',
          );
        }
      }
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      if (await file.length() > _maxSourceBytes) {
        throw const EditorMediaException(
            'Choose a smaller image (under 8 MB).');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxSourceBytes) {
        throw const EditorMediaException(
            'Choose a smaller image (under 8 MB).');
      }
      // All decoding, resizing and JPEG encoding runs off the UI isolate.
      return await compute(
          _compressImage, (bytes, maxBytes.clamp(1, maxImageBytes)));
    } on EditorMediaException {
      rethrow;
    } catch (_) {
      throw const EditorMediaException(
        'The image could not be added. Choose a JPEG or PNG image and try again.',
      );
    } finally {
      _picking = false;
    }
  }
}

String _compressImage((Uint8List, int) request) {
  final (bytes, maxBytes) = request;
  // This isolate processes one selection. Header checks precede pixel decode;
  // the decoder guard is a second bound against malformed dimensions.
  const maxPixels = 4 * 1024 * 1024;
  image.Decoder.defaultMaxPixels = maxPixels;
  final image.Decoder decoder;
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    decoder = image.JpegDecoder(maxPixels: maxPixels);
  } else if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71) {
    decoder = image.PngDecoder(maxPixels: maxPixels);
  } else {
    throw const EditorMediaException('Choose a JPEG or PNG image.');
  }
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width > 4096 ||
      info.height > 4096 ||
      info.width * info.height > maxPixels) {
    throw const EditorMediaException(
        'The image is invalid or too large. Choose a smaller image.');
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) {
    throw const EditorMediaException(
        'The image could not be read. Choose another image.');
  }
  final resized = _resizeWithin(image.bakeOrientation(decoded), 1024);
  // Composite onto white and create fresh pixels so EXIF/GPS, source filenames
  // and other metadata are never embedded in synced note content.
  final clean = image.Image(width: resized.width, height: resized.height);
  image.fill(clean, color: image.ColorRgb8(255, 255, 255));
  image.compositeImage(clean, resized);
  final longest = clean.width >= clean.height ? clean.width : clean.height;
  for (final dimension in {longest, 768, 512, 384, 256, 192, 128}) {
    if (dimension > longest) continue;
    final candidate = _resizeWithin(clean, dimension);
    for (final quality in [70, 55, 40]) {
      final jpeg = image.encodeJpg(candidate, quality: quality);
      if (jpeg.length <= maxBytes) return base64Encode(jpeg);
    }
  }
  throw const EditorMediaException(
      'This image could not fit under 24 KB and the note’s remaining image space. Choose a smaller image or remove another image.');
}

image.Image _resizeWithin(image.Image source, int maxDimension) {
  final longest = source.width >= source.height ? source.width : source.height;
  if (longest <= maxDimension) return source;
  final scale = maxDimension / longest;
  return image.copyResize(source,
      width: (source.width * scale).round().clamp(1, source.width),
      height: (source.height * scale).round().clamp(1, source.height),
      interpolation: image.Interpolation.average);
}
