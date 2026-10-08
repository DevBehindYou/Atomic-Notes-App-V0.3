import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/notes_source.dart' show WipeOutcome;
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

/// Hold an already committed reply while the repository starts a cloud wipe.
class _HoldCommittedPushReply extends http.BaseClient {
  _HoldCommittedPushReply(this.inner);
  final http.Client inner;
  final received = Completer<void>();
  final release = Completer<void>();
  int wipes = 0;
  bool hold = true;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'DELETE' && request.url.path == '/api/notes') wipes++;
    final response = await inner.send(request);
    if (request.method == 'POST' && request.url.path == '/api/notes/push' && hold) {
      hold = false;
      final bytes = await response.stream.toBytes();
      if (response.statusCode != 200) {
        throw StateError('Held reply requires a committed successful request');
      }
      received.complete();
      await release.future;
      return http.StreamedResponse(Stream.value(bytes), response.statusCode,
          headers: response.headers);
    }
    return response;
  }
}

/// Observe actual outgoing envelopes without altering requests or responses.
class _CapturePushes extends http.BaseClient {
  _CapturePushes(this.inner);
  final http.Client inner;
  final bodies = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' && request.url.path == '/api/notes/push') {
      bodies.add((request as http.Request).body);
    }
    return inner.send(request);
  }
}

/// Hold a fully received real count response at the client transport boundary.
class _HoldCountReply extends http.BaseClient {
  _HoldCountReply(this.inner);
  final http.Client inner;
  final received = Completer<void>();
  final release = Completer<void>();
  int? status;
  bool hold = true;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (request.url.path == '/api/notes/count' && hold) {
      hold = false;
      final bytes = await response.stream.toBytes();
      status = response.statusCode;
      received.complete();
      await release.future;
      return http.StreamedResponse(Stream.value(bytes), response.statusCode,
          headers: response.headers);
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
          {http.Client? deviceTransport,
          TestVault? vault,
          _Storage? storage}) async {
    final api = ApiClient.forTest(
        client: deviceTransport ?? transport,
        storage: storage ?? _Storage(userId, token),
        baseUrl: origin.replace(path: '/api'));
    await api.init();
    final notes = NotesRepository.forTest(
        box: await Hive.openBox('device-$name'),
        api: api,
        vault: vault ?? TestVault(),
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
            'real Flutter API/repository/Cubit to real notes/auth/admin routes; disposable Mongo; fake Drive',
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

  for (final deleteFirst in [false, true]) {
    final code = deleteFirst
        ? 'stale_edit_keeps_remote_tombstone_and_local_conflict_copy'
        : 'stale_delete_keeps_remote_edit_and_local_conflict_copy';
    wireTest(code, () async {
      // Use the otherwise read-only isolated owner with its own seeded wallet.
      // Both clients have independent Hive/storage but share this synthetic
      // bearer session. Session/device management is outside this proof.
      final uid = descriptor['other'] as String;
      final a = await device('delete-a', 'atomic-disposable-other', uid);
      final b = await device('delete-b', 'atomic-disposable-other', uid);
      Map<String, dynamic> wallet(Map<String, dynamic> state) =>
          (state['users'] as List)
              .cast<Map<String, dynamic>>()
              .singleWhere((user) => user['userId'] == uid);
      final title = deleteFirst ? 'Stale edit fixture' : 'Stale delete fixture';
      final note = Note(id: newId(), title: title, body: 'Synthetic base');
      await a.notes.save(note);
      await a.cubit.sync(uploadAll: false);
      expect(a.cubit.state.lastReport!.completed, isTrue);
      final base = a.notes.byId(note.id)!.serverVersion;
      await b.cubit.sync(uploadAll: false);
      expect(b.notes.byId(note.id)!.serverVersion, base);
      if (deleteFirst) {
        await b.notes
            .save(b.notes.byId(note.id)!..body = 'Synthetic offline edit');
        await a.notes.deleteNotes([note.id]);
      } else {
        await b.notes.deleteNotes([note.id]);
        await a.notes
            .save(a.notes.byId(note.id)!..body = 'Synthetic accepted edit');
      }
      await a.cubit.sync(uploadAll: false);
      expect(a.cubit.state.lastReport!.completed, isTrue);
      final acceptedVersion = a.notes.byId(note.id)!.serverVersion;
      expect(acceptedVersion, base + 1);
      final before = await diagnostic('/__fixture/state');
      final message = await b.cubit.sync(uploadAll: false);
      expect(message!.text, contains('separate copies'));
      expect(b.cubit.state.lastReport!.completed, isFalse);
      expect(b.cubit.state.lastReport!.operations.single.charged, 10);
      expect(b.cubit.state.lastReport!.operations.single.refunded, 10);
      expect(b.notes.byId(note.id)!.serverVersion, acceptedVersion);
      expect(b.notes.byId(note.id)!.deleted, deleteFirst);
      expect(b.notes.byId(note.id)!.dirty, isFalse);
      final copy = b.notes
          .visible()
          .singleWhere((n) => n.title == '$title (conflict copy)');
      expect(copy.id, isNot(note.id));
      expect(copy.deleted, isFalse);
      expect(
          copy.body, deleteFirst ? 'Synthetic offline edit' : 'Synthetic base');
      expect(copy.dirty, isTrue);
      final refused = await diagnostic('/__fixture/state');
      expect(refused['writes'], before['writes']);
      expect(wallet(refused)['energy'], wallet(before)['energy']);
      expect(wallet(refused)['notes'], wallet(before)['notes']);
      expect((wallet(refused)['ledger'] as List).length,
          (wallet(before)['ledger'] as List).length + 2);
      await b.cubit.sync(uploadAll: false);
      expect(b.cubit.state.lastReport!.completed, isTrue);
      expect(b.notes.byId(copy.id)!.dirty, isFalse);
      final uploaded = await diagnostic('/__fixture/state');
      expect(uploaded['writes'], (refused['writes'] as int) + 1);
      expect(
          wallet(uploaded)['energy'], (wallet(refused)['energy'] as int) - 10);
      await a.cubit.sync(uploadAll: false);
      expect(a.cubit.state.lastReport!.completed, isTrue);
      expect(a.notes.byId(copy.id)!.body, copy.body);
      expect(a.notes.byId(note.id)!.deleted, deleteFirst);
      if (!deleteFirst) {
        expect(a.notes.byId(note.id)!.body, 'Synthetic accepted edit');
        expect(b.notes.byId(note.id)!.body, 'Synthetic accepted edit');
      }
    });
  }

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

  wireTest('edit_after_committed_reply_loss_survives_restart_and_replay',
      () async {
    final before = await diagnostic('/__fixture/state');
    final fault = _DiscardCommittedReply(transport);
    final first = await device('later-edit', 'atomic-disposable-client-a',
        descriptor['owner'] as String,
        deviceTransport: fault);
    final note = Note(
        id: newId(),
        title: 'Later edit fixture',
        body: 'Synthetic committed base');
    await first.notes.save(note);
    await first.cubit.sync(uploadAll: false);
    expect(first.cubit.state.lastReport!.completed, isFalse);
    final box = Hive.box('device-later-edit');
    final pending =
        Map<String, dynamic>.from(box.get('__pending_sync_operation') as Map);
    final committed = await diagnostic('/__fixture/state');
    expect(committed['writes'], (before['writes'] as int) + 1);
    expect(ownerState(committed)['energy'],
        (ownerState(before)['energy'] as int) - 10);
    final page = await first.api.pullNotes();
    final accepted = (page['rows'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['id'] == note.id);
    expect(accepted['body'], 'Synthetic committed base');
    final acceptedVersion = accepted['version'] as int;
    await first.notes.save(
        first.notes.byId(note.id)!..body = 'Synthetic later offline edit');
    expect(box.get('__pending_sync_operation'), pending);
    expect(first.notes.byId(note.id)!.dirty, isTrue);
    await first.notes.stop(waitForSync: true);
    await first.cubit.close();
    first.notes.dispose();
    repositories.remove(first.notes);
    cubits.remove(first.cubit);
    await box.close();
    final restarted = await device('later-edit', 'atomic-disposable-client-a',
        descriptor['owner'] as String,
        deviceTransport: fault);
    expect(restarted.notes.byId(note.id)!.body, 'Synthetic later offline edit');
    expect(restarted.notes.byId(note.id)!.dirty, isTrue);
    await restarted.cubit.sync(uploadAll: false);
    final report = restarted.cubit.state.lastReport!;
    expect(report.completed, isTrue);
    expect(report.operations, hasLength(2));
    expect(report.operations.first.recovered, isTrue);
    expect(report.operations.first.requestId, pending['requestId']);
    expect(report.operations.last.recovered, isFalse);
    expect(report.operations.last.requestId, isNot(pending['requestId']));
    expect(report.netCharge, 20,
        reason: 'One historical receipt plus one new operation');
    expect(fault.bodies, hasLength(3));
    expect(fault.bodies[1], fault.bodies[0]);
    final laterRequest = jsonDecode(fault.bodies[2]) as Map;
    final laterRow = (laterRequest['rows'] as List).single as Map;
    expect(laterRow['id'], note.id);
    expect(laterRow['base_version'], acceptedVersion);
    expect(laterRow['body'], 'Synthetic later offline edit');
    expect(restarted.notes.byId(note.id)!.dirty, isFalse);
    expect(restarted.notes.byId(note.id)!.serverVersion, acceptedVersion + 1);
    expect(
        Hive.box('device-later-edit').get('__pending_sync_operation'), isNull);
    final finished = await diagnostic('/__fixture/state');
    expect(finished['writes'], (committed['writes'] as int) + 1);
    expect(ownerState(finished)['energy'],
        (ownerState(committed)['energy'] as int) - 10);
    expect((ownerState(finished)['ledger'] as List).length,
        (ownerState(committed)['ledger'] as List).length + 1);
    final remote = (await restarted.api.pullNotes())['rows'] as List;
    expect(
        remote
            .cast<Map<String, dynamic>>()
            .singleWhere((row) => row['id'] == note.id)['body'],
        'Synthetic later offline edit');
  });

  wireTest('actual_partial_failure_full_refund_and_new_request_retry',
      () async {
    Future<void> arm(List<String> ids) async {
      final response =
          await transport.post(origin.replace(path: '/__fixture/fail-writes'),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer atomic-disposable-client-a'
              },
              body: jsonEncode({'ids': ids}));
      expect(response.statusCode, 200);
      expect((jsonDecode(response.body) as Map)['armed'], ids.length);
    }

    final a = await device(
        'failure', 'atomic-disposable-client-a', descriptor['owner'] as String);
    final accepted = Note(
        id: newId(), title: 'Accepted fixture', body: 'Synthetic accepted');
    final refused =
        Note(id: newId(), title: 'Refused fixture', body: 'Synthetic refused');
    await a.notes.save(accepted);
    await a.notes.save(refused);
    final before = await diagnostic('/__fixture/state');
    await arm([refused.id]);
    try {
      await a.cubit.sync(uploadAll: false);
      final partial = a.cubit.state.lastReport!;
      expect(partial.completed, isFalse);
      expect(partial.charged, 10);
      expect(partial.refunded, 0);
      expect(partial.netCharge, 10);
      expect(a.notes.byId(accepted.id)!.dirty, isFalse);
      expect(a.notes.byId(refused.id)!.dirty, isTrue);
      expect(a.notes.pendingCount, 1);
      final committed = await diagnostic('/__fixture/state');
      expect(committed['writes'], (before['writes'] as int) + 1);
      expect(ownerState(committed)['notes'],
          (ownerState(before)['notes'] as int) + 1);
      expect(ownerState(committed)['energy'],
          (ownerState(before)['energy'] as int) - partial.netCharge!);
      expect((ownerState(committed)['ledger'] as List).length,
          (ownerState(before)['ledger'] as List).length + 1);

      await a.cubit.sync(uploadAll: false);
      final failed = a.cubit.state.lastReport!;
      expect(failed.completed, isFalse);
      expect(failed.charged, 10);
      expect(failed.refunded, 10);
      expect(failed.netCharge, 0);
      expect(failed.operations.single.requestId,
          isNot(partial.operations.single.requestId));
      expect(a.notes.byId(refused.id)!.dirty, isTrue);
      expect(a.notes.byId(accepted.id)!.dirty, isFalse);
      final refunded = await diagnostic('/__fixture/state');
      expect(refunded['writes'], committed['writes']);
      expect(ownerState(refunded)['notes'], ownerState(committed)['notes']);
      expect(ownerState(refunded)['energy'], ownerState(committed)['energy']);
      expect((ownerState(refunded)['ledger'] as List).length,
          (ownerState(committed)['ledger'] as List).length + 2);

      await arm([]);
      await a.cubit.sync(uploadAll: false);
      final recovered = a.cubit.state.lastReport!;
      expect(recovered.completed, isTrue);
      expect(recovered.netCharge, 10);
      expect(recovered.operations.single.requestId,
          isNot(failed.operations.single.requestId));
      expect(a.notes.pendingCount, 0);
      final finished = await diagnostic('/__fixture/state');
      expect(finished['writes'], (refunded['writes'] as int) + 1);
      expect(ownerState(finished)['notes'],
          (refunded['users'] as List).first['notes'] + 1);
      expect(ownerState(finished)['energy'],
          (ownerState(refunded)['energy'] as int) - 10);
    } finally {
      await arm([]);
    }
  });

  wireTest('locked_plaintext_pull_then_unlock_reloads_and_seals_cloud_rows',
      () async {
    final uid = descriptor['other'] as String;
    Map<String, dynamic> wallet(Map<String, dynamic> state) =>
        (state['users'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((user) => user['userId'] == uid);
    final aVault = TestVault();
    final a =
        await device('vault-a', 'atomic-disposable-other', uid, vault: aVault);
    final plain = Note(
        id: newId(),
        title: 'Plain wire fixture',
        body: 'Synthetic plain content');
    await a.notes.save(plain);
    await a.cubit.sync(uploadAll: false);
    expect(a.cubit.state.lastReport!.completed, isTrue);
    aVault.unlocked = true;
    final sealed = Note(
        id: newId(),
        title: 'Sealed wire fixture',
        body: 'Synthetic sealed content');
    await a.notes.save(sealed);
    await a.cubit.sync(uploadAll: false);
    expect(a.cubit.state.lastReport!.completed, isTrue);
    final allRows = (await a.api.pullNotes())['rows'] as List;
    final protected = allRows
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['id'] == sealed.id);
    expect(protected['enc_v'], greaterThan(0));
    expect(protected['title'], '');
    expect(protected['body'], '');
    expect(protected['items'], isEmpty);
    expect(protected['payload'], isA<String>());
    final bVault = TestVault();
    final b =
        await device('vault-b', 'atomic-disposable-other', uid, vault: bVault);
    final before = await diagnostic('/__fixture/state');
    await b.cubit.sync(uploadAll: false);
    expect(b.cubit.state.lastReport!.completed, isTrue);
    expect(b.cubit.state.lastReport!.operations, isEmpty);
    expect(b.notes.byId(plain.id)!.body, 'Synthetic plain content');
    expect(b.notes.byId(sealed.id), isNull);
    final filtered = await b.api.pullNotes(encOnly: true);
    expect(
        (filtered['rows'] as List)
            .cast<Map<String, dynamic>>()
            .any((row) => row['id'] == sealed.id),
        isFalse);
    final box = Hive.box('device-vault-b');
    expect(box.get(sealed.id), isNull);
    expect(box.get('__sync_cursor__'), filtered['nextCursor']);
    final locked = await diagnostic('/__fixture/state');
    expect(locked['writes'], before['writes']);
    expect(locked['users'], before['users']);
    bVault.unlocked = true;
    await b.notes.reloadAfterUnlock();
    expect(b.notes.byId(sealed.id)!.body, 'Synthetic sealed content');
    expect(b.notes.byId(plain.id)!.body, 'Synthetic plain content');
    expect(b.notes.pendingCount, 0);
    final stored = box.get(sealed.id) as Map;
    expect(stored['body'], '');
    expect(stored['title'], '');
    expect(stored['payload'], isA<String>());
    final finished = await diagnostic('/__fixture/state');
    expect(wallet(finished)['energy'], (wallet(locked)['energy'] as int) - 5);
    expect((wallet(finished)['ledger'] as List).length,
        (wallet(locked)['ledger'] as List).length + 1);
    final encryptedRows = (await b.api.pullNotes())['rows'] as List;
    for (final id in [plain.id, sealed.id]) {
      final row = encryptedRows
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row['id'] == id);
      expect(row['enc_v'], greaterThan(0));
      expect(row['title'], '');
      expect(row['body'], '');
      expect(row['payload'], isA<String>());
    }
    final remainingPlain = await b.api.pullNotes(encOnly: true);
    expect(
        (remainingPlain['rows'] as List)
            .cast<Map<String, dynamic>>()
            .any((row) => row['id'] == plain.id || row['id'] == sealed.id),
        isFalse);
  });

  wireTest('unreadable_and_mismatched_pages_preserve_cache_cursor_and_retry',
      () async {
    final uid = descriptor['owner'] as String;
    final receiver =
        await device('integrity-receiver', 'atomic-disposable-client-b', uid);
    await receiver.cubit.sync(uploadAll: false);
    expect(receiver.cubit.state.lastReport!.completed, isTrue);
    final receiverBox = Hive.box('device-integrity-receiver');
    final baseline = Map<dynamic, dynamic>.from(receiverBox.toMap());
    final savedCursor = baseline['__sync_cursor__'];
    expect(savedCursor, isA<int>());
    final writer =
        await device('integrity-writer', 'atomic-disposable-client-a', uid);
    final good = Note(
        id: newId(),
        title: 'Intact page fixture',
        body: 'Synthetic intact page row');
    final bad = Note(
        id: newId(),
        title: 'Faulted page fixture',
        body: 'Synthetic restored page row');
    await writer.notes.save(good);
    await writer.notes.save(bad);
    await writer.cubit.sync(uploadAll: false);
    expect(writer.cubit.state.lastReport!.completed, isTrue);
    final before = await diagnostic('/__fixture/state');
    Future<void> arm(String mode) async {
      final response =
          await transport.post(origin.replace(path: '/__fixture/read-fault'),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer atomic-disposable-client-a'
              },
              body: jsonEncode({'noteId': bad.id, 'mode': mode}));
      expect(response.statusCode, 200);
      expect((jsonDecode(response.body) as Map)['armed'], mode != 'none');
    }

    try {
      for (final mode in ['missing', 'corrupt', 'mismatch']) {
        outcomes['pull_integrity_phase'] = mode;
        final client = mode == 'missing'
            ? receiver
            : await device(
                'integrity-$mode', 'atomic-disposable-client-b', uid);
        final box = Hive.box(
            'device-integrity-${mode == 'missing' ? 'receiver' : mode}');
        if (mode != 'missing') {
          // An actual earlier pull's snapshot models another offline device;
          // no fabricated note versions or cursor are introduced.
          await box.putAll(baseline);
          await client.notes.start();
        }
        await arm(mode);
        for (var attempt = 0; attempt < 2; attempt++) {
          final message = await client.cubit.sync(uploadAll: false);
          expect(client.cubit.state.lastReport!.completed, isFalse);
          expect(client.cubit.state.lastReport!.operations, isEmpty);
          expect(
              message!.text,
              contains(mode == 'mismatch'
                  ? 'could not be read safely'
                  : 'missing or unreadable'));
          expect(box.toMap(), baseline);
          expect(box.get('__sync_cursor__'), savedCursor);
          expect(client.notes.byId(good.id), isNull);
          expect(client.notes.byId(bad.id), isNull);
        }
        final refused = await diagnostic('/__fixture/state');
        expect(refused['writes'], before['writes']);
        expect(refused['users'], before['users']);
        await arm('none');
        await client.cubit.sync(uploadAll: false);
        expect(client.cubit.state.lastReport!.completed, isTrue);
        expect(client.cubit.state.lastReport!.operations, isEmpty);
        expect(client.notes.lastError, isNull);
        expect(client.notes.byId(good.id)!.body, good.body);
        expect(client.notes.byId(bad.id)!.body, bad.body);
        expect(box.get('__sync_cursor__'), greaterThan(savedCursor as int));
        for (final entry in baseline.entries) {
          if (entry.key != '__sync_cursor__') {
            expect(box.get(entry.key), entry.value);
          }
        }
        final recovered = await diagnostic('/__fixture/state');
        expect(recovered['writes'], before['writes']);
        expect(recovered['users'], before['users']);
      }
      outcomes['pull_integrity_phase'] = 'passed';
    } finally {
      await arm('none');
    }
  });

  wireTest(
      'cloud_wipe_preserves_local_and_other_client_cache_without_tombstones',
      () async {
    final uid = descriptor['owner'] as String;
    final actor = await device('wipe-actor', 'atomic-disposable-client-a', uid);
    final observer =
        await device('wipe-observer', 'atomic-disposable-client-b', uid);
    for (final client in [actor, observer]) {
      await client.cubit.sync(uploadAll: false);
      expect(client.cubit.state.lastReport!.completed, isTrue);
      expect(client.cubit.state.lastReport!.operations, isEmpty);
    }
    expect(actor.notes.count, greaterThan(0));
    expect(observer.notes.count, actor.notes.count);
    final unsent = Note(
        id: newId(),
        title: 'Unsent wipe fixture',
        body: 'Synthetic offline work');
    await actor.notes.save(unsent);
    final actorBox = Hive.box('device-wipe-actor');
    final observerBox = Hive.box('device-wipe-observer');
    final actorSnapshot = Map<dynamic, dynamic>.from(actorBox.toMap());
    final observerSnapshot = Map<dynamic, dynamic>.from(observerBox.toMap());
    final actorCount = actor.notes.count;
    final pendingCount = actor.notes.pendingCount;
    final before = await diagnostic('/__fixture/state');
    await actor.cubit.check();
    expect(actor.cubit.state.cloud, greaterThan(0));
    final result = await actor.notes.wipeRemote();
    expect(result.ok, isTrue);
    expect(result.message, contains('on this device are untouched'));
    expect(actor.notes.count, actorCount);
    expect(actor.notes.pendingCount, pendingCount);
    expect(actor.notes.byId(unsent.id)!.body, unsent.body);
    expect(actor.notes.byId(unsent.id)!.dirty, isTrue);
    expect(actorBox.keys.toSet(), actorSnapshot.keys.toSet());
    for (final entry in actorSnapshot.entries) {
      final value = entry.value;
      if (value is Map && value.containsKey('id')) {
        final current =
            Map<dynamic, dynamic>.from(actorBox.get(entry.key) as Map);
        expect(current['serverVersion'], 0);
        expect(current['syncedSig'], '');
        current.remove('serverVersion');
        current.remove('syncedSig');
        final previous = Map<dynamic, dynamic>.from(value)
          ..remove('serverVersion')
          ..remove('syncedSig');
        expect(current, previous);
      } else {
        expect(actorBox.get(entry.key), value);
      }
    }
    expect(actorBox.get('__pending_sync_operation'), isNull);
    await actor.cubit.check();
    expect(actor.cubit.state.cloud, 0);
    expect(actor.cubit.state.onDevice, actorCount);
    final wiped = await diagnostic('/__fixture/state');
    expect(ownerState(wiped)['notes'], 0);
    expect(ownerState(wiped)['energy'], ownerState(before)['energy']);
    expect(ownerState(wiped)['ledger'], ownerState(before)['ledger']);
    expect(
        (wiped['users'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((user) => user['userId'] == descriptor['other']),
        (before['users'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((user) => user['userId'] == descriptor['other']));
    expect(wiped['liveFiles'], lessThan(before['liveFiles'] as int));
    await observer.cubit.sync(uploadAll: false);
    expect(observer.cubit.state.lastReport!.completed, isTrue);
    expect(observer.cubit.state.lastReport!.operations, isEmpty);
    expect(observerBox.toMap(), observerSnapshot);
    final page = await observer.api.pullNotes();
    expect(page['rows'], isEmpty);
    expect(page['nextCursor'], observerSnapshot['__sync_cursor__']);
    final fresh = await device('wipe-fresh', 'atomic-disposable-client-b', uid);
    await fresh.cubit.sync(uploadAll: false);
    expect(fresh.cubit.state.lastReport!.completed, isTrue);
    expect(fresh.cubit.state.lastReport!.operations, isEmpty);
    expect(fresh.notes.count, 0);
    expect(fresh.notes.binNotes, isEmpty);
    final afterPulls = await diagnostic('/__fixture/state');
    expect(afterPulls['writes'], wiped['writes']);
    expect(afterPulls['users'], wiped['users']);
    expect(await actor.notes.markAllForUpload(), actorCount);
    expect(actor.notes.pendingCount, actorCount);
    expect(actor.notes.count, actorCount);
    // Refill is queued only: the synthetic owner's energy is exhausted. A
    // successful new upload or simultaneous wipe/push is a separate scenario.
    final queued = await diagnostic('/__fixture/state');
    expect(queued['writes'], wiped['writes']);
    expect(queued['users'], wiped['users']);
  });

  wireTest('fifty_row_batches_preserve_waiting_work_and_charge_per_request',
      () async {
    final uid = descriptor['batchOwner'] as String;
    final capture = _CapturePushes(transport);
    final client = await device('batch-rows', 'atomic-disposable-batch', uid,
        deviceTransport: capture);
    Map<String, dynamic> wallet(Map<String, dynamic> state) =>
        (state['users'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((user) => user['userId'] == uid);
    final notes = List.generate(
        51,
        (_) => Note(
            id: newId(), title: 'Batch fixture', body: 'Synthetic batch row'));
    for (final note in notes) {
      await client.notes.save(note);
    }
    final before = await diagnostic('/__fixture/state');
    final first = await client.notes.syncWithReport(instant: false);
    expect(first.completed, isFalse);
    expect(first.errorMessage, isNull);
    expect(first.operations, hasLength(1));
    expect(first.netCharge, 5);
    expect(client.notes.pendingCount, 1);
    expect(client.notes.nextAutoSyncAt, isNotNull);
    expect(capture.bodies, hasLength(1));
    final request = jsonDecode(capture.bodies.single) as Map;
    expect(request['mode'], 'standard');
    expect(request['rows'], hasLength(50));
    expect(
        utf8.encode(capture.bodies.single).length, lessThanOrEqualTo(2500000));
    final waiting = await diagnostic('/__fixture/state');
    expect(wallet(waiting)['energy'], (wallet(before)['energy'] as int) - 5);
    expect(waiting['writes'], (before['writes'] as int) + 50);
    expect(wallet(waiting)['notes'], 50);
    final paused = await client.notes.syncWithReport(instant: false);
    expect(paused.completed, isFalse);
    expect(paused.operations, isEmpty);
    expect(client.notes.pendingCount, 1);
    expect(capture.bodies, hasLength(1));
    final stillWaiting = await diagnostic('/__fixture/state');
    expect(stillWaiting['writes'], waiting['writes']);
    expect(stillWaiting['users'], waiting['users']);
    await client.cubit.sync(uploadAll: false);
    final finishedReport = client.cubit.state.lastReport!;
    expect(finishedReport.completed, isTrue);
    expect(finishedReport.netCharge, 10);
    expect(finishedReport.operations, hasLength(1));
    expect(client.notes.pendingCount, 0);
    expect(capture.bodies, hasLength(2));
    final remaining = jsonDecode(capture.bodies.last) as Map;
    expect(remaining['mode'], 'instant');
    expect(remaining['requestId'], isNot(request['requestId']));
    expect(remaining['rows'], hasLength(1));
    final sentIds = capture.bodies.expand((body) =>
        ((jsonDecode(body) as Map)['rows'] as List)
            .map((row) => (row as Map)['id']));
    expect(sentIds.toSet(), notes.map((note) => note.id).toSet());
    expect(sentIds, hasLength(51));
    final finished = await diagnostic('/__fixture/state');
    expect(wallet(finished)['energy'], (wallet(before)['energy'] as int) - 15);
    expect((wallet(finished)['ledger'] as List).length,
        (wallet(before)['ledger'] as List).length + 2);
    expect(finished['writes'], (before['writes'] as int) + 51);
    expect(wallet(finished)['notes'], 51);
    final box = Hive.box('device-batch-rows');
    expect(box.get('__pending_sync_operation'), isNull);
    for (final note in notes) {
      expect(client.notes.byId(note.id)!.dirty, isFalse);
      expect(client.notes.byId(note.id)!.body, note.body);
      expect(client.notes.byId(note.id)!.serverVersion, greaterThan(0));
      expect((box.get(note.id) as Map)['dirty'], isFalse);
    }
  });

  wireTest(
      'utf8_envelope_budget_splits_large_rows_without_loss_or_extra_retries',
      () async {
    final uid = descriptor['batchOwner'] as String;
    final capture = _CapturePushes(transport);
    final client = await device('batch-bytes', 'atomic-disposable-batch', uid,
        deviceTransport: capture);
    Map<String, dynamic> wallet(Map<String, dynamic> state) =>
        (state['users'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((user) => user['userId'] == uid);
    final body = List.filled(60000, '雪').join();
    expect(utf8.encode(body).length, 180000);
    final notes = List.generate(
        14, (_) => Note(id: newId(), title: 'UTF-8 fixture', body: body));
    for (final note in notes) {
      await client.notes.save(note);
    }
    final before = await diagnostic('/__fixture/state');
    await client.cubit.sync(uploadAll: false);
    final report = client.cubit.state.lastReport!;
    expect(report.completed, isTrue);
    expect(report.operations, hasLength(2));
    expect(report.netCharge, 20);
    expect(client.notes.pendingCount, 0);
    expect(capture.bodies, hasLength(2));
    final first = jsonDecode(capture.bodies.first) as Map;
    final second = jsonDecode(capture.bodies.last) as Map;
    expect(first['rows'], hasLength(13));
    expect(second['rows'], hasLength(1));
    expect(first['requestId'], isNot(second['requestId']));
    for (final encoded in capture.bodies) {
      expect(utf8.encode(encoded).length, lessThanOrEqualTo(2500000));
    }
    final overflow = Map<dynamic, dynamic>.from(first)
      ..['rows'] = [...first['rows'] as List, (second['rows'] as List).single];
    expect(utf8.encode(jsonEncode(overflow)).length, greaterThan(2500000));
    final sentIds = capture.bodies.expand((encoded) =>
        ((jsonDecode(encoded) as Map)['rows'] as List)
            .map((row) => (row as Map)['id']));
    expect(sentIds.toSet(), notes.map((note) => note.id).toSet());
    expect(sentIds, hasLength(14));
    for (final note in notes) {
      expect(client.notes.byId(note.id)!.body, body);
      expect(client.notes.byId(note.id)!.dirty, isFalse);
    }
    final finished = await diagnostic('/__fixture/state');
    expect(wallet(finished)['energy'], (wallet(before)['energy'] as int) - 20);
    expect((wallet(finished)['ledger'] as List).length,
        (wallet(before)['ledger'] as List).length + 2);
    expect(wallet(finished)['notes'], (wallet(before)['notes'] as int) + 14);
    expect(finished['writes'], (before['writes'] as int) + 14);
    expect(
        Hive.box('device-batch-bytes').get('__pending_sync_operation'), isNull);
  });

  wireTest('current_revoked_session_retires_without_deleting_unsent_hive_work',
      () async {
    final uid = descriptor['owner'] as String;
    final storage = _Storage(uid, 'atomic-disposable-client-a');
    final client = await device(
        'retired-current', 'atomic-disposable-client-a', uid,
        storage: storage);
    final note = Note(
        id: newId(),
        title: 'Retired session fixture',
        body: 'Synthetic preserved offline work');
    await client.notes.save(note);
    final box = Hive.box('device-retired-current');
    final savedRow = box.get(note.id);
    final before = await diagnostic('/__fixture/state');
    final logout = await transport.post(
        origin.replace(path: '/api/auth/logout'),
        headers: {'authorization': 'Bearer atomic-disposable-client-a'});
    expect(logout.statusCode, 200);
    final ended = client.api.onSessionEnded.first;
    final report = await client.notes.syncWithReport(instant: true);
    await ended.timeout(const Duration(seconds: 5));
    expect(report.completed, isFalse);
    expect(report.charged, isNull);
    expect(report.refunded, isNull);
    expect(client.api.isSignedIn, isFalse);
    expect(client.api.currentUserId, isNull);
    expect(client.notes.count, 0);
    expect(client.notes.byId(note.id), isNull);
    expect(box.get(note.id), savedRow);
    expect((box.get(note.id) as Map)['dirty'], isTrue);
    expect(box.get('__cache_owner__'), uid);
    final pending =
        Map<dynamic, dynamic>.from(box.get('__pending_sync_operation') as Map);
    expect(pending['userId'], uid);
    expect((pending['rows'] as List).single['id'], note.id);
    await client.api.init(); // Wait for queued secure-storage deletion.
    expect(storage.values.containsKey('atomic_api_session_token'), isFalse);
    expect(storage.values.containsKey('atomic_api_user_id'), isFalse);
    final refused = await diagnostic('/__fixture/state');
    expect(refused['writes'], before['writes']);
    expect(refused['users'], before['users']);
    storage.values.addAll({
      'atomic_api_session_token': 'atomic-disposable-client-b',
      'atomic_api_user_id': uid,
      'atomic_api_user_email': 'fixture@example.test',
    });
    await client.api.init();
    await client.notes.start();
    expect(client.notes.byId(note.id)!.body, note.body);
    expect(client.notes.byId(note.id)!.dirty, isTrue);
    expect(box.get('__pending_sync_operation'), pending);
    expect(await client.api.remoteNoteCount(), 0);
    // Restoration proves original-owner access and pending preservation, not
    // upload recovery: this synthetic owner's energy is exhausted.
  });

  wireTest('late_real_401_cannot_retire_a_newer_same_owner_session', () async {
    final uid = descriptor['owner'] as String;
    final storage = _Storage(uid, 'atomic-disposable-client-a');
    final held = _HoldCountReply(transport);
    final client = await device(
        'retired-late', 'atomic-disposable-client-a', uid,
        storage: storage, deviceTransport: held);
    final note = Note(
        id: newId(),
        title: 'New session fixture',
        body: 'Synthetic current-session offline work');
    await client.notes.save(note);
    final box = Hive.box('device-retired-late');
    final snapshot = Map<dynamic, dynamic>.from(box.toMap());
    final before = await diagnostic('/__fixture/state');
    var ended = 0;
    final subscription = client.api.onSessionEnded.listen((_) => ended++);
    try {
      final staleRequest = client.api.remoteNoteCount();
      final assertion = expectLater(
          staleRequest,
          throwsA(isA<ApiException>()
              .having((error) => error.code, 'code', 'session_changed')));
      await held.received.future.timeout(const Duration(seconds: 5));
      expect(held.status, 401);
      storage.values['atomic_api_session_token'] = 'atomic-disposable-client-b';
      await client.api.init();
      final revision = client.api.sessionRevision;
      held.release.complete();
      await assertion;
      expect(client.api.sessionRevision, revision);
      expect(client.api.isSignedIn, isTrue);
      expect(client.api.currentUserId, uid);
      expect(ended, 0);
      expect(storage.values['atomic_api_session_token'],
          'atomic-disposable-client-b');
      expect(client.notes.byId(note.id)!.body, note.body);
      expect(client.notes.byId(note.id)!.dirty, isTrue);
      expect(box.toMap(), snapshot);
      expect(await client.api.remoteNoteCount(), 0);
      final after = await diagnostic('/__fixture/state');
      expect(after['writes'], before['writes']);
      expect(after['users'], before['users']);
    } finally {
      if (!held.release.isCompleted) held.release.complete();
      await subscription.cancel();
    }
  });

  for (final mode in ['partial', 'full']) {
    wireTest('${mode}_capped_refund_keeps_dirty_work_and_replays_once',
        () async {
      final uid = descriptor['owner'] as String;
      // Test-only public key in the guarded loopback fixture, never production.
      final initial = await diagnostic('/__fixture/state');
      final initialEnergy = ownerState(initial)['energy'] as int;
      if (initialEnergy < 100) {
        final grant =
            await transport.post(origin.replace(path: '/api/admin/energy'),
                headers: {
                  'content-type': 'application/json',
                  'x-admin-api-key': 'atomic-disposable-admin-key'
                },
                body: jsonEncode({
                  'user_id': uid,
                  'request_id': newId(),
                  'energy_delta': 100 - initialEnergy,
                  'coins_delta': 0,
                  'note': 'Synthetic fixture budget'
                }));
        expect(grant.statusCode, 200);
      }
      final capture = _CapturePushes(transport);
      final client = await device(
          'capped-$mode', 'atomic-disposable-client-b', uid,
          deviceTransport: capture);
      final note = Note(
          id: newId(),
          title: 'Capped refund fixture',
          body: 'Synthetic preserved offline work');
      await client.notes.save(note);
      final box = Hive.box('device-capped-$mode');
      Future<void> arm(String selected) async {
        final response = await transport.post(
            origin.replace(path: '/__fixture/refund-fault'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer atomic-disposable-client-a'
            },
            body: jsonEncode({'noteId': note.id, 'mode': selected}));
        expect(response.statusCode, 200);
      }

      final before = await diagnostic('/__fixture/state');
      await arm(mode);
      try {
        await client.cubit.sync(uploadAll: false);
        final report = client.cubit.state.lastReport!;
        final refund = mode == 'partial' ? 1 : 0;
        expect(report.completed, isFalse);
        expect(report.charged, 10);
        expect(report.refunded, refund);
        expect(report.netCharge, 10 - refund);
        expect(report.operations, hasLength(1));
        expect(client.notes.byId(note.id)!.body, note.body);
        expect(client.notes.byId(note.id)!.dirty, isTrue);
        expect(client.notes.pendingCount, 1);
        expect(box.get('__pending_sync_operation'), isNull);
        expect((box.get(note.id) as Map)['dirty'], isTrue);
        expect(capture.bodies, hasLength(1));
        final request = jsonDecode(capture.bodies.single) as Map;
        final after = await diagnostic('/__fixture/state');
        expect(after['writes'], before['writes']);
        expect(ownerState(after)['notes'], ownerState(before)['notes']);
        expect(ownerState(after)['energy'], 120);
        final grant = (mode == 'partial' ? 119 : 120) -
            ((ownerState(before)['energy'] as int) - 10);
        final addedDeltas = (ownerState(after)['ledger'] as List)
            .map((row) => (row as Map)['energyDelta'] as int)
            .toList();
        // Diagnostic reads have no order contract; preserve duplicate counts.
        for (final previous in ownerState(before)['ledger'] as List) {
          expect(addedDeltas.remove((previous as Map)['energyDelta']), isTrue);
        }
        addedDeltas.sort();
        final expectedDeltas =
            mode == 'partial' ? [-10, grant, 1] : [-10, grant];
        expectedDeltas.sort();
        expect(addedDeltas, expectedDeltas);
        final replay = await client.api.pushNotes(
            (request['rows'] as List)
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList(),
            requestId: request['requestId'] as String,
            instant: true);
        expect(replay.receipt!.charged, 10);
        expect(replay.receipt!.refunded, refund);
        expect(replay.results.single['ok'], isFalse);
        expect(replay.results.single['error'], 'note_write_failed');
        final replayed = await diagnostic('/__fixture/state');
        expect(replayed, after);
        expect(client.notes.byId(note.id)!.dirty, isTrue);
        expect(capture.bodies, hasLength(2));
        expect(capture.bodies[1], capture.bodies[0]);
        await arm('none');
        await client.cubit.sync(uploadAll: false);
        final retry = client.cubit.state.lastReport!;
        expect(retry.completed, isTrue);
        expect(retry.netCharge, 10);
        expect(retry.operations.single.requestId, isNot(request['requestId']));
        expect(client.notes.byId(note.id)!.body, note.body);
        expect(client.notes.byId(note.id)!.dirty, isFalse);
        expect(client.notes.pendingCount, 0);
        expect(box.get('__pending_sync_operation'), isNull);
        final finished = await diagnostic('/__fixture/state');
        expect(finished['writes'], (after['writes'] as int) + 1);
        expect(ownerState(finished)['notes'],
            (ownerState(after)['notes'] as int) + 1);
        expect(ownerState(finished)['energy'], 110);
        expect((ownerState(finished)['ledger'] as List).length,
            (ownerState(after)['ledger'] as List).length + 1);
      } finally {
        await arm('none');
      }
    });
  }

  wireTest('encrypted_base64_budget_splits_payloads_and_preserves_ciphertext',
      () async {
    outcomes['encrypted_batch_phase'] = 'opening_client';
    final uid = descriptor['encryptedOwner'] as String;
    final capture = _CapturePushes(transport);
    final vault = TestVault()..unlocked = true;
    final client = await device(
        'encrypted-bytes', 'atomic-disposable-encrypted', uid,
        vault: vault, deviceTransport: capture);
    Map<String, dynamic> wallet(Map<String, dynamic> state) =>
        (state['users'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((user) => user['userId'] == uid);
    final body = List.filled(42000, '雪').join();
    final notes = List.generate(16,
        (_) => Note(id: newId(), title: 'Encrypted bytes fixture', body: body));
    for (final note in notes) {
      await client.notes.save(note);
    }
    final before = await diagnostic('/__fixture/state');
    outcomes['encrypted_batch_phase'] = 'isolated_budget';
    expect(wallet(before)['notes'], 0);
    expect(wallet(before)['energy'], 100);
    await client.cubit.sync(uploadAll: false);
    final report = client.cubit.state.lastReport!;
    outcomes['encrypted_batch_phase'] = 'completed_report';
    expect(report.completed, isTrue);
    expect(report.operations, hasLength(2));
    expect(report.netCharge, 20);
    expect(client.notes.pendingCount, 0);
    expect(capture.bodies, hasLength(2));
    final first = jsonDecode(capture.bodies.first) as Map;
    final second = jsonDecode(capture.bodies.last) as Map;
    outcomes['encrypted_batch_phase'] = 'batch_shape';
    expect(first['rows'], hasLength(14));
    expect(second['rows'], hasLength(2));
    final overflow = Map<dynamic, dynamic>.from(first)
      ..['rows'] = [...first['rows'] as List, (second['rows'] as List).first];
    expect(utf8.encode(jsonEncode(overflow)).length, greaterThan(2500000));
    final sent = <String>{};
    outcomes['encrypted_batch_phase'] = 'cipher_envelopes';
    for (final envelope in capture.bodies) {
      expect(utf8.encode(envelope).length, lessThanOrEqualTo(2500000));
      for (final entry in (jsonDecode(envelope) as Map)['rows'] as List) {
        final row = entry as Map;
        expect(sent.add(row['id'] as String), isTrue);
        expect(row['enc_v'], 1);
        expect(row['title'], '');
        expect(row['body'], '');
        expect(row['items'], isEmpty);
        final payload = row['payload'] as String;
        expect(base64Decode(payload).length,
            greaterThan(utf8.encode(body).length));
        expect(payload.length, greaterThan(168000));
        final decoded = await vault.decryptContent(payload);
        outcomes['encrypted_batch_phase'] = 'decrypted_content';
        expect(decoded['body'], body);
        expect(decoded['title'], 'Encrypted bytes fixture');
      }
    }
    expect(sent, notes.map((note) => note.id).toSet());
    final box = Hive.box('device-encrypted-bytes');
    outcomes['encrypted_batch_phase'] = 'sealed_hive';
    for (final note in notes) {
      expect(client.notes.byId(note.id)!.body, body);
      expect(client.notes.byId(note.id)!.dirty, isFalse);
      final stored = box.get(note.id) as Map;
      expect(stored['title'], '');
      expect(stored['body'], '');
      expect(stored['payload'], isA<String>());
    }
    expect(box.get('__pending_sync_operation'), isNull);
    final after = await diagnostic('/__fixture/state');
    outcomes['encrypted_batch_phase'] = 'final_wallet';
    expect(after['writes'], (before['writes'] as int) + 16);
    expect(wallet(after)['notes'], 16);
    expect(wallet(after)['energy'], 80);
    expect((wallet(after)['ledger'] as List).length,
        (wallet(before)['ledger'] as List).length + 2);
    outcomes['encrypted_batch_phase'] = 'passed';
  });

  wireTest('locked_large_cipher_pages_reload_and_decrypt_without_upload_charge',
      () async {
    outcomes['encrypted_receiver_phase'] = 'opening_client';
    final uid = descriptor['encryptedOwner'] as String;
    final vault = TestVault();
    final client = await device(
        'encrypted-receiver', 'atomic-disposable-encrypted', uid,
        vault: vault);
    final before = await diagnostic('/__fixture/state');
    await client.cubit.sync(uploadAll: false);
    outcomes['encrypted_receiver_phase'] = 'locked_report';
    expect(client.cubit.state.lastReport!.completed, isTrue);
    expect(client.cubit.state.lastReport!.netCharge, 0);
    expect(client.notes.count, 0);
    final box = Hive.box('device-encrypted-receiver');
    outcomes['encrypted_receiver_phase'] = 'locked_cursor';
    expect(box.get('__sync_cursor__'), 16);
    final locked = await diagnostic('/__fixture/state');
    expect(locked['writes'], before['writes']);
    expect(locked['users'], before['users']);
    vault.unlocked = true;
    await client.notes.reloadAfterUnlock();
    outcomes['encrypted_receiver_phase'] = 'unlocked_content';
    final body = List.filled(42000, '雪').join();
    expect(client.notes.count, 16);
    expect(client.notes.pendingCount, 0);
    expect(box.get('__sync_cursor__'), 16);
    for (final note in client.notes.visible()) {
      expect(note.body, body);
      expect(note.title, 'Encrypted bytes fixture');
      expect(note.dirty, isFalse);
      final stored = box.get(note.id) as Map;
      expect(stored['title'], '');
      expect(stored['body'], '');
      expect(stored['payload'], isA<String>());
    }
    final after = await diagnostic('/__fixture/state');
    outcomes['encrypted_receiver_phase'] = 'free_reload';
    expect(after['writes'], before['writes']);
    expect(after['users'], before['users']);
    expect(box.get('__pending_sync_operation'), isNull);
    outcomes['encrypted_receiver_phase'] = 'passed';
  });

  wireTest(
      'oversized_ciphertext_preserves_dirty_work_and_smaller_edit_retries_cleanly',
      () async {
    outcomes['oversized_cipher_phase'] = 'opening_client';
    final uid = descriptor['encryptedOwner'] as String;
    final capture = _CapturePushes(transport);
    final vault = TestVault()..unlocked = true;
    final client = await device(
        'oversized-cipher', 'atomic-disposable-encrypted', uid,
        vault: vault, deviceTransport: capture);
    final largeBody = List.filled(60000, '雪').join();
    final note =
        Note(id: newId(), title: 'Oversized cipher fixture', body: largeBody);
    await client.notes.save(note);
    final before = await diagnostic('/__fixture/state');
    await client.cubit.sync(uploadAll: false);
    outcomes['oversized_cipher_phase'] = 'refused_report';
    expect(client.cubit.state.lastReport!.completed, isFalse);
    expect(client.cubit.state.lastReport!.errorMessage, isNotNull);
    expect(client.cubit.state.lastReport!.charged, isNull);
    expect(client.notes.byId(note.id)!.body, largeBody);
    expect(client.notes.byId(note.id)!.dirty, isTrue);
    expect(capture.bodies, hasLength(1));
    final envelope = jsonDecode(capture.bodies.single) as Map;
    expect(((envelope['rows'] as List).single as Map)['payload'].length,
        greaterThan(196608));
    final box = Hive.box('device-oversized-cipher');
    outcomes['oversized_cipher_phase'] = 'invalid_request_cleared';
    expect(box.get('__pending_sync_operation'), isNull);
    final refused = await diagnostic('/__fixture/state');
    expect(refused['writes'], before['writes']);
    expect(refused['users'], before['users']);
    note.body = 'Synthetic smaller replacement';
    await client.notes.save(note);
    await client.cubit.sync(uploadAll: false);
    outcomes['oversized_cipher_phase'] = 'corrected_report';
    expect(client.cubit.state.lastReport!.completed, isTrue);
    expect(client.cubit.state.lastReport!.netCharge, 10);
    expect(client.notes.byId(note.id)!.body, note.body);
    expect(client.notes.byId(note.id)!.dirty, isFalse);
    expect(capture.bodies, hasLength(2));
    final corrected = jsonDecode(capture.bodies[1]) as Map;
    outcomes['oversized_cipher_phase'] = 'fresh_envelope';
    expect(corrected['requestId'], isNot(envelope['requestId']));
    expect(capture.bodies[1], isNot(capture.bodies[0]));
    expect(box.get('__pending_sync_operation'), isNull);
    final after = await diagnostic('/__fixture/state');
    outcomes['oversized_cipher_phase'] = 'final_wallet';
    expect(after['writes'], (before['writes'] as int) + 1);
    final walletBefore = (before['users'] as List)
        .cast<Map>()
        .singleWhere((user) => user['userId'] == uid);
    final walletAfter = (after['users'] as List)
        .cast<Map>()
        .singleWhere((user) => user['userId'] == uid);
    expect(walletAfter['energy'], (walletBefore['energy'] as int) - 10);
    expect(walletAfter['notes'], (walletBefore['notes'] as int) + 1);
    outcomes['oversized_cipher_phase'] = 'passed';
  });

  wireTest('cloud_wipe_waits_for_committed_reply_and_preserves_local_reset',
      () async {
    final uid = descriptor['owner'] as String;
    // The earlier cases exhausted this disposable owner's budget. Use the
    // existing real admin route with the public loopback-only fixture key.
    final initial = await diagnostic('/__fixture/state');
    final energy = ownerState(initial)['energy'] as int;
    if (energy < 100) {
      final grant = await transport.post(
          origin.replace(path: '/api/admin/energy'),
          headers: {
            'content-type': 'application/json',
            'x-admin-api-key': 'atomic-disposable-admin-key'
          },
          body: jsonEncode({
            'user_id': uid,
            'request_id': newId(),
            'energy_delta': 100 - energy,
            'coins_delta': 0,
            'note': 'Synthetic held-reply fixture budget'
          }));
      expect(grant.statusCode, 200);
    }
    final held = _HoldCommittedPushReply(transport);
    final client = await device('wipe-held-reply',
        'atomic-disposable-client-b', uid, deviceTransport: held);
    final note = Note(id: newId(), title: 'Held receipt wipe fixture',
        body: 'Synthetic local text survives the wipe');
    await client.notes.save(note);
    final before = await diagnostic('/__fixture/state');
    final syncing = client.notes.syncWithReport(instant: true);
    Future<WipeOutcome>? wiping;
    try {
      await held.received.future.timeout(const Duration(seconds: 20));
      final committed = await diagnostic('/__fixture/state');
      expect(ownerState(committed)['notes'],
          (ownerState(before)['notes'] as int) + 1);
      expect(ownerState(committed)['energy'],
          (ownerState(before)['energy'] as int) - 10);
      expect((ownerState(committed)['ledger'] as List).length,
          (ownerState(before)['ledger'] as List).length + 1);
      wiping = client.notes.wipeRemote();
      await Future<void>.delayed(Duration.zero);
      expect(held.wipes, 0, reason: 'Consume the receipt before deleting cloud rows');
      expect(client.notes.isSyncing, isTrue);
      held.release.complete();
      expect((await syncing).completed, isTrue);
      expect((await wiping).ok, isTrue);
      expect(held.wipes, 1);
      final current = client.notes.byId(note.id)!;
      expect(current.body, note.body);
      expect(current.dirty, isFalse);
      expect(current.serverVersion, 0);
      expect(current.syncedSig, '');
      final box = Hive.box('device-wipe-held-reply');
      expect((box.get(note.id) as Map)['body'], note.body);
      expect((box.get(note.id) as Map)['serverVersion'], 0);
      expect((box.get(note.id) as Map)['syncedSig'], '');
      expect(box.get('__pending_sync_operation'), isNull);
      final wiped = await diagnostic('/__fixture/state');
      expect(ownerState(wiped)['notes'], 0);
      expect(ownerState(wiped)['energy'], ownerState(committed)['energy']);
      expect(ownerState(wiped)['ledger'], ownerState(committed)['ledger']);
      expect(wiped['writes'], committed['writes']);
      expect(wiped['liveFiles'], lessThan(committed['liveFiles'] as int));
      expect((wiped['users'] as List).cast<Map>().singleWhere(
          (user) => user['userId'] == descriptor['other']),
          (before['users'] as List).cast<Map>().singleWhere(
          (user) => user['userId'] == descriptor['other']));
    } finally {
      if (!held.release.isCompleted) held.release.complete();
      await syncing;
      if (wiping != null) await wiping;
    }
  });
}
