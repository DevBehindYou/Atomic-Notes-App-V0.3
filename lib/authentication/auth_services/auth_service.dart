// ignore_for_file: unnecessary_null_comparison

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/profile/profile_store.dart';

/// What [AuthServices.updateUsername] established (review R32).
enum UsernameUpdateOutcome {
  /// The Server took the name and this device cached it.
  saved,

  /// The Server did not take the name, or could not be reached.
  rejected,

  /// The Server took the name, but caching it on this device failed. The
  /// update is not a failure; refresh the handle to reconcile.
  savedUncached,
}

class AuthServices {
  /// [api] defaults to [ApiClient.instance]; tests pass a fixture client.
  AuthServices({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;
  late String userId = _api.currentUserId!;

  // update user info
  Future<String?> updateUserInfo({
    required String username,
  }) async {
    try {
      // MIGRATION NOTE: this used to be an insert-then-catch-23505-then-update
      // dance to work around Supabase not offering an atomic upsert at this
      // call site. The server does a real upsert in one round trip now
      // (routes/atomicuser.ts), so there's nothing left to catch here.
      await _api.setUsername(username);
      await ProfileStore.instance.cacheUsername(username);
      return "Username updated wait for refresh";
    } catch (error) {
      return "Error updating username";
    }
  }

  /// The same update as [updateUserInfo], with a typed outcome instead of a
  /// message, so the caller never reads success from visible copy (review
  /// R32). A failed local cache write after the Server took the name is
  /// reported apart from a failed update.
  Future<UsernameUpdateOutcome> updateUsername(String username) async {
    try {
      await _api.setUsername(username);
    } catch (_) {
      return UsernameUpdateOutcome.rejected;
    }
    try {
      await ProfileStore.instance.cacheUsername(username);
    } catch (_) {
      return UsernameUpdateOutcome.savedUncached;
    }
    return UsernameUpdateOutcome.saved;
  }

  /// The handle to show before the Server answers: the last one this account had.
  static String get cachedHandle {
    final cached = ProfileStore.instance.cachedUsername;
    return cached == null ? "@atomicuser" : "@$cached";
  }

  // fetch user info from the Atomic Notes API
  Future<String> getUserInfo() async {
    try {
      final username = await _api.getUsername();
      if (username == "") {
        return "@atomicuser";
      }
      await ProfileStore.instance.cacheUsername(username);
      return "@$username";
    } catch (error) {
      // Offline or the Server is down: keep the name this account last had.
      return cachedHandle;
    }
  }
}
