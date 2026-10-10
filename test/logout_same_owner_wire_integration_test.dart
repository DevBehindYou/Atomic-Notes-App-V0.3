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

class _Replies extends http.BaseClient {
  _Replies(this.inner);
  final http.Client inner;
  String? dropPath;
  int uploads = 0, recoveries = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/api/notes/push') uploads++;
    if (request.url.path == '/api/notes/logout-attempt/recovery-commit')
      recoveries++;
    final reply = await inner.send(request);
    if (request.url.path == dropPath) {
      dropPath = null;
      expect(reply.statusCode, 200);
      await reply.stream.drain<void>();
      throw http.ClientException('Synthetic successful reply withheld');
    }
    return reply;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const configuredOrigin = String.fromEnvironment('ATOMIC_FIXTURE_ORIGIN');
  const selected = String.fromEnvironment('ATOMIC_RECOVERY_CASE');
  for (final code in ['paid_commit_loss', 'completed_old_session']) {
    test(
      code,
      () async {
        var phase = 'setup', passed = false, finished = 0;
        Directory? directory;
        http.Client? transport;
        NotesRepository? repository;
        addTearDown(() async {
          await repository?.stop(waitForSync: true);
          repository?.dispose();
          transport?.close();
          await Hive.close();
          if (directory != null) {
            final resolved = await directory!.resolveSymbolicLinks();
            expect(
              Directory(resolved).parent.path,
              await Directory.systemTemp.resolveSymbolicLinks(),
            );
            expect(
              Directory(
                resolved,
              ).uri.pathSegments.where((s) => s.isNotEmpty).last,
              startsWith('atomic-recovery-handoff-wire-'),
            );
            await Directory(resolved).delete(recursive: true);
          }
          await File('ci-recovery-handoff-$code.json').writeAsString(
            jsonEncode({
              'version': 1,
              'case': code,
              'outcome': passed ? 'passed' : 'failed',
              'phase': phase,
            }),
          );
        });
        final origin = serverFixtureOrigin(configuredOrigin);
        transport = serverFixtureTransport();
        final wire = transport;
        Future<Map<String, dynamic>> diagnostic(String path) async {
          final response = await wire.get(origin.replace(path: path));
          expect(response.statusCode, 200);
          return jsonDecode(response.body) as Map<String, dynamic>;
        }

        final uid = (await diagnostic('/__fixture/ready'))['owner'] as String;
        final replies = _Replies(wire);
        directory = await Directory.systemTemp.createTemp(
          'atomic-recovery-handoff-wire-',
        );
        Hive.init(directory.path);
        var box = await Hive.openBox('recovery-handoff-notes');
        SyncStatusHelper.syncBox = await Hive.openBox<bool>(
          'recovery-handoff-sync',
        );
        await SyncStatusHelper.setSyncStatus(true);
        late ApiClient api;
        Future<void> open(String token) async {
          api = ApiClient.forTest(
            client: replies,
            storage: _Storage(uid, token),
            baseUrl: origin.replace(path: '/api'),
          );
          await api.init();
          repository = NotesRepository.forTest(
            box: box,
            api: api,
            vault: TestVault(),
            checkConnectivity: () async => [ConnectivityResult.wifi],
          );
          await repository!.start();
        }

        Future<void> reopen() async {
          await repository!.stop(waitForSync: true);
          repository!.dispose();
          repository = null;
          await box.close();
          box = await Hive.openBox('recovery-handoff-notes');
          await open('atomic-disposable-client-b');
        }

        Future<void> logout() => repository!.logoutSafely(
          finishLocal: (check) async {
            check();
            expect(box.isEmpty, isTrue);
            await api.signOutIfCurrent(api.sessionRevision);
            finished++;
          },
        );
        Map<String, dynamic> wallet(Map<String, dynamic> state) =>
            (state['users'] as List).cast<Map<String, dynamic>>().singleWhere(
              (row) => row['userId'] == uid,
            );
        phase = 'preparing';
        await open('atomic-disposable-client-a');
        final initial = await diagnostic('/__fixture/state');
        final currentEnergy = wallet(initial)['energy'] as int;
        if (currentEnergy != 100) {
          final adjust = await wire.post(
            origin.replace(path: '/api/admin/energy'),
            headers: {
              'content-type': 'application/json',
              'x-admin-api-key': 'atomic-disposable-admin-key',
            },
            body: jsonEncode({
              'user_id': uid,
              'request_id': newId(),
              'energy_delta': 100 - currentEnergy,
              'coins_delta': 0,
              'note': 'Public recovery fixture budget',
            }),
          );
          expect(adjust.statusCode, 200);
        }
        final note = Note.create()
          ..title = 'Public retained edit'
          ..body = 'Same owner keeps this content';
        await repository!.save(note);
        final before = await diagnostic('/__fixture/state');
        phase = 'first_logout';
        replies.dropPath = code == 'completed_old_session'
            ? '/api/notes/logout-attempt/complete'
            : '/api/notes/push';
        await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
        expect(finished, 0);
        expect(box.containsKey(note.id), isTrue);
        final oldPlan = jsonEncode(box.get(LogoutPlanStore.key));
        if (code == 'paid_commit_loss') {
          final revoke = await wire.post(
            origin.replace(path: '/api/auth/logout'),
            headers: {'authorization': 'Bearer atomic-disposable-client-a'},
          );
          expect(revoke.statusCode, 200);
        }
        final afterWrite = await diagnostic('/__fixture/state');
        expect(
          wallet(afterWrite)['energy'],
          (wallet(before)['energy'] as int) - 10,
        );
        expect(afterWrite['writes'], (before['writes'] as int) + 1);
        phase = 'restart';
        await reopen();
        expect(jsonEncode(box.get(LogoutPlanStore.key)), oldPlan);
        expect(replies.recoveries, 0);
        if (code == 'paid_commit_loss') {
          replies.dropPath = '/api/notes/logout-attempt/recovery-commit';
          phase = 'commit_loss';
          await expectLater(logout(), throwsA(isA<LogoutBlocked>()));
          expect(finished, 0);
          expect(box.containsKey(note.id), isTrue);
          expect(jsonEncode(box.get(LogoutPlanStore.key)), oldPlan);
          final afterCommit = await diagnostic('/__fixture/state');
          expect(afterCommit['users'], afterWrite['users']);
          expect(afterCommit['writes'], afterWrite['writes']);
          // Fresh auth remains live after recovering the old attempt.
          final probe = await wire.get(
            origin.replace(path: '/api/notes/pull'),
            headers: {'authorization': 'Bearer atomic-disposable-client-b'},
          );
          expect(probe.statusCode, 200);
          final remote = jsonDecode(probe.body) as Map;
          expect(
            (remote['rows'] as List).cast<Map>().single['body'],
            note.body,
          );
          await reopen();
        }
        phase = 'retry';
        await logout();
        phase = 'checking';
        expect(finished, 1);
        expect(box.isEmpty, isTrue);
        expect(replies.uploads, 1);
        expect(replies.recoveries, code == 'paid_commit_loss' ? 2 : 1);
        final after = await diagnostic('/__fixture/state');
        expect(after['users'], afterWrite['users']);
        expect(after['writes'], afterWrite['writes']);
        final ended = await wire.get(
          origin.replace(path: '/api/notes/pull'),
          headers: {'authorization': 'Bearer atomic-disposable-client-b'},
        );
        expect(
          ended.statusCode,
          401,
        ); // Explicit completed logout ends fresh auth last.
        phase = 'complete';
        passed = true;
      },
      skip: configuredOrigin.isEmpty || selected != code
          ? 'Dedicated same-owner loopback CI scenario required'
          : false,
    );
  }
}
