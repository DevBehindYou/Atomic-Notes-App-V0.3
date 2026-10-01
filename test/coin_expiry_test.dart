import 'dart:async';
import 'dart:convert';
import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/page/endpage/energy_page.dart';
import 'package:atomic_notes/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'support/fake_energy_store.dart';
import 'support/fake_notes_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  setUp(() => FlutterSecureStorage.setMockInitialValues({
    'atomic_api_session_token': 'fixture', 'atomic_api_user_id': 'user-a',
  }));
  Future<ApiClient> client(Future<http.Response> Function(http.Request) respond) async {
    final transport = MockClient((r) async => r.method == 'GET' && r.url.path.endsWith('/energy')
        ? http.Response('{"coin_request_replay":true}', 200) : respond(r));
    addTearDown(transport.close);
    final api = ApiClient.forTest(client: transport, storage: storage, baseUrl: Uri.parse('https://fixture.invalid/api'));
    await api.init(); return api;
  }
  test('an older Server cannot receive or replay a monetary request it cannot deduplicate', () async {
    var posts = 0;
    final transport = MockClient((r) async { if (r.method == 'POST') posts++; return http.Response('{}', 200); });
    addTearDown(transport.close);
    final api = ApiClient.forTest(client: transport, storage: storage, baseUrl: Uri.parse('https://fixture.invalid/api'));
    await api.init();
    await expectLater(api.energyConvert(1), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'coin_replay_unavailable')));
    expect(posts, 0); expect(await api.pendingCoinConversion(), isNull);
  });
  test('conversion retains request ID across response loss and restart; a new conversion gets another', () async {
    final sent = <Map<String, dynamic>>[];
    final first = await client((r) async {
      sent.add(jsonDecode(r.body) as Map<String, dynamic>);
      throw TimeoutException('lost response');
    });
    await expectLater(first.energyConvert(1), throwsA(isA<TimeoutException>()));
    final restarted = await client((r) async {
      sent.add(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    });
    expect(await restarted.pendingCoinConversion(), 1);
    await expectLater(restarted.energyConvert(2), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'coin_conversion_pending_1')));
    await restarted.energyConvert(1);
    expect(sent[0], sent[1]);
    expect(await restarted.pendingCoinConversion(), isNull);
    await restarted.energyConvert(1);
    expect(sent[2]['request_id'], isNot(sent[1]['request_id']));
  });
  test('pending conversion is isolated by account; explicit refusal clears only its own request', () async {
    final first = await client((_) async => throw TimeoutException('lost response'));
    await expectLater(first.energyConvert(1), throwsA(isA<TimeoutException>()));
    await storage.write(key: 'atomic_api_user_id', value: 'user-b');
    final other = await client((_) async => http.Response('{"error":"insufficient_coins"}', 409));
    expect(await other.pendingCoinConversion(), isNull);
    await expectLater(other.energyConvert(2), throwsA(isA<ApiException>()));
    expect(await other.pendingCoinConversion(), isNull);
    await storage.write(key: 'atomic_api_user_id', value: 'user-a');
    await other.init();
    expect(await other.pendingCoinConversion(), 1);
  });
  test('concurrent taps do not send two conversion requests', () async {
    final entered = Completer<void>(), response = Completer<http.Response>();
    var calls = 0;
    final api = await client((_) { calls++; entered.complete(); return response.future; });
    final first = api.energyConvert(1); await entered.future;
    await expectLater(api.energyConvert(1), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'coin_conversion_busy')));
    response.complete(http.Response('{}', 200)); await first;
    expect(calls, 1);
  });
  final data = <String, dynamic>{
    'enabled': true, 'non_expiring_coins': 40, 'next_expiry_coins': 20,
    'next_expiry_at': '2027-02-28T12:00:00.000Z', 'server_time': '2026-10-01T12:00:00.000Z',
    'next_cursor': null, 'rows': [
      {'id': 'legacy', 'source': 'legacy', 'amount': 40, 'remaining': 40, 'credited_at': '2026-10-01T12:00:00.000Z', 'expires_at': null},
      {'id': 'new', 'source': 'controller', 'amount': 50, 'remaining': 20, 'credited_at': '2026-08-30T12:00:00.000Z', 'expires_at': '2027-02-28T12:00:00.000Z'},
    ],
  };
  test('old wallet remains compatible; new batch dates retain exact instants in local time', () {
    expect(Wallet.fromMap(const {'coins': 5}).coinDetails, isNull);
    final wallet = Wallet.fromMap({'coins': 60, 'coin_details': data});
    expect(wallet.coinDetails!.nonExpiring, 40);
    expect(wallet.coinDetails!.rows[0].expiresAt, isNull);
    expect(wallet.coinDetails!.rows[1].expiresAt!.toUtc(), DateTime.utc(2027, 2, 28, 12));
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('expiry batches remain readable at 375px, text scale $scale', (tester) async {
      tester.view.devicePixelRatio = 1; tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
      final store = FakeEnergyStore(wallet: Wallet.fromMap({'coins': 60, 'coin_details': data}));
      final notes = FakeNotesSource(); addTearDown(store.dispose); addTearDown(notes.dispose);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: EnergyPage(store: store, notes: notes)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('COIN EXPIRY'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('40 coins never expire.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Credit batches'), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Credit batches'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credit batches')); await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('20 of 50 coins remaining'), 150, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      expect(store.converted, isEmpty);
    });
  }
}
