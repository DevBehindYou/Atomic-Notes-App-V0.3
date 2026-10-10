import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/api/logout_recovery.dart';
import 'package:atomic_notes/database/logout_plan.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;

import 'support/server_fixture_origin.dart';
import 'support/server_fixture_transport.dart';

// Public synthetic fixture storage. Never opens native secure storage.
class _Storage implements FlutterSecureStorage {
  _Storage(String uid, String token)
    : values = {'atomic_api_session_token': token, 'atomic_api_user_id': uid};
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const configuredOrigin = String.fromEnvironment('ATOMIC_FIXTURE_ORIGIN');
  test(
    'settled old-session status preserves real Hive and current session',
    () async {
      var phase = 'setup', passed = false;
      Directory? directory;
      http.Client? transport;
      addTearDown(() async {
        transport?.close();
        await Hive.close();
        final owned = directory;
        if (owned != null) {
          final resolved = await owned.resolveSymbolicLinks();
          expect(
            Directory(resolved).parent.path,
            await Directory.systemTemp.resolveSymbolicLinks(),
          );
          expect(
            Directory(
              resolved,
            ).uri.pathSegments.where((s) => s.isNotEmpty).last,
            startsWith('atomic-logout-recovery-wire-'),
          );
          await Directory(resolved).delete(recursive: true);
        }
        await File('ci-logout-recovery-wire-case.json').writeAsString(
          jsonEncode({
            'version': 1,
            'case': 'settled_readonly_inspection',
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
      final oldStorage = _Storage(uid, 'atomic-disposable-client-a');
      final oldApi = ApiClient.forTest(
        client: wire,
        storage: oldStorage,
        baseUrl: origin.replace(path: '/api'),
      );
      await oldApi.init();
      final currentStorage = _Storage(uid, 'atomic-disposable-client-b');
      final currentApi = ApiClient.forTest(
        client: wire,
        storage: currentStorage,
        baseUrl: origin.replace(path: '/api'),
      );
      await currentApi.init();
      directory = await Directory.systemTemp.createTemp(
        'atomic-logout-recovery-wire-',
      );
      Hive.init(directory.path);
      final box = await Hive.openBox('logout-recovery-wire-notes');
      final note = Note.create()
        ..title = 'Public recovery fixture'
        ..body = 'Keep this offline snapshot';
      await box.put('__cache_owner__', uid);
      await box.put(note.id, note.toMap());
      final row = note.toRemote(uid)
        ..['enc_v'] = 0
        ..['payload'] = null;
      final plan = await LogoutPlan.prepare(
        userId: uid,
        sessionHash: await oldApi.logoutSessionHash(),
        rows: [row],
        snapshots: {
          note.id: LogoutSnapshot(
            contentSig: note.contentSig,
            updatedAt: note.updatedAt.toIso8601String(),
            conflictId: newId(),
          ),
        },
      );
      final store = LogoutPlanStore(box);
      await store.save(plan);
      final query = LogoutRecoveryQuery(
        previousSessionHash: plan.sessionHash,
        batches: plan.batches,
      );
      final admission = await oldApi.beginLogoutSync(
        plan.attemptId,
        plan.batches.map((batch) => batch.toManifest()).toList(),
      );
      phase = 'active_session_refusal';
      final beforeRefusal = await diagnostic('/__fixture/state');
      await expectLater(
        currentApi.inspectLogoutRecovery(query),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'logout_recovery_previous_session_active',
          ),
        ),
      );
      expect(await diagnostic('/__fixture/state'), beforeRefusal);
      phase = 'settling';
      final receipt = await oldApi.pushLogoutNotes(plan.batches.single);
      expect(receipt.results.single['ok'], isTrue);
      await store.recordCompletionRequested(plan);
      await oldApi.completeLogoutSync(plan.attemptId);
      // Model the crash boundary before applying/consuming any local data.
      await box.flush();
      await box.close();
      final reopened = await Hive.openBox('logout-recovery-wire-notes');
      final localBefore = jsonEncode(reopened.toMap());
      final storageBefore = Map<String, String>.from(currentStorage.values);
      final revision = currentApi.sessionRevision;
      final cloudBefore = await diagnostic('/__fixture/state');
      phase = 'inspection';
      final first = await currentApi.inspectLogoutRecovery(query);
      final replay = await currentApi.inspectLogoutRecovery(query);
      expect(first.state, LogoutRecoveryState.completed);
      expect(replay.state, first.state);
      expect(first.attemptId, plan.attemptId);
      expect(first.batches.single.requestId, plan.batches.single.requestId);
      expect(first.batches.single.charged, admission.costPerBatch);
      expect(first.batches.single.refunded, 0);
      expect(first.batches.single.accepted, 1);
      expect(first.batches.single.failed, 0);
      phase = 'checking';
      expect(jsonEncode(reopened.toMap()), localBefore);
      expect(reopened.containsKey(note.id), isTrue);
      expect(reopened.containsKey(LogoutPlanStore.key), isTrue);
      expect(Note.fromMap(reopened.get(note.id) as Map).dirty, isTrue);
      expect(currentStorage.values, storageBefore);
      expect(currentApi.isSignedIn, isTrue);
      expect(currentApi.sessionRevision, revision);
      expect(currentApi.pendingLogoutCompletion, isNull);
      expect(await diagnostic('/__fixture/state'), cloudBefore);
      final revoked = await wire.get(
        origin.replace(path: '/api/notes/pull'),
        headers: {'authorization': 'Bearer atomic-disposable-client-a'},
      );
      expect(revoked.statusCode, 401);
      phase = 'complete';
      passed = true;
    },
    skip: configuredOrigin.isEmpty
        ? 'Dedicated opt-in loopback fixture required'
        : false,
  );
}
