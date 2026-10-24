import 'dart:convert';
import 'dart:math';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/editor/editor_media.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';

class _ImageInput implements EditorImageInput {
  String? result;
  bool fail = false;
  int calls = 0;
  int? lastMaxBytes;
  @override
  Future<String?> pickJpeg({required int maxBytes}) async {
    calls++;
    lastMaxBytes = maxBytes;
    expect(maxBytes, inInclusiveRange(1, 23999));
    if (fail) throw const EditorMediaException('Gallery unavailable');
    return result;
  }
}

class _GalleryPicker extends ImagePicker {
  _GalleryPicker(this.file);
  XFile file;
  int calls = 0;
  @override
  Future<XFile?> pickImage(
      {required ImageSource source,
      double? maxWidth,
      double? maxHeight,
      int? imageQuality,
      CameraDevice preferredCameraDevice = CameraDevice.rear,
      bool requestFullMetadata = true}) async {
    calls++;
    return file;
  }
}

String _legacyLargeJpeg() {
  final pixels = image.Image(width: 160, height: 160);
  final random = Random(112);
  for (var y = 0; y < pixels.height; y++) {
    for (var x = 0; x < pixels.width; x++) {
      pixels.setPixelRgb(
          x, y, random.nextInt(256), random.nextInt(256), random.nextInt(256));
    }
  }
  return base64Encode(image.encodeJpg(pixels, quality: 90));
}

String _jpegWithExactBytes(int size) {
  final jpeg = image.encodeJpg(image.Image(width: 16, height: 12));
  final padding = size - jpeg.length - 4;
  assert(padding >= 0 && padding < 65533);
  final segmentLength = padding + 2;
  return base64Encode([
    ...jpeg.take(2),
    0xff,
    0xfe,
    segmentLength >> 8,
    segmentLength & 255,
    ...List<int>.filled(padding, 0),
    ...jpeg.skip(2),
  ]);
}

/// Intentionally emits even after cancellation to verify the UI session guard.
class _SpeechInput implements EditorSpeechInput {
  int starts = 0, cancels = 0, stops = 0;
  bool completeDuringStart = false;
  void Function(String, bool)? result;
  void Function()? stopped;
  @override
  Future<bool> start(
      {required void Function(String, bool) onResult,
      required void Function(String) onError,
      required void Function() onStopped}) async {
    starts++;
    result = onResult;
    stopped = onStopped;
    if (completeDuringStart) {
      onResult('fast final', true);
      onStopped();
      return false;
    }
    return true;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  void words(String words, {bool finalResult = false}) =>
      result!(words, finalResult);
}

Finder get _body => find.byKey(const ValueKey('note-body'));
TextEditingController _controller(WidgetTester tester) =>
    tester.widget<TextField>(_body).controller!;

Future<void> _open(
  WidgetTester tester,
  Note note, {
  EditorImageInput? images,
  _SpeechInput? speech,
  VoidCallback? onDelete,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => NotesCreaterPage(
                          note: note,
                          imageInput: images ?? _ImageInput(),
                          speechInput: speech ?? _SpeechInput(),
                          onDelete: onDelete)),
                  child: const Text('Open'))))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _action(WidgetTester tester, String label) async {
  final button = find.byTooltip(label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
  if (label == 'Add image') {
    bool preparing() =>
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
            .onPressed ==
        null;
    // Exercise the production compute isolate, which needs real event-loop
    // time rather than only advancing Flutter's fake animation clock.
    for (var attempt = 0; attempt < 100 && preparing(); attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(preparing(), isFalse,
        reason: 'automatic image optimization should finish');
  }
  await tester.pumpAndSettle();
}

Future<void> _startSpeech(WidgetTester tester) async {
  await _action(tester, 'Dictate text');
  await tester.tap(find.text('Start dictation'));
  await tester.pumpAndSettle();
}

Note _savedImages(int count, String encoded) => Note(
      id: 'saved-images-$count',
      title: 'Images',
      body: jsonEncode({
        'v': 2,
        'tags': <String>[],
        'blocks': [
          {
            'text': 'Keep this prose',
            'checklist': false,
            'done': false,
            'styles': []
          },
          for (var i = 0; i < count; i++)
            {
              'text': '',
              'checklist': false,
              'done': false,
              'styles': [],
              'image': encoded
            },
        ],
      }),
      items: [TodoItem(text: NoteDocument.richFormatMarker)],
    );

Future<void> _dismissMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

Future<void> _removeFirstImage(WidgetTester tester) async {
  final button = find.widgetWithText(TextButton, 'Remove image').first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('third image is accepted and fourth never opens the picker',
      (tester) async {
    final encoded =
        base64Encode(image.encodeJpg(image.Image(width: 16, height: 12)));
    final note = _savedImages(2, encoded);
    final input = _ImageInput()..result = encoded;
    await _open(tester, note, images: input);
    await tester.enterText(_body, 'Latest unsaved prose');
    await _action(tester, 'Add image');
    expect(input.calls, 1);
    await _action(tester, 'Add image');
    expect(input.calls, 1);
    expect(find.textContaining('3 images per note'), findsWidgets);
    expect(_controller(tester).text, 'Latest unsaved prose');
    await _dismissMessage(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(NoteDocument.fromNote(note).lines.where((line) => line.isImage),
        hasLength(3));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'legacy four images survive save and block additions until below three',
      (tester) async {
    final encoded =
        base64Encode(image.encodeJpg(image.Image(width: 16, height: 12)));
    final note = _savedImages(4, encoded);
    final before = note.toMap();
    final input = _ImageInput()..result = encoded;
    await _open(tester, note, images: input);
    expect(NoteDocument.fromNote(note).lines.where((line) => line.isImage),
        hasLength(4));
    await _action(tester, 'Add image');
    expect(input.calls, 0);
    expect(find.textContaining('3 images per note'), findsWidgets);
    await _dismissMessage(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.toMap(), before);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _removeFirstImage(tester);
    await _action(tester, 'Add image');
    expect(input.calls, 0, reason: 'three remaining images still fill the cap');
    await _dismissMessage(tester);
    await _removeFirstImage(tester);
    await _action(tester, 'Add image');
    expect(input.calls, 1);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final saved = NoteDocument.fromNote(note);
    expect(saved.lines.where((line) => line.isImage), hasLength(3));
    expect(
        saved.lines
            .where((line) => line.isImage)
            .every((line) => line.imageBase64 == encoded),
        isTrue);
    expect(saved.lines.first.text, 'Keep this prose');
  });

  testWidgets('JPEG and PNG selections share one three-image limit',
      (tester) async {
    final pixels = image.Image(width: 16, height: 12);
    final png = XFile.fromData(image.encodePng(pixels), mimeType: 'image/png');
    final jpeg =
        XFile.fromData(image.encodeJpg(pixels), mimeType: 'image/jpeg');
    final picker = _GalleryPicker(png);
    final input = PlatformEditorImageInput(picker: picker, isAndroid: false);
    final note = Note(id: 'mixed-source-formats', body: 'Keep prose');
    await _open(tester, note, images: input);
    for (final source in [png, jpeg, png]) {
      picker.file = source;
      await _action(tester, 'Add image');
    }
    expect(picker.calls, 3);
    await _action(tester, 'Add image');
    expect(picker.calls, 3);
    expect(find.textContaining('3 images per note'), findsWidgets);
    await _dismissMessage(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final images =
        NoteDocument.fromNote(note).lines.where((line) => line.isImage);
    expect(images, hasLength(3));
    for (final block in images) {
      final bytes = base64Decode(block.imageBase64!);
      expect(bytes.length, lessThan(24000));
      expect(image.decodeJpg(bytes), isNotNull);
    }
  });

  testWidgets('title stays above tags and uses the accepted 32px size',
      (tester) async {
    final original =
        Note(id: 'title-tags', title: 'Project title', body: 'Body');
    final document = NoteDocument.fromNote(original)..setTags(['planning']);
    await _open(tester, document.toNote(original));
    final title = find.byKey(const ValueKey('note-title'));
    expect(tester.widget<TextField>(title).style!.fontSize, 32);
    expect(tester.getRect(title).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('#planning')).top));
  });
  testWidgets('image cancellation preserves text and saves no image block',
      (tester) async {
    final note = Note(id: 'photo-cancel', title: 'Project', body: 'Original');
    final input = _ImageInput();
    await _open(tester, note, images: input);
    await tester.enterText(_body, 'Edited draft stays here');
    await _action(tester, 'Add image');
    expect(input.calls, 1);
    expect(_controller(tester).text, 'Edited draft stays here');
    expect(find.byType(Image), findsNothing);
    expect(note.body, 'Original');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.body, 'Edited draft stays here');
    expect(NoteDocument.fromNote(note).lines.where((l) => l.isImage), isEmpty);
  });

  testWidgets('image survives save and reopen without entering word counts',
      (tester) async {
    final note =
        Note(id: 'photo-save', title: 'Project', body: 'two plain words');
    final bytes = image.encodeJpg(image.Image(width: 16, height: 12));
    final encoded = base64Encode(bytes);
    await _open(tester, note, images: _ImageInput()..result = encoded);
    expect(find.text('4 WORDS'), findsOneWidget);
    await _action(tester, 'Add image');
    expect(find.text('Optimize image'), findsNothing);
    expect(find.text('Insert image'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('4 WORDS'), findsOneWidget);
    expect(find.text('1 MIN READ'), findsOneWidget);
    expect(note.body, 'two plain words');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final saved = NoteDocument.fromNote(note);
    expect(saved.isReadOnly, isFalse);
    expect(saved.lines.where((l) => l.isImage).single.imageBase64, encoded);
    expect(saved.lines.where((l) => !l.isImage).single.text, 'two plain words');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('4 WORDS'), findsOneWidget);
    expect(find.textContaining(encoded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'gallery selection optimizes in compute and inserts without a prompt',
      (tester) async {
    final source = image.encodePng(image.Image(width: 128, height: 96));
    final input = PlatformEditorImageInput(
        picker: _GalleryPicker(XFile.fromData(source, mimeType: 'image/png')),
        isAndroid: false);
    final note = Note(id: 'automatic-gallery', body: 'Retain prose');
    await _open(tester, note, images: input);
    await _action(tester, 'Add image');
    expect(find.text('Optimize image'), findsNothing);
    expect(find.text('Insert image'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(note.body, 'Retain prose');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final doc = NoteDocument.fromNote(note);
    final bytes = base64Decode(
        doc.lines.where((line) => line.isImage).single.imageBase64!);
    expect(bytes.length, inInclusiveRange(1, 23999));
    final decoded = image.decodeJpg(bytes)!;
    expect([decoded.width, decoded.height], [128, 96]);
    expect(
        doc.lines.where((line) => !line.isImage).single.text, 'Retain prose');
  });

  testWidgets(
      'discarding after automatic insertion preserves the original note',
      (tester) async {
    final note = Note(id: 'optimizer-cancel', body: 'Original');
    final encoded =
        base64Encode(image.encodeJpg(image.Image(width: 16, height: 12)));
    await _open(tester, note, images: _ImageInput()..result = encoded);
    await tester.enterText(_body, 'Edited draft remains');
    await _action(tester, 'Add image');
    expect(find.byType(Image), findsOneWidget);
    expect(note.body, 'Original');
    await _action(tester, 'Back to notes');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesCreaterPage), findsNothing);
    expect(note.body, 'Original');
    expect(NoteDocument.fromNote(note).lines.where((l) => l.isImage), isEmpty);
  });
  testWidgets(
      'remaining aggregate budget gates new images without rewriting a larger legacy image',
      (tester) async {
    final encoded =
        base64Encode(image.encodeJpg(image.Image(width: 16, height: 12)));
    final legacy = _legacyLargeJpeg();
    expect(base64Decode(legacy).length, greaterThan(23999));
    expect(base64Decode(legacy).length, lessThanOrEqualTo(60 * 1024));
    final original =
        Note(id: 'aggregate-image-budget', body: 'Keep existing image');
    final document = NoteDocument.fromNote(original);
    document.insertImageAfter(0, legacy);
    final note = document.toNote(original);
    final before = note.contentSig;
    final remaining =
        NoteContentBudget.maxImageBytes - base64Decode(legacy).length;
    expect(remaining, lessThan(23999));
    final input = _ImageInput()..result = encoded;
    await _open(tester, note, images: input);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.contentSig, before,
        reason: 'opening/saving must not recompress old images');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _action(tester, 'Add image');
    expect(input.lastMaxBytes, remaining);
    expect(find.text('Optimize image'), findsNothing);
    expect(find.byType(Image), findsNWidgets(2));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final images = NoteDocument.fromNote(note)
        .lines
        .where((line) => line.isImage)
        .toList();
    expect(images, hasLength(2));
    expect(images.first.imageBase64, legacy);
    expect(images.last.imageBase64, encoded);
  });

  testWidgets('image failure leaves unsaved draft editable', (tester) async {
    final note = Note(id: 'photo-fail', body: 'Original');
    await _open(tester, note, images: _ImageInput()..fail = true);
    await tester.enterText(_body, 'Keep this draft');
    await _action(tester, 'Add image');
    expect(_controller(tester).text, 'Keep this draft');
    expect(note.body, 'Original');
    expect(find.byType(Image), findsNothing);
    expect(find.text('Gallery unavailable'), findsWidgets);
    await tester.enterText(_body, 'Keep this draft and edit');
    // The temporary floating error toast covers the footer while visible.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.body, 'Keep this draft and edit');
  });

  testWidgets('an adapter result at 24000 bytes is rejected without draft loss',
      (tester) async {
    final note = Note(id: 'exact-image-boundary', body: 'Original');
    final input = _ImageInput()..result = _jpegWithExactBytes(24000);
    await _open(tester, note, images: input);
    await tester.enterText(_body, 'Keep my latest draft');
    await _action(tester, 'Add image');
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('under 24 KB'), findsWidgets);
    expect(_controller(tester).text, 'Keep my latest draft');
    expect(note.body, 'Original');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.body, 'Keep my latest draft');
    expect(NoteDocument.fromNote(note).imageBytes, 0);
  });

  testWidgets('a sub-24KB image still respects the complete note sync budget',
      (tester) async {
    final original = 'x' * 100000;
    final note = Note(id: 'complete-note-image-limit', body: original);
    expect(NoteContentBudget.errorFor(note), isNull);
    final input = _ImageInput()..result = _jpegWithExactBytes(23999);
    await _open(tester, note, images: input);
    await _action(tester, 'Add image');
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('sync size limit'), findsWidgets);
    expect(_controller(tester).text, original);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.body, original);
    expect(NoteDocument.fromNote(note).imageBytes, 0);
  });

  testWidgets('canceling speech disclosure never starts the microphone',
      (tester) async {
    final input = _SpeechInput();
    final note = Note(id: 'disclosure', body: 'Keep me');
    await _open(tester, note, speech: input);
    await _action(tester, 'Dictate text');
    expect(find.text('Dictate into your note'), findsOneWidget);
    expect(
        find.textContaining('may send audio to its provider'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(input.starts, 0);
    expect(_controller(tester).text, 'Keep me');
    expect(note.body, 'Keep me');
  });

  testWidgets('dictation partial and final replace the selected segment once',
      (tester) async {
    final input = _SpeechInput();
    final note = Note(id: 'dictation', body: 'Alpha target omega');
    await _open(tester, note, speech: input);
    await tester.tap(_body);
    _controller(tester).selection =
        const TextSelection(baseOffset: 6, extentOffset: 12);
    await tester.pump();
    await _startSpeech(tester);
    expect(input.starts, 1);
    input.words('hello');
    await tester.pump();
    expect(_controller(tester).text, 'Alpha hello omega');
    input.words('hello world', finalResult: true);
    await tester.pump();
    expect(_controller(tester).text, 'Alpha hello world omega');
    expect(_controller(tester).selection.isCollapsed, isTrue);
    expect(note.body, 'Alpha target omega');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.body, 'Alpha hello world omega');
  });

  testWidgets('typing cancels dictation and rejects a late recognition result',
      (tester) async {
    final input = _SpeechInput();
    await _open(tester, Note(id: 'manual', body: 'Before'), speech: input);
    await _startSpeech(tester);
    input.words('dictated');
    await tester.pump();
    final canceledBefore = input.cancels;
    await tester.enterText(_body, 'Manually edited text');
    await tester.pump();
    expect(input.cancels, greaterThan(canceledBefore));
    input.words('late recognition', finalResult: true);
    await tester.pump();
    expect(_controller(tester).text, 'Manually edited text');
    expect(find.byTooltip('Dictate text'), findsOneWidget);
  });

  testWidgets(
      'a final result before start resolves is saved without an unavailable toast',
      (tester) async {
    final input = _SpeechInput()..completeDuringStart = true;
    final note = Note(id: 'fast-final', body: 'Before');
    await _open(tester, note, speech: input);
    await _startSpeech(tester);
    expect(input.starts, 1);
    expect(_controller(tester).text, 'Before fast final');
    expect(note.body, 'Before');
    expect(find.byTooltip('Dictate text'), findsOneWidget);
    expect(find.byTooltip('Stop dictation'), findsNothing);
    expect(find.text('LISTENING…'), findsNothing);
    expect(
        find.textContaining('Speech recognition is unavailable'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.body, 'Before fast final');
    expect(find.byType(NotesCreaterPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stop waits for the final transcript and session end before restart',
      (tester) async {
    final input = _SpeechInput();
    await _open(tester, Note(id: 'stop-final', body: 'Before'), speech: input);
    await _startSpeech(tester);
    input.words('partial');
    await tester.pump();
    await _action(tester, 'Stop dictation');
    expect(input.stops, 1);
    expect(input.starts, 1);
    expect(find.byTooltip('Dictate text'), findsNothing);
    expect(find.byTooltip('Stop dictation'), findsOneWidget);
    input.words('complete transcript', finalResult: true);
    await tester.pump();
    expect(_controller(tester).text, 'Before complete transcript');
    expect(find.byTooltip('Dictate text'), findsNothing);
    await _action(tester, 'Stop dictation');
    expect(input.starts, 1);
    expect(input.stops, 2);
    input.stopped!();
    await tester.pump();
    expect(find.byTooltip('Dictate text'), findsOneWidget);
    await _action(tester, 'Dictate text');
    expect(input.starts, 2);
    input.words('next segment', finalResult: true);
    await tester.pump();
    expect(_controller(tester).text, 'Before complete transcript next segment');
    input.stopped!();
    await tester.pump();
  });

  testWidgets('moving the cursor cancels dictation without losing partial text',
      (tester) async {
    final input = _SpeechInput();
    await _open(tester, Note(id: 'cursor', body: 'Before'), speech: input);
    await _startSpeech(tester);
    input.words('dictated');
    await tester.pump();
    final current = _controller(tester).text;
    final canceledBefore = input.cancels;
    _controller(tester).selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    expect(input.cancels, greaterThan(canceledBefore));
    input.words('late recognition', finalResult: true);
    await tester.pump();
    expect(_controller(tester).text, current);
    expect(_controller(tester).selection.baseOffset, 0);
  });

  testWidgets('backgrounding cancels dictation and rejects late speech',
      (tester) async {
    final input = _SpeechInput();
    await _open(tester, Note(id: 'background', body: 'Before'), speech: input);
    await _startSpeech(tester);
    input.words('dictated');
    await tester.pump();
    final current = _controller(tester).text;
    final canceledBefore = input.cancels;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(input.cancels, greaterThan(canceledBefore));
    input.words('late recognition', finalResult: true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(_controller(tester).text, current);
    expect(find.byTooltip('Dictate text'), findsOneWidget);
  });

  testWidgets('focusing another body block cancels the previous speech target',
      (tester) async {
    final input = _SpeechInput();
    final original = Note(id: 'different-block', body: 'First paragraph');
    final document = NoteDocument.fromNote(original);
    document.insertChecklistAfter(0);
    document.replaceText(1, 'Second task');
    await _open(tester, document.toNote(original), speech: input);
    await tester.tap(_body);
    _controller(tester).selection =
        TextSelection.collapsed(offset: _controller(tester).text.length);
    await tester.pump();
    await _startSpeech(tester);
    input.words('dictated');
    await tester.pump();
    final before = _controller(tester).text;
    final canceledBefore = input.cancels;
    final other = find.byKey(const ValueKey('note-item-1'));
    await tester.ensureVisible(other);
    await tester.tap(other);
    await tester.pump();
    expect(input.cancels, greaterThan(canceledBefore));
    await tester.enterText(other, 'Manually edited second task');
    input.words('late recognition', finalResult: true);
    await tester.pump();
    expect(_controller(tester).text, before);
    expect(tester.widget<TextField>(other).controller!.text,
        'Manually edited second task');
  });

  testWidgets('focusing the title cancels body dictation before editing it',
      (tester) async {
    final input = _SpeechInput();
    await _open(tester, Note(id: 'title-focus', title: 'Title', body: 'Before'),
        speech: input);
    await _startSpeech(tester);
    input.words('dictated');
    await tester.pump();
    final before = _controller(tester).text;
    final canceledBefore = input.cancels;
    final title = find.byKey(const ValueKey('note-title'));
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pump();
    expect(input.cancels, greaterThan(canceledBefore));
    await tester.enterText(title, 'Edited title');
    input.words('late recognition', finalResult: true);
    await tester.pump();
    expect(_controller(tester).text, before);
    expect(tester.widget<TextField>(title).controller!.text, 'Edited title');
  });

  testWidgets(
      'delete cancel preserves draft then confirms once without saving it',
      (tester) async {
    final note =
        Note(id: 'delete', title: 'Original title', body: 'Saved content');
    final original = note.toMap();
    var deletes = 0;
    await _open(tester, note, onDelete: () => deletes++);
    await tester.enterText(_body, 'Unsaved content');
    await _action(tester, 'Delete note');
    expect(find.text('Move note to Recycle Bin?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    expect(_controller(tester).text, 'Unsaved content');
    expect(note.toMap(), original);
    await _action(tester, 'Delete note');
    await tester.tap(find.text('Move to Recycle Bin'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(note.toMap(), original);
    expect(find.byType(NotesCreaterPage), findsNothing);
  });
}
