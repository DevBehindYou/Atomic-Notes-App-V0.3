import 'package:atomic_notes/database/notification_models.dart';
import 'package:atomic_notes/database/notifications_source.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// The in-app notification feed.
final class NotificationsState extends Equatable {
  const NotificationsState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final List<AppNotification> items;
  final bool loading;
  final String? error;

  int get unreadCount => items.where((n) => !n.isRead).length;

  @override
  List<Object?> get props => [items, loading, error];
}

/// State and actions of the Notification Center and its bell badge.
class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit({required NotificationsSource source})
      : _source = source,
        super(_read(source)) {
    _source.addListener(_changed);
  }

  final NotificationsSource _source;

  static NotificationsState _read(NotificationsSource source) =>
      NotificationsState(
        items: List<AppNotification>.unmodifiable(source.items),
        loading: source.loading,
        error: source.error,
      );

  void _changed() {
    if (isClosed) return;
    final next = _read(_source);
    if (next != state) emit(next);
  }

  @override
  Future<void> close() {
    _source.removeListener(_changed);
    return super.close();
  }

  Future<void> refresh() => _source.refresh();
  Future<void> markRead(String id) => _source.markRead(id);
  Future<void> markAllRead() => _source.markAllRead();
  Future<void> dismiss(String id) => _source.dismiss(id);
}
