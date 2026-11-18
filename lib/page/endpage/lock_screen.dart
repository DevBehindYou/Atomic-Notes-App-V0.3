// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:atomic_notes/security/two_factor.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/utility/splash_route_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// The device lock (screens spec, Lock screen): a fingerprint circle, the
/// title, the instruction and one Unlock button. It prompts on its own one
/// second after it opens; success continues the splash gate order.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, this.localAuth});

  /// The device authenticator. Null uses the platform's, as the app does;
  /// tests pass a fake.
  final LocalAuthentication? localAuth;

  static const String title = 'This device is locked';
  static const String instruction = 'Unlock with your fingerprint or device '
      'credential to open your notes.';
  static const String unlockLabel = 'Unlock';
  static const String busyLabel = 'Authenticating…';

  /// Shown instead of the platform's raw error text (CA18).
  static const String failedMessage =
      'That did not work. Try again, or use your phone PIN.';

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  late final LocalAuthentication auth;

  bool _mounted = true;
  bool _supportState = false;
  bool _isLoading = false;

  @override
  void initState() {
    auth = widget.localAuth ?? LocalAuthentication();
    auth.isDeviceSupported().then(
      (bool isSupported) {
        if (!mounted) return;
        setState(() {
          _supportState = isSupported;
        });
      },
    );
    super.initState();
    autoAuth();
  }

  @override
  void dispose() {
    _mounted = false;
    _isLoading = false;
    super.dispose();
  }

  autoAuth() async {
    await Future.delayed(const Duration(seconds: 1));
    _auth();
  }

  Future<void> _auth() async {
    if (!_mounted) return;

    setState(() {
      _isLoading = true;
    });
    try {
      bool authenticated = await auth.authenticate(
          localizedReason: "Privacy for AtomicNotes",
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ));

      if (!_mounted) return;
      if (authenticated) {
        // The device lock has passed, so continue the same gate order the
        // splash screen started: two-factor, then the vault, then the notes.
        // Onboarding never re-triggers here, only at the very first launch.
        final route = const SplashRouteResolver().resolve(
          isSignedIn: true,
          isAuthOn: false,
          twoFactorArmed: TwoFactor.instance.isArmed,
          vaultLocked: Vault.instance.isLocked,
          hasSeenOnboarding: true,
        );
        Navigator.pushReplacementNamed(
          context,
          route.routeName,
          arguments: route == SplashRoute.vaultUnlock ? true : null,
        );
      }
    } on PlatformException catch (e) {
      if (!_mounted) return;
      // The platform's text stays in debug logs only; people see plain copy.
      if (kDebugMode) debugPrint('LockScreen: $e');
      const AtomicSnackBar(
        text: LockScreen.failedMessage,
        millis: 4000,
        error: true,
      ).show(context);
    } finally {
      if (_mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: EntranceGroup(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: margin, vertical: AtomicSpace.x8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 2 * AtomicSpace.x8)
                      .clamp(0, double.infinity),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Entrance(
                          index: 0,
                          child: _LockBadge(supported: _supportState),
                        ),
                        const SizedBox(height: AtomicSpace.x6),
                        Entrance(
                          index: 1,
                          child: Semantics(
                            header: true,
                            child: Text(
                              LockScreen.title,
                              textAlign: TextAlign.center,
                              style: AtomicType.headlineLarge
                                  .copyWith(color: c.textPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(height: AtomicSpace.x3),
                        Entrance(
                          index: 2,
                          child: Text(
                            LockScreen.instruction,
                            textAlign: TextAlign.center,
                            style: AtomicType.bodyLarge
                                .copyWith(color: c.textSecondary),
                          ),
                        ),
                        const SizedBox(height: AtomicSpace.x8),
                        Entrance(
                          index: 3,
                          child: AtomicButton.primary(
                            key: const ValueKey('lock-unlock'),
                            label: _isLoading
                                ? LockScreen.busyLabel
                                : LockScreen.unlockLabel,
                            // While busy the button keeps its accent face
                            // with a spinner and ignores taps, as the old
                            // `_isLoading ? null : _auth` did.
                            busy: _isLoading,
                            onPressed: _auth,
                            size: AtomicButtonSize.large,
                            expand: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 96 dp accent circle. It shows a fingerprint once the device says it
/// can check one, and a lock until then or when it cannot. Decorative: the
/// title and the button carry the meaning.
class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.supported});

  final bool supported;

  static const double size = 96;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Center(
        child: Container(
          key: const ValueKey('lock-badge'),
          width: size,
          height: size,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: AtomicMotion.fade(context, AtomicMotion.standard),
            child: Icon(
              supported ? AtomicIcons.fingerprint : AtomicIcons.lock,
              key: ValueKey(supported),
              size: 44,
              color: c.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}
