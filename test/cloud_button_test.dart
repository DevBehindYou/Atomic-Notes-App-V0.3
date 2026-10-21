import 'dart:async';

import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/utility/component/cloud_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'support/fake_notes_source.dart';

void _stage(String value) {
  // Fixed public fixture markers only; no credentials or widget text.
  // ignore: avoid_print
  print('atomic_ui_stage:cloud_connectivity:$value');
}

// Match MainPage's composition, with counters instead of network/UI work.
Widget control({
  required bool busy,
  required VoidCallback sync,
  required VoidCallback energy,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  bool tickerEnabled = true,
}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        ),
        child: child!,
      ),
      home: TickerMode(
        enabled: tickerEnabled,
        child: Scaffold(
          body: CloudButton(
            ico: 'assets/sync.svg',
            action: sync,
            clr: 0xff5F5EF7,
            isLoading: busy,
            onLongPress: energy,
          ),
        ),
      ),
    );

void main() {
  CustomPainter ringPainter(WidgetTester tester) => tester
      .widget<CustomPaint>(find.byKey(const ValueKey('cloud-sync-ring')))
      .painter!;

  BoxDecoration surface(WidgetTester tester) => tester
      .widget<Container>(
        find.byKey(const ValueKey('cloud-button-surface')),
      )
      .decoration! as BoxDecoration;

  testWidgets('cloud matches bell surface and keeps a 48px touch target',
      (tester) async {
    for (final busy in [false, true]) {
      await tester.pumpWidget(control(busy: busy, sync: () {}, energy: () {}));
      expect(tester.getSize(find.byKey(const ValueKey('cloud-button-surface'))),
          const Size(46, 38));
      final target = tester.getSize(find.byType(GestureDetector));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
      expect(surface(tester).boxShadow, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('cloud is purple when idle and black with a rotating busy ring', (
    tester,
  ) async {
    await tester.pumpWidget(control(busy: false, sync: () {}, energy: () {}));
    expect(surface(tester).color, AppColors.signal);
    expect(surface(tester).boxShadow, isNull);
    expect(find.byKey(const ValueKey('cloud-sync-ring')), findsNothing);
    await tester.pumpWidget(control(busy: true, sync: () {}, energy: () {}));
    expect(surface(tester).color, AppColors.ink);
    final initial = ringPainter(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(ringPainter(tester).shouldRepaint(initial), isTrue);
    await tester.pumpWidget(control(busy: false, sync: () {}, energy: () {}));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('cloud-sync-ring')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in ['reduced-motion', 'accessible-navigation', 'muted']) {
    testWidgets('busy ring is static for $mode and keeps Energy available', (
      tester,
    ) async {
      var energies = 0;
      await tester.pumpWidget(
        control(
          busy: true,
          sync: () => fail('busy sync must not dispatch'),
          energy: () => energies++,
          disableAnimations: mode == 'reduced-motion',
          accessibleNavigation: mode == 'accessible-navigation',
          tickerEnabled: mode != 'muted',
        ),
      );
      final initial = ringPainter(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(ringPainter(tester).shouldRepaint(initial), isFalse);
      await tester.longPress(find.byType(CloudButton));
      await tester.pump();
      expect(energies, 1);
      expect(surface(tester).color, AppColors.ink);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('foreground pause stops the ring and resume restarts it', (
    tester,
  ) async {
    await tester.pumpWidget(control(busy: true, sync: () {}, energy: () {}));
    await tester.pump(const Duration(milliseconds: 200));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final paused = ringPainter(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(ringPainter(tester).shouldRepaint(paused), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final resumed = ringPainter(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(ringPainter(tester).shouldRepaint(resumed), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('receive-only source sync animates and returns to idle', (
    tester,
  ) async {
    final source = FakeNotesSource();
    final bloc = NotesBloc(
      source: source,
      isSyncEnabled: () => true,
      isOnline: () async => true,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await bloc.close();
      source.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocBuilder<NotesBloc, NotesState>(
            bloc: bloc,
            builder: (_, state) => CloudButton(
              ico: 'assets/sync.svg',
              action: () {},
              clr: 0,
              isLoading: state.syncing,
            ),
          ),
        ),
      ),
    );
    source.changeBehindTheScenes(() => source.isSyncing = true);
    await tester.pump();
    await tester.pump();
    expect(bloc.state.pending, 0);
    expect(find.byKey(const ValueKey('cloud-sync-ring')), findsOneWidget);
    source.changeBehindTheScenes(() => source.isSyncing = false);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('cloud-sync-ring')), findsNothing);
    expect(source.syncCalls, 0);
  });

  testWidgets('manual connectivity check is busy without claiming an upload', (
    tester,
  ) async {
    // Use the semantics handle owned by testWidgets. An extra handle disposed
    // in addTearDown would outlive end-of-test handle verification.
    final connectivity = Completer<bool>();
    final source = FakeNotesSource();
    final bloc = NotesBloc(
      source: source,
      isSyncEnabled: () => true,
      isOnline: () => connectivity.future,
    );
    addTearDown(() async {
      if (!connectivity.isCompleted) connectivity.complete(false);
      await tester.pumpWidget(const SizedBox.shrink());
      await bloc.close();
      source.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocBuilder<NotesBloc, NotesState>(
            bloc: bloc,
            builder: (_, state) => CloudButton(
              ico: 'assets/sync.svg',
              action: () => bloc.add(const NotesSyncRequested(instant: true)),
              clr: 0,
              isLoading: state.syncing,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(CloudButton));
    await tester.pump();
    await tester.pump();
    _stage('busy');
    expect(find.byKey(const ValueKey('cloud-sync-ring')), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('Sync now'));
    _stage('semantics');
    expect(node.getSemanticsData().value, 'Syncing');
    expect(source.syncCalls, 0);
    connectivity.complete(false);
    await tester.pump();
    await tester.pump();
    _stage('idle');
    expect(find.byKey(const ValueKey('cloud-sync-ring')), findsNothing);
    expect(bloc.state.notice!.text, 'No Internet Connection!');
    _stage('clean');
    expect(source.syncCalls, 0);
  });

  testWidgets(
    'sync control exposes one named button and both accessible actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var syncs = 0, energies = 0;
        await tester.pumpWidget(
          control(busy: false, sync: () => syncs++, energy: () => energies++),
        );
        expect(find.bySemanticsLabel('Sync now'), findsOneWidget);
        final node = tester.getSemantics(find.bySemanticsLabel('Sync now'));
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.hasAction(SemanticsAction.longPress), isTrue);
        expect(data.hint, 'Long press to open Atomic Energy');
        tester.semantics.tap(find.semantics.byLabel('Sync now'));
        tester.semantics.longPress(find.semantics.byLabel('Sync now'));
        await tester.pump();
        expect(syncs, 1);
        expect(energies, 1);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('busy sync remains named and exposes only its Energy action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var syncs = 0, energies = 0;
      await tester.pumpWidget(
        control(busy: true, sync: () => syncs++, energy: () => energies++),
      );
      expect(find.bySemanticsLabel('Sync now'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('Sync now'));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.value, 'Syncing');
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      tester.semantics.longPress(find.semantics.byLabel('Sync now'));
      await tester.pump();
      expect(syncs, 0);
      expect(energies, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'pointer tap is blocked while busy and long press remains available',
    (tester) async {
      var syncs = 0, energies = 0;
      for (final busy in [false, true]) {
        await tester.pumpWidget(
          control(busy: busy, sync: () => syncs++, energy: () => energies++),
        );
        await tester.tap(find.byType(CloudButton));
        await tester.pump();
        await tester.longPress(find.byType(CloudButton));
        await tester.pump();
      }
      expect(syncs, 1);
      expect(energies, 2);
    },
  );
}
