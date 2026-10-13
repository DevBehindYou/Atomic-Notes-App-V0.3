import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/api/user_sessions.dart';
import 'package:atomic_notes/page/endpage/user_sessions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const currentHandle = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const otherHandle = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

Map<String, Object?> row(
  String handle, {
  bool current = false,
  String? label = 'Public client hint',
}) => {
  'session_handle': handle,
  'created_at': '2026-10-01T12:00:00.000Z',
  'expires_at': current
      ? '2027-03-30T12:00:00.000Z'
      : '2026-10-08T12:00:00.000Z',
  'is_current': current,
  'agent_label': label,
};
Map<String, Object?> inventory({bool other = true}) => {
  'limit': 5,
  'sessions': [row(currentHandle, current: true), if (other) row(otherHandle)],
};
http.Response response(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  late ApiClient api;
  late MockClient transport;
  late List<http.Request> requests;
  late List<Completer<http.Response>> ownedReplies;
  late Future<http.Response> Function(http.Request) handler;

  Future<void> newerSession({String owner = 'user-a'}) async {
    await storage.write(
      key: 'atomic_api_session_token',
      value: 'public-new-session',
    );
    await storage.write(key: 'atomic_api_user_id', value: owner);
    await api.init();
  }

  Future<void> show(
    WidgetTester tester, {
    double width = 430,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1600),
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: UserSessionsPage(api: api),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tap(tester, 'end-$otherHandle');
    await tester.pump(const Duration(milliseconds: 250));
    await tap(tester, 'confirm-session-revoke');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
  }

  Completer<http.Response> hold() {
    final reply = Completer<http.Response>();
    ownedReplies.add(reply);
    return reply;
  }

  void caseTest(
    String name,
    String code,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(name, (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'atomic_api_session_token': 'public-original-session',
        'atomic_api_user_id': 'user-a',
        'atomic_api_user_email': 'public@example.test',
      });
      requests = [];
      ownedReplies = [];
      handler = (_) async => response(inventory());
      transport = MockClient((request) {
        requests.add(request);
        return handler(request);
      });
      api = ApiClient.forTest(
        client: transport,
        storage: storage,
        baseUrl: Uri.parse('https://fixture.invalid/api'),
      );
      // Fixed stage codes expose a stalled fixture without retaining payloads.
      // ignore: avoid_print
      print('atomic_sessions_stage:$code:init');
      await api.init();
      addTearDown(() async {
        // Unmount first, then drain every response owned by this case. Never
        // leave a page callback or failed response parked beyond cleanup.
        await tester.pumpWidget(const SizedBox());
        for (final reply in ownedReplies) {
          if (!reply.isCompleted) {
            reply.complete(response({'sessions': [], 'limit': 5}));
          }
        }
        await tester.pump();
        await api.init();
        await tester.pump();
        transport.close();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        expect(tester.takeException(), isNull);
        // Fixed case code only; the proof runner never retains raw messages.
        // ignore: avoid_print
        print('atomic_sessions_cleanup:$code');
      });
      // ignore: avoid_print
      print('atomic_sessions_stage:$code:body');
      await body(tester);
    });
  }

  caseTest(
    'session inventory shows stored dates current guidance and unverified hints',
    'inventory_render',
    (tester) async {
      await show(tester, width: 375, scale: 2);
      expect(find.text('THIS SIGN-IN'), findsOneWidget);
      expect(
        find.textContaining('Older sign-ins can have earlier deadlines'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('end-$currentHandle')), findsNothing);
      expect(find.textContaining('Use Logout in Settings'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('session-$otherHandle')),
      );
      await tester.pump();
      expect(find.textContaining('Client hint (unverified)'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  caseTest(
    'session load error can retry without changing authentication',
    'load_retry',
    (tester) async {
      var reads = 0;
      handler = (_) async => ++reads == 1
          ? throw http.ClientException('public synthetic offline')
          : response(inventory());
      await show(tester);
      expect(find.textContaining('Could not load or update'), findsOneWidget);
      await tap(tester, 'retry-sessions');
      await tester.pump();
      expect(find.text('THIS SIGN-IN'), findsOneWidget);
      expect(api.isSignedIn, isTrue);
      expect(reads, 2);
    },
  );
  caseTest('empty session inventory remains refreshable', 'empty_refresh', (
    tester,
  ) async {
    handler = (_) async => response({'sessions': [], 'limit': 5});
    await show(tester);
    expect(find.textContaining('No sign-ins were returned'), findsOneWidget);
    await tap(tester, 'refresh-sessions');
    await tester.pump();
    expect(requests, hasLength(2));
  });
  caseTest('cancelled session confirmation sends no revoke', 'cancel_confirm', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'end-$otherHandle');
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Unsynced notes remain'), findsOneWidget);
    await tap(tester, 'cancel-session-revoke');
    await tester.pump(const Duration(milliseconds: 250));
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
  });
  caseTest(
    'confirmed other session revoke refreshes once and keeps current login',
    'revoke_confirm',
    (tester) async {
      var ended = false;
      handler = (request) async {
        if (request.method == 'POST') {
          ended = true;
          return response({'ok': true});
        }
        return response(inventory(other: !ended));
      };
      await show(tester);
      await confirm(tester);
      await tester.pump();
      final posts = requests
          .where((request) => request.method == 'POST')
          .toList();
      expect(posts, hasLength(1));
      expect(posts.single.url.path, '/api/auth/sessions/revoke');
      expect(jsonDecode(posts.single.body), {'session_handle': otherHandle});
      expect(find.byKey(const ValueKey('session-$otherHandle')), findsNothing);
      expect(api.currentUserId, 'user-a');
      expect(api.isSignedIn, isTrue);
    },
  );
  caseTest(
    'protected session revoke displays refusal without bypassing safe logout',
    'protected_revoke',
    (tester) async {
      handler = (request) async => request.method == 'POST'
          ? response({'error': 'session_logout_active'}, status: 409)
          : response(inventory());
      await show(tester);
      await confirm(tester);
      expect(find.textContaining('unfinished safe logout'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-$otherHandle')),
        findsOneWidget,
      );
      expect(api.isSignedIn, isTrue);
      expect(
        requests.any((request) => request.url.path == '/api/auth/logout'),
        isFalse,
      );
    },
  );
  caseTest(
    'ambiguous revoke retries the identical handle and serializes writes',
    'ambiguous_retry',
    (tester) async {
      var posts = 0, ended = false;
      handler = (request) async {
        if (request.method == 'POST') {
          if (++posts == 1) {
            throw http.ClientException('public synthetic reply lost');
          }
          ended = true;
          return response({'ok': true});
        }
        return response(inventory(other: !ended));
      };
      await show(tester);
      await confirm(tester);
      expect(find.textContaining('Could not confirm whether'), findsOneWidget);
      await tap(tester, 'end-$otherHandle');
      expect(posts, 1);
      await tap(tester, 'retry-sessions');
      await tester.pump();
      final payloads = requests
          .where((request) => request.method == 'POST')
          .map((request) => request.body)
          .toList();
      expect(payloads, hasLength(2));
      expect(payloads[0], payloads[1]);
      expect(api.isSignedIn, isTrue);
    },
  );
  for (final sameOwner in [false, true]) {
    caseTest(
      'late inventory is hidden after ${sameOwner ? 'same-owner reauthentication' : 'another account login'}',
      sameOwner ? 'same_owner_read' : 'foreign_read',
      (tester) async {
        final held = hold();
        handler = (_) => held.future;
        await show(tester);
        await newerSession(owner: sameOwner ? 'user-a' : 'user-b');
        held.complete(response(inventory()));
        await tester.pump();
        await tester.pump();
        expect(find.text('THIS SIGN-IN'), findsNothing);
        expect(find.textContaining('Your sign-in changed'), findsOneWidget);
        expect(api.currentUserId, sameOwner ? 'user-a' : 'user-b');
      },
    );
  }
  caseTest(
    'unmounted session page ignores its late inventory',
    'unmount_read',
    (tester) async {
      final held = hold();
      handler = (_) => held.future;
      await show(tester);
      await tester.pumpWidget(const MaterialApp(home: Text('Replacement')));
      held.complete(response(inventory()));
      await tester.pump();
      await tester.pump();
      expect(find.text('Replacement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  caseTest(
    'late revoke cannot mutate a newer account screen or credentials',
    'foreign_revoke',
    (tester) async {
      final held = hold();
      handler = (request) async =>
          request.method == 'POST' ? held.future : response(inventory());
      await show(tester);
      await confirm(tester);
      await newerSession(owner: 'user-b');
      held.complete(response({'ok': true}));
      await tester.pump();
      await tester.pump();
      expect(api.currentUserId, 'user-b');
      expect(api.isSignedIn, isTrue);
      expect(find.text('THIS SIGN-IN'), findsNothing);
      expect(
        requests.where((request) => request.method == 'GET'),
        hasLength(1),
      );
    },
  );
  caseTest(
    'session change while confirmation is open prevents revoke',
    'late_confirmation',
    (tester) async {
      await show(tester);
      await tap(tester, 'end-$otherHandle');
      await tester.pump(const Duration(milliseconds: 250));
      await newerSession();
      await tap(tester, 'confirm-session-revoke');
      await tester.pump(const Duration(milliseconds: 250));
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      expect(find.text('THIS SIGN-IN'), findsNothing);
    },
  );
  caseTest(
    'session DTO rejects malformed identities dates bounds and current flags',
    'invalid_dto',
    (tester) async {
      for (final payload in [
        {'limit': 6, 'sessions': []},
        {
          'limit': 5,
          'sessions': [row(currentHandle, current: true), row(currentHandle)],
        },
        {
          'limit': 5,
          'sessions': [row(otherHandle)],
        },
        {
          'limit': 5,
          'sessions': [
            {
              ...row(currentHandle, current: true),
              'expires_at': '2026-02-31T12:00:00.000Z',
            },
          ],
        },
        {
          'limit': 5,
          'sessions': [
            {
              ...row(currentHandle, current: true),
              'token': 'public-forbidden-field',
            },
          ],
        },
        {
          'limit': 5,
          'sessions': [
            row(
              currentHandle,
              current: true,
              label: List.filled(81, 'x').join(),
            ),
          ],
        },
      ]) {
        expect(
          () => UserSessionInventory.parse(payload),
          throwsFormatException,
        );
      }
      final missingHint = row(currentHandle, current: true)
        ..remove('agent_label');
      missingHint['token'] = 'public-forbidden-field';
      expect(
        () => UserSessionInventory.parse({
          'limit': 5,
          'sessions': [missingHint],
        }),
        throwsFormatException,
      );
      expect(
        UserSessionInventory.parse({
          'limit': 5,
          'sessions': [
            row(
              currentHandle,
              current: true,
              label: List.filled(80, '🟦').join(),
            ),
          ],
        }).sessions.single.agentLabel!.runes.length,
        80,
      );
      expect(
        UserSessionInventory.parse({
          'limit': 5,
          'sessions': [row(currentHandle, current: true, label: null)],
        }).sessions.single.agentLabel,
        isNull,
      );
      await expectLater(api.revokeUserSession('bad'), throwsFormatException);
      expect(requests, isEmpty);
    },
  );
}
