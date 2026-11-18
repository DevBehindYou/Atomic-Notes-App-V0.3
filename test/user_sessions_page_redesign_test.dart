// Sign-ins on lib/ui components (screens spec, Sign-ins): one card per
// sign-in, "This device" on the current one and no way to end it there, the
// shared destructive dialog for "End sign-in", a busy button while the
// request runs, the loading, empty, error and changed states, and the layout
// checks every redesigned page passes. The real ApiClient over a synthetic
// transport and store; no network or keystore.

import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/page/endpage/user_sessions_page.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/chips/status_chip.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/feedback/empty_state.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/mascot/mascot_stage.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final String _current = 'A' * 43;
final String _other = 'B' * 43;

/// Other sign-ins after [_other], up to the Server's limit of five.
final List<String> _more = ['C' * 43, 'D' * 43, 'E' * 43];

const String _created = '2026-10-01T12:00:00.000Z';
const String _expires = '2026-10-08T12:00:00.000Z';

Map<String, Object?> _row(String handle,
        {bool current = false, String? hint = 'Synthetic client hint'}) =>
    {
      'session_handle': handle,
      'created_at': _created,
      'expires_at': current ? '2027-03-30T12:00:00.000Z' : _expires,
      'is_current': current,
      'agent_label': hint,
    };

Map<String, Object?> _inventory({bool other = true, int more = 0}) => {
      'limit': 5,
      'sessions': [
        _row(_current, current: true),
        if (other) _row(_other),
        for (final h in _more.take(more)) _row(h, hint: null),
      ],
    };

http.Response _reply(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// The page's date format, in local time.
String _local(String iso) {
  final d = DateTime.parse(iso).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}';
}

class _Store implements FlutterSecureStorage {
  final values = <String, String>{
    'atomic_api_session_token': 'synthetic-session',
    'atomic_api_user_id': 'user-a',
    'atomic_api_user_email': 'synthetic@example.test',
  };

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

/// One case's client, transport and the requests it saw.
class _Harness {
  _Harness(this.handler);

  Future<http.Response> Function(http.Request) handler;
  final List<http.Request> requests = [];
  final List<Completer<http.Response>> held = [];
  final _Store store = _Store();
  late final MockClient transport = MockClient((request) {
    requests.add(request);
    return handler(request);
  });
  late final ApiClient api = ApiClient.forTest(
    client: transport,
    storage: store,
    baseUrl: Uri.parse('https://fixture.invalid/api'),
  );

  int get posts => requests.where((r) => r.method == 'POST').length;
  int get gets => requests.where((r) => r.method == 'GET').length;

  Completer<http.Response> hold() {
    final c = Completer<http.Response>();
    held.add(c);
    return c;
  }
}

Future<_Harness> _harness(
  WidgetTester tester, {
  Future<http.Response> Function(http.Request)? handler,
}) async {
  final h = _Harness(handler ?? (_) async => _reply(_inventory()));
  await h.api.init();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    for (final c in h.held) {
      if (!c.isCompleted) c.complete(_reply({'sessions': [], 'limit': 5}));
    }
    await tester.pump();
    h.transport.close();
  });
  return h;
}

Future<void> _pump(
  WidgetTester tester,
  _Harness h, {
  ThemeData? theme,
  double width = 412,
  double height = 915,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AtomicTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: UserSessionsPage(api: h.api),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder _card(String handle) => find.byKey(ValueKey('session-$handle'));

Finder _end(String handle) => find.byKey(ValueKey('end-$handle'));

/// Scrolls the sign-in's button into view, as a user would, and taps it.
Future<void> _tapEnd(WidgetTester tester, String handle) async {
  await tester.ensureVisible(_end(handle));
  await tester.pump();
  await tester.tap(_end(handle));
}

Finder _inDialog(String label) => find.descendant(
    of: find.byType(AtomicDialog<bool>), matching: find.text(label));

AtomicButton _button(WidgetTester tester, Finder finder) =>
    tester.widget<AtomicButton>(finder);

AtomicIconButton _refresh(WidgetTester tester) => tester
    .widget<AtomicIconButton>(find.byKey(const ValueKey('refresh-sessions')));

/// Whether [finder] sits under a live region, so a change is read out.
bool _live(WidgetTester tester, Finder finder) => tester
    .widgetList<Semantics>(
        find.ancestor(of: finder, matching: find.byType(Semantics)))
    .any((s) => s.properties.liveRegion ?? false);

void main() {
  group('cards', () {
    testWidgets('this sign-in is marked and has no end button', (tester) async {
      final h = await _harness(tester);
      await _pump(tester, h);

      final card = _card(_current);
      Finder inCard(Finder f) => find.descendant(of: card, matching: f);
      expect(inCard(find.text('This sign-in')), findsOneWidget);
      final chip = tester.widget<StatusChip>(inCard(find.byType(StatusChip)));
      expect(chip.label, 'This device');
      expect(chip.tone, StatusTone.accent);
      expect(_end(_current), findsNothing);
      expect(inCard(find.byType(AtomicButton)), findsNothing);
      expect(inCard(find.textContaining('Use Logout in Settings')),
          findsOneWidget);
    });

    testWidgets('another sign-in shows its stored dates and unverified hint',
        (tester) async {
      final h = await _harness(tester);
      await _pump(tester, h);

      final card = _card(_other);
      Finder inCard(Finder f) => find.descendant(of: card, matching: f);
      expect(inCard(find.text('Other sign-in')), findsOneWidget);
      expect(inCard(find.byType(StatusChip)), findsNothing);
      expect(inCard(find.text('Issued: ${_local(_created)}')), findsOneWidget);
      expect(inCard(find.text('Expires: ${_local(_expires)}')), findsOneWidget);
      expect(
          inCard(find.text('Client hint (unverified): Synthetic client hint')),
          findsOneWidget);
      // The hint never reads as a verified device or its last activity.
      expect(
          inCard(find.text(
              'This hint does not verify a device or show its last activity.')),
          findsOneWidget);
      final end = _button(tester, _end(_other));
      expect(end.label, 'End sign-in');
      expect(end.variant, AtomicButtonVariant.danger);
      expect(end.onPressed, isNotNull);
      expect(end.busy, isFalse);
    });

    testWidgets('a missing hint says it is unavailable', (tester) async {
      final h = await _harness(tester,
          handler: (_) async => _reply(_inventory(other: false, more: 1)));
      await _pump(tester, h);
      expect(
          find.descendant(
              of: _card(_more.first),
              matching: find.text('Client hint (unverified): Unavailable')),
          findsOneWidget);
    });
  });

  group('End sign-in', () {
    testWidgets('asks first in the shared destructive dialog', (tester) async {
      final h = await _harness(tester);
      await _pump(tester, h);
      await _tapEnd(tester, _other);
      await tester.pumpAndSettle();

      final dialog =
          tester.widget<AtomicDialog<bool>>(find.byType(AtomicDialog<bool>));
      expect(dialog.destructive, isTrue);
      expect(dialog.title, 'End this sign-in?');
      expect(dialog.body, contains('It will need Google sign-in again.'));
      expect(dialog.body, contains('Unsynced notes remain on that device'));
      expect(dialog.body, contains('sign back into the same account'));
      expect(dialog.body, contains('Requests already in progress may still'));
      expect(dialog.actions.map((a) => (a.label, a.result, a.variant)), [
        ('Cancel', false, AtomicButtonVariant.text),
        ('End sign-in', true, AtomicButtonVariant.danger),
      ]);
      // Nothing is sent before the answer, and the card cannot open a
      // second dialog meanwhile.
      expect(h.posts, 0);
      expect(_button(tester, _end(_other)).onPressed, isNull);
      expect(_refresh(tester).onPressed, isNull);
    });

    testWidgets('the scrim cannot dismiss it', (tester) async {
      final h = await _harness(tester);
      await _pump(tester, h);
      await _tapEnd(tester, _other);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
      expect(h.posts, 0);
    });

    testWidgets('Cancel keeps the sign-in and sends nothing', (tester) async {
      final h = await _harness(tester);
      await _pump(tester, h);
      await _tapEnd(tester, _other);
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(h.posts, 0);
      expect(_card(_other), findsOneWidget);
      // The card can be ended again.
      expect(_button(tester, _end(_other)).onPressed, isNotNull);
      expect(_refresh(tester).onPressed, isNotNull);
    });

    testWidgets('a double tap opens one dialog', (tester) async {
      final h = await _harness(tester);
      await _pump(tester, h);
      await _tapEnd(tester, _other);
      await tester.tap(_end(_other), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();
      // Two taps that land before the button rebuilds disabled reach the
      // same callback twice; the runner itself must still ask only once.
      final onEnd = _button(tester, _end(_other)).onPressed!;
      onEnd();
      onEnd();
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsOneWidget);
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(h.posts, 0);
    });

    testWidgets(
        'runs after the dialog closes: busy button, one request, card gone',
        (tester) async {
      late Completer<http.Response> post;
      var ended = false;
      final h = await _harness(tester);
      h.handler = (request) async {
        if (request.method == 'POST') return post.future;
        return _reply(_inventory(other: !ended));
      };
      post = h.hold();
      await _pump(tester, h);
      await _tapEnd(tester, _other);
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('End sign-in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(h.posts, 1);
      expect(jsonDecode(h.requests.last.body), {'session_handle': _other});
      expect(_button(tester, _end(_other)).busy, isTrue);
      expect(find.text('Ending sign-in…'), findsOneWidget);
      expect(_live(tester, find.text('Ending sign-in…')), isTrue);
      expect(_refresh(tester).onPressed, isNull);

      // More taps while it runs neither ask again nor send again.
      await tester.tap(_end(_other), warnIfMissed: false);
      await tester.tap(_end(_other), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AtomicDialog<bool>), findsNothing);
      expect(h.posts, 1);

      ended = true;
      post.complete(_reply({'ok': true}));
      await tester.pumpAndSettle();
      expect(_card(_other), findsNothing);
      expect(_card(_current), findsOneWidget);
      expect(h.posts, 1);
      expect(h.gets, 2);
      expect(h.api.isSignedIn, isTrue);
      expect(h.api.currentUserId, 'user-a');
    });

    testWidgets('a refusal shows its message and keeps the sign-in',
        (tester) async {
      final h = await _harness(tester,
          handler: (request) async => request.method == 'POST'
              ? _reply({'error': 'session_logout_active'}, status: 409)
              : _reply(_inventory()));
      await _pump(tester, h);
      await _tapEnd(tester, _other);
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('End sign-in'));
      await tester.pumpAndSettle();

      final banner = tester
          .widget<AtomicBanner>(find.byKey(const ValueKey('sessions-error')));
      expect(banner.tone, BannerTone.danger);
      expect(banner.title,
          'This sign-in has an unfinished safe logout. Finish it on that device, then refresh.');
      expect(
          _live(tester, find.byKey(const ValueKey('sessions-error'))), isTrue);
      expect(_card(_other), findsOneWidget);
      expect(_button(tester, _end(_other)).onPressed, isNotNull);
      expect(
          _button(tester, find.byKey(const ValueKey('retry-sessions'))).label,
          'Retry');
      expect(h.posts, 1);
    });

    testWidgets('an unconfirmed result offers to retry the same request',
        (tester) async {
      var posts = 0, ended = false;
      final h = await _harness(tester);
      h.handler = (request) async {
        if (request.method == 'POST') {
          if (++posts == 1) {
            throw http.ClientException('synthetic reply lost');
          }
          ended = true;
          return _reply({'ok': true});
        }
        return _reply(_inventory(other: !ended));
      };
      await _pump(tester, h);
      await _tapEnd(tester, _other);
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('End sign-in'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not confirm whether this sign-in'),
          findsOneWidget);
      final retry = find.byKey(const ValueKey('retry-sessions'));
      expect(_button(tester, retry).label, 'Retry ending sign-in');
      // Only the retry can resend it.
      expect(_button(tester, _end(_other)).onPressed, isNull);
      expect(_refresh(tester).onPressed, isNull);
      await tester.ensureVisible(retry);
      await tester.pump();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      final bodies = h.requests
          .where((r) => r.method == 'POST')
          .map((r) => r.body)
          .toList();
      expect(bodies, hasLength(2));
      expect(bodies[0], bodies[1]);
      expect(_card(_other), findsNothing);
    });
  });

  group('states', () {
    testWidgets('loading shows the mascot and is read out', (tester) async {
      final h = await _harness(tester);
      final read = h.hold();
      h.handler = (_) => read.future;
      await _pump(tester, h, settle: false);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(MascotStage), findsOneWidget);
      expect(find.text('Loading sign-ins…'), findsOneWidget);
      expect(_live(tester, find.text('Loading sign-ins…')), isTrue);
      expect(_refresh(tester).onPressed, isNull);

      read.complete(_reply(_inventory()));
      await tester.pumpAndSettle();
      expect(find.byType(MascotStage), findsNothing);
      expect(find.text('Loading sign-ins…'), findsNothing);
      expect(_card(_other), findsOneWidget);
    });

    testWidgets('an empty list uses the shared empty state and refreshes',
        (tester) async {
      final h = await _harness(tester,
          handler: (_) async => _reply({'sessions': [], 'limit': 5}));
      await _pump(tester, h);
      final empty = tester.widget<EmptyState>(find.byType(EmptyState));
      expect(empty.title, 'No sign-ins were returned');
      expect(empty.body, 'Refresh to check again.');
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(h.gets, 2);
    });

    testWidgets('a load error shows its message and retries', (tester) async {
      var reads = 0;
      final h = await _harness(tester,
          handler: (_) async => ++reads == 1
              ? throw http.ClientException('synthetic offline')
              : _reply(_inventory()));
      await _pump(tester, h);
      expect(
          tester
              .widget<AtomicBanner>(
                  find.byKey(const ValueKey('sessions-error')))
              .title,
          'Could not load or update sign-ins. Check your connection and retry.');
      expect(find.byType(EmptyState), findsNothing);
      await tester.tap(find.byKey(const ValueKey('retry-sessions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sessions-error')), findsNothing);
      expect(_card(_other), findsOneWidget);
      expect(reads, 2);
    });

    testWidgets('a changed sign-in hides the list and the refresh action',
        (tester) async {
      final h = await _harness(tester);
      await _pump(tester, h);
      await h.store.write(
          key: 'atomic_api_session_token', value: 'synthetic-newer-session');
      await h.api.init();
      // A rebuild, as the header's refresh would cause, sees the change.
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      final banner = tester
          .widget<AtomicBanner>(find.byKey(const ValueKey('sessions-changed')));
      expect(banner.title, 'Your sign-in changed. Return to Settings.');
      expect(banner.tone, BannerTone.attention);
      expect(_card(_other), findsNothing);
      expect(find.byTooltip('Refresh'), findsNothing);
      expect(h.gets, 1);
    });
  });

  group('page', () {
    testWidgets('the back button leaves the page', (tester) async {
      final h = await _harness(tester);
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AtomicTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => UserSessionsPage(api: h.api))),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(_card(_other), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(_card(_other), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('the header shows the title once the large one scrolls away',
        (tester) async {
      final h = await _harness(tester,
          handler: (_) async => _reply(_inventory(more: 3)));
      await _pump(tester, h, height: 700);
      AtomicPageHeader header() =>
          tester.widget<AtomicPageHeader>(find.byType(AtomicPageHeader));
      expect(header().title, 'Sign-ins');
      expect(header().showTitle, isFalse);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(header().showTitle, isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(header().showTitle, isFalse);
    });

    for (final (name, theme) in [
      ('light', AtomicTheme.light),
      ('dark', AtomicTheme.dark),
    ]) {
      for (final direction in TextDirection.values) {
        testWidgets(
            'fits 320 dp at 2.0 text ($name, ${direction.name}), '
            'down to the last sign-in', (tester) async {
          final h = await _harness(tester,
              handler: (_) async => _reply(_inventory(more: 3)));
          await _pump(tester, h,
              theme: theme,
              width: 320,
              height: 640,
              textScale: 2,
              direction: direction);
          expect(tester.takeException(), isNull);
          for (var i = 0; i < 16; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -400));
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // The last sign-in and its button are reached.
          final last = _more.last;
          expect(_end(last), findsOneWidget);
          await tester.ensureVisible(_end(last));
          await tester.pumpAndSettle();
          expect(
              tester.getRect(_end(last)).bottom,
              lessThanOrEqualTo(tester.getSize(find.byType(ListView)).height +
                  tester.getTopLeft(find.byType(ListView)).dy));
          // The dialog fits as well.
          await tester.tap(_end(last));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(_inDialog('Cancel'));
          await tester.pumpAndSettle();
          expect(h.posts, 0);
        });
      }
    }

    testWidgets('targets are at least 48 dp', (tester) async {
      final h = await _harness(tester,
          handler: (request) async => request.method == 'POST'
              ? _reply({'error': 'session_logout_active'}, status: 409)
              : _reply(_inventory()));
      await _pump(tester, h);
      await _tapEnd(tester, _other);
      await tester.pumpAndSettle();
      for (final finder in [_inDialog('Cancel'), _inDialog('End sign-in')]) {
        final button =
            find.ancestor(of: finder, matching: find.byType(AtomicButton));
        final size = tester.getSize(button.first);
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
      }
      await tester.tap(_inDialog('End sign-in'));
      await tester.pumpAndSettle();
      for (final finder in [
        _end(_other),
        find.byKey(const ValueKey('retry-sessions')),
        find.byTooltip('Refresh'),
        find.byTooltip('Back'),
      ]) {
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
      }
    });

    testWidgets('screen readers hear the buttons, the title and the marker',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _harness(tester);
      await _pump(tester, h);
      expect(find.bySemanticsLabel('End sign-in'), findsOneWidget);
      expect(find.bySemanticsLabel('Refresh'), findsOneWidget);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('This device')), findsOneWidget);
      expect(
          tester.getSemantics(find.bySemanticsLabel('End sign-in')),
          isSemantics(
              label: 'End sign-in',
              isButton: true,
              isEnabled: true,
              hasTapAction: true));
      semantics.dispose();
    });

    testWidgets('reduced motion shows everything at once', (tester) async {
      final h = await _harness(tester);
      await _pump(tester, h, disableAnimations: true, settle: false);
      await tester.pump();
      for (final opacity in tester.widgetList<FadeTransition>(find.ancestor(
          of: find.text('Other sign-in'),
          matching: find.byType(FadeTransition)))) {
        expect(opacity.opacity.value, 1);
      }
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('without reduced motion the cards rise in', (tester) async {
      final h = await _harness(tester);
      await _pump(tester, h, settle: false);
      await tester.pump(const Duration(milliseconds: 16));
      final fades = tester
          .widgetList<FadeTransition>(find.ancestor(
              of: find.text('Other sign-in'),
              matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value);
      expect(fades.any((v) => v < 1), isTrue);
      await tester.pumpAndSettle();
      final settled = tester
          .widgetList<FadeTransition>(find.ancestor(
              of: find.text('Other sign-in'),
              matching: find.byType(FadeTransition)))
          .map((f) => f.opacity.value);
      expect(settled.every((v) => v == 1), isTrue);
    });
  });
}
