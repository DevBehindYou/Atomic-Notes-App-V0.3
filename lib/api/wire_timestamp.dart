final _serverUtcTimestamp = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$',
);

/// Server receipts use UTC ISO milliseconds (legacy receipts may omit them).
/// Parsing alone normalizes impossible dates; exact round-trip rejects them.
bool isServerUtcTimestamp(Object? value) {
  if (value is! String || !_serverUtcTimestamp.hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return false;
  final canonical = value.contains('.')
      ? value
      : value.replaceFirst('Z', '.000Z');
  return parsed.toUtc().toIso8601String() == canonical;
}
