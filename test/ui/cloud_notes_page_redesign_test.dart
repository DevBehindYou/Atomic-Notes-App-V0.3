// Cloud Notes on lib/ui components (screens spec, Cloud Notes): the hero
// counts, the status that follows the returned count, the details group, the
// actions and the collapsible receipt. Synthetic notes over a fake source and
// a fake sync box; no Hive files or network.

import 'dart:async';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/sync_report.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/page/endpage/cloud_notes_page.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../support/fake_notes_source.dart';

class _SyncBox implements Box<bool> {
  bool enabled = true;
  @override
  bool? get(dynamic key, {bool? defaultValue}) => enabled;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts answered one by one, an account identity that can change, and a
/// sync that hands back a receipt.
class _Cloud extends FakeNotesSource implements SyncReportSource {
  _Cloud({super.notes});

  int session = 0;
  int countCalls = 0;
  int reportCalls = 0;
  final answers = <Future<int?>>[];

  /// The next count throws, as a transport failure would.
  bool failNext = false;
  SyncAttemptReport report = SyncAttemptReport(
    completed: true,
    activity: SyncAttemptActivity.started,
    operations: const [
      SyncOperationReport(
          requestId: 'op-a',
          instant: true,
          recovered: false,
          charged: 10,
          refunded: 0),
    ],
  );

  @override
  Object get syncReportIdentity => session;

  @override
  Future<int?> cloudCount() {
    countCalls++;
    if (failNext) {
      failNext = false;
      return Future.error(StateError('fixture secret failure'));
    }
    return answers.isEmpty ? Future.value(cloudNotes) : answers.removeAt(0);
  }

  @override
  Future<SyncAttemptReport> syncWithReport({bool instant = false}) async {
    reportCalls++;
    syncCalls++;
    return report;
  }

  void switchAccount() {
    session++;
    poke();
  }
}

List<Note> _notes(int synced, {int edited = 0}) => [
      for (var i = 0; i < synced; i++) syncedNote('synced-$i'),
      for (var i = 0; i < edited; i++) syncedNote('edited-$i')..dirty = true,
    ];

Future<void> _pump(
  WidgetTester tester,
  FakeNotesSource source, {
  ThemeData? theme,
  double width = 412,
  double height = 915,
  double textScale = 1,
  bool disableAnimations = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(source.dispose);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: CloudNotesPage(source: source),
  ));
  if (settle) await tester.pumpAndSettle();
}

final Finder _verdictFinder = find.byKey(const ValueKey('cloud-notes-verdict'));
final Finder _check = find.byKey(const ValueKey('cloud-notes-check'));
final Finder _sync = find.byKey(const ValueKey('cloud-notes-sync'));
final Finder _uploadAll = find.byKey(const ValueKey('cloud-notes-upload-all'));
final Finder _hero = find.byKey(const ValueKey('cloud-notes-hero'));
final Finder _receiptToggle =
    find.byKey(const ValueKey('cloud-notes-receipt-toggle'));
final Finder _refresh = find.byTooltip('Check cloud again');

/// The status title: on the status card's text, or the banner's title.
String _verdict(WidgetTester tester) {
  final widget = tester.widget(_verdictFinder);
  return widget is AtomicBanner ? widget.title : (widget as Text).data!;
}

BannerTone? _verdictTone(WidgetTester tester) {
  final widget = tester.widget(_verdictFinder);
  return widget is AtomicBanner ? widget.tone : null;
}

AtomicButton _button(WidgetTester tester, Finder finder) =>
    tester.widget<AtomicButton>(finder);

AtomicIconButton _refreshButton(WidgetTester tester) =>
    tester.widget<AtomicIconButton>(
        find.ancestor(of: _refresh, matching: find.byType(AtomicIconButton)));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _banner(BannerTone tone) =>
    find.byWidgetPredicate((w) => w is AtomicBanner && w.tone == tone,
        description: 'AtomicBanner(${tone.name})');

void main() {
  late _SyncBox box;
  setUp(() => SyncStatusHelper.syncBox = box = _SyncBox());

  group('populated', () {
    testWidgets('matching counts: hero, check status and actions',
        (tester) async {
      final source = _Cloud(notes: _notes(3))..cloudNotes = 3;
      await _pump(tester, source);

      expect(find.byType(AtomicPageHeader), findsOneWidget);
      expect(find.byType(PageTitle), findsOneWidget);
      expect(find.text('Cloud notes'), findsWidgets);
      expect(find.text('3'), findsNWidgets(2));
      expect(find.text('on device'), findsOneWidget);
      expect(find.text('in cloud'), findsOneWidget);
      expect(find.text('3 unchanged · 0 edited'), findsOneWidget);
      expect(_verdict(tester), 'Counts match');
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cloud-notes-status')),
              matching: find.byIcon(AtomicIcons.circleCheck)),
          findsOneWidget);
      expect(find.textContaining('This check does not compare note contents.'),
          findsOneWidget);
      expect(find.byType(AtomicBanner), findsNothing);
      expect(_button(tester, _check).label, 'Check cloud');
      expect(_button(tester, _check).variant, AtomicButtonVariant.tonal);
      expect(_button(tester, _sync).label, 'Sync now · 10 energy per batch');
      expect(_button(tester, _sync).variant, AtomicButtonVariant.primary);
      expect(_button(tester, _sync).onPressed, isNotNull);
      expect(_uploadAll, findsNothing);
      expect(source.countCalls, 1);
      expect(source.syncCalls, 0);
      expect(source.markAllCalls, 0);
    });

    testWidgets('edits waiting: counts, waiting status and deletions',
        (tester) async {
      final source = _Cloud(notes: _notes(2, edited: 1))..cloudNotes = 3;
      source.all.add(syncedNote('binned')
        ..deleted = true
        ..dirty = true);
      await _pump(tester, source);

      expect(find.text('2 unchanged · 1 edited'), findsOneWidget);
      expect(find.text('1 deletion waiting'), findsOneWidget);
      expect(_verdict(tester), '2 waiting');
      expect(
          find.textContaining('2 changes are waiting to upload, including '
              'edited notes or deletions.'),
          findsOneWidget);
      expect(find.textContaining('does not compare cloud contents'),
          findsOneWidget);
    });

    for (final (cloud, title) in [
      (1, 'Fewer in cloud'),
      (5, 'More in cloud')
    ]) {
      testWidgets('a count mismatch is an attention banner ($title)',
          (tester) async {
        final source = _Cloud(notes: _notes(3))..cloudNotes = cloud;
        await _pump(tester, source);

        expect(_verdict(tester), title);
        expect(_verdictTone(tester), BannerTone.attention);
        expect(
            find.textContaining('This check does not compare note contents.'),
            findsOneWidget);
        expect(_uploadAll, cloud < 3 ? findsOneWidget : findsNothing);
        expect(find.text('$cloud'), findsOneWidget);
      });
    }

    testWidgets('Upload all appears only for fewer in cloud and marks all',
        (tester) async {
      final source = _Cloud(notes: _notes(2))..cloudNotes = 0;
      await _pump(tester, source);

      expect(_button(tester, _uploadAll).label,
          'Upload all · 10 energy per batch');
      await _tap(tester, _uploadAll);
      expect(source.markAllCalls, 1);
      expect(source.reportCalls, 1);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });

  group('empty', () {
    testWidgets('no notes anywhere says so, not that counts match',
        (tester) async {
      final source = _Cloud()..cloudNotes = 0;
      await _pump(tester, source);

      expect(_verdict(tester), 'No notes');
      expect(find.text('There are no notes on this device or in the cloud.'),
          findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text('0 unchanged · 0 edited'), findsOneWidget);
      expect(_uploadAll, findsNothing);
      expect(find.byType(AtomicBanner), findsNothing);
    });

    testWidgets('an empty device with notes in the cloud is a mismatch',
        (tester) async {
      final source = _Cloud()..cloudNotes = 4;
      await _pump(tester, source);

      expect(_verdict(tester), 'More in cloud');
      expect(_banner(BannerTone.attention), findsOneWidget);
    });
  });

  group('loading', () {
    testWidgets('while counting: checking copy, ring, busy check, no number',
        (tester) async {
      final gate = Completer<int?>();
      final source = _Cloud(notes: _notes(2))..answers.add(gate.future);
      await _pump(tester, source, settle: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(_verdict(tester), 'Checking');
      expect(find.text('Counting the notes in your cloud…'), findsOneWidget);
      expect(
          find.descendant(of: _hero, matching: find.text('—')), findsOneWidget);
      expect(
          find.descendant(
              of: _hero, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(_button(tester, _check).busy, isTrue);
      expect(_button(tester, _sync).onPressed, isNull);
      expect(_refreshButton(tester).onPressed, isNull);

      gate.complete(2);
      await tester.pumpAndSettle();
      expect(_verdict(tester), 'Counts match');
      expect(find.text('2'), findsNWidgets(2));
      expect(
          find.descendant(
              of: _hero, matching: find.byType(CircularProgressIndicator)),
          findsNothing);
      expect(_button(tester, _check).busy, isFalse);
    });

    testWidgets('a background sync shows activity and holds the actions',
        (tester) async {
      final source = _Cloud(notes: _notes(1))..cloudNotes = 0;
      await _pump(tester, source);
      source.changeBehindTheScenes(() => source.isSyncing = true);
      await tester.pump();
      await tester.pump();

      expect(
          find.descendant(
              of: _hero, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(_button(tester, _check).onPressed, isNull);
      expect(_button(tester, _sync).onPressed, isNull);
      expect(_button(tester, _uploadAll).onPressed, isNull);
      expect(_refreshButton(tester).onPressed, isNull);

      source.changeBehindTheScenes(() => source.isSyncing = false);
      await tester.pumpAndSettle();
      expect(_button(tester, _sync).onPressed, isNotNull);
    });
  });

  group('failed read', () {
    for (final throws in [false, true]) {
      testWidgets(
          'a failed count is a danger banner and retries '
          '(${throws ? 'throws' : 'null'})', (tester) async {
        final source = _Cloud(notes: _notes(1))
          ..cloudNotes = null
          ..failNext = throws;
        await _pump(tester, source);

        expect(tester.takeException(), isNull);
        expect(_verdict(tester), 'Check failed');
        expect(_verdictTone(tester), BannerTone.danger);
        expect(
            find.textContaining('Your local notes remain on this device. '
                'Try Check cloud again.'),
            findsOneWidget);
        expect(find.textContaining('fixture secret failure'), findsNothing);
        expect(find.descendant(of: _hero, matching: find.text('—')),
            findsOneWidget);
        expect(_uploadAll, findsNothing);
        expect(source.all.single.id, 'synced-0');

        source.cloudNotes = 1;
        await _tap(tester, _check);
        expect(source.countCalls, 2);
        expect(_verdict(tester), 'Counts match');
        expect(_banner(BannerTone.danger), findsNothing);
        expect(source.syncCalls, 0);
      });
    }
  });

  group('refresh', () {
    testWidgets('the header refresh counts again and shows the new count',
        (tester) async {
      final source = _Cloud(notes: _notes(2))..cloudNotes = 2;
      await _pump(tester, source);
      expect(_verdict(tester), 'Counts match');

      source.cloudNotes = 7;
      await tester.tap(_refresh);
      await tester.pumpAndSettle();

      expect(source.countCalls, 2);
      expect(find.text('7'), findsOneWidget);
      expect(_verdict(tester), 'More in cloud');
      expect(source.syncCalls, 0);
      expect(source.markAllCalls, 0);
    });

    testWidgets('Sync now syncs, says so, shows the receipt and recounts',
        (tester) async {
      final source = _Cloud(notes: _notes(1, edited: 1))..cloudNotes = 1;
      await _pump(tester, source);

      await _tap(tester, _sync);
      expect(source.reportCalls, 1);
      expect(source.countCalls, 2);
      expect(find.text('Synced with the cloud'), findsOneWidget);
      expect(find.text('Sync completed'), findsOneWidget);
      expect(find.text('Net upload cost'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('an incomplete sync shows its own error in the receipt',
        (tester) async {
      final source = _Cloud(notes: _notes(1))
        ..cloudNotes = 1
        ..report = SyncAttemptReport(
          completed: false,
          activity: SyncAttemptActivity.started,
          errorMessage: 'Pull unavailable',
        );
      await _pump(tester, source);

      await _tap(tester, _sync);
      expect(find.text('Sync incomplete'), findsOneWidget);
      expect(find.text('Pull unavailable'), findsWidgets);
      expect(find.text('Upload energy totals unavailable.'), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('the receipt collapses and expands', (tester) async {
      final source = _Cloud(notes: _notes(1))..cloudNotes = 1;
      await _pump(tester, source);
      await _tap(tester, _sync);
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(find.text('Net upload cost'), findsOneWidget);

      await _tap(tester, _receiptToggle);
      expect(find.text('Net upload cost'), findsNothing);
      expect(find.text('Sync completed'), findsOneWidget);

      await _tap(tester, _receiptToggle);
      expect(find.text('Net upload cost'), findsOneWidget);
    });
  });

  group('account switch', () {
    testWidgets('a new account clears the count and receipt until rechecked',
        (tester) async {
      final source = _Cloud(notes: _notes(1))..cloudNotes = 9;
      await _pump(tester, source);
      await _tap(tester, _sync);
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(find.text('9'), findsOneWidget);
      expect(find.text('Sync completed'), findsOneWidget);

      source.switchAccount();
      await tester.pumpAndSettle();

      expect(find.text('9'), findsNothing);
      expect(
          find.descendant(of: _hero, matching: find.text('—')), findsOneWidget);
      expect(_verdict(tester), 'Not checked');
      expect(
          find.textContaining('The cloud note count has not been checked for '
              'this session.'),
          findsOneWidget);
      expect(find.text('Sync completed'), findsNothing);
      expect(_receiptToggle, findsNothing);
      expect(find.text('—', skipOffstage: false), findsWidgets);

      source.cloudNotes = 1;
      await _tap(tester, _check);
      expect(_verdict(tester), 'Counts match');
      expect(find.text('1'), findsNWidgets(2));
    });
  });

  group('sync off', () {
    testWidgets('says so and holds Sync now', (tester) async {
      box.enabled = false;
      final source = _Cloud(notes: _notes(1))..cloudNotes = 0;
      await _pump(tester, source);

      expect(_verdict(tester), 'Sync off');
      expect(
          find.text(
              'Cloud Sync is turned off, so notes stay on this device only.'),
          findsOneWidget);
      expect(_button(tester, _sync).onPressed, isNull);
      expect(_uploadAll, findsNothing);
      await tester.ensureVisible(_sync);
      await tester.tap(_sync, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(source.syncCalls, 0);
    });
  });

  group('details', () {
    testWidgets('last sync, last check, cloud sync and automatic sync',
        (tester) async {
      final source = _Cloud(notes: _notes(1))
        ..cloudNotes = 1
        ..lastSyncedAt = DateTime(2026, 3, 4, 5, 6);
      await _pump(tester, source);

      for (final label in [
        'Last sync',
        'Last check',
        'Cloud sync',
        'Automatic sync'
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('2026-03-04 05:06'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });
  });

  group('layout and access', () {
    for (final (name, theme) in [
      ('light', AtomicTheme.light),
      ('dark', AtomicTheme.dark),
    ]) {
      testWidgets('fits 320 dp at 2.0 text ($name)', (tester) async {
        final source = _Cloud(notes: _notes(3, edited: 2))..cloudNotes = 1;
        await _pump(tester, source,
            theme: theme, width: 320, height: 640, textScale: 2);
        expect(tester.takeException(), isNull);
        await _tap(tester, _sync);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        for (var i = 0; i < 12; i++) {
          await tester.drag(
              find.byType(SingleChildScrollView), const Offset(0, -400));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
            find.textContaining('Each charged upload batch'), findsOneWidget);
      });

      testWidgets('hero is the inverse surface ($name)', (tester) async {
        final source = _Cloud(notes: _notes(1))..cloudNotes = 1;
        await _pump(tester, source, theme: theme);
        final colors = theme.extension<AtomicColors>()!;
        final card = tester.widget<AtomicCard>(
            find.descendant(of: _hero, matching: find.byType(AtomicCard)));
        expect(card.color, colors.inverseSurface);
        final number = tester.widget<Text>(find.text('1').first);
        expect(number.style?.color, colors.onInverse);
      });
    }

    testWidgets(
        'screen readers hear the counts as one sentence and the '
        'status as a live region', (tester) async {
      final semantics = tester.ensureSemantics();
      final source = _Cloud(notes: _notes(2, edited: 1))..cloudNotes = 3;
      await _pump(tester, source);

      expect(
          find.bySemanticsLabel(
              '3 on device, 3 in cloud. 2 unchanged, 1 edited'),
          findsOneWidget);
      final status =
          tester.getSemantics(find.byKey(const ValueKey('cloud-notes-status')));
      expect(status.flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
    });

    testWidgets('targets are at least 48 dp', (tester) async {
      final source = _Cloud(notes: _notes(1))..cloudNotes = 0;
      await _pump(tester, source);
      for (final finder in [
        _check,
        _sync,
        _uploadAll,
        _refresh,
        find.byTooltip('Back')
      ]) {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
      }
    });

    testWidgets('reduced motion shows everything at once', (tester) async {
      final source = _Cloud(notes: _notes(1))..cloudNotes = 1;
      await _pump(tester, source, disableAnimations: true, settle: false);
      await tester.pump();
      await tester.pump();
      for (final fade in tester.widgetList<FadeTransition>(
          find.ancestor(of: _hero, matching: find.byType(FadeTransition)))) {
        expect(fade.opacity.value, 1);
      }
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('without reduced motion the blocks rise in', (tester) async {
      final source = _Cloud(notes: _notes(1))..cloudNotes = 1;
      await _pump(tester, source, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      Iterable<double> fades() => tester
          .widgetList<FadeTransition>(
              find.ancestor(of: _hero, matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value);
      expect(fades().any((v) => v < 1), isTrue);
      await tester.pumpAndSettle();
      expect(fades().every((v) => v == 1), isTrue);
    });
  });
}
