import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'notes_repository_lifecycle_test.dart' show TestVault;
import 'support/server_fixture_origin.dart';
import 'support/server_fixture_transport.dart';

class _Store implements FlutterSecureStorage {
  _Store(String owner, String token)
    : values = {
        'atomic_api_session_token': token,
        'atomic_api_user_id': owner,
        'atomic_api_user_email': 'public@example.test',
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
        throw StateError('Unexpected synthetic store operation');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const configured = String.fromEnvironment('ATOMIC_FIXTURE_ORIGIN');
  test(
    'actual session management preserves dirty Hive work and account isolation',
    () async {
      var phase = 'setup', passed = false;
      int? failureLine;
      addTearDown(
        () async => File('ci-user-sessions-wire-case.json').writeAsString(
          jsonEncode({
            'version': 1,
            'case': 'session_management_hive',
            'phase': phase,
            'outcome': passed ? 'passed' : 'failed',
            if (failureLine != null) 'failureLine': failureLine,
          }),
        ),
      );
      try {
        final origin = serverFixtureOrigin(configured),
            transport = serverFixtureTransport();
        final directory = await Directory.systemTemp.createTemp(
          'atomic-sessions-wire-',
        );
        final repositories = <NotesRepository>[];
        StreamSubscription<void>? endedSub;
        addTearDown(() async {
          await endedSub?.cancel();
          for (final notes in repositories) {
            await notes.stop(waitForSync: true);
            notes.dispose();
          }
          transport.close();
          await Hive.close();
          final resolved = await directory.resolveSymbolicLinks();
          expect(
            Directory(resolved).parent.path,
            await Directory.systemTemp.resolveSymbolicLinks(),
          );
          expect(
            Directory(
              resolved,
            ).uri.pathSegments.where((part) => part.isNotEmpty).last,
            startsWith('atomic-sessions-wire-'),
          );
          await Directory(resolved).delete(recursive: true);
        });
        Future<Map<String, dynamic>> diagnostic(String path) async {
          final reply = await transport.get(origin.replace(path: path));
          expect(reply.statusCode, 200);
          return jsonDecode(reply.body) as Map<String, dynamic>;
        }

        final descriptor = await diagnostic('/__fixture/ready'),
            owner = descriptor['owner'] as String;
        Hive.init(directory.path);
        SyncStatusHelper.syncBox = await Hive.openBox<bool>('sessions-sync');
        Future<ApiClient> client(_Store store) async {
          final api = ApiClient.forTest(
            client: transport,
            storage: store,
            baseUrl: origin.replace(path: '/api'),
          );
          await api.init();
          return api;
        }

        final storeA = _Store(owner, 'atomic-disposable-client-a'),
            storeB = _Store(owner, 'atomic-disposable-client-b');
        final a = await client(storeA), b = await client(storeB);
        final boxA = await Hive.openBox('sessions-a'),
            boxB = await Hive.openBox('sessions-b');
        Future<NotesRepository> notes(Box box, ApiClient api) async {
          final repository = NotesRepository.forTest(
            box: box,
            api: api,
            vault: TestVault(),
            checkConnectivity: () async => [ConnectivityResult.wifi],
          );
          repositories.add(repository);
          await repository.start();
          return repository;
        }

        final notesA = await notes(boxA, a), notesB = await notes(boxB, b);
        final noteA = Note(
          id: newId(),
          title: 'Public retained A',
          body: 'Public unsent work A',
        );
        final noteB = Note(
          id: newId(),
          title: 'Public retained B',
          body: 'Public unsent work B',
        );
        await notesA.save(noteA);
        await notesB.save(noteB);
        await notesA.stop(waitForSync: true);
        await notesB.stop(waitForSync: true);
        final diskA = Map<dynamic, dynamic>.from(boxA.toMap()),
            diskB = Map<dynamic, dynamic>.from(boxB.toMap());
        final before = await diagnostic('/__fixture/state');
        phase = 'inventory_and_current_refusal';
        final inventoryA = await a.userSessions();
        expect(inventoryA.sessions, hasLength(2));
        final current = inventoryA.sessions.singleWhere((row) => row.isCurrent);
        final other = inventoryA.sessions.singleWhere((row) => !row.isCurrent);
        expect(current.handle, isNot(other.handle));
        expect(current.handle, isNot('atomic-disposable-client-a'));
        expect(current.handle.length, 43);
        await expectLater(
          a.revokeUserSession(current.handle),
          throwsA(
            isA<ApiException>().having(
              (error) => error.code,
              'code',
              'current_session_requires_safe_logout',
            ),
          ),
        );
        expect(a.isSignedIn, isTrue);
        expect(boxA.toMap(), diskA);
        phase = 'foreign_handle_noop';
        final foreign = await client(
          _Store(descriptor['other'] as String, 'atomic-disposable-other'),
        );
        await foreign.revokeUserSession(other.handle);
        expect((await a.userSessions()).sessions, hasLength(2));
        phase = 'revoke_other_and_idempotent_retry';
        await a.revokeUserSession(other.handle);
        await a.revokeUserSession(other.handle);
        final remaining = await a.userSessions();
        expect(remaining.sessions, hasLength(1));
        expect(remaining.sessions.single.isCurrent, isTrue);
        expect(a.currentUserId, owner);
        expect(boxA.toMap(), diskA);
        expect(boxB.toMap(), diskB);
        phase = 'real401_retains_hive_and_same_owner_restore';
        final retired = Completer<void>();
        endedSub = b.onSessionEnded.listen((_) async {
          await notesB.stop();
          notesB.clearMemory();
          retired.complete();
        });
        await expectLater(
          b.energyState(),
          throwsA(
            isA<ApiException>().having(
              (error) => error.statusCode,
              'status',
              401,
            ),
          ),
        );
        await retired.future.timeout(const Duration(seconds: 5));
        await b.init();
        expect(b.isSignedIn, isFalse);
        expect(notesB.count, 0);
        expect(boxB.toMap(), diskB);
        expect((boxB.get(noteB.id) as Map)['dirty'], isTrue);
        expect(boxB.get('__cache_owner__'), owner);
        // An existing other valid synthetic token proves owner restoration, not a
        // native Google login, new token issuance or physical multi-device test.
        storeB.values.addAll({
          'atomic_api_session_token': 'atomic-disposable-client-a',
          'atomic_api_user_id': owner,
          'atomic_api_user_email': 'public@example.test',
        });
        await b.init();
        await notesB.start();
        expect(notesB.byId(noteB.id)!.body, noteB.body);
        expect(notesB.byId(noteB.id)!.dirty, isTrue);
        expect(boxB.toMap(), diskB);
        final after = await diagnostic('/__fixture/state');
        expect(after['users'], before['users']);
        expect(after['writes'], before['writes']);
        phase = 'complete';
        passed = true;
      } catch (_, stack) {
        final match = RegExp(
          r'user_sessions_wire_integration_test\.dart:([1-9][0-9]{0,3})',
        ).firstMatch(stack.toString());
        if (match != null) failureLine = int.parse(match[1]!);
        rethrow;
      }
    },
    skip: configured.isEmpty ? 'Dedicated loopback CI fixture required' : false,
  );
}
