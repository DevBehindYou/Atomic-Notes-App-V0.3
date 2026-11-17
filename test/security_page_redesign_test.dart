// Security on lib/ui components (screens spec, Security): the app lock and
// screen privacy switch rows and the requirements banner, over a fake
// 'authBox', a fake device check and a mocked screen channel. No Hive files,
// biometrics or platform code.

import 'dart:async';

import 'package:atomic_notes/page/endpage/bio_auth_page.dart';
import 'package:atomic_notes/security/screen_security.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/controls/atomic_switch.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:local_auth/local_auth.dart';

/// What happened, in order, across the device check, the screen channel and
/// the box.
final List<String> _events = [];

/// The 'authBox', with an optional failure on writes.
class _AuthBox implements Box<bool> {
  final Map<String, bool> stored = {};
  Object? failure;
  int puts = 0;

  @override
  bool? get(dynamic key, {bool? defaultValue}) => stored[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, bool value) async {
    puts++;
    _events.add('put $key=$value');
    final failure = this.failure;
    if (failure != null) throw failure;
    stored[key as String] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The device check: whether the device is supported, and the answer to the
/// prompt, with an optional failure or a gate.
class _Auth implements LocalAuthentication {
  bool supported = true;
  bool answer = true;
  PlatformException? failure;
  Completer<void>? gate;
  final List<Invocation> prompts = [];

  @override
  Future<bool> isDeviceSupported() async => supported;

  Future<bool> _authenticate(Invocation invocation) async {
    prompts.add(invocation);
    _events.add('authenticate');
    await gate?.future;
    final failure = this.failure;
    if (failure != null) throw failure;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #authenticate) {
      return _authenticate(invocation);
    }
    return super.noSuchMethod(invocation);
  }
}

const MethodChannel _screenChannel = MethodChannel('com.notes.atomic/screen');

/// How the mocked screen channel answers.
enum _Screen { applies, fails, missing }

final Finder _biometric = find.byKey(const ValueKey('security-biometric'));
final Finder _screenshots = find.byKey(const ValueKey('security-screenshots'));

AtomicSwitchTrack _track(WidgetTester tester, Finder row) =>
    tester.widget<AtomicSwitchTrack>(
        find.descendant(of: row, matching: find.byType(AtomicSwitchTrack)));

Future<void> _settleSnackBar(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(seconds: 4));

void main() {
  late _AuthBox box;
  late _Auth auth;
  late _Screen screen;
  Completer<void>? screenGate;

  setUp(() {
    _events.clear();
    box = _AuthBox();
    auth = _Auth();
    screen = _Screen.applies;
    screenGate = null;
  });

  Future<void> pump(
    WidgetTester tester, {
    ThemeData? theme,
    double width = 412,
    double height = 915,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
    bool disableAnimations = false,
    Future<Box<bool>> Function()? openAuthBox,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_screenChannel, (call) async {
      _events.add('${call.method} ${call.arguments}');
      await screenGate?.future;
      switch (screen) {
        case _Screen.applies:
          return null;
        case _Screen.fails:
          throw PlatformException(code: 'unavailable');
        case _Screen.missing:
          // Answered as "no implementation on this platform".
          throw MissingPluginException();
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_screenChannel, null));
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? AtomicTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: BiomPage(auth: auth, openAuthBox: openAuthBox ?? () async => box),
    ));
    await tester.pumpAndSettle();
  }

  group('biometric unlock', () {
    testWidgets('shows what is stored, with the supported caption',
        (tester) async {
      box.stored['isAuthOn'] = true;
      await pump(tester);

      expect(_track(tester, _biometric).value, isTrue);
      expect(_track(tester, _biometric).enabled, isTrue);
      expect(find.text(BiomPage.biometricCaption), findsOneWidget);
      expect(find.text(BiomPage.biometricUnsupported), findsNothing);
    });

    testWidgets('a tap anywhere on the row checks the device, then stores on',
        (tester) async {
      await pump(tester);
      expect(_track(tester, _biometric).value, isFalse);

      await tester.tap(find.text(BiomPage.biometricCaption));
      await tester.pumpAndSettle();

      // The device check comes first, with today's prompt and options.
      expect(_events, ['authenticate', 'put isAuthOn=true']);
      final prompt = auth.prompts.single;
      expect(prompt.namedArguments[#localizedReason],
          'Checking Device Capability');
      final options = prompt.namedArguments[#options] as AuthenticationOptions;
      expect(options.stickyAuth, isTrue);
      expect(options.biometricOnly, isFalse);
      expect(box.stored['isAuthOn'], isTrue);
      expect(_track(tester, _biometric).value, isTrue);
      expect(find.text('Biometric unlock on'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('stored on, a passed check turns it off', (tester) async {
      box.stored['isAuthOn'] = true;
      await pump(tester);

      await tester.tap(_biometric);
      await tester.pumpAndSettle();

      expect(_events, ['authenticate', 'put isAuthOn=false']);
      expect(box.stored['isAuthOn'], isFalse);
      expect(_track(tester, _biometric).value, isFalse);
      expect(find.text('Biometric unlock off'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a declined check changes nothing', (tester) async {
      auth.answer = false;
      await pump(tester);

      await tester.tap(_biometric);
      await tester.pumpAndSettle();

      expect(_events, ['authenticate']);
      expect(box.puts, 0);
      expect(_track(tester, _biometric).value, isFalse);
      expect(find.text('Biometric unlock on'), findsNothing);
      // The switch is usable again.
      expect(_track(tester, _biometric).enabled, isTrue);
    });

    testWidgets('a failed check says so and changes nothing', (tester) async {
      auth.failure = PlatformException(code: 'NotAvailable');
      await pump(tester);

      await tester.tap(_biometric);
      await tester.pumpAndSettle();

      expect(box.puts, 0);
      expect(_track(tester, _biometric).value, isFalse);
      expect(
          find.text(
              "Couldn't run the biometric check. See the requirements below."),
          findsOneWidget);
      expect(_track(tester, _biometric).enabled, isTrue);
      await _settleSnackBar(tester);
    });

    testWidgets('a failed write shows what is stored and says so',
        (tester) async {
      box.failure = StateError('disk full');
      await pump(tester);

      await tester.tap(_biometric);
      await tester.pumpAndSettle();

      expect(_events, ['authenticate', 'put isAuthOn=true']);
      expect(box.stored['isAuthOn'], isNull);
      expect(_track(tester, _biometric).value, isFalse);
      expect(find.text("Couldn't change biometric unlock. Try again."),
          findsOneWidget);
      expect(find.text('Biometric unlock on'), findsNothing);
      expect(_track(tester, _biometric).enabled, isTrue);
      await _settleSnackBar(tester);
    });

    testWidgets('without device support the switch is off and inert',
        (tester) async {
      auth.supported = false;
      await pump(tester);

      expect(find.text(BiomPage.biometricUnsupported), findsOneWidget);
      expect(find.text(BiomPage.biometricCaption), findsNothing);
      expect(_track(tester, _biometric).enabled, isFalse);

      await tester.tap(_biometric, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(auth.prompts, isEmpty);
      expect(box.puts, 0);
      // The other switch still works.
      expect(_track(tester, _screenshots).enabled, isTrue);
    });

    testWidgets('taps wait while the device check is open', (tester) async {
      auth.gate = Completer<void>();
      await pump(tester);

      await tester.tap(_biometric);
      await tester.pump();
      expect(_track(tester, _biometric).enabled, isFalse);
      await tester.tap(_biometric, warnIfMissed: false);
      await tester.pump();
      expect(auth.prompts, hasLength(1));

      auth.gate!.complete();
      await tester.pumpAndSettle();
      expect(auth.prompts, hasLength(1));
      expect(box.puts, 1);
      expect(_track(tester, _biometric).value, isTrue);
      expect(_track(tester, _biometric).enabled, isTrue);
      await _settleSnackBar(tester);
    });
  });

  group('block screenshots', () {
    testWidgets('shows what is stored', (tester) async {
      box.stored[ScreenSecurity.prefKey] = true;
      await pump(tester);

      expect(_track(tester, _screenshots).value, isTrue);
      expect(find.text(BiomPage.screenshotCaption), findsOneWidget);
    });

    testWidgets('a tap applies the block, then stores it', (tester) async {
      await pump(tester);

      await tester.tap(find.text(BiomPage.screenshotCaption));
      await tester.pumpAndSettle();

      expect(_events, ['setSecure {secure: true}', 'put noScreenshot=true']);
      expect(box.stored[ScreenSecurity.prefKey], isTrue);
      expect(_track(tester, _screenshots).value, isTrue);
      expect(find.text('Screenshots blocked'), findsOneWidget);
      expect(auth.prompts, isEmpty);
      await _settleSnackBar(tester);
    });

    testWidgets('stored on, a tap allows them again', (tester) async {
      box.stored[ScreenSecurity.prefKey] = true;
      await pump(tester);

      await tester.tap(_screenshots);
      await tester.pumpAndSettle();

      expect(_events, ['setSecure {secure: false}', 'put noScreenshot=false']);
      expect(box.stored[ScreenSecurity.prefKey], isFalse);
      expect(_track(tester, _screenshots).value, isFalse);
      expect(find.text('Screenshots allowed'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    for (final kind in [_Screen.fails, _Screen.missing]) {
      testWidgets('a device that cannot block (${kind.name}) stores nothing',
          (tester) async {
        screen = kind;
        await pump(tester);

        await tester.tap(_screenshots);
        await tester.pumpAndSettle();

        expect(box.puts, 0);
        expect(_track(tester, _screenshots).value, isFalse);
        expect(
            find.text("This device can't block screenshots"), findsOneWidget);
        expect(find.text('Screenshots blocked'), findsNothing);
        expect(_track(tester, _screenshots).enabled, isTrue);
        await _settleSnackBar(tester);
      });
    }

    testWidgets('a failed write shows what is stored and says so',
        (tester) async {
      box.failure = StateError('disk full');
      await pump(tester);

      await tester.tap(_screenshots);
      await tester.pumpAndSettle();

      expect(_events, ['setSecure {secure: true}', 'put noScreenshot=true']);
      expect(_track(tester, _screenshots).value, isFalse);
      expect(find.text("Couldn't save the screenshot setting. Try again."),
          findsOneWidget);
      expect(find.text('Screenshots blocked'), findsNothing);
      expect(_track(tester, _screenshots).enabled, isTrue);
      await _settleSnackBar(tester);
    });

    testWidgets('taps wait while the block is being applied', (tester) async {
      screenGate = Completer<void>();
      await pump(tester);

      await tester.tap(_screenshots);
      await tester.pump();
      expect(_track(tester, _screenshots).enabled, isFalse);
      await tester.tap(_screenshots, warnIfMissed: false);
      await tester.pump();
      expect(_events, ['setSecure {secure: true}']);

      screenGate!.complete();
      await tester.pumpAndSettle();
      expect(_events, ['setSecure {secure: true}', 'put noScreenshot=true']);
      expect(_track(tester, _screenshots).value, isTrue);
      expect(_track(tester, _screenshots).enabled, isTrue);
      await _settleSnackBar(tester);
    });
  });

  group('page', () {
    testWidgets('both switches wait for the stored choices', (tester) async {
      final opening = Completer<Box<bool>>();
      box.stored['isAuthOn'] = true;
      await pump(tester, openAuthBox: () => opening.future);

      expect(_track(tester, _biometric).enabled, isFalse);
      expect(_track(tester, _screenshots).enabled, isFalse);
      await tester.tap(_biometric, warnIfMissed: false);
      await tester.tap(_screenshots, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_events, isEmpty);

      opening.complete(box);
      await tester.pumpAndSettle();
      expect(_track(tester, _biometric).value, isTrue);
      expect(_track(tester, _biometric).enabled, isTrue);
      expect(_track(tester, _screenshots).enabled, isTrue);
    });

    testWidgets('groups and the requirements banner replace the old modules',
        (tester) async {
      await pump(tester);

      expect(find.text('App lock'), findsOneWidget);
      expect(find.text('Screen privacy'), findsOneWidget);
      expect(find.text(BiomPage.requirementsTitle), findsOneWidget);
      expect(find.text(BiomPage.requirementsBody), findsOneWidget);
      // The status pills and upper-case labels are gone; the switches carry
      // the state.
      for (final old in [
        'DEVICE LOCK',
        'SCREEN PRIVACY',
        'REQUIREMENTS',
        'ARMED',
        'OFF',
        'BLOCKED',
        'ALLOWED',
        'No screenshots',
      ]) {
        expect(find.text(old), findsNothing, reason: old);
      }
    });

    testWidgets('the back button leaves the page', (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AtomicTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) =>
                        BiomPage(auth: auth, openAuthBox: () async => box))),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(BiomPage.biometricCaption), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('the header shows the title once the large one scrolls away',
        (tester) async {
      await pump(tester, height: 480, textScale: 2);

      AtomicPageHeader header() =>
          tester.widget<AtomicPageHeader>(find.byType(AtomicPageHeader));
      expect(header().showTitle, isFalse);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(header().showTitle, isTrue);
    });

    for (final (name, theme) in [
      ('light', AtomicTheme.light),
      ('dark', AtomicTheme.dark),
    ]) {
      for (final direction in TextDirection.values) {
        for (final supported in [true, false]) {
          testWidgets(
              'fits 320 dp at 2.0 text ($name, ${direction.name}, '
              '${supported ? 'supported, on' : 'unsupported, off'})',
              (tester) async {
            auth.supported = supported;
            box.stored['isAuthOn'] = supported;
            box.stored[ScreenSecurity.prefKey] = supported;
            await pump(tester,
                theme: theme,
                width: 320,
                height: 640,
                textScale: 2,
                direction: direction);
            expect(tester.takeException(), isNull);
            for (var i = 0; i < 8; i++) {
              await tester.drag(find.byType(ListView), const Offset(0, -400));
              await tester.pump();
            }
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text(BiomPage.screenshotCaption), findsOneWidget);
          });
        }
      }
    }

    testWidgets('targets are at least 48 dp', (tester) async {
      await pump(tester);

      for (final finder in [_biometric, _screenshots, find.byTooltip('Back')]) {
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
      }
    });

    testWidgets('screen readers hear one toggle per row with its meaning',
        (tester) async {
      final semantics = tester.ensureSemantics();
      box.stored['isAuthOn'] = true;
      await pump(tester);

      const biometric =
          '${BiomPage.biometricTitle}. ${BiomPage.biometricCaption}';
      const screenshots =
          '${BiomPage.screenshotTitle}. ${BiomPage.screenshotCaption}';
      expect(find.bySemanticsLabel(biometric), findsOneWidget);
      expect(
          tester.getSemantics(find.bySemanticsLabel(biometric)),
          isSemantics(
              label: biometric,
              isButton: false,
              hasEnabledState: true,
              isEnabled: true,
              hasToggledState: true,
              isToggled: true,
              hasTapAction: true));
      expect(find.bySemanticsLabel(screenshots), findsOneWidget);
      expect(
          tester.getSemantics(find.bySemanticsLabel(screenshots)),
          isSemantics(
              label: screenshots,
              isButton: false,
              hasEnabledState: true,
              isEnabled: true,
              hasToggledState: true,
              isToggled: false,
              hasTapAction: true));
      // Captions are not read a second time on their own.
      expect(find.bySemanticsLabel(BiomPage.biometricCaption), findsNothing);
      expect(find.bySemanticsLabel(BiomPage.screenshotCaption), findsNothing);
      semantics.dispose();
    });

    testWidgets('screen readers hear an unsupported switch as unavailable',
        (tester) async {
      final semantics = tester.ensureSemantics();
      auth.supported = false;
      await pump(tester);

      const label =
          '${BiomPage.biometricTitle}. ${BiomPage.biometricUnsupported}';
      expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(
              label: label,
              isButton: false,
              hasEnabledState: true,
              isEnabled: false,
              hasToggledState: true,
              isToggled: false,
              hasTapAction: false));
      semantics.dispose();
    });

    testWidgets('reduced motion shows everything at once', (tester) async {
      await pump(tester, disableAnimations: true);
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(MaterialApp(
        theme: AtomicTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: BiomPage(
            key: const ValueKey('fresh'),
            auth: auth,
            openAuthBox: () async => box),
      ));
      await tester.pump();
      for (final fade in tester.widgetList<FadeTransition>(find.ancestor(
          of: find.text(BiomPage.screenshotCaption),
          matching: find.byType(FadeTransition)))) {
        expect(fade.opacity.value, 1);
      }
    });

    testWidgets('without reduced motion the blocks rise in', (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: AtomicTheme.light,
          home: BiomPage(auth: auth, openAuthBox: () async => box)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      Iterable<double> fades() => tester
          .widgetList<FadeTransition>(find.ancestor(
              of: find.text(BiomPage.screenshotCaption),
              matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value);
      expect(fades().any((v) => v < 1), isTrue);
      await tester.pumpAndSettle();
      expect(fades().every((v) => v == 1), isTrue);
    });
  });
}
