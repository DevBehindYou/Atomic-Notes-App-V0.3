import 'package:flutter_test/flutter_test.dart';
import 'support/server_fixture_origin.dart';

void main() {
  test('accepts explicit HTTP IPv4 loopback fixture port', () {
    expect(serverFixtureOrigin('http://127.0.0.1:31001').port, 31001);
  });
  for (final entry in {
    'remote': 'http://example.test:31001',
    'TLS': 'https://127.0.0.1:31001',
    'credentials': 'http://dummy:dummy@127.0.0.1:31001',
    'path': 'http://127.0.0.1:31001/api',
    'query': 'http://127.0.0.1:31001?x=1',
    'fragment': 'http://127.0.0.1:31001#x',
    'implicit port': 'http://127.0.0.1',
    'zero port': 'http://127.0.0.1:0',
  }.entries) {
    test('refuses ${entry.key} before client creation', () {
      expect(() => serverFixtureOrigin(entry.value), throwsStateError);
    });
  }
}
