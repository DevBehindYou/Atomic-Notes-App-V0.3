// Sync decisions found on a real phone (2026-09-27 device run): a paid push whose answer was
// lost stayed "waiting" for an hour, and a reconnect gave up after one early try.

import 'dart:async';
import 'dart:io';

import 'package:atomic_notes/database/sync_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;

void main() {
  group('mayPushNow', () {
    final closed = DateTime.now().add(const Duration(minutes: 48));

    test('an instant sync always may', () {
      expect(mayPushNow(instant: true, nextAutoSyncAt: closed, hasUnansweredPush: false), isTrue);
    });

    test('an automatic sync waits while the window is closed', () {
      expect(mayPushNow(instant: false, nextAutoSyncAt: closed, hasUnansweredPush: false), isFalse);
      expect(mayPushNow(instant: false, nextAutoSyncAt: null, hasUnansweredPush: false), isTrue);
    });

    test('an unanswered push is replayed even while the window is closed', () {
      expect(mayPushNow(instant: false, nextAutoSyncAt: closed, hasUnansweredPush: true), isTrue);
    });
  });

  group('closesAutomaticSync', () {
    final written = [
      {'id': 'a', 'ok': true},
    ];
    final refused = [
      {'id': 'a', 'ok': false, 'error': 'note_conflict'},
    ];

    test('a standard push that wrote something closes it', () {
      expect(closesAutomaticSync(sentInstant: false, results: written), isTrue);
    });

    test('a replayed instant push does not, whatever triggered the replay', () {
      expect(closesAutomaticSync(sentInstant: true, results: written), isFalse);
    });

    test('a standard push that wrote nothing does not', () {
      expect(closesAutomaticSync(sentInstant: false, results: refused), isFalse);
      expect(closesAutomaticSync(sentInstant: false, results: const []), isFalse);
    });
  });

  group('isNetworkFailure', () {
    test('lost connections count', () {
      expect(isNetworkFailure(const SocketException('Network is unreachable')), isTrue);
      expect(isNetworkFailure(ClientException('Software caused connection abort')), isTrue);
      expect(isNetworkFailure(const HandshakeException('reset')), isTrue);
    });

    test('Server refusals and timeouts do not', () {
      expect(isNetworkFailure(Exception('insufficient_energy')), isFalse);
      expect(isNetworkFailure(TimeoutException('slow')), isFalse);
      expect(isNetworkFailure(StateError('bug')), isFalse);
    });
  });

  test('network retries back off and then stop', () {
    expect(
      [for (var i = 0; i < 4; i++) networkRetryDelay(i)],
      [const Duration(seconds: 5), const Duration(seconds: 15), const Duration(seconds: 45), null],
    );
  });
}
