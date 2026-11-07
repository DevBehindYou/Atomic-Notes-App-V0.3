import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:atomic_notes/editor/editor_media.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class FakeSpeech extends SpeechToText {
  FakeSpeech() : super.withMethodChannel();
  SpeechResultListener? result;
  SpeechStatusListener? status;
  SpeechErrorListener? error;
  SpeechListenOptions? options;
  Completer<bool>? initialization;
  Object? initializationError;
  bool available = true;
  bool bluetoothDisabled = false;
  int canceled = 0;
  int listens = 0;
  Completer<void>? cancellation;
  Completer<void>? listening;
  @override
  Future<bool> initialize(
      {SpeechErrorListener? onError,
      SpeechStatusListener? onStatus,
      dynamic debugLogging = false,
      Duration finalTimeout = SpeechToText.defaultFinalTimeout,
      List<SpeechConfigOption>? options}) async {
    status = onStatus;
    error = onError;
    bluetoothDisabled = options!.contains(SpeechToText.androidNoBluetooth);
    if (initializationError != null) throw initializationError!;
    return initialization == null ? available : initialization!.future;
  }

  @override
  Future<void> listen(
      {SpeechResultListener? onResult,
      Duration? listenFor,
      Duration? pauseFor,
      String? localeId,
      SpeechSoundLevelChange? onSoundLevelChange,
      dynamic cancelOnError = false,
      dynamic partialResults = true,
      dynamic onDevice = false,
      ListenMode listenMode = ListenMode.confirmation,
      dynamic sampleRate = 0,
      SpeechListenOptions? listenOptions}) async {
    listens++;
    result = onResult;
    options = listenOptions;
    await listening?.future;
  }

  @override
  Future<void> cancel() async {
    canceled++;
    await cancellation?.future;
  }

  @override
  Future<void> stop() async {}
  void words(String text, {bool finalResult = false}) =>
      result!(SpeechRecognitionResult.init(
          [SpeechRecognitionWords(text, null, 1)],
          finalResult ? ResultType.finalResult : ResultType.partial));
}

class FakePicker extends ImagePicker {
  XFile? file;
  LostDataResponse lost = LostDataResponse.empty();
  int picks = 0;
  int? requestedQuality;
  @override
  Future<LostDataResponse> retrieveLostData() async => lost;
  @override
  Future<XFile?> pickImage(
      {required ImageSource source,
      double? maxWidth,
      double? maxHeight,
      int? imageQuality,
      CameraDevice preferredCameraDevice = CameraDevice.rear,
      bool requestFullMetadata = true}) async {
    expect(source, ImageSource.gallery);
    expect(maxWidth, 1024);
    expect(maxHeight, 1024);
    requestedQuality = imageQuality;
    expect(requestFullMetadata, isFalse);
    picks++;
    return file;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'speech sends replacement partials and final; cancel rejects late results',
      () async {
    final speech = FakeSpeech();
    final input = PlatformEditorSpeechInput(speech: speech);
    final results = <String>[];
    var stopped = 0;
    expect(
        await input.start(
            onResult: (words, finalResult) =>
                results.add('$words:$finalResult'),
            onError: fail,
            onStopped: () => stopped++),
        isTrue);
    expect(speech.bluetoothDisabled, isTrue);
    expect(speech.options!.listenMode, ListenMode.dictation);
    expect(speech.options!.partialResults, isTrue);
    speech.words('hello');
    speech.words('hello world', finalResult: true);
    await input.cancel();
    speech.words('late', finalResult: true);
    speech.status!(SpeechToText.doneStatus);
    expect(results, ['hello:false', 'hello world:true']);
    expect(stopped, 1);
  });
  test('cancel during permission initialization cannot start listening',
      () async {
    final speech = FakeSpeech()..initialization = Completer<bool>();
    final input = PlatformEditorSpeechInput(speech: speech);
    final start = input.start(
        onResult: (_, __) => fail('late result'),
        onError: fail,
        onStopped: () {});
    await Future<void>.delayed(Duration.zero);
    final canceled = input.cancel();
    // Dart callbacks invalidate immediately; the returned Future also waits for
    // pending native initialization before draining its cancellation.
    speech.initialization!.complete(true);
    await canceled;
    expect(await start, isFalse);
    expect(speech.result, isNull);
  });
  test('unavailable speech reports a useful error without listening', () async {
    final speech = FakeSpeech()..available = false;
    String? error;
    expect(
        await PlatformEditorSpeechInput(speech: speech).start(
            onResult: (_, __) {},
            onError: (message) => error = message,
            onStopped: () {}),
        isFalse);
    expect(error, contains('permission'));
    expect(speech.result, isNull);
  });
  test(
      'missing recognizer explains service setup and can retry after enabling it',
      () async {
    final speech = FakeSpeech()
      ..initializationError = PlatformException(
          code: 'recognizerNotAvailable', message: 'private platform detail');
    final input = PlatformEditorSpeechInput(speech: speech);
    final errors = <String>[];
    final results = <String>[];
    var stops = 0;
    Future<bool> start() => input.start(
        onResult: (words, _) => results.add(words),
        onError: errors.add,
        onStopped: () => stops++);
    expect(await start(), isFalse);
    expect(errors.single, contains('Install or enable'));
    expect(errors.single, contains('speech-recognition service'));
    expect(errors.single, isNot(contains('private platform detail')));
    expect(speech.listens, 0);
    expect(stops, 1);
    speech.initializationError = null;
    expect(await start(), isTrue);
    speech.words('Retry works', finalResult: true);
    expect(results, ['Retry works']);
    await input.cancel();
  });
  test('stop accepts a final transcript before notifying stopped', () async {
    final speech = FakeSpeech();
    final input = PlatformEditorSpeechInput(speech: speech);
    final events = <String>[];
    await input.start(
        onResult: (text, _) => events.add(text),
        onError: fail,
        onStopped: () => events.add('stopped'));
    await input.stop();
    speech.status!(SpeechToText.notListeningStatus);
    speech.words('complete transcript', finalResult: true);
    speech.status!(SpeechToText.doneStatus);
    expect(events, ['complete transcript', 'stopped']);
  });
  test('restart waits for native cancel and ignores old teardown callbacks',
      () async {
    final speech = FakeSpeech()..cancellation = Completer<void>();
    final input = PlatformEditorSpeechInput(speech: speech);
    final events = <String>[];
    await input.start(onResult: (_, __) {}, onError: fail, onStopped: () {});
    final oldResult = speech.result!;
    final canceled = input.cancel();
    final restarted = input.start(
        onResult: (text, _) => events.add(text),
        onError: fail,
        onStopped: () => events.add('stopped'));
    await Future<void>.delayed(Duration.zero);
    expect(speech.listens, 1,
        reason: 'new listen must wait for native cancellation');
    oldResult(SpeechRecognitionResult.init(
        const [SpeechRecognitionWords('old', null, 1)],
        ResultType.finalResult));
    speech.status!(SpeechToText.doneStatus);
    speech.error!(SpeechRecognitionError('old cancel error', false));
    expect(events, isEmpty);
    speech.cancellation!.complete();
    await canceled;
    expect(await restarted, isTrue);
    expect(speech.listens, 2);
    speech.words('new', finalResult: true);
    speech.status!(SpeechToText.doneStatus);
    expect(events, ['new', 'stopped']);
  });
  testWidgets('final before Stop needs no second final or done callback',
      (tester) async {
    final speech = FakeSpeech();
    final input = PlatformEditorSpeechInput(speech: speech);
    final errors = <String>[];
    var stopped = 0;
    final words = <String>[];
    await input.start(
        onResult: (text, _) => words.add(text),
        onError: errors.add,
        onStopped: () => stopped++);
    speech.words('already complete', finalResult: true);
    expect(stopped, 0);
    await input.stop();
    await tester.pump(const Duration(seconds: 4));
    expect(errors, isEmpty);
    expect(words, ['already complete']);
    expect(stopped, 1);
    expect(speech.canceled, 0);
  });
  test(
      'completed result before listen resolves returns inactive without an error',
      () async {
    final speech = FakeSpeech()..listening = Completer<void>();
    final input = PlatformEditorSpeechInput(speech: speech);
    final events = <String>[];
    final started = input.start(
        onResult: (text, _) => events.add(text),
        onError: fail,
        onStopped: () => events.add('stopped'));
    await Future<void>.delayed(Duration.zero);
    expect(speech.listens, 1);
    speech.words('fast complete', finalResult: true);
    speech.status!(SpeechToText.doneStatus);
    expect(events, ['fast complete', 'stopped']);
    speech.listening!.complete();
    expect(await started, isFalse,
        reason:
            'False means no longer active, not necessarily permission failure');
  });
  test('stop done before any partial still accepts the delayed final result',
      () async {
    final speech = FakeSpeech();
    final input = PlatformEditorSpeechInput(speech: speech);
    final events = <String>[];
    await input.start(
        onResult: (text, _) => events.add(text),
        onError: fail,
        onStopped: () => events.add('stopped'));
    await input.stop();
    // Android doneNoResult maps to done even if a final is still pending.
    speech.status!(SpeechToText.doneStatus);
    expect(events, isEmpty);
    speech.words('delayed final', finalResult: true);
    expect(events, ['delayed final', 'stopped']);
  });
  testWidgets('missing final after stop fails after a bounded grace',
      (tester) async {
    final speech = FakeSpeech();
    final input = PlatformEditorSpeechInput(speech: speech);
    final errors = <String>[];
    var stopped = 0;
    await input.start(
        onResult: (_, __) => fail('no result expected'),
        onError: errors.add,
        onStopped: () => stopped++);
    await input.stop();
    speech.status!(SpeechToText.doneStatus);
    expect(stopped, 0);
    await tester.pump(const Duration(seconds: 4));
    expect(stopped, 1);
    expect(errors, hasLength(1));
    expect(speech.canceled, 1);
  });
  test('recognizer error cancels listening and prevents late transcript',
      () async {
    final speech = FakeSpeech();
    final input = PlatformEditorSpeechInput(speech: speech);
    var stopped = 0;
    final errors = <String>[];
    await input.start(
        onResult: (_, __) => fail('late transcript'),
        onError: errors.add,
        onStopped: () => stopped++);
    speech.error!(SpeechRecognitionError('error_audio_error', false));
    await Future<void>.delayed(Duration.zero);
    speech.words('late');
    expect(speech.canceled, 1);
    expect(stopped, 1);
    expect(errors.single, contains('permission'));
  });
  test('picker preserves native image quality before bounded optimization',
      () async {
    final picker = FakePicker();
    await PlatformEditorImageInput(picker: picker, isAndroid: false)
        .pickJpeg(maxBytes: 60000);
    expect(picker.requestedQuality, 100);
  });
  test('picker cancel keeps draft unchanged', () async {
    expect(
        await PlatformEditorImageInput(picker: FakePicker(), isAndroid: true)
            .pickJpeg(maxBytes: 60 * 1024),
        isNull);
  });
  test('lost selection is never attached to a different note', () async {
    final picker = FakePicker()
      ..lost = LostDataResponse(file: XFile.fromData(Uint8List.fromList([1])));
    await expectLater(
        PlatformEditorImageInput(picker: picker, isAndroid: true)
            .pickJpeg(maxBytes: 60000),
        throwsA(isA<EditorMediaException>()));
    expect(picker.picks, 0);
  });
  test('image is a bounded JPEG without source metadata', () async {
    final source = image.Image(width: 1200, height: 800);
    image.fill(source, color: image.ColorRgb8(50, 70, 90));
    final picker = FakePicker()
      ..file = XFile.fromData(Uint8List.fromList(image.encodePng(source)));
    final encoded =
        await PlatformEditorImageInput(picker: picker, isAndroid: false)
            .pickJpeg(maxBytes: 12000);
    final bytes = base64Decode(encoded!);
    expect(bytes.length, lessThanOrEqualTo(12000));
    final decoded = image.decodeJpg(bytes)!;
    expect(decoded.width, lessThanOrEqualTo(1024));
    expect(decoded.height, lessThanOrEqualTo(1024));
    expect(decoded.exif.isEmpty, isTrue);
  });
  test('60KB images retain more detail than the former 24KB allowance',
      () async {
    final pixels = image.Image(width: 512, height: 384);
    final random = Random(724);
    for (var y = 0; y < pixels.height; y++) {
      for (var x = 0; x < pixels.width; x++) {
        pixels.setPixelRgb(x, y, random.nextInt(256), random.nextInt(256),
            random.nextInt(256));
      }
    }
    final picker = FakePicker()
      ..file = XFile.fromData(Uint8List.fromList(image.encodePng(pixels)));
    // A larger caller allowance cannot bypass the 60,000-byte image cap.
    final encoded =
        await PlatformEditorImageInput(picker: picker, isAndroid: false)
            .pickJpeg(maxBytes: 60 * 1024);
    final bytes = base64Decode(encoded!);
    final decoded = image.decodeJpg(bytes)!;
    expect(bytes.length, inInclusiveRange(24000, 60000));
    final limited =
        await PlatformEditorImageInput(picker: picker, isAndroid: false)
            .pickJpeg(maxBytes: 23999);
    final limitedBytes = base64Decode(limited!);
    final limitedImage = image.decodeJpg(limitedBytes)!;
    expect(limitedBytes.length, lessThan(24000));
    expect(bytes.length, greaterThan(limitedBytes.length));
    expect(decoded.width * decoded.height,
        greaterThanOrEqualTo(limitedImage.width * limitedImage.height),
        reason: 'the larger allowance must not lower image resolution');
    if (decoded.width == limitedImage.width &&
        decoded.height == limitedImage.height) {
      final reference = image.copyResize(pixels,
          width: decoded.width,
          height: decoded.height,
          interpolation: image.Interpolation.average);
      double error(image.Image actual) {
        var squared = 0.0;
        for (var y = 0; y < actual.height; y++) {
          for (var x = 0; x < actual.width; x++) {
            final expected = reference.getPixel(x, y);
            final got = actual.getPixel(x, y);
            for (final delta in [
              expected.r - got.r,
              expected.g - got.g,
              expected.b - got.b
            ]) {
              squared += delta * delta;
            }
          }
        }
        return squared;
      }

      expect(error(decoded), lessThan(error(limitedImage)),
          reason: 'at equal resolution the larger image retains color detail');
    }
    expect(decoded.width, lessThan(512),
        reason: 'noise requires dimension reduction');
    expect((decoded.width / decoded.height - 4 / 3).abs(), lessThan(.01));
    expect(decoded.exif.isEmpty, isTrue);
  });
  test('automatic optimization never enlarges a small source', () async {
    final picker = FakePicker()
      ..file = XFile.fromData(Uint8List.fromList(
          image.encodePng(image.Image(width: 24, height: 16))));
    final encoded =
        await PlatformEditorImageInput(picker: picker, isAndroid: false)
            .pickJpeg(maxBytes: 60000);
    final decoded = image.decodeJpg(base64Decode(encoded!))!;
    expect([decoded.width, decoded.height], [24, 16]);
  });
  test('an image that cannot fit the remaining budget fails clearly', () async {
    final picker = FakePicker()
      ..file = XFile.fromData(Uint8List.fromList(
          image.encodePng(image.Image(width: 24, height: 16))));
    await expectLater(
        PlatformEditorImageInput(picker: picker, isAndroid: false)
            .pickJpeg(maxBytes: 100),
        throwsA(isA<EditorMediaException>()));
  });
  test('invalid and oversized images fail without attaching data', () async {
    final picker = FakePicker()..file = XFile.fromData(Uint8List(10));
    final input = PlatformEditorImageInput(picker: picker, isAndroid: false);
    await expectLater(
        input.pickJpeg(maxBytes: 60000), throwsA(isA<EditorMediaException>()));
    await expectLater(
        input.pickJpeg(maxBytes: 0), throwsA(isA<EditorMediaException>()));
    picker.file = XFile.fromData(Uint8List(8 * 1024 * 1024 + 1));
    await expectLater(
        input.pickJpeg(maxBytes: 60000), throwsA(isA<EditorMediaException>()));
    picker.file = XFile.fromData(Uint8List.fromList(
        image.encodePng(image.Image(width: 4097, height: 1))));
    await expectLater(
        input.pickJpeg(maxBytes: 60000), throwsA(isA<EditorMediaException>()));
  });

  group('C07 source layouts and formats', () {
    Future<image.Image> optimize(List<int> source,
        {int maxBytes = 60000}) async {
      final picker = FakePicker()
        ..file = XFile.fromData(Uint8List.fromList(source));
      final encoded =
          await PlatformEditorImageInput(picker: picker, isAndroid: false)
              .pickJpeg(maxBytes: maxBytes);
      final bytes = base64Decode(encoded!);
      expect(bytes.length, lessThanOrEqualTo(maxBytes));
      return image.decodeJpg(bytes)!;
    }

    void expectNear(image.Pixel pixel, List<int> rgb) {
      for (var i = 0; i < 3; i++) {
        expect([pixel.r, pixel.g, pixel.b][i], closeTo(rgb[i], 6),
            reason: 'got (${pixel.r}, ${pixel.g}, ${pixel.b}), want $rgb');
      }
    }

    test('transparent grayscale-with-alpha areas become white, not black',
        () async {
      final source = image.Image(width: 64, height: 64, numChannels: 2);
      for (final pixel in source) {
        // Left half opaque dark gray, right half fully transparent.
        pixel.setRgba(60, 60, 60, pixel.x < 32 ? 255 : 0);
      }
      final out = await optimize(image.encodePng(source));
      expectNear(out.getPixel(5, 5), [60, 60, 60]);
      expectNear(out.getPixel(58, 5), [255, 255, 255]);
    });

    test('semi-transparent color blends over white', () async {
      final source = image.Image(width: 32, height: 32, numChannels: 4);
      for (final pixel in source) {
        pixel.setRgba(0, 0, 255, 128);
      }
      final out = await optimize(image.encodePng(source));
      expectNear(out.getPixel(16, 16), [127, 127, 255]);
    });

    test('16-bit PNG keeps its color', () async {
      final source = image.Image(
          width: 32, height: 32, numChannels: 4, format: image.Format.uint16);
      for (final pixel in source) {
        pixel.setRgba(65535, 0, 0, 65535);
      }
      final out = await optimize(image.encodePng(source));
      expectNear(out.getPixel(16, 16), [255, 0, 0]);
    });

    test('EXIF orientation is applied, then removed', () async {
      final source = image.Image(width: 80, height: 40);
      image.fill(source, color: image.ColorRgb8(0, 200, 0));
      source.exif.imageIfd.orientation = 6; // rotate 90 degrees clockwise
      final out = await optimize(image.encodeJpg(source));
      expect([out.width, out.height], [40, 80]);
      expect(out.exif.isEmpty, isTrue);
    });

    test('a GIF is accepted as its first frame', () async {
      final source = image.Image(width: 40, height: 20);
      image.fill(source, color: image.ColorRgb8(200, 0, 0));
      final out = await optimize(image.encodeGif(source));
      expect([out.width, out.height], [40, 20]);
      expectNear(out.getPixel(10, 10), [200, 0, 0]);
    });

    test('a small WebP from the gallery is accepted', () async {
      // 3 x 2 lossless WebP, red at alpha 128 (generated with Pillow).
      final webp =
          base64Decode('UklGRhwAAABXRUJQVlA4TA8AAAAvAkAAEAcQ/Y8CBiKi/wEA');
      final out = await optimize(webp);
      expect([out.width, out.height], [3, 2]);
      expectNear(out.getPixel(1, 1), [255, 127, 127]);
    });

    test('other formats name the supported ones', () async {
      for (final source in [
        image.encodeBmp(image.Image(width: 4, height: 4)),
        [0, 0, 0, 24, ...ascii.encode('ftypheic'), 0, 0, 0, 0],
      ]) {
        await expectLater(
            optimize(source),
            throwsA(isA<EditorMediaException>().having((e) => e.message,
                'message', 'Choose a JPEG, PNG, WebP or GIF image.')));
      }
    });

    test('an oversized GIF is refused before its pixels are decoded', () async {
      // Header claims 4097 x 1: beyond the 4096 dimension bound.
      final source = image.encodeGif(image.Image(width: 4097, height: 1));
      await expectLater(optimize(source), throwsA(isA<EditorMediaException>()));
    });

    group('a first frame smaller than the logical canvas', () {
      // 20 x 20: columns 0-7 red, 8-19 blue. Placed at (40, 40), every color
      // edge falls on an 8-pixel JPEG block boundary, so samples are exact.
      image.Image frame() {
        final source = image.Image(width: 20, height: 20);
        for (final pixel in source) {
          pixel.setRgb(pixel.x < 8 ? 255 : 0, 0, pixel.x < 8 ? 0 : 255);
        }
        return source;
      }

      void expectPlacedAt40(image.Image out) {
        expect([out.width, out.height], [100, 100],
            reason: 'the output keeps the logical canvas, not the frame');
        expectNear(out.getPixel(44, 44), [255, 0, 0]);
        expectNear(out.getPixel(52, 52), [0, 0, 255]);
        // Uncovered canvas is white, whatever the background field says.
        for (final (x, y) in [
          (36, 44),
          (44, 36),
          (36, 36),
          (66, 50),
          (50, 66),
          (5, 5),
          (95, 95),
        ]) {
          expectNear(out.getPixel(x, y), [255, 255, 255]);
        }
      }

      test('GIF frame is composited at its declared offset', () async {
        final gif = offsetGif(frame(), width: 100, height: 100, x: 40, y: 40);
        final info = image.GifDecoder().startDecode(gif)!;
        expect([info.width, info.height], [100, 100]);
        expect([info.frames.first.x, info.frames.first.y], [40, 40]);
        expect([info.frames.first.width, info.frames.first.height], [20, 20]);
        expectPlacedAt40(await optimize(gif));
      });

      test('interlaced GIF frame below the top edge is placed, not refused',
          () async {
        // The package writes interlaced rows at their canvas row, which
        // overruns a frame that starts below row 0.
        final gif = offsetGif(frame(),
            width: 100, height: 100, x: 40, y: 40, interlaced: true);
        expect(image.GifDecoder().startDecode(gif)!.frames.first.interlaced,
            isTrue);
        expectPlacedAt40(await optimize(gif));
      });

      test('a GIF frame overrunning the logical canvas is refused', () async {
        final gif = offsetGif(frame(), width: 50, height: 50, x: 40, y: 40);
        await expectLater(optimize(gif), throwsA(isA<EditorMediaException>()));
      });

      test('animated WebP frame is composited at its declared offset',
          () async {
        final webp =
            animatedWebP(frame(), width: 100, height: 100, x: 40, y: 40);
        final info = image.WebPDecoder().startDecode(webp)!;
        expect([info.width, info.height], [100, 100]);
        expect(info.hasAnimation, isTrue);
        final first = info.frames.first;
        expect([first.x, first.y, first.width, first.height], [40, 40, 20, 20]);
        // The package's own full animation decode agrees on the placement.
        final reference = image.decodeWebP(webp)!;
        expect([reference.width, reference.height], [100, 100]);
        expect(reference.getPixel(44, 44).r, 255);
        expect(reference.getPixel(5, 5).a, 0);
        expectPlacedAt40(await optimize(webp));
      });

      test('a WebP frame overrunning the canvas is refused', () async {
        final webp = animatedWebP(frame(), width: 50, height: 50, x: 40, y: 40);
        await expectLater(optimize(webp), throwsA(isA<EditorMediaException>()));
      });

      test('a full-canvas animated WebP keeps its first frame', () async {
        final first = image.Image(width: 24, height: 16);
        image.fill(first, color: image.ColorRgb8(0, 160, 0));
        final second = image.Image(width: 24, height: 16);
        image.fill(second, color: image.ColorRgb8(160, 0, 0));
        first.addFrame(second);
        final webp = image.encodeWebP(first);
        expect(image.WebPDecoder().startDecode(webp)!.hasAnimation, isTrue);
        final out = await optimize(webp);
        expect([out.width, out.height], [24, 16]);
        expectNear(out.getPixel(12, 8), [0, 160, 0]);
      });
    });
  });
}

/// Re-declares a single-frame GIF from the package encoder as a [width] x
/// [height] logical screen whose only frame sits at ([x], [y]). The background
/// index is set to 0, a frame color, so honoring it would not produce white.
Uint8List offsetGif(image.Image frame,
    {required int width,
    required int height,
    required int x,
    required int y,
    bool interlaced = false}) {
  final bytes = Uint8List.fromList(image.encodeGif(frame));
  final data = ByteData.sublistView(bytes);
  data.setUint16(6, width, Endian.little);
  data.setUint16(8, height, Endian.little);
  bytes[11] = 0;
  final flags = bytes[10];
  var p = 13 + ((flags & 0x80) != 0 ? 3 << ((flags & 7) + 1) : 0);
  while (bytes[p] == 0x21) {
    // Extension: introducer, label, then data sub-blocks up to a 0 length.
    p += 2;
    while (bytes[p] != 0) {
      p += bytes[p] + 1;
    }
    p++;
  }
  expect(bytes[p], 0x2c, reason: 'image descriptor');
  data.setUint16(p + 1, x, Endian.little);
  data.setUint16(p + 3, y, Endian.little);
  if (interlaced) bytes[p + 9] |= 0x40;
  return bytes;
}

/// A VP8X + ANIM + ANMF animation of one lossless [frame] at ([x], [y]) on a
/// [width] x [height] canvas. The package encoder always writes frames at the
/// origin, so the container is assembled around its VP8L chunk. The ANIM
/// background is opaque black, which libwebp (and the editor) ignore.
Uint8List animatedWebP(image.Image frame,
    {required int width, required int height, required int x, required int y}) {
  final still = image.encodeWebP(frame);
  expect(ascii.decode(still.sublist(12, 16)), 'VP8L');
  final vp8l = still.sublist(12); // the VP8L chunk, header and padding
  Uint8List chunk(String tag, List<int> payload) {
    final out = BytesBuilder()
      ..add(ascii.encode(tag))
      ..add((ByteData(4)..setUint32(0, payload.length, Endian.little))
          .buffer
          .asUint8List())
      ..add(payload);
    if (payload.length.isOdd) out.addByte(0);
    return out.toBytes();
  }

  List<int> u24(int value) => [value & 0xff, (value >> 8) & 0xff, value >> 16];
  final body = BytesBuilder()
    ..add(ascii.encode('WEBP'))
    ..add(chunk('VP8X', [0x12, 0, 0, 0, ...u24(width - 1), ...u24(height - 1)]))
    ..add(chunk('ANIM', [0, 0, 0, 0xff, 0, 0]))
    ..add(chunk('ANMF', [
      ...u24(x ~/ 2),
      ...u24(y ~/ 2),
      ...u24(frame.width - 1),
      ...u24(frame.height - 1),
      ...u24(100),
      0,
      ...vp8l,
    ]));
  final payload = body.toBytes();
  return (BytesBuilder()
        ..add(ascii.encode('RIFF'))
        ..add((ByteData(4)..setUint32(0, payload.length, Endian.little))
            .buffer
            .asUint8List())
        ..add(payload))
      .toBytes();
}
