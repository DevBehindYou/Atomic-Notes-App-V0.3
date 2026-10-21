import 'package:flutter_test/flutter_test.dart';
import '../../tool/device_acceptance/guard.dart';

void main() {
  test(
      'acceptance allows only an explicitly enabled non-release loopback build',
      () {
    expect(
        acceptanceBase('http://127.0.0.1:24139/api',
                enabled: true, release: false)
            .host,
        '127.0.0.1');
  });
  test('production, remote, credentialed and ambiguous targets are rejected',
      () {
    for (final value in [
      'https://example.com/api',
      'http://localhost:24139/api',
      'http://127.0.0.1:24140/api',
      'http://user@127.0.0.1:24139/api',
      'http://127.0.0.1:24139/api?q=x',
      'http://127.0.0.1:24139/api#x'
    ]) {
      expect(() => acceptanceBase(value, enabled: true, release: false),
          throwsStateError);
    }
    expect(
        () => acceptanceBase('http://127.0.0.1:24139/api',
            enabled: false, release: false),
        throwsStateError);
    expect(
        () => acceptanceBase('http://127.0.0.1:24139/api',
            enabled: true, release: true),
        throwsStateError);
  });
  test(
      'only a generated fixture database and valid synthetic owner can be seeded',
      () {
    const owner = '12345678-1234-4234-8234-123456789abc';
    expect(
        acceptanceOwner(
            {'owner': owner, 'database': 'atomic_test_1234567890abcdef1234'}),
        owner);
    for (final data in [
      null,
      {},
      {'owner': owner, 'database': 'Atomic-DB'},
      {'owner': 'invalid', 'database': 'atomic_test_1234567890abcdef1234'}
    ]) {
      expect(() => acceptanceOwner(data), throwsStateError);
    }
  });
}
