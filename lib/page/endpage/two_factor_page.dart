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

/// Turn two-factor on or off, and manage its recovery codes (screens spec,
/// Two-factor setup).
///
/// Every await belongs to the account and the setup attempt that started
/// it. A result that returns after the page has gone, after the setup was
/// cancelled or restarted, or after the sign-in changed is dropped: an old
/// account's recovery codes are never shown to the account signed in now.
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
  bool _saved = false;
  bool _busy = false;
  String? _error;
  String? _notice;
  int? _codesLeft;

  /// Bumped by every begin and cancel: a confirm from an older setup
  /// attempt is stale.
  int _attempt = 0;

  /// Bumped by every count read: an older read is stale.
  int _countRead = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
    _refreshCount();
  }

  @override
  void dispose() {
    // Leaving mid-setup discards the key: nothing was stored yet.
    _tf.cancelSetup();
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

  void _begin() {
    if (_busy) return;
    _attempt++;
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
    _tf.cancelSetup();
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
    final int attempt = _attempt;
    final Object? owner = _identity();
    setState(() {
      _busy = true;
      _error = null;
    });
    final List<String>? codes = await _tf.confirmSetup(text);
    if (!mounted || attempt != _attempt) return;
    if (_identity() != owner) {
      // The result, and any codes in it, belong to the old account.
      _stopForSignInChange();
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
    _attempt++;
    setState(() {
      _busy = false;
      _codes = codes;
      _saved = false;
      _stage = _Stage.codes;
      _setup = null;
    });
    _code.clear();
    _toTop();
    _refreshCount();
  }

  void _stopForSignInChange() {
    _attempt++;
    _tf.cancelSetup();
    _code.clear();
    setState(() {
      _busy = false;
      _setup = null;
      _codes = const [];
      _saved = false;
      _codesLeft = null;
      _error = null;
      _stage = _Stage.overview;
      _notice = TwoFactorPage.signInChanged;
    });
    _toTop();
    _refreshCount();
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _say(done);
  }

  Future<TwoFactorCheck?> _prompt({
    required String title,
    required String body,
    required String confirmLabel,
    required Future<TwoFactorCheck> Function(String) submit,
    bool danger = false,
  }) {
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
        submit: submit,
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
                                key: ValueKey(_stage),
                                child: switch (_stage) {
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
          onPressed: _begin,
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
                      left == null ? '–' : '$left',
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
                      onPressed: () => _copy(setup.secret, 'Setup key copied'),
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
    final rows = <Widget>[];
    for (var i = 0; i < _codes.length; i += 2) {
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : AtomicSpace.x3),
        child: Row(
          children: [
            for (var j = i; j < i + 2; j++)
              Expanded(
                child: j < _codes.length
                    ? SelectableText(
                        _codes[j],
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
          onPressed: () => _copy(_codes.join('\n'), 'Recovery codes copied'),
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
  final Future<TwoFactorCheck> Function(String) submit;

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
    final TwoFactorCheck result = await widget.submit(text);
    if (!mounted) return;
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
