import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/security/two_factor.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/utility/component/two_factor_code_field.dart';
import 'package:atomic_notes/utility/splash_route_resolver.dart';
import 'package:flutter/material.dart';

/// The second step when Atomic opens (screens spec, Two-factor gate): the
/// 6-digit code from the authenticator app, or a recovery code. Shown after
/// the device lock and before the notes.
///
/// Every check belongs to the account and the attempt that started it. A
/// result that comes back after the page has gone, after a newer attempt,
/// or after the sign-in changed is dropped: it never opens the app.
class TwoFactorGatePage extends StatefulWidget {
  /// Only tests pass one; the app uses [TwoFactor.instance].
  final TwoFactor? twoFactor;

  /// Who the gate is checking for, compared by `==` before and after every
  /// await. Only tests pass one; the app uses the signed-in account and its
  /// session revision.
  final Object? Function()? identity;

  const TwoFactorGatePage({this.twoFactor, this.identity, super.key});

  static const String title = 'Enter your code';
  static const String codeHint =
      'Open your authenticator app and type the 6-digit code for Atomic Notes.';
  static const String recoveryHint =
      'Type one of the recovery codes you saved. Each works once.';
  static const String wrongCode =
      "That code didn't match. Wait for a fresh one and try again.";
  static const String wrongRecovery = "That recovery code didn't match.";
  static const String signInChanged =
      'Your sign-in changed. Enter a code for this account.';
  static const String verifyLabel = 'Verify';
  static const String useRecovery = 'Use a recovery code';
  static const String useAuthenticator = 'Use authenticator code';
  static const String unavailableTitle = 'Key unavailable';
  static const String unavailableBody =
      "This device can't read its two-factor key. That can happen after a "
      'restore from backup or a system reset.';
  static const String retryLabel = 'Try again';
  static const String turnOffLabel = 'Turn off on this device';
  static const String turnOffTitle = 'Turn off two-factor here?';
  static const String turnOffBody =
      'This device can no longer read its two-factor key, so no code can be '
      'checked. Turn two-factor off on this device? Your device lock and '
      'Google sign-in stay as they are. You can set it up again in Profile.';
  static const String turnOffConfirm = 'Turn off';
  static const String turnOffFailed =
      "Two-factor couldn't be turned off on this device. Try again.";

  static String lockedMessage(int seconds) =>
      'Too many wrong tries. Try again in $seconds s.';

  @override
  State<TwoFactorGatePage> createState() => _TwoFactorGatePageState();
}

class _TwoFactorGatePageState extends State<TwoFactorGatePage> {
  late final TwoFactor _tf = widget.twoFactor ?? TwoFactor.instance;
  late final Object? Function() _identity = widget.identity ??
      () => (
            ApiClient.instance.currentUserId,
            ApiClient.instance.sessionRevision
          );
  final TextEditingController _controller = TextEditingController();

  bool _probing = true;
  bool _unavailable = false;
  bool _recovery = false;
  bool _busy = false;

  /// A confirmed turn-off is waiting for the service.
  bool _resetting = false;
  bool _left = false;
  String? _error;

  /// Bumped by every probe, submit and mode switch. An await whose ticket is
  /// no longer current is stale.
  int _ticket = 0;

  Timer? _ticker;
  DateTime? _lockEnds;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void dispose() {
    _ticket++;
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final int ticket = ++_ticket;
    final Object? owner = _identity();
    setState(() {
      _probing = true;
      _error = null;
    });
    final bool readable = await _tf.hasVerificationData();
    if (!mounted || _left || ticket != _ticket) return;
    if (_identity() != owner) {
      // Read for the old account: read again for this one.
      unawaited(_probe());
      return;
    }
    setState(() {
      _probing = false;
      _unavailable = !readable;
    });
  }

  Future<void> _submit([String? typed]) async {
    if (_busy || _left || _lockLeft > 0) return;
    final String text = (typed ?? _controller.text).trim();
    if (text.isEmpty) return;

    final int ticket = ++_ticket;
    final Object? owner = _identity();
    final bool recovery = _recovery;
    setState(() {
      _busy = true;
      _error = null;
    });
    final TwoFactorCheck check = await _tf.check(text);
    if (!mounted || _left || ticket != _ticket) return;
    if (_identity() != owner) {
      // The sign-in changed while the code was checked: the result was for
      // the old account. Drop it and start again for this one.
      _controller.clear();
      setState(() => _busy = false);
      await _probe();
      if (mounted) setState(() => _error = TwoFactorGatePage.signInChanged);
      return;
    }

    switch (check.result) {
      case TwoFactorResult.ok:
        _enter();
      case TwoFactorResult.wrong:
        _controller.clear();
        setState(() {
          _busy = false;
          _error = recovery
              ? TwoFactorGatePage.wrongRecovery
              : TwoFactorGatePage.wrongCode;
        });
      case TwoFactorResult.locked:
        _controller.clear();
        setState(() => _busy = false);
        _startLock(check.retryAfter ?? const Duration(seconds: 30));
      case TwoFactorResult.unavailable:
        setState(() {
          _busy = false;
          _unavailable = true;
        });
    }
  }

  void _toggleMode() {
    if (_busy) return;
    _ticket++;
    setState(() {
      _recovery = !_recovery;
      _error = null;
      _controller.clear();
    });
  }

  void _startLock(Duration wait) {
    _lockEnds = DateTime.now().add(wait);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lockLeft <= 0) timer.cancel();
      setState(() {});
    });
    setState(() {});
  }

  /// Whole seconds left on a lock, or 0.
  int get _lockLeft {
    final DateTime? ends = _lockEnds;
    if (ends == null) return 0;
    final int ms = ends.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void _enter() {
    if (_left) return;
    _left = true;
    // The device lock and this code check have both passed; two-factor is
    // done either way, so continue the same gate order past it: the vault,
    // then the notes.
    final route = const SplashRouteResolver().resolve(
      isSignedIn: true,
      isAuthOn: false,
      twoFactorArmed: false,
      vaultLocked: Vault.instance.isLocked,
      hasSeenOnboarding: true,
    );
    Navigator.pushReplacementNamed(
      context,
      route.routeName,
      arguments: route == SplashRoute.vaultUnlock ? true : null,
    );
  }

  /// The sign-in changed while a turn-off was asked or running: whatever
  /// happened was for the old account. Unblock, read the key again for this
  /// account and say why.
  Future<void> _restartForNewAccount() async {
    setState(() {
      _busy = false;
      _resetting = false;
    });
    await _probe();
    if (mounted && !_left) {
      setState(() => _error = TwoFactorGatePage.signInChanged);
    }
  }

  /// Turning two-factor off is offered only while this device cannot read
  /// its key. The page stays blocked from the tap until the service has
  /// answered for the same account, and it opens the app only when the reset
  /// finished and the gate is no longer armed.
  Future<void> _turnOffHere() async {
    if (_busy || _left || !_unavailable) return;
    final int ticket = ++_ticket;
    final Object? owner = _identity();
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool? confirmed = await showAtomicDialog<bool>(
      context: context,
      title: TwoFactorGatePage.turnOffTitle,
      body: TwoFactorGatePage.turnOffBody,
      icon: AtomicIcons.shieldLock,
      destructive: true,
      actions: const [
        AtomicDialogAction(label: 'Cancel', result: false),
        AtomicDialogAction(
          label: TwoFactorGatePage.turnOffConfirm,
          result: true,
          variant: AtomicButtonVariant.danger,
        ),
      ],
    );
    if (!mounted || _left) return;
    if (_identity() != owner) {
      await _restartForNewAccount();
      return;
    }
    if (ticket != _ticket || confirmed != true) {
      setState(() => _busy = false);
      return;
    }

    // The dialog has closed; the page stays blocked until the reset answers.
    setState(() => _resetting = true);
    bool done;
    try {
      await _tf.resetOnThisDevice();
      done = true;
    } catch (_) {
      // Storage may have failed part-way: the key could be gone while the
      // gate is still armed. Say it did not finish and let the user retry.
      done = false;
    }
    if (!mounted || _left) return;
    if (_identity() != owner) {
      await _restartForNewAccount();
      return;
    }
    if (ticket != _ticket || !done || _tf.isArmed) {
      setState(() {
        _busy = false;
        _resetting = false;
        if (ticket == _ticket) _error = TwoFactorGatePage.turnOffFailed;
      });
      return;
    }
    _enter();
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
                        const Entrance(index: 0, child: _GateBadge()),
                        const SizedBox(height: AtomicSpace.x6),
                        Entrance(
                          index: 1,
                          child: Semantics(
                            header: true,
                            child: Text(
                              TwoFactorGatePage.title,
                              key: const ValueKey('tf-gate-title'),
                              style: AtomicType.headlineLarge
                                  .copyWith(color: c.textPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(height: AtomicSpace.x3),
                        if (_probing)
                          const Padding(
                            padding: EdgeInsets.only(top: AtomicSpace.x6),
                            child: Center(
                              child: ProgressRing(
                                key: ValueKey('tf-gate-probing'),
                                semanticsLabel: 'Checking this device',
                              ),
                            ),
                          )
                        else if (_unavailable)
                          ..._unavailableBody()
                        else
                          ..._entryBody(context),
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

  List<Widget> _entryBody(BuildContext context) {
    final c = context.colors;
    final int locked = _lockLeft;
    return [
      Entrance(
        index: 2,
        child: Text(
          _recovery
              ? TwoFactorGatePage.recoveryHint
              : TwoFactorGatePage.codeHint,
          style: AtomicType.bodyLarge.copyWith(color: c.textSecondary),
        ),
      ),
      const SizedBox(height: AtomicSpace.x6),
      Entrance(
        index: 3,
        child: TwoFactorCodeField(
          key: ValueKey(_recovery),
          controller: _controller,
          recovery: _recovery,
          enabled: !_busy && locked == 0,
          autofocus: true,
          errorText: locked > 0 ? null : _error,
          onCompleted: _submit,
          onSubmitted: _submit,
        ),
      ),
      if (locked > 0) ...[
        const SizedBox(height: AtomicSpace.x4),
        AtomicBanner(
          key: const ValueKey('tf-gate-locked'),
          tone: BannerTone.danger,
          icon: AtomicIcons.clock,
          title: TwoFactorGatePage.lockedMessage(locked),
        ),
      ],
      const SizedBox(height: AtomicSpace.x6),
      Entrance(
        index: 4,
        child: AtomicButton.primary(
          key: const ValueKey('tf-gate-verify'),
          label: TwoFactorGatePage.verifyLabel,
          busy: _busy,
          onPressed: locked > 0 ? null : _submit,
          size: AtomicButtonSize.large,
          expand: true,
        ),
      ),
      const SizedBox(height: AtomicSpace.x2),
      Entrance(
        index: 5,
        child: Center(
          child: AtomicButton.text(
            key: const ValueKey('tf-gate-toggle'),
            label: _recovery
                ? TwoFactorGatePage.useAuthenticator
                : TwoFactorGatePage.useRecovery,
            onPressed: _busy ? null : _toggleMode,
          ),
        ),
      ),
    ];
  }

  List<Widget> _unavailableBody() {
    return [
      const SizedBox(height: AtomicSpace.x3),
      const Entrance(
        index: 2,
        child: AtomicBanner(
          key: ValueKey('tf-gate-unavailable'),
          tone: BannerTone.danger,
          icon: AtomicIcons.key,
          title: TwoFactorGatePage.unavailableTitle,
          body: TwoFactorGatePage.unavailableBody,
        ),
      ),
      if (_error case final String error) ...[
        const SizedBox(height: AtomicSpace.x4),
        Semantics(
          liveRegion: true,
          child: Text(
            error,
            key: const ValueKey('tf-gate-unavailable-error'),
            style: AtomicType.bodyMedium
                .copyWith(color: context.colors.dangerText),
          ),
        ),
      ],
      const SizedBox(height: AtomicSpace.x6),
      Entrance(
        index: 3,
        child: AtomicButton.primary(
          key: const ValueKey('tf-gate-retry'),
          label: TwoFactorGatePage.retryLabel,
          onPressed: _busy ? null : _probe,
          size: AtomicButtonSize.large,
          expand: true,
        ),
      ),
      const SizedBox(height: AtomicSpace.x3),
      Entrance(
        index: 4,
        child: AtomicButton.tonal(
          key: const ValueKey('tf-gate-turn-off'),
          label: TwoFactorGatePage.turnOffLabel,
          busy: _resetting,
          onPressed: _busy ? null : _turnOffHere,
          size: AtomicButtonSize.large,
          expand: true,
        ),
      ),
    ];
  }
}

/// A 72 dp accent circle with a shield. Decorative: the title carries the
/// meaning.
class _GateBadge extends StatelessWidget {
  const _GateBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          key: const ValueKey('tf-gate-badge'),
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(AtomicIcons.shieldLock, size: 36, color: c.onAccent),
        ),
      ),
    );
  }
}
