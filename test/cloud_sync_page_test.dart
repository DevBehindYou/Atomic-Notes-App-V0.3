// Cloud sync on lib/ui components (screens spec, Cloud sync): the hero
// switch, the row to Cloud Notes and the info banner, over a fake sync box.
// No Hive files or network.

import 'dart:async';

import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/endpage/cloud_sync_page.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/controls/atomic_switch.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

/// The stored choice, with an optional failure or a gate on writes.
class _SyncBox implements Box<bool> {
  _SyncBox(this.value);

  bool? value;
  Object? failure;
  Completer<void>? gate;
  int puts = 0;

  @override
  bool? get(dynamic key, {bool? defaultValue}) => value ?? defaultValue;

  @override
  Future<void> put(dynamic key, bool value) async {
    puts++;
    await gate?.future;
    final failure = this.failure;
    if (failure != null) throw failure;
    this.value = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final Finder _hero = find.byKey(const ValueKey('cloud-sync-switch'));

bool _shownOn(WidgetTester tester) =>
    tester.widget<AtomicSwitchTrack>(find.byType(AtomicSwitchTrack)).value;

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 412,
  double height = 915,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    routes: {
      '/': (_) => const CloudSyncPage(),
      '/cloudnotes': (_) => const Scaffold(body: Text('cloud notes page')),
    },
  ));
  await tester.pumpAndSettle();
}

Future<void> _settleSnackBar(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(seconds: 4));

void main() {
  late _SyncBox box;
  setUp(() => SyncStatusHelper.syncBox = box = _SyncBox(null));

  group('switch', () {
    testWidgets('on by default, as the store reads it', (tester) async {
      await _pump(tester);

      expect(_shownOn(tester), isTrue);
      expect(find.text(CloudSyncPage.onCaption), findsOneWidget);
      expect(find.text(CloudSyncPage.offCaption), findsNothing);
    });

    testWidgets('a tap anywhere on the card turns it off and stores it',
        (tester) async {
      box.value = true;
      await _pump(tester);

      await tester.tap(find.text(CloudSyncPage.onCaption));
      await tester.pumpAndSettle();

      expect(box.value, isFalse);
      expect(box.puts, 1);
      expect(_shownOn(tester), isFalse);
      expect(find.text(CloudSyncPage.offCaption), findsOneWidget);
      expect(find.text('Cloud sync off'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('stored off, a tap turns it on', (tester) async {
      box.value = false;
      await _pump(tester);
      expect(_shownOn(tester), isFalse);
      expect(find.text(CloudSyncPage.offCaption), findsOneWidget);

      await tester.tap(_hero);
      await tester.pumpAndSettle();

      expect(box.value, isTrue);
      expect(_shownOn(tester), isTrue);
      expect(find.text('Cloud sync on'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a failed write shows what is stored and says so',
        (tester) async {
      box
        ..value = true
        ..failure = StateError('disk full');
      await _pump(tester);

      await tester.tap(_hero);
      await tester.pumpAndSettle();

      expect(box.value, isTrue);
      expect(_shownOn(tester), isTrue);
      expect(find.text(CloudSyncPage.onCaption), findsOneWidget);
      expect(
          find.text("Couldn't change cloud sync. Try again."), findsOneWidget);
      expect(find.text('Cloud sync off'), findsNothing);
      await _settleSnackBar(tester);
    });

    testWidgets('taps wait while the choice is being stored', (tester) async {
      box
        ..value = true
        ..gate = Completer<void>();
      await _pump(tester);

      await tester.tap(_hero);
      await tester.pump();
      expect(_shownOn(tester), isFalse);
      // The switch shows it is busy.
      expect(
          tester
              .widget<AtomicSwitchTrack>(find.byType(AtomicSwitchTrack))
              .enabled,
          isFalse);
      await tester.tap(_hero, warnIfMissed: false);
      await tester.pump();
      expect(box.puts, 1);

      box.gate!.complete();
      await tester.pumpAndSettle();
      expect(box.value, isFalse);
      expect(box.puts, 1);
      expect(
          tester
              .widget<AtomicSwitchTrack>(find.byType(AtomicSwitchTrack))
              .enabled,
          isTrue);
      await _settleSnackBar(tester);
    });
  });

  group('page', () {
    testWidgets('the Cloud notes row opens Cloud Notes', (tester) async {
      await _pump(tester);

      expect(find.text('Compare this device with the cloud'), findsOneWidget);
      await tester.tap(find.text('Cloud notes'));
      await tester.pumpAndSettle();
      expect(find.text('cloud notes page'), findsOneWidget);
    });

    testWidgets('the banner says when a change takes effect', (tester) async {
      await _pump(tester);

      expect(find.text('Changes take effect immediately'), findsOneWidget);
      // The old note claimed an "Atomic cloud database"; notes sync with
      // the user's Google Drive.
      expect(find.textContaining('Atomic cloud database'), findsNothing);
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
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const CloudSyncPage())),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(CloudSyncPage.onCaption), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('the header shows the title once the large one scrolls away',
        (tester) async {
      await _pump(tester, height: 480, textScale: 2);

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
        for (final on in [true, false]) {
          testWidgets(
              'fits 320 dp at 2.0 text ($name, ${direction.name}, '
              '${on ? 'on' : 'off'})', (tester) async {
            box.value = on;
            await _pump(tester,
                theme: theme,
                width: 320,
                height: 640,
                textScale: 2,
                direction: direction);
            expect(tester.takeException(), isNull);
            for (var i = 0; i < 6; i++) {
              await tester.drag(find.byType(ListView), const Offset(0, -400));
              await tester.pump();
            }
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
                find.text('Changes take effect immediately'), findsOneWidget);
          });
        }
      }
    }

    testWidgets('targets are at least 48 dp', (tester) async {
      await _pump(tester);

      for (final finder in [
        _hero,
        find.byKey(const ValueKey('cloud-sync-cloud-notes')),
        find.byTooltip('Back'),
      ]) {
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
      }
    });

    testWidgets('screen readers hear one toggle with its meaning',
        (tester) async {
      final semantics = tester.ensureSemantics();
      box.value = true;
      await _pump(tester);

      const label = '${CloudSyncPage.title}. ${CloudSyncPage.onCaption}';
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(
              label: label,
              isButton: false,
              hasToggledState: true,
              isToggled: true,
              hasTapAction: true));
      // The caption is not read a second time on its own.
      expect(find.bySemanticsLabel(CloudSyncPage.onCaption), findsNothing);
      semantics.dispose();
    });

    testWidgets('reduced motion shows everything at once', (tester) async {
      await _pump(tester, disableAnimations: true);
      expect(tester.hasRunningAnimations, isFalse);

      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      await tester.pumpWidget(MaterialApp(
        theme: AtomicTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const CloudSyncPage(key: ValueKey('fresh')),
      ));
      await tester.pump();
      for (final fade in tester.widgetList<FadeTransition>(find.ancestor(
          of: find.text(CloudSyncPage.onCaption),
          matching: find.byType(FadeTransition)))) {
        expect(fade.opacity.value, 1);
      }
    });

    testWidgets('without reduced motion the blocks rise in', (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          MaterialApp(theme: AtomicTheme.light, home: const CloudSyncPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      Iterable<double> fades() => tester
          .widgetList<FadeTransition>(find.ancestor(
              of: find.text('Changes take effect immediately'),
              matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value);
      expect(fades().any((v) => v < 1), isTrue);
      await tester.pumpAndSettle();
      expect(fades().every((v) => v == 1), isTrue);
    });
  });
}
