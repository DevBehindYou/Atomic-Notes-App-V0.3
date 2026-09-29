// The state behind the Atomic Energy screen and popup. The balances are a fake in memory, so
// these need neither the Server nor the network.

import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/state/energy/energy_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_energy_store.dart';
import 'support/fake_notes_source.dart';

Wallet _wallet({int coins = 12, int energy = 60, int noteLimit = 30}) => Wallet(
    coins: coins,
    energy: energy,
    energyCap: 120,
    lastDailyGrantAt: null,
    noteLimit: noteLimit);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('what the screen shows', () {
    test('starts from the store', () {
      final cubit = EnergyCubit(store: FakeEnergyStore());
      addTearDown(cubit.close);
      expect(cubit.state.coins, 12);
      expect(cubit.state.energy, 60);
      expect(cubit.state.energyCap, 120);
      expect(cubit.state.noteLimit, 30);
      expect(cubit.state.hasLoaded, isTrue);
    });

    test('counts the notes in use when it is given the notes', () {
      final notes = FakeNotesSource(notes: [syncedNote('a'), syncedNote('b')]);
      final cubit = EnergyCubit(store: FakeEnergyStore(), notes: notes);
      addTearDown(cubit.close);
      expect(cubit.state.notesUsed, 2);
    });

    test('a popup with no notes store counts none', () {
      final cubit = EnergyCubit(store: FakeEnergyStore());
      addTearDown(cubit.close);
      expect(cubit.state.notesUsed, 0);
    });

    test('follows a balance that changes behind the screen', () async {
      final store = FakeEnergyStore();
      final cubit = EnergyCubit(store: store);
      addTearDown(cubit.close);

      store.change(() => store.wallet = _wallet(energy: 50));
      await _settle();

      expect(cubit.state.energy, 50);
    });

    test('follows the notes in use', () async {
      final notes = FakeNotesSource(notes: [syncedNote('a')]);
      final cubit = EnergyCubit(store: FakeEnergyStore(), notes: notes);
      addTearDown(cubit.close);

      await notes.save(syncedNote('b'));
      await _settle();

      expect(cubit.state.notesUsed, 2);
    });

    test('shows a load in progress and its failure', () async {
      final store = FakeEnergyStore()..hasLoaded = false;
      final cubit = EnergyCubit(store: store);
      addTearDown(cubit.close);
      expect(cubit.state.hasLoaded, isFalse);

      store.change(() => store.loading = true);
      await _settle();
      expect(cubit.state.loading, isTrue);

      store.change(() {
        store.loading = false;
        store.error = 'You appear to be offline.';
      });
      await _settle();
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.error, 'You appear to be offline.');
    });

    test('a store that says nothing new emits nothing', () async {
      final store = FakeEnergyStore();
      final cubit = EnergyCubit(store: store);
      addTearDown(cubit.close);
      final seen = <EnergyState>[];
      final sub = cubit.stream.listen(seen.add);
      addTearDown(sub.cancel);

      store.poke();
      store.change(() => store.wallet = _wallet()); // a new object with the same numbers
      await _settle();

      expect(seen, isEmpty);
    });

    test('the activity list arrives with the balance', () async {
      final store = FakeEnergyStore();
      final cubit = EnergyCubit(store: store);
      addTearDown(cubit.close);
      final tx = EnergyTx(
        id: '1',
        kind: EnergyTxKind.spend,
        coinsDelta: 0,
        energyDelta: -10,
        resultingCoins: 12,
        resultingEnergy: 50,
        note: 'Instant sync',
        createdAt: DateTime.utc(2026, 9, 21),
      );

      store.change(() => store.history = [tx]);
      await _settle();

      expect(cubit.state.history, [tx]);
    });
  });

  group('note capacity', () {
    test('the next tier goes 30, 40, 50, 100 and stops at the ceiling', () {
      final steps = <int>[];
      for (final limit in [30, 40, 50, 100]) {
        final cubit = EnergyCubit(
            store: FakeEnergyStore(wallet: _wallet(noteLimit: limit)));
        addTearDown(cubit.close);
        steps.add(cubit.state.nextNoteLimit);
      }
      expect(steps, [40, 50, 100, 100]);
    });

    test('each tier is named after a particle, biggest at the top', () {
      final names = <String>{};
      for (final limit in [30, 40, 50]) {
        final cubit = EnergyCubit(
            store: FakeEnergyStore(wallet: _wallet(noteLimit: limit)));
        addTearDown(cubit.close);
        names.add(cubit.state.nextTier!.name);
      }
      expect(names, {'Antimatter', 'Monopole', 'Strangelet'});
    });

    test('the last tier costs more than the earlier ones', () {
      final cubit =
          EnergyCubit(store: FakeEnergyStore(wallet: _wallet(noteLimit: 50)));
      addTearDown(cubit.close);
      expect(cubit.state.nextTier, const NoteLimitTier(
          limit: 100, name: 'Strangelet', costCoins: 30));
    });

    test('nothing can be bought at the ceiling', () {
      final cubit = EnergyCubit(
          store: FakeEnergyStore(wallet: _wallet(noteLimit: 100)));
      addTearDown(cubit.close);
      expect(cubit.state.canRaiseNoteLimit, isFalse);
      expect(cubit.state.nextTier, isNull);
    });

    test('a step needs 10 coins', () {
      final poor = EnergyCubit(store: FakeEnergyStore(wallet: _wallet(coins: 9)));
      final enough =
          EnergyCubit(store: FakeEnergyStore(wallet: _wallet(coins: 10)));
      addTearDown(poor.close);
      addTearDown(enough.close);
      expect(poor.state.canAffordNoteLimit, isFalse);
      expect(enough.state.canAffordNoteLimit, isTrue);
    });

    test('buying a step raises the limit, takes the coins and reaches the state', () async {
      final store = FakeEnergyStore();
      final cubit = EnergyCubit(store: store);
      addTearDown(cubit.close);

      final error = await cubit.upgradeNoteLimit();
      await _settle();

      expect(error, isNull);
      expect(cubit.state.noteLimit, 40);
      expect(cubit.state.coins, 2);
      expect(store.upgrades, 1);
    });

    test('a purchase the store refuses answers with its message', () async {
      final cubit =
          EnergyCubit(store: FakeEnergyStore(wallet: _wallet(coins: 2)));
      addTearDown(cubit.close);
      expect(await cubit.upgradeNoteLimit(), 'Not enough Atomic Coins.');
      expect(cubit.state.noteLimit, 30);
    });
  });

  group('coins and refreshing', () {
    test('converting coins gives 40 energy each', () async {
      final store = FakeEnergyStore();
      final cubit = EnergyCubit(store: store);
      addTearDown(cubit.close);

      final error = await cubit.convertCoins(2);
      await _settle();

      expect(error, isNull);
      expect(cubit.state.coins, 10);
      expect(cubit.state.energy, 140);
      expect(store.converted, [2]);
    });

    test('more coins than there are is refused with the store\'s words', () async {
      final cubit = EnergyCubit(store: FakeEnergyStore());
      addTearDown(cubit.close);
      expect(await cubit.convertCoins(99), 'Not enough Atomic Coins.');
    });

    test('refresh asks the store to read again', () async {
      final store = FakeEnergyStore();
      final cubit = EnergyCubit(store: store);
      addTearDown(cubit.close);

      await cubit.refresh();

      expect(store.refreshCalls, 1);
    });

    test('a closed cubit stops listening to the balances and the notes', () async {
      final store = FakeEnergyStore();
      final notes = FakeNotesSource();
      final cubit = EnergyCubit(store: store, notes: notes);
      await cubit.close();

      // Would throw if the closed cubit still emitted.
      store.change(() => store.wallet = _wallet(energy: 1));
      notes.poke();
      await _settle();

      expect(cubit.isClosed, isTrue);
    });
  });
}
