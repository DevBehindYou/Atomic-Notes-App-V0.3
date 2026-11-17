// UX-05-profile (screens spec, Profile): the header and large title, the
// 88 dp photo with its edit badge, the username row (Copy and Edit, or a field
// with Cancel), "Save changes" only while the field differs, and the existing
// save messages. Fakes only: no network, Hive or account data.

import 'dart:async';

import 'package:atomic_notes/page/endpage/edit_profile_page.dart';
import 'package:atomic_notes/profile/profile_source.dart';
import 'package:atomic_notes/profile/profile_store.dart';
import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/utility/component/avatar_picker_dialog.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _Profile extends ChangeNotifier implements ProfileSource {
  bool public = true;
  @override
  String get avatarAsset => Avatars.defaultAsset;
  @override
  bool get publicProfile => public;
  @override
  Future<void> setAvatar(String? asset) async {}
  @override
  Future<void> setPublicProfile(bool value) async {
    public = value;
    notifyListeners();
  }
}

class _Account {
  String handle = '@ada';
  int loads = 0;
  final List<String> updates = [];
  Completer<String>? loadGate;
  Completer<String?>? updateGate;
  Object? updateError;
  List<ConnectivityResult> link = const [ConnectivityResult.wifi];

  Future<String> load() async {
    loads++;
    if (loadGate != null) return loadGate!.future;
    return handle;
  }

  Future<String?> update(String name) async {
    updates.add(name);
    if (updateError != null) throw updateError!;
    if (updateGate != null) return updateGate!.future;
    handle = '@$name';
    return 'Username updated wait for refresh';
  }

  Future<List<ConnectivityResult>> connectivity() async => link;
}

Future<_Account> _open(
  WidgetTester tester, {
  _Account? account,
  ThemeData? theme,
  Size size = const Size(400, 860),
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final a = account ?? _Account();
  final profile = ProfileCubit(store: _Profile());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await profile.close();
  });
  await tester.pumpWidget(BlocProvider<ProfileCubit>.value(
    value: profile,
    child: MaterialApp(
      theme: theme ?? AtomicTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: Directionality(textDirection: direction, child: child!),
      ),
      initialRoute: '/profile',
      routes: {
        '/': (_) => const Scaffold(body: Text('stub settings')),
        '/profile': (_) => EditProfilePage(
              loadUsername: a.load,
              updateUsername: a.update,
              checkConnectivity: a.connectivity,
            ),
        '/twofactor': (_) => const Scaffold(body: Text('stub 2fa')),
      },
    ),
  ));
  await tester.pump();
  await tester.pump();
  // Let the page's entrance finish (a hidden element has no semantics).
  await tester.pump(const Duration(seconds: 1));
  return a;
}

final Finder _save = find.byKey(const ValueKey('profile-save'));
final Finder _edit = find.byKey(const ValueKey('profile-username-edit'));
final Finder _field = find.byKey(const ValueKey('profile-username-field'));

Future<void> _startEditing(WidgetTester tester) async {
  await tester.tap(_edit);
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(
      find.descendant(of: _field, matching: find.byType(EditableText)), text);
  await tester.pump();
  // "Save changes" grows in from the bottom.
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('username', () {
    testWidgets('idle: the handle, Copy and Edit, and no Save', (tester) async {
      await _open(tester);
      expect(find.text('@ada'), findsWidgets);
      expect(find.byTooltip('Copy username'), findsOneWidget);
      expect(_edit, findsOneWidget);
      expect(_save, findsNothing);
    });

    testWidgets('while the handle loads, Copy and Edit wait', (tester) async {
      final a = _Account()..loadGate = Completer<String>();
      await _open(tester, account: a);
      expect(find.text('Loading…'), findsWidgets);
      await tester.tap(_edit);
      await tester.pump();
      expect(_field, findsNothing);
      a.loadGate!.complete('@ada');
      await tester.pump();
      expect(find.text('@ada'), findsWidgets);
    });

    testWidgets('Save shows only while the field differs; Cancel hides it',
        (tester) async {
      await _open(tester);
      await _startEditing(tester);
      expect(_field, findsOneWidget);
      expect(find.byTooltip('Cancel'), findsOneWidget);
      expect(_save, findsNothing, reason: 'unchanged');
      await _type(tester, 'ada2');
      expect(_save, findsOneWidget);
      await _type(tester, 'ADA ');
      expect(_save, findsNothing, reason: 'same name after trim/lowercase');
      await _type(tester, 'grace');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      expect(_save, findsNothing);
      expect(find.text('@ada'), findsWidgets);
    });

    testWidgets('saving trims and lowercases, shows the answer and reloads',
        (tester) async {
      final a = await _open(tester);
      await _startEditing(tester);
      await _type(tester, '  Grace ');
      await tester.tap(_save);
      await tester.pump();
      await tester.pump();
      expect(a.updates, ['grace']);
      expect(find.text('Username updated wait for refresh'), findsOneWidget);
      expect(a.loads, 2);
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      expect(_save, findsNothing);
      expect(find.text('@grace'), findsWidgets);
    });

    testWidgets('a save in flight is busy and ignores a second tap',
        (tester) async {
      final a = await _open(tester);
      a.updateGate = Completer<String?>();
      await _startEditing(tester);
      await _type(tester, 'grace');
      await tester.tap(_save);
      await tester.pump();
      expect(tester.widget<AtomicButton>(_save).busy, isTrue);
      await tester.tap(_save, warnIfMissed: false);
      await tester.pump();
      expect(a.updates, ['grace']);
      a.updateGate!.complete('Username updated wait for refresh');
      await tester.pumpAndSettle();
      expect(_save, findsNothing);
    });

    testWidgets('offline: the existing message, and nothing is sent',
        (tester) async {
      final a = await _open(tester);
      a.link = const [ConnectivityResult.none];
      await _startEditing(tester);
      await _type(tester, 'grace');
      await tester.tap(_save);
      await tester.pump();
      await tester.pump();
      expect(find.text('No Internet Connection!'), findsOneWidget);
      expect(a.updates, isEmpty);
      expect(_field, findsOneWidget, reason: 'the draft stays');
    });

    testWidgets('an empty name asks for one, and nothing is sent',
        (tester) async {
      final a = await _open(tester);
      await _startEditing(tester);
      await _type(tester, '   ');
      expect(_save, findsOneWidget);
      await tester.tap(_save);
      await tester.pump();
      await tester.pump();
      expect(find.text('Please enter your username'), findsOneWidget);
      expect(a.updates, isEmpty);
    });

    testWidgets('a failed save shows the existing error and ends editing',
        (tester) async {
      final a = await _open(tester);
      a.updateError = StateError('server down');
      await _startEditing(tester);
      await _type(tester, 'grace');
      await tester.tap(_save);
      await tester.pump();
      await tester.pump();
      expect(
          find.text('Error occurred while updating user info'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
    });

    testWidgets('Copy puts the name (without @) on the clipboard',
        (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _open(tester);
      await tester.tap(find.byTooltip('Copy username'));
      await tester.pump();
      expect(copied, 'ada');
      expect(find.text('Username copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('page', () {
    testWidgets('the photo opens the avatar sheet', (tester) async {
      await _open(tester);
      expect(find.bySemanticsLabel('Change profile photo'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-photo')));
      await tester.pumpAndSettle();
      expect(find.byType(AvatarPickerDialog), findsOneWidget);
    });

    testWidgets('the named back button leaves the page', (tester) async {
      await _open(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('stub settings'), findsOneWidget);
    });

    testWidgets('two-factor opens its page; the public switch toggles',
        (tester) async {
      await _open(tester);
      final public = find.byKey(const ValueKey('profile-public'));
      await tester.ensureVisible(public);
      await tester.tap(public);
      await tester.pump();
      expect(tester.element(public).read<ProfileCubit>().state.publicProfile,
          isFalse);
      final twoFactor = find.byKey(const ValueKey('profile-two-factor'));
      await tester.ensureVisible(twoFactor);
      await tester.tap(twoFactor);
      await tester.pumpAndSettle();
      expect(find.text('stub 2fa'), findsOneWidget);
    });

    testWidgets('the collapsed title shows once the large title scrolls away',
        (tester) async {
      await _open(tester, size: const Size(400, 600));
      AnimatedOpacity collapsed() => tester.widget<AnimatedOpacity>(find
          .ancestor(
              of: find.text(EditProfilePage.title).first,
              matching: find.byType(AnimatedOpacity))
          .first);
      expect(collapsed().opacity, 0);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(collapsed().opacity, 1);
    });
  });

  group('layout and accessibility', () {
    for (final theme
        in {'light': AtomicTheme.light, 'dark': AtomicTheme.dark}.entries) {
      for (final direction in TextDirection.values) {
        testWidgets(
            '${theme.key} ${direction.name}: 320 dp at 2.0 text, idle and '
            'editing, without overflow', (tester) async {
          await _open(tester,
              theme: theme.value,
              direction: direction,
              size: const Size(320, 700),
              textScale: 2);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(_edit);
          await tester.tap(_edit);
          await tester.pump();
          await _type(tester, 'a-much-longer-username');
          expect(_save, findsOneWidget);
          expect(tester.takeException(), isNull);
          final connected = find.byKey(const ValueKey('profile-connected'));
          await tester.scrollUntilVisible(connected, 200,
              scrollable: find.byType(Scrollable).first);
          expect(connected, findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('photo, Copy, Edit, Cancel and Back have 48 dp targets',
        (tester) async {
      await _open(tester);
      for (final finder in [
        find.byKey(const ValueKey('profile-photo')),
        find.byTooltip('Copy username'),
        find.byTooltip('Edit username'),
        find.byTooltip('Back'),
      ]) {
        final size = tester.getSize(finder);
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
      }
      await _startEditing(tester);
      final cancel = tester.getSize(find.byTooltip('Cancel'));
      expect(cancel.width, greaterThanOrEqualTo(48));
      expect(cancel.height, greaterThanOrEqualTo(48));
    });

    testWidgets('reduced motion: Save still appears and works', (tester) async {
      final a = await _open(tester, disableAnimations: true);
      await _startEditing(tester);
      await _type(tester, 'grace');
      expect(_save, findsOneWidget);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(a.updates, ['grace']);
      expect(tester.takeException(), isNull);
    });
  });
}
