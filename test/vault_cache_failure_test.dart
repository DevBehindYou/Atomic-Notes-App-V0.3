import 'dart:convert';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/security/vault_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _DeviceStore extends FlutterSecureStorage {
  _DeviceStore() : super();
  final values = <String, String>{
    'atomic_api_session_token': 'fixture-session',
    'atomic_api_user_id': 'fixture-user',
    'atomic_api_user_email': 'fixture@example.test',
  };
  bool failVaultReads = false;
  int vaultReads = 0;
  int writes = 0;
  int deletes = 0;
  @override
  Future<String?> read(
      {required String key,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (key.startsWith('atomic_vault_key_')) {
      vaultReads++;
      if (failVaultReads) {
        throw PlatformException(
            code: 'Exception encountered',
            message: 'read',
            details: 'javax.crypto.BadPaddingException: BAD_DECRYPT');
      }
    }
    return values[key];
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
    writes++;
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
    deletes++;
    values.remove(key);
  }

  @override
  Future<void> deleteAll(
      {IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    deletes++;
    values.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const entry = 'atomic_vault_key_fixture-user';
  final keyBytes = List<int>.generate(32, (index) => index);
  Future<Vault> vault(_DeviceStore store,
      {bool offline = false, bool configured = true}) async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/vault');
      if (offline) throw http.ClientException('fixture offline');
      return configured
          ? http.Response(jsonEncode({'encVersion': 1}), 200)
          : http.Response(jsonEncode({'error': 'vault_not_found'}), 404);
    });
    addTearDown(client.close);
    final api = ApiClient.forTest(
        client: client,
        storage: store,
        baseUrl: Uri.parse('https://fixture.invalid/api'));
    await api.init();
    return Vault.forTest(api: api, storage: store);
  }

  for (final offline in [false, true]) {
    test(
        'startup unreadable cached key stays locked without storage mutation (${offline ? 'offline' : 'online'})',
        () async {
      final store = _DeviceStore()..failVaultReads = true;
      store.values[entry] = 'fixture-unreadable-entry';
      final before = Map<String, String>.of(store.values);
      final subject = await vault(store, offline: offline);
      await subject.init();
      expect(subject.isLocked, isTrue);
      expect(subject.isUnlocked, isFalse);
      await expectLater(
          subject.encryptContent({'title': 'fixture'}), throwsStateError);
      expect(store.values, before);
      expect(store.writes, 0);
      expect(store.deletes, 0);
    });
  }

  test('startup malformed cached key stays locked without overwriting it',
      () async {
    final store = _DeviceStore();
    store.values[entry] = 'not valid base64!';
    final subject = await vault(store);
    await subject.init();
    expect(subject.isLocked, isTrue);
    expect(store.values[entry], 'not valid base64!');
    expect(store.writes, 0);
    expect(store.deletes, 0);
  });

  test('startup unavailable key can be retried without a destructive reset',
      () async {
    final store = _DeviceStore()..failVaultReads = true;
    store.values[entry] = base64Encode(keyBytes);
    final subject = await vault(store);
    await subject.init();
    expect(subject.isLocked, isTrue);
    store.failVaultReads = false;
    await subject.init();
    expect(subject.isUnlocked, isTrue);
    final payload = await VaultCrypto.sealJson(
        {'title': 'fixture retained note'}, SecretKey(keyBytes));
    expect(await subject.decryptContent(payload),
        {'title': 'fixture retained note'});
    expect(store.writes, 0);
    expect(store.deletes, 0);
  });

  test('startup healthy cached key still unlocks while offline', () async {
    final store = _DeviceStore();
    store.values[entry] = base64Encode(keyBytes);
    final subject = await vault(store, offline: true);
    await subject.init();
    expect(subject.isUnlocked, isTrue);
    expect(subject.isLocked, isFalse);
    expect(store.writes, 0);
    expect(store.deletes, 0);
  });

  test(
      'startup confirmed account without a vault does not read an unrelated broken cache',
      () async {
    final store = _DeviceStore()..failVaultReads = true;
    final subject = await vault(store, configured: false);
    await subject.init();
    expect(subject.isEnabled, isFalse);
    expect(subject.isLocked, isFalse);
    expect(store.vaultReads, 0);
  });
}
