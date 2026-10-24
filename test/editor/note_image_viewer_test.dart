import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/editor/editor_media.dart';
import 'package:atomic_notes/editor/note_image_viewer.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

class _Speech implements EditorSpeechInput {
  int cancels = 0;
  void Function(String, bool)? result;
  @override
  Future<bool> start({
    required void Function(String, bool) onResult,
    required void Function(String) onError,
    required void Function() onStopped,
  }) async {
    result = onResult;
    return true;
  }

  @override
  Future<void> cancel() async => cancels++;
  @override
  Future<void> stop() async {}
}

Finder get _body => find.byKey(const ValueKey('note-body'));
Finder get _fullImage => find.byWidgetPredicate((widget) =>
    widget is Image && widget.semanticLabel == 'Full size note image');

Note _note(int width, int height) {
  final original =
      Note(id: 'image-viewer', title: 'Original', body: 'Saved text');
  final document = NoteDocument.fromNote(original);
  document.insertImageAfter(0,
      base64Encode(image.encodeJpg(image.Image(width: width, height: height))));
  return document.toNote(original);
}

Future<void> _open(WidgetTester tester, Note note,
    {Size size = const Size(390, 844),
    double scale = 1,
    double keyboard = 0,
    _Speech? speech}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => NotesCreaterPage(
                  note: note, speechInput: speech ?? _Speech())),
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _view(WidgetTester tester) async {
  final opener = find.byTooltip('View note image');
  if (opener.evaluate().isEmpty) {
    await tester.scrollUntilVisible(opener, 120,
        scrollable: find
            .descendant(
                of: find.byType(NotesCreaterPage),
                matching: find.byType(Scrollable))
            .first);
  }
  expect(opener, findsOneWidget);
  await tester.ensureVisible(opener);
  await tester.pumpAndSettle();
  await tester.tap(opener);
  await tester.pump();
  // Native codec work needs real event-loop time; Flutter's test clock alone
  // cannot finish the asynchronous decode while a progress indicator animates.
  for (var attempt = 0;
      attempt < 100 && _fullImage.evaluate().isEmpty;
      attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void _expectFits(WidgetTester tester, double aspect,
    {required Size screen, double keyboard = 0}) {
  final rect = tester.getRect(_fullImage);
  expect(rect.width / rect.height, closeTo(aspect, 0.01));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(24));
  expect(rect.right, lessThanOrEqualTo(screen.width));
  expect(rect.bottom, lessThanOrEqualTo(screen.height - keyboard));
  for (final label in ['Close image', 'Zoom in', 'Zoom out', 'Reset zoom']) {
    final button = find.byTooltip(label);
    expect(button.hitTestable(), findsOneWidget);
    expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final dimensions in [const Size(240, 80), const Size(80, 240)]) {
    testWidgets(
        'whole ${dimensions.aspectRatio > 1 ? 'landscape' : 'portrait'} image fits popup',
        (tester) async {
      final note = _note(dimensions.width.toInt(), dimensions.height.toInt());
      await _open(tester, note);
      await _view(tester);
      _expectFits(tester, dimensions.aspectRatio, screen: const Size(390, 844));
      final imageWidget = tester.widget<Image>(_fullImage);
      expect(imageWidget.fit, BoxFit.contain);
    });
  }

  testWidgets('narrow 2x text with keyboard refits after orientation changes',
      (tester) async {
    await _open(tester, _note(240, 80),
        size: const Size(320, 760), scale: 2, keyboard: 280);
    await _view(tester);
    _expectFits(tester, 3, screen: const Size(320, 760), keyboard: 280);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    tester.view.physicalSize = const Size(760, 320);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    _expectFits(tester, 3, screen: const Size(760, 320));
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
  });

  testWidgets('zoom controls, pinch, pan and reset inspect without editing',
      (tester) async {
    final note = _note(240, 80);
    final before = note.toMap();
    await _open(tester, note);
    await _view(tester);
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    final translation = controller.value.getTranslation();
    await tester.drag(find.byType(InteractiveViewer), const Offset(30, 15));
    await tester.pumpAndSettle();
    expect(controller.value.getTranslation(), isNot(translation));
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pump();
    expect(controller.value.isIdentity(), isTrue);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first =
        await tester.startGesture(center - const Offset(25, 0), pointer: 1);
    final second =
        await tester.startGesture(center + const Offset(25, 0), pointer: 2);
    await tester.pump();
    await first.moveTo(center - const Offset(70, 0));
    await second.moveTo(center + const Offset(70, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pump();
    expect(controller.value.isIdentity(), isTrue);
    expect(note.toMap(), before);
  });

  testWidgets('image opener and controls support keyboard and accessibility',
      (tester) async {
    await _open(tester, _note(240, 80));
    final opener = find.byTooltip('View note image');
    final inkWell = find.descendant(of: opener, matching: find.byType(InkWell));
    final openFocus = Focus.of(tester.element(find.byType(Image)));
    openFocus.requestFocus();
    await tester.pump();
    expect(inkWell, findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('View note image')), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    for (var attempt = 0;
        attempt < 100 && _fullImage.evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(_fullImage, findsOneWidget);
    final zoom = find.byTooltip('Zoom in');
    Focus.of(tester
            .element(find.descendant(of: zoom, matching: find.byType(Icon))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_fullImage, findsNothing);
    expect(find.byType(NotesCreaterPage), findsOneWidget);
  });

  testWidgets('decode failure keeps accessible Close available',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
        onPressed: () => showDialog<void>(
            context: context,
            builder: (_) =>
                NoteImageViewer(bytes: Uint8List.fromList([1, 2, 3]))),
        child: const Text('View invalid image'),
      ));
    })));
    await tester.tap(find.text('View invalid image'));
    await tester.pump();
    final failure = find.text('Image could not be displayed.');
    for (var attempt = 0;
        attempt < 100 && failure.evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(failure, findsOneWidget);
    expect(
        tester.getSemantics(find.byTooltip('Close image')),
        matchesSemantics(
            tooltip: 'Close image',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasFocusAction: true,
            hasTapAction: true));
    await tester.tap(find.byTooltip('Close image'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteImageViewer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close, back and barrier preserve draft and reuse original bytes',
      (tester) async {
    final note = _note(240, 80);
    final before = note.toMap();
    await _open(tester, note);
    await tester.enterText(_body, 'Unsaved draft');
    final originalBytes =
        (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes;
    for (final dismiss in ['close', 'back', 'barrier']) {
      await _view(tester);
      final shownBytes =
          (tester.widget<Image>(_fullImage).image as MemoryImage).bytes;
      expect(identical(shownBytes, originalBytes), isTrue);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      if (dismiss == 'close') {
        await tester.tap(find.byTooltip('Close image'));
      } else if (dismiss == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(2, 50));
      }
      await tester.pumpAndSettle();
      expect(_fullImage, findsNothing);
      expect(tester.widget<TextField>(_body).controller!.text, 'Unsaved draft');
      expect(note.toMap(), before);
    }
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final saved = NoteDocument.fromNote(note);
    expect(saved.lines.first.text, 'Unsaved draft');
    expect(
        saved.lines.singleWhere((line) => line.isImage).imageBase64,
        NoteDocument.fromNote(Note.fromMap(before))
            .lines
            .singleWhere((line) => line.isImage)
            .imageBase64);
  });

  testWidgets('opening image cancels dictation and ignores late speech',
      (tester) async {
    final speech = _Speech();
    final note = _note(240, 80);
    await _open(tester, note, speech: speech);
    await tester.tap(_body);
    await tester.enterText(_body, 'Unsaved draft');
    await tester.tap(find.byTooltip('Dictate text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start dictation'));
    await tester.pumpAndSettle();
    final cancels = speech.cancels;
    await _view(tester);
    expect(speech.cancels, greaterThan(cancels));
    speech.result!('Late words', true);
    await tester.pump();
    await tester.tap(find.byTooltip('Close image'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_body).controller!.text, 'Unsaved draft');
    expect(tester.widget<TextField>(_body).focusNode!.hasFocus, isFalse,
        reason: 'primary focus: ${FocusManager.instance.primaryFocus}');
    expect(tester.takeException(), isNull);
  });
}
