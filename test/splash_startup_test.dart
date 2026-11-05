import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/page/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class Startup extends SplashStartupServices {
  Startup({this.signedIn = true});
  bool signedIn;
  @override
  int sessionRevision = 0;
  final vaultReady = Completer<void>();
  final notesReady = Completer<void>();
  final stopReady = Completer<void>();
  final onboardingSaved = Completer<void>();
  bool foreignCache = false;
  bool locked = false;
  bool armed = false;
  int vaultReads = 0, notesStarts = 0, serviceStarts = 0, memoryClears = 0;
  int onboardingWrites = 0;
  @override
  bool get isSignedIn => signedIn;
  @override
  bool get hasForeignPendingCache => foreignCache;
  @override
  bool get vaultLocked => locked;
  @override
  bool get twoFactorArmed => armed;
  @override
  Future<void> initVault() {
    vaultReads++;
    return vaultReady.future;
  }

  @override
  Future<void> startNotes() {
    notesStarts++;
    return notesReady.future;
  }

  @override
  Future<void> stopNotes() => stopReady.future;
  @override
  void clearNotesMemory() {
    memoryClears++;
  }

  @override
  Future<void> markOnboardingSeen(Box<bool> authBox) {
    onboardingWrites++;
    return onboardingSaved.future;
  }

  @override
  void startAccountServices() {
    serviceStarts++;
  }
}

void main() {
  late Directory directory;
  late Box<bool> auth;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-splash-route-');
    Hive.init(directory.path);
    auth = await Hive.openBox<bool>('authBox');
    await auth.put('hasSeenOnboarding', false);
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester, Startup startup) async {
    await tester.pumpWidget(MaterialApp(
      home: SplashPage.forTest(startup: startup),
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        transitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) =>
            Scaffold(body: Text('Ready ${settings.name}')),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
      'signed-out startup routes after local auth read without a timed splash hold',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: const SplashPage(),
      routes: {'/loginpage': (_) => const Scaffold(body: Text('Login ready'))},
    ));
    // No Duration advance: a cosmetic delay would keep this offstage.
    await tester.pump();
    await tester.pump();
    expect(find.text('Login ready'), findsOneWidget);
    expect(auth.get('hasSeenOnboarding'), false);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'vault readiness controls routing; background notes never hold it',
      (tester) async {
    final startup = Startup()..locked = true;
    await open(tester, startup);
    expect(startup.vaultReads, 1);
    expect(find.text('Ready /vaultunlock'), findsNothing);
    expect(startup.notesStarts, 0);
    startup.vaultReady.complete();
    await flush(tester);
    final vaultRoute = find.text('Ready /vaultunlock');
    expect(vaultRoute, findsOneWidget);
    expect(ModalRoute.of(tester.element(vaultRoute))?.settings.arguments, true);
    expect(startup.notesStarts, 1);
    expect(startup.notesReady.isCompleted, false);
    expect(startup.serviceStarts, 1);
    expect(auth.get('hasSeenOnboarding'), false);
    await tester.pumpWidget(const SizedBox());
    startup.notesReady.complete();
  });
  testWidgets(
      'device lock and two-factor retain priority after vault readiness',
      (tester) async {
    for (final deviceLock in [true, false]) {
      await tester.runAsync(() => auth.put('isAuthOn', deviceLock));
      final startup = Startup()
        ..locked = true
        ..armed = true;
      await open(tester, startup);
      startup.vaultReady.complete();
      await flush(tester);
      expect(
          find.text('Ready ${deviceLock ? '/lockscreen' : '/twofactorgate'}'),
          findsOneWidget);
      expect(auth.get('hasSeenOnboarding'), false);
      await tester.pumpWidget(const SizedBox());
      startup.notesReady.complete();
    }
  });
  testWidgets('foreign pending cache recovers before vault or notes start',
      (tester) async {
    final startup = Startup()..foreignCache = true;
    await open(tester, startup);
    expect(startup.vaultReads, 0);
    expect(find.text('Ready /account-cache-recovery'), findsNothing);
    startup.stopReady.complete();
    await flush(tester);
    expect(find.text('Ready /account-cache-recovery'), findsOneWidget);
    expect(startup.memoryClears, 1);
    expect(startup.notesStarts, 0);
  });
  testWidgets('cache becoming foreign during vault refresh cannot reach notes',
      (tester) async {
    final startup = Startup();
    await open(tester, startup);
    startup.foreignCache = true;
    startup.vaultReady.complete();
    await flush(tester);
    expect(find.text('Ready /account-cache-recovery'), findsOneWidget);
    expect(find.text('Ready /onboardingscreen'), findsNothing);
    expect(auth.get('hasSeenOnboarding'), false);
    expect(startup.notesStarts, 0);
    expect(startup.serviceStarts, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'disposed splash does not start account work after vault readiness',
      (tester) async {
    final startup = Startup();
    await open(tester, startup);
    await tester.pumpWidget(const SizedBox());
    startup.vaultReady.complete();
    await flush(tester);
    expect(startup.notesStarts, 0);
    expect(startup.serviceStarts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'session expiry during vault init routes to login without account work',
      (tester) async {
    final startup = Startup()..locked = true;
    await open(tester, startup);
    expect(startup.vaultReads, 1);
    startup.signedIn = false;
    startup.sessionRevision++;
    startup.vaultReady.complete();
    await flush(tester);
    expect(find.text('Ready /loginpage'), findsOneWidget);
    expect(find.text('Ready /vaultunlock'), findsNothing);
    expect(startup.notesStarts, 0);
    expect(startup.serviceStarts, 0);
    expect(startup.onboardingWrites, 0);
  });

  testWidgets('replacement session during onboarding starts fresh gate checks',
      (tester) async {
    final startup = Startup();
    await open(tester, startup);
    startup.vaultReady.complete();
    await flush(tester);
    expect(startup.onboardingWrites, 1);
    startup.sessionRevision++;
    startup.notesReady.completeError(ForeignPendingCacheError());
    await flush(tester);
    expect(find.text('Ready /account-cache-recovery'), findsNothing);
    startup.onboardingSaved.complete();
    await flush(tester);
    expect(find.text('Ready /splashpage'), findsOneWidget);
    expect(find.text('Ready /onboardingscreen'), findsNothing);
  });

  testWidgets('expired session during cache stop routes to login',
      (tester) async {
    final startup = Startup()..foreignCache = true;
    await open(tester, startup);
    startup.signedIn = false;
    startup.sessionRevision++;
    startup.stopReady.complete();
    await flush(tester);
    expect(find.text('Ready /loginpage'), findsOneWidget);
    expect(find.text('Ready /account-cache-recovery'), findsNothing);
    expect(startup.memoryClears, 0);
  });
  testWidgets('onboarding waits for its local flag write after all gates pass',
      (tester) async {
    final firstLaunch = Startup();
    await open(tester, firstLaunch);
    expect(firstLaunch.onboardingWrites, 0);
    firstLaunch.vaultReady.complete();
    await flush(tester);
    expect(firstLaunch.onboardingWrites, 1);
    expect(find.text('Ready /onboardingscreen'), findsNothing);
    await tester.runAsync(() => auth.put('hasSeenOnboarding', true));
    firstLaunch.onboardingSaved.complete();
    await flush(tester);
    expect(find.text('Ready /onboardingscreen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    firstLaunch.notesReady.complete();

    final nextLaunch = Startup();
    await open(tester, nextLaunch);
    nextLaunch.vaultReady.complete();
    await flush(tester);
    expect(nextLaunch.onboardingWrites, 0);
    expect(find.text('Ready /mainpage'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    nextLaunch.notesReady.complete();
  });

  testWidgets('cache recovery wins while the onboarding flag is being saved',
      (tester) async {
    final startup = Startup();
    await open(tester, startup);
    startup.vaultReady.complete();
    await flush(tester);
    expect(startup.onboardingWrites, 1);
    startup.notesReady.completeError(ForeignPendingCacheError());
    await flush(tester);
    startup.onboardingSaved.complete();
    await flush(tester);
    expect(find.text('Ready /account-cache-recovery'), findsOneWidget);
    expect(find.text('Ready /onboardingscreen'), findsNothing);
  });
}
