import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/mascot/mascot_catalog.dart';
import 'package:atomic_notes/mascot/mascot_preferences.dart';
import 'package:atomic_notes/mascot/mascot_cubit.dart';

class Store implements MascotPreferencesStore {
  final readResult = Completer<MascotPreferenceRead>();
  final writes = <MascotPreferences>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<MascotPreferenceRead> read() => readResult.future;
  @override
  Future<void> write(MascotPreferences value) async {
    writes.add(value);
    await gate?.future;
    if (fail) throw StateError('private data');
  }
}

class RetryingReadStore extends Store {
  int attempts = 0;
  @override
  Future<MascotPreferenceRead> read() async {
    attempts++;
    if (attempts == 1) throw StateError('private data');
    return const MascotPreferenceRead.missing();
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  test('slow A then B then C persists latest intent with serialized coalescing',
      () async {
    final store = Store()
      ..readResult.complete(const MascotPreferenceRead.missing());
    final cubit = MascotCubit(store);
    await cubit.load();
    final ids = MascotCatalog.all.map((e) => e.id).take(4).toList();
    store.gate = Completer<void>();
    cubit.selectMascot(ids[1]);
    cubit.selectMascot(ids[2]);
    cubit.selectMascot(ids[3]);
    expect(store.writes.length, 1);
    store.gate!.complete();
    await tick();
    await tick();
    expect(store.writes.map((e) => e.selectedId), [ids[1], ids[3]]);
    expect(cubit.state.persisted!.selectedId, ids[3]);
    await cubit.close();
  });
  test('late startup read cannot revert a selection', () async {
    final store = Store();
    final cubit = MascotCubit(store);
    final loading = cubit.load();
    final id = MascotCatalog.all.last.id;
    cubit.selectMascot(id);
    expect(store.writes, isEmpty);
    store.readResult
        .complete(MascotPreferenceRead.valid(MascotPreferences.defaults()));
    await loading;
    await tick();
    expect(cubit.state.desired.selectedId, id);
    expect(store.writes.single.selectedId, id);
    await cubit.close();
  });
  test(
      'explicit default selection during load survives an older saved favorite',
      () async {
    final store = Store();
    final cubit = MascotCubit(store);
    final loading = cubit.load();
    cubit.selectMascot(MascotCatalog.defaultId);
    store.readResult.complete(MascotPreferenceRead.valid(MascotPreferences(
      selectedId: '022-antimatter',
      animationsEnabled: false,
    )));
    await loading;
    await tick();
    expect(cubit.state.desired.selectedId, MascotCatalog.defaultId);
    expect(cubit.state.desired.animationsEnabled, false);
    expect(store.writes.single.selectedId, MascotCatalog.defaultId);
    expect(store.writes.single.animationsEnabled, false);
    await cubit.close();
  });
  test('explicit default motion during load survives saved disabled motion',
      () async {
    final store = Store();
    final cubit = MascotCubit(store);
    final loading = cubit.load();
    cubit.setAnimationsEnabled(true);
    store.readResult.complete(MascotPreferenceRead.valid(MascotPreferences(
      selectedId: '022-antimatter',
      animationsEnabled: false,
    )));
    await loading;
    await tick();
    expect(cubit.state.desired.selectedId, '022-antimatter');
    expect(cubit.state.desired.animationsEnabled, true);
    expect(store.writes.single.selectedId, '022-antimatter');
    expect(store.writes.single.animationsEnabled, true);
    await cubit.close();
  });
  test('pre-read favorite change preserves saved motion setting', () async {
    final store = Store();
    final cubit = MascotCubit(store);
    final loading = cubit.load();
    cubit.selectMascot('038-ollie');
    store.readResult.complete(MascotPreferenceRead.valid(MascotPreferences(
      selectedId: '022-antimatter',
      animationsEnabled: false,
    )));
    await loading;
    await tick();
    expect(cubit.state.desired.selectedId, '038-ollie');
    expect(cubit.state.desired.animationsEnabled, false);
    expect(store.writes.single.animationsEnabled, false);
    await cubit.close();
  });
  test('pre-read motion change preserves saved favorite', () async {
    final store = Store();
    final cubit = MascotCubit(store);
    final loading = cubit.load();
    cubit.setAnimationsEnabled(false);
    store.readResult.complete(MascotPreferenceRead.valid(MascotPreferences(
      selectedId: '022-antimatter',
      animationsEnabled: true,
    )));
    await loading;
    await tick();
    expect(cubit.state.desired.selectedId, '022-antimatter');
    expect(cubit.state.desired.animationsEnabled, false);
    expect(store.writes.single.selectedId, '022-antimatter');
    await cubit.close();
  });
  test('write failure keeps desired and retry saves it', () async {
    final store = Store()
      ..readResult.complete(const MascotPreferenceRead.missing())
      ..fail = true;
    final cubit = MascotCubit(store);
    await cubit.load();
    cubit.setAnimationsEnabled(false);
    await tick();
    expect(cubit.state.saveState, MascotSaveState.error);
    expect(cubit.state.persisted, isNull);
    store.fail = false;
    cubit.retrySave();
    await tick();
    expect(cubit.state.persisted!.animationsEnabled, false);
    await cubit.close();
  });
  test('future versions preserve record even after selection and retry',
      () async {
    final store = Store()
      ..readResult.complete(const MascotPreferenceRead.futureVersion());
    final cubit = MascotCubit(store);
    await cubit.load();
    cubit.selectMascot(MascotCatalog.all.last.id);
    cubit.retrySave();
    await tick();
    expect(cubit.state.saveState, MascotSaveState.readOnly);
    expect(cubit.state.desired, MascotPreferences.defaults());
    expect(store.writes, isEmpty);
    await cubit.close();
  });
  test('late future schema read discards provisional selection', () async {
    final store = Store();
    final cubit = MascotCubit(store);
    final loading = cubit.load();
    cubit.selectMascot(MascotCatalog.all.last.id);
    store.readResult.complete(const MascotPreferenceRead.futureVersion());
    await loading;
    expect(cubit.state.desired, MascotPreferences.defaults());
    expect(cubit.state.saveState, MascotSaveState.readOnly);
    expect(store.writes, isEmpty);
    await cubit.close();
  });
  test('read failure blocks writing until successful reread', () async {
    final store = Store()..readResult.completeError(StateError('private'));
    final cubit = MascotCubit(store);
    await cubit.load();
    cubit.setAnimationsEnabled(false);
    await tick();
    expect(store.writes, isEmpty);
    expect(cubit.state.errorCode, 'read_failed');
    await cubit.close();
  });
  test('read retry writes the latest user choice only after a successful read',
      () async {
    final store = RetryingReadStore();
    final cubit = MascotCubit(store);
    await cubit.load();
    cubit.setAnimationsEnabled(false);
    expect(store.writes, isEmpty);
    expect(cubit.state.errorCode, 'read_failed');
    cubit.retrySave();
    await tick();
    expect(store.attempts, 2);
    expect(store.writes.single.animationsEnabled, false);
    expect(cubit.state.persisted, cubit.state.desired);
    await cubit.close();
  });
  test('closing during a write stops later writes and emissions', () async {
    final store = Store()
      ..readResult.complete(const MascotPreferenceRead.missing());
    final cubit = MascotCubit(store);
    await cubit.load();
    store.gate = Completer<void>();
    final emitted = <MascotState>[];
    final subscription = cubit.stream.listen(emitted.add);
    cubit.setAnimationsEnabled(false);
    await cubit.close();
    final afterClose = emitted.length;
    store.gate!.complete();
    await tick();
    expect(store.writes.length, 1);
    expect(emitted.length, afterClose);
    await subscription.cancel();
  });
  test('malformed record uses defaults and writes only after user choice',
      () async {
    final store = Store()
      ..readResult.complete(const MascotPreferenceRead.malformed());
    final cubit = MascotCubit(store);
    await cubit.load();
    expect(cubit.state.desired, MascotPreferences.defaults());
    expect(cubit.state.errorCode, 'malformed_preferences');
    expect(store.writes, isEmpty);
    cubit.setAnimationsEnabled(false);
    await tick();
    expect(store.writes.single.animationsEnabled, false);
    await cubit.close();
  });
}
