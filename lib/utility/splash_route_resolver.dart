/// Where the app sends the user next, worked out from account and device-gate
/// state. Three screens make this same decision at different starting points
/// (the splash screen from scratch, the lock screen after a device-lock pass,
/// the two-factor gate after a code check), and used to each carry their own
/// copy of the ordering. One pure function now owns it, so the gate order —
/// device lock, then two-factor, then vault, then onboarding — is tested once
/// and cannot drift between the three call sites.
enum SplashRoute { login, lockScreen, twoFactorGate, vaultUnlock, onboarding, mainPage }

extension SplashRouteName on SplashRoute {
  /// The named route to push. [SplashRoute.vaultUnlock] always carries
  /// `arguments: true` (`VaultUnlockPage.fromStartup`) wherever it is reached
  /// from: skipping it still has to continue past the gate, not pop to a
  /// settings screen that was never opened.
  String get routeName => switch (this) {
        SplashRoute.login => '/loginpage',
        SplashRoute.lockScreen => '/lockscreen',
        SplashRoute.twoFactorGate => '/twofactorgate',
        SplashRoute.vaultUnlock => '/vaultunlock',
        SplashRoute.onboarding => '/onboardingscreen',
        SplashRoute.mainPage => '/mainpage',
      };
}

/// No I/O, no singletons: every input is a plain value the caller already
/// read, so this is tested as data in, data out.
class SplashRouteResolver {
  const SplashRouteResolver();

  SplashRoute resolve({
    required bool isSignedIn,
    required bool isAuthOn,
    required bool twoFactorArmed,
    required bool vaultLocked,
    required bool hasSeenOnboarding,
  }) {
    if (!isSignedIn) return SplashRoute.login;

    // The device lock takes priority over every other gate.
    if (isAuthOn) return SplashRoute.lockScreen;

    // Two-factor comes next; the vault gate below is only reached once it
    // is off or has been passed.
    if (twoFactorArmed) return SplashRoute.twoFactorGate;

    if (vaultLocked) return SplashRoute.vaultUnlock;

    if (!hasSeenOnboarding) return SplashRoute.onboarding;

    return SplashRoute.mainPage;
  }
}
