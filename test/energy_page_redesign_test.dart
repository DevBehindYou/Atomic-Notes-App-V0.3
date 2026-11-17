// The Atomic Energy screen and popup on lib/ui components (screens spec,
// Energy and Energy popup): the accent hero with the rolling balance, the
// coins card and its sheets, the note-limit tiers, coin expiry, activity,
// "How Atomic Energy works", and the layout checks every redesigned page
// passes. A fake store; no Hive or network. Every number shown comes from the
// store's wallet and policy.

import 'dart:async';

import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/note_quota.dart';
import 'package:atomic_notes/page/endpage/energy_page.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/odometer.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/utility/component/energy_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_energy_store.dart';
import 'support/fake_notes_source.dart';

final DateTime _t0 = DateTime(2026, 11, 10, 8);

EnergyTx _tx(String id,
        {EnergyTxKind kind = EnergyTxKind.spend,
        int energy = 0,
        int coins = 0,
        String? note,
        DateTime? at}) =>
    EnergyTx(
      id: id,
      kind: kind,
      coinsDelta: coins,
      energyDelta: energy,
      resultingCoins: 0,
      resultingEnergy: 0,
      note: note,
      createdAt: at ?? _t0,
    );

final List<EnergyTx> _history = [
  _tx('grant',
      kind: EnergyTxKind.dailyGrant, energy: 20, note: 'Daily energy grant'),
  _tx('sync', energy: -10, note: 'Instant sync'),
  _tx('convert', kind: EnergyTxKind.convert, coins: -1, energy: 40),
];

CoinDetails _details({String? cursor}) => CoinDetails(
      nonExpiring: 40,
      nextExpiryCoins: 5,
      nextExpiryAt: DateTime(2027, 2, 28, 12),
      serverTime: DateTime(2026, 11, 10, 9),
      nextCursor: cursor,
      rows: [
        CoinBatch(
            id: 'legacy',
            source: 'legacy',
            amount: 40,
            remaining: 40,
            creditedAt: DateTime(2026, 10, 1, 12)),
        CoinBatch(
            id: 'new',
            source: 'controller',
            amount: 50,
            remaining: 5,
            creditedAt: DateTime(2026, 8, 30, 12),
            expiresAt: DateTime(2027, 2, 28, 12)),
      ],
    );

Wallet _wallet(
        {int coins = 45,
        int energy = 110,
        int noteLimit = 30,
        CoinDetails? details}) =>
    Wallet(
      coins: coins,
      energy: energy,
      energyCap: 120,
      lastDailyGrantAt: null,
      noteLimit: noteLimit,
      coinDetails: details,
    );

/// A fake that counts the calls the screen makes beyond the shared fake.
class _Store extends FakeEnergyStore {
  _Store({super.wallet, super.limits, super.history});

  int batchLoads = 0;
  int retries = 0;
  Completer<String?>? convertGate;

  @override
  Future<String?> loadMoreCoinBatches() async {
    batchLoads++;
    return 'No more batches.';
  }

  @override
  Future<String?> retryPendingConversion() async {
    retries++;
    return super.retryPendingConversion();
  }
}

_Store _store({
  int coins = 45,
  int energy = 110,
  int noteLimit = 30,
  CoinDetails? details,
  List<EnergyTx>? history,
  EnergyLimits limits = const EnergyLimits(),
}) {
  final s = _Store(
    wallet: _wallet(
        coins: coins, energy: energy, noteLimit: noteLimit, details: details),
    limits: limits,
    history: history ?? _history,
  );
  addTearDown(s.dispose);
  return s;
}

void _view(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app({
  required Widget home,
  ThemeData? theme,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
}) =>
    MaterialApp(
      theme: theme ?? AtomicTheme.light,
      routes: {
        '/energyintro': (_) => const Scaffold(body: Text('Energy intro route')),
        '/energypage': (_) => const Scaffold(body: Text('Energy page route')),
      },
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: home,
    );

Future<void> _pump(
  WidgetTester tester,
  _Store store, {
  ThemeData? theme,
  double width = 412,
  double height = 915,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
  bool settle = true,
}) async {
  _view(tester, width, height);
  final notes = FakeNotesSource();
  addTearDown(notes.dispose);
  await tester.pumpWidget(_app(
    theme: theme,
    textScale: textScale,
    direction: direction,
    disableAnimations: disableAnimations,
    home: EnergyPage(store: store, notes: notes),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder get _list => find.byType(Scrollable).first;

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: _list);
  await tester.pumpAndSettle();
}

/// Scrolls back up until [finder] is built and on screen.
Future<void> _revealUp(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, -300, scrollable: _list);
  await tester.pumpAndSettle();
}

Future<void> _settleSnackBar(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(seconds: 5));

AtomicColors _c(WidgetTester tester, Finder within) =>
    Theme.of(tester.element(within)).extension<AtomicColors>()!;

Finder _inTier(int limit, Finder matching) => find.descendant(
    of: find.byKey(ValueKey('capacity-$limit')), matching: matching);

void main() {
  group('hero', () {
    testWidgets('accent card with the balance, the cap, the bar and the policy',
        (tester) async {
      await _pump(
          tester,
          _store(
              limits: const EnergyLimits(
                  syncStandardCost: 6, syncInstantCost: 12)));

      final hero = find.byKey(const ValueKey('energy-hero'));
      final c = _c(tester, hero);
      expect(tester.widget<AtomicCard>(hero).color, c.accent);
      expect(find.descendant(of: hero, matching: find.text('Atomic energy')),
          findsOneWidget);
      final balance =
          tester.widget<Odometer>(find.byKey(const ValueKey('energy-balance')));
      expect(balance.text, '110');
      expect(find.text('of 120'), findsOneWidget);
      final bar =
          tester.widget<ProgressBar>(find.byKey(const ValueKey('energy-bar')));
      expect(bar.value, closeTo(110 / 120, 1e-9));
      expect(bar.onAccent, isTrue);
      // The costs are the Server's policy, not constants.
      final rule = find.textContaining('upload batch');
      expect(rule, findsOneWidget);
      final text = tester.widget<Text>(rule).data!;
      expect(text, contains('costs 6 energy'));
      expect(text, contains('Each instant upload batch costs 12.'));
      expect(text, contains('up to 120.'));
      expect(text, contains('Receive-only sync is free.'));
      expect(text, contains('Local notes are always free.'));
    });

    testWidgets('the balance follows the store', (tester) async {
      final store = _store();
      await _pump(tester, store);

      store.change(() => store.wallet = _wallet(energy: 35));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Odometer>(find.byKey(const ValueKey('energy-balance')))
              .text,
          '35');
      expect(
          tester
              .widget<ProgressBar>(find.byKey(const ValueKey('energy-bar')))
              .value,
          closeTo(35 / 120, 1e-9));
    });
  });

  group('coins card', () {
    testWidgets('shows the coins, the rate, Get coins and Convert',
        (tester) async {
      await _pump(tester, _store());

      expect(find.text('45 coins'), findsOneWidget);
      expect(find.text('1 coin = ${EnergyService.coinToEnergy} energy'),
          findsOneWidget);
      final get = tester
          .widget<AtomicButton>(find.byKey(const ValueKey('energy-get-coins')));
      final convert = tester
          .widget<AtomicButton>(find.byKey(const ValueKey('energy-convert')));
      expect(get.label, 'Get coins');
      expect(get.variant, AtomicButtonVariant.secondary);
      expect(convert.label, 'Convert');
      expect(convert.variant, AtomicButtonVariant.tonal);
      expect(convert.onPressed, isNotNull);
    });

    testWidgets('one coin reads in the singular', (tester) async {
      await _pump(tester, _store(coins: 1));
      expect(find.text('1 coin'), findsOneWidget);
    });

    testWidgets('no coins: Convert is off and says why', (tester) async {
      await _pump(tester, _store(coins: 0));

      final convert = tester
          .widget<AtomicButton>(find.byKey(const ValueKey('energy-convert')));
      expect(convert.label, 'No coins to convert');
      expect(convert.onPressed, isNull);
    });

    testWidgets('Convert opens the sheet; the stepper sets the amount',
        (tester) async {
      final store = _store(energy: 0);
      await _pump(tester, store);

      await tester.tap(find.byKey(const ValueKey('energy-convert')));
      await tester.pumpAndSettle();
      expect(find.text('Convert coins'), findsOneWidget);
      expect(find.text('= 40 energy'), findsOneWidget);
      expect(find.text('You have 45 coins.'), findsOneWidget);
      // At one coin there is nothing less to pick.
      expect(
          tester
              .widget<AtomicButton>(
                  find.byKey(const ValueKey('energy-convert-confirm')))
              .size,
          AtomicButtonSize.large);

      await tester.tap(find.byTooltip('More coins'));
      await tester.pumpAndSettle();
      expect(find.text('= 80 energy'), findsOneWidget);
      await tester.tap(find.byTooltip('More coins'));
      await tester.tap(find.byTooltip('Fewer coins'));
      await tester.pumpAndSettle();
      expect(find.text('= 80 energy'), findsOneWidget);
      expect(store.converted, isEmpty);

      await tester.tap(find.byKey(const ValueKey('energy-convert-confirm')));
      await tester.pumpAndSettle();
      expect(store.converted, [2]);
      expect(find.text('Convert coins'), findsNothing);
      expect(find.text('Converted 2 coins to 80 energy.'), findsOneWidget);
      expect(find.text('43 coins'), findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('a conversion past the cap is refused in the sheet',
        (tester) async {
      final store = _store(energy: 100);
      await _pump(tester, store);

      await tester.tap(find.byKey(const ValueKey('energy-convert')));
      await tester.pumpAndSettle();
      expect(
          find.text('That would overflow your 120 cap. Use some energy first '
              'or convert fewer coins.'),
          findsOneWidget);
      final confirm = find.byKey(const ValueKey('energy-convert-confirm'));
      expect(tester.widget<AtomicButton>(confirm).onPressed, isNull);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(store.converted, isEmpty);
    });

    testWidgets('the stepper stops at the coins there are', (tester) async {
      await _pump(tester, _store(coins: 2, energy: 0));

      await tester.tap(find.byKey(const ValueKey('energy-convert')));
      await tester.pumpAndSettle();
      Finder more() => find.byKey(const ValueKey('energy-convert-more'));
      Finder less() => find.byKey(const ValueKey('energy-convert-less'));
      expect(tester.widget<AtomicIconButton>(less()).onPressed, isNull);
      expect(tester.widget<AtomicIconButton>(more()).onPressed, isNotNull);
      await tester.tap(more());
      await tester.pumpAndSettle();
      expect(tester.widget<AtomicIconButton>(more()).onPressed, isNull);
      expect(tester.widget<AtomicIconButton>(less()).onPressed, isNotNull);
      expect(find.text('= 80 energy'), findsOneWidget);
    });

    testWidgets('closing the sheet converts nothing', (tester) async {
      final store = _store(energy: 0);
      await _pump(tester, store);

      await tester.tap(find.byKey(const ValueKey('energy-convert')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Convert coins'), findsNothing);
      expect(store.converted, isEmpty);
    });

    testWidgets('Get coins opens the coin store; Not now closes it',
        (tester) async {
      final store = _store();
      await _pump(tester, store);

      await tester.tap(find.byKey(const ValueKey('energy-get-coins')));
      await tester.pumpAndSettle();
      expect(find.text('Coin store'), findsOneWidget);
      expect(find.text('Get Atomic Coins early.'), findsOneWidget);
      expect(find.textContaining("Coins aren't sold in the app yet."),
          findsOneWidget);
      expect(
          tester
              .widget<AtomicButton>(
                  find.byKey(const ValueKey('energy-support')))
              .variant,
          AtomicButtonVariant.primary);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Coin store'), findsNothing);
      expect(store.converted, isEmpty);
      expect(store.upgrades, 0);
    });

    testWidgets('Retry unconfirmed conversion asks the store and says so',
        (tester) async {
      final store = _store();
      await _pump(tester, store);

      await tester.tap(find.byKey(const ValueKey('energy-retry-conversion')));
      await tester.pump();
      expect(store.retries, 1);
      expect(find.text('No unconfirmed conversion.'), findsOneWidget);
      await _settleSnackBar(tester);
    });
  });

  group('note-limit tiers', () {
    testWidgets(
        'the current tier is inverse and "Current"; the next shows '
        'its cost', (tester) async {
      await _pump(tester, _store());
      await _reveal(tester, find.byKey(const ValueKey('energy-tiers')));

      final current = find.byKey(const ValueKey('capacity-30'));
      final c = _c(tester, current);
      final currentBox =
          tester.widget<Container>(current).decoration! as BoxDecoration;
      expect(currentBox.color, c.inverseSurface);
      expect(_inTier(30, find.text('Current')), findsOneWidget);
      expect(_inTier(30, find.text('Tachyon')), findsOneWidget);
      expect(_inTier(30, find.text('30 notes')), findsOneWidget);

      final nextBox = tester
          .widget<Container>(find.byKey(const ValueKey('capacity-40')))
          .decoration! as BoxDecoration;
      expect(nextBox.color, c.surface);
      expect((nextBox.border! as Border).top.color, c.accentText);
      expect(_inTier(40, find.text('10 coins')), findsOneWidget);
      expect(_inTier(40, find.text('Current')), findsNothing);
      expect(_inTier(100, find.text('30 coins')), findsOneWidget);
      expect(find.text('0 of 30 notes used'), findsOneWidget);
      expect(find.text('Become Antimatter for 10 coins to hold 40 notes.'),
          findsOneWidget);
    });

    testWidgets('tiers come from the policy, not from constants',
        (tester) async {
      await _pump(
          tester,
          _store(
              noteLimit: 25,
              limits: const EnergyLimits(noteLimitTiers: [
                NoteLimitTier(limit: 25, name: 'Tachyon', costCoins: 0),
                NoteLimitTier(limit: 60, name: 'Monopole', costCoins: 7),
              ])));
      await _reveal(tester, find.byKey(const ValueKey('energy-tiers')));

      expect(find.byKey(const ValueKey('capacity-25')), findsOneWidget);
      expect(find.byKey(const ValueKey('capacity-60')), findsOneWidget);
      expect(find.byKey(const ValueKey('capacity-40')), findsNothing);
      expect(_inTier(60, find.text('7 coins')), findsOneWidget);
      expect(find.text('Become Monopole · 7 coins'), findsOneWidget);
    });

    testWidgets('a tier already passed shows no cost', (tester) async {
      await _pump(tester, _store(noteLimit: 40));
      await _reveal(tester, find.byKey(const ValueKey('energy-tiers')));

      expect(_inTier(40, find.text('Current')), findsOneWidget);
      expect(_inTier(30, find.text('Current')), findsNothing);
      expect(_inTier(30, find.textContaining('coins')), findsNothing);
      expect(_inTier(50, find.text('20 coins')), findsOneWidget);
    });

    testWidgets('becoming the next tier asks first and the scrim keeps it',
        (tester) async {
      final store = _store();
      await _pump(tester, store);
      final raise = find.byKey(const ValueKey('energy-raise-limit'));
      await _reveal(tester, raise);
      expect(tester.widget<AtomicButton>(raise).label,
          'Become Antimatter · 10 coins');

      await tester.tap(raise);
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
      expect(find.text('Become Antimatter?'), findsOneWidget);
      expect(
          find.text('Spend 10 coins to become Antimatter and raise your note '
              'limit from 30 to 40?'),
          findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
      expect(store.upgrades, 0);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(store.upgrades, 1);
      expect(find.text("You're Antimatter now — you can keep 40 notes."),
          findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('Cancel spends nothing', (tester) async {
      final store = _store();
      await _pump(tester, store);
      final raise = find.byKey(const ValueKey('energy-raise-limit'));
      await _reveal(tester, raise);
      await tester.tap(raise);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.upgrades, 0);
      expect(find.byType(AtomicDialog<bool>), findsNothing);
    });

    testWidgets('too few coins says what is missing', (tester) async {
      final store = _store(coins: 2);
      await _pump(tester, store);
      final raise = find.byKey(const ValueKey('energy-raise-limit'));
      await _reveal(tester, raise);
      await tester.tap(raise);
      await tester.pump();
      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(find.text('Becoming Antimatter costs 10 coins. You have 2.'),
          findsOneWidget);
      await _settleSnackBar(tester);
    });

    testWidgets('at the ceiling nothing is offered', (tester) async {
      await _pump(tester, _store(noteLimit: 100));
      await _reveal(
          tester, find.text('This is the most notes an account can hold.'));
      expect(find.byKey(const ValueKey('energy-raise-limit')), findsNothing);
      expect(_inTier(100, find.text('Current')), findsOneWidget);
    });
  });

  group('coin expiry', () {
    testWidgets('the existing texts, then the batches on request',
        (tester) async {
      final store = _store(details: _details(cursor: 'next'));
      await _pump(tester, store);
      await _reveal(tester, find.text('Coin expiry'));

      expect(find.text('40 coins never expire.'), findsOneWidget);
      expect(find.text('5 coins next expire 2027-02-28 12:00 (local time).'),
          findsOneWidget);
      expect(find.textContaining('New coins expire six calendar months'),
          findsOneWidget);
      expect(find.textContaining('Last checked 2026-11-10 09:00.'),
          findsOneWidget);
      expect(find.text('5 of 50 coins remaining'), findsNothing);

      final toggle = find.byKey(const ValueKey('energy-credit-batches'));
      await _reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('5 of 50 coins remaining'));
      expect(find.text('40 of 40 coins remaining'), findsOneWidget);
      expect(
          find.text('Credited 2026-08-30 12:00\nExpiry 2027-02-28 12:00 · '
              'local time'),
          findsOneWidget);
      expect(find.text('Credited 2026-10-01 12:00\nNever expires · local time'),
          findsOneWidget);

      final more = find.byKey(const ValueKey('energy-load-more-batches'));
      await _reveal(tester, more);
      expect(tester.widget<AtomicButton>(more).label, 'Load more batches');
      await tester.tap(more);
      await tester.pump();
      expect(store.batchLoads, 1);
      expect(find.text('No more batches.'), findsOneWidget);
      await _settleSnackBar(tester);

      await _reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('5 of 50 coins remaining'), findsNothing);
    });

    testWidgets('no cursor, no Load more batches', (tester) async {
      await _pump(tester, _store(details: _details()));
      final toggle = find.byKey(const ValueKey('energy-credit-batches'));
      await _reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('energy-load-more-batches')), findsNothing);
    });

    testWidgets('an older Server without details shows no section',
        (tester) async {
      await _pump(tester, _store());
      await _reveal(tester, find.text('How Atomic Energy works'));
      expect(find.text('Coin expiry'), findsNothing);
    });
  });

  group('activity', () {
    testWidgets('rows show what happened, when, and the deltas',
        (tester) async {
      await _pump(tester, _store());
      await _reveal(tester, find.byKey(const ValueKey('energy-tx-convert')));

      expect(find.text('Daily energy grant'), findsOneWidget);
      expect(find.text('Instant sync'), findsOneWidget);
      // Without a note the kind's label shows.
      expect(find.text('Coins converted'), findsOneWidget);
      expect(find.text('2026-11-10 08:00'), findsNWidgets(3));

      final c = _c(tester, find.text('Instant sync'));
      Color? colour(String text) =>
          tester.widget<Text>(find.text(text)).style!.color;
      expect(colour('+20 energy'), c.accentText);
      expect(colour('−10 energy'), c.textSecondary);
      expect(colour('+40 energy'), c.accentText);
      expect(colour('−1 coins'), c.textSecondary);
    });

    testWidgets('Load more shows the next page', (tester) async {
      await _pump(
          tester,
          _store(history: [
            for (var i = 0; i < 9; i++) _tx('t$i', energy: -5, note: 'Sync $i'),
          ]));
      final more = find.byKey(const ValueKey('energy-load-more'));
      await _reveal(tester, more);
      expect(find.text('Sync 6'), findsOneWidget);
      expect(find.text('Sync 7'), findsNothing);

      await tester.tap(more);
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Sync 8'));
      expect(find.byKey(const ValueKey('energy-load-more')), findsNothing);
    });

    testWidgets('the refresh button reloads and shows the first page again',
        (tester) async {
      final store = _store(history: [
        for (var i = 0; i < 9; i++) _tx('t$i', energy: -5, note: 'Sync $i'),
      ]);
      await _pump(tester, store);
      final opened = store.refreshCalls;
      final more = find.byKey(const ValueKey('energy-load-more'));
      await _reveal(tester, more);
      await tester.tap(more);
      await tester.pumpAndSettle();

      final refresh = find.byTooltip('Refresh activity');
      await _reveal(tester, refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(store.refreshCalls, opened + 1);
      await _reveal(tester, more);
      expect(find.text('Sync 7'), findsNothing);
    });

    testWidgets('no history: the existing empty text', (tester) async {
      await _pump(tester, _store(history: const []));
      await _reveal(tester, find.byKey(const ValueKey('energy-activity-note')));
      expect(
          find.text('No transactions yet. Daily energy and conversions will '
              'show up here.'),
          findsOneWidget);
    });

    testWidgets('a failed load: the existing retry text', (tester) async {
      final store = _store()..error = 'Could not reach the Server.';
      await _pump(tester, store);
      await _reveal(tester, find.byKey(const ValueKey('energy-activity-note')));
      expect(find.text('Could not load activity. Pull down to retry.'),
          findsOneWidget);
      expect(find.text('Instant sync'), findsNothing);
    });

    testWidgets('pull to refresh asks the store again', (tester) async {
      final store = _store();
      await _pump(tester, store);
      final opened = store.refreshCalls;
      await tester.fling(_list, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(store.refreshCalls, opened + 1);
    });
  });

  group('page', () {
    testWidgets('first load without a cached balance shows a spinner',
        (tester) async {
      final store = _store()
        ..loading = true
        ..hasLoaded = false;
      // The spinner never settles.
      await _pump(tester, store, settle: false);
      expect(find.byKey(const ValueKey('energy-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('energy-hero')), findsNothing);
      // The way back is there while it loads.
      expect(find.byTooltip('Back'), findsOneWidget);

      store.change(() {
        store.loading = false;
        store.hasLoaded = true;
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('energy-loading')), findsNothing);
      expect(find.byKey(const ValueKey('energy-hero')), findsOneWidget);
    });

    testWidgets('a refresh with a cached balance keeps the page',
        (tester) async {
      final store = _store()..loading = true;
      await _pump(tester, store);
      expect(find.byKey(const ValueKey('energy-loading')), findsNothing);
      expect(find.byKey(const ValueKey('energy-hero')), findsOneWidget);
    });

    testWidgets('How Atomic Energy works reopens the intro', (tester) async {
      await _pump(tester, _store());
      final how = find.text('How Atomic Energy works');
      await _reveal(tester, how);
      await tester.tap(how);
      await tester.pumpAndSettle();
      expect(find.text('Energy intro route'), findsOneWidget);
    });

    testWidgets('the back button leaves the page', (tester) async {
      _view(tester, 412, 915);
      final store = _store();
      final notes = FakeNotesSource();
      addTearDown(notes.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: AtomicTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => EnergyPage(store: store, notes: notes))),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('energy-hero')), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('energy-hero')), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('the header shows the title once the large one scrolls away',
        (tester) async {
      await _pump(tester, _store(), height: 700);

      AtomicPageHeader header() =>
          tester.widget<AtomicPageHeader>(find.byType(AtomicPageHeader));
      expect(header().title, 'Atomic Energy');
      expect(header().showTitle, isFalse);
      expect(find.text('Atomic Energy'), findsNWidgets(2));

      await tester.drag(_list, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(header().showTitle, isTrue);

      await tester.drag(_list, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(header().showTitle, isFalse);
    });

    for (final (name, theme) in [
      ('light', AtomicTheme.light),
      ('dark', AtomicTheme.dark),
    ]) {
      for (final direction in TextDirection.values) {
        testWidgets(
            'fits 320 dp at 2.0 text ($name, ${direction.name}), down to the '
            'last row, with its sheets and dialog', (tester) async {
          await _pump(
              tester,
              _store(energy: 120, details: _details(cursor: 'next'), history: [
                ..._history,
                for (var i = 0; i < 6; i++)
                  _tx('x$i', energy: -120, coins: 30, note: 'Sync $i'),
              ]),
              theme: theme,
              width: 320,
              height: 640,
              textScale: 2,
              direction: direction);
          expect(tester.takeException(), isNull);

          final toggle = find.byKey(const ValueKey('energy-credit-batches'));
          await _reveal(tester, toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          for (var i = 0; i < 30; i++) {
            await tester.drag(_list, const Offset(0, -400));
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('How Atomic Energy works'), findsOneWidget);

          // The tier row scrolls sideways to its last card.
          final tiers = find.byKey(const ValueKey('energy-tiers'));
          await _revealUp(tester, tiers);
          await tester.drag(
              tiers, Offset(direction == TextDirection.ltr ? -2000 : 2000, 0));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // The raise dialog, the convert sheet and the coin store fit too.
          final raise = find.byKey(const ValueKey('energy-raise-limit'));
          await _reveal(tester, raise);
          await tester.tap(raise);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Cancel'));
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          final getCoins = find.byKey(const ValueKey('energy-get-coins'));
          await _revealUp(tester, getCoins);
          await tester.tap(getCoins);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final notNow = find.text('Not now');
          await tester.ensureVisible(notNow);
          await tester.pumpAndSettle();
          await tester.tap(notNow);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the convert sheet fits 320 dp at 2.0 text', (tester) async {
      await _pump(tester, _store(energy: 0, coins: 99),
          width: 320, height: 640, textScale: 2);
      final convert = find.byKey(const ValueKey('energy-convert'));
      await _reveal(tester, convert);
      await tester.tap(convert);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final confirm = find.byKey(const ValueKey('energy-convert-confirm'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      expect(confirm.hitTestable(), findsOneWidget);
    });

    testWidgets('targets are at least 48 dp', (tester) async {
      await _pump(tester, _store(details: _details(cursor: 'next')));

      final targets = [
        find.byTooltip('Back'),
        find.byKey(const ValueKey('energy-get-coins')),
        find.byKey(const ValueKey('energy-convert')),
        find.byKey(const ValueKey('energy-retry-conversion')),
        find.byKey(const ValueKey('energy-raise-limit')),
        find.byKey(const ValueKey('energy-credit-batches')),
        find.byTooltip('Refresh activity'),
        find.byKey(const ValueKey('energy-how-it-works')),
      ];
      for (final finder in targets) {
        await _reveal(tester, finder);
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
      }

      await _revealUp(tester, find.byKey(const ValueKey('energy-convert')));
      await tester.tap(find.byKey(const ValueKey('energy-convert')));
      await tester.pumpAndSettle();
      for (final finder in [
        find.byTooltip('Fewer coins'),
        find.byTooltip('More coins'),
        find.byKey(const ValueKey('energy-convert-confirm')),
      ]) {
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
      }
    });

    testWidgets('screen readers hear the balance, tiers and controls',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _store(), height: 2400);

      for (final label in [
        'Back',
        'Atomic energy, 110 of 120',
        'Energy level',
        'Get coins',
        'Convert',
        'Retry unconfirmed conversion',
        'Tachyon. 30 notes. Current',
        'Antimatter. 40 notes. 10 coins',
        'Strangelet. 100 notes. 30 coins',
        'Become Antimatter · 10 coins',
        'Refresh activity',
        'How Atomic Energy works',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(tester.getSemantics(find.byKey(const ValueKey('energy-bar'))),
          matchesSemantics(label: 'Energy level', value: '110 of 120'));
      // One activity row is one node: what, when and how much.
      expect(
          find.bySemanticsLabel(
              RegExp(r'^Instant sync\n2026-11-10 08:00\n−10 energy$')),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets('reduced motion shows everything at once', (tester) async {
      await _pump(tester, _store(), disableAnimations: true);
      // _pump settles; rebuild from scratch to see the first frame.
      final notes = FakeNotesSource();
      addTearDown(notes.dispose);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(
        disableAnimations: true,
        home: EnergyPage(store: _store(), notes: notes),
      ));
      await tester.pump();

      for (final opacity in tester.widgetList<FadeTransition>(find.ancestor(
          of: find.byKey(const ValueKey('energy-hero')),
          matching: find.byType(FadeTransition)))) {
        expect(opacity.opacity.value, 1);
      }
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('without reduced motion the blocks rise and the balance rolls',
        (tester) async {
      _view(tester, 412, 915);
      final notes = FakeNotesSource();
      addTearDown(notes.dispose);
      await tester
          .pumpWidget(_app(home: EnergyPage(store: _store(), notes: notes)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      Iterable<double> fades() => tester
          .widgetList<FadeTransition>(find.ancestor(
              of: find.byKey(const ValueKey('energy-hero')),
              matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value);
      expect(fades().any((v) => v < 1), isTrue);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(fades().every((v) => v == 1), isTrue);
    });
  });

  group('popup', () {
    setUp(() => EnergyService.instance.debugSet(
          wallet: const Wallet(
              coins: 7, energy: 60, energyCap: 120, lastDailyGrantAt: null),
          limits: const EnergyLimits(),
        ));
    tearDown(() async {
      EnergyService.instance.debugSet(wallet: Wallet.empty);
      await NoteQuota.reset();
    });

    Future<void> open(
      WidgetTester tester, {
      ThemeData? theme,
      double width = 412,
      double height = 915,
      double textScale = 1,
      TextDirection direction = TextDirection.ltr,
      bool disableAnimations = false,
    }) async {
      _view(tester, width, height);
      await tester.pumpWidget(_app(
        theme: theme,
        textScale: textScale,
        direction: direction,
        disableAnimations: disableAnimations,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showEnergyPopup(context),
                child: const Text('long-press stand-in'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('long-press stand-in'));
      await tester.pumpAndSettle();
    }

    testWidgets('a centred card with energy, coins, Open energy and Dismiss',
        (tester) async {
      await open(tester);

      final card = find.byKey(const ValueKey('energy-popup'));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.byType(AtomicCard)),
          findsOneWidget);
      expect(tester.getCenter(card).dx, closeTo(412 / 2, 0.5));
      expect(find.text('60 / 120'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(
          tester
              .widget<ProgressBar>(
                  find.descendant(of: card, matching: find.byType(ProgressBar)))
              .value,
          closeTo(0.5, 1e-9));
      final openButton = tester.widget<AtomicButton>(
          find.byKey(const ValueKey('energy-popup-open')));
      final dismiss = tester.widget<AtomicButton>(
          find.byKey(const ValueKey('energy-popup-dismiss')));
      expect(openButton.label, 'Open energy');
      expect(openButton.variant, AtomicButtonVariant.primary);
      expect(dismiss.label, 'Dismiss');
      expect(dismiss.variant, AtomicButtonVariant.text);
    });

    testWidgets('Dismiss closes it', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('energy-popup-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('energy-popup')), findsNothing);
      expect(find.text('Energy page route'), findsNothing);
    });

    testWidgets('a tap outside closes it', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('energy-popup')), findsNothing);
    });

    testWidgets('Open energy closes it and opens the Energy page',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('energy-popup-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('energy-popup')), findsNothing);
      expect(find.text('Energy page route'), findsOneWidget);
      // Back returns to where the popup was opened, not to the popup.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('long-press stand-in'), findsOneWidget);
      expect(find.byKey(const ValueKey('energy-popup')), findsNothing);
    });

    testWidgets('it follows the balance while open', (tester) async {
      await open(tester);
      EnergyService.instance.debugSet(
          wallet: const Wallet(
              coins: 3, energy: 90, energyCap: 120, lastDailyGrantAt: null));
      await tester.pumpAndSettle();
      expect(find.text('90 / 120'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('it scales in, and only fades under reduced motion',
        (tester) async {
      await open(tester);
      expect(
          find.ancestor(
              of: find.byKey(const ValueKey('energy-popup')),
              matching: find.byType(ScaleTransition)),
          findsWidgets);
      await tester.tap(find.byKey(const ValueKey('energy-popup-dismiss')));
      await tester.pumpAndSettle();

      await open(tester, disableAnimations: true);
      expect(
          find.ancestor(
              of: find.byKey(const ValueKey('energy-popup')),
              matching: find.byType(ScaleTransition)),
          findsNothing);
      expect(find.byKey(const ValueKey('energy-popup')), findsOneWidget);
    });

    testWidgets('screen readers hear energy, coins and both actions',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester);
      expect(find.bySemanticsLabel('Atomic energy, 60 of 120'), findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp(r'^Atomic coins\n7$')), findsOneWidget);
      expect(find.bySemanticsLabel('Open energy'), findsOneWidget);
      expect(find.bySemanticsLabel('Dismiss'), findsWidgets);
      for (final key in ['energy-popup-open', 'energy-popup-dismiss']) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
      }
      semantics.dispose();
    });

    for (final (name, theme) in [
      ('light', AtomicTheme.light),
      ('dark', AtomicTheme.dark),
    ]) {
      for (final direction in TextDirection.values) {
        testWidgets('fits 320 dp at 2.0 text ($name, ${direction.name})',
            (tester) async {
          EnergyService.instance.debugSet(
              wallet: const Wallet(
                  coins: 999,
                  energy: 120,
                  energyCap: 120,
                  lastDailyGrantAt: null));
          await open(tester,
              theme: theme,
              width: 320,
              height: 640,
              textScale: 2,
              direction: direction);
          expect(tester.takeException(), isNull);
          final openButton = find.byKey(const ValueKey('energy-popup-open'));
          await tester.ensureVisible(openButton);
          await tester.pumpAndSettle();
          expect(openButton.hitTestable(), findsOneWidget);
          await tester.tap(openButton);
          await tester.pumpAndSettle();
          expect(find.text('Energy page route'), findsOneWidget);
        });
      }
    }
  });
}
