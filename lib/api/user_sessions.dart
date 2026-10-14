/// Opaque inventory handles are neither bearer tokens nor stored token hashes.
class UserSession {
  const UserSession({
    required this.handle,
    required this.createdAt,
    required this.expiresAt,
    required this.isCurrent,
    required this.agentLabel,
  });
  final String handle;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isCurrent;
  final String? agentLabel;

  static final handlePattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
  static final _datePattern = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  );
  static DateTime _date(Object? value) {
    if (value is! String || !_datePattern.hasMatch(value)) {
      throw const FormatException('Invalid session date');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toUtc().toIso8601String() != value) {
      throw const FormatException('Invalid session date');
    }
    return parsed.toUtc();
  }

  factory UserSession.parse(Object? value) {
    if (value is! Map ||
        value.length != 5 ||
        !value.keys.every(
          const {
            'session_handle',
            'created_at',
            'expires_at',
            'is_current',
            'agent_label',
          }.contains,
        ) ||
        value['session_handle'] is! String ||
        !handlePattern.hasMatch(value['session_handle'] as String) ||
        value['is_current'] is! bool ||
        (value['agent_label'] != null &&
            (value['agent_label'] is! String ||
                (value['agent_label'] as String).runes.length > 80 ||
                RegExp(
                  r'[\x00-\x1f\x7f\u0080-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff]',
                ).hasMatch(value['agent_label'] as String)))) {
      throw const FormatException('Invalid session inventory row');
    }
    final issued = _date(value['created_at']),
        expires = _date(value['expires_at']);
    if (!expires.isAfter(issued)) {
      throw const FormatException('Invalid session lifetime');
    }
    return UserSession(
      handle: value['session_handle'] as String,
      createdAt: issued,
      expiresAt: expires,
      isCurrent: value['is_current'] as bool,
      agentLabel: value['agent_label'] as String?,
    );
  }
}

class UserSessionInventory {
  const UserSessionInventory(this.sessions, this.limit);
  final List<UserSession> sessions;
  final int limit;

  factory UserSessionInventory.parse(Object? value) {
    if (value is! Map ||
        value.length != 2 ||
        value['limit'] != 5 ||
        value['sessions'] is! List ||
        (value['sessions'] as List).length > 5) {
      throw const FormatException('Invalid session inventory');
    }
    final rows = (value['sessions'] as List)
        .map(UserSession.parse)
        .toList(growable: false);
    if (rows.map((row) => row.handle).toSet().length != rows.length ||
        (rows.isNotEmpty && rows.where((row) => row.isCurrent).length != 1)) {
      throw const FormatException('Invalid session inventory identities');
    }
    return UserSessionInventory(List.unmodifiable(rows), 5);
  }
}
