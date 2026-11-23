// Review R32: the Profile page's username adapter reports a typed outcome, and
// the Profile page keeps the draft unless the save is confirmed. The Server
// is a synthetic in-process transport; the local cache is a temporary Hive
// box. No network, account data or real notes.
//
// Review R37: the page's default adapters (no injected load or save) run
// against a synthetic `/atomicuser` behind `ApiClient.instance`. A valid
// Server answer survives a failing cache; an unreadable handle offers a
// read-only refresh; an answer from an ended sign-in changes nothing.
//
// Review R40: a success status whose reply cannot be read is neither a
// rejection nor a confirmation. A read-only refresh decides; the draft stays
// unless the Server's handle is the draft; the update is never resent. A
// cached handle is labelled as possibly out of date.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/page/endpage/edit_profile_page.dart';
import 'package:atomic_notes/profile/profile_source.dart';
import 'package:atomic_notes/profile/profile_store.dart';
import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A synthetic Server: answers PATCH /atomicuser with [status] and records
/// the names it was sent.
class _Server {
  int status = 200;
  bool unreachable = false;

  /// Review R40: a success status whose body is not JSON.
  bool unreadable = false;
  final List<String> names = [];

  late final MockClient transport = MockClient((request) async {
    if (request.method == 'PATCH' && request.url.path.endsWith('/atomicuser')) {
      if (unreachable) throw http.ClientException('synthetic: unreachable');
      names.add((jsonDecode(request.body) as Map)['username'] as String);
      if (unreadable) return http.Response('synthetic non-JSON body', status);
      return http.Response(
          status == 200 ? '{}' : '{"error":"synthetic_failure"}', status);
    }
    return http.Response('{"error":"unexpected"}', 404);
  });

  ProfileUsernameUpdater get updater => ProfileUsernameUpdater(
        api: ApiClient.forTest(
            client: transport,
            baseUrl: Uri.parse('https://fixture.invalid/api')),
      );
}

class _Profile extends ChangeNotifier implements ProfileSource {
  @override
  String get avatarAsset => Avatars.defaultAsset;
  @override
  bool get publicProfile => true;
  @override
  Future<void> setAvatar(String? asset) async {}
  @override
  Future<void> setPublicProfile(bool value) async {}
}

final Finder _save = find.byKey(const ValueKey('profile-save'));
final Finder _edit = find.byKey(const ValueKey('profile-username-edit'));
final Finder _field = find.byKey(const ValueKey('profile-username-field'));

String _draft(WidgetTester tester) => tester
    .widget<EditableText>(
        find.descendant(of: _field, matching: find.byType(EditableText)))
    .controller
    .text;

/// The synthetic `/atomicuser` behind `ApiClient.instance` (review R37). Each
/// test sets what PATCH and GET answer; [calls] records the methods in order.
class _Live {
  String handle = 'ada';
  final List<String> calls = [];

  /// Answers PATCH; null applies the name and says 200.
  Future<http.Response> Function(String name)? patch;

  /// Answers GET; null says 200 with [handle].
  Future<http.Response> Function()? get;

  late final MockClient transport = MockClient((request) async {
    expect(request.url.path, endsWith('/atomicuser'));
    calls.add(request.method);
    if (request.method == 'PATCH') {
      final name = (jsonDecode(request.body) as Map)['username'] as String;
      if (patch != null) return patch!(name);
      handle = name;
      return http.Response('{}', 200);
    }
    expect(request.method, 'GET');
    if (get != null) return get!();
    return http.Response('{"username":"$handle"}', 200);
  });

  void reset() {
    handle = 'ada';
    calls.clear();
    patch = null;
    get = null;
  }
}

final _Live _live = _Live();

/// Starts a synthetic sign-in on `ApiClient.instance`; every call starts a
/// new session, as a sign-out and sign-in would.
Future<void> _signIn(String owner) async {
  FlutterSecureStorage.setMockInitialValues({
    'atomic_api_session_token': 'synthetic-token-$owner',
    'atomic_api_user_id': owner,
    'atomic_api_user_email': '$owner@example.invalid',
  });
  await ApiClient.instance.init();
}

http.Response _unavailable() =>
    http.Response('{"error":"synthetic_unavailable"}', 503);

final Finder _note = find.byKey(const ValueKey('profile-handle-note'));
final Finder _refresh = find.byKey(const ValueKey('profile-handle-refresh'));

/// Opens the page with the real adapter of [server]; [handle] is what the
/// refresh reads.
Future<void> _open(
    WidgetTester tester, _Server server, String Function() handle) =>
    _mount(
        tester,
        EditProfilePage(
          loadUsername: () async => handle(),
          updateUsername: server.updater.update,
          checkConnectivity: () async => const [ConnectivityResult.wifi],
        ));

/// Opens the page with its default (production) load and save; only
/// connectivity is synthetic.
Future<void> _openDefault(WidgetTester tester) => _mount(
    tester,
    EditProfilePage(
      checkConnectivity: () async => const [ConnectivityResult.wifi],
    ));

Future<void> _mount(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(400, 860) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final profile = ProfileCubit(store: _Profile());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await profile.close();
  });
  await tester.pumpWidget(BlocProvider<ProfileCubit>.value(
    value: profile,
    child: MaterialApp(
      theme: AtomicTheme.light,
      initialRoute: '/profile',
      routes: {
        '/': (_) => const Scaffold(body: Text('stub settings')),
        '/profile': (_) => page,
      },
    ),
  ));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _typeDraft(WidgetTester tester, String name) async {
  await tester.tap(_edit);
  await tester.pump();
  await tester.enterText(
      find.descendant(of: _field, matching: find.byType(EditableText)), name);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _saveDraft(WidgetTester tester, String name) async {
  await _typeDraft(tester, name);
  await tester.tap(_save);
  await tester.pumpAndSettle();
}

/// Lets a message leave; it floats over the pinned Save button.
Future<void> _quiet(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  // Review R37: `ApiClient.instance` is created here, inside the synthetic
  // transport, before anything else reads it.
  setUpAll(() async {
    http.runWithClient(() => ApiClient.instance, () => _live.transport);
    await _signIn('synthetic-owner-a');
  });
  setUp(_live.reset);

  group('ProfileUsernameUpdater (real adapter)', () {
    test('a Server failure is a rejection, and nothing is cached', () async {
      final server = _Server()..status = 500;
      final before = ProfileStore.instance.cachedUsername;
      expect(
          await server.updater.update('grace'), UsernameUpdateOutcome.rejected);
      expect(server.names, ['grace']);
      expect(ProfileStore.instance.cachedUsername, before);
    });

    // Review R37: a lost connection proves neither outcome (it used to be
    // reported as a rejection). The page keeps the draft either way.
    test('an unreachable Server is uncertain, not a confirmed rejection',
        () async {
      final server = _Server()..unreachable = true;
      final before = ProfileStore.instance.cachedUsername;
      expect(await server.updater.update('grace'),
          UsernameUpdateOutcome.uncertain);
      expect(ProfileStore.instance.cachedUsername, before);
    });

    // Review R40.
    test('a success status with an unreadable reply is unconfirmed, not a '
        'rejection, and nothing is cached', () async {
      final server = _Server()..unreadable = true;
      final before = ProfileStore.instance.cachedUsername;
      expect(await server.updater.update('grace'),
          UsernameUpdateOutcome.unconfirmed);
      expect(server.names, ['grace']);
      expect(ProfileStore.instance.cachedUsername, before);
    });

    test('a failure status with an unreadable reply is still a rejection',
        () async {
      final server = _Server()
        ..unreadable = true
        ..status = 500;
      expect(
          await server.updater.update('grace'), UsernameUpdateOutcome.rejected);
    });

    test('a Server success is saved and cached', () async {
      final server = _Server();
      expect(await server.updater.update('grace'), UsernameUpdateOutcome.saved);
      expect(server.names, ['grace']);
      expect(ProfileStore.instance.cachedUsername, 'grace');
    });
  });

  group('the page with the real adapter', () {
    testWidgets('a Server failure keeps the draft; a retry saves it once',
        (tester) async {
      final server = _Server()..status = 500;
      var handle = '@ada';
      await _open(tester, server, () => handle);
      await _saveDraft(tester, 'grace');
      expect(server.names, ['grace']);
      expect(find.text('Error updating username'), findsOneWidget);
      expect(_field, findsOneWidget);
      expect(_draft(tester), 'grace');
      expect(tester.widget<AtomicButton>(_save).busy, isFalse);

      server.status = 200;
      handle = '@grace';
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(server.names, ['grace', 'grace']);
      expect(_field, findsNothing);
      expect(find.text('@grace'), findsWidgets);
    });
  });

  // Review R37, with this device's copy held in memory (no Hive box yet).
  group('the page with its default adapters (R37)', () {
    const acknowledged = "Username updated. Couldn't refresh it yet.";
    const uncertain =
        "Couldn't confirm the update. Check your connection and try again.";

    testWidgets('a stale copy offers a refresh that reads, never saves',
        (tester) async {
      await ProfileStore.instance.cacheUsername('old-ada');
      _live.get = () async => _unavailable();
      await _openDefault(tester);
      expect(_live.calls, ['GET']);
      expect(find.text('@old-ada'), findsWidgets);
      expect(find.byTooltip('Refresh username'), findsOneWidget);
      expect(_note, findsNothing, reason: 'the page does not move');
      expect(_refresh, findsOneWidget);

      _live.get = null;
      await tester.tap(_refresh);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'GET']);
      expect(find.text('@ada'), findsWidgets);
      expect(find.text('@old-ada'), findsNothing);
      expect(_note, findsNothing);
      expect(ProfileStore.instance.cachedUsername, 'ada');
    });

    testWidgets('an acknowledged update whose refresh fails says so, keeps the '
        'last confirmed handle, and Refresh does not resubmit', (tester) async {
      await _openDefault(tester);
      expect(find.text('@ada'), findsWidgets);
      await _typeDraft(tester, 'grace');
      _live.get = () async => _unavailable();
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
      expect(_live.handle, 'grace');
      expect(find.text('Username updated wait for refresh'), findsOneWidget);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.text(acknowledged), findsOneWidget);
      expect(find.text('@ada'), findsWidgets,
          reason: 'a cached copy is not the Server answer');
      expect(_field, findsNothing, reason: 'the update was acknowledged');

      _live.get = null;
      await tester.tap(_refresh);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH', 'GET', 'GET']);
      expect(find.text('@grace'), findsWidgets);
      expect(_note, findsNothing);
    });

    testWidgets('a definitive rejection keeps the draft; a retry saves once',
        (tester) async {
      await _openDefault(tester);
      _live.patch =
          (_) async => http.Response('{"error":"synthetic_invalid"}', 400);
      await _saveDraft(tester, 'grace');
      expect(_live.calls, ['GET', 'PATCH']);
      expect(find.text('Error updating username'), findsOneWidget);
      expect(_field, findsOneWidget);
      expect(_draft(tester), 'grace');
      expect(tester.widget<AtomicButton>(_save).busy, isFalse);
      expect(find.text('@ada'), findsWidgets);

      _live.patch = null;
      await _quiet(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH', 'PATCH', 'GET']);
      expect(_field, findsNothing);
      expect(find.text('@grace'), findsWidgets);
    });

    testWidgets('a timeout proves nothing: the draft stays and a retry saves',
        (tester) async {
      await _openDefault(tester);
      final never = Completer<http.Response>();
      _live.patch = (_) => never.future;
      await _typeDraft(tester, 'grace');
      await tester.tap(_save);
      await tester.pump();
      expect(tester.widget<AtomicButton>(_save).busy, isTrue);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH']);
      expect(find.text(uncertain), findsOneWidget);
      expect(find.text('Error updating username'), findsNothing);
      expect(find.text('Username updated wait for refresh'), findsNothing);
      expect(_field, findsOneWidget);
      expect(_draft(tester), 'grace');
      expect(tester.widget<AtomicButton>(_save).busy, isFalse);
      expect(find.text('@ada'), findsWidgets);

      _live.patch = null;
      await _quiet(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH', 'PATCH', 'GET']);
      expect(_field, findsNothing);
      expect(find.text('@grace'), findsWidgets);
    });

    testWidgets('a lost connection is uncertain too, and keeps the draft',
        (tester) async {
      await _openDefault(tester);
      _live.patch =
          (_) async => throw http.ClientException('synthetic: connection lost');
      await _saveDraft(tester, 'grace');
      expect(_live.calls, ['GET', 'PATCH']);
      expect(find.text(uncertain), findsOneWidget);
      expect(_field, findsOneWidget);
      expect(_draft(tester), 'grace');
      expect(tester.widget<AtomicButton>(_save).busy, isFalse);
    });

    testWidgets('an update answered after the sign-in changed changes nothing '
        'and the old page cannot save for the new one', (tester) async {
      await _openDefault(tester);
      final gate = Completer<http.Response>();
      _live.patch = (name) {
        _live.handle = name;
        return gate.future;
      };
      await _typeDraft(tester, 'grace');
      await tester.tap(_save);
      await tester.pump();
      await tester.runAsync(() => _signIn('synthetic-owner-b'));
      gate.complete(http.Response('{}', 200));
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH'], reason: 'nothing is refreshed');
      expect(find.text('Username updated wait for refresh'), findsNothing);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.text('@grace'), findsNothing);
      expect(ProfileStore.instance.cachedUsername, isNull,
          reason: "the new account's copy is untouched");
      expect(tester.widget<AtomicButton>(_save).busy, isFalse);

      _live.patch = null;
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH'], reason: 'no update for account B');
    });

    testWidgets('a refresh answered after the sign-in changed is not shown '
        'or cached', (tester) async {
      await _openDefault(tester);
      final gate = Completer<http.Response>();
      await _typeDraft(tester, 'grace');
      _live.get = () => gate.future;
      await tester.tap(_save);
      await tester.pump();
      await tester.pump();
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
      await tester.runAsync(() => _signIn('synthetic-owner-c'));
      gate.complete(http.Response('{"username":"grace"}', 200));
      await tester.pumpAndSettle();
      expect(find.text('@grace'), findsNothing);
      expect(find.text('@ada'), findsWidgets);
      expect(ProfileStore.instance.cachedUsername, isNull,
          reason: "the new account's copy is untouched");
      expect(find.textContaining('Error'), findsNothing);
    });

    testWidgets('leaving during the refresh is quiet', (tester) async {
      await _openDefault(tester);
      final gate = Completer<http.Response>();
      await _typeDraft(tester, 'grace');
      _live.get = () => gate.future;
      await tester.tap(_save);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('stub settings'), findsOneWidget);
      gate.complete(http.Response('{"username":"grace"}', 200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
    });
  });

  // Review R40: the Server says 200 but its reply cannot be read.
  group('a success status with an unreadable reply (R40)', () {
    const uncertain =
        "Couldn't confirm the update. Check your connection and try again.";
    const unconfirmed = "Couldn't confirm the update. Try again.";
    final Finder stale = find.byKey(const ValueKey('profile-handle-stale'));

    /// PATCH applies the name (unless [apply] is false) and says 200 with a
    /// body that is not JSON.
    void unreadableOk({bool apply = true}) => _live.patch = (name) async {
          if (apply) _live.handle = name;
          return http.Response('synthetic non-JSON body', 200);
        };

    testWidgets('the refresh reads the draft: saved, no error, not resent',
        (tester) async {
      await _openDefault(tester);
      unreadableOk();
      await _saveDraft(tester, 'grace');
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.text('Username updated'), findsOneWidget);
      expect(_field, findsNothing);
      expect(find.text('@grace'), findsWidgets);
      expect(_refresh, findsNothing);
      expect(ProfileStore.instance.cachedUsername, 'grace',
          reason: 'the Server answer is cached, not the unreadable reply');
    });

    testWidgets('the refresh reads another name: the draft stays and a retry '
        'saves once', (tester) async {
      await _openDefault(tester);
      unreadableOk(apply: false);
      await _saveDraft(tester, 'grace');
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.text(unconfirmed), findsOneWidget);
      expect(find.text('Username updated'), findsNothing);
      expect(find.text('Username updated wait for refresh'), findsNothing);
      expect(_field, findsOneWidget);
      expect(_draft(tester), 'grace');
      expect(tester.widget<AtomicButton>(_save).busy, isFalse);
      expect(find.text('@ada'), findsWidgets);

      _live.patch = null;
      await _quiet(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH', 'GET', 'PATCH', 'GET']);
      expect(_field, findsNothing);
      expect(find.text('@grace'), findsWidgets);
    });

    testWidgets('the refresh cannot reach the Server: uncertain, the draft '
        'stays, and Refresh only reads', (tester) async {
      await _openDefault(tester);
      unreadableOk();
      _live.get = () async => _unavailable();
      await _typeDraft(tester, 'grace');
      // GET at open already answered; later GETs fail.
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
      expect(find.text(uncertain), findsOneWidget);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.text('Username updated'), findsNothing);
      expect(_field, findsOneWidget);
      expect(_draft(tester), 'grace');
      expect(tester.widget<AtomicButton>(_save).busy, isFalse);
      expect(find.text('@ada'), findsWidgets);
      expect(stale, findsNothing, reason: 'the shown name is a Server answer');

      await _quiet(tester);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();
      _live.get = null;
      await tester.tap(_refresh);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH', 'GET', 'GET'],
          reason: 'Refresh reads; it does not resend');
      expect(find.text('@grace'), findsWidgets);
      expect(_refresh, findsNothing);
    });

    testWidgets('one save at a time through the reconciling refresh',
        (tester) async {
      await _openDefault(tester);
      unreadableOk();
      final gate = Completer<http.Response>();
      await _typeDraft(tester, 'grace');
      _live.get = () => gate.future;
      await tester.tap(_save);
      await tester.pump();
      await tester.pump();
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
      expect(tester.widget<AtomicButton>(_save).busy, isTrue);
      await tester.tap(_save);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(_live.calls, ['GET', 'PATCH', 'GET'], reason: 'no second update');
      gate.complete(http.Response('{"username":"grace"}', 200));
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
      expect(_field, findsNothing);
      expect(find.text('@grace'), findsWidgets);
    });

    testWidgets('an unreadable 200 answered after the sign-in changed '
        'changes nothing', (tester) async {
      await _openDefault(tester);
      final gate = Completer<http.Response>();
      _live.patch = (name) {
        _live.handle = name;
        return gate.future;
      };
      await _typeDraft(tester, 'grace');
      await tester.tap(_save);
      await tester.pump();
      await tester.runAsync(() => _signIn('synthetic-owner-r40-d'));
      gate.complete(http.Response('synthetic non-JSON body', 200));
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH'], reason: 'nothing is refreshed');
      expect(find.textContaining('Error'), findsNothing);
      expect(find.textContaining("Couldn't confirm"), findsNothing);
      expect(find.text('Username updated'), findsNothing);
      expect(find.text('@grace'), findsNothing);
      expect(ProfileStore.instance.cachedUsername, isNull,
          reason: "the new account's copy is untouched");
      expect(tester.widget<AtomicButton>(_save).busy, isFalse);

      _live.patch = null;
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH'], reason: 'no update for account B');
    });

    testWidgets('a reconciling refresh answered after the sign-in changed is '
        'not shown or cached', (tester) async {
      await _openDefault(tester);
      unreadableOk();
      final gate = Completer<http.Response>();
      await _typeDraft(tester, 'grace');
      _live.get = () => gate.future;
      await tester.tap(_save);
      await tester.pump();
      await tester.pump();
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
      await tester.runAsync(() => _signIn('synthetic-owner-r40-e'));
      gate.complete(http.Response('{"username":"grace"}', 200));
      await tester.pumpAndSettle();
      expect(find.text('@grace'), findsNothing);
      expect(find.text('@ada'), findsWidgets);
      expect(find.text('Username updated'), findsNothing);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.textContaining("Couldn't confirm"), findsNothing);
      expect(ProfileStore.instance.cachedUsername, isNull,
          reason: "the new account's copy is untouched");
      expect(tester.widget<AtomicButton>(_save).busy, isFalse);
    });

    testWidgets('a cached handle is labelled as possibly out of date until '
        'the Server answers', (tester) async {
      await ProfileStore.instance.cacheUsername('old-ada');
      _live.get = () async => _unavailable();
      await _openDefault(tester);
      expect(find.text('@old-ada'), findsWidgets);
      expect(stale, findsOneWidget);
      expect(find.text('Saved on this device · may be out of date'),
          findsOneWidget);
      expect(_refresh, findsOneWidget);

      _live.get = null;
      await tester.tap(_refresh);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'GET']);
      expect(find.text('@ada'), findsWidgets);
      expect(stale, findsNothing);
    });

    testWidgets('no cached handle: the placeholder is not labelled as a copy',
        (tester) async {
      await ProfileStore.instance.cacheUsername('');
      expect(ProfileStore.instance.cachedUsername, isNull);
      _live.get = () async => _unavailable();
      await _openDefault(tester);
      expect(find.text('@atomicuser'), findsWidgets);
      expect(_refresh, findsOneWidget);
      expect(stale, findsNothing);
    });
  });

  // Last: closing the profile box makes every later cache write fail.
  group('a local cache failure after the Server took the name', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('atomic-profile-r32-');
      Hive.init(dir.path);
      await ProfileStore.instance.init();
      await Hive.box<dynamic>(ProfileStore.boxName).close();
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('is reported as saved but uncached, not as a rejection', () async {
      final server = _Server();
      expect(await server.updater.update('grace'),
          UsernameUpdateOutcome.savedUncached);
      expect(server.names, ['grace']);
    });

    testWidgets('the page claims no failure and the refresh reconciles it',
        (tester) async {
      final server = _Server();
      // The refresh reads the name the Server now has.
      await _open(
          tester, server, () => server.names.isEmpty ? '@ada' : '@grace');
      await _saveDraft(tester, 'grace');
      expect(server.names, ['grace']);
      expect(find.text('Username updated wait for refresh'), findsOneWidget);
      expect(find.text('Error updating username'), findsNothing);
      expect(_field, findsNothing);
      expect(find.text('@grace'), findsWidgets);
    });

    testWidgets('the page keeps the draft while the refresh shows the old name',
        (tester) async {
      final server = _Server();
      await _open(tester, server, () => '@ada');
      await _saveDraft(tester, 'grace');
      expect(server.names, ['grace']);
      expect(find.text('Error updating username'), findsNothing);
      expect(_field, findsOneWidget);
      expect(_draft(tester), 'grace');
      expect(tester.widget<AtomicButton>(_save).busy, isFalse);
    });

    // Review R37: the default adapters, with the box closed.
    testWidgets('default adapters: a valid Server answer survives the failing '
        'cache, before and after a save', (tester) async {
      await _openDefault(tester);
      expect(_live.calls, ['GET']);
      expect(find.text('@ada'), findsWidgets);
      expect(find.text("This device couldn't keep a copy of your username."),
          findsOneWidget);
      expect(_refresh, findsNothing, reason: 'the Server was read');

      await _saveDraft(tester, 'grace');
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
      expect(_live.handle, 'grace');
      expect(find.text('Username updated wait for refresh'), findsOneWidget);
      expect(find.textContaining('Error'), findsNothing);
      expect(_field, findsNothing);
      expect(find.text('@grace'), findsWidgets);
    });

    testWidgets('default adapters: an unreadable cache and Server give the '
        'placeholder, no failure after an acknowledged save, and a refresh',
        (tester) async {
      _live.get = () async => _unavailable();
      await _openDefault(tester);
      expect(find.text('@atomicuser'), findsWidgets);
      expect(find.byTooltip('Refresh username'), findsOneWidget);
      expect(_note, findsNothing, reason: 'the page does not move');
      expect(_refresh, findsOneWidget);

      await _saveDraft(tester, 'grace');
      expect(_live.calls, ['GET', 'PATCH', 'GET']);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.text("Username updated. Couldn't refresh it yet."),
          findsOneWidget);
      expect(_field, findsNothing);

      _live.get = null;
      await tester.tap(_refresh);
      await tester.pumpAndSettle();
      expect(_live.calls, ['GET', 'PATCH', 'GET', 'GET']);
      expect(find.text('@grace'), findsWidgets);
      expect(_refresh, findsNothing);
    });
  });
}
