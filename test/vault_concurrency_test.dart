import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/security/seed_phrase.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/security/vault_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Store extends FlutterSecureStorage {
  final values = <String, String>{
    'atomic_api_session_token': 'fixture-token',
    'atomic_api_user_id': 'fixture-user',
    'atomic_api_user_email': 'fixture@example.test',
  };
  int reads = 0, writes = 0, deletes = 0;
  Completer<void>? readGate, writeGate, deleteGate;
  bool failVaultWrites = false;

  @override
  Future<String?> read(
      {required String key,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    final value = values[key];
    if (key.startsWith('atomic_vault_key_')) {
      reads++;
      await readGate?.future;
    }
    return value;
  }

  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (key.startsWith('atomic_vault_key_')) {
      writes++;
      await writeGate?.future;
      if (failVaultWrites) throw StateError('fixture vault write failed');
    }
    if (value != null) values[key] = value;
  }

  @override
  Future<void> delete(
      {required String key,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (key.startsWith('atomic_vault_key_')) {
      deletes++;
      await deleteGate?.future;
    }
    values.remove(key);
  }
}

// Count and gate real Argon2 operations without changing production injection
// points. Fixtures use a stored legacy cost, never the user's device vault.
class _CountingCrypto extends DartCryptography {
  int calls = 0, active = 0, peak = 0;
  Completer<void>? gate;
  @override
  Argon2id argon2id(
          {required int memory,
          required int parallelism,
          required int iterations,
          required int hashLength}) =>
      _CountingArgon(this,
          memory: memory,
          iterations: iterations,
          parallelism: parallelism,
          hashLength: hashLength);
}

class _CountingArgon extends DartArgon2id {
  final _CountingCrypto counter;
  _CountingArgon(this.counter,
      {required super.memory,
      required super.iterations,
      required super.parallelism,
      required super.hashLength});
  @override
  Future<SecretKey> deriveKey(
      {required SecretKey secretKey,
      required List<int> nonce,
      List<int> optionalSecret = const [],
      List<int> associatedData = const []}) async {
    counter.calls++;
    counter.active++;
    if (counter.active > counter.peak) counter.peak = counter.active;
    try {
      await counter.gate?.future;
      return await super.deriveKey(
          secretKey: secretKey,
          nonce: nonce,
          optionalSecret: optionalSecret,
          associatedData: associatedData);
    } finally {
      counter.active--;
    }
  }
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 1000 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue, reason: 'fixture operation reached the gated stage');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const phrase = ['ocean', 'tiger', 'maple', 'copper'];
  const entry = 'atomic_vault_key_fixture-user';
  late _Store store;
  late ApiClient api;
  late Vault vault;
  late _CountingCrypto crypto;
  late Map<String, dynamic>? row;
  late Future<void> Function()? beforeGet;
  late int gets;

  setUp(() async {
    store = _Store();
    gets = 0;
    beforeGet = null;
    final key = await VaultCrypto.deriveKey(SeedPhrase.canonical(phrase),
        await VaultCrypto.saltForUser('fixture-user'),
        memory: 32, iterations: 1, parallelism: 1);
    row = {
      'verifier': await VaultCrypto.makeVerifier(key),
      'kdfMemory': 32,
      'kdfIterations': 1,
      'kdfParallelism': 1
    };
    final client = MockClient((request) async {
      expect(request.url.path, '/api/vault');
      gets++;
      await beforeGet?.call();
      return row == null
          ? http.Response('{"error":"vault_not_found"}', 404)
          : http.Response(jsonEncode(row), 200);
    });
    addTearDown(client.close);
    api = ApiClient.forTest(
        client: client,
        storage: store,
        baseUrl: Uri.parse('https://fixture.invalid/api'));
    await api.init();
    vault = Vault.forTest(api: api, storage: store);
    final original = Cryptography.instance;
    crypto = _CountingCrypto();
    Cryptography.instance = crypto;
    addTearDown(() => Cryptography.instance = original);
  });

  test('overlapping init shares one cloud read and one cache read', () async {
    final gate = Completer<void>();
    beforeGet = () => gate.future;
    final first = vault.init(), second = vault.init();
    await _until(() => gets > 0);
    gate.complete();
    await Future.wait([first, second]);
    expect(gets, 1);
    expect(store.reads, 1);
    await vault.init();
    expect(gets, 2, reason: 'completed init must not suppress a fresh refresh');
  });

  test('identical overlapping unlocks derive once and decrypt legacy notes',
      () async {
    final gate = Completer<void>();
    crypto.gate = gate;
    final first = vault.unlock(phrase);
    final second = vault.unlock([' OCEAN ', 'tiger', 'maple', 'copper']);
    await _until(() => crypto.calls > 0);
    gate.complete();
    expect(await Future.wait([first, second]), [true, true]);
    expect(crypto.calls, 1);
    expect(gets, 1);
    expect(store.writes, 1);
    final compatibleKey = await VaultCrypto.deriveKey(
        SeedPhrase.canonical(phrase),
        await VaultCrypto.saltForUser('fixture-user'),
        memory: 32,
        iterations: 1,
        parallelism: 1);
    final payload =
        await VaultCrypto.sealJson({'body': 'fixture note'}, compatibleKey);
    expect(await vault.decryptContent(payload), {'body': 'fixture note'});
  });

  test('different overlapping phrases do not allocate concurrent KDF work',
      () async {
    final gate = Completer<void>();
    crypto.gate = gate;
    final first = vault.unlock(phrase);
    await _until(() => crypto.calls == 1);
    final second = vault.unlock(['wrong', 'fixture', 'phrase']);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    gate.complete();
    expect(await Future.wait([first, second]), [true, false]);
    expect(crypto.calls, 2);
    expect(crypto.peak, 1);
  });

  test('locking while init reads the cache rejects the late key', () async {
    store.values[entry] = base64Encode(List<int>.filled(32, 7));
    final gate = Completer<void>();
    store.readGate = gate;
    final pending = vault.init();
    await _until(() => store.reads == 1);
    vault.lockMemory();
    gate.complete();
    await pending;
    expect(vault.isUnlocked, isFalse);
  });

  test('locking during a derivation prevents unlock and key caching', () async {
    final gate = Completer<void>();
    crypto.gate = gate;
    final pending = vault.unlock(phrase);
    await _until(() => crypto.calls == 1);
    await vault.lockThisDevice();
    gate.complete();
    expect(await pending, isFalse);
    expect(vault.isUnlocked, isFalse);
    expect(store.values[entry], isNull);
    expect(store.writes, 0);
  });

  test('locking during a cache write wins over the late write', () async {
    final gate = Completer<void>();
    store.writeGate = gate;
    final pending = vault.unlock(phrase);
    await _until(() => store.writes == 1);
    final locking = vault.lockThisDevice();
    gate.complete();
    await locking;
    expect(await pending, isFalse);
    expect(store.values[entry], isNull);
    expect(vault.isUnlocked, isFalse);
  });

  test('initializing during a device lock cannot restore its cached key',
      () async {
    store.values[entry] = base64Encode(List<int>.filled(32, 7));
    final gate = Completer<void>();
    store.deleteGate = gate;
    final locking = vault.lockThisDevice();
    await _until(() => store.deletes == 1);
    final initializing = vault.init();
    await _until(() => gets == 1);
    await Future<void>.delayed(Duration.zero);
    final readsBeforeDeletion = store.reads;
    gate.complete();
    await Future.wait([locking, initializing]);
    expect(readsBeforeDeletion, 0);
    expect(vault.isUnlocked, isFalse);
    expect(store.values[entry], isNull);
  });

  test('a late cache read cannot replace the verified in-memory key', () async {
    store.values[entry] = base64Encode(List<int>.filled(32, 7));
    final gate = Completer<void>();
    store.readGate = gate;
    final initializing = vault.init();
    await _until(() => store.reads == 1);
    expect(await vault.unlock(phrase), isTrue);
    final payload = await vault.encryptContent({'body': 'fixture note'});
    gate.complete();
    await initializing;
    expect(await vault.decryptContent(payload), {'body': 'fixture note'});
  });

  test('a failed cache write preserves the verified key and can be retried',
      () async {
    store.failVaultWrites = true;
    await expectLater(vault.unlock(phrase), throwsStateError);
    expect(vault.isUnlocked, isTrue);
    expect(store.values[entry], isNull);

    store.failVaultWrites = false;
    expect(await vault.unlock(phrase), isTrue);
    expect(store.values[entry], isNotNull);
  });

  for (final user in ['fixture-user', 'other-user']) {
    test('a new session for $user rejects a prior derivation', () async {
      final gate = Completer<void>();
      crypto.gate = gate;
      final pending = vault.unlock(phrase);
      await _until(() => crypto.calls == 1);
      store.values['atomic_api_user_id'] = user;
      store.values['atomic_api_session_token'] = 'replacement-fixture-token';
      await api.init();
      gate.complete();
      expect(await pending, isFalse);
      expect(vault.isUnlocked, isFalse);
      expect(store.writes, 0);
    });
  }
}
