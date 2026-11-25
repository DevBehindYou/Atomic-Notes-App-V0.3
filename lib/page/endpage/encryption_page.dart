// ignore_for_file: use_build_context_synchronously

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/security/seed_phrase.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/chips/status_chip.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/fields/atomic_text_field.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Security -> Encryption (screens spec, Encryption and vault).
///
/// Runs the one-time setup: generate a recovery phrase, show it, make the user
/// prove they wrote it down, and only then create the vault. Setup is not
/// finished until the phrase is typed back correctly, because a phrase nobody
/// saved is a vault nobody can reopen.
///
/// The phrase is only held in the page's state and the confirm fields, and
/// handed to the vault. The page never logs it and never shows it in a
/// message.
class EncryptionPage extends StatefulWidget {
  const EncryptionPage({
    super.key,
    this.isUnlocked,
    this.isEnabled,
    this.generatePhrase,
    this.createVault,
    this.migrateToVault,
    this.lockVault,
    this.currentAccount,
    this.currentSession,
  });

  /// Whether the vault is open on this device. Defaults to
  /// [Vault.isUnlocked]; tests pass a fake.
  final bool Function()? isUnlocked;

  /// Whether the account has a vault. Defaults to [Vault.isEnabled].
  final bool Function()? isEnabled;

  /// Makes a new phrase. Defaults to [SeedPhrase.generate].
  final List<String> Function()? generatePhrase;

  /// Creates the vault from a confirmed phrase. Defaults to
  /// [Vault.createVault].
  final Future<void> Function(List<String> phrase)? createVault;

  /// Folds plaintext notes into the vault and returns how many still wait to
  /// be sent sealed. Defaults to [NotesRepository.migrateToVault].
  final Future<int> Function()? migrateToVault;

  /// Forgets the key on this device. Defaults to
  /// [NotesRepository.lockVault].
  final Future<void> Function()? lockVault;

  /// The signed-in account, which a setup outcome belongs to. Defaults to
  /// [ApiClient.currentUserId]. Read only, never sent anywhere.
  final String? Function()? currentAccount;
  final int Function()? currentSession;

  static const String title = 'Encryption';

  // Off.
  static const String offTitle = 'End-to-end encryption';
  static const String offBody =
      'Seal every note with AES-256-GCM before it leaves this device. You get '
      'a ${SeedPhrase.wordCount}-word recovery phrase that unlocks your notes '
      'on any device. It is the only thing that can open them, and it never '
      'leaves your device.';
  static const String warningTitle = 'Read this first';
  static const String warningBody =
      'The recovery phrase is separate from your account password. Signing in '
      'is not enough to read encrypted notes, on purpose. If you lose the '
      'phrase, nobody can recover those notes, including us. Write it down '
      'somewhere safe before you finish.';
  static const String generateLabel = 'Generate recovery phrase';

  // Step 1 of 2.
  static const String step1 = 'Step 1 of 2';
  static const String showTitle = 'Write it down';
  static const String showBody =
      'These ${SeedPhrase.wordCount} words are your recovery phrase, in this '
      'order. Write them down now. They are shown once and cannot be shown '
      'again after setup.';
  static const String copyLabel = 'Copy phrase';
  static const String wroteLabel = 'I wrote it down';
  static const String copiedMessage =
      'Copied. It clears from the clipboard in 60s. Writing it down by hand is '
      'safer, since any app can read the clipboard.';

  // Step 2 of 2.
  static const String step2 = 'Step 2 of 2';
  static const String verifyTitle = 'Confirm';
  static const String verifyBody =
      'Type the ${SeedPhrase.wordCount} words in order. This confirms you '
      'saved them before encryption is switched on.';
  static const String turnOnLabel = 'Turn on encryption';
  static const String backLabel = 'Back';
  static const String turningOn = 'Turning on encryption…';

  static const String incompleteMessage =
      'Enter all ${SeedPhrase.wordCount} words.';
  static const String mismatchMessage =
      'That does not match the phrase. Check the order.';
  static const String existsMessage =
      'This account already has a vault. Unlock it with your existing phrase '
      'instead of making a new one.';
  static const String failedMessage =
      'Could not turn on encryption. Check your connection.';
  static const String partialMessage =
      'Encryption is on, but your existing notes could not be encrypted yet.';

  static const String onMessage =
      'Encryption is on. Your notes are now end-to-end encrypted.';
  static String waitingMessage(int waiting) =>
      'Encryption is on. $waiting ${waiting == 1 ? 'note has' : 'notes have'} '
      'not been sent encrypted yet.';

  /// The setup outcome that stays on the page after the toast: the notes
  /// the notes step reported as still waiting. Phrased as what setup left,
  /// so it never promises when they will be sent.
  static String pendingTitle(int waiting) =>
      'Setup left $waiting ${waiting == 1 ? 'note' : 'notes'} waiting';
  static const String pendingBody =
      'Setup finished before these notes were sent encrypted. This result '
      'does not reflect any later sync.';

  // On, open on this device.
  static const String onTitle = 'Encryption is on';
  static const String onBody =
      'While the vault is open here, notes are sealed with AES-256-GCM on '
      'this device before they are stored or synced. An encrypted note '
      'reaches the server only as ciphertext it cannot read.';
  static const String deviceLabel = 'This device';
  static const String lockBody =
      'Locking forgets the key here. It does not change copies already '
      'encrypted in the cloud or on other devices. This device asks for '
      'the recovery phrase again.';
  static const String lockLabel = 'Lock on this device';
  static const String locking = 'Locking on this device…';
  static const String lockFailedMessage =
      'Could not finish locking. Please retry.';

  // On, locked on this device.
  static const String lockedTitle = 'Vault locked here';
  static const String lockedBody =
      'This account already has an encrypted vault. Enter your recovery '
      'phrase to open it on this device. Until then your encrypted notes stay '
      'hidden and new notes are saved unencrypted.';
  static const String unlockLabel = 'Unlock vault';

  static const String chipOff = 'Off';
  static const String chipOn = 'On';
  static const String chipLocked = 'Locked';

  /// The accessible name of word [index] (zero-based), shown or typed.
  static String wordLabel(int index) =>
      'Word ${index + 1} of ${SeedPhrase.wordCount}';

  @override
  State<EncryptionPage> createState() => _EncryptionPageState();
}

enum _Step { intro, show, verify }

/// What the last setup on this page reported for one account: notes still
/// waiting ([waiting] > 0), or a notes step that failed after the vault was
/// made ([failed]). A completed setup leaves no outcome.
class _Outcome {
  const _Outcome.pending(this.owner, this.waiting) : failed = false;
  const _Outcome.failed(this.owner)
      : waiting = 0,
        failed = true;

  final (String?, int) owner;
  final int waiting;
  final bool failed;
}

class _EncryptionPageState extends State<EncryptionPage> {
  _Step _step = _Step.intro;
  List<String> _phrase = const [];
  late List<TextEditingController> _fields;
  bool _loading = false;
  String? _error;

  /// The last-known setup outcome. Shown only for the account it belongs
  /// to ([_knownOutcome]).
  _Outcome? _outcome;

  /// Setup is running (a subset of [_loading]); only decides what is shown.
  bool _settingUp = false;

  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _fields =
        List.generate(SeedPhrase.wordCount, (_) => TextEditingController());
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  bool _unlocked() => (widget.isUnlocked ?? () => Vault.instance.isUnlocked)();
  bool _enabled() => (widget.isEnabled ?? () => Vault.instance.isEnabled)();
  String? _account() =>
      (widget.currentAccount ?? () => ApiClient.instance.currentUserId)();

  (String?, int) _owner() => (
        _account(),
        widget.currentSession?.call() ?? ApiClient.instance.sessionRevision,
      );

  bool _showSetupResult((String?, int) owner) {
    if (!mounted) return false;
    if (_owner() == owner) return true;
    for (final field in _fields) {
      field.clear();
    }
    setState(() {
      _loading = false;
      _settingUp = false;
      _phrase = const [];
      _step = _Step.intro;
      _error = null;
      _outcome = null;
    });
    return false;
  }

  /// The outcome, if it is a fact about the account signed in now. Only the
  /// On and Locked views show it, so it is never shown once that account's
  /// vault is off.
  _Outcome? _knownOutcome() {
    final outcome = _outcome;
    if (outcome == null || outcome.owner != _owner()) return null;
    return outcome;
  }

  /// The message for the message slot: this action's error, else a known
  /// failed notes step.
  String? _message() =>
      _error ??
      (_knownOutcome()?.failed == true ? EncryptionPage.partialMessage : null);

  void _toast(String text, {bool error = false}) =>
      AtomicSnackBar(text: text, millis: 2500, error: error).show(context);

  void _generate() {
    setState(() {
      _phrase = (widget.generatePhrase ?? SeedPhrase.generate)();
      _step = _Step.show;
      _error = null;
    });
  }

  Future<void> _copy() async {
    final phrase = _phrase.join(' ');
    await Clipboard.setData(ClipboardData(text: phrase));
    if (!mounted) return;
    _toast(EncryptionPage.copiedMessage);
    // Shrink the exposure window: clear it later, but only if it still holds
    // the phrase, so we never wipe something the user copied in the meantime.
    // No context/setState here, so it is safe after dispose.
    Future.delayed(const Duration(seconds: 60), () async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == phrase) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }

  Future<void> _confirm() async {
    if (_loading) return;
    final typed = _fields.map((c) => c.text).toList();
    if (typed.any((w) => w.trim().isEmpty)) {
      setState(() => _error = EncryptionPage.incompleteMessage);
      return;
    }
    if (!SeedPhrase.matches(typed, _phrase)) {
      setState(() => _error = EncryptionPage.mismatchMessage);
      return;
    }

    // The account this setup runs for; its outcome belongs to it alone.
    final owner = _owner();
    setState(() {
      _loading = true;
      _settingUp = true;
      _error = null;
      _outcome = null;
    });
    try {
      await (widget.createVault ?? Vault.instance.createVault)(_phrase);
      if (_owner() != owner) {
        _showSetupResult(owner);
        return;
      }
      // Fold every existing plaintext note into the vault.
      final waiting = await (widget.migrateToVault ??
          NotesRepository.instance.migrateToVault)();
      if (!_showSetupResult(owner)) return;
      setState(() {
        _loading = false;
        _settingUp = false;
        _phrase = const [];
        _step = _Step.intro;
        // Notes still waiting stay on the page after the toast.
        _outcome = waiting > 0 ? _Outcome.pending(owner, waiting) : null;
      });
      _toast(waiting == 0
          ? EncryptionPage.onMessage
          : EncryptionPage.waitingMessage(waiting));
    } on VaultAlreadyExistsError {
      if (!_showSetupResult(owner)) return;
      setState(() {
        _loading = false;
        _settingUp = false;
        _error = EncryptionPage.existsMessage;
      });
    } catch (e) {
      // Plain copy only: an error's own text is never shown or logged here.
      if (!_showSetupResult(owner)) return;
      setState(() {
        _loading = false;
        _settingUp = false;
        // The vault may be on already (the notes step failed after it was
        // made): say so rather than claim encryption did not turn on. That
        // outcome stays shown for this account, through [_message].
        if (_enabled() || _unlocked()) {
          _outcome = _Outcome.failed(owner);
        } else {
          _error = EncryptionPage.failedMessage;
        }
      });
    }
  }

  Future<void> _lockDevice() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await (widget.lockVault ?? NotesRepository.instance.lockVault)();
      if (!mounted) return;
      // Dispose old editors and routes that may retain decrypted Note objects.
      Navigator.pushNamedAndRemoveUntil(
          context, '/vaultunlock', (route) => false,
          arguments: true);
    } catch (_) {
      if (!mounted) return;
      if (!_unlocked()) {
        Navigator.pushNamedAndRemoveUntil(
            context, '/vaultunlock', (route) => false,
            arguments: true);
      } else {
        setState(() => _loading = false);
        _toast(EncryptionPage.lockFailedMessage, error: true);
      }
    }
  }

  Future<void> _openUnlock() async {
    await Navigator.pushNamed(context, '/vaultunlock');
    // The unlock page may have opened the vault: show what is true now.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final List<Widget> body;
    // While setup runs it stays on the confirm step, even once the vault is
    // made and only the notes step is left, so the busy line stays true.
    if (_settingUp) {
      body = _verify();
    } else if (_unlocked()) {
      body = _active();
    } else if (_enabled()) {
      body = _lockedElsewhere();
    } else {
      body = switch (_step) {
        _Step.intro => _intro(),
        _Step.show => _show(),
        _Step.verify => _verify(),
      };
    }

    return Scaffold(
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
                    title: EncryptionPage.title, showTitle: away),
              ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(margin, 0, margin,
                      AtomicSpace.x8 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    const Entrance(
                        index: 0, child: PageTitle(EncryptionPage.title)),
                    const SizedBox(height: AtomicSpace.x2),
                    for (var i = 0; i < body.length; i++)
                      Entrance(index: i + 1, child: body[i]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The current message, announced when it appears. Always in the tree so
  /// a change of message animates in place.
  Widget _errorSlot() {
    final error = _message();
    return AnimatedSize(
      duration: AtomicMotion.move(context, AtomicMotion.standard),
      curve: AtomicMotion.standardCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AtomicMotion.fade(context, AtomicMotion.quick),
        child: error == null
            ? const SizedBox(
                key: ValueKey('encryption-no-error'), width: double.infinity)
            : Padding(
                key: ValueKey(error),
                padding: const EdgeInsets.only(top: AtomicSpace.x6),
                child: Semantics(
                  liveRegion: true,
                  child: AtomicBanner(
                    key: const ValueKey('encryption-error'),
                    tone: BannerTone.danger,
                    icon: AtomicIcons.alertCircle,
                    title: error,
                  ),
                ),
              ),
      ),
    );
  }

  /// Notes the last setup left waiting, for the account signed in now. It
  /// stays after the toast, so the page never reads as fully encrypted
  /// while its own outcome says otherwise.
  Widget _pendingSlot() {
    final outcome = _knownOutcome();
    if (outcome == null || outcome.waiting <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AtomicSpace.x4),
      child: AtomicBanner(
        key: const ValueKey('encryption-pending'),
        tone: BannerTone.attention,
        icon: AtomicIcons.alertTriangle,
        title: EncryptionPage.pendingTitle(outcome.waiting),
        body: EncryptionPage.pendingBody,
      ),
    );
  }

  /// A short line under a busy button, announced so a screen reader hears
  /// that the action is running.
  Widget _busyLine(String text) => Padding(
        padding: const EdgeInsets.only(top: AtomicSpace.x3),
        child: Semantics(
          liveRegion: true,
          child: Text(
            text,
            key: const ValueKey('encryption-busy'),
            textAlign: TextAlign.center,
            style: AtomicType.bodySmall
                .copyWith(color: context.colors.textSecondary),
          ),
        ),
      );

  Widget _body(String text) => Text(text,
      style:
          AtomicType.bodyLarge.copyWith(color: context.colors.textSecondary));

  // ---- vault on, open on this device ------------------------------------
  List<Widget> _active() => [
        const _Hero(
          key: ValueKey('encryption-on'),
          icon: AtomicIcons.shieldCheck,
          accent: true,
          title: EncryptionPage.onTitle,
          body: EncryptionPage.onBody,
          chip: StatusChip(EncryptionPage.chipOn,
              tone: StatusTone.accent, icon: AtomicIcons.check),
        ),
        _pendingSlot(),
        const SizedBox(height: AtomicSpace.x6),
        const _GroupLabel(EncryptionPage.deviceLabel),
        _body(EncryptionPage.lockBody),
        _errorSlot(),
        const SizedBox(height: AtomicSpace.x4),
        AtomicButton.tonal(
          key: const ValueKey('encryption-lock'),
          label: EncryptionPage.lockLabel,
          icon: AtomicIcons.lock,
          busy: _loading,
          onPressed: _lockDevice,
          expand: true,
        ),
        if (_loading) _busyLine(EncryptionPage.locking),
      ];

  // ---- vault exists, this device cannot open it -------------------------
  List<Widget> _lockedElsewhere() => [
        const _Hero(
          key: ValueKey('encryption-locked'),
          icon: AtomicIcons.lock,
          title: EncryptionPage.lockedTitle,
          body: EncryptionPage.lockedBody,
          chip: StatusChip(EncryptionPage.chipLocked,
              tone: StatusTone.inverse, icon: AtomicIcons.lock),
        ),
        _pendingSlot(),
        _errorSlot(),
        const SizedBox(height: AtomicSpace.x6),
        AtomicButton.primary(
          key: const ValueKey('encryption-unlock'),
          label: EncryptionPage.unlockLabel,
          icon: AtomicIcons.lockOpen,
          onPressed: _openUnlock,
          size: AtomicButtonSize.large,
          expand: true,
        ),
      ];

  // ---- setup, step 1 ----------------------------------------------------
  List<Widget> _intro() => [
        const _Hero(
          key: ValueKey('encryption-off'),
          icon: AtomicIcons.shieldLock,
          title: EncryptionPage.offTitle,
          body: EncryptionPage.offBody,
          chip: StatusChip(EncryptionPage.chipOff),
        ),
        const SizedBox(height: AtomicSpace.x4),
        const AtomicBanner(
          key: ValueKey('encryption-warning'),
          tone: BannerTone.attention,
          icon: AtomicIcons.alertTriangle,
          title: EncryptionPage.warningTitle,
          body: EncryptionPage.warningBody,
        ),
        _errorSlot(),
        const SizedBox(height: AtomicSpace.x6),
        AtomicButton.primary(
          key: const ValueKey('encryption-generate'),
          label: EncryptionPage.generateLabel,
          icon: AtomicIcons.shieldLock,
          onPressed: _generate,
          size: AtomicButtonSize.large,
          expand: true,
        ),
      ];

  // ---- setup, step 2 ----------------------------------------------------
  List<Widget> _show() => [
        const _StepHeading(
            step: EncryptionPage.step1, title: EncryptionPage.showTitle),
        _body(EncryptionPage.showBody),
        const SizedBox(height: AtomicSpace.x4),
        _PhraseGrid(key: const ValueKey('encryption-phrase'), words: _phrase),
        _errorSlot(),
        const SizedBox(height: AtomicSpace.x6),
        AtomicButton.tonal(
          key: const ValueKey('encryption-copy'),
          label: EncryptionPage.copyLabel,
          icon: AtomicIcons.copy,
          onPressed: _copy,
          expand: true,
        ),
        const SizedBox(height: AtomicSpace.x3),
        AtomicButton.primary(
          key: const ValueKey('encryption-wrote'),
          label: EncryptionPage.wroteLabel,
          onPressed: () => setState(() {
            _step = _Step.verify;
            _error = null;
          }),
          size: AtomicButtonSize.large,
          expand: true,
        ),
      ];

  // ---- setup, step 3 ----------------------------------------------------
  List<Widget> _verify() => [
        const _StepHeading(
            step: EncryptionPage.step2, title: EncryptionPage.verifyTitle),
        _body(EncryptionPage.verifyBody),
        const SizedBox(height: AtomicSpace.x4),
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _fields.length; i++) ...[
                if (i > 0) const SizedBox(height: AtomicSpace.x3),
                _WordField(
                  key: ValueKey('encryption-word-$i'),
                  index: i,
                  controller: _fields[i],
                  last: i == _fields.length - 1,
                ),
              ],
            ],
          ),
        ),
        _errorSlot(),
        const SizedBox(height: AtomicSpace.x6),
        AtomicButton.primary(
          key: const ValueKey('encryption-turn-on'),
          label: EncryptionPage.turnOnLabel,
          icon: AtomicIcons.shieldLock,
          busy: _loading,
          onPressed: _confirm,
          size: AtomicButtonSize.large,
          expand: true,
        ),
        if (_loading) _busyLine(EncryptionPage.turningOn),
        const SizedBox(height: AtomicSpace.x3),
        Center(
          child: AtomicButton.text(
            key: const ValueKey('encryption-back'),
            label: EncryptionPage.backLabel,
            onPressed:
                _loading ? null : () => setState(() => _step = _Step.show),
          ),
        ),
      ];
}

/// A hero card: a 48 dp icon circle, a title with a status pill, and the
/// state's explanation.
class _Hero extends StatelessWidget {
  const _Hero({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.chip,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget chip;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AtomicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent ? c.accent : c.surfaceInset,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon,
                      size: 24, color: accent ? c.onAccent : c.textPrimary),
                ),
              ),
              const Spacer(),
              chip,
            ],
          ),
          const SizedBox(height: AtomicSpace.x4),
          Semantics(
            container: true,
            header: true,
            child: Text(title,
                style: AtomicType.titleLarge.copyWith(color: c.textPrimary)),
          ),
          const SizedBox(height: AtomicSpace.x2),
          Text(body,
              style: AtomicType.bodyMedium.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}

/// A step pill and the step's title.
class _StepHeading extends StatelessWidget {
  const _StepHeading({required this.step, required this.title});

  final String step;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AtomicSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusChip(step,
              key: const ValueKey('encryption-step'), tone: StatusTone.inverse),
          const SizedBox(height: AtomicSpace.x3),
          Semantics(
            container: true,
            header: true,
            child: Text(title,
                style: AtomicType.headlineMedium
                    .copyWith(color: context.colors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AtomicSpace.x2),
      child: Semantics(
        container: true,
        header: true,
        child: Text(text,
            style: AtomicType.titleMedium
                .copyWith(color: context.colors.textPrimary)),
      ),
    );
  }
}

/// The phrase as numbered pills in `mono`: two per row, row by row, so the
/// reading order is 1 to 6. With large text the pills stack in one column so
/// no word is squeezed.
class _PhraseGrid extends StatelessWidget {
  const _PhraseGrid({super.key, required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 280 && scale <= 1.3 ? 2 : 1;
      final rows = <Widget>[];
      for (var i = 0; i < words.length; i += columns) {
        if (i > 0) rows.add(const SizedBox(height: AtomicSpace.x2));
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = i; j < i + columns; j++) ...[
              if (j > i) const SizedBox(width: AtomicSpace.x2),
              Expanded(
                child: j < words.length
                    ? _PhrasePill(index: j, word: words[j])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    });
  }
}

class _PhrasePill extends StatelessWidget {
  const _PhrasePill({required this.index, required this.word});

  final int index;
  final String word;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: EncryptionPage.wordLabel(index),
      value: word,
      excludeSemantics: true,
      child: Container(
        key: ValueKey('encryption-phrase-$index'),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
            horizontal: AtomicSpace.x4, vertical: AtomicSpace.x3),
        decoration: BoxDecoration(
          color: c.surfaceInset,
          borderRadius: AtomicRadius.pill,
          border: Border.all(color: c.outline),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text('${index + 1}',
                  style: AtomicType.mono.copyWith(color: c.textSecondary)),
            ),
            const SizedBox(width: AtomicSpace.x2),
            Expanded(
              child: Text(word,
                  style: AtomicType.mono.copyWith(color: c.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One numbered pill field, named "Word n of 6" for screen readers. Entry
/// rules are the old page's: no autocorrect, no suggestions.
class _WordField extends StatelessWidget {
  const _WordField({
    super.key,
    required this.index,
    required this.controller,
    required this.last,
  });

  final int index;
  final TextEditingController controller;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: EncryptionPage.wordLabel(index),
      child: TextField(
        controller: controller,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        cursorColor: c.textPrimary,
        style: AtomicType.mono.copyWith(color: c.textPrimary),
        decoration: AtomicInputDecoration.of(
          context,
          prefixIcon: ExcludeSemantics(
            child: SizedBox(
              width: 48,
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: AtomicType.mono.copyWith(color: c.textSecondary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
