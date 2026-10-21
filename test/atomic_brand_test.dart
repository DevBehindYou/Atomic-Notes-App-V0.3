import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_view.dart';
import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> open(WidgetTester tester,
        {bool reducedMotion = false,
        bool active = true,
        bool secondary = false}) =>
    tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(
                devicePixelRatio: 3, disableAnimations: reducedMotion),
            child: TickerMode(
                enabled: active,
                child: DevBehindYouMascot(secondary: secondary)))));
void main() {
  testWidgets('primary mascot uses the supplied offline default',
      (tester) async {
    await open(tester);
    final view = tester.widget<MascotView>(find.byType(MascotView));
    expect(view.mascot.id, MascotCatalog.defaultId);
    expect(view.size, 72);
    expect(view.animationsEnabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  for (final secondary in [false, true]) {
    testWidgets('reduced motion keeps supplied artwork (secondary=$secondary)',
        (tester) async {
      await open(tester, reducedMotion: true, secondary: secondary);
      final view = tester.widget<MascotView>(find.byType(MascotView));
      expect(view.mascot.id, MascotCatalog.defaultId);
      expect(
          MediaQuery.disableAnimationsOf(
              tester.element(find.byType(MascotView))),
          isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('inactive route gates the controlled player', (tester) async {
    await open(tester, active: false);
    expect(TickerMode.valuesOf(tester.element(find.byType(MascotView))).enabled,
        isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('secondary activity accent uses a still supplied character',
      (tester) async {
    await open(tester, secondary: true);
    expect(tester.widget<MascotView>(find.byType(MascotView)).animationsEnabled,
        isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('logo contrast variant follows its actual background',
      (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(
          MaterialApp(home: AtomicBrandMark(size: 44, onDark: dark)));
      final image = tester.widget<Image>(find.byType(Image));
      final asset = (image.image as ResizeImage).imageProvider as AssetImage;
      expect(asset.assetName,
          dark ? AtomicBrandAssets.darkLogo : AtomicBrandAssets.lightLogo);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
