import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/note_quota.dart';
import 'package:flutter_test/flutter_test.dart';

class WalletApi implements ApiClient {
  String? user = 'a';
  int revision = 0;
  final requests = <Completer<Map<String, dynamic>>>[];
  Completer<Map<String, dynamic>>? purchase;
  @override
  String? get currentUserId => user;
  @override
  int get sessionRevision => revision;
  @override
  Future<Map<String, dynamic>> energyState() {
    final request = Completer<Map<String, dynamic>>();
    requests.add(request);
    return request.future;
  }
  @override
  Future<Map<String, dynamic>> upgradeNoteLimit(int fromLimit) {
    purchase = Completer<Map<String, dynamic>>();
    return purchase!.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> wallet(int coins, int limit) => {
  'wallet': {'coins': coins, 'energy': 20, 'energy_cap': 120, 'note_limit': limit},
  'history': <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WalletApi api;
  late EnergyService service;
  setUp(() async { await NoteQuota.reset(); api = WalletApi(); service = EnergyService.forTest(api); });
  tearDown(() async { service.dispose(); await NoteQuota.reset(); });

  test('R9 old account refresh cannot alter the new wallet quota or loading flag', () async {
    final old = service.refresh();
    service.clear();
    api.user = 'b'; api.revision++;
    final current = service.refresh();
    api.requests[0].complete(wallet(999, 100));
    await old;
    expect(service.coins, 0);
    expect(NoteQuota.limit, 30);
    expect(service.loading, isTrue);
    api.requests[1].complete(wallet(3, 40));
    await current;
    expect(service.coins, 3);
    expect(NoteQuota.limit, 40);
    expect(service.loading, isFalse);
  });

  test('R9 re-login to the same account invalidates an earlier refresh', () async {
    final old = service.refresh();
    service.clear(); api.revision++;
    api.requests.single.complete(wallet(999, 100));
    await old;
    expect(service.coins, 0);
    expect(NoteQuota.limit, 30);
    expect(service.hasLoaded, isFalse);
  });

  test('R9 overlapping refreshes keep the newest result', () async {
    final old = service.refresh(), current = service.refresh();
    api.requests[1].complete(wallet(4, 50));
    await current;
    api.requests[0].complete(wallet(999, 100));
    await old;
    expect(service.coins, 4);
    expect(NoteQuota.limit, 50);
  });

  test('R9 a delayed purchase cannot adopt its result after account switch', () async {
    final result = service.upgradeNoteLimit();
    service.clear(); api.user = 'b'; api.revision++;
    api.purchase!.complete(wallet(99, 100));
    expect(await result, 'Your session changed. Please retry.');
    expect(service.coins, 0);
    expect(NoteQuota.limit, 30);
    expect(api.requests, isEmpty);
  });
}
