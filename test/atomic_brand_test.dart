import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(
  WidgetTester tester, {
  bool reducedMotion = false,
  bool active = true,
  bool secondary = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        devicePixelRatio: 3,
        disableAnimations: reducedMotion,
      ),
      child: TickerMode(
        enabled: active,
        child: DevBehindYouMascot(secondary: secondary),
      ),
    ),
  ),
);

AssetImage _asset(Image image) =>
    (image.image as ResizeImage).imageProvider as AssetImage;

void main() {
  testWidgets('primary worker decodes at display resolution', (tester) async {
    await _open(tester);
    final image = tester.widget<Image>(find.byType(Image));
    expect(_asset(image).assetName, AtomicBrandAssets.worker);
    expect((image.image as ResizeImage).width, 216);
    expect(image.width, 72);
    expect(image.height, 72);
    expect(image.excludeFromSemantics, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  for (final secondary in [false, true]) {
    testWidgets('reduced motion uses a static frame (secondary=$secondary)', (
      tester,
    ) async {
      await _open(tester, reducedMotion: true, secondary: secondary);
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        _asset(image).assetName,
        secondary
            ? AtomicBrandAssets.dotgridStatic
            : AtomicBrandAssets.workerStatic,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('inactive route releases the animated worker', (tester) async {
    await _open(tester);
    expect(
      _asset(tester.widget<Image>(find.byType(Image))).assetName,
      AtomicBrandAssets.worker,
    );
    await _open(tester, active: false);
    expect(
      _asset(tester.widget<Image>(find.byType(Image))).assetName,
      AtomicBrandAssets.workerStatic,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('secondary activity accent uses dotgrid', (tester) async {
    await _open(tester, secondary: true);
    expect(
      _asset(tester.widget<Image>(find.byType(Image))).assetName,
      AtomicBrandAssets.dotgrid,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('logo contrast variant follows its actual background', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(home: AtomicBrandMark(size: 44, onDark: dark)),
      );
      expect(
        _asset(tester.widget<Image>(find.byType(Image))).assetName,
        dark ? AtomicBrandAssets.darkLogo : AtomicBrandAssets.lightLogo,
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
}
