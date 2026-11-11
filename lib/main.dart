import 'dart:async';
import 'mascot/mascot_runtime.dart';
import 'page/endpage/mascot_settings_page.dart';

import 'package:atomic_notes/appearance/appearance_controller.dart';
import 'package:atomic_notes/authentication/auth_pages/login_page.dart';
import 'package:atomic_notes/authentication/auth_services/session_guard.dart';
import 'package:atomic_notes/platform/browser_preview_gate.dart';
import 'package:atomic_notes/state/app_bloc_observer.dart';
import 'package:atomic_notes/state/app_blocs.dart';
import 'package:atomic_notes/page/endpage/about_us_page.dart';
import 'package:atomic_notes/page/endpage/bio_auth_page.dart';
import 'package:atomic_notes/page/endpage/cloud_sync_page.dart';
import 'package:atomic_notes/page/endpage/cloud_notes_page.dart';
import 'package:atomic_notes/page/endpage/danger_zone_page.dart';
import 'package:atomic_notes/page/endpage/encryption_page.dart';
import 'package:atomic_notes/page/endpage/energy_page.dart';
import 'package:atomic_notes/page/endpage/user_sessions_page.dart';
import 'package:atomic_notes/page/endpage/recycle_bin_page.dart';
import 'package:atomic_notes/page/endpage/vault_unlock_page.dart';
import 'package:atomic_notes/page/endpage/edit_profile_page.dart';
import 'package:atomic_notes/page/endpage/t_and_c_page.dart';
import 'package:atomic_notes/page/endpage/two_factor_gate_page.dart';
import 'package:atomic_notes/page/endpage/two_factor_page.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/page/endpage/lock_screen.dart';
import 'package:atomic_notes/page/logout_screen.dart';
import 'package:atomic_notes/page/main_page.dart';
import 'package:atomic_notes/page/endpage/notifications_page.dart';
import 'package:atomic_notes/page/settings_page.dart';
import 'package:atomic_notes/page/splash_screen.dart';
import 'package:atomic_notes/page/account_cache_recovery_page.dart';
import 'package:atomic_notes/theme/app_theme.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/intropages/onboarding_screen.dart';
import 'package:atomic_notes/utility/intropages/energy_intro_screen.dart';
import 'package:atomic_notes/utility/startup_sequence.dart';
import 'package:atomic_notes/utility/startup_trace.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // W1 compile proof only. Do not initialize native auth, secure storage,
  // Hive, vault state or repositories on browsers before their release gates.
  if (kIsWeb) {
    runApp(const BrowserPreviewGate());
    return;
  }
  Bloc.observer = const AppBlocObserver();
  // Opt-in phase timing (--dart-define=ATOMIC_STARTUP_TRACE=true, never in
  // release). Off, each step below runs exactly as written.
  final trace = StartupTrace.fromEnvironment();

  try {
    await runStartupSequence(const StartupServices(), trace);
  } catch (error) {
    trace.finish();
    // This used to be `exit(0)`: the app vanished on launch with no message,
    // indistinguishable from a crash and impossible to report.
    runApp(StartupFailedApp(error: error.toString()));
    return;
  }

  trace.finish();
  runApp(const MascotScope(child: MyApp()));
}

/// Shown when Supabase or Hive can't be initialised at all. There is no usable
/// app behind this point, so it just explains itself instead of disappearing.
class StartupFailedApp extends StatelessWidget {
  final String error;
  const StartupFailedApp({required this.error, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const MonoLabel('SYSTEM / STARTUP FAILED',
                      color: AppColors.error),
                  const SizedBox(height: AppSpace.sm),
                  const HairRule(color: AppColors.ink),
                  const SizedBox(height: AppSpace.lg),
                  const EditorialHeading(
                    "Atomic couldn't start",
                    style: AppType.headlineLg,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  const Text(
                    'Check your connection and reopen the app. If this keeps '
                    'happening, the details below will say why.',
                    style: AppType.bodyMd,
                  ),
                  const SizedBox(height: AppSpace.lg),
                  EditorialModule(
                    fill: AppColors.errorContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MonoLabel('TRACE',
                            color: AppColors.onErrorContainer),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          error,
                          style: AppType.labelMonoSm
                              .copyWith(color: AppColors.onErrorContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.appearance});

  /// Replaced in tests; the app uses the choice read at startup.
  final AppearanceController? appearance;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppearanceController get _appearance =>
      widget.appearance ?? AppearanceController.instance;

  @override
  void initState() {
    super.initState();
    // Start the central auth-state guard once, for the life of the app. It
    // owns the sign-out -> reset-to-login transition from anywhere.
    SessionGuard.attach();
  }

  @override
  void dispose() {
    SessionGuard.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only MaterialApp listens: a theme change must not rebuild the blocs.
    return AppearanceScope(
      controller: _appearance,
      child: AppBlocs(
        child: ListenableBuilder(
          listenable: _appearance,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AtomicTheme.dark,
            themeMode: _appearance.themeMode,
            // Shared with SessionGuard so a sign-out can reset the stack even when it
            // happens off-screen (a background token refresh failing).
            navigatorKey: SessionGuard.navigatorKey,
            initialRoute: '/splashpage',
            routes: {
              '/loginpage': (context) => const LoginPage(),
              '/homepage': (context) => const HomePage(),
              '/splashpage': (context) => const SplashPage(),
              '/account-cache-recovery': (context) =>
                  const AccountCacheRecoveryPage(),
              '/loggedout': (context) => const LoggedOutScreen(),
              '/mainpage': (context) => const MainPage(),
              '/settingspage': (context) => const SettingsPage(),
              '/mascot': (context) {
                final scope = MascotScope.maybeOf(context);
                if (scope == null) {
                  return const Scaffold(
                      body: Center(child: Text('Mascot settings unavailable')));
                }
                return MascotSettingsPage(
                    preferences: scope.preferences, resolver: scope.resolver);
              },
              '/onboardingscreen': (context) => const OnBoardingScreen(),
              '/energyintro': (context) => const EnergyIntroScreen(),
              '/appinfo': (context) => const AppInfo(),
              '/lockscreen': (context) => const LockScreen(),
              '/twofactor': (context) => const TwoFactorPage(),
              '/twofactorgate': (context) => const TwoFactorGatePage(),
              '/dangerzone': (context) => const DangerZonePage(),
              '/cloudnotes': (context) => const CloudNotesPage(),
              '/recyclebin': (context) => const RecycleBinPage(),
              '/cloudsyncpage': (context) => const CloudSyncPage(),
              '/biompage': (context) => const BiomPage(),
              '/encryptionpage': (context) => const EncryptionPage(),
              '/energypage': (context) => const EnergyPage(),
              '/usersessions': (context) => const UserSessionsPage(),
              '/notifications': (context) => const NotificationsPage(),
              '/vaultunlock': (context) => VaultUnlockPage(
                    // `arguments: true` means the splash sent the user here at
                    // launch, so unlocking continues into the app.
                    fromStartup: ModalRoute.of(context)?.settings.arguments == true,
                  ),
              '/tcpage': (context) => const TCPage(),
              '/editprofilepage': (context) => const EditProfilePage(),
            },
          ),
        ),
      ),
    );
  }
}
