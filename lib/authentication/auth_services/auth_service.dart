// ignore_for_file: unnecessary_null_comparison

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/profile/profile_store.dart';

class AuthServices {
  final ApiClient _api = ApiClient.instance;
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
