import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/state/cloud_notes/cloud_notes_cubit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;

import 'notes_repository_lifecycle_test.dart' show TestVault;
import 'support/server_fixture_origin.dart';

/// Independent synthetic stores for logical devices; no native global mock.
class _Storage implements FlutterSecureStorage {
  _Storage(String userId, String token)
      : values = {
          'atomic_api_session_token': token,
          'atomic_api_user_id': userId,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const configuredOrigin = String.fromEnvironment('ATOMIC_FIXTURE_ORIGIN');
  late Uri origin;
  late Directory directory;
  late http.Client transport;
  Directory? ownedDirectory;
  http.Client? ownedTransport;
  late Map<String, dynamic> descriptor;
  final repositories = <NotesRepository>[];
  final cubits = <CloudNotesCubit>[];
  final outcomes = <String, String>{};

  Future<Map<String, dynamic>> diagnostic(String endpoint) async {
    final response = await transport.get(origin.replace(path: endpoint));
    expect(response.statusCode, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<({NotesRepository notes, CloudNotesCubit cubit, ApiClient api})>
      device(String name, String token, String userId) async {
    final api = ApiClient.forTest(
        client: transport,
        storage: _Storage(userId, token),
        baseUrl: origin.replace(path: '/api'));
    await api.init();
    final notes = NotesRepository.forTest(
        box: await Hive.openBox('device-$name'),
        api: api,
        vault: TestVault(),
        checkConnectivity: () async => [ConnectivityResult.wifi]);
    await notes.start();
    repositories.add(notes);
    final cubit = CloudNotesCubit(source: notes);
    cubits.add(cubit);
    return (notes: notes, cubit: cubit, api: api);
  }

  Map<String, dynamic> ownerState(Map<String, dynamic> state) =>
      (state['users'] as List).cast<Map<String, dynamic>>().first;

  setUp(() async {
    if (configuredOrigin.isEmpty) return;
    origin = serverFixtureOrigin(configuredOrigin);
    transport = http.Client();
    ownedTransport = transport;
    descriptor = await diagnostic('/__fixture/ready');
    directory = await Directory.systemTemp.createTemp('atomic-server-wire-');
    ownedDirectory = directory;
    Hive.init(directory.path);
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('isolated-wire-sync');
  });
  tearDown(() async {
    if (configuredOrigin.isEmpty) return;
    for (final cubit in cubits) {
      await cubit.close();
    }
    for (final notes in repositories) {
      await notes.stop(waitForSync: true);
      notes.dispose();
    }
    cubits.clear();
    repositories.clear();
    ownedTransport?.close();
    ownedTransport = null;
    await Hive.close();
    final cleanupDirectory = ownedDirectory;
    ownedDirectory = null;
    if (cleanupDirectory == null) return;
    final resolved = await cleanupDirectory.resolveSymbolicLinks();
    expect(Directory(resolved).parent.path,
        await Directory.systemTemp.resolveSymbolicLinks());
    expect(
        Directory(resolved)
            .uri
            .pathSegments
            .where((part) => part.isNotEmpty)
            .last,
        startsWith('atomic-server-wire-'));
    await Directory(resolved).delete(recursive: true);
  });
  tearDownAll(() async {
    if (configuredOrigin.isNotEmpty) {
      await File('ci-wire-proof.json').writeAsString(jsonEncode({
        'scope':
            'real Flutter API/repository/Cubit to real notes/auth routes; disposable Mongo; fake Drive',
        'outcomes': outcomes,
      }));
    }
  });

  void wireTest(String code, Future<void> Function() body) {
    test(code, () async {
      outcomes[code] = 'failed';
      await body();
      outcomes[code] = 'passed';
    },
        skip: configuredOrigin.isEmpty
            ? 'Dedicated loopback CI fixture required'
            : false);
  }

  wireTest('create_pull_and_other_account_isolation', () async {
    final before = await diagnostic('/__fixture/state');
    final a = await device(
        'a', 'atomic-disposable-client-a', descriptor['owner'] as String);
    final b = await device(
        'b', 'atomic-disposable-client-b', descriptor['owner'] as String);
    final note =
        Note(id: newId(), title: 'Wire fixture', body: 'Synthetic body');
    await a.notes.save(note);
    await a.cubit.sync(uploadAll: false);
    expect(a.cubit.state.lastReport!.completed, isTrue);
    expect(a.cubit.state.lastReport!.netCharge, 10);
    expect(a.notes.byId(note.id)!.dirty, isFalse);
    expect(a.notes.byId(note.id)!.serverVersion, 1);
    await b.cubit.sync(uploadAll: false);
    expect(b.cubit.state.lastReport!.netCharge, 0);
    expect(b.notes.byId(note.id)!.body, note.body);
    expect(b.notes.byId(note.id)!.dirty, isFalse);
    expect(b.notes.byId(note.id)!.serverVersion, 1);
    final after = await diagnostic('/__fixture/state');
    expect(after['writes'], (before['writes'] as int) + 1);
    expect(ownerState(after)['energy'],
        (ownerState(before)['energy'] as int) - 10);
    expect(
        ownerState(after)['notes'], (ownerState(before)['notes'] as int) + 1);
    final other = await device(
        'other', 'atomic-disposable-other', descriptor['other'] as String);
    await other.cubit.sync(uploadAll: false);
    expect(other.notes.byId(note.id), isNull);
    expect(other.notes.count, 0);
  });

  wireTest('receive_only_preserves_actual_wallet_and_ledger', () async {
    final before = await diagnostic('/__fixture/state');
    final a = await device(
        'a', 'atomic-disposable-client-a', descriptor['owner'] as String);
    await a.cubit.sync(uploadAll: false);
    expect(a.cubit.state.lastReport!.completed, isTrue);
    expect(a.cubit.state.lastReport!.operations, isEmpty);
    expect(a.cubit.state.lastReport!.netCharge, 0);
    final after = await diagnostic('/__fixture/state');
    expect(after['writes'], before['writes']);
    expect(after['users'], before['users']);
  });

  wireTest('offline_conflict_preserves_both_versions_without_stale_drive_write',
      () async {
    final a = await device(
        'a', 'atomic-disposable-client-a', descriptor['owner'] as String);
    final b = await device(
        'b', 'atomic-disposable-client-b', descriptor['owner'] as String);
    final note = Note(id: newId(), title: 'Conflict fixture', body: 'Base');
    await a.notes.save(note);
    await a.cubit.sync(uploadAll: false);
    await b.cubit.sync(uploadAll: false);
    final offline = b.notes.byId(note.id)!;
    offline.body = 'Offline B';
    await b.notes.save(offline);
    note.body = 'Accepted A';
    await a.notes.save(note);
    await a.cubit.sync(uploadAll: false);
    final before = await diagnostic('/__fixture/state');
    final message = await b.cubit.sync(uploadAll: false);
    expect(message!.text, contains('separate copies'));
    expect(b.cubit.state.lastReport!.completed, isFalse);
    expect(b.notes.byId(note.id)!.body, 'Accepted A');
    expect(b.notes.byId(note.id)!.serverVersion, 2);
    final copy = b.notes.visible().singleWhere((value) =>
        value.id != note.id &&
        value.title == 'Conflict fixture (conflict copy)');
    expect(copy.body, 'Offline B');
    expect(copy.dirty, isTrue);
    final refused = await diagnostic('/__fixture/state');
    expect(refused['writes'], before['writes']);
    expect(ownerState(refused)['energy'], ownerState(before)['energy']);
    await b.cubit.sync(uploadAll: false);
    expect(b.cubit.state.lastReport!.completed, isTrue);
    expect(b.notes.byId(copy.id)!.dirty, isFalse);
    await a.cubit.sync(uploadAll: false);
    expect(a.notes.byId(note.id)!.body, 'Accepted A');
    expect(a.notes.byId(copy.id)!.body, 'Offline B');
  });

  wireTest('cloud_count_is_read_only_through_actual_http', () async {
    final a = await device(
        'a', 'atomic-disposable-client-a', descriptor['owner'] as String);
    final pending =
        Note(id: newId(), title: 'Only local', body: 'Unsent fixture');
    await a.notes.save(pending);
    final before = await diagnostic('/__fixture/state');
    await a.cubit.check();
    expect(a.cubit.state.cloud, ownerState(before)['notes']);
    expect(a.cubit.state.checked, isTrue);
    expect(a.notes.byId(pending.id)!.dirty, isTrue);
    expect(a.notes.byId(pending.id)!.serverVersion, 0);
    final after = await diagnostic('/__fixture/state');
    expect(after['writes'], before['writes']);
    expect(after['users'], before['users']);
  });
}
