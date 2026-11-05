import 'dart:convert';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/editor/editor_media.dart';
import 'package:atomic_notes/editor/note_image_viewer.dart';
import 'package:atomic_notes/page/notes_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../notes_editor_page_test.dart' show openEditor;

class _ImageInput implements EditorImageInput {
  _ImageInput(this.jpeg);
  final String jpeg;

  @override
  Future<String?> pickJpeg({required int maxBytes}) async => jpeg;
}

String _jpeg(int width, int height) =>
    base64Encode(image.encodeJpg(image.Image(width: width, height: height)));

Note _note(String jpeg, {int copies = 1}) {
  final original = Note(id: 'image-cache', body: 'Saved text');
  final document = NoteDocument.fromNote(original);
  for (var i = 0; i < copies; i++) {
    document.insertImageAfter(i, jpeg);
  }
  return document.toNote(original);
}

Finder get _images => find.byWidgetPredicate(
    (widget) => widget is Image && widget.semanticLabel == 'Note image');

Future<void> _decoded(WidgetTester tester, MemoryImage provider) async {
  final cache = PaintingBinding.instance.imageCache;
  for (var attempt = 0;
      attempt < 100 && !cache.statusForKey(provider).keepAlive;
      attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(cache.statusForKey(provider).keepAlive, isTrue);
}

Future<void> _removeImage(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Remove image').first);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Remove image'));
  await tester.pumpAndSettle();
}

// Editor-owned decoded images must not accumulate after their route closes.
void main() {
  setUp(() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    addTearDown(() {
      cache.clear();
      cache.clearLiveImages();
    });
  });

  testWidgets('releases decoded images after each unchanged editor visit',
      (tester) async {
    final cache = PaintingBinding.instance.imageCache;
    // Match the approved synthetic corpus's dimensions and repeated-image
    // pattern, while generating independent non-private JPEG bytes here.
    const width = 1024, height = 768;
    final note = _note(_jpeg(width, height), copies: 3);
    final before = note.toMap();
    final providers = <MemoryImage>[];
    for (var visit = 1; visit <= 3; visit++) {
      await openEditor(tester, note);
      final images = _images;
      // ListView mounts visible rows; offscreen attachments need not decode.
      expect(images, findsWidgets);
      final widget = tester.widget<Image>(images.first);
      final provider = widget.image as MemoryImage;
      for (final rendered in tester.widgetList<Image>(images)) {
        expect(rendered.image, provider,
            reason: 'Repeated bytes share one provider within this editor');
      }
      providers.add(provider);
      await _decoded(tester, provider);
      expect(cache.currentSize, 1);
      expect(cache.currentSizeBytes, width * height * 4);
      await tester.tap(find.byTooltip('Back to notes'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesCreaterPage), findsNothing);
      expect(cache.liveImageCount, 0);
      expect(cache.currentSize, 0);
      expect(cache.currentSizeBytes, 0);
      expect(note.toMap(), before);
    }
    expect(providers[0], isNot(providers[1]));
    expect(providers[1], isNot(providers[2]));
  });

  testWidgets('closing the editor preserves unrelated cached images',
      (tester) async {
    final cache = PaintingBinding.instance.imageCache;
    final unrelated = MemoryImage(base64Decode(_jpeg(32, 24)));
    await tester.pumpWidget(MaterialApp(home: Image(image: unrelated)));
    await _decoded(tester, unrelated);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final baselineBytes = cache.currentSizeBytes;
    expect(cache.currentSize, 1);
    expect(cache.statusForKey(unrelated).live, isFalse);

    await openEditor(tester, _note(_jpeg(120, 80)));
    final owned = tester.widget<Image>(_images.first).image as MemoryImage;
    await _decoded(tester, owned);
    expect(cache.currentSize, 2);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(cache.statusForKey(owned).untracked, isTrue);
    expect(cache.statusForKey(unrelated).keepAlive, isTrue);
    expect(cache.currentSize, 1);
    expect(cache.currentSizeBytes, baselineBytes);
  });

  testWidgets('last removal releases bytes but repeated attachments share them',
      (tester) async {
    final jpeg = _jpeg(120, 80);
    final note = _note(jpeg, copies: 2);
    final before = note.toMap();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: NotesCreaterPage(note: note, imageInput: _ImageInput(jpeg))));
    await tester.pumpAndSettle();
    final provider = tester.widget<Image>(_images.first).image as MemoryImage;
    await _decoded(tester, provider);
    await _removeImage(tester);
    expect(_images, findsOneWidget);
    expect(tester.widget<Image>(_images).image, provider);
    expect(PaintingBinding.instance.imageCache.statusForKey(provider).keepAlive,
        isTrue);
    await _removeImage(tester);
    expect(_images, findsNothing);
    expect(PaintingBinding.instance.imageCache.statusForKey(provider).untracked,
        isTrue);
    expect(note.toMap(), before, reason: 'removals only change the draft');

    // Re-adding the same encoded content must not reuse a removed buffer still
    // retained by the editor's map. A new attachment owns fresh bytes.
    await tester.tap(find.byTooltip('Add image'));
    await tester.pumpAndSettle();
    final added = tester.widget<Image>(_images).image as MemoryImage;
    expect(identical(added.bytes, provider.bytes), isFalse);
    expect(added.bytes, provider.bytes);
    await _decoded(tester, added);
    expect(PaintingBinding.instance.imageCache.currentSize, 1);
    expect(note.toMap(), before);
  });

  testWidgets('live popup survives editor disposal and keeps full quality',
      (tester) async {
    final cache = PaintingBinding.instance.imageCache;
    final note = _note(_jpeg(120, 80));
    final before = note.toMap();
    await openEditor(tester, note);
    final editorContext = tester.element(find.byType(NotesCreaterPage));
    final editorRoute = ModalRoute.of(editorContext)!;
    final navigator = Navigator.of(editorContext);
    final provider = tester.widget<Image>(_images).image as MemoryImage;
    await _decoded(tester, provider);
    await tester.tap(find.byTooltip('View note image'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteImageViewer), findsOneWidget);
    final fullImage = find.byWidgetPredicate((widget) =>
        widget is Image && widget.semanticLabel == 'Full size note image');
    expect(tester.widget<Image>(fullImage).image, provider);

    navigator.removeRoute(editorRoute);
    await tester.pumpAndSettle();
    expect(find.byType(NotesCreaterPage), findsNothing);
    expect(find.byType(NoteImageViewer), findsOneWidget);
    expect(cache.statusForKey(provider).live, isTrue);
    expect(cache.statusForKey(provider).keepAlive, isFalse);
    expect(tester.widget<Image>(fullImage).image, provider);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        greaterThan(1));
    expect(note.toMap(), before);
    await tester.tap(find.byTooltip('Close image'));
    await tester.pumpAndSettle();
    expect(cache.statusForKey(provider).untracked, isTrue);
    expect(cache.currentSizeBytes, 0);
    expect(tester.takeException(), isNull);
  });
}
