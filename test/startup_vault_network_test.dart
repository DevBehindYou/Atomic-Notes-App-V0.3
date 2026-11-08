import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/page/splash_screen.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _entry = 'atomic_vault_key_fixture-user';
final _keyBytes = List<int>.generate(32, (index) => index);

class _DeviceStore extends FlutterSecureStorage {
  _DeviceStore() : super();
  final values = <String, String>{
    'atomic_api_session_token': 'fixture-session',
    'atomic_api_user_id': 'fixture-user',
    'atomic_api_user_email': 'fixture@example.test',
  };
  int vaultReads = 0;
  bool failVaultReads = false;
  bool failDeletes = false;
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
      if (failVaultReads) throw Exception('fixture keystore read failure');
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
    if (failDeletes) throw Exception('fixture keystore delete failure');
    values.remove(key);
  }
}

enum _Answer { vault, none, offline }

/// The real ApiClient over a fake transport, so every logical vault check is a
/// counted HTTP request.
class _Cloud {
  _Cloud(this.store);
  final _DeviceStore store;
  int vaultRequests = 0;
  _Answer answer = _Answer.vault;
  Completer<void>? gate;
  late final ApiClient api;

  Future<ApiClient> open() async {
    final client = MockClient((request) async {
      // No expect() here: it can run inside tester.pump(), where flutter_test
      // rejects a nested guarded call and the request would fail spuriously.
      if (request.method != 'GET' || request.url.path != '/api/vault') {
        throw StateError('unexpected ${request.method} ${request.url.path}');
      }
      vaultRequests++;
      final wait = gate;
      if (wait != null) await wait.future;
      switch (answer) {
        case _Answer.vault:
          return http.Response(jsonEncode({'encVersion': 1}), 200);
        case _Answer.none:
          return http.Response(jsonEncode({'error': 'vault_not_found'}), 404);
        case _Answer.offline:
          throw http.ClientException('fixture offline');
      }
    });
    addTearDown(client.close);
    api = ApiClient.forTest(
        client: client,
        storage: store,
        baseUrl: Uri.parse('https://fixture.invalid/api'));
    await api.init();
    return api;
  }
}

/// The production splash services with only the account singletons replaced:
/// `initVault`, `vaultLocked` and `discardStartupVault` keep their production
/// bodies.
class _Startup extends SplashStartupServices {
  _Startup(this.vault, this.api, {this.foreignCache = false});
  @override
  final Vault vault;
  final ApiClient api;
  bool foreignCache;
  bool armed = false;
  @override
  bool get isSignedIn => api.isSignedIn;
  @override
  int get sessionRevision => api.sessionRevision;
  @override
  bool get hasForeignPendingCache => foreignCache;
  @override
  bool get twoFactorArmed => armed;
  @override
  Future<void> startNotes() => Completer<void>().future;
  @override
  void startAccountServices() {}
}

/// The base-revision (6de248b) splash body: an ordinary refresh.
class _OrdinaryStartup extends _Startup {
  _OrdinaryStartup(super.vault, super.api);
  @override
  Future<void> initVault() => vault.init();
}

void main() {
  late Directory directory;
  late Box<bool> auth;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic-startup-vault-');
    Hive.init(directory.path);
    auth = await Hive.openBox<bool>('authBox');
    await auth.put('hasSeenOnboarding', true);
  });
  tearDown(() async {
    Vault.startupHandoffMaxAge = const Duration(seconds: 30);
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> openSplash(WidgetTester tester, _Startup startup) async {
    await tester.pumpWidget(MaterialApp(
      home: SplashPage.forTest(startup: startup),
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        transitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) =>
            Scaffold(body: Text('Ready ${settings.name}')),
      ),
    ));
    await flush(tester);
  }

  Future<void> closeSplash(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  /// A signed-in returning device with an existing cloud vault and, by
  /// default, its cached key.
  Future<(_DeviceStore, _Cloud, Vault)> device(
      {bool cachedKey = true, String? cached}) async {
    final store = _DeviceStore();
    if (cachedKey) store.values[_entry] = cached ?? base64Encode(_keyBytes);
    final cloud = _Cloud(store);
    await cloud.open();
    return (store, cloud, Vault.forTest(api: cloud.api, storage: store));
  }

  group('baseline characterization', () {
    test('main vault step does not finish until the cloud vault check answers',
        () async {
      final (store, cloud, vault) = await device();
      cloud.gate = Completer<void>();

      var finished = false;
      // main() awaits this before NotesRepository.init() and runApp(). This
      // increment keeps that ordering, so the pre-frame wait remains.
      final step = vault.initAtStartup().whenComplete(() => finished = true);
      await pumpEventQueue();
      expect(cloud.vaultRequests, 1);
      expect(finished, isFalse, reason: 'first frame waits on the network');
      expect(vault.isUnlocked, isFalse);

      cloud.gate!.complete();
      await step;
      expect(finished, isTrue);
      expect(vault.isUnlocked, isTrue);
      expect(store.vaultReads, 1);
    });

    testWidgets('ordinary init at both sites still makes two vault requests',
        (tester) async {
      final (store, cloud, vault) = await device();
      await vault.init();
      await openSplash(tester, _OrdinaryStartup(vault, cloud.api));
      expect(find.text('Ready /mainpage'), findsOneWidget);
      expect(cloud.vaultRequests, 2);
      expect(store.vaultReads, 1, reason: 'key already in memory at splash');
      await closeSplash(tester);
    });
  });

  group('single-use startup handoff', () {
    testWidgets('existing vault with cached key: one request, unlocked Home',
        (tester) async {
      final (store, cloud, vault) = await device();
      await vault.initAtStartup();
      expect(vault.isUnlocked, isTrue);
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(find.text('Ready /mainpage'), findsOneWidget);
      expect(cloud.vaultRequests, 1);
      expect(store.vaultReads, 1);
      expect(vault.isUnlocked, isTrue);
      await closeSplash(tester);
    });

    testWidgets('existing vault without cached key: one request, unlock route',
        (tester) async {
      final (store, cloud, vault) = await device(cachedKey: false);
      await vault.initAtStartup();
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(find.text('Ready /vaultunlock'), findsOneWidget);
      expect(cloud.vaultRequests, 1);
      expect(store.vaultReads, 1);
      expect(vault.isLocked, isTrue);
      await closeSplash(tester);
    });

    testWidgets('device lock route keeps priority over a reused vault',
        (tester) async {
      await tester.runAsync(() => auth.put('isAuthOn', true));
      final (_, cloud, vault) = await device();
      await vault.initAtStartup();
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(find.text('Ready /lockscreen'), findsOneWidget);
      expect(cloud.vaultRequests, 1);
      await closeSplash(tester);
    });

    testWidgets('two-factor route keeps priority over a reused locked vault',
        (tester) async {
      final (_, cloud, vault) = await device(cachedKey: false);
      await vault.initAtStartup();
      await openSplash(tester, _Startup(vault, cloud.api)..armed = true);
      expect(find.text('Ready /twofactorgate'), findsOneWidget);
      expect(cloud.vaultRequests, 1);
      await closeSplash(tester);
    });

    testWidgets('no cloud vault with a stale cached key is not reused',
        (tester) async {
      final (store, cloud, vault) = await device();
      cloud.answer = _Answer.none;
      await vault.initAtStartup();
      expect(vault.isEnabled, isFalse);
      expect(store.vaultReads, 0, reason: 'stale cache is not read');
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      expect(vault.isEnabled, isFalse);
      expect(vault.isUnlocked, isFalse);
      expect(store.vaultReads, 0);
      expect(find.text('Ready /mainpage'), findsOneWidget);
      await closeSplash(tester);
    });

    testWidgets('negative startup answer, then a vault created elsewhere',
        (tester) async {
      final (_, cloud, vault) = await device();
      cloud.answer = _Answer.none;
      await vault.initAtStartup();
      expect(vault.isEnabled, isFalse);
      cloud.answer = _Answer.vault;
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      expect(vault.isEnabled, isTrue);
      expect(vault.isUnlocked, isTrue);
      await closeSplash(tester);
    });

    testWidgets('offline startup unlocks from cache but is not reused',
        (tester) async {
      final (_, cloud, vault) = await device();
      cloud.answer = _Answer.offline;
      await vault.initAtStartup();
      expect(vault.isUnlocked, isTrue);
      cloud.answer = _Answer.vault;
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      expect(find.text('Ready /mainpage'), findsOneWidget);
      await closeSplash(tester);
    });

    testWidgets('timed-out startup check is not reused', (tester) async {
      final (_, cloud, vault) = await device();
      cloud.gate = Completer<void>();
      var finished = false;
      unawaited(vault.initAtStartup().whenComplete(() => finished = true));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(finished, isTrue, reason: 'bounded by the 5 s vault timeout');
      expect(vault.isUnlocked, isTrue, reason: 'cached-key fallback kept');
      cloud.gate!.complete();
      cloud.gate = null;
      await tester.pump();
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      await closeSplash(tester);
    });

    for (final cached in [
      'not valid base64!',
      base64Encode([1, 2, 3])
    ]) {
      testWidgets('malformed cached key is not reused ($cached)',
          (tester) async {
        final (store, cloud, vault) = await device(cached: cached);
        await vault.initAtStartup();
        expect(vault.isLocked, isTrue);
        await openSplash(tester, _Startup(vault, cloud.api));
        expect(cloud.vaultRequests, 2);
        expect(vault.isLocked, isTrue);
        expect(store.values[_entry], cached);
        expect(find.text('Ready /vaultunlock'), findsOneWidget);
        await closeSplash(tester);
      });
    }

    testWidgets('failed key-store read is not reused', (tester) async {
      final (store, cloud, vault) = await device();
      store.failVaultReads = true;
      await vault.initAtStartup();
      expect(vault.isLocked, isTrue);
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      expect(vault.isLocked, isTrue);
      await closeSplash(tester);
    });

    testWidgets('failed key deletion before startup is not reused',
        (tester) async {
      final (store, cloud, vault) = await device();
      store.failDeletes = true;
      await expectLater(vault.lockThisDevice(), throwsException);
      await vault.initAtStartup();
      expect(vault.isLocked, isTrue, reason: 'retained entry is not trusted');
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      expect(vault.isLocked, isTrue);
      expect(store.values.containsKey(_entry), isTrue);
      await closeSplash(tester);
    });

    testWidgets('explicit device lock after startup forces a fresh check',
        (tester) async {
      final (store, cloud, vault) = await device();
      await vault.initAtStartup();
      await vault.lockThisDevice();
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      expect(vault.isLocked, isTrue);
      expect(store.values.containsKey(_entry), isFalse);
      await closeSplash(tester);
    });

    testWidgets('memory lock after startup forces a fresh check',
        (tester) async {
      final (_, cloud, vault) = await device();
      await vault.initAtStartup();
      vault.lockMemory();
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      expect(vault.isUnlocked, isTrue, reason: 'same user re-reads own cache');
      await closeSplash(tester);
    });

    testWidgets('logout clear after startup forces a fresh check',
        (tester) async {
      final (store, cloud, vault) = await device();
      await vault.initAtStartup();
      await vault.clearLocal();
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      expect(store.values.containsKey(_entry), isFalse);
      expect(vault.isLocked, isTrue);
      await closeSplash(tester);
    });

    testWidgets('session replaced after startup forces a fresh check',
        (tester) async {
      final (_, cloud, vault) = await device();
      await vault.initAtStartup();
      await cloud.api.init(); // new session revision for the same account
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      await closeSplash(tester);
    });

    testWidgets('account replaced after startup cannot reuse or unlock',
        (tester) async {
      final (store, cloud, vault) = await device();
      await vault.initAtStartup();
      store.values['atomic_api_user_id'] = 'fixture-other';
      await cloud.api.init();
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      expect(vault.isUnlocked, isFalse, reason: 'other account has no cache');
      expect(vault.isLocked, isTrue);
      expect(find.text('Ready /vaultunlock'), findsOneWidget);
      await closeSplash(tester);
    });

    testWidgets('session replaced while the startup check is in flight',
        (tester) async {
      final (_, cloud, vault) = await device();
      cloud.gate = Completer<void>();
      final step = vault.initAtStartup();
      await tester.pump();
      await cloud.api.init();
      cloud.gate!.complete();
      cloud.gate = null;
      await step;
      expect(vault.isUnlocked, isFalse,
          reason: 'stale completion must not unlock the new session');
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      expect(vault.isUnlocked, isTrue, reason: 'fresh check for new session');
      await closeSplash(tester);
    });

    testWidgets('memory lock while the startup check is in flight',
        (tester) async {
      final (_, cloud, vault) = await device();
      cloud.gate = Completer<void>();
      final step = vault.initAtStartup();
      await tester.pump();
      vault.lockMemory();
      cloud.gate!.complete();
      cloud.gate = null;
      await step;
      expect(vault.isUnlocked, isFalse);
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      await closeSplash(tester);
    });

    testWidgets('ordinary init joining the startup check withdraws the offer',
        (tester) async {
      final (_, cloud, vault) = await device();
      cloud.gate = Completer<void>();
      final step = vault.initAtStartup();
      await tester.pump();
      final joined = vault.init();
      cloud.gate!.complete();
      cloud.gate = null;
      await Future.wait([step, joined]);
      expect(cloud.vaultRequests, 1, reason: 'in-flight work still shared');
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      await closeSplash(tester);
    });

    testWidgets('ordinary init between startup and splash withdraws the offer',
        (tester) async {
      final (_, cloud, vault) = await device();
      await vault.initAtStartup();
      await vault.init();
      expect(cloud.vaultRequests, 2);
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 3);
      await closeSplash(tester);
    });

    testWidgets('stale or interrupted startup result is not reused',
        (tester) async {
      final (_, cloud, vault) = await device();
      await vault.initAtStartup();
      Vault.startupHandoffMaxAge = const Duration(microseconds: -1);
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2);
      await closeSplash(tester);
    });

    testWidgets('result is consumed once; later splash and init refresh',
        (tester) async {
      final (_, cloud, vault) = await device();
      await vault.initAtStartup();
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 1);
      await closeSplash(tester);
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 2, reason: 'later navigation refreshes');
      await closeSplash(tester);
      await vault.initAfterStartup();
      await vault.init();
      expect(cloud.vaultRequests, 4);
    });

    testWidgets('foreign pending cache wins and discards the unused result',
        (tester) async {
      final (_, cloud, vault) = await device();
      await vault.initAtStartup();
      final startup = _Startup(vault, cloud.api, foreignCache: true);
      await openSplash(tester, startup);
      expect(find.text('Ready /account-cache-recovery'), findsOneWidget);
      expect(cloud.vaultRequests, 1, reason: 'no vault check before recovery');
      await closeSplash(tester);
      startup.foreignCache = false;
      await openSplash(tester, startup);
      expect(cloud.vaultRequests, 2, reason: 'left splash discarded result');
      await closeSplash(tester);
    });

    testWidgets('first login on a second device: no startup owner, one check',
        (tester) async {
      final store = _DeviceStore()
        ..values.remove('atomic_api_session_token')
        ..values.remove('atomic_api_user_id');
      final cloud = _Cloud(store);
      await cloud.open();
      final vault = Vault.forTest(api: cloud.api, storage: store);
      await vault.initAtStartup();
      expect(cloud.vaultRequests, 0);
      store.values['atomic_api_session_token'] = 'fixture-session';
      store.values['atomic_api_user_id'] = 'fixture-user';
      await cloud.api.init(); // sign-in completed
      await openSplash(tester, _Startup(vault, cloud.api));
      expect(cloud.vaultRequests, 1);
      expect(vault.isEnabled, isTrue);
      expect(find.text('Ready /vaultunlock'), findsOneWidget);
      await closeSplash(tester);
    });
  });
}
