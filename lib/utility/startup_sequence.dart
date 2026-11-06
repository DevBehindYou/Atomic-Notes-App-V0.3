import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/note_quota.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/profile/profile_store.dart';
import 'package:atomic_notes/security/screen_security.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/utility/startup_trace.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Bounded so startup can't hang forever. ApiClient.init() only reads a local
/// secure-storage token (no network), so this is fast; the timeout mirrors the
/// old Supabase.initialize() one so a slow keystore read still can't block the
/// app opening.
const Duration apiInitTimeout = Duration(seconds: 8);

/// The services main() initializes before the first frame. Tests replace them
/// to check ordering, fallbacks and failures of [runStartupSequence].
class StartupServices {
  const StartupServices();
  Future<void> initApi() => ApiClient.instance.init();
  Future<void> initHive() => Hive.initFlutter();
  Future<void> openBox(String name) => Hive.openBox<bool>(name);
  Future<void> applyScreenSecurity() => ScreenSecurity.applySaved();
  Future<void> initProfile() => ProfileStore.instance.init();
  Future<void> initSyncStatus() => SyncStatusHelper.init();
  Future<void> initQuota() => NoteQuota.init();
  Future<void> initVault() => Vault.instance.initAtStartup();
  Future<void> initRepository() => NotesRepository.instance.init();
}

/// main()'s pre-first-frame initialization, one step after another. A failed
/// or slow API init is tolerated (local-first); any other failure is rethrown
/// so main() can show the startup failure screen.
Future<void> runStartupSequence(
    StartupServices services, StartupTrace trace) async {
  try {
    await trace.step(
        StartupStep.apiInit, () => services.initApi().timeout(apiInitTimeout));
  } catch (e) {
    // Local-first: a slow or absent secure-storage read must never block
    // startup. Continue so local notes always open.
    debugPrint('ApiClient.init slow/failed; continuing local-first: $e');
  }

  await trace.step(StartupStep.hiveInit, services.initHive);
  // open the Hive Boxes. These stay open for the life of the process —
  // individual screens must not close them (see splash_screen.dart).
  await trace.step(StartupStep.authBox, () => services.openBox('authBox'));
  // "No screenshots" is a device-wide choice: apply it before any screen shows.
  await trace.step(StartupStep.screenSecurity, services.applyScreenSecurity);
  // Avatar and profile switches are local: read them before any screen draws.
  await trace.step(StartupStep.profile, services.initProfile);
  await trace.step(StartupStep.syncBox, () => services.openBox('syncBox'));
  await trace.step(StartupStep.syncStatus, services.initSyncStatus);
  await trace.step(StartupStep.quota, services.initQuota);
  // Determine encryption state and auto-unlock from a cached key (if any)
  // before the repository loads, so encrypted notes can be decrypted on load.
  // The splash's first check may reuse this one result (see initAfterStartup).
  await trace.step(StartupStep.vault, services.initVault);
  await trace.step(StartupStep.repository, services.initRepository);
}
