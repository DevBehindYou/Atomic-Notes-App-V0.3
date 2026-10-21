Uri acceptanceBase(String raw, {required bool enabled, required bool release}) {
  final uri = Uri.tryParse(raw);
  if (!enabled ||
      release ||
      uri == null ||
      uri.scheme != 'http' ||
      uri.host != '127.0.0.1' ||
      uri.port != 24139 ||
      uri.path != '/api' ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw StateError('acceptance_disabled');
  }
  return uri;
}

String acceptanceOwner(Object? value) {
  if (value is! Map ||
      value['owner'] is! String ||
      value['database'] is! String ||
      !RegExp(r'^atomic_test_[a-f0-9]{20}$')
          .hasMatch(value['database'] as String) ||
      !RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')
          .hasMatch(value['owner'] as String)) {
    throw StateError('fixture_invalid');
  }
  return value['owner'] as String;
}
