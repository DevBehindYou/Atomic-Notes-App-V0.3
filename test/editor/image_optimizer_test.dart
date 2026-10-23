import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/editor/image_optimizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

String _jpeg(int width, int height) {
  final pixels = image.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      pixels.setPixelRgb(
          x, y, (x ~/ 8) % 256, (y ~/ 8) % 256, ((x + y) ~/ 16) % 256);
    }
  }
  return base64Encode(image.encodeJpg(pixels, quality: 60));
}

Future<void> _show(
  WidgetTester tester,
  String source, {
  int maxBytes = 60 * 1024,
  String? Function(String)? validate,
  Future<ImageOptimizationResult> Function(ImageOptimizationRequest)? optimizer,
  void Function(String?)? onClosed,
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                  onPressed: () async {
                    final result = await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => NoteImageOptimizer(
                            sourceBase64: source,
                            maxBytes: maxBytes,
                            validate: validate,
                            optimizer: optimizer ??
                                (request) async => optimizeNoteImage(request)));
                    onClosed?.call(result);
                  },
                  child: const Text('Optimize'))))));
  await tester.tap(find.text('Optimize'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _chooseSize(WidgetTester tester, String size) async {
  final control = find.byKey(const ValueKey('image-max-dimension'));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('$size px').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  late String source;
  setUpAll(() {
    source = _jpeg(1024, 768);
  });
  test('resolution uses selected maximum and never upscales', () {
    final result = optimizeNoteImage(ImageOptimizationRequest(
        sourceBase64: source, quality: 70, maxDimension: 512));
    final decoded = image.decodeJpg(result.bytes)!;
    expect([decoded.width, decoded.height], [512, 384]);
    expect([result.sourceWidth, result.sourceHeight], [1024, 768]);
    expect(decoded.exif.isEmpty, isTrue);
    final small = optimizeNoteImage(ImageOptimizationRequest(
        sourceBase64: _jpeg(32, 24), quality: 70, maxDimension: 1024));
    expect([small.width, small.height], [32, 24]);
  });
  test('quality is honored rather than silently reduced to fit a budget', () {
    final low = optimizeNoteImage(ImageOptimizationRequest(
        sourceBase64: source, quality: 40, maxDimension: 1024));
    final high = optimizeNoteImage(ImageOptimizationRequest(
        sourceBase64: source, quality: 85, maxDimension: 1024));
    expect(high.bytes.length, greaterThan(low.bytes.length));
    expect(high.bytes, isNot(orderedEquals(low.bytes)));
    expect([high.width, high.height], [1024, 768]);
  });
  test('invalid or unsupported input is rejected before pixel decoding', () {
    expect(
        () => optimizeNoteImage(const ImageOptimizationRequest(
            sourceBase64: 'not a JPEG', quality: 70, maxDimension: 512)),
        throwsFormatException);
  });
  testWidgets('Insert returns the selected optimized JPEG', (tester) async {
    String? inserted;
    await _show(tester, source, onClosed: (value) => inserted = value);
    await _chooseSize(tester, '512');
    final insert = find.text('Insert image');
    await tester.ensureVisible(insert);
    await tester.tap(insert);
    await tester.pumpAndSettle();
    expect(inserted, isNotNull);
    final decoded = image.decodeJpg(base64Decode(inserted!))!;
    expect([decoded.width, decoded.height], [512, 384]);
    expect(find.byType(NoteImageOptimizer), findsNothing);
  });
  testWidgets('Cancel returns no attachment', (tester) async {
    String? inserted = 'unchanged';
    await _show(tester, source, onClosed: (value) => inserted = value);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(inserted, isNull);
  });
  testWidgets('raw-byte and full-note limits disable Insert', (tester) async {
    await _show(tester, source, maxBytes: 1);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Insert image'))
            .onPressed,
        isNull);
    expect(find.textContaining('exceeds the image budget'), findsOneWidget);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _show(tester, source, validate: (_) => 'Note sync limit reached');
    expect(find.text('Note sync limit reached'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Insert image'))
            .onPressed,
        isNull);
  });
  testWidgets('outdated compression cannot replace the newest selected size',
      (tester) async {
    final pending = <Completer<ImageOptimizationResult>>[];
    final requests = <ImageOptimizationRequest>[];
    await _show(tester, source, optimizer: (request) {
      requests.add(request);
      final future = Completer<ImageOptimizationResult>();
      pending.add(future);
      return future.future;
    });
    expect(pending, hasLength(1));
    await _chooseSize(tester, '512');
    expect(pending, hasLength(1));
    pending[0].complete(optimizeNoteImage(requests[0]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pending, hasLength(2));
    expect(find.textContaining('Output: 1024'), findsNothing);
    pending[1].complete(optimizeNoteImage(requests[1]));
    await tester.pumpAndSettle();
    expect(find.textContaining('512 × 384'), findsWidgets);
    expect(find.textContaining('Output: 1024'), findsNothing);
  });
  testWidgets('queued settings coalesce with only one compute running',
      (tester) async {
    var active = 0, maxActive = 0;
    final pending = <Completer<ImageOptimizationResult>>[];
    final requests = <ImageOptimizationRequest>[];
    await _show(tester, source, optimizer: (request) {
      requests.add(request);
      final future = Completer<ImageOptimizationResult>();
      pending.add(future);
      active++;
      if (active > maxActive) maxActive = active;
      return future.future.whenComplete(() => active--);
    });
    await _chooseSize(tester, '512');
    final change = tester.widget<Slider>(find.byType(Slider)).onChanged!;
    change(40);
    await tester.pump(const Duration(milliseconds: 200));
    change(85);
    await _chooseSize(tester, '768');
    expect(requests, hasLength(1));
    pending[0].complete(optimizeNoteImage(requests[0]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, hasLength(2));
    expect(requests.last.maxDimension, 768);
    expect(requests.last.quality, 85);
    pending[1].complete(optimizeNoteImage(requests[1]));
    await tester.pumpAndSettle();
    expect(maxActive, 1);
    expect(active, 0);
    expect(find.textContaining('768 × 576'), findsWidgets);
  });
  testWidgets('closed optimizer ignores a late compression result',
      (tester) async {
    final pending = Completer<ImageOptimizationResult>();
    ImageOptimizationRequest? request;
    var calls = 0;
    await _show(tester, source, optimizer: (value) {
      calls++;
      request ??= value;
      return pending.future;
    });
    tester.widget<Slider>(find.byType(Slider)).onChanged!(85);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    pending.complete(optimizeNoteImage(request!));
    await tester.pumpAndSettle();
    expect(find.byType(NoteImageOptimizer), findsNothing);
    expect(calls, 1, reason: 'Closing must discard queued optimization work');
    expect(tester.takeException(), isNull);
  });
  testWidgets('quality changes debounce to the last chosen value',
      (tester) async {
    final requests = <ImageOptimizationRequest>[];
    await _show(tester, source, optimizer: (request) async {
      requests.add(request);
      return optimizeNoteImage(request);
    });
    expect(requests, hasLength(1));
    final change = tester.widget<Slider>(find.byType(Slider)).onChanged!;
    change(40);
    change(85);
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(requests.last.quality, 85);
    expect(find.text('JPEG quality: 85%'), findsOneWidget);
  });
  testWidgets(
      'Insert rechecks a changed full-note budget before returning data',
      (tester) async {
    var allowed = true;
    var closed = false;
    await _show(tester, source,
        validate: (_) => allowed ? null : 'Note changed and no longer has room',
        onClosed: (_) => closed = true);
    allowed = false;
    await tester.ensureVisible(find.text('Insert image'));
    await tester.tap(find.text('Insert image'));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(find.byType(NoteImageOptimizer), findsOneWidget);
    expect(find.text('Note changed and no longer has room'), findsOneWidget);
  });
  testWidgets('320px and large text keep actions reachable without overflow',
      (tester) async {
    await _show(tester, source, size: const Size(320, 640), scale: 2);
    await tester.ensureVisible(find.text('Insert image'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Insert image')).bottom,
        lessThanOrEqualTo(640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Insert image'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteImageOptimizer), findsNothing);
  });
}
