import 'package:atomic_notes/database/notification_models.dart';
import 'package:flutter/foundation.dart';

/// What the notifications state needs from the place the feed is kept.
///
/// [NotificationService] is the real one. The state layer only sees this interface, so it is tested
/// with a fake and no network.
abstract interface class NotificationsSource implements Listenable {
  List<AppNotification> get items;
  bool get loading;

  /// Why the last load failed, in words for the user.
  String? get error;

  Future<void> refresh();
  Future<void> markRead(String id);
  Future<void> markAllRead();
  Future<void> dismiss(String id);
}
