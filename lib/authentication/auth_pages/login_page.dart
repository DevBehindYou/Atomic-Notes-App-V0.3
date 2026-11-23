// ignore_for_file: library_private_types_in_public_api, use_build_context_synchronously

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/profile/guest_profile_store.dart';
import 'package:atomic_notes/profile/guest_workspace_page.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:atomic_notes/utility/component/login_button.dart';
import 'package:flutter/material.dart';

/// MIGRATION NOTE: this used to be an email/password sign-in and sign-up
/// pair (with a mode-switch tab, textfields, an email-verification detour to
/// signup_verify_page.dart, and a forgot-password detour to
/// reset_password_page.dart/reset_verify_page.dart) built on Supabase Auth.
/// The new backend only supports Google Sign-In (see the server's README —
/// that was the original brief's stated auth design, not a simplification
/// made here), so there is no password to forget and nothing to verify by
/// email. Those three pages were deleted along with their main.dart routes
/// once Google-only auth was confirmed — there was no live path to them left.
///
/// Layout (screens spec, Login): the brand mark, the display headline, the
/// existing subtitle, "Sign in with Google" in Google's own button style,
/// the optional Guest entry, and the terms line. There are no text fields,
/// so there is nothing to autofill.
class LoginPage extends StatefulWidget {
  const LoginPage({
    this.guestEntry = GuestFeature.enabled,
    this.signIn,
    super.key,
  });

  /// Offers "Continue without an account" (local-only Guest notes). Off in
  /// default builds; the Google-only start is unchanged.
  final bool guestEntry;

  /// The Google sign-in. Null uses `ApiClient.instance.signInWithGoogle`, as
  /// the app does; tests pass a fake.
  final Future<void> Function()? signIn;

  static const String title = 'Your notes, your Drive.';
  static const String subtitle = 'Sign in with Google. Notes sync to your own '
      'Google Drive — nothing is stored on our servers but sync metadata.';
  static const String googleLabel = 'Sign in with Google';
  static const String guestLabel = 'Continue without an account';
  static const String termsLine = 'By signing in you agree to the terms.';
  static const String termsLink = 'Read the terms';

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    // One sign-in per action, even for two taps inside one frame.
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await (widget.signIn ?? ApiClient.instance.signInWithGoogle)();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/splashpage');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'cancelled') return; // user dismissed the picker — not an error
      // Visible in `adb logcat -s flutter`; carries error codes only, never tokens.
      debugPrint('Sign-in failed: ${e.code} (HTTP ${e.statusCode})');
      AtomicSnackBar(text: _friendly(e), millis: 2500, error: true)
          .show(context);
    } catch (e) {
      if (!mounted) return;
      // A Google PlatformException (for example ApiException: 10 when the signing
      // certificate is not registered) or a network error ends up here.
      debugPrint('Sign-in failed unexpectedly: ${e.runtimeType}: $e');
      const AtomicSnackBar(
              text: 'Unknown error occurred!', millis: 2000, error: true)
          .show(context);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendly(ApiException e) {
    switch (e.code) {
      case 'no_server_auth_code':
        return "Couldn't complete Google sign-in. Please try again.";
      case 'code_exchange_failed':
        return 'Sign-in expired before it finished — please try again.';
      case 'refresh_token_required':
        return 'Google did not allow offline access. Sign in again and accept every permission.';
      case 'incomplete_token_response':
      case 'invalid_id_token':
        return "Google's answer could not be verified. Please try again.";
      case 'internal_error':
      case 'http_500':
      case 'http_502':
      case 'http_503':
        return 'The Atomic Notes server had a problem. Please try again shortly.';
      default:
        return 'Sign-in failed. Please try again.';
    }
  }

  void _openGuest() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          GuestWorkspacePage(notes: GuestStoreNotes(GuestProfileStore()))));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: EntranceGroup(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: margin, vertical: AtomicSpace.x12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Entrance(
                      index: 0,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Semantics(
                          label: 'Atomic Notes',
                          image: true,
                          child: ExcludeSemantics(
                            child: AtomicBrandMark(
                              key: const ValueKey('login-mark'),
                              size: 64,
                              onDark: dark,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x8),
                    Entrance(
                      index: 1,
                      child: Semantics(
                        header: true,
                        child: Text(
                          LoginPage.title,
                          style:
                              AtomicType.display.copyWith(color: c.textPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x3),
                    Entrance(
                      index: 2,
                      child: Text(
                        LoginPage.subtitle,
                        style: AtomicType.bodyLarge
                            .copyWith(color: c.textSecondary),
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x8),
                    Entrance(
                      index: 3,
                      child: LoginButton(
                        key: const ValueKey('login-google'),
                        isLoading: _isLoading,
                        signIn: _signInWithGoogle,
                        text: LoginPage.googleLabel,
                      ),
                    ),
                    if (widget.guestEntry) ...[
                      const SizedBox(height: AtomicSpace.x3),
                      Entrance(
                        index: 4,
                        child: AtomicButton.tonal(
                          key: const ValueKey('login-guest'),
                          label: LoginPage.guestLabel,
                          onPressed: _isLoading ? null : _openGuest,
                          expand: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: AtomicSpace.x8),
                    Entrance(index: 5, child: _TermsLine(colors: c)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "By signing in you agree to the terms." and the "Read the terms" link in
/// `infoText`, with a full 48 dp target.
class _TermsLine extends StatelessWidget {
  const _TermsLine({required this.colors});

  final AtomicColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LoginPage.termsLine,
          style: AtomicType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        AtomicPressable(
          key: const ValueKey('login-terms'),
          onTap: () => Navigator.pushNamed(context, '/tcpage'),
          semanticsLabel: LoginPage.termsLink,
          excludeSemantics: true,
          borderRadius: AtomicRadius.smallAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AtomicSpace.x3),
            child: Text(
              LoginPage.termsLink,
              style: AtomicType.labelLarge.copyWith(
                color: colors.infoText,
                decoration: TextDecoration.underline,
                decorationColor: colors.infoText,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
