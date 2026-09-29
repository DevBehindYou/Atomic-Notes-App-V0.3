// The Notification Center with a fake feed: a tap on a card marks it read, the ✕ dismisses, and a
// pinned message has no ✕. Found on the phone (2026-09-27): a message without an action button
// could only be marked read with "Mark all read".

import 'package:atomic_notes/database/notification_models.dart';
import 'package:atomic_notes/database/notifications_source.dart';
import 'package:atomic_notes/page/endpage/notifications_page.dart';
import 'package:atomic_notes/state/notifications/notifications_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _n(String id, {bool read = false, bool dismissible = true, String priority = 'normal'}) =>
    AppNotification(
      id: id,
      type: 'general',
      subject: 'Subject $id',
      description: 'Body $id',
      priority: priority,
      status: 'active',
      action: null,
      actionUrl: null,
      icon: null,
      createdAt: DateTime(2026, 9, 27, 18, 3),
      expiresAt: null,
      isRead: read,
      dismissedAt: null,
      dismissible: dismissible,
    );

class _FakeFeed extends ChangeNotifier implements NotificationsSource {
  _FakeFeed(this._items);

  List<AppNotification> _items;
  final List<String> calls = [];

  @override
  List<AppNotification> get items => _items;
  @override
  bool get loading => false;
  @override
  String? get error => null;

  @override
  Future<void> refresh() async => calls.add('refresh');

  @override
  Future<void> markRead(String id) async {
    calls.add('read $id');
    _items = [for (final n in _items) n.id == id ? n.copyWith(isRead: true) : n];
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

Future<_FakeFeed> _open(WidgetTester tester, List<AppNotification> items) async {
  final feed = _FakeFeed(items);
  final cubit = NotificationsCubit(source: feed);
  addTearDown(cubit.close);
  await tester.pumpWidget(MaterialApp(
    home: BlocProvider<NotificationsCubit>.value(value: cubit, child: const NotificationsPage()),
  ));
  await tester.pump();
  return feed;
}

void main() {
  testWidgets('a tap on an unread card marks it read, once', (tester) async {
    final feed = await _open(tester, [_n('a'), _n('b', read: true)]);
    await tester.tap(find.byKey(const ValueKey('notification-a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('notification-a')));
    await tester.tap(find.byKey(const ValueKey('notification-b')));
    await tester.pump();
    expect(feed.calls.where((c) => c.startsWith('read ')), ['read a']);
    expect(find.text('MARK ALL READ'), findsNothing, reason: 'nothing unread is left');
  });

  testWidgets('the ✕ dismisses without also counting as a card tap', (tester) async {
    final feed = await _open(tester, [_n('a')]);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(feed.calls, contains('dismiss a'));
    expect(feed.calls, isNot(contains('read a')));
    expect(find.text('Subject a'), findsNothing);
  });

  testWidgets('a pinned message shows a pin, not a ✕', (tester) async {
    await _open(tester, [_n('p', dismissible: false, priority: 'critical')]);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
  });
}
