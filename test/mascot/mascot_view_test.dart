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

void main() {
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
