import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/notification_models.dart';
import 'package:atomic_notes/database/notifications_source.dart';
import 'package:atomic_notes/utility/app_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

/// The calls [NotificationService] makes, so it can be tested without the network.
abstract interface class NotificationsApi {
  Future<List<Map<String, dynamic>>> feed({String? appVersion});
  Future<void> markRead(String id);
  Future<void> markAllRead();
  Future<void> dismiss(String id);
}

class _ServerNotificationsApi implements NotificationsApi {
  const _ServerNotificationsApi();

  ApiClient get _api => ApiClient.instance;

  @override
  Future<List<Map<String, dynamic>>> feed({String? appVersion}) =>
      _api.notificationsFeed(appVersion: appVersion);
  @override
  Future<void> markRead(String id) => _api.markNotificationRead(id);
  @override
  Future<void> markAllRead() => _api.markAllNotificationsRead();
  @override
  Future<void> dismiss(String id) => _api.dismissNotification(id);
}

/// The in-app notification feed: what the Controller published to this account, with its own
/// read and dismiss state kept on the Server.
///
/// Marking read and dismissing show at once and are then sent; if sending fails the next
/// [refresh] brings back what the Server holds. A feed fetched for one account is dropped if
/// the account changes while it is on its way.
class NotificationService extends ChangeNotifier with WidgetsBindingObserver implements NotificationsSource {
  NotificationService._(this._api, this._currentUser);

  static final NotificationService instance = NotificationService._(
      const _ServerNotificationsApi(), () => ApiClient.instance.currentUserId);

  @visibleForTesting
  factory NotificationService.forTest(NotificationsApi api, String? Function() currentUser) =>
      NotificationService._(api, currentUser);

  final NotificationsApi _api;
  final String? Function() _currentUser;

  List<AppNotification> _items = const [];
  bool _loading = false;
  String? _error;
  String? _boundUser;
  bool _observing = false;
  DateTime? _fetchedAt;

  /// Coming back to the App fetches the feed again, at most this often.
  static const Duration _resumeRefreshGap = Duration(minutes: 1);

  @override
  List<AppNotification> get items => _items;
  @override
  bool get loading => _loading;
  @override
  String? get error => _error;
  int get unreadCount => _items.where((n) => !n.isRead).length;

  /// Binds the feed to the signed-in account and loads it.
  Future<void> init() async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final uid = _currentUser();
    if (uid != _boundUser) {
      _items = const [];
      _error = null;
      _boundUser = uid;
      notifyListeners();
    }
    if (uid != null) await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _fetchedAt;
    if (last != null && DateTime.now().difference(last) < _resumeRefreshGap) return;
    unawaited(refresh());
  }

  void clear() {
    _items = const [];
    _error = null;
    _boundUser = null;
    notifyListeners();
  }

  @override
  Future<void> refresh() async {
    final uid = _currentUser();
    if (uid == null) return;
    _boundUser = uid;
    _loading = true;
    notifyListeners();
    try {
      final rows = await _api.feed(appVersion: AppInfoText.version);
      if (_currentUser() != uid) return; // signed out or switched account meanwhile
      _items = List.unmodifiable(rows.map(AppNotification.fromMap));
      _error = null;
      _fetchedAt = DateTime.now();
    } catch (e) {
      if (_currentUser() != uid) return;
      debugPrint('NotificationService.refresh failed: $e');
      _error = 'Could not load notifications. Pull down to retry.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  Future<void> markRead(String id) async {
    final i = _items.indexWhere((n) => n.id == id);
    if (i < 0 || _items[i].isRead) return;
    _replace(i, _items[i].copyWith(isRead: true));
    await _send(() => _api.markRead(id));
  }

  @override
  Future<void> markAllRead() async {
    if (_items.every((n) => n.isRead)) return;
    _items = List.unmodifiable(_items.map((n) => n.copyWith(isRead: true)));
    notifyListeners();
    await _send(_api.markAllRead);
  }

  @override
  Future<void> dismiss(String id) async {
    final i = _items.indexWhere((n) => n.id == id);
    // Pinned by the Controller: the Server refuses too, so it is not even tried.
    if (i < 0 || !_items[i].dismissible) return;
    _items = List.unmodifiable(_items.where((n) => n.id != id));
    notifyListeners();
    await _send(() => _api.dismiss(id));
  }

  void _replace(int index, AppNotification next) {
    final list = [..._items];
    list[index] = next;
    _items = List.unmodifiable(list);
    notifyListeners();
  }

  /// Sends a change already shown on screen. On failure the Server's copy is fetched again,
  /// so the screen never keeps showing something the Server did not record.
  Future<void> _send(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      debugPrint('NotificationService: change not saved: $e');
      unawaited(refresh());
    }
  }
}
