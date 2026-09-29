// Note capacity: the Server decides the limit, its tiers and their prices; the App shows it
// and offers the next one. The purchase itself is a Server call and is tested there; these
// check what the App does with the numbers it is given.

import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/note_quota.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/page/endpage/energy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Tall on purpose: the whole screen is on view, so nothing has to be scrolled to.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _wallet({int coins = 30, int noteLimit = 30}) {
  EnergyService.instance.debugSet(
    wallet: Wallet(
      coins: coins,
      energy: 50,
      energyCap: 120,
      lastDailyGrantAt: null,
      noteLimit: noteLimit,
    ),
    limits: const EnergyLimits(),
  );
}

void main() {
  tearDown(() async {
    EnergyService.instance.debugSet(wallet: Wallet.empty);
    await NoteQuota.reset();
  });

  group('what the Server sends', () {
    test('the wallet carries the note limit, 30 when it is absent', () {
      expect(Wallet.fromMap(const {'coins': 1, 'note_limit': 40}).noteLimit, 40);
      expect(Wallet.fromMap(const {'coins': 1}).noteLimit, 30);
    });

    test('the limits carry the tiers, their prices and the ceiling', () {
      final l = EnergyLimits.fromMap(const {
        'note_limit_free': 30,
        'note_limit_ceiling': 100,
        'note_limit_tiers': [
          {'limit': 30, 'name': 'Tachyon', 'cost_coins': 0},
          {'limit': 40, 'name': 'Antimatter', 'cost_coins': 10},
          {'limit': 50, 'name': 'Monopole', 'cost_coins': 20},
          {'limit': 100, 'name': 'Strangelet', 'cost_coins': 30},
        ],
        'sync_standard_cost': 5,
        'sync_instant_cost': 10,
        'sync_standard_interval_seconds': 3600,
      });
      expect([l.noteLimitFree, l.noteLimitCeiling], [30, 100]);
      expect(l.noteLimitTiers.map((t) => t.limit), [30, 40, 50, 100]);
      expect(l.noteLimitTiers.map((t) => t.name),
          ['Tachyon', 'Antimatter', 'Monopole', 'Strangelet']);
      expect(l.noteLimitTiers.map((t) => t.costCoins), [0, 10, 20, 30]);
      expect([l.syncStandardCost, l.syncInstantCost], [5, 10]);
      expect(l.syncStandardIntervalSeconds, 3600);
    });

    test('a missing field falls back to the defaults', () {
      final l = EnergyLimits.fromMap(const {});
      expect(l.noteLimitCeiling, 100);
      expect(l.noteLimitTiers.last.name, 'Strangelet');
      expect(l.syncInstantCost, 10);
    });
  });

  group('the next tier', () {
    test('goes 30, 40, 50, 100 and stops at the ceiling', () {
      final steps = <int>[];
      for (final limit in [30, 40, 50, 100]) {
        _wallet(noteLimit: limit);
        steps.add(EnergyService.instance.nextNoteLimit);
      }
      expect(steps, [40, 50, 100, 100]);
      expect(EnergyService.instance.canRaiseNoteLimit, isFalse);
    });

    test('the last tier is Strangelet and costs more than the others', () {
      _wallet(noteLimit: 50);
      final tier = EnergyService.instance.nextTier;
      expect(tier, const NoteLimitTier(limit: 100, name: 'Strangelet', costCoins: 30));
    });

    test('the first tier needs 10 coins to become Antimatter', () {
      _wallet(coins: 9);
      expect(EnergyService.instance.canAffordNoteLimit, isFalse);
      _wallet(coins: 10);
      expect(EnergyService.instance.canAffordNoteLimit, isTrue);
    });

    test('the note quota follows the wallet', () {
      _wallet(noteLimit: 40);
      expect(NoteQuota.limit, 40);
    });

    test('the notes screen hears about a new limit at once', () {
      int heard = 0;
      void listener() => heard++;
      NotesRepository.instance.addListener(listener);
      addTearDown(() => NotesRepository.instance.removeListener(listener));

      _wallet(noteLimit: 40);
      expect(NotesRepository.instance.usageLabel, '0 / 40');
      expect(heard, 1);
      // The same limit again is not news.
      _wallet(noteLimit: 40);
      expect(heard, 1);
    });
  });

  group('Atomic Energy screen', () {
    Future<void> open(WidgetTester tester) async {
      _phone(tester);
      await tester.pumpWidget(const MaterialApp(home: EnergyPage()));
      await tester.pump();
    }

    testWidgets('shows the four tiers and offers the next one', (tester) async {
      _wallet(noteLimit: 30);
      await open(tester);

      for (final v in [30, 40, 50, 100]) {
        expect(find.byKey(ValueKey('capacity-$v')), findsOneWidget, reason: '$v');
      }
      // TACHYON is also the current-tier header label, so it appears twice.
      for (final name in ['TACHYON', 'ANTIMATTER', 'MONOPOLE', 'STRANGELET']) {
        expect(find.text(name), findsWidgets, reason: name);
      }
      expect(find.text('0 of 30 notes used'), findsOneWidget);
      expect(find.text('BECOME ANTIMATTER  ·  10 COINS'), findsOneWidget);
    });

    testWidgets('asks before spending coins', (tester) async {
      _wallet();
      await open(tester);

      await tester.tap(find.text('BECOME ANTIMATTER  ·  10 COINS'));
      await tester.pumpAndSettle();
      expect(
        find.text('Spend 10 coins to become Antimatter and raise your note limit '
            'from 30 to 40?'),
        findsOneWidget,
      );

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(EnergyService.instance.noteLimit, 30);
      expect(EnergyService.instance.coins, 30);
    });

    testWidgets('says what is missing when there are too few coins',
        (tester) async {
      _wallet(coins: 2);
      await open(tester);

      await tester.tap(find.text('BECOME ANTIMATTER  ·  10 COINS'));
      await tester.pump();
      expect(find.text('Becoming Antimatter costs 10 coins. You have 2.'),
          findsOneWidget);
    });

    testWidgets('offers nothing at the ceiling', (tester) async {
      _wallet(noteLimit: 100);
      await open(tester);

      expect(find.text('This is the most notes an account can hold.'),
          findsOneWidget);
      expect(find.textContaining('BECOME'), findsNothing);
    });
  });
}
