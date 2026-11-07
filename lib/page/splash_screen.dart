// ignore_for_file: library_private_types_in_public_api, use_build_context_synchronously

import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/notification_service.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/security/two_factor.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/app_info.dart';
import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:atomic_notes/utility/component/atomic_splash_mark.dart';
import 'package:atomic_notes/utility/component/logo_container.dart';
import 'package:atomic_notes/utility/splash_route_resolver.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key}) : startup = const SplashStartupServices();

  @visibleForTesting
  const SplashPage.forTest({super.key, required this.startup});

  final SplashStartupServices startup;

  @override
  _SplashPageState createState() => _SplashPageState();
}

/// The existing account services, separated only to exercise startup ordering.
class SplashStartupServices {
  const SplashStartupServices();
  bool get isSignedIn => ApiClient.instance.isSignedIn;
  int get sessionRevision => ApiClient.instance.sessionRevision;
  bool get hasForeignPendingCache =>
      NotesRepository.instance.hasForeignPendingCache;
  bool get twoFactorArmed => TwoFactor.instance.isArmed;
  bool get vaultLocked => vault.isLocked;
  Vault get vault => Vault.instance;
  Future<void> initVault() => vault.initAfterStartup();

  /// A splash that leaves before its vault check must not hand main()'s
  /// result to a later one.
  void discardStartupVault() => vault.discardStartupHandoff();
  Future<void> startNotes() => NotesRepository.instance.start();
  Future<void> stopNotes() => NotesRepository.instance.stop();
  void clearNotesMemory() => NotesRepository.instance.clearMemory();
  Future<void> markOnboardingSeen(Box<bool> authBox) =>
      authBox.put('hasSeenOnboarding', true);

  void startAccountServices() {
    unawaited(EnergyService.instance.init());
    unawaited(NotificationService.instance.init());
  }
}

class _SplashPageState extends State<SplashPage> {
  late final _startup = widget.startup;
  bool _recoveringCache = false;

  bool _ownsSession(int revision) =>
      _startup.isSignedIn && _startup.sessionRevision == revision;

  bool _canContinue(int revision) {
    if (!mounted ||
        _recoveringCache ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    if (_ownsSession(revision)) return true;
    // A replacement session needs its own vault and account-cache checks.
    Navigator.pushReplacementNamed(
        context, _startup.isSignedIn ? '/splashpage' : '/loginpage');
    return false;
  }

  void _showCacheRecovery() {
    if (!mounted || _recoveringCache) return;
    _recoveringCache = true;
    Navigator.pushNamedAndRemoveUntil(
        context, '/account-cache-recovery', (_) => false);
  }

  Future<void> _startNotes(int revision) async {
    try {
      await _startup.startNotes();
    } on ForeignPendingCacheError {
      if (_ownsSession(revision)) _showCacheRecovery();
    } catch (_) {
      if (!mounted || _recoveringCache || !_ownsSession(revision)) return;
      Navigator.pushReplacementNamed(context, '/loginpage');
    }
  }

  @override
  void initState() {
    super.initState();
    _redirect();
  }

  @override
  void dispose() {
    _startup.discardStartupVault();
    super.dispose();
  }

  Future<void> _redirect() async {
    final revision = _startup.sessionRevision;
    try {
      // The auth box is read here rather than in a separate method racing
      // this one: the old code could reach the `isAuthOn` check before the
      // box-opening callback had assigned it.
      final authBox = await Hive.openBox<bool>('authBox');
      if (!_canContinue(revision)) return;
      final bool isAuthOn =
          authBox.get('isAuthOn', defaultValue: false) ?? false;
      final bool hasSeenOnboarding =
          authBox.get('hasSeenOnboarding', defaultValue: false) ?? false;

      if (_startup.hasForeignPendingCache) {
        await _startup.stopNotes();
        if (!_canContinue(revision)) return;
        _startup.clearNotesMemory();
        _showCacheRecovery();
        return;
      }

      // Re-read the vault for THIS account now that a session exists.
      //
      // main() also calls this, but main() runs before the user has signed in:
      // on a second device the account id is still null there, so the vault
      // reads as "not configured" and stays that way for the whole session.
      // That single missing refresh is why the same recovery phrase on a
      // second phone showed no notes: the unlock screen never appeared,
      // encrypted rows were skipped as unreadable, and new notes were written
      // in the clear. The splash runs on every launch AND after every login,
      // which makes it the one place this is always correct. On the first
      // launch splash it may reuse main()'s check once, when that check
      // confirmed a vault for this same session and nothing has changed since.
      await _startup.initVault();
      if (!_canContinue(revision)) return;
      if (_startup.hasForeignPendingCache) {
        _showCacheRecovery();
        return;
      }

      // Local-first means routing NEVER waits on the network. The cached
      // notes were already loaded from Hive in main(), so there is nothing
      // here worth blocking on — start() is deliberately not awaited.
      //
      // It used to be awaited, which meant that with no connection the app
      // sat on this screen until a socket gave up. An offline launch has to
      // be as fast as an online one.
      unawaited(_startNotes(revision));

      // Load Atomic Energy/Coins for this account and apply the daily grant.
      // Non-blocking, same as sync — routing never waits on it.
      // Pull the notification feed too; both services remain non-blocking.
      _startup.startAccountServices();
      if (!mounted || _recoveringCache) return;
      if (_startup.hasForeignPendingCache) {
        _showCacheRecovery();
        return;
      }

      // One resolver owns the gate order (device lock, two-factor, vault,
      // onboarding) so lock_screen and two_factor_gate_page, which continue
      // this same decision from further along, cannot drift from it.
      final route = const SplashRouteResolver().resolve(
        isSignedIn: true,
        isAuthOn: isAuthOn,
        twoFactorArmed: _startup.twoFactorArmed,
        vaultLocked: _startup.vaultLocked,
        hasSeenOnboarding: hasSeenOnboarding,
      );

      // Onboarding is keyed off its own persisted flag. It used to be keyed
      // off `NOTESLIST == null`, which is only written when the user saves
      // their first note — so anyone who hadn't written a note yet got the
      // 6-page tutorial on every single launch.
      if (route == SplashRoute.onboarding) {
        await _startup.markOnboardingSeen(authBox);
        if (!_canContinue(revision)) return;
      }

      Navigator.pushReplacementNamed(
        context,
        route.routeName,
        arguments: route == SplashRoute.vaultUnlock ? true : null,
      );
    } catch (error) {
      // Fall back to the login page rather than sitting on the splash forever.
      if (!_canContinue(revision)) return;
      Navigator.pushReplacementNamed(context, '/loginpage');
    }
  }

  // NOTE: deliberately no `_authBox.close()` here — see bio_auth_page.dart.
  // The splash screen is disposed on every launch, so closing the shared
  // 'authBox' here shut it down seconds into every session.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpace.screenMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Spacer(flex: 3),
              LogoContainer(showTagline: true, mark: AtomicSplashMark()),
              Spacer(flex: 4),
              // Boot status reads like a system readout rather than a
              // decorative spinner block.
              HairRule(color: AppColors.ink),
              SizedBox(height: AppSpace.md),
              Row(
                children: [
                  DevBehindYouMascot(size: 24, secondary: true),
                  SizedBox(width: AppSpace.md - 4),
                  Expanded(
                    child: MonoLabel('INITIALISING · CHECKING SESSION'),
                  ),
                  MonoLabel(AppInfoText.version, small: true),
                ],
              ),
              SizedBox(height: AppSpace.sm),
            ],
          ),
        ),
      ),
    );
  }
}
