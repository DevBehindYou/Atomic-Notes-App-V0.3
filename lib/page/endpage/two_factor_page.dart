import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/security/two_factor.dart';
import 'package:atomic_notes/state/two_factor/two_factor_armed_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/chips/status_chip.dart';
import 'package:atomic_notes/ui/controls/atomic_checkbox.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/utility/component/two_factor_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum _Stage { overview, setup, codes }

/// Bookkeeping shared by every [TwoFactorPage] on one [TwoFactor]. The
/// service holds a single pending key and stores a confirm before it returns
/// the recovery codes, so the pages have to agree on who owns that key and
/// where codes go when their page has gone.
class _SetupLedger {
  /// The page state whose Begin made the service's pending key. Only it may
  /// confirm or discard that key.
  Object? holder;

  /// Set while a confirm is being stored. A new setup waits for it: the
  /// service clears its pending key when that confirm returns.
  Future<void>? storing;

  /// Codes from a confirm that was stored after its page had gone, kept for
  /// the account that started it and shown to no one else.
  List<String>? unshown;
  Object? unshownOwner;
}

final Expando<_SetupLedger> _ledgers = Expando('two-factor setup ledger');

/// Turn two-factor on or off, and manage its recovery codes (screens spec,
/// Two-factor setup).
///
/// A setup belongs to the account signed in at Begin. Confirm runs only while
/// that account is still signed in and this page still holds the setup key;
/// otherwise the setup is stopped before anything is checked or stored. A
/// confirm the service has already stored is never left without its codes:
/// if its page has gone they are kept for the same account and shown when it
/// opens this screen again. If the sign-in changed, they are shown to no one;
/// the account that turned it on still opens with its authenticator and can
/// make new codes. Code prompts check the account the same way before they
/// send anything.
class TwoFactorPage extends StatefulWidget {
  /// Only tests pass one; the app uses [TwoFactor.instance].
  final TwoFactor? twoFactor;

  /// Who the page is working for, compared by `==` before and after every
  /// await. Only tests pass one; the app uses the signed-in account and its
  /// session revision.
  final Object? Function()? identity;

  const TwoFactorPage({this.twoFactor, this.identity, super.key});

  static const String title = 'Two-factor';
  static const String offChip = 'Off';
  static const String onChip = 'On';
  static const String offHeading = 'A second step to open Atomic';
  static const String offBody =
      'After your device lock, Atomic asks for a 6-digit code from an '
      'authenticator app. It works with Google Authenticator, Authy, Aegis, '
      '1Password and any app that reads a QR code for time-based codes.';
  static const String setUpLabel = 'Set up two-factor';
  static const String goodToKnow = 'Good to know';
  static const String onHeading = 'Two-factor is on';
  static const String onBody =
      'Atomic asks for a code from your authenticator app each time it opens.';
  static const String codesLeftLabel = 'Recovery codes left';
  static const String newCodesLabel = 'New recovery codes';
  static const String turnOffLabel = 'Turn off two-factor';
  static const String step1Title = 'Add to your authenticator app';
  static const String step1Body =
      'In your authenticator app, add a new account. Scan this code with '
      'another device, or choose "enter a setup key" and type the key below.';
  static const String setupKeyLabel = 'Setup key';
  static const String copyKeyLabel = 'Copy key';
  static const String step2Title = 'Confirm';
  static const String step2Body =
      'Type the 6-digit code your app now shows for Atomic Notes.';
  static const String verifyLabel = 'Verify and turn on';
  static const String cancelLabel = 'Cancel';
  static const String needSixDigits = 'Type the 6-digit code from your app.';
  static const String wrongCode = "That code didn't match. Check that your "
      'app shows Atomic Notes and try the next code.';
  static const String codesTitle = 'Save these now';
  static const String shownOnce = 'Shown once';
  static const String codesBody =
      'If you lose your authenticator, each code opens Atomic once. They are '
      'not stored in a readable form, so this is the only time you will see '
      'them.';
  static const String copyAllLabel = 'Copy all codes';
  static const String savedLabel = 'I saved these codes somewhere safe';
  static const String doneLabel = 'Done';
  static const String signInChanged =
      'Your sign-in changed, so that step was stopped. Nothing was shown for '
      'the new account.';
  static const String setupReplaced =
      'That setup was started again on another screen, so this one was '
      'stopped. Start again to get a new key.';
  static const String notTurnedOn =
      "Two-factor wasn't turned on. Check the code and try again.";

  @override
  State<TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends State<TwoFactorPage> {
  late final TwoFactor _tf = widget.twoFactor ?? TwoFactor.instance;
  late final Object? Function() _identity = widget.identity ??
      () => (
            ApiClient.instance.currentUserId,
            ApiClient.instance.sessionRevision
          );
  final TextEditingController _code = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  _Stage _stage = _Stage.overview;
  TwoFactorSetup? _setup;
  List<String> _codes = const [];
  Object? _codesOwner;
  StreamSubscription<void>? _sessionEnded;
  bool _saved = false;
  bool _busy = false;
  String? _error;
  String? _notice;
  int? _codesLeft;

  late final _SetupLedger _ledger = _ledgers[_tf] ??= _SetupLedger();

  /// The account signed in when this setup began. Confirm runs only for it.
  Object? _setupOwner;

  /// A confirm started by an earlier page is still being stored.
  bool _earlier = false;

  /// Bumped by every begin and cancel: a confirm from an older setup
  /// attempt is stale.
  int _attempt = 0;

  /// Bumped by every count read: an older read is stale.
  int _countRead = 0;

  @override
  void initState() {
    super.initState();
    if (widget.identity == null) {
      _sessionEnded = ApiClient.instance.onSessionEnded.listen((_) {
        if (mounted && _sensitiveStageRetired) _stopForSignInChange();
      });
    }
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
    final Future<void>? storing = _ledger.storing;
    if (storing != null) {
      _earlier = true;
      storing.whenComplete(() {
        if (!mounted) return;
        setState(() {
          _earlier = false;
          _takeUnshown();
        });
        _refreshCount();
      });
    } else {
      _takeUnshown();
    }
    _refreshCount();
  }

  @override
  void dispose() {
    // Leaving mid-setup discards the key, if it is still this page's: a
    // confirm already being stored carries on and keeps its codes for the
    // account that started it.
    unawaited(_sessionEnded?.cancel());
    _release();
    _attempt++;
    _countRead++;
    _code.dispose();
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  Future<void> _refreshCount() async {
    final int read = ++_countRead;
    final Object? owner = _identity();
    final int? left = await _tf.recoveryCodesLeft();
    if (!mounted || read != _countRead || _identity() != owner) return;
    setState(() => _codesLeft = left);
  }

  /// A new stage starts at the top, where its title and any notice are.
  void _toTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _say(String text) {
    AtomicSnackBar(text: text, millis: 2500).show(context);
  }

  /// Codes a gone page stored for this account are shown here; for any other
  /// account they are dropped, never shown. Called from initState or inside
  /// setState.
  void _takeUnshown() {
    final List<String>? codes = _ledger.unshown;
    if (codes == null) return;
    final Object? owner = _ledger.unshownOwner;
    _ledger
      ..unshown = null
      ..unshownOwner = null;
    if (_identity() != owner) return;
    _codes = codes;
    _codesOwner = owner;
    _saved = false;
    _notice = null;
    _stage = _Stage.codes;
  }

  /// Discards the service's pending key if this page made it.
  void _release() {
    if (!identical(_ledger.holder, this)) return;
    _ledger.holder = null;
    _tf.cancelSetup();
  }

  void _begin() {
    if (_busy || _earlier || _ledger.storing != null) return;
    _attempt++;
    _ledger.holder = this;
    _setupOwner = _identity();
    setState(() {
      _setup = _tf.beginSetup();
      _stage = _Stage.setup;
      _error = null;
      _notice = null;
      _code.clear();
    });
    _toTop();
  }

  void _cancelSetup() {
    if (_busy) return;
    _attempt++;
    _release();
    setState(() {
      _setup = null;
      _stage = _Stage.overview;
      _error = null;
      _code.clear();
    });
    _toTop();
  }

  Future<void> _confirm([String? typed]) async {
    if (_busy || _stage != _Stage.setup) return;
    final String text = (typed ?? _code.text).trim();
    if (text.length != 6) {
      setState(() => _error = TwoFactorPage.needSixDigits);
      return;
    }
    final Object? owner = _identity();
    // The key was made for the account signed in at Begin; the service
    // stores it for whoever is signed in when confirm starts. Nothing is
    // sent unless they are the same and the key is still this page's.
    if (owner != _setupOwner) {
      _stopForSignInChange();
      return;
    }
    if (!identical(_ledger.holder, this)) {
      _stopSetup(TwoFactorPage.setupReplaced);
      return;
    }
    final int attempt = _attempt;
    setState(() {
      _busy = true;
      _error = null;
    });
    final done = Completer<void>();
    _ledger.storing = done.future;
    List<String>? codes;
    bool failed = false;
    try {
      codes = await _tf.confirmSetup(text);
    } catch (_) {
      failed = true;
    }
    final bool sameOwner = _identity() == owner;
    final bool here = mounted && attempt == _attempt;
    if (codes != null) {
      // Stored and on: the service has dropped its pending key.
      if (identical(_ledger.holder, this)) _ledger.holder = null;
      if (!here && sameOwner) {
        _ledger
          ..unshown = codes
          ..unshownOwner = owner;
      }
    }
    if (identical(_ledger.storing, done.future)) _ledger.storing = null;
    done.complete();
    if (!here) return;
    if (!sameOwner) {
      // The result, and any codes in it, belong to the old account.
      _stopForSignInChange();
      return;
    }
    if (failed) {
      // Nothing was armed, or the keystore refused it part way: the same
      // key can be confirmed again.
      _code.clear();
      setState(() {
        _busy = false;
        _error = TwoFactorPage.notTurnedOn;
      });
      return;
    }
    if (codes == null) {
      _code.clear();
      setState(() {
        _busy = false;
        _error = TwoFactorPage.wrongCode;
      });
      return;
    }
    final List<String> shown = codes;
    _attempt++;
    setState(() {
      _busy = false;
      _codes = shown;
      _codesOwner = owner;
      _saved = false;
      _stage = _Stage.codes;
      _setup = null;
    });
    _code.clear();
    _toTop();
    _refreshCount();
  }

  void _stopForSignInChange() => _stopSetup(TwoFactorPage.signInChanged);

  void _stopSetup(String notice) {
    _attempt++;
    _release();
    _code.clear();
    setState(() {
      _busy = false;
      _setup = null;
      _codes = const [];
      _codesOwner = null;
      _saved = false;
      _codesLeft = null;
      _error = null;
      _stage = _Stage.overview;
      _notice = notice;
    });
    _toTop();
    _refreshCount();
  }

  bool get _sensitiveStageRetired => switch (_stage) {
        _Stage.setup => _identity() != _setupOwner,
        _Stage.codes => _identity() != _codesOwner,
        _Stage.overview => false,
      };

  Future<void> _copy(String text, String done, Object? owner) async {
    if (!mounted) return;
    if (_identity() != owner) {
      if (_sensitiveStageRetired) _stopForSignInChange();
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted || _identity() != owner) return;
    _say(done);
  }

  Future<TwoFactorCheck?> _prompt({
    required String title,
    required String body,
    required String confirmLabel,
    required Future<TwoFactorCheck> Function(String) submit,
    bool danger = false,
  }) {
    // The service checks the code, then reads the signed-in account again
    // to change it, so the prompt sends nothing once the account that
    // opened it is no longer signed in.
    final Object? owner = _identity();
    return showAtomicDialog<TwoFactorCheck>(
      context: context,
      title: title,
      body: body,
      icon: danger ? AtomicIcons.shieldLock : AtomicIcons.key,
      destructive: danger,
      barrierDismissible: false,
      content: _CodePrompt(
        confirmLabel: confirmLabel,
        danger: danger,
        submit: (code) =>
            _identity() == owner ? submit(code) : Future.value(null),
      ),
      actions: const [],
    );
  }

  Future<void> _newCodes() async {
    if (_busy) return;
    final Object? owner = _identity();
    final TwoFactorCheck? result = await _prompt(
      title: 'New recovery codes',
      body: 'Type a code from your authenticator app. The old recovery codes '
          'stop working.',
      confirmLabel: 'Make new codes',
      submit: _tf.regenerateRecoveryCodes,
    );
    if (!mounted) return;
    if (_identity() != owner) {
      _stopForSignInChange();
      return;
    }
    if (result == null || !result.ok || result.codes == null) return;
    setState(() {
      _codes = result.codes!;
      _codesOwner = owner;
      _saved = false;
      _stage = _Stage.codes;
      _notice = null;
    });
    _toTop();
    _refreshCount();
  }

  Future<void> _turnOff() async {
    if (_busy) return;
    final Object? owner = _identity();
    final TwoFactorCheck? result = await _prompt(
      title: 'Turn off two-factor',
      body: 'Type a code from your authenticator app, or a recovery code, to '
          'turn it off.',
      confirmLabel: 'Turn off',
      danger: true,
      submit: _tf.disable,
    );
    if (!mounted) return;
    if (_identity() != owner) {
      _stopForSignInChange();
      return;
    }
    if (result == null || !result.ok) return;
    setState(() => _codesLeft = null);
    _say('Two-factor is off');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final retired = _sensitiveStageRetired;
    if (retired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sensitiveStageRetired) _stopForSignInChange();
      });
    }
    final displayedStage = retired ? _Stage.overview : _stage;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return BlocProvider(
      create: (_) => TwoFactorArmedCubit(source: _tf),
      // No leaving while a confirm is being stored.
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          backgroundColor: c.canvas,
          body: SafeArea(
            bottom: false,
            child: EntranceGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _titleAway,
                    builder: (context, away, _) => AtomicPageHeader(
                      title: TwoFactorPage.title,
                      showTitle: away,
                    ),
                  ),
                  Expanded(
                    // A plain scroll view, not a lazy list: the stages are
                    // short, and the whole stage is always built.
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(
                          margin,
                          0,
                          margin,
                          AtomicSpace.x8 +
                              MediaQuery.paddingOf(context).bottom),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Entrance(
                              index: 0, child: PageTitle(TwoFactorPage.title)),
                          const SizedBox(height: AtomicSpace.x4),
                          if (_notice != null) ...[
                            AtomicBanner(
                              key: const ValueKey('tf-setup-notice'),
                              tone: BannerTone.attention,
                              icon: AtomicIcons.alertTriangle,
                              title: _notice!,
                            ),
                            const SizedBox(height: AtomicSpace.x4),
                          ],
                          Entrance(
                            index: 1,
                            child: AnimatedSwitcher(
                              duration: AtomicMotion.fade(
                                  context, AtomicMotion.standard),
                              switchInCurve: AtomicMotion.standardCurve,
                              // The new stage fades in; the old one leaves at
                              // once, so a stage's key or codes are never on
                              // screen, or read out, beside the next stage.
                              layoutBuilder: (current, previous) =>
                                  current ?? const SizedBox.shrink(),
                              child: KeyedSubtree(
                                key: ValueKey(displayedStage),
                                child: switch (displayedStage) {
                                  _Stage.setup => _setupView(),
                                  _Stage.codes => _codesView(),
                                  _Stage.overview =>
                                    BlocBuilder<TwoFactorArmedCubit, bool>(
                                      builder: (context, armed) =>
                                          armed ? _armedView() : _offView(),
                                    ),
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
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

  // ---- off ----------------------------------------------------------------

  Widget _offView() {
    final c = context.colors;
    return Column(
      key: const ValueKey('tf-setup-off'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AtomicCard(
          padding: const EdgeInsets.all(AtomicSpace.heroPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconCircle(
                      icon: AtomicIcons.shieldLock,
                      fill: c.surfaceInset,
                      color: c.textPrimary),
                  const Spacer(),
                  const StatusChip(TwoFactorPage.offChip,
                      key: ValueKey('tf-setup-status')),
                ],
              ),
              const SizedBox(height: AtomicSpace.x4),
              Semantics(
                header: true,
                child: Text(TwoFactorPage.offHeading,
                    style:
                        AtomicType.titleLarge.copyWith(color: c.textPrimary)),
              ),
              const SizedBox(height: AtomicSpace.x2),
              Text(TwoFactorPage.offBody,
                  style:
                      AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
            ],
          ),
        ),
        // The way in comes first: below the fold it would be easy to miss.
        const SizedBox(height: AtomicSpace.x6),
        AtomicButton.primary(
          key: const ValueKey('tf-setup-begin'),
          label: TwoFactorPage.setUpLabel,
          icon: AtomicIcons.shieldLock,
          busy: _earlier,
          onPressed: _earlier ? null : _begin,
          size: AtomicButtonSize.large,
          expand: true,
        ),
        const SizedBox(height: AtomicSpace.sectionGap),
        _groupLabel(TwoFactorPage.goodToKnow),
        AtomicCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bullet('It protects this device. The key is kept in its secure '
                  'storage and does not move to other devices.'),
              _bullet('You get ${TwoFactor.recoveryCodeCount} recovery codes. '
                  'Keep them somewhere safe: they are your way in if you lose '
                  'the authenticator.'),
              _bullet(
                  'Signing in with Google is protected by your Google '
                  "account's own two-step verification.",
                  last: true),
            ],
          ),
        ),
      ],
    );
  }

  // ---- on -----------------------------------------------------------------

  Widget _armedView() {
    final c = context.colors;
    final int? left = _codesLeft;
    return Column(
      key: const ValueKey('tf-setup-on'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AtomicCard(
          padding: const EdgeInsets.all(AtomicSpace.heroPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconCircle(
                      icon: AtomicIcons.shieldCheck,
                      fill: c.accent,
                      color: c.onAccent),
                  const Spacer(),
                  const StatusChip(TwoFactorPage.onChip,
                      key: ValueKey('tf-setup-status'),
                      tone: StatusTone.accent),
                ],
              ),
              const SizedBox(height: AtomicSpace.x4),
              Semantics(
                header: true,
                child: Text(TwoFactorPage.onHeading,
                    style:
                        AtomicType.titleLarge.copyWith(color: c.textPrimary)),
              ),
              const SizedBox(height: AtomicSpace.x2),
              Text(TwoFactorPage.onBody,
                  style:
                      AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
              const SizedBox(height: AtomicSpace.x4),
              MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(TwoFactorPage.codesLeftLabel,
                          style: AtomicType.bodyMedium
                              .copyWith(color: c.textSecondary)),
                    ),
                    Text(
                      left == null ? 'â€“' : '$left',
                      key: const ValueKey('tf-setup-codes-left'),
                      style:
                          AtomicType.titleLarge.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (left != null && left <= 2) ...[
          const SizedBox(height: AtomicSpace.x4),
          AtomicBanner(
            key: const ValueKey('tf-setup-low-codes'),
            tone: left == 0 ? BannerTone.danger : BannerTone.attention,
            icon: AtomicIcons.alertTriangle,
            title: left == 0
                ? 'You have no recovery codes left. Make new ones so you are '
                    'not locked out if you lose your authenticator.'
                : 'Only $left recovery ${left == 1 ? 'code is' : 'codes are'} '
                    'left. Consider making new ones.',
          ),
        ],
        const SizedBox(height: AtomicSpace.x6),
        AtomicButton.tonal(
          key: const ValueKey('tf-setup-new-codes'),
          label: TwoFactorPage.newCodesLabel,
          icon: AtomicIcons.key,
          onPressed: _newCodes,
          size: AtomicButtonSize.large,
          expand: true,
        ),
        const SizedBox(height: AtomicSpace.x3),
        AtomicButton.danger(
          key: const ValueKey('tf-setup-turn-off'),
          label: TwoFactorPage.turnOffLabel,
          onPressed: _turnOff,
          size: AtomicButtonSize.large,
          expand: true,
        ),
      ],
    );
  }

  // ---- setup --------------------------------------------------------------

  Widget _setupView() {
    final c = context.colors;
    final TwoFactorSetup setup = _setup!;
    final owner = _setupOwner;
    return Column(
      key: const ValueKey('tf-setup-steps'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AtomicCard(
          key: const ValueKey('tf-setup-step-1'),
          padding: const EdgeInsets.all(AtomicSpace.heroPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stepHeading(1, TwoFactorPage.step1Title),
              const SizedBox(height: AtomicSpace.x2),
              Text(TwoFactorPage.step1Body,
                  style:
                      AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
              const SizedBox(height: AtomicSpace.x4),
              Center(child: _QrCard(data: setup.uri)),
              const SizedBox(height: AtomicSpace.x4),
              Container(
                padding: const EdgeInsets.all(AtomicSpace.x4),
                decoration: BoxDecoration(
                    color: c.surfaceInset,
                    borderRadius: AtomicRadius.mediumAll),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(TwoFactorPage.setupKeyLabel,
                        style: AtomicType.bodySmall
                            .copyWith(color: c.textSecondary)),
                    const SizedBox(height: AtomicSpace.x1),
                    SelectableText(
                      _grouped(setup.secret),
                      key: const ValueKey('tf-setup-key'),
                      style: AtomicType.mono
                          .copyWith(letterSpacing: 1.2, color: c.textPrimary),
                    ),
                    const SizedBox(height: AtomicSpace.x3),
                    AtomicButton.tonal(
                      key: const ValueKey('tf-setup-copy-key'),
                      label: TwoFactorPage.copyKeyLabel,
                      icon: AtomicIcons.copy,
                      onCard: true,
                      size: AtomicButtonSize.compact,
                      onPressed: () {
                        if (_stage != _Stage.setup || !identical(_setup, setup))
                          return;
                        _copy(setup.secret, 'Setup key copied', owner);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AtomicSpace.x4),
        AtomicCard(
          key: const ValueKey('tf-setup-step-2'),
          padding: const EdgeInsets.all(AtomicSpace.heroPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stepHeading(2, TwoFactorPage.step2Title),
              const SizedBox(height: AtomicSpace.x2),
              Text(TwoFactorPage.step2Body,
                  style:
                      AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
              const SizedBox(height: AtomicSpace.x4),
              TwoFactorCodeField(
                controller: _code,
                enabled: !_busy,
                errorText: _error,
                onCompleted: _confirm,
                onSubmitted: _confirm,
              ),
            ],
          ),
        ),
        const SizedBox(height: AtomicSpace.x6),
        AtomicButton.primary(
          key: const ValueKey('tf-setup-verify'),
          label: TwoFactorPage.verifyLabel,
          busy: _busy,
          onPressed: _confirm,
          size: AtomicButtonSize.large,
          expand: true,
        ),
        const SizedBox(height: AtomicSpace.x2),
        Center(
          child: AtomicButton.text(
            key: const ValueKey('tf-setup-cancel'),
            label: TwoFactorPage.cancelLabel,
            onPressed: _busy ? null : _cancelSetup,
          ),
        ),
      ],
    );
  }

  // ---- recovery codes -----------------------------------------------------

  Widget _codesView() {
    final c = context.colors;
    final codes = _codes;
    final owner = _codesOwner;
    final rows = <Widget>[];
    for (var i = 0; i < codes.length; i += 2) {
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : AtomicSpace.x3),
        child: Row(
          children: [
            for (var j = i; j < i + 2; j++)
              Expanded(
                child: j < codes.length
                    ? SelectableText(
                        codes[j],
                        style: AtomicType.mono
                            .copyWith(letterSpacing: 1.4, color: c.textPrimary),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ));
    }
    return Column(
      key: const ValueKey('tf-setup-codes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: StatusChip(TwoFactorPage.shownOnce, tone: StatusTone.danger),
        ),
        const SizedBox(height: AtomicSpace.x3),
        Semantics(
          header: true,
          child: Text(TwoFactorPage.codesTitle,
              style: AtomicType.titleLarge.copyWith(color: c.textPrimary)),
        ),
        const SizedBox(height: AtomicSpace.x2),
        Text(TwoFactorPage.codesBody,
            style: AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
        const SizedBox(height: AtomicSpace.x4),
        AtomicCard(
          key: const ValueKey('tf-setup-code-grid'),
          padding: const EdgeInsets.all(AtomicSpace.heroPadding),
          child: Column(children: rows),
        ),
        const SizedBox(height: AtomicSpace.x4),
        AtomicButton.tonal(
          key: const ValueKey('tf-setup-copy-codes'),
          label: TwoFactorPage.copyAllLabel,
          icon: AtomicIcons.copy,
          onPressed: () {
            if (_stage != _Stage.codes || !identical(_codes, codes)) return;
            _copy(codes.join('\n'), 'Recovery codes copied', owner);
          },
          size: AtomicButtonSize.large,
          expand: true,
        ),
        const SizedBox(height: AtomicSpace.x3),
        GestureDetector(
          key: const ValueKey('tf-setup-saved'),
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () => setState(() => _saved = !_saved),
          child: Row(
            children: [
              AtomicCheckbox(
                checked: _saved,
                semanticsLabel: TwoFactorPage.savedLabel,
                onChanged: (v) => setState(() => _saved = v),
              ),
              const SizedBox(width: AtomicSpace.x1),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(TwoFactorPage.savedLabel,
                      style:
                          AtomicType.bodyLarge.copyWith(color: c.textPrimary)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AtomicSpace.x4),
        AtomicButton.primary(
          key: const ValueKey('tf-setup-done'),
          label: TwoFactorPage.doneLabel,
          onPressed: _saved
              ? () {
                  setState(() {
                    _codes = const [];
                    _codesOwner = null;
                    _stage = _Stage.overview;
                  });
                  _toTop();
                }
              : null,
          size: AtomicButtonSize.large,
          expand: true,
        ),
      ],
    );
  }

  // ---- bits ---------------------------------------------------------------

  Widget _groupLabel(String text) => Padding(
        padding:
            const EdgeInsets.only(left: AtomicSpace.x1, bottom: AtomicSpace.x2),
        child: Semantics(
          header: true,
          child: Text(text,
              style: AtomicType.titleMedium
                  .copyWith(color: context.colors.textPrimary)),
        ),
      );

  Widget _stepHeading(int step, String title) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusChip('Step $step of 2'),
        const SizedBox(height: AtomicSpace.x3),
        Semantics(
          header: true,
          child: Text(title,
              style: AtomicType.titleLarge.copyWith(color: c.textPrimary)),
        ),
      ],
    );
  }

  Widget _bullet(String text, {bool last = false}) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AtomicSpace.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: AtomicSpace.x3),
            child: Container(
              height: 6,
              width: 6,
              decoration:
                  BoxDecoration(color: c.textSecondary, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text(text,
                style: AtomicType.bodyMedium.copyWith(color: c.textPrimary)),
          ),
        ],
      ),
    );
  }

  /// The key in groups of four, easier to read against an app.
  static String _grouped(String secret) {
    final parts = <String>[];
    for (int i = 0; i < secret.length; i += 4) {
      parts.add(
          secret.substring(i, i + 4 > secret.length ? secret.length : i + 4));
    }
    return parts.join(' ');
  }
}

/// A 48 dp icon circle on a card. Decorative.
class _IconCircle extends StatelessWidget {
  const _IconCircle(
      {required this.icon, required this.fill, required this.color});

  final IconData icon;
  final Color fill;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
        child: Icon(icon, size: 24, color: color),
      ),
    );
  }
}

/// The setup QR code: always black on a white rounded card with a 16 dp
/// quiet zone, in both themes, so every scanner reads it.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.data});

  final String data;

  static const double quietZone = 16;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      image: true,
      child: Container(
        key: const ValueKey('tf-setup-qr'),
        padding: const EdgeInsets.all(quietZone),
        decoration: const BoxDecoration(
          color: AtomicPalette.white,
          borderRadius: AtomicRadius.mediumAll,
        ),
        child: QrImageView(
          data: data,
          size: 192,
          padding: EdgeInsets.zero,
          backgroundColor: AtomicPalette.white,
          semanticsLabel: 'Two-factor setup QR code',
          eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square, color: AtomicPalette.black),
          dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: AtomicPalette.black),
        ),
      ),
    );
  }
}

/// Asks for a code inside an [AtomicDialog], runs [submit] with it, and
/// closes with the result once it is ok.
class _CodePrompt extends StatefulWidget {
  final String confirmLabel;
  final bool danger;

  /// Null means nothing was sent: the prompt closes without a result.
  final Future<TwoFactorCheck?> Function(String) submit;

  const _CodePrompt({
    required this.confirmLabel,
    required this.submit,
    this.danger = false,
  });

  @override
  State<_CodePrompt> createState() => _CodePromptState();
}

class _CodePromptState extends State<_CodePrompt> {
  final TextEditingController _controller = TextEditingController();
  bool _recovery = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _go([String? typed]) async {
    if (_busy) return;
    final String text = (typed ?? _controller.text).trim();
    if (text.isEmpty) return;
    final bool recovery = _recovery;
    setState(() {
      _busy = true;
      _error = null;
    });
    TwoFactorCheck? sent;
    try {
      sent = await widget.submit(text);
    } catch (_) {
      // A keystore that refuses the write: the prompt stays usable.
      sent = const TwoFactorCheck(TwoFactorResult.unavailable);
    }
    if (!mounted) return;
    if (sent == null) {
      Navigator.pop(context);
      return;
    }
    final TwoFactorCheck result = sent;
    if (result.ok) {
      Navigator.pop(context, result);
      return;
    }
    _controller.clear();
    setState(() {
      _busy = false;
      _error = switch (result.result) {
        TwoFactorResult.locked =>
          'Too many wrong tries. Try again in ${result.retryAfter?.inSeconds ?? 30} s.',
        TwoFactorResult.unavailable =>
          "This device can't read its two-factor key.",
        _ => recovery
            ? "That recovery code didn't match."
            : "That code didn't match. Wait for a fresh one and try again.",
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TwoFactorCodeField(
          key: ValueKey(_recovery),
          controller: _controller,
          recovery: _recovery,
          enabled: !_busy,
          autofocus: true,
          errorText: _error,
          onCompleted: _go,
          onSubmitted: _go,
        ),
        const SizedBox(height: AtomicSpace.x2),
        Center(
          child: AtomicButton.text(
            key: const ValueKey('tf-prompt-toggle'),
            label: _recovery ? 'Use authenticator code' : 'Use a recovery code',
            onPressed: _busy
                ? null
                : () => setState(() {
                      _recovery = !_recovery;
                      _error = null;
                      _controller.clear();
                    }),
          ),
        ),
        const SizedBox(height: AtomicSpace.x4),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AtomicSpace.x2,
          runSpacing: AtomicSpace.x2,
          children: [
            AtomicButton.text(
              key: const ValueKey('tf-prompt-cancel'),
              label: 'Cancel',
              onPressed: _busy ? null : () => Navigator.pop(context),
            ),
            AtomicButton(
              key: const ValueKey('tf-prompt-confirm'),
              label: widget.confirmLabel,
              variant: widget.danger
                  ? AtomicButtonVariant.danger
                  : AtomicButtonVariant.primary,
              busy: _busy,
              onPressed: _go,
            ),
          ],
        ),
      ],
    );
  }
}
