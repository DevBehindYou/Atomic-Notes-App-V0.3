import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/mascot/mascot_preferences.dart';
import 'package:atomic_notes/mascot/hive_mascot_preferences.dart';
import 'package:hive_ce/hive.dart';

void main() {
  test('defaults and copy preserve a known mascot and strict version', () {
    final defaults = MascotPreferences.defaults();
    expect(defaults.toMap(), {
      'schemaVersion': 1,
      'selectedId': '061-cubie',
      'animationsEnabled': true,
    });
    expect(
        defaults.copyWith(animationsEnabled: false).animationsEnabled, false);
    expect(() => MascotPreferences(selectedId: 'unknown'), throwsArgumentError);
    expect(() => MascotPreferences(schemaVersion: 2, selectedId: '061-cubie'),
        throwsArgumentError);
  });
  test('codec accepts strict v1 and preserves supported values', () {
    final decoded = MascotPreferencesCodec.decode({
      'schemaVersion': 1,
      'selectedId': '061-cubie',
      'animationsEnabled': false
    });
    expect(decoded.kind, MascotPreferenceReadKind.valid);
    expect(decoded.value!.animationsEnabled, false);
  });
  test('missing, malformed and future schemas are distinguished', () {
    expect(MascotPreferencesCodec.decode(null).kind,
        MascotPreferenceReadKind.missing);
    for (final value in [
      false,
      {},
      {'schemaVersion': 1, 'selectedId': 'unknown', 'animationsEnabled': true},
      {'schemaVersion': 1, 'selectedId': '061-cubie', 'animationsEnabled': 1},
      {
        'schemaVersion': 1.0,
        'selectedId': '061-cubie',
        'animationsEnabled': true
      }
    ]) {
      expect(MascotPreferencesCodec.decode(value).kind,
          MascotPreferenceReadKind.malformed);
    }
    expect(MascotPreferencesCodec.decode({'schemaVersion': 2}).kind,
        MascotPreferenceReadKind.futureVersion);
  });

  test('Hive round trip survives reopening and leaves other boxes alone',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('mascot-pref-test-');
    try {
      Hive.init(directory.path);
      final auth = await Hive.openBox<dynamic>('authBox');
      await auth.put('sentinel', 'untouched');
      var store = HiveMascotPreferencesStore.openBox(
        () => Hive.openBox<dynamic>(HiveMascotPreferencesStore.boxName),
      );
      expect((await store.read()).kind, MascotPreferenceReadKind.missing);
      final value = MascotPreferences(
        selectedId: '022-antimatter',
        animationsEnabled: false,
      );
      await store.write(value);
      await store.close();

      store = HiveMascotPreferencesStore.openBox(
        () => Hive.openBox<dynamic>(HiveMascotPreferencesStore.boxName),
      );
      expect((await store.read()).value, value);
      expect(auth.get('sentinel'), 'untouched');
      await store.close();
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

  test('future version stays untouched by a read and close', () async {
    final directory =
        await Directory.systemTemp.createTemp('mascot-future-test-');
    try {
      Hive.init(directory.path);
      final box =
          await Hive.openBox<dynamic>(HiveMascotPreferencesStore.boxName);
      final raw = {'schemaVersion': 2, 'selectedId': 'future-character'};
      await box.put(HiveMascotPreferencesStore.configKey, raw);
      final store = HiveMascotPreferencesStore.box(box);
      expect((await store.read()).kind, MascotPreferenceReadKind.futureVersion);
      await store.close();
      expect(box.isOpen, isTrue);
      expect(box.get(HiveMascotPreferencesStore.configKey), raw);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
  test('direct store write cannot replace a future schema record', () async {
    final directory =
        await Directory.systemTemp.createTemp('mascot-future-write-');
    try {
      Hive.init(directory.path);
      final box =
          await Hive.openBox<dynamic>(HiveMascotPreferencesStore.boxName);
      final raw = {'schemaVersion': 2, 'selectedId': 'future-character'};
      await box.put(HiveMascotPreferencesStore.configKey, raw);
      final store = HiveMascotPreferencesStore.box(box);
      await expectLater(
          store.write(MascotPreferences.defaults()), throwsStateError);
      expect(box.get(HiveMascotPreferencesStore.configKey), raw);
      await store.close();
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

  test('owned box closes after queued write and rejects new writes', () async {
    final directory =
        await Directory.systemTemp.createTemp('mascot-close-test-');
    try {
      Hive.init(directory.path);
      final opener = Completer<Box<dynamic>>();
      final store = HiveMascotPreferencesStore.openBox(() => opener.future);
      final value = MascotPreferences.defaults();
      final pending = store.write(value);
      final closing = store.close();
      expect(() => store.write(value), throwsStateError);
      final box =
          await Hive.openBox<dynamic>(HiveMascotPreferencesStore.boxName);
      opener.complete(box);
      await pending;
      await closing;
      expect(box.isOpen, isFalse);
      final reopened =
          await Hive.openBox<dynamic>(HiveMascotPreferencesStore.boxName);
      expect(
          MascotPreferencesCodec.decode(
                  reopened.get(HiveMascotPreferencesStore.configKey))
              .value,
          value);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
