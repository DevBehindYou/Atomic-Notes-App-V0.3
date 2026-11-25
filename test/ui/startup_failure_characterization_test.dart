// Characterization of the startup failure route (UX-08-entry, R48), written
// against the base API only so it runs unchanged before and after
// `StartupFailedApp` moved from main.dart into lib/page. It imports the
// widget through main.dart, so it also proves that entry point still exists.
//
// main() itself cannot be driven from a test (it calls the real services and
// runApp). [_boot] mirrors its non-web body line for line: run the startup
// sequence; on a throw, finish the trace and show StartupFailedApp with the
// error's text; otherwise finish the trace and show the app. The
// MAIN-DART-BOUNDARY receipt shows that body is unchanged.
//
// Every value here is synthetic.

import 'package:atomic_notes/main.dart' show StartupFailedApp;
import 'package:atomic_notes/utility/startup_sequence.dart';
import 'package:atomic_notes/utility/startup_trace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records each call; a step can be made to fail.
class _Services implements StartupServices {
  final calls = <String>[];
  final fail = <String>{};

  Future<void> _run(String name) {
    calls.add(name);
    if (fail.contains(name)) {
      return Future.error(StateError('synthetic $name failure'));
    }
    return Future<void>.value();
  }

  @override
  Future<void> initApi() => _run('api');
  @override
  Future<void> initHive() => _run('hive');
  @override
  Future<void> openBox(String name) => _run('box:$name');
  @override
  bool themeSwitchingEnabled = false;
  @override
  Future<void> initAppearance() => _run('appearance');
  @override
  Future<void> applyScreenSecurity() => _run('screenSecurity');
  @override
  Future<void> initProfile() => _run('profile');
  @override
  Future<void> initSyncStatus() => _run('syncStatus');
  @override
  Future<void> initQuota() => _run('quota');
  @override
  Future<void> initVault() => _run('vault');
  @override
  Future<void> initRepository() => _run('repository');
}

const _order = [
  'api',
  'hive',
  'box:authBox',
  'screenSecurity',
  'profile',
  'box:syncBox',
  'syncStatus',
  'quota',
  'vault',
  'repository',
];

/// Stands in for the app main() runs on success.
class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) => const Directionality(
      textDirection: TextDirection.ltr, child: Text('app'));
}

/// main()'s non-web body, with runApp replaced by [show].
Future<void> _boot(
    StartupServices services, void Function(Widget app) show) async {
  final trace = StartupTrace.fromEnvironment();
  try {
    await runStartupSequence(services, trace);
  } catch (error) {
    trace.finish();
    show(StartupFailedApp(error: error.toString()));
    return;
  }
  trace.finish();
  show(const _App());
}

/// Opens the diagnostics when the screen gates them behind a control. The
/// base screen shows them at once, so there is nothing to open there.
Future<void> _revealDetails(WidgetTester tester) async {
  final details = find.text('Show details');
  if (details.evaluate().isNotEmpty) {
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
  }
}

void _phone(WidgetTester tester,
    {double textScale = 1, Brightness brightness = Brightness.light}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

final _title = RegExp(r"^atomic couldn't start$", caseSensitive: false);

void main() {
  group('startup route', () {
    testWidgets(
        'a fatal step shows the failure screen once, with that error as '
        'the trace, and no later step runs', (tester) async {
      _phone(tester);
      final services = _Services()..fail.add('hive');
      final shown = <Widget>[];
      await _boot(services, shown.add);

      expect(services.calls, ['api', 'hive']);
      expect(shown, hasLength(1));
      expect(shown.single, isA<StartupFailedApp>());

      await tester.pumpWidget(shown.single);
      expect(tester.takeException(), isNull);
      expect(find.textContaining(_title), findsOneWidget);
      expect(find.textContaining('reopen the app'), findsOneWidget);
      await _revealDetails(tester);
      expect(find.text('Bad state: synthetic hive failure'), findsOneWidget);
    });

    test('ordinary startup resolves exactly once, to the app', () async {
      final services = _Services();
      final shown = <Widget>[];
      await _boot(services, shown.add);
      expect(services.calls, _order);
      expect(shown, hasLength(1));
      expect(shown.single, isA<_App>());
    });

    test('a failing API init is not fatal: the app still opens once', () async {
      final services = _Services()..fail.add('api');
      final shown = <Widget>[];
      await _boot(services, shown.add);
      expect(services.calls, _order);
      expect(shown, hasLength(1));
      expect(shown.single, isA<_App>());
    });
  });

  group('startup failure screen', () {
    for (final brightness in Brightness.values) {
      testWidgets(
          'explains itself and keeps the trace reachable at 320 dp and 2.0 '
          'text (${brightness.name} system)', (tester) async {
        _phone(tester, textScale: 2, brightness: brightness);
        await tester.pumpWidget(const StartupFailedApp(
            error: 'synthetic startup failure: a long line that has to wrap '
                'within the narrow screen without overflowing it'));
        expect(tester.takeException(), isNull);
        expect(find.textContaining(_title), findsOneWidget);
        expect(find.textContaining('Check your connection and reopen the app'),
            findsOneWidget);
        await _revealDetails(tester);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('synthetic startup failure: a long line'),
            findsOneWidget);
      });
    }

    testWidgets('builds its own app: no ancestor theme or navigator needed',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(const StartupFailedApp(error: 'synthetic'));
      expect(tester.takeException(), isNull);
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
