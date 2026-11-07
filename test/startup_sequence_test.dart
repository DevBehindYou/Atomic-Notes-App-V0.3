import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/utility/startup_sequence.dart';
import 'package:atomic_notes/utility/startup_trace.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records each call; a step can be held open or made to fail.
class _Services implements StartupServices {
  final calls = <String>[];
  final hold = <String, Completer<void>>{};
  final fail = <String>{};

  Future<void> _run(String name) {
    calls.add(name);
    if (fail.contains(name)) return Future.error(StateError('$name failed'));
    return hold[name]?.future ?? Future<void>.value();
  }

  @override
  Future<void> initApi() => _run('api');
  @override
  Future<void> initHive() => _run('hive');
  @override
  Future<void> openBox(String name) => _run('box:$name');
  @override
  Future<void> applyScreenSecurity() => _run('screenSecurity');
  @override
  Future<void> initProfile() => _run('profile');
  @override
  Future<void> initSyncStatus() => _run('syncStatus');
  @override
  Future<void> initQuota() => _run('quota');
  @override
  Future<void> initVault() => _run('vault');
  @override
  Future<void> initRepository() => _run('repository');
}

const _order = [
  'api',
  'hive',
  'box:authBox',
  'screenSecurity',
  'profile',
  'box:syncBox',
  'syncStatus',
  'quota',
  'vault',
  'repository',
];

class _Store extends FlutterSecureStorage {
  _Store() : super();
  final values = <String, String>{
    'atomic_api_session_token': 'fixture-session',
    'atomic_api_user_id': 'fixture-user',
    'atomic_api_user_email': 'fixture@example.test',
    'atomic_vault_key_fixture-user': base64Encode(List<int>.filled(32, 7)),
  };
  @override
  Future<String?> read(
          {required String key,
          IOSOptions? iOptions,
          AndroidOptions? aOptions,
          LinuxOptions? lOptions,
          WebOptions? webOptions,
          MacOsOptions? mOptions,
          WindowsOptions? wOptions}) async =>
      values[key];
}

void main() {
  StartupTrace trace() => StartupTrace(enabled: true, sink: (_) {});

  test('runs every step once, in the fixed order', () async {
    final services = _Services();
    final t = trace();
    await runStartupSequence(services, t);
    expect(services.calls, _order);
    expect(t.spans.map((s) => s.step), StartupStep.values);
    expect(t.spans.every((s) => s.outcome == StartupOutcome.ok), isTrue);
  });

  test('each step waits for the previous one to finish', () async {
    final services = _Services();
    for (final name in _order) {
      services.hold[name] = Completer<void>();
    }
    final run = runStartupSequence(services, trace());
    for (var i = 0; i < _order.length; i++) {
      await pumpEventQueue();
      expect(services.calls, _order.sublist(0, i + 1),
          reason: 'only ${_order[i]} may be running');
      services.hold[_order[i]]!.complete();
    }
    await run;
  });

  test('a failing API init is tolerated and the rest still runs', () async {
    final services = _Services()..fail.add('api');
    final t = trace();
    await runStartupSequence(services, t);
    expect(services.calls, _order);
    expect(t.spans.first.outcome, StartupOutcome.error);
  });

  testWidgets('a hung API init falls back after the 8 s bound', (tester) async {
    final services = _Services()..hold['api'] = Completer<void>();
    var done = false;
    unawaited(runStartupSequence(services, trace()).then((_) => done = true));
    await tester.pump(apiInitTimeout - const Duration(milliseconds: 1));
    expect(services.calls, ['api'], reason: 'still waiting within the bound');
    await tester.pump(const Duration(milliseconds: 2));
    expect(done, isTrue);
    expect(services.calls, _order);
  });

  for (final failing in _order.skip(1)) {
    test('a failure in $failing stops startup and is rethrown', () async {
      final services = _Services()..fail.add(failing);
      final t = trace();
      await expectLater(runStartupSequence(services, t), throwsStateError);
      final at = _order.indexOf(failing);
      expect(services.calls, _order.sublist(0, at + 1),
          reason: 'no later step may run after a failure');
      expect(t.spans.last.outcome, StartupOutcome.error);
    });
  }

  test('returning-user start makes one vault request through the real chain',
      () async {
    var vaultRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path != '/api/vault') {
        throw StateError('unexpected ${request.url.path}');
      }
      vaultRequests++;
      return http.Response(jsonEncode({'encVersion': 1}), 200);
    });
    addTearDown(client.close);
    final store = _Store();
    final api = ApiClient.forTest(
        client: client,
        storage: store,
        baseUrl: Uri.parse('https://fixture.invalid/api'));
    final vault = Vault.forTest(api: api, storage: store);
    final services = _RealVaultServices(api, vault);

    await runStartupSequence(services, trace());
    expect(vaultRequests, 1);
    expect(vault.isUnlocked, isTrue);
    // The splash's first check (SplashStartupServices.initVault).
    await vault.initAfterStartup();
    expect(vaultRequests, 1,
        reason: 'a second serial vault request would be a regression');
  });
}

/// The fixture services with the real ApiClient and Vault startup steps.
class _RealVaultServices extends _Services {
  _RealVaultServices(this.api, this.vault);
  final ApiClient api;
  final Vault vault;
  @override
  Future<void> initApi() => api.init();
  @override
  Future<void> initVault() => vault.initAtStartup();
}
