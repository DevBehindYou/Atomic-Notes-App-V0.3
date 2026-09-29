import 'package:equatable/equatable.dart';

/// In-app notification model: a row of the Server's `/notifications` feed, which
/// joins what the Controller published with this user's read/dismiss state. Plain
/// data type; icon/colour mapping lives in the UI.
class AppNotification extends Equatable {
  final String id;
  final String type;
  final String subject;
  final String description;
  final String priority; // low | normal | high | critical
  final String status; // active | resolved | expired
  final String? action; // CTA label
  final String? actionUrl; // CTA destination
  final String? icon; // category asset key
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isRead;
  final DateTime? dismissedAt;

  /// When false, the user cannot dismiss/delete this notification (pinned by an
  /// admin — e.g. a critical incident or a mandatory update). The ✕ is hidden
  /// and the server refuses the dismiss RPC.
  final bool dismissible;

  const AppNotification({
    required this.id,
    required this.type,
    required this.subject,
    required this.description,
    required this.priority,
    required this.status,
    required this.action,
    required this.actionUrl,
    required this.icon,
    required this.createdAt,
    required this.expiresAt,
    required this.isRead,
    required this.dismissedAt,
    required this.dismissible,
  });

  @override
  List<Object?> get props => [
        id,
        type,
        subject,
        description,
        priority,
        status,
        action,
        actionUrl,
        icon,
        createdAt,
        expiresAt,
        isRead,
        dismissedAt,
        dismissible,
      ];

  AppNotification copyWith({bool? isRead, DateTime? dismissedAt}) => AppNotification(
        id: id,
        type: type,
        subject: subject,
        description: description,
        priority: priority,
        status: status,
        action: action,
        actionUrl: actionUrl,
        icon: icon,
        createdAt: createdAt,
        expiresAt: expiresAt,
        isRead: isRead ?? this.isRead,
        dismissedAt: dismissedAt ?? this.dismissedAt,
        dismissible: dismissible,
      );

  bool get isCritical => priority == 'critical';
  bool get hasAction =>
      (action != null && action!.isNotEmpty) &&
      (actionUrl != null && actionUrl!.isNotEmpty);

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    DateTime? dt(dynamic v) =>
        v == null ? null : DateTime.tryParse('$v')?.toLocal();
    return AppNotification(
      id: '${m['id']}',
      type: '${m['type']}',
      subject: '${m['subject']}',
      description: '${m['description']}',
      priority: '${m['priority'] ?? 'normal'}',
      status: '${m['status'] ?? 'active'}',
      action: m['action'] as String?,
      actionUrl: m['action_url'] as String?,
      icon: m['icon'] as String?,
      createdAt: dt(m['created_at']) ?? DateTime.now(),
      expiresAt: dt(m['expires_at']),
      isRead: m['is_read'] == true,
      dismissedAt: dt(m['dismissed_at']),
      // Default true: rows/feeds without the field are dismissible.
      dismissible: m['dismissible'] != false,
    );
  }
}
