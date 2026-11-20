// Review R32: the Profile page's username adapter reports a typed outcome, and
// the Profile page keeps the draft unless the save is confirmed. The Server
// is a synthetic in-process transport; the local cache is a temporary Hive
// box. No network, account data or real notes.

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
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A synthetic Server: answers PATCH /atomicuser with [status] and records
/// the names it was sent.
class _Server {
  int status = 200;
  bool unreachable = false;
  final List<String> names = [];

  late final MockClient transport = MockClient((request) async {
    if (request.method == 'PATCH' && request.url.path.endsWith('/atomicuser')) {
      if (unreachable) throw http.ClientException('synthetic: unreachable');
      names.add((jsonDecode(request.body) as Map)['username'] as String);
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

/// Opens the page with the real adapter of [server]; [handle] is what the
/// refresh reads.
Future<void> _open(
    WidgetTester tester, _Server server, String Function() handle) async {
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
      home: EditProfilePage(
        loadUsername: () async => handle(),
        updateUsername: server.updater.update,
        checkConnectivity: () async => const [ConnectivityResult.wifi],
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _saveDraft(WidgetTester tester, String name) async {
  await tester.tap(_edit);
  await tester.pump();
  await tester.enterText(
      find.descendant(of: _field, matching: find.byType(EditableText)), name);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(_save);
  await tester.pumpAndSettle();
}

void main() {
  group('ProfileUsernameUpdater (real adapter)', () {
    test('a Server failure is a rejection, and nothing is cached', () async {
      final server = _Server()..status = 500;
      final before = ProfileStore.instance.cachedUsername;
      expect(
          await server.updater.update('grace'), UsernameUpdateOutcome.rejected);
      expect(server.names, ['grace']);
      expect(ProfileStore.instance.cachedUsername, before);
    });

    test('an unreachable Server is a rejection', () async {
      final server = _Server()..unreachable = true;
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
  });
}
