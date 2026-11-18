// ignore_for_file: use_build_context_synchronously

import 'package:atomic_notes/security/screen_security.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/ui/rows/settings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:local_auth/local_auth.dart';

/// Security (screens spec, Security): the app lock and screen privacy
/// switches, and what the app lock needs from the device.
///
/// The choices live in the process-wide 'authBox'. Biometric unlock is only
/// stored after the device check passes; the screenshot block is only stored
/// after the platform applies it, and the window flag is kept in agreement
/// with what is stored (see [_ScreenProtectionSync]).
class BiomPage extends StatefulWidget {
  const BiomPage({super.key, this.auth, this.openAuthBox});

  /// The device check. Defaults to the real [LocalAuthentication].
  final LocalAuthentication? auth;

  /// Opens the 'authBox'. Defaults to `Hive.openBox<bool>('authBox')`.
  final Future<Box<bool>> Function()? openAuthBox;

  static const String title = 'Security';

  static const String biometricTitle = 'Biometric unlock';
  static const String biometricCaption =
      'Require a fingerprint or face check before opening Atomic.';
  static const String biometricUnsupported =
      "This device doesn't report biometric support.";

  static const String requirementsTitle = 'Requirements';
  static const String requirementsBody =
      'The device needs a lock-screen credential and a fingerprint sensor '
      'for this to work. If you remove the lock-screen password while this '
      'is on, unlocking Atomic may fail.';

  static const String screenshotTitle = 'Block screenshots';
  static const String screenshotCaption =
      'Blocks screenshots and screen recording inside Atomic, and hides its '
      'preview in the recent-apps switcher. Takes effect immediately.';

  /// Shown, with the switch off, while Atomic can't confirm the window flag
  /// matches the saved choice. A tap applies the saved choice again.
  static const String screenshotUnconfirmed =
      "Atomic couldn't confirm whether screenshots are blocked. Tap to apply "
      'your saved choice again.';

  @override
  State<BiomPage> createState() => _BiomPageState();
}

/// How a screenshot change or retry ended.
enum _ScreenOutcome {
  /// The window flag and the saved choice agree on the new value.
  applied,

  /// The platform refused; nothing changed.
  unsupported,

  /// The save failed and the window flag was put back to the saved choice.
  notSaved,

  /// The window flag may differ from the saved choice.
  unconfirmed,

  /// Another change is still running; this one did nothing.
  busy,
}

/// Keeps the window's screenshot flag and the saved choice in one 'authBox'
/// in agreement.
///
/// It is not tied to the page: a change started on the page runs to the end,
/// including putting the flag back after a failed save, even if the page is
/// closed meanwhile. A page opened later finds the same object through the
/// box, so it sees a change still running and any unconfirmed result.
///
/// The box stays the record of the choice; this only tracks whether a change
/// is running and whether the flag is unconfirmed.
class _ScreenProtectionSync extends ChangeNotifier {
  _ScreenProtectionSync._(this._box);

  static final Expando<_ScreenProtectionSync> _byBox = Expando();

  static _ScreenProtectionSync of(Box<bool> box) =>
      _byBox[box] ??= _ScreenProtectionSync._(box);

  final Box<bool> _box;

  /// A change or retry is running.
  bool get busy => _busy;
  bool _busy = false;

  /// The window flag may not match the saved choice.
  bool get unconfirmed => _unconfirmed;
  bool _unconfirmed = false;

  /// The saved choice, or null when the box can't be read.
  bool? saved() {
    try {
      return _box.get(ScreenSecurity.prefKey, defaultValue: false) ?? false;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _apply(bool secure) async {
    try {
      return await ScreenSecurity.set(secure);
    } catch (_) {
      return false;
    }
  }

  /// Sets the window flag to [value], then saves it. When the save fails the
  /// flag is put back to the saved choice; when that fails too the result is
  /// unconfirmed.
  Future<_ScreenOutcome> change(bool value) => _run(() async {
        if (!await _apply(value)) {
          // The platform refused, so the flag is as it was.
          return (_ScreenOutcome.unsupported, _unconfirmed);
        }
        try {
          await _box.put(ScreenSecurity.prefKey, value);
          return (_ScreenOutcome.applied, false);
        } catch (_) {
          // Fall through and match the flag to what is stored.
        }
        final stored = saved();
        if (stored == value) return (_ScreenOutcome.applied, false);
        if (stored != null && await _apply(stored)) {
          return (_ScreenOutcome.notSaved, false);
        }
        return (_ScreenOutcome.unconfirmed, true);
      });

  /// Applies the saved choice to the window flag again.
  Future<_ScreenOutcome> recover() => _run(() async {
        final stored = saved();
        if (stored != null && await _apply(stored)) {
          return (_ScreenOutcome.applied, false);
        }
        return (_ScreenOutcome.unconfirmed, true);
      });

  Future<_ScreenOutcome> _run(
      Future<(_ScreenOutcome, bool)> Function() step) async {
    if (_busy) return _ScreenOutcome.busy;
    _busy = true;
    notifyListeners();
    var result = (_ScreenOutcome.unconfirmed, true);
    try {
      result = await step();
    } catch (_) {
      // Unexpected: say the flag is unconfirmed rather than guess.
    } finally {
      _unconfirmed = result.$2;
      _busy = false;
      notifyListeners();
    }
    return result.$1;
  }
}

class _BiomPageState extends State<BiomPage> {
  // Plain nullable, NOT `late final`: this is assigned from an async callback
  // that can lose the race against dispose(), and reading an unassigned
  // `late final` throws LateInitializationError.
  Box<bool>? _authBox;
  late final LocalAuthentication auth;
  bool isAuthOn = false;
  bool _noScreenshot = false;
  bool _supportState = false;

  /// True while a change to biometric unlock is in progress; taps wait for
  /// it.
  bool _biometricBusy = false;

  /// The screenshot flag's agreement with the box, once the box is open.
  _ScreenProtectionSync? _screen;

  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  @override
  void initState() {
    auth = widget.auth ?? LocalAuthentication();
    auth.isDeviceSupported().then(
      (bool isSupported) {
        if (!mounted) return;
        setState(() {
          _supportState = isSupported;
        });
      },
    );
    _initAuthHive();
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
    super.initState();
  }

  @override
  void dispose() {
    // A screenshot change still running carries on without the page.
    _screen?.removeListener(_onScreenChanged);
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  Future<void> _initAuthHive() async {
    final openAuthBox = widget.openAuthBox;
    final box = openAuthBox != null
        ? await openAuthBox()
        : await Hive.openBox<bool>('authBox');
    if (!mounted) return;
    final screen = _ScreenProtectionSync.of(box)..addListener(_onScreenChanged);
    setState(() {
      _authBox = box;
      _screen = screen;
      isAuthOn = box.get('isAuthOn', defaultValue: false) ?? false;
      _noScreenshot = screen.saved() ?? false;
    });
  }

  void _onScreenChanged() {
    if (!mounted) return;
    setState(() => _noScreenshot = _screen?.saved() ?? false);
  }

  Future<void> _setBiometric(bool value) async {
    final box = _authBox;
    // Nothing to persist to yet — the box is still opening.
    if (box == null) return;
    if (_biometricBusy) return;
    setState(() => _biometricBusy = true);
    try {
      if (_supportState && await _checkCapability()) {
        if (!mounted) return;
        // The write is awaited outside setState: setState's callback is for
        // mutating state, not for I/O.
        try {
          await box.put('isAuthOn', value);
        } catch (_) {
          // Show what is stored, not what was asked for.
          if (!mounted) return;
          const AtomicSnackBar(
            text: "Couldn't change biometric unlock. Try again.",
            millis: 3000,
            error: true,
          ).show(context);
          return;
        }
        if (!mounted) return;
        setState(() {
          isAuthOn = value;
        });
        AtomicSnackBar(
          text: value ? 'Biometric unlock on' : 'Biometric unlock off',
          millis: 2000,
        ).show(context);
      }
    } finally {
      if (mounted) setState(() => _biometricBusy = false);
    }
  }

  /// The switch was tapped: change the block, or, while the flag is
  /// unconfirmed, apply the saved choice again.
  Future<void> _onScreenshotSwitch(bool value) async {
    final screen = _screen;
    if (screen == null || screen.busy) return;
    final outcome = screen.unconfirmed
        ? await screen.recover()
        : await screen.change(value);
    // The change has finished either way; only the message needs the page.
    if (!mounted) return;
    final AtomicSnackBar? message = switch (outcome) {
      _ScreenOutcome.applied => AtomicSnackBar(
          text: (screen.saved() ?? false)
              ? 'Screenshots blocked'
              : 'Screenshots allowed',
          millis: 2000,
        ),
      _ScreenOutcome.unsupported => const AtomicSnackBar(
          text: "This device can't block screenshots",
          millis: 2500,
        ),
      _ScreenOutcome.notSaved => const AtomicSnackBar(
          text: "Couldn't save the screenshot setting. Try again.",
          millis: 3000,
          error: true,
        ),
      _ScreenOutcome.unconfirmed => const AtomicSnackBar(
          text: "Couldn't confirm screenshot protection. Try again.",
          millis: 3000,
          error: true,
        ),
      _ScreenOutcome.busy => null,
    };
    message?.show(context);
  }

  Future<bool> _checkCapability() async {
    try {
      bool authenticated = await auth.authenticate(
          localizedReason: "Checking Device Capability",
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ));

      if (authenticated) {
        return true;
      }
      return false;
    } on PlatformException catch (_) {
      // The biometric prompt can sit open for a while — the user may have
      // left this screen by the time it fails.
      if (!mounted) return false;
      const AtomicSnackBar(
        text: "Couldn't run the biometric check. See the requirements below.",
        millis: 2000,
        error: true,
      ).show(context);
      return false;
    }
  }

  // NOTE: deliberately no `_authBox.close()` here. 'authBox' is a process-wide
  // box opened once in main(); closing it from one screen's dispose() tore it
  // down for every other screen that reads it.

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final ready = _authBox != null;
    final screen = _screen;
    final screenBusy = screen?.busy ?? false;
    final screenUnconfirmed = screen?.unconfirmed ?? false;
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
                builder: (context, away, _) =>
                    AtomicPageHeader(title: BiomPage.title, showTitle: away),
              ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(margin, 0, margin,
                      AtomicSpace.x8 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    const Entrance(index: 0, child: PageTitle(BiomPage.title)),
                    const SizedBox(height: AtomicSpace.x2),
                    Entrance(
                      index: 1,
                      child: SettingsGroup(
                        label: 'App lock',
                        children: [
                          SettingsRow.toggle(
                            key: const ValueKey('security-biometric'),
                            icon: AtomicIcons.fingerprint,
                            title: BiomPage.biometricTitle,
                            caption: _supportState
                                ? BiomPage.biometricCaption
                                : BiomPage.biometricUnsupported,
                            value: isAuthOn,
                            // Off while the box opens, while a change is in
                            // progress, and on a device without support.
                            onChanged: ready && _supportState && !_biometricBusy
                                ? _setBiometric
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x4),
                    const Entrance(
                      index: 2,
                      child: AtomicBanner(
                        tone: BannerTone.info,
                        icon: AtomicIcons.infoCircle,
                        title: BiomPage.requirementsTitle,
                        body: BiomPage.requirementsBody,
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x6),
                    Entrance(
                      index: 3,
                      child: SettingsGroup(
                        label: 'Screen privacy',
                        children: [
                          SettingsRow.toggle(
                            key: const ValueKey('security-screenshots'),
                            icon: AtomicIcons.eyeOff,
                            title: BiomPage.screenshotTitle,
                            caption: screenUnconfirmed
                                ? BiomPage.screenshotUnconfirmed
                                : BiomPage.screenshotCaption,
                            // On only when the block is saved and confirmed:
                            // never while a change runs or the flag is
                            // unconfirmed.
                            value: _noScreenshot &&
                                !screenBusy &&
                                !screenUnconfirmed,
                            onChanged: ready && screen != null && !screenBusy
                                ? _onScreenshotSwitch
                                : null,
                          ),
                        ],
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
