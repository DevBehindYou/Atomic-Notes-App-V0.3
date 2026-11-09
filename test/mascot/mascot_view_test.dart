import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/mascot/mascot_asset_resolver.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_frame_source.dart';
import 'package:atomic_notes/mascot/mascot_view.dart';

class Resolver implements MascotAssetResolver {
  @override
  Future<MascotAssetLease> openVerifiedClip(MascotClip clip) async =>
      throw StateError('unused');
}

class Source implements MascotFrameSource {
  int opens = 0;
  @override
  Future<MascotFrameSession> open(MascotClip clip, int pixels) async {
    opens++;
    throw StateError('bad');
  }
}

class _ControlledFrames implements MascotFrameSource, MascotFrameSession {
  Completer<OwnedMascotFrame> _pending = Completer<OwnedMascotFrame>();

  @override
  int get frameCount => 2;

  @override
  Future<MascotFrameSession> open(MascotClip clip, int pixels) async => this;

  @override
  Future<OwnedMascotFrame> nextFrame() => _pending.future;

  OwnedMascotFrame publish(Duration duration) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final frame = OwnedMascotFrame(picture.toImageSync(1, 1), duration);
    picture.dispose();
    final pending = _pending;
    _pending = Completer<OwnedMascotFrame>();
    pending.complete(frame);
    return frame;
  }

  @override
  Future<void> close() async {}
}

class _RecoveringSource implements MascotFrameSource {
  final frames = _ControlledFrames();
  bool failing = true;

  @override
  Future<MascotFrameSession> open(MascotClip clip, int pixels) async {
    if (failing) throw StateError("synthetic decode failure");
    return frames;
  }
}

void main() {
  testWidgets("retry restores artwork after a decode failure", (tester) async {
    final source = _RecoveringSource();
    await tester.pumpWidget(MaterialApp(
        home: MascotView(
            mascot: MascotCatalog.defaultMascot,
            resolver: Resolver(),
            frameSource: source)));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byType(TextButton), findsOneWidget);
    source.failing = false;
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    await tester.pump();
    expect(find.text("Loading mascot"), findsOneWidget);
    final frame = source.frames.publish(Duration.zero);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image,
        same(frame.image));
    expect(find.byType(FocusableActionDetector), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(frame.isDisposed, isTrue);
  });

  testWidgets("replacing a failed player subscribes to the new frame source",
      (tester) async {
    final resolver = Resolver();
    Widget stableView(MascotFrameSource source) => MaterialApp(
        home: MascotView(
            mascot: MascotCatalog.defaultMascot,
            resolver: resolver,
            frameSource: source));
    await tester.pumpWidget(stableView(Source()));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byType(TextButton), findsOneWidget);
    final replacement = _ControlledFrames();
    await tester.pumpWidget(stableView(replacement));
    await tester.pump();
    expect(find.text("Loading mascot"), findsOneWidget);
    final frame = replacement.publish(Duration.zero);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image,
        same(frame.image));
    await tester.pumpWidget(const SizedBox());
    expect(frame.isDisposed, isTrue);
  });

  testWidgets('decoded frames update only the artwork', (tester) async {
    final source = _ControlledFrames();
    await tester.pumpWidget(MaterialApp(
        home: MascotView(
            mascot: MascotCatalog.defaultMascot,
            resolver: Resolver(),
            frameSource: source)));
    expect(find.text('Loading mascot'), findsOneWidget);
    final focus = find.descendant(
        of: find.byType(MascotView),
        matching: find.byType(FocusableActionDetector));
    final semantics =
        find.ancestor(of: focus, matching: find.byType(Semantics)).first;
    final gesture =
        find.descendant(of: focus, matching: find.byType(GestureDetector));
    final originalFocus = tester.widget(focus);
    final originalSemantics = tester.widget(semantics);
    final originalGesture = tester.widget(gesture);

    const frameDuration = Duration(milliseconds: 40);
    final first = source.publish(frameDuration);
    await tester.pump();
    final artwork = find.byType(RawImage);
    expect(tester.widget<RawImage>(artwork).image, same(first.image));

    await tester.pump(frameDuration);
    final second = source.publish(Duration.zero);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<RawImage>(artwork).image, same(second.image));
    expect(first.isDisposed, isTrue);
    expect(tester.widget(focus), same(originalFocus));
    expect(tester.widget(semantics), same(originalSemantics));
    expect(tester.widget(gesture), same(originalGesture));

    await tester.pumpWidget(const SizedBox());
    expect(second.isDisposed, isTrue);
  });

  testWidgets('failed artwork retains status activation on retry',
      (tester) async {
    var activations = 0;
    await tester.pumpWidget(MaterialApp(
        home: MascotView(
            mascot: MascotCatalog.defaultMascot,
            resolver: Resolver(),
            frameSource: Source(),
            semanticActionLabel: 'show sync status and change animation',
            onAdvance: () => activations++)));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byType(TextButton), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    expect(activations, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'hidden route performs no decode; keyboard and tap have same action and 48 target',
      (tester) async {
    final s = Source();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MascotView(
                mascot: MascotCatalog.defaultMascot,
                resolver: Resolver(),
                frameSource: s,
                size: 24,
                routeVisible: false,
                semanticActionLabel: 'show sync status and change animation',
                onAdvance: () => taps++))));
    await tester.pump();
    expect(s.opens, 0);
    final target = find.byType(GestureDetector);
    expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
    await tester.tap(target);
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(taps, 3);
    tester.semantics.tap(find.semantics.byLabel(
        '${MascotCatalog.defaultMascot.displayName}, show sync status and change animation'));
    expect(taps, 4);
    await tester.pumpWidget(const SizedBox());
  });
}
