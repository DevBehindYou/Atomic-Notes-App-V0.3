import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:atomic_notes/editor/editor_media.dart';
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
    expect(imageQuality, lessThanOrEqualTo(70));
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
  test('new high-entropy images automatically downsize below 24000 bytes',
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
    // Even callers carrying the legacy 60 KiB budget cannot bypass the new cap.
    final encoded =
        await PlatformEditorImageInput(picker: picker, isAndroid: false)
            .pickJpeg(maxBytes: 60 * 1024);
    final bytes = base64Decode(encoded!);
    final decoded = image.decodeJpg(bytes)!;
    expect(bytes.length, lessThan(24000));
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
            .pickJpeg(maxBytes: 23999);
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
}
