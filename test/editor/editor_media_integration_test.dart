import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/editor/editor_media.dart';
import 'package:atomic_notes/editor/image_optimizer.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

class _ImageInput implements EditorImageInput {
  String? result;
  bool fail = false;
  int calls = 0;
  int? lastMaxBytes;
  @override
  Future<String?> pickJpeg({required int maxBytes}) async {
    calls++;
    lastMaxBytes = maxBytes;
    expect(maxBytes, inInclusiveRange(1, 60 * 1024));
    if (fail) throw const EditorMediaException('Gallery unavailable');
    return result;
  }
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
  _ImageInput? images,
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
  if (label == 'Add image' &&
      find.byType(NoteImageOptimizer).evaluate().isNotEmpty) {
    final progress = find.descendant(
        of: find.byType(NoteImageOptimizer),
        matching: find.byType(LinearProgressIndicator));
    // Exercise the production compute isolate, which needs real event-loop
    // time rather than only advancing Flutter's fake animation clock.
    for (var attempt = 0;
        attempt < 100 && progress.evaluate().isNotEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(progress, findsNothing, reason: 'image optimization should finish');
  }
  await tester.pumpAndSettle();
}

Future<void> _startSpeech(WidgetTester tester) async {
  await _action(tester, 'Dictate text');
  await tester.tap(find.text('Start dictation'));
  await tester.pumpAndSettle();
}

void main() {
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
    expect(find.byType(NoteImageOptimizer), findsOneWidget);
    final preview = tester.widget<Image>(find.byType(Image));
    final optimized = base64Encode((preview.image as MemoryImage).bytes);
    await tester.ensureVisible(find.text('Insert image'));
    await tester.tap(find.text('Insert image'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteImageOptimizer), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('4 WORDS'), findsOneWidget);
    expect(find.text('1 MIN READ'), findsOneWidget);
    expect(note.body, 'two plain words');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final saved = NoteDocument.fromNote(note);
    expect(saved.isReadOnly, isFalse);
    expect(saved.lines.where((l) => l.isImage).single.imageBase64, optimized);
    expect(saved.lines.where((l) => !l.isImage).single.text, 'two plain words');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('4 WORDS'), findsOneWidget);
    expect(find.textContaining(encoded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'canceling the optimizer preserves the draft without attaching an image',
      (tester) async {
    final note = Note(id: 'optimizer-cancel', body: 'Original');
    final encoded =
        base64Encode(image.encodeJpg(image.Image(width: 16, height: 12)));
    await _open(tester, note, images: _ImageInput()..result = encoded);
    await tester.enterText(_body, 'Edited draft remains');
    await _action(tester, 'Add image');
    expect(find.byType(NoteImageOptimizer), findsOneWidget);
    expect(note.body, 'Original');
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteImageOptimizer), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(_controller(tester).text, 'Edited draft remains');
    expect(note.body, 'Original');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(note.body, 'Edited draft remains');
    expect(NoteDocument.fromNote(note).lines.where((l) => l.isImage), isEmpty);
  });
  testWidgets(
      'picker preparation uses the full cap while sheet shows remaining image budget',
      (tester) async {
    final encoded =
        base64Encode(image.encodeJpg(image.Image(width: 16, height: 12)));
    final original =
        Note(id: 'aggregate-image-budget', body: 'Keep existing image');
    final document = NoteDocument.fromNote(original);
    document.insertImageAfter(0, encoded);
    final note = document.toNote(original);
    final before = note.contentSig;
    final remaining =
        NoteContentBudget.maxImageBytes - base64Decode(encoded).length;
    final input = _ImageInput()..result = encoded;
    await _open(tester, note, images: input);
    await _action(tester, 'Add image');
    expect(input.lastMaxBytes, NoteContentBudget.maxImageBytes);
    expect(find.byType(NoteImageOptimizer), findsOneWidget);
    expect(
        find.text(
            'Available image budget: ${(remaining / 1024).toStringAsFixed(1)} KB'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(note.contentSig, before);
    expect(NoteDocument.fromNote(note).lines.where((line) => line.isImage),
        hasLength(1));
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
