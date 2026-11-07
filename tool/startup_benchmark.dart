// Synthetic startup-sequence report (C02). Run with:
//
//   flutter test --no-pub tool/startup_benchmark.dart
//
// It drives runStartupSequence with fake services on fake time, plus the real
// ApiClient/Vault over a counting HTTP fake, and prints one JSON line
// prefixed "startup-benchmark:". Every figure is synthetic: logical call
// order, outcomes, vault request counts and fake-clock durations. None of it
// is a device or physical startup measurement.
//
// It runs only under `flutter test`, so the test-only constructors are allowed.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/utility/startup_sequence.dart';
import 'package:atomic_notes/utility/startup_trace.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

enum _Cloud { vault, none, offline }

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

/// Local steps take a fixed synthetic delay; API and vault use the real chain.
class _Services extends StartupServices {
  _Services(this.api, this.vault, {required this.apiHangs});
  final ApiClient api;
  final Vault vault;
  final bool apiHangs;
  final calls = <String>[];
  static const localDelay = Duration(milliseconds: 5);

  Future<void> _local(String name) async {
    calls.add(name);
    await Future<void>.delayed(localDelay);
  }

  @override
  Future<void> initApi() {
    calls.add('api');
    return apiHangs ? Completer<void>().future : api.init();
  }

  @override
  Future<void> initHive() => _local('hive');
  @override
  Future<void> openBox(String name) => _local('box:$name');
  @override
  Future<void> applyScreenSecurity() => _local('screenSecurity');
  @override
  Future<void> initProfile() => _local('profile');
  @override
  Future<void> initSyncStatus() => _local('syncStatus');
  @override
  Future<void> initQuota() => _local('quota');
  @override
  Future<void> initVault() {
    calls.add('vault');
    return vault.initAtStartup();
  }

  @override
  Future<void> initRepository() => _local('repository');
}

void main() {
  final report = <Map<String, Object?>>[];

  Future<void> scenario(WidgetTester tester, String name,
      {_Cloud cloud = _Cloud.vault, bool apiHangs = false}) async {
    var vaultRequests = 0;
    final client = MockClient((request) async {
      vaultRequests++;
      switch (cloud) {
        case _Cloud.vault:
          return http.Response(jsonEncode({'encVersion': 1}), 200);
        case _Cloud.none:
          return http.Response(jsonEncode({'error': 'vault_not_found'}), 404);
        case _Cloud.offline:
          throw http.ClientException('fixture offline');
      }
    });
    final store = _Store();
    final api = ApiClient.forTest(
        client: client,
        storage: store,
        baseUrl: Uri.parse('https://fixture.invalid/api'));
    // A hung init never loads the stored session, so give the vault one.
    if (apiHangs) await api.init();
    final vault = Vault.forTest(api: api, storage: store);
    final services = _Services(api, vault, apiHangs: apiHangs);
    final trace = StartupTrace(enabled: true, sink: (_) {});

    final started = tester.binding.clock.now();
    var done = false;
    unawaited(runStartupSequence(services, trace).then((_) => done = true));
    while (!done) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    final fakeElapsed = tester.binding.clock.now().difference(started);
    final startupRequests = vaultRequests;
    await vault.initAfterStartup(); // the splash's first check
    client.close();

    report.add({
      'scenario': name,
      'order': services.calls,
      'outcomes': {
        for (final s in trace.spans) s.step.name: s.outcome.name,
      },
      'vaultRequestsBeforeFirstFrame': startupRequests,
      'vaultRequestsThroughSplash': vaultRequests,
      'fakeElapsedMs': fakeElapsed.inMilliseconds,
      'vaultUnlocked': vault.isUnlocked,
    });
  }

  testWidgets('healthy returning user', (t) => scenario(t, 'healthy'));
  testWidgets(
      'no cloud vault', (t) => scenario(t, 'noVault', cloud: _Cloud.none));
  testWidgets(
      'cloud offline', (t) => scenario(t, 'offline', cloud: _Cloud.offline));
  testWidgets('API init hangs', (t) => scenario(t, 'apiHangs', apiHangs: true));

  tearDownAll(() {
    final line = jsonEncode({
      'synthetic': true,
      'note': 'fake services and fake clock; not a device measurement',
      'localStepDelayMs': _Services.localDelay.inMilliseconds,
      'apiInitTimeoutMs': apiInitTimeout.inMilliseconds,
      'scenarios': report,
    });
    // ignore: avoid_print
    print('startup-benchmark: $line');
    final out = Platform.environment['STARTUP_BENCHMARK_OUT'];
    if (out != null && out.isNotEmpty) File(out).writeAsStringSync('$line\n');
  });
}
