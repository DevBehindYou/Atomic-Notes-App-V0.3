Uri serverFixtureOrigin(String value) {
  try {
    final uri = Uri.parse(value);
    if (uri.scheme == 'http' &&
        uri.host == '127.0.0.1' &&
        uri.hasPort &&
        uri.port > 0 &&
        uri.port <= 65535 &&
        uri.userInfo.isEmpty &&
        uri.path.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment) {
      return uri;
    }
  } on FormatException {
    // Never echo a rejected URL: it could contain credentials.
  }
  throw StateError('Only the disposable IPv4 loopback fixture is allowed');
}
