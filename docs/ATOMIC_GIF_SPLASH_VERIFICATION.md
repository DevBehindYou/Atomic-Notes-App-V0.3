# Supplied Atomic icon GIF on the Flutter splash

The Flutter splash uses the supplied rotating Atomic icon rather than a still
mark. The transparent light/dark GIF companions are retained byte-for-byte and
selected from actual theme brightness. Both are 480 by 480, 100 frames, with a
four-second loop. Light is 767,386 bytes; dark is 1,153,531 bytes. No mascot art,
native launcher or splash resource is changed.

`AtomicSplashMark` streams the existing asset through Flutter's image codec,
with a decode width bounded to 480 pixels. It never preloads all frames or
downloads artwork. Reduced motion, an inactive route/ticker, or backgrounded app
lifecycle selects a PNG containing exactly the corresponding GIF's first frame.
Changing to the still image removes the animated stream listener and stops frame
scheduling. Disposal removes the lifecycle observer. A decode failure falls back
to the existing static Atomic logo without blocking startup.

The optional `LogoContainer.mark` slot leaves every other screen's static mark
unchanged. Only the Flutter splash requests the animated mark. Its background
uses the actual theme scaffold color. The authentication/cache/security routing
and existing 900ms/one-second waits are unchanged; there is no forced four-second
animation wait. Android's OS-owned initial splash remains a static vector with
its existing day/night qualifiers. Animated GIF playback begins in Flutter.

Verification:

```text
python tool/prepare_atomic_splash.py --verify-only
flutter test --no-pub test/atomic_splash_mark_test.dart test/splash_route_resolver_test.dart
flutter analyze --no-pub lib/utility/component/atomic_splash_mark.dart lib/utility/component/logo_container.dart lib/page/splash_screen.dart test/atomic_splash_mark_test.dart
```

The preparation tool pins both supplied GIF SHA-256 hashes and checks decoded
first-frame equality. The Flutter tests independently decode both bundled GIFs
and PNGs and compare RGBA bytes, then cover theme selection, reduced motion,
lifecycle, covered routes, inactive tickers and the narrow-phone lockup. Existing
route resolver tests exercise all startup security gates. Full CI and actual
device launch appearance remain separate acceptance gates.
