import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:flutter/material.dart';

/// Shows no account identifiers or note contents. Signing out here preserves
/// the disk cache; SessionGuard performs the normal runtime teardown.
///
/// Layout (screens spec, Account cache recovery): the title, the existing
/// explanation, an attention banner with the storage warning, one primary
/// action whose label shows the progress, and a danger banner under it when
/// returning to sign-in fails.
class AccountCacheRecoveryPage extends StatefulWidget {
  const AccountCacheRecoveryPage({super.key, this.signOut});
  final Future<void> Function()? signOut;

  static const String title = 'Finish syncing your previous account';
  static const String explanation =
      'This device still has unfinished changes or local-only notes from another '
      'account. Those notes are preserved and hidden from this account. '
      'Sign back into the previous account. Unlock the vault if needed, '
      'use Upload all in Cloud Notes for local-only notes, and finish syncing before switching.';
  static const String warningTitle =
      'Do not uninstall the app or clear its storage.';
  static const String warningBody =
      'If the vault is enabled, you may need your recovery phrase after signing in.';
  static const String failedTitle = 'Could not return to sign-in.';
  static const String failedBody = 'Your stored notes are unchanged. Try again.';
  static const String signInLabel = 'Sign in to previous account';
  static const String busyLabel = 'Returning to sign-in…';

  @override
  State<AccountCacheRecoveryPage> createState() =>
      _AccountCacheRecoveryPageState();
}

class _AccountCacheRecoveryPageState extends State<AccountCacheRecoveryPage> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _switchAccount() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await (widget.signOut ?? ApiClient.instance.signOut)();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/loginpage', (_) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: c.canvas,
        body: SafeArea(
          child: EntranceGroup(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                    horizontal: margin, vertical: AtomicSpace.x8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Entrance(
                        index: 0,
                        child: Semantics(
                          header: true,
                          child: Text(
                            AccountCacheRecoveryPage.title,
                            style: AtomicType.headlineLarge
                                .copyWith(color: c.textPrimary),
                          ),
                        ),
                      ),
                      const SizedBox(height: AtomicSpace.x4),
                      Entrance(
                        index: 1,
                        child: Text(
                          AccountCacheRecoveryPage.explanation,
                          style: AtomicType.bodyLarge
                              .copyWith(color: c.textSecondary),
                        ),
                      ),
                      const SizedBox(height: AtomicSpace.x6),
                      const Entrance(
                        index: 2,
                        child: AtomicBanner(
                          key: ValueKey('recovery-warning'),
                          tone: BannerTone.attention,
                          icon: AtomicIcons.alertTriangle,
                          title: AccountCacheRecoveryPage.warningTitle,
                          body: AccountCacheRecoveryPage.warningBody,
                        ),
                      ),
                      const SizedBox(height: AtomicSpace.x6),
                      Entrance(
                        index: 3,
                        child: AtomicButton.primary(
                          key: const ValueKey('recovery-sign-in'),
                          // The label is the progress text, so it stays
                          // readable; the button ignores taps while busy.
                          label: _busy
                              ? AccountCacheRecoveryPage.busyLabel
                              : AccountCacheRecoveryPage.signInLabel,
                          onPressed: _busy ? null : _switchAccount,
                          size: AtomicButtonSize.large,
                          expand: true,
                        ),
                      ),
                      // Under the action that failed, so the action never moves.
                      Semantics(
                        liveRegion: true,
                        child: AnimatedSize(
                          duration:
                              AtomicMotion.move(context, AtomicMotion.standard),
                          curve: AtomicMotion.standardCurve,
                          alignment: Alignment.topCenter,
                          child: _failed
                              ? const Padding(
                                  padding:
                                      EdgeInsets.only(top: AtomicSpace.x4),
                                  child: AtomicBanner(
                                    key: ValueKey('recovery-failed'),
                                    tone: BannerTone.danger,
                                    icon: AtomicIcons.alertCircle,
                                    title: AccountCacheRecoveryPage.failedTitle,
                                    body: AccountCacheRecoveryPage.failedBody,
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
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
    );
  }
}
