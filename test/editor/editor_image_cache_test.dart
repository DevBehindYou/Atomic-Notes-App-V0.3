import 'dart:convert';
import 'dart:typed_data';

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
    base64Encode(image.encodeJpg(image.Image(width: width, height: height),
        // Large legacy fixtures need 4:2:0 to stay within the 60 KiB reader.
        chroma: width * height > 1 << 20
            ? image.JpegChroma.yuv420
            : image.JpegChroma.yuv444));

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

/// The image cache key of [provider]. Thumbnails are size-bounded
/// ResizeImages; their key differs from the source MemoryImage's key.
Future<Object> _key(ImageProvider<Object> provider) =>
    provider.obtainKey(ImageConfiguration.empty);

ImageCacheStatus _status(Object key) =>
    PaintingBinding.instance.imageCache.statusForKey(key);

/// The editor thumbnail provider shown by [finder].
ResizeImage _thumbnail(WidgetTester tester, Finder finder) =>
    tester.widget<Image>(finder).image as ResizeImage;

Uint8List _sourceBytes(ResizeImage thumbnail) =>
    (thumbnail.imageProvider as MemoryImage).bytes;

Future<void> _decoded(
    WidgetTester tester, ImageProvider<Object> provider) async {
  final key = await _key(provider);
  for (var attempt = 0; attempt < 100 && !_status(key).keepAlive; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(_status(key).keepAlive, isTrue);
}

/// A 1x, 800 x 1600 view, so decoded sizes are exact.
void _plainView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1600);
  addTearDown(tester.view.reset);
}

Finder get _fullImage => find.byWidgetPredicate((widget) =>
    widget is Image && widget.semanticLabel == 'Full size note image');

/// Opens the viewer. Its full-size decode is real codec work, which needs
/// real event-loop time while the progress indicator animates.
Future<void> _openViewer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('View note image'));
  await tester.pump();
  for (var attempt = 0;
      attempt < 100 && _fullImage.evaluate().isEmpty;
      attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
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
    final providers = <ResizeImage>[];
    for (var visit = 1; visit <= 3; visit++) {
      await openEditor(tester, note);
      final images = _images;
      // ListView mounts visible rows; offscreen attachments need not decode.
      expect(images, findsWidgets);
      final provider = _thumbnail(tester, images.first);
      for (final rendered in tester.widgetList<Image>(images)) {
        expect(identical(rendered.image, provider), isTrue,
            reason: 'Repeated bytes share one provider within this editor');
      }
      providers.add(provider);
      await _decoded(tester, provider);
      expect(cache.currentSize, 1);
      // Bounded by the thumbnail box (screen width x 220, physical pixels),
      // never the full source size.
      final boxWidth = tester.view.physicalSize.width.ceil();
      final boxHeight = (220 * tester.view.devicePixelRatio).ceil();
      expect(cache.currentSizeBytes, lessThan(width * height * 4));
      expect(
          cache.currentSizeBytes, lessThanOrEqualTo(boxWidth * boxHeight * 4));
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
    final owned = _thumbnail(tester, _images.first);
    final ownedKey = await _key(owned);
    await _decoded(tester, owned);
    expect(cache.currentSize, 2);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(_status(ownedKey).untracked, isTrue);
    expect(cache.statusForKey(unrelated).keepAlive, isTrue);
    expect(cache.currentSize, 1);
    expect(cache.currentSizeBytes, baselineBytes);
  });

  testWidgets('last removal releases bytes but repeated attachments share them',
      (tester) async {
    final jpeg = _jpeg(120, 80);
    final note = _note(jpeg, copies: 2);
    final before = note.toMap();
    _plainView(tester);
    await tester.pumpWidget(MaterialApp(
        home: NotesCreaterPage(note: note, imageInput: _ImageInput(jpeg))));
    await tester.pumpAndSettle();
    final provider = _thumbnail(tester, _images.first);
    final key = await _key(provider);
    await _decoded(tester, provider);
    await _removeImage(tester);
    expect(_images, findsOneWidget);
    expect(identical(tester.widget<Image>(_images).image, provider), isTrue);
    expect(_status(key).keepAlive, isTrue);
    await _removeImage(tester);
    expect(_images, findsNothing);
    expect(_status(key).untracked, isTrue);
    expect(note.toMap(), before, reason: 'removals only change the draft');

    // Re-adding the same encoded content must not reuse a removed buffer still
    // retained by the editor's map. A new attachment owns fresh bytes.
    await tester.tap(find.byTooltip('Add image'));
    await tester.pumpAndSettle();
    final added = _thumbnail(tester, _images);
    expect(identical(_sourceBytes(added), _sourceBytes(provider)), isFalse);
    expect(_sourceBytes(added), _sourceBytes(provider));
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
    final thumbnail = _thumbnail(tester, _images);
    await _decoded(tester, thumbnail);
    await _openViewer(tester);
    expect(find.byType(NoteImageViewer), findsOneWidget);
    final fullImage = find.byWidgetPredicate((widget) =>
        widget is Image && widget.semanticLabel == 'Full size note image');
    // The viewer decodes the same bytes at full size, under its own key.
    final provider = tester.widget<Image>(fullImage).image as MemoryImage;
    expect(identical(provider.bytes, _sourceBytes(thumbnail)), isTrue);

    final thumbnailKey = await _key(thumbnail);
    navigator.removeRoute(editorRoute);
    await tester.pumpAndSettle();
    expect(find.byType(NotesCreaterPage), findsNothing);
    expect(find.byType(NoteImageViewer), findsOneWidget);
    expect(_status(thumbnailKey).untracked, isTrue,
        reason: 'the closed editor released its thumbnail');
    expect(cache.statusForKey(provider).live, isTrue);
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

  group('C06 decoded-size budget', () {
    for (final (width, height) in const [
      (3000, 1000), // legacy wide attachment, 12 MB at source size
      (1000, 3000), // legacy tall attachment
      (1024, 768), // current picker maximum
      (120, 80), // smaller than the box: never upscaled
    ]) {
      testWidgets('thumbnail decodes within its box (${width}x$height)',
          (tester) async {
        final cache = PaintingBinding.instance.imageCache;
        await openEditor(tester, _note(_jpeg(width, height)));
        final thumbnail = _thumbnail(tester, _images);
        await _decoded(tester, thumbnail);
        // Box: the screen width by 220 logical pixels, in physical pixels
        // (openEditor uses a 390 x 844 view at 1x).
        final boxWidth = tester.view.physicalSize.width.ceil();
        final boxHeight = (220 * tester.view.devicePixelRatio).ceil();
        final scale = [boxWidth / width, boxHeight / height, 1.0]
            .reduce((a, b) => a < b ? a : b);
        final expectedWidth = (width * scale).round();
        final expectedHeight = (height * scale).round();
        expect(cache.currentSize, 1);
        expect(cache.currentSizeBytes,
            closeTo(expectedWidth * expectedHeight * 4, expectedWidth * 8 + 8),
            reason: 'source would be ${width * height * 4} bytes');
      });
    }

    testWidgets('closing the viewer releases its full-size decode only',
        (tester) async {
      final cache = PaintingBinding.instance.imageCache;
      _plainView(tester);
      await openEditor(tester, _note(_jpeg(1024, 768)));
      final thumbnail = _thumbnail(tester, _images);
      final thumbnailKey = await _key(thumbnail);
      await _decoded(tester, thumbnail);
      final thumbnailBytes = cache.currentSizeBytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        await _openViewer(tester);
        final full = tester
            .widget<Image>(find.byWidgetPredicate((widget) =>
                widget is Image &&
                widget.semanticLabel == 'Full size note image'))
            .image as MemoryImage;
        await _decoded(tester, full);
        expect(cache.currentSizeBytes, thumbnailBytes + 1024 * 768 * 4,
            reason: 'full quality while the viewer is open');
        await tester.tap(find.byTooltip('Close image'));
        await tester.pumpAndSettle();
        expect(cache.statusForKey(full).untracked, isTrue);
        expect(_status(thumbnailKey).keepAlive, isTrue,
            reason: 'the open editor keeps its thumbnail');
        expect(cache.currentSizeBytes, thumbnailBytes,
            reason: 'repeated views do not accumulate (cycle $cycle)');
      }
    });
  });
}
