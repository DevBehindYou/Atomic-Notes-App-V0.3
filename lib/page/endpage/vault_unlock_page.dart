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
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/fields/atomic_text_field.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shown when the account has a vault this device cannot open yet (screens
/// spec, Vault unlock): a large title, six numbered pill fields, "Unlock
/// vault" and "Skip for now".
///
/// Reachable two ways: the splash routes here at launch, and Settings offers it
/// explicitly. Either way the user can skip it: signing in still gives them
/// their unencrypted notes, which is the whole point of keeping the account
/// password and the recovery phrase as separate boundaries.
///
/// The phrase is only held in the fields and handed to the vault. The page
/// never logs it, never shows it back in a message, and drops it when the
/// sign-in changes under an unlock.
class VaultUnlockPage extends StatefulWidget {
  /// True when the splash sent the user here at launch, so unlocking should
  /// continue into the app rather than pop back to Settings.
  final bool fromStartup;

  /// Checks a phrase. Defaults to [Vault.unlock] with the notes repository's
  /// sample ciphertext; tests pass a fake.
  final Future<bool> Function(List<String> phrase)? unlock;

  /// Runs after a successful unlock. Defaults to
  /// [NotesRepository.reloadAfterUnlock].
  final Future<void> Function()? reloadAfterUnlock;

  /// Who is signed in, compared before and after every wait so a result for
  /// one sign-in never unlocks another. Defaults to the API client's user and
  /// session revision.
  final Object? Function()? sessionIdentity;

  const VaultUnlockPage({
    this.fromStartup = false,
    super.key,
    this.unlock,
    this.reloadAfterUnlock,
    this.sessionIdentity,
  });

  static const String title = 'Enter your recovery phrase';
  static const String explanation =
      'Your encrypted notes are protected on this device. Enter the '
      '${SeedPhrase.wordCount} words you saved to unlock them. They are '
      'checked on this device and never sent anywhere.';
  static const String unlockLabel = 'Unlock vault';
  static const String skipLabel = 'Skip for now';
  static const String cancelLabel = 'Cancel';
  static const String footnote =
      'Skipping still gets you your unencrypted notes. Encrypted notes stay '
      'hidden until you enter the phrase. Nobody can reset it for you, so '
      'never share it with anyone.';

  static const String incompleteMessage =
      'Enter all ${SeedPhrase.wordCount} words.';
  static String unknownMessage(List<String> words) =>
      'Not from the word list: ${words.join(', ')}. Check the spelling.';
  static const String wrongMessage =
      'That phrase did not open the vault. Check the words and their order.';
  static const String offlineMessage =
      'Connect to the internet to unlock on this device the first time.';
  static const String failedMessage = 'Could not unlock. Please try again.';

  /// The accessible name of word field [index] (zero-based).
  static String wordLabel(int index) =>
      'Word ${index + 1} of ${SeedPhrase.wordCount}';

  @override
  State<VaultUnlockPage> createState() => _VaultUnlockPageState();
}

class _VaultUnlockPageState extends State<VaultUnlockPage> {
  late final List<TextEditingController> _fields;
  late final List<FocusNode> _focus;
  bool _loading = false;
  String? _error;

  /// Bumped by every unlock; a result from an older one is ignored.
  int _attempt = 0;

  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _fields =
        List.generate(SeedPhrase.wordCount, (_) => TextEditingController());
    _focus = List.generate(SeedPhrase.wordCount, (_) => FocusNode());
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  Future<bool> _check(List<String> phrase) {
    final unlock = widget.unlock;
    if (unlock != null) return unlock(phrase);
    return Vault.instance.unlock(
      phrase,
      sampleCiphertext: NotesRepository.instance.sampleCiphertext,
    );
  }

  Future<void> _reload() => (widget.reloadAfterUnlock ??
      NotesRepository.instance.reloadAfterUnlock)();

  Object? _session() {
    final identity = widget.sessionIdentity;
    if (identity != null) return identity();
    final api = ApiClient.instance;
    return (api.currentUserId, api.sessionRevision);
  }

  /// Let the user paste the whole phrase into a field.
  void _spread(String value) {
    final parts = SeedPhrase.split(value);
    if (parts.length < 2) return;
    for (var i = 0; i < _fields.length; i++) {
      _fields[i].text = i < parts.length ? parts[i] : '';
    }
    setState(() {});
  }

  /// The sign-in changed while an unlock ran: forget the phrase it was typed
  /// for and say the unlock did not happen.
  void _dropForOtherSession() {
    for (final c in _fields) {
      c.clear();
    }
    setState(() {
      _loading = false;
      _error = VaultUnlockPage.failedMessage;
    });
  }

  Future<void> _unlock() async {
    if (_loading) return;
    final typed = _fields.map((c) => c.text).toList();
    if (typed.any((w) => w.trim().isEmpty)) {
      setState(() => _error = VaultUnlockPage.incompleteMessage);
      return;
    }
    final unknown = SeedPhrase.unknownWords(typed);
    if (unknown.isNotEmpty) {
      setState(() => _error = VaultUnlockPage.unknownMessage(unknown));
      return;
    }

    final attempt = ++_attempt;
    final session = _session();
    // Only this attempt, on this page, for the sign-in it started under, may
    // act on the result.
    bool current() => mounted && attempt == _attempt;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await _check(typed);
      if (!current()) return;
      if (_session() != session) {
        _dropForOtherSession();
        return;
      }
      if (!ok) {
        setState(() {
          _loading = false;
          _error = VaultUnlockPage.wrongMessage;
        });
        return;
      }
      // Decrypt what is already here, pull the rest, fold in plaintext notes.
      await _reload();
      if (!current()) return;
      if (_session() != session) {
        _dropForOtherSession();
        return;
      }
      if (widget.fromStartup) {
        Navigator.pushReplacementNamed(context, '/splashpage');
      } else {
        Navigator.pop(context);
      }
    } on VaultUnverifiableError {
      if (!current()) return;
      if (_session() != session) return _dropForOtherSession();
      setState(() {
        _loading = false;
        _error = VaultUnlockPage.offlineMessage;
      });
    } catch (_) {
      // Plain copy only: an error's own text is never shown or logged here.
      if (!current()) return;
      if (_session() != session) return _dropForOtherSession();
      setState(() {
        _loading = false;
        _error = VaultUnlockPage.failedMessage;
      });
    }
  }

  void _skip() {
    if (widget.fromStartup) {
      Navigator.pushReplacementNamed(context, '/mainpage');
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final error = _error;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: EntranceGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // From Settings the header's back leaves like system back
              // does, even during an unlock; the result is then ignored. At
              // launch there is nothing behind the page, so no back button.
              if (widget.fromStartup)
                const SizedBox(height: AtomicSpace.x6)
              else
                ValueListenableBuilder<bool>(
                  valueListenable: _titleAway,
                  builder: (context, away, _) => AtomicPageHeader(
                    title: VaultUnlockPage.title,
                    showTitle: away,
                  ),
                ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(margin, 0, margin,
                      AtomicSpace.x8 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    const Entrance(index: 0, child: _Title()),
                    const SizedBox(height: AtomicSpace.x3),
                    Entrance(
                      index: 1,
                      child: Text(
                        VaultUnlockPage.explanation,
                        style: AtomicType.bodyLarge
                            .copyWith(color: c.textSecondary),
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x6),
                    Entrance(
                      index: 2,
                      child: FocusTraversalGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < _fields.length; i++) ...[
                              if (i > 0) const SizedBox(height: AtomicSpace.x3),
                              _WordField(
                                key: ValueKey('vault-word-$i'),
                                index: i,
                                controller: _fields[i],
                                focusNode: _focus[i],
                                last: i == _fields.length - 1,
                                onChanged: _spread,
                                onSubmitted: _unlock,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration:
                          AtomicMotion.move(context, AtomicMotion.standard),
                      curve: AtomicMotion.standardCurve,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration:
                            AtomicMotion.fade(context, AtomicMotion.quick),
                        child: error == null
                            ? const SizedBox(
                                key: ValueKey('vault-no-error'),
                                width: double.infinity)
                            : Padding(
                                key: ValueKey(error),
                                padding:
                                    const EdgeInsets.only(top: AtomicSpace.x6),
                                child: Semantics(
                                  liveRegion: true,
                                  child: AtomicBanner(
                                    key: const ValueKey('vault-error'),
                                    tone: BannerTone.danger,
                                    icon: AtomicIcons.alertCircle,
                                    title: error,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x8),
                    Entrance(
                      index: 3,
                      child: AtomicButton.primary(
                        key: const ValueKey('vault-unlock'),
                        label: VaultUnlockPage.unlockLabel,
                        icon: AtomicIcons.lockOpen,
                        // While busy the button keeps its face with a
                        // spinner and ignores taps.
                        busy: _loading,
                        onPressed: _unlock,
                        size: AtomicButtonSize.large,
                        expand: true,
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x3),
                    Entrance(
                      index: 4,
                      child: Center(
                        child: AtomicButton.text(
                          key: const ValueKey('vault-skip'),
                          label: widget.fromStartup
                              ? VaultUnlockPage.skipLabel
                              : VaultUnlockPage.cancelLabel,
                          onPressed: _loading ? null : _skip,
                        ),
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x6),
                    Entrance(
                      index: 5,
                      child: Text(
                        VaultUnlockPage.footnote,
                        style: AtomicType.bodySmall
                            .copyWith(color: c.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AtomicSpace.x2),
      child: Semantics(
        header: true,
        child: Text(
          VaultUnlockPage.title,
          style: AtomicType.headlineLarge
              .copyWith(color: context.colors.textPrimary),
        ),
      ),
    );
  }
}

/// One numbered pill field. The number is drawn inside the pill and the
/// field is named "Word n of 6" for screen readers. Entry rules are the old
/// page's: letters and spaces only, no autocorrect, no suggestions, never
/// capitalised.
class _WordField extends StatelessWidget {
  const _WordField({
    super.key,
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.last,
    required this.onChanged,
    required this.onSubmitted,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool last;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: VaultUnlockPage.wordLabel(index),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
        keyboardType: TextInputType.visiblePassword,
        inputFormatters: [
          FilteringTextInputFormatter.deny(RegExp(r'[^a-zA-Z ]')),
        ],
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        onChanged: onChanged,
        onSubmitted: last ? (_) => onSubmitted() : null,
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
