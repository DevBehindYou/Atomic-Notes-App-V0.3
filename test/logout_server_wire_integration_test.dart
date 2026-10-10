import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/logout_plan.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;

import 'notes_repository_lifecycle_test.dart' show TestVault;
import 'support/server_fixture_origin.dart';
import 'support/server_fixture_transport.dart';

// Synthetic storage, not Android secure storage or real account credentials.
class _Storage implements FlutterSecureStorage {
  _Storage(String uid, String token)
      : values = {
          'atomic_api_session_token': token,
          'atomic_api_user_id': uid,
          'atomic_api_user_email': 'fixture@example.test',
        };
  final Map<String, String> values;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key] as String?;
    switch (invocation.memberName) {
      case #read:
        return Future<String?>.value(values[key]);
      case #write:
        final value = invocation.namedArguments[#value] as String?;
        if (value == null) {
          values.remove(key);
        } else {
          values[key!] = value;
        }
        return Future<void>.value();
      case #delete:
        values.remove(key);
        return Future<void>.value();
      default:
        throw StateError('Unexpected synthetic storage call');
    }
  }
}

// Lose a fully received response AFTER the actual route/transaction completed.
// Request/response bodies stay private to this test; artifacts contain codes only.
class _Replies extends http.BaseClient {
  _Replies(this.inner);
  final http.Client inner;
  String? dropPath;
  int dropOccurrence = 1, matching = 0;
  final pushes = <Map<String, dynamic>>[];
  final paths = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    paths.add(request.url.path);
    if (request.method == 'POST' && request.url.path == '/api/notes/push') {
      pushes.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>);
    }
    final response = await inner.send(request);
    if (request.url.path == dropPath && ++matching == dropOccurrence) {
      dropPath = null;
      expect(response.statusCode, 200);
      await response.stream.drain<void>();
      throw http.ClientException('Synthetic committed reply withheld');
    }
    return response;
  }
}

const _cases = [
  'paid_logout',
  'emergency_logout',
  'lost_push_restart',
  'lost_completion_restart',
  'paid_second_batch_restart',
  'partial_failure_retry',
  'conflict_copy_retry',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const configuredOrigin = String.fromEnvironment('ATOMIC_FIXTURE_ORIGIN');
  const selected = String.fromEnvironment('ATOMIC_LOGOUT_CASE');
  for (final code in _cases) {
    test(code, () async {
      var phase = 'setup', passed = false, finished = 0;
      Directory? directory;
      http.Client? transport;
      final repositories = <NotesRepository>[];
      addTearDown(() async {
        for (final repo in repositories) {
          await repo.stop(waitForSync: true);
          repo.dispose();
        }
        transport?.close();
        await Hive.close();
        final ownedDirectory = directory;
        if (ownedDirectory != null) {
          final resolved = await ownedDirectory.resolveSymbolicLinks();
          expect(Directory(resolved).parent.path,
              await Directory.systemTemp.resolveSymbolicLinks());
          expect(
              Directory(resolved)
                  .uri
                  .pathSegments
                  .where((s) => s.isNotEmpty)
                  .last,
              startsWith('atomic-logout-wire-'));
          await Directory(resolved).delete(recursive: true);
        }
        await File('ci-logout-wire-$code.json').writeAsString(jsonEncode({
          'version': 1,
          'case': code,
          'outcome': passed ? 'passed' : 'failed',
          'phase': phase,
        }));
      });
      final origin = serverFixtureOrigin(configuredOrigin);
      transport = serverFixtureTransport();
      final wire = transport;
      Future<Map<String, dynamic>> diagnostic(String path) async {
        final response = await wire.get(origin.replace(path: path));
        expect(response.statusCode, 200);
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      final descriptor = await diagnostic('/__fixture/ready');
      final batch = code == 'paid_second_batch_restart';
      final uid = descriptor[batch ? 'batchOwner' : 'owner'] as String;
      final token =
          batch ? 'atomic-disposable-batch' : 'atomic-disposable-client-a';
      final storage = _Storage(uid, token);
      final replies = _Replies(wire);
      late Box box;
      late ApiClient api;
      late NotesRepository repo;
      directory = await Directory.systemTemp.createTemp('atomic-logout-wire-');
      Hive.init(directory.path);
      box = await Hive.openBox('logout-wire-notes');
      SyncStatusHelper.syncBox = await Hive.openBox<bool>('logout-wire-sync');
      await SyncStatusHelper.setSyncStatus(true);
      Future<void> openDevice() async {
        api = ApiClient.forTest(
            client: replies,
            storage: storage,
            baseUrl: origin.replace(path: '/api'));
        await api.init();
        repo = NotesRepository.forTest(
            box: box,
            api: api,
            vault: TestVault(),
            checkConnectivity: () async => [ConnectivityResult.wifi]);
        await repo.start();
        repositories.add(repo);
      }

      await openDevice();
      Map<String, dynamic> wallet(Map<String, dynamic> state) =>
          (state['users'] as List)
              .cast<Map<String, dynamic>>()
              .singleWhere((row) => row['userId'] == uid);
      Future<void> energy(int target) async {
        final current =
            wallet(await diagnostic('/__fixture/state'))['energy'] as int;
        if (current == target) return;
        final response =
            await wire.post(origin.replace(path: '/api/admin/energy'),
                headers: {
                  'content-type': 'application/json',
                  'x-admin-api-key': 'atomic-disposable-admin-key'
                },
                body: jsonEncode({
                  'user_id': uid,
                  'request_id': newId(),
                  'energy_delta': target - current,
                  'coins_delta': 0,
                  'note': 'Synthetic logout fixture budget'
                }));
        expect(response.statusCode, 200);
        expect(wallet(await diagnostic('/__fixture/state'))['energy'], target);
      }

      Future<void> failWrites(List<String> ids) async {
        final response =
            await wire.post(origin.replace(path: '/__fixture/fail-writes'),
                headers: {
                  'content-type': 'application/json',
                  'authorization': 'Bearer atomic-disposable-client-a'
                },
                body: jsonEncode({'ids': ids}));
        expect(response.statusCode, 200);
      }

      Future<void> logout() => repo.logoutSafely(finishLocal: (check) async {
            check();
            expect(box.isEmpty, isTrue);
            await api.signOutIfCurrent(api.sessionRevision);
            finished++;
          });
      Future<void> restart() async {
        await repo.stop(waitForSync: true);
        repositories.remove(repo);
        repo.dispose();
        await box.close();
        box = await Hive.openBox('logout-wire-notes');
        await openDevice();
      }

      phase = 'preparing';
      final emergency = code == 'emergency_logout' ||
          code == 'lost_push_restart' ||
          code == 'lost_completion_restart' ||
          code == 'partial_failure_retry';
      await energy(emergency ? 0 : 100);
      final notes = <Note>[];
      for (var i = 0; i < (batch ? 51 : 1); i++) {
        final note = Note.create()
          ..title = 'Public logout fixture $i'
          ..body = 'Synthetic offline content $i';
        await repo.save(note);
        notes.add(note.copy());
      }
      if (code == 'partial_failure_retry') {
        final extra = Note.create()
          ..title = 'Public failed row'
          ..body = 'Retain offline row';
        await repo.save(extra);
        notes.add(extra.copy());
        await failWrites([extra.id]);
      }
      if (code == 'conflict_copy_retry') {
        expect(await repo.syncNow(instant: true), isTrue);
        final otherApi = ApiClient.forTest(
            client: wire,
            storage: _Storage(uid, 'atomic-disposable-client-b'),
            baseUrl: origin.replace(path: '/api'));
        await otherApi.init();
        final local = repo.byId(notes.single.id)!;
        final remote = local.copy()..body = 'Accepted on other device';
        final row = remote.toRemote(uid)
          ..['base_version'] = local.serverVersion
          ..['enc_v'] = 0
          ..['payload'] = null;
        expect(
            (await otherApi.pushNotes([row], requestId: newId(), instant: true))
                .results
                .single['ok'],
            isTrue);
        local.body = 'Offline edit on logging out device';
        await repo.save(local);
        await energy(0);
      }
      final before = await diagnostic('/__fixture/state');
      final beforeEnergy = wallet(before)['energy'] as int;
      final beforeLedger = (wallet(before)['ledger'] as List).length;
      final beforeWrites = before['writes'] as int;
      phase = 'first_logout';
      if (code == 'lost_push_restart' || batch) {
        replies.dropPath = '/api/notes/push';
        replies.dropOccurrence = batch ? 2 : 1;
      } else if (code == 'lost_completion_restart') {
        replies.dropPath = '/api/notes/logout-attempt/complete';
      }
      final shouldBlock = code != 'paid_logout' && code != 'emergency_logout';
      if (shouldBlock) {
        await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
        expect(finished, 0);
        expect(box.containsKey(notes.first.id), isTrue);
        expect(api.isSignedIn, isTrue);
        final interrupted = await diagnostic('/__fixture/state');
        if (code == 'conflict_copy_retry') {
          expect(interrupted['writes'], beforeWrites);
          expect(repo.byId(notes.single.id)!.body, 'Accepted on other device');
          final copy = repo
              .visible()
              .singleWhere((n) => n.title.endsWith('(conflict copy)'));
          expect(copy.body, 'Offline edit on logging out device');
          expect(copy.dirty, isTrue);
          notes.add(copy.copy());
          expect(box.containsKey(LogoutPlanStore.key), isFalse);
        } else if (code == 'partial_failure_retry') {
          expect(repo.byId(notes.last.id)!.dirty, isTrue);
          expect(repo.byId(notes.first.id)!.dirty, isFalse);
          expect(box.containsKey(LogoutPlanStore.key), isFalse);
          expect(wallet(interrupted)['energy'], 0);
          expect((wallet(interrupted)['ledger'] as List).length, beforeLedger);
          await failWrites([]);
        } else {
          expect(box.containsKey(LogoutPlanStore.key), isTrue);
          expect(interrupted['writes'], beforeWrites + notes.length);
          expect(
              wallet(interrupted)['energy'], beforeEnergy - (batch ? 20 : 0));
          if (code == 'lost_completion_restart') {
            expect(api.pendingLogoutCompletion, isNotNull);
            final probe = await wire.get(
                origin.replace(path: '/api/notes/pull'),
                headers: {'authorization': 'Bearer $token'});
            expect(probe.statusCode, 401);
          }
          phase = 'restart';
          await restart();
          expect(box.containsKey(notes.first.id), isTrue);
        }
        final pathsBeforeRetry = replies.paths.length;
        phase = 'retry';
        await logout();
        if (code == 'lost_completion_restart') {
          expect(replies.paths.skip(pathsBeforeRetry),
              ['/api/notes/logout-attempt/complete']);
        }
      } else {
        await logout();
      }
      phase = 'checking';
      expect(finished, 1);
      expect(box.isEmpty, isTrue);
      expect(api.isSignedIn, isFalse);
      final after = await diagnostic('/__fixture/state');
      final charged = code == 'paid_logout'
          ? 10
          : batch
              ? 20
              : 0;
      expect(wallet(after)['energy'], beforeEnergy - charged);
      expect((wallet(after)['ledger'] as List).length,
          beforeLedger + (charged ~/ 10));
      expect(after['writes'],
          beforeWrites + (code == 'conflict_copy_retry' ? 1 : notes.length));
      expect(wallet(after)['notes'], notes.length);
      if (code == 'lost_push_restart' || batch) {
        final unique = replies.pushes.map((body) => body['requestId']).toSet();
        expect(unique.length, batch ? 2 : 1);
        expect(replies.pushes.length, greaterThan(unique.length));
        for (final id in unique) {
          final bodies = replies.pushes
              .where((body) => body['requestId'] == id)
              .map(jsonEncode)
              .toSet();
          expect(bodies.length, 1);
        }
      }
      final revoked = await wire.get(origin.replace(path: '/api/notes/pull'),
          headers: {'authorization': 'Bearer $token'});
      expect(revoked.statusCode, 401);
      if (!batch) {
        // The account's second session is not revoked; pull through real API and
        // repository into its own Hive box rather than trusting a count alone.
        final observerApi = ApiClient.forTest(
            client: wire,
            storage: _Storage(uid, 'atomic-disposable-client-b'),
            baseUrl: origin.replace(path: '/api'));
        await observerApi.init();
        final observer = NotesRepository.forTest(
            box: await Hive.openBox('observer'),
            api: observerApi,
            vault: TestVault(),
            checkConnectivity: () async => [ConnectivityResult.wifi]);
        repositories.add(observer);
        await observer.start();
        expect(await observer.syncNow(instant: true), isTrue);
        expect(observer.count, notes.length);
        for (final note in notes) {
          final expected =
              code == 'conflict_copy_retry' && note.id == notes.first.id
                  ? 'Accepted on other device'
                  : note.body;
          expect(observer.byId(note.id)!.body, expected);
          expect(observer.byId(note.id)!.dirty, isFalse);
        }
        final afterPull = await diagnostic('/__fixture/state');
        expect(afterPull['users'], after['users']);
        expect(afterPull['writes'], after['writes']);
      }
      phase = 'complete';
      passed = true;
    },
        skip: configuredOrigin.isEmpty || selected != code
            ? 'Dedicated opt-in loopback CI scenario required'
            : false);
  }
}
