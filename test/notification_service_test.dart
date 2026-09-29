// The notification feed against a fake Server: what it loads, what a tap on read or dismiss
// shows at once, and what happens when the Server does not take a change.

import 'dart:async';

import 'package:atomic_notes/database/notification_models.dart';
import 'package:atomic_notes/database/notification_service.dart';
import 'package:atomic_notes/utility/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(String id, {bool read = false, bool dismissible = true, String created = '2026-09-27T10:00:00.000Z'}) => {
      'id': id,
      'type': 'general',
      'subject': 'Subject $id',
      'description': 'Body $id',
      'priority': 'normal',
      'status': 'active',
      'action': null,
      'action_url': null,
      'icon': null,
      'dismissible': dismissible,
      'created_at': created,
      'expires_at': null,
      'is_read': read,
      'dismissed_at': null,
    };

class _FakeApi implements NotificationsApi {
  List<Map<String, dynamic>> rows = [];
  String? askedVersion;
  bool fail = false;
  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> feed({String? appVersion}) async {
    askedVersion = appVersion;
    calls.add('feed');
    if (fail) throw Exception('offline');
    return rows;
  }

  @override
  Future<void> markRead(String id) async {
    calls.add('read $id');
    if (fail) throw Exception('offline');
  }

  @override
  Future<void> markAllRead() async {
    calls.add('read-all');
    if (fail) throw Exception('offline');
  }

  @override
  Future<void> dismiss(String id) async {
    calls.add('dismiss $id');
    if (fail) throw Exception('offline');
  }
}

void main() {
  late _FakeApi api;
  String? user;
  late NotificationService service;

  setUp(() {
    api = _FakeApi()..rows = [_row('a'), _row('b', read: true), _row('p', dismissible: false)];
    user = 'user-1';
    service = NotificationService.forTest(api, () => user);
  });

  test('loads the feed for this App version and counts what is unread', () async {
    await service.refresh();
    expect(api.askedVersion, AppInfoText.version);
    expect(service.items.map((n) => n.id), ['a', 'b', 'p']);
    expect(service.unreadCount, 2);
    expect(service.error, isNull);
    expect(service.loading, isFalse);
  });

  test('marking read shows at once and is sent once', () async {
    await service.refresh();
    await service.markRead('a');
    expect(service.items.firstWhere((n) => n.id == 'a').isRead, isTrue);
    await service.markRead('a');
    expect(api.calls.where((c) => c == 'read a'), hasLength(1));
  });

  test('mark all read clears the badge', () async {
    await service.refresh();
    await service.markAllRead();
    expect(service.unreadCount, 0);
    expect(api.calls, contains('read-all'));
  });

  test('dismiss removes a message, but never a pinned one', () async {
    await service.refresh();
    await service.dismiss('a');
    expect(service.items.map((n) => n.id), ['b', 'p']);
    await service.dismiss('p');
    expect(service.items.map((n) => n.id), ['b', 'p']);
    expect(api.calls, isNot(contains('dismiss p')));
  });

  test('a change the Server does not take is undone by fetching the feed again', () async {
    await service.refresh();
    api.fail = true;
    await service.dismiss('a');
    await pumpEventQueue();
    // The fetch also failed: the error shows and the last good list stays.
    expect(service.error, isNotNull);
    api.fail = false;
    await service.refresh();
    expect(service.items.map((n) => n.id), contains('a'));
    expect(service.error, isNull);
  });

  test('a feed that arrives after the account changed is dropped', () async {
    final slow = _SlowApi(api.rows);
    service = NotificationService.forTest(slow, () => user);
    final loading = service.refresh();
    user = 'someone-else';
    slow.release();
    await loading;
    expect(service.items, isEmpty);
  });

  test('signed out: nothing is fetched', () async {
    user = null;
    await service.refresh();
    expect(api.calls, isEmpty);
  });

  test('the Server feed row parses, including read state and pinning', () {
    final n = AppNotification.fromMap(_row('x', read: true, dismissible: false));
    expect(n.isRead, isTrue);
    expect(n.dismissible, isFalse);
    expect(n.copyWith(isRead: false).isRead, isFalse);
    expect(n.copyWith(isRead: false).subject, 'Subject x');
  });
}

class _SlowApi extends _FakeApi {
  _SlowApi(List<Map<String, dynamic>> rows) {
    this.rows = rows;
  }

  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<List<Map<String, dynamic>>> feed({String? appVersion}) async {
    await _gate.future;
    return rows;
  }
}
