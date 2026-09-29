// The gate order splash_screen, lock_screen and two_factor_gate_page all
// continue: device lock, then two-factor, then the vault, then onboarding.
// Pure data in, data out — no Hive, no singletons, no widget pump.

import 'package:atomic_notes/utility/splash_route_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = SplashRouteResolver();

  SplashRoute resolve({
    bool isSignedIn = true,
    bool isAuthOn = false,
    bool twoFactorArmed = false,
    bool vaultLocked = false,
    bool hasSeenOnboarding = true,
  }) =>
      resolver.resolve(
        isSignedIn: isSignedIn,
        isAuthOn: isAuthOn,
        twoFactorArmed: twoFactorArmed,
        vaultLocked: vaultLocked,
        hasSeenOnboarding: hasSeenOnboarding,
      );

  test('not signed in always goes to login, whatever else is set', () {
    expect(
      resolve(
        isSignedIn: false,
        isAuthOn: true,
        twoFactorArmed: true,
        vaultLocked: true,
        hasSeenOnboarding: false,
      ),
      SplashRoute.login,
    );
  });

  test('the device lock outranks two-factor, the vault and onboarding', () {
    expect(
      resolve(
        isAuthOn: true,
        twoFactorArmed: true,
        vaultLocked: true,
        hasSeenOnboarding: false,
      ),
      SplashRoute.lockScreen,
    );
  });

  test('two-factor outranks the vault and onboarding', () {
    expect(
      resolve(twoFactorArmed: true, vaultLocked: true, hasSeenOnboarding: false),
      SplashRoute.twoFactorGate,
    );
  });

  test('the vault outranks onboarding', () {
    expect(resolve(vaultLocked: true, hasSeenOnboarding: false),
        SplashRoute.vaultUnlock);
  });

  test('onboarding is offered once nothing else gates the user', () {
    expect(resolve(hasSeenOnboarding: false), SplashRoute.onboarding);
  });

  test('the notes screen is the end of every gate passing', () {
    expect(resolve(), SplashRoute.mainPage);
  });

  test('each route names the screen it pushes', () {
    expect(SplashRoute.login.routeName, '/loginpage');
    expect(SplashRoute.lockScreen.routeName, '/lockscreen');
    expect(SplashRoute.twoFactorGate.routeName, '/twofactorgate');
    expect(SplashRoute.vaultUnlock.routeName, '/vaultunlock');
    expect(SplashRoute.onboarding.routeName, '/onboardingscreen');
    expect(SplashRoute.mainPage.routeName, '/mainpage');
  });
}
