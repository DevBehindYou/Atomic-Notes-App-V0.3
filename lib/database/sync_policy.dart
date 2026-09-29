import 'dart:io';

import 'package:http/http.dart' show ClientException;

/// Small sync decisions kept apart from [NotesRepository] so they can be tested
/// without Hive, the network or the Server.

/// True when [error] means the connection went away (no route, dropped socket,
/// failed TLS), not that the Server answered with a refusal.
bool isNetworkFailure(Object error) =>
    error is SocketException ||
    error is ClientException ||
    error is TlsException ||
    error is HttpException;

/// Whether a sync may send a push now.
///
/// A manual (instant) sync always may. An automatic one waits while the Server
/// has closed automatic sync, except to replay a push that was already sent and
/// never answered: the Server recorded that request under its id, so sending it
/// again costs nothing and only collects the result.
bool mayPushNow({
  required bool instant,
  required DateTime? nextAutoSyncAt,
  required bool hasUnansweredPush,
}) =>
    instant || nextAutoSyncAt == null || hasUnansweredPush;

/// Whether a finished push closes automatic sync for the Server's interval.
///
/// Only a standard request that wrote something does. What counts is how the
/// request was sent, not what triggered this attempt: an instant request replayed
/// by an automatic trigger was still instant, and the Server did not start the
/// hourly wait for it.
bool closesAutomaticSync({
  required bool sentInstant,
  required Iterable<Map<String, dynamic>> results,
}) =>
    !sentInstant && results.any((r) => r['ok'] == true);

/// How long to wait before trying an automatic sync again after a network
/// failure: 5 s, 15 s, then 45 s. Null after that; the next reconnect, resume or
/// edit starts a new round.
Duration? networkRetryDelay(int attempt) => switch (attempt) {
      0 => const Duration(seconds: 5),
      1 => const Duration(seconds: 15),
      2 => const Duration(seconds: 45),
      _ => null,
    };
