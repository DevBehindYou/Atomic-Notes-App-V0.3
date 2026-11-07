import 'dart:io';

import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/profile/guest_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

const _guestId = '9a3f0c1e-5b7d-4e2a-8c6f-0123456789ab';
const _otherId = '1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d';

Note _note(String id, String title) => Note(id: id, title: title);

void main() {
  late Directory directory;
  late List<int> accountCacheBytes;

  File accountCacheFile() => File('${directory.path}/notesbox.hive');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-guest-');
    Hive.init(directory.path);
    // A signed-in account's cache, which guest code must never touch.
    final account = await Hive.openBox<dynamic>('notesBox');
    await account.put('__cache_owner__', 'account-user');
    await account.put('n1', {'id': 'n1', 'title': 'Account note'});
    await account.close();
    accountCacheBytes = await accountCacheFile().readAsBytes();
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<GuestProfileStore> restart(GuestProfileStore store) async {
    await store.close();
    await Hive.close();
    Hive.init(directory.path);
    return GuestProfileStore(newProfileId: () => fail('must reuse profile'));
  }

  test('first open creates a profile that survives a restart', () async {
    var store = GuestProfileStore(newProfileId: () => _guestId);
    final session = await store.open();
    expect([session.profileId, session.generation], [_guestId, 1]);
    await store.put(session, _note('a', 'Offline idea'));
    store = await restart(store);
    final again = await store.open();
    expect([again.profileId, again.generation], [_guestId, 1]);
    expect(store.notes(again).map((n) => n.title), ['Offline idea']);
  });

  test('concurrent opens share one profile', () async {
    var created = 0;
    final store = GuestProfileStore(newProfileId: () {
      created++;
      return _guestId;
    });
    final sessions = await Future.wait([store.open(), store.open()]);
    expect(created, 1);
    expect(sessions[0].profileId, sessions[1].profileId);
    final registry = Hive.box<dynamic>(GuestProfileStore.registryBox);
    expect(registry.keys, ['profile']);
  });

  test('unreadable metadata is reported, kept, and replaced only on request',
      () async {
    var store = GuestProfileStore(newProfileId: () => _guestId);
    final session = await store.open();
    await store.put(session, _note('a', 'Keep me'));
    store = await restart(store);
    final registry = await Hive.openBox<dynamic>(GuestProfileStore.registryBox);
    await registry
        .put('profile', {'v': 1, 'id': '../notesBox', 'generation': 1});

    final reopened = GuestProfileStore(newProfileId: () => _otherId);
    await expectLater(reopened.open(), throwsA(isA<GuestProfileCorrupt>()));
    expect(await Hive.boxExists(GuestProfileStore.notesBoxName(_guestId, 1)),
        isTrue,
        reason: 'notes are not removed');

    final recovered = await reopened.recover();
    expect(recovered.profileId, _otherId);
    final aside = registry.keys.where((k) => '$k'.startsWith('unreadable:'));
    expect(aside, hasLength(1));
    expect(registry.get(aside.single),
        {'v': 1, 'id': '../notesBox', 'generation': 1});
    expect(reopened.notes(recovered), isEmpty);
    expect(await Hive.boxExists(GuestProfileStore.notesBoxName(_guestId, 1)),
        isTrue,
        reason: 'recovery never deletes earlier guest notes');
  });

  test('reset ends old sessions and starts an empty generation', () async {
    final store = GuestProfileStore(newProfileId: () => _guestId);
    final first = await store.open();
    await store.put(first, _note('a', 'Old'));
    final second = await store.reset(first);
    expect(second.generation, 2);
    expect(store.notes(second), isEmpty);
    expect(() => store.notes(first), throwsA(isA<GuestSessionStale>()));
    await expectLater(store.put(first, _note('b', 'Late write')),
        throwsA(isA<GuestSessionStale>()));
    expect(await Hive.boxExists(GuestProfileStore.notesBoxName(_guestId, 1)),
        isFalse);
  });

  test('a reset interrupted after its fence never shows the old notes',
      () async {
    var store = GuestProfileStore(newProfileId: () => _guestId);
    final first = await store.open();
    await store.put(first, _note('a', 'Before reset'));
    store = await restart(store);
    // The crash: generation moved, old box not yet deleted.
    final registry = await Hive.openBox<dynamic>(GuestProfileStore.registryBox);
    await registry.put('profile', {'v': 1, 'id': _guestId, 'generation': 2});
    expect(await Hive.boxExists(GuestProfileStore.notesBoxName(_guestId, 1)),
        isTrue);
    final session = await GuestProfileStore().open();
    expect(session.generation, 2);
    expect(await Hive.boxExists(GuestProfileStore.notesBoxName(_guestId, 1)),
        isFalse,
        reason: 'the unreachable old generation is removed');
  });

  test('a session for another profile cannot read or write this one', () async {
    final storeA = GuestProfileStore(newProfileId: () => _guestId);
    final sessionA = await storeA.open();
    await storeA.put(sessionA, _note('a', 'Profile A'));
    // Profile A is replaced by profile B on this device.
    final registry = Hive.box<dynamic>(GuestProfileStore.registryBox);
    await registry.put('profile', 'corrupt');
    final storeB = GuestProfileStore(newProfileId: () => _otherId);
    final sessionB = await storeB.recover();
    await storeB.put(sessionB, _note('b', 'Profile B'));
    expect(() => storeA.notes(sessionA), throwsA(isA<GuestSessionStale>()));
    expect(() => storeB.notes(sessionA), throwsA(isA<GuestSessionStale>()));
    expect(storeB.notes(sessionB).map((n) => n.title), ['Profile B']);
  });

  test('the signed-in account cache is never opened or changed', () async {
    var store = GuestProfileStore(newProfileId: () => _guestId);
    var session = await store.open();
    expect(Hive.isBoxOpen('notesBox'), isFalse);
    await store.put(session, _note('a', 'Guest'));
    await store.remove(session, 'a');
    session = await store.reset(session);
    await store.put(session, _note('b', 'Guest again'));
    store = await restart(store);
    await store.open();
    expect(Hive.isBoxOpen('notesBox'), isFalse);
    await store.close();
    await Hive.close();
    expect(await accountCacheFile().readAsBytes(), accountCacheBytes,
        reason: 'account cache byte-preserved');
  });
}
