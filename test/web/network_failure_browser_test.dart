@TestOn('browser')
library;

import 'package:atomic_notes/database/network_failure_stub.dart';
import 'package:atomic_notes/database/sync_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;

void main() {
  test('browser transport failures keep bounded retry policy', () {
    final failure = ClientException('public opaque transport fixture');
    expect(isPlatformNetworkFailure(failure), isFalse);
    expect(isNetworkFailure(failure), isTrue);
    expect(isNetworkFailure(Exception('BAD_DECRYPT')), isFalse);
    expect(isNetworkFailure(Exception('sync_cooldown')), isFalse);
  });
}
