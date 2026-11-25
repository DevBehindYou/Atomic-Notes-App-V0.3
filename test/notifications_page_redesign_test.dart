// UX-07-notifications (screens spec, Notifications): the page header with
// "Mark all read", cards with an unread dot, title, body, relative time and an
// optional action, pull to refresh, and the empty/error states. Fakes only.

import 'package:atomic_notes/database/notification_models.dart';
import 'package:atomic_notes/database/notifications_source.dart';
import 'package:atomic_notes/page/endpage/notifications_page.dart';
import 'package:atomic_notes/state/notifications/notifications_cubit.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime(2026, 9, 27, 18, 3);

AppNotification _n(
  String id, {
  bool read = false,
  bool dismissible = true,
  String priority = 'normal',
  String? action,
  String? actionUrl,
  String? subject,
  Duration age = const Duration(minutes: 5),
}) =>
    AppNotification(
      id: id,
      type: 'general',
      subject: subject ?? 'Subject $id',
      description: 'Body $id',
      priority: priority,
      status: 'active',
      action: action,
      actionUrl: actionUrl,
      icon: null,
      createdAt: _now.subtract(age),
      expiresAt: null,
      isRead: read,
      dismissedAt: null,
      dismissible: dismissible,
    );

class _Feed extends ChangeNotifier implements NotificationsSource {
  _Feed(this._items, {this.loading = false, this.error});

  List<AppNotification> _items;
  final List<String> calls = [];

  @override
  List<AppNotification> get items => _items;
  @override
  bool loading;
  @override
  String? error;

  @override
  Future<void> refresh() async => calls.add('refresh');
  @override
  Future<void> markRead(String id) async {
    calls.add('read $id');
    _items = [
      for (final n in _items) n.id == id ? n.copyWith(isRead: true) : n
    ];
    notifyListeners();
  }

  @override
  Future<void> markAllRead() async {
    calls.add('read-all');
    _items = [for (final n in _items) n.copyWith(isRead: true)];
    notifyListeners();
  }

  @override
  Future<void> dismiss(String id) async {
    calls.add('dismiss $id');
    _items = _items.where((n) => n.id != id).toList();
    notifyListeners();
  }
}

class _Routes extends NavigatorObserver {
  final List<String?> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route.settings.name);
}

Future<(_Feed, _Routes)> _open(
  WidgetTester tester,
  List<AppNotification> items, {
  bool loading = false,
  String? error,
  ThemeData? theme,
  Size size = const Size(400, 860),
  double textScale = 1,
  bool disableAnimations = false,
  ValueNotifier<bool>? reducedMotion,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final feed = _Feed(items, loading: loading, error: error);
  final cubit = NotificationsCubit(source: feed);
  final routes = _Routes();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
    feed.dispose();
  });
  await tester.pumpWidget(BlocProvider<NotificationsCubit>.value(
    value: cubit,
    child: MaterialApp(
      theme: theme ?? AtomicTheme.light,
      navigatorObservers: [routes],
      builder: (context, child) {
        Widget withMotion(bool reduced) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: reduced,
              ),
              child: child!,
            );
        final preference = reducedMotion;
        return preference == null
            ? withMotion(disableAnimations)
            : ValueListenableBuilder(
                valueListenable: preference,
                builder: (context, reduced, _) => withMotion(reduced),
              );
      },
      initialRoute: '/notifications',
      routes: {
        '/': (_) => const Scaffold(body: Text('stub home')),
        '/notifications': (_) => NotificationsPage(now: () => _now),
        '/energypage': (_) => const Scaffold(body: Text('stub energy')),
      },
    ),
  ));
  await tester.pump();
  return (feed, routes);
}

void main() {
  group('relativeTime', () {
    test('reads as a short relative time, then the date', () {
      expect(relativeTime(_now.subtract(const Duration(seconds: 20)), _now),
          'Just now');
      expect(
          relativeTime(_now.add(const Duration(minutes: 3)), _now), 'Just now');
      expect(relativeTime(_now.subtract(const Duration(minutes: 5)), _now),
          '5 min ago');
      expect(relativeTime(_now.subtract(const Duration(hours: 3)), _now),
          '3 h ago');
      expect(relativeTime(_now.subtract(const Duration(hours: 20)), _now),
          '20 h ago');
      expect(relativeTime(_now.subtract(const Duration(hours: 30)), _now),
          'Yesterday');
      expect(relativeTime(_now.subtract(const Duration(days: 4)), _now),
          '4 days ago');
      expect(relativeTime(DateTime(2026, 9, 1, 9), _now), '2026-09-01');
    });
  });

  group('header', () {
    testWidgets('Mark all read shows only with unread messages and reads all',
        (tester) async {
      final (feed, _) = await _open(tester, [_n('a'), _n('b')]);
      final button = find.byKey(const ValueKey('notifications-mark-all-read'));
      expect(button, findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(feed.calls, contains('read-all'));
      expect(button, findsNothing);
    });

    testWidgets('no unread: no Mark all read', (tester) async {
      await _open(tester, [_n('a', read: true)]);
      expect(find.byKey(const ValueKey('notifications-mark-all-read')),
          findsNothing);
    });

    testWidgets('the named back button leaves the page', (tester) async {
      await _open(tester, [_n('a')]);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('stub home'), findsOneWidget);
    });

    testWidgets('the collapsed title shows once the large title scrolls away',
        (tester) async {
      await _open(tester, [for (var i = 0; i < 12; i++) _n('m$i')]);
      AnimatedOpacity collapsed() => tester.widget<AnimatedOpacity>(find
          .ancestor(
              of: find.text('Notifications').first,
              matching: find.byType(AnimatedOpacity))
          .first);
      expect(find.text('Notifications'), findsNWidgets(2));
      expect(collapsed().opacity, 0);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(collapsed().opacity, 1);
    });
  });

  group('states', () {
    testWidgets('an open loading page stops and restarts with motion settings',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final reduced = ValueNotifier(false);
      addTearDown(reduced.dispose);
      await _open(tester, const [], loading: true, reducedMotion: reduced);
      final label = find.bySemanticsLabel('Loading notifications');
      final ring = find.byType(CircularProgressIndicator);
      expect(tester.widget<CircularProgressIndicator>(ring).value, isNull);
      expect(tester.hasRunningAnimations, isTrue);

      reduced.value = true;
      await tester.pumpAndSettle();
      expect(tester.widget<CircularProgressIndicator>(ring).value, isNotNull);
      expect(tester.getSemantics(label).getSemanticsData().value, isEmpty);
      expect(tester.hasRunningAnimations, isFalse);

      reduced.value = false;
      await tester.pump();
      expect(tester.widget<CircularProgressIndicator>(ring).value, isNull);
      expect(tester.hasRunningAnimations, isTrue);
      semantics.dispose();
    });

    testWidgets('loading with nothing yet shows a progress ring',
        (tester) async {
      await _open(tester, const [], loading: true);
      expect(find.byType(ProgressRing), findsOneWidget);
      expect(find.bySemanticsLabel('Loading notifications'), findsOneWidget);
    });

    testWidgets('empty: the caught-up state, and pull to refresh still works',
        (tester) async {
      final (feed, _) = await _open(tester, const []);
      expect(find.byKey(const ValueKey('notifications-empty')), findsOneWidget);
      expect(find.text("You're all caught up"), findsOneWidget);
      expect(find.text('Nothing new right now.'), findsOneWidget);
      final before = feed.calls.where((c) => c == 'refresh').length;
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(feed.calls.where((c) => c == 'refresh').length, before + 1);
    });

    testWidgets('error: the retry state, and pull to refresh retries',
        (tester) async {
      final (feed, _) = await _open(tester, const [], error: 'offline');
      expect(find.byKey(const ValueKey('notifications-error')), findsOneWidget);
      expect(find.text('Could not load notifications'), findsOneWidget);
      expect(find.text('Pull down to retry.'), findsOneWidget);
      final before = feed.calls.where((c) => c == 'refresh').length;
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(feed.calls.where((c) => c == 'refresh').length, before + 1);
    });
  });

  group('cards', () {
    testWidgets('unread cards show the dot; read cards do not', (tester) async {
      await _open(tester, [_n('a'), _n('b', read: true)]);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('notification-a')),
              matching: find.byKey(const ValueKey('notification-unread-dot'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('notification-b')),
              matching: find.byKey(const ValueKey('notification-unread-dot'))),
          findsNothing);
      expect(find.text('5 min ago'), findsNWidgets(2));
    });

    testWidgets('a critical message keeps its alert mark and says so',
        (tester) async {
      await _open(tester, [_n('c', priority: 'critical')]);
      expect(find.byIcon(AtomicIcons.alertTriangle), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Unread, Critical, Subject c, ')),
          findsOneWidget);
    });

    testWidgets('an Energy action opens the Energy page and marks it read',
        (tester) async {
      final (feed, routes) = await _open(tester, [
        _n('e', action: 'Open Energy', actionUrl: '/energypage'),
      ]);
      await tester.tap(find.text('Open Energy'));
      await tester.pumpAndSettle();
      expect(feed.calls, contains('read e'));
      expect(routes.pushed.last, '/energypage');
      expect(find.text('stub energy'), findsOneWidget);
    });

    testWidgets('an unknown action asks to update the app', (tester) async {
      final (feed, routes) = await _open(tester, [
        _n('u', action: 'Try it', actionUrl: 'atomic://future-screen'),
      ]);
      await tester.tap(find.text('Try it'));
      await tester.pump();
      expect(feed.calls, contains('read u'));
      expect(find.text('Update Atomic Notes to open this.'), findsOneWidget);
      expect(routes.pushed.where((r) => r == '/energypage'), isEmpty);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the action button does not also count as a card tap twice',
        (tester) async {
      final (feed, _) = await _open(tester, [
        _n('e', action: 'Open Energy', actionUrl: '/energypage'),
      ]);
      await tester.tap(find.text('Open Energy'));
      await tester.pumpAndSettle();
      expect(feed.calls.where((c) => c == 'read e'), hasLength(1));
    });
  });

  group('layout and accessibility', () {
    for (final theme
        in {'light': AtomicTheme.light, 'dark': AtomicTheme.dark}.entries) {
      testWidgets('${theme.key}: 320 dp at 2.0 text has no overflow',
          (tester) async {
        await _open(
          tester,
          [
            _n('a',
                subject: 'A long maintenance notice for every account',
                action: 'Open Energy',
                actionUrl: '/energypage',
                priority: 'critical'),
            _n('p', dismissible: false, read: true),
          ],
          theme: theme.value,
          size: const Size(320, 700),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        // Too wide for the header here, so it sits under the page title.
        final markAll =
            find.byKey(const ValueKey('notifications-mark-all-read'));
        expect(markAll, findsOneWidget);
        expect(
            tester.getTopLeft(markAll).dy,
            greaterThan(
                tester.getBottomLeft(find.text('Notifications').last).dy - 1));
        expect(find.byTooltip('Dismiss'), findsOneWidget);
        // The pinned card is below the fold here; scroll to it.
        await tester.scrollUntilVisible(
            find.byKey(const ValueKey('notification-pinned')), 200,
            scrollable: find.byType(Scrollable).first);
        expect(
            find.byKey(const ValueKey('notification-pinned')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dismiss, back and Mark all read have 48 dp targets',
        (tester) async {
      await _open(tester, [_n('a')]);
      for (final finder in [
        find.byTooltip('Dismiss'),
        find.byTooltip('Back'),
        find.byKey(const ValueKey('notifications-mark-all-read')),
      ]) {
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
      }
    });

    testWidgets('reduced motion renders and still marks read on tap',
        (tester) async {
      final (feed, _) = await _open(tester, [_n('a')], disableAnimations: true);
      await tester.tap(find.byKey(const ValueKey('notification-a')));
      await tester.pump();
      expect(feed.calls, contains('read a'));
      expect(tester.takeException(), isNull);
    });
  });
}
