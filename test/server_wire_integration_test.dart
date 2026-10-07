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
import 'support/server_fixture_transport.dart';

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

/// Withhold one fully received real push reply from ApiClient after commit.
/// The surrounding fixture owns the borrowed transport.
class _DiscardCommittedReply extends http.BaseClient {
  _DiscardCommittedReply(this.inner);
  final http.Client inner;
  final bodies = <String>[];
  bool discard = true;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final push =
        request.method == 'POST' && request.url.path == '/api/notes/push';
    if (push) bodies.add((request as http.Request).body);
    final response = await inner.send(request);
    if (push && discard) {
      discard = false;
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw StateError('Committed reply fixture requires successful push');
      }
      await response.stream.drain<void>();
      throw http.ClientException('Fixture withheld committed push reply');
    }
    return response;
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
      device(String name, String token, String userId,
          {http.Client? deviceTransport}) async {
    final api = ApiClient.forTest(
        client: deviceTransport ?? transport,
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
    outcomes['setup'] = 'validating_origin';
    origin = serverFixtureOrigin(configuredOrigin);
    transport = serverFixtureTransport();
    ownedTransport = transport;
    outcomes['setup'] = 'requesting_ready';
    descriptor = await diagnostic('/__fixture/ready');
    outcomes['setup'] = 'opening_hive';
    directory = await Directory.systemTemp.createTemp('atomic-server-wire-');
    ownedDirectory = directory;
    Hive.init(directory.path);
    SyncStatusHelper.syncBox = await Hive.openBox<bool>('isolated-wire-sync');
    outcomes['setup'] = 'passed';
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
    outcomes['conflict_phase'] = 'opening_clients';
    final a = await device(
        'a', 'atomic-disposable-client-a', descriptor['owner'] as String);
    final b = await device(
        'b', 'atomic-disposable-client-b', descriptor['owner'] as String);
    final note = Note(id: newId(), title: 'Conflict fixture', body: 'Base');
    await a.notes.save(note);
    await a.cubit.sync(uploadAll: false);
    outcomes['conflict_phase'] = 'base_uploaded';
    expect(a.cubit.state.lastReport!.completed, isTrue);
    final baseVersion = a.notes.byId(note.id)!.serverVersion;
    expect(baseVersion, greaterThan(0));
    await b.cubit.sync(uploadAll: false);
    expect(b.notes.byId(note.id)!.serverVersion, baseVersion);
    final offline = b.notes.byId(note.id)!;
    offline.body = 'Offline B';
    await b.notes.save(offline);
    note.body = 'Accepted A';
    await a.notes.save(note);
    await a.cubit.sync(uploadAll: false);
    outcomes['first_client_edit'] =
        a.cubit.state.lastReport!.completed ? 'completed' : 'failed';
    expect(a.cubit.state.lastReport!.completed, isTrue);
    final acceptedVersion = baseVersion + 1;
    expect(a.notes.byId(note.id)!.serverVersion, acceptedVersion);
    outcomes['conflict_phase'] = 'remote_edit_uploaded';
    final before = await diagnostic('/__fixture/state');
    final message = await b.cubit.sync(uploadAll: false);
    outcomes['conflict_phase'] = 'checking_conflict_message';
    expect(message!.text, contains('separate copies'));
    outcomes['conflict_phase'] = 'checking_conflict_report';
    expect(b.cubit.state.lastReport!.completed, isFalse);
    final page = await b.api.pullNotes();
    final serverOriginal = (page['rows'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['id'] == note.id);
    outcomes['server_original_body'] =
        serverOriginal['body'] == 'Accepted A' ? 'expected' : 'different';
    outcomes['server_original_version'] =
        serverOriginal['version'] == acceptedVersion ? 'expected' : 'different';
    outcomes['client_original_version'] =
        b.notes.byId(note.id)!.serverVersion == acceptedVersion
            ? 'expected'
            : 'different';
    outcomes['conflict_phase'] = 'checking_remote_original_body';
    expect(b.notes.byId(note.id)!.body, 'Accepted A');
    outcomes['conflict_phase'] = 'checking_remote_original_version';
    expect(b.notes.byId(note.id)!.serverVersion, acceptedVersion);
    outcomes['conflict_phase'] = 'checking_local_copy';
    final copy = b.notes.visible().singleWhere((value) =>
        value.id != note.id &&
        value.title == 'Conflict fixture (conflict copy)');
    expect(copy.body, 'Offline B');
    expect(copy.dirty, isTrue);
    outcomes['conflict_phase'] = 'checking_no_stale_write';
    final refused = await diagnostic('/__fixture/state');
    expect(refused['writes'], before['writes']);
    outcomes['conflict_phase'] = 'checking_refund';
    expect(ownerState(refused)['energy'], ownerState(before)['energy']);
    outcomes['conflict_phase'] = 'sending_copy';
    await b.cubit.sync(uploadAll: false);
    outcomes['conflict_phase'] = 'checking_copy_acknowledgement';
    expect(b.cubit.state.lastReport!.completed, isTrue);
    expect(b.notes.byId(copy.id)!.dirty, isFalse);
    outcomes['conflict_phase'] = 'receiving_copy_on_first_client';
    await a.cubit.sync(uploadAll: false);
    expect(a.notes.byId(note.id)!.body, 'Accepted A');
    expect(a.notes.byId(copy.id)!.body, 'Offline B');
    outcomes['conflict_phase'] = 'passed';
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

  wireTest('committed_reply_discard_restart_replays_without_second_charge',
      () async {
    final before = await diagnostic('/__fixture/state');
    final fault = _DiscardCommittedReply(transport);
    final first = await device(
        'replay', 'atomic-disposable-client-a', descriptor['owner'] as String,
        deviceTransport: fault);
    final note =
        Note(id: newId(), title: 'Replay fixture', body: 'Synthetic replay');
    await first.notes.save(note);
    await first.cubit.sync(uploadAll: false);
    expect(first.cubit.state.lastReport!.completed, isFalse);
    expect(first.cubit.state.lastReport!.netCharge, isNull);
    expect(first.notes.byId(note.id)!.dirty, isTrue);
    final box = Hive.box('device-replay');
    final pending =
        Map<String, dynamic>.from(box.get('__pending_sync_operation') as Map);
    final committed = await diagnostic('/__fixture/state');
    expect(committed['writes'], (before['writes'] as int) + 1);
    expect(ownerState(committed)['notes'],
        (ownerState(before)['notes'] as int) + 1);
    expect(ownerState(committed)['energy'],
        (ownerState(before)['energy'] as int) - 10);
    await first.notes.stop(waitForSync: true);
    await first.cubit.close();
    first.notes.dispose();
    repositories.remove(first.notes);
    cubits.remove(first.cubit);
    await box.close();
    final restarted = await device(
        'replay', 'atomic-disposable-client-a', descriptor['owner'] as String,
        deviceTransport: fault);
    expect(restarted.notes.byId(note.id)!.dirty, isTrue);
    await restarted.cubit.sync(uploadAll: false);
    final report = restarted.cubit.state.lastReport!;
    expect(report.completed, isTrue);
    expect(report.operations.single.recovered, isTrue);
    expect(report.operations.single.requestId, pending['requestId']);
    expect(report.netCharge, 10,
        reason: 'Historical receipt, not a second debit');
    expect(fault.bodies, hasLength(2));
    expect(fault.bodies.last, fault.bodies.first);
    expect(restarted.notes.byId(note.id)!.dirty, isFalse);
    expect(restarted.notes.byId(note.id)!.serverVersion, greaterThan(0));
    expect(Hive.box('device-replay').get('__pending_sync_operation'), isNull);
    final replayed = await diagnostic('/__fixture/state');
    expect(replayed['writes'], committed['writes']);
    expect(replayed['users'], committed['users']);
  });
}
