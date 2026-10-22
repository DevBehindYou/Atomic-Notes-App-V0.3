import 'dart:ui' as ui;
import 'package:atomic_notes/utility/component/atomic_splash_mark.dart';
import 'package:atomic_notes/utility/component/logo_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> open(WidgetTester tester,
    {Brightness brightness = Brightness.light,
    bool reducedMotion = false,
    bool active = true}) async {
  await tester.pumpWidget(MaterialApp(
    themeAnimationDuration: Duration.zero,
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data:
          MediaQueryData(devicePixelRatio: 4, disableAnimations: reducedMotion),
      child: TickerMode(
        enabled: active,
        child: const AtomicSplashMark(size: 144),
      ),
    ),
  ));
}

String asset(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  final resized = image.image as ResizeImage;
  expect(resized.width, 480); // Bound the decode even on high-density displays.
  return (resized.imageProvider as AssetImage).assetName;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final display = FontLoader('BebasNeue')
      ..addFont(rootBundle.load('assets/fonts/BebasNeue-Regular.ttf'));
    await display.load();
  });
  test('bundled static fallbacks exactly match the supplied GIF first frames',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final pair in [
      [AtomicSplashAssets.lightAnimation, AtomicSplashAssets.lightStill],
      [AtomicSplashAssets.darkAnimation, AtomicSplashAssets.darkStill],
    ]) {
      final gif = await rootBundle.load(pair[0]);
      final png = await rootBundle.load(pair[1]);
      final animation =
          await ui.instantiateImageCodec(gif.buffer.asUint8List());
      final still = await ui.instantiateImageCodec(png.buffer.asUint8List());
      try {
        expect(animation.frameCount, 100);
        final first = await animation.getNextFrame();
        final static = await still.getNextFrame();
        try {
          expect(first.image.width, 480);
          expect(first.image.height, 480);
          expect(await static.image.toByteData(), isNotNull);
          final sourcePixels = await first.image.toByteData();
          final stillPixels = await static.image.toByteData();
          expect(stillPixels!.buffer.asUint8List(),
              sourcePixels!.buffer.asUint8List());
        } finally {
          first.image.dispose();
          static.image.dispose();
        }
      } finally {
        animation.dispose();
        still.dispose();
      }
    }
  });

  testWidgets('uses the supplied animation matching actual theme brightness',
      (tester) async {
    for (final brightness in Brightness.values) {
      await open(tester, brightness: brightness);
      expect(
          asset(tester),
          brightness == Brightness.dark
              ? AtomicSplashAssets.darkAnimation
              : AtomicSplashAssets.lightAnimation);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion uses a still Atomic first frame in both themes',
      (tester) async {
    for (final brightness in Brightness.values) {
      await open(tester, brightness: brightness, reducedMotion: true);
      expect(
          asset(tester),
          brightness == Brightness.dark
              ? AtomicSplashAssets.darkStill
              : AtomicSplashAssets.lightStill);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inactive ticker removes the animated image listener',
      (tester) async {
    await open(tester, active: false);
    expect(asset(tester), AtomicSplashAssets.lightStill);
    await open(tester);
    expect(asset(tester), AtomicSplashAssets.lightAnimation);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background lifecycle stops playback and resume restores it',
      (tester) async {
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(asset(tester), AtomicSplashAssets.lightStill);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(asset(tester), AtomicSplashAssets.lightAnimation);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a covered route keeps only the still first frame',
      (tester) async {
    final navigation = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigation,
      home: const Scaffold(body: AtomicSplashMark()),
    ));
    navigation.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Next screen')),
    ));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image, skipOffstage: false));
    final source = (image.image as ResizeImage).imageProvider as AssetImage;
    expect(source.assetName, AtomicSplashAssets.lightStill);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('animated mark fits the existing lockup on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: LogoContainer(mark: AtomicSplashMark())),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(AtomicSplashMark), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
