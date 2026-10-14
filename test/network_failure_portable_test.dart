import 'dart:async';

import 'package:atomic_notes/database/sync_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;

void main() {
  test('portable HTTP failures retain retries without message matching', () {
    expect(isNetworkFailure(ClientException('opaque browser failure')), isTrue);
    expect(isNetworkFailure(Exception('Network is unreachable')), isFalse);
    expect(isNetworkFailure(Exception('insufficient_energy')), isFalse);
    expect(isNetworkFailure(TimeoutException('slow')), isFalse);
    expect(isNetworkFailure(StateError('bug')), isFalse);
    expect(
      [for (var i = 0; i < 4; i++) networkRetryDelay(i)],
      [
        const Duration(seconds: 5),
        const Duration(seconds: 15),
        const Duration(seconds: 45),
        null,
      ],
    );
  });
}
