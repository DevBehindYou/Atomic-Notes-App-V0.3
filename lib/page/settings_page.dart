import 'dart:math' as math;

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/appearance/appearance_controller.dart';
import 'package:atomic_notes/appearance/appearance_preferences.dart';
import 'package:atomic_notes/authentication/auth_services/auth_service.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/energy_store.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/controls/segmented.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/ui/rows/settings_row.dart';
import 'package:atomic_notes/utility/app_info.dart';
import 'package:atomic_notes/utility/component/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_ce/hive_ce.dart';

typedef SettingsLogoutOperation = Future<void> Function({
  required Future<void> Function(void Function() checkCurrent) finishLocal,
  void Function(String message)? onProgress,
});

/// Settings (screens spec, Settings), pushed from the Home header avatar:
/// the account card, three "At a glance" tiles, then the Notes, Privacy and
/// security, Appearance and About groups, Log out with its live progress,
/// and Danger Zone.
///
/// Every row opens the route it opened before. Logout keeps its
/// confirmation text and runs the same safe sequence; while it runs the
/// page ignores touches and Back, and the progress is read out as it
/// changes.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.api,
    this.repository,
    this.finishLogout,
    this.logoutOperation,
    this.energy,
    this.isSyncOn,
    this.isEncryptionOn,
    this.handle,
    this.appearance,
  });
  final ApiClient? api;
  final NotesRepository? repository;
  final Future<void> Function(void Function() checkCurrent)? finishLogout;
  final SettingsLogoutOperation? logoutOperation;

  /// The balances for the Energy tile. Defaults to [EnergyService.instance].
  final EnergyStore? energy;

  /// Whether cloud sync is on. Defaults to [SyncStatusHelper.isSyncOn].
  final bool Function()? isSyncOn;

  /// Whether note encryption is set up. Defaults to [Vault.isEnabled].
  final bool Function()? isEncryptionOn;

  /// The account handle for the account card. Defaults to
  /// [AuthServices.cachedHandle], which the shell keeps warm.
  final String Function()? handle;

  /// Defaults to the app's [AppearanceScope]. The theme picker shows only
  /// while the controller allows theme switching.
  final AppearanceController? appearance;

  static const String title = 'Settings';

  /// Today's logout confirmation, unchanged.
  static const String logoutConfirmation =
      "Atomic will sync unsent changes before logging out. Instant Sync uses Energy; if you cannot cover it, Emergency InstaSync for this logout uses no Energy. If sync fails, you stay signed in and your notes are kept.";

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _api = widget.api ?? ApiClient.instance;
  late final NotesRepository repo =
      widget.repository ?? NotesRepository.instance;
  late final EnergyStore _energy = widget.energy ?? EnergyService.instance;
  bool _isLoading = false;
  bool _confirming = false;
  String _logoutStatus = 'Checking notes before logout…';
  bool _isMounted = true;

  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
  }

  @override
  void dispose() {
    _isMounted = false;
    _isLoading = false;
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  String get _handle =>
      (widget.handle ?? () => AuthServices.cachedHandle).call();

  /// Null when the sync choice cannot be read yet.
  bool? get _syncOn {
    try {
      return (widget.isSyncOn ?? () => SyncStatusHelper.isSyncOn).call();
    } catch (_) {
      return null;
    }
  }

  bool get _encryptionOn =>
      (widget.isEncryptionOn ?? () => Vault.instance.isEnabled).call();

  /// Opens [route] and reads the summaries again on return, since the page
  /// that was open may have changed them.
  Future<void> _open(String route) async {
    if (!_isMounted || _isLoading) return;
    await Navigator.pushNamed(context, route);
    if (_isMounted) setState(() {});
  }

  Future<void> _confirmLogout() async {
    if (!_isMounted || _isLoading || _confirming) return;
    _confirming = true;
    final confirmed = await showAtomicDialog<bool>(
      context: context,
      // Only the buttons close it, as before.
      barrierDismissible: false,
      icon: AtomicIcons.logout,
      title: 'Log out?',
      body: SettingsPage.logoutConfirmation,
      actions: const [
        AtomicDialogAction(label: 'Cancel', result: false),
        AtomicDialogAction(
          label: 'Log out',
          result: true,
          variant: AtomicButtonVariant.primary,
        ),
      ],
    );
    _confirming = false;
    // The confirmation is closed before the long operation, so its buttons
    // cannot race a second logout and progress stays visible on Settings.
    if (confirmed == true) await _logOut();
  }

  Future<void> _logOut() async {
    if (!_isMounted || _isLoading) return;
    final session = _api.sessionRevision;
    setState(() {
      _isLoading = true;
      _logoutStatus = 'Checking notes before logout…';
    });
    try {
      await (widget.logoutOperation ?? repo.logoutSafely)(
        onProgress: (message) {
          if (_isMounted) setState(() => _logoutStatus = message);
        },
        finishLocal: widget.finishLogout ??
            (checkCurrent) async {
              checkCurrent();
              final authBox = await Hive.openBox<bool>('authBox');
              checkCurrent();
              await authBox.put('isAuthOn', false);
              checkCurrent();
              await SyncStatusHelper.setSyncStatus(true);
              checkCurrent();
              await Vault.instance.clearLocal();
              checkCurrent();
              await _api.signOutIfCurrent(session);
            },
      );
    } catch (error) {
      if (!_isMounted || !mounted) return;
      AtomicSnackBar(
        text: error is LogoutBlocked
            ? error.message
            : 'Logout could not finish. Your unsynced notes remain on this device.',
        millis: 6000,
        error: true,
      ).show(context);
    } finally {
      if (_isMounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setTheme(
      AppearanceController controller, AppearanceMode mode) async {
    final kept = await controller.setMode(mode);
    if (kept || !mounted) return;
    const AtomicSnackBar(
      text: "Couldn't save your theme. It applies until you close the app.",
      millis: 3000,
      error: true,
    ).show(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        backgroundColor: c.canvas,
        body: AbsorbPointer(
          absorbing: _isLoading,
          child: SafeArea(
            bottom: false,
            child: EntranceGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _titleAway,
                    builder: (context, away, _) => AtomicPageHeader(
                      title: SettingsPage.title,
                      showTitle: away,
                    ),
                  ),
                  Expanded(child: _body(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final appearance = widget.appearance ?? AppearanceScope.maybeOf(context);
    const gap = SizedBox(height: AtomicSpace.sectionGap);
    return ListView(
      key: const ValueKey('settings-list'),
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(margin, 0, margin,
          AtomicSpace.x8 + MediaQuery.paddingOf(context).bottom),
      children: [
        const Entrance(index: 0, child: PageTitle(SettingsPage.title)),
        const SizedBox(height: AtomicSpace.x6),
        Entrance(index: 1, child: _accountCard(context)),
        gap,
        Entrance(index: 2, child: _glance(context)),
        gap,
        Entrance(
          index: 3,
          child: BlocSelector<NotesBloc, NotesState, int>(
            selector: (state) => state.binCount,
            builder: (context, binned) => SettingsGroup(
              label: 'Notes',
              children: [
                SettingsRow(
                  key: const ValueKey('settings-cloudsync'),
                  icon: AtomicIcons.cloud,
                  title: 'Cloud sync',
                  caption: 'Sync with your Google Drive',
                  onTap: () => _open('/cloudsyncpage'),
                ),
                SettingsRow(
                  key: const ValueKey('settings-recyclebin'),
                  icon: AtomicIcons.trash,
                  title: 'Recycle Bin',
                  caption: binned == 0 ? 'Empty' : null,
                  count: binned == 0 ? null : binned,
                  countLabel:
                      binned == 1 ? '1 deleted note' : '$binned deleted notes',
                  onTap: () => _open('/recyclebin'),
                ),
              ],
            ),
          ),
        ),
        gap,
        Entrance(
          index: 4,
          child: SettingsGroup(
            label: 'Privacy and security',
            children: [
              SettingsRow(
                key: const ValueKey('settings-security'),
                icon: AtomicIcons.shieldLock,
                title: 'Security',
                caption: 'App lock, screenshots',
                onTap: () => _open('/biompage'),
              ),
              SettingsRow(
                key: const ValueKey('settings-encryption'),
                icon: AtomicIcons.lock,
                title: 'Encryption',
                caption: 'Optional protection before upload',
                onTap: () => _open('/encryptionpage'),
              ),
              SettingsRow(
                key: const ValueKey('settings-twofactor'),
                icon: AtomicIcons.key,
                title: 'Two-factor',
                caption: 'A code to open the app on this device',
                onTap: () => _open('/twofactor'),
              ),
              SettingsRow(
                key: const ValueKey('settings-signins'),
                icon: AtomicIcons.devices,
                title: 'Sign-ins',
                caption: 'Review other sign-ins',
                onTap: () => _open('/usersessions'),
              ),
            ],
          ),
        ),
        gap,
        Entrance(
          index: 5,
          child: SettingsGroup(
            label: 'Appearance',
            children: [
              if (appearance != null && appearance.themeSwitchingEnabled)
                ListenableBuilder(
                  listenable: appearance,
                  builder: (context, _) => _ThemeRow(
                    value: appearance.value,
                    onChanged: (mode) => _setTheme(appearance, mode),
                  ),
                ),
              SettingsRow(
                key: const ValueKey('settings-mascot'),
                icon: AtomicIcons.star,
                title: 'Mascot',
                caption: 'Choose a character and motion',
                onTap: () => _open('/mascot'),
              ),
            ],
          ),
        ),
        gap,
        Entrance(
          index: 6,
          child: SettingsGroup(
            label: 'About',
            children: [
              SettingsRow(
                key: const ValueKey('settings-appinfo'),
                icon: AtomicIcons.infoCircle,
                title: 'App info',
                caption:
                    '${AppInfoText.versionLabel} · ${AppInfoText.copyright}',
                onTap: () => _open('/appinfo'),
              ),
              SettingsRow(
                key: const ValueKey('settings-terms'),
                icon: AtomicIcons.fileText,
                title: 'Terms',
                caption: 'Terms and conditions',
                onTap: () => _open('/tcpage'),
              ),
            ],
          ),
        ),
        gap,
        Entrance(index: 7, child: _logoutCard(context)),
        const SizedBox(height: AtomicSpace.x4),
        Entrance(
          index: 8,
          child: SettingsGroup(
            children: [
              SettingsRow(
                key: const ValueKey('settings-dangerzone'),
                icon: AtomicIcons.alertTriangle,
                title: 'Danger Zone',
                caption: 'Remove cloud or device notes',
                danger: true,
                onTap: () => _open('/dangerzone'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _accountCard(BuildContext context) {
    final c = context.colors;
    final handle = _handle;
    final email = _api.currentUserEmail;
    final hasEmail = email != null && email.isNotEmpty;
    return AtomicPressable(
      key: const ValueKey('settings-account'),
      semanticsLabel: ['Profile', handle, if (hasEmail) email].join('. '),
      excludeSemantics: true,
      borderRadius: AtomicRadius.largeAll,
      onTap: () => _open('/editprofilepage'),
      child: AtomicCard(
        child: Row(
          children: [
            const ClipOval(child: ProfileAvatar(size: 56, frame: 0)),
            const SizedBox(width: AtomicSpace.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(handle,
                      style: AtomicType.titleMedium
                          .copyWith(color: c.textPrimary)),
                  if (hasEmail)
                    Text(email,
                        style: AtomicType.bodySmall
                            .copyWith(color: c.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: AtomicSpace.x2),
            Icon(AtomicIcons.chevronRight, size: 20, color: c.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _glance(BuildContext context) {
    // At large text the tiles stack, so each value keeps its room.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final syncOn = _syncOn;
    final encryptionOn = _encryptionOn;
    final tiles = <Widget>[
      ListenableBuilder(
        listenable: _energy,
        builder: (context, _) {
          final loaded = _energy.hasLoaded;
          final w = _energy.wallet;
          return _GlanceTile(
            key: const ValueKey('glance-energy'),
            fill: !stacked,
            icon: AtomicIcons.bolt,
            label: 'Energy',
            value: loaded ? '${w.energy} / ${w.energyCap}' : 'Not loaded',
            spoken: loaded ? '${w.energy} of ${w.energyCap}' : null,
            accent: true,
            onTap: () => _open('/energypage'),
          );
        },
      ),
      BlocSelector<NotesBloc, NotesState, int>(
        selector: (state) => state.pending,
        builder: (context, pending) {
          final state = switch (syncOn) {
            true => 'On',
            false => 'Off',
            null => 'Unknown',
          };
          return _GlanceTile(
            key: const ValueKey('glance-sync'),
            fill: !stacked,
            icon: syncOn == false
                ? AtomicIcons.cloudOff
                : pending > 0
                    ? AtomicIcons.cloudUpload
                    : AtomicIcons.cloudCheck,
            label: 'Sync',
            value: pending > 0 ? '$state · $pending waiting' : state,
            spoken: pending > 0
                ? '$state. $pending note ${pending == 1 ? 'change' : 'changes'} waiting to sync'
                : null,
            onTap: () => _open('/cloudsyncpage'),
          );
        },
      ),
      _GlanceTile(
        key: const ValueKey('glance-encryption'),
        fill: !stacked,
        icon: encryptionOn ? AtomicIcons.lock : AtomicIcons.lockOpen,
        label: 'Encryption',
        value: encryptionOn ? 'On' : 'Off',
        onTap: () => _open('/encryptionpage'),
      ),
    ];
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: AtomicSpace.x1, bottom: AtomicSpace.x2),
          child: Semantics(
            header: true,
            child: Text('At a glance',
                style: AtomicType.bodySmall.copyWith(color: c.textSecondary)),
          ),
        ),
        if (stacked)
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) const SizedBox(height: AtomicSpace.gridGap),
            Stagger(index: i, child: tile),
          ]
        else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, tile) in tiles.indexed) ...[
                  if (i > 0) const SizedBox(width: AtomicSpace.gridGap),
                  Expanded(
                    child: Stagger(index: i, child: tile),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _logoutCard(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      key: const ValueKey('settings-logout-card'),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AtomicRadius.largeAll,
        border: Border.all(color: c.danger, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: AtomicRadius.largeAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsRow(
              key: const ValueKey('settings-logout'),
              icon: AtomicIcons.logout,
              title: 'Log out',
              caption: _isLoading ? 'Signing out…' : null,
              chevron: false,
              onTap: _isLoading ? null : _confirmLogout,
            ),
            if (_isLoading)
              Padding(
                key: const ValueKey('settings-logout-progress'),
                padding: const EdgeInsets.fromLTRB(
                    AtomicSpace.x4, 0, AtomicSpace.x4, AtomicSpace.x4),
                child: Row(
                  children: [
                    const ProgressRing(size: 20),
                    const SizedBox(width: AtomicSpace.x3),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(_logoutStatus,
                            style: AtomicType.bodySmall
                                .copyWith(color: c.textSecondary)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One "At a glance" tile: an icon, a value and a label on a card, and one
/// button that opens the page behind it.
class _GlanceTile extends StatelessWidget {
  const _GlanceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.spoken,
    this.accent = false,
    this.fill = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// What screen readers hear for [value], when it differs from the text.
  final String? spoken;
  final bool accent;

  /// Fill the height the row gives the tile, so the three match.
  final bool fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = accent ? c.onAccent : c.textPrimary;
    return AtomicPressable(
      semanticsLabel: '$label. ${spoken ?? value}',
      excludeSemantics: true,
      borderRadius: AtomicRadius.largeAll,
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        height: fill ? double.infinity : null,
        child: AtomicCard(
          color: accent ? c.accent : null,
          padding: const EdgeInsets.all(AtomicSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(height: AtomicSpace.x2),
              Text(value,
                  style: AtomicType.numeric(AtomicType.titleMedium)
                      .copyWith(color: fg)),
              Text(label,
                  style: AtomicType.bodySmall
                      .copyWith(color: accent ? c.onAccent : c.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Theme row: the System / Light / Dark segmented control inside the
/// row. When the three labels cannot fit side by side (narrow screens, large
/// text) the same three choices stack as full-width options instead.
class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.value, required this.onChanged});

  final AppearanceMode value;
  final ValueChanged<AppearanceMode> onChanged;

  static const List<(AppearanceMode, String)> _modes = [
    (AppearanceMode.system, 'System'),
    (AppearanceMode.light, 'Light'),
    (AppearanceMode.dark, 'Dark'),
  ];

  /// Whether every label fits on one line in an equal third of [width].
  static bool _fits(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final (_, label) in _modes) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: AtomicType.labelMedium),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    final segment = (width - 2 * AtomicSpace.x1) / _modes.length;
    return widest + 2 * AtomicSpace.x3 <= segment;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      key: const ValueKey('settings-theme'),
      container: true,
      explicitChildNodes: true,
      label: 'Theme',
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AtomicSpace.x4, vertical: AtomicSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: c.surfaceInset, shape: BoxShape.circle),
                  child:
                      Icon(AtomicIcons.palette, size: 20, color: c.textPrimary),
                ),
                const SizedBox(width: AtomicSpace.x3),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text('Theme',
                        style: AtomicType.titleMedium
                            .copyWith(color: c.textPrimary)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AtomicSpace.x3),
            LayoutBuilder(
              builder: (context, box) {
                if (_fits(context, box.maxWidth)) {
                  // The control's highlight is placed left to right, so lay
                  // it out that way and mirror the order for RTL instead.
                  return Directionality(
                    textDirection: TextDirection.ltr,
                    child: Segmented<AppearanceMode>(
                      key: const ValueKey('settings-theme-segmented'),
                      segments: rtl ? _modes.reversed.toList() : _modes,
                      value: value,
                      onChanged: onChanged,
                    ),
                  );
                }
                return Column(
                  key: const ValueKey('settings-theme-stacked'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, (mode, label)) in _modes.indexed) ...[
                      if (i > 0) const SizedBox(height: AtomicSpace.x2),
                      _ThemeOption(
                        label: label,
                        selected: mode == value,
                        onTap: () {
                          if (mode == value) return;
                          AtomicHaptics.play(AtomicHaptic.selection);
                          onChanged(mode);
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One theme choice when the choices stack: selected reads as an inverse
/// pill with a check, as the segmented control's highlight does.
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onInverse : c.textPrimary;
    return AtomicPressable(
      key: ValueKey('settings-theme-$label'),
      selected: selected,
      semanticsLabel: label,
      excludeSemantics: true,
      borderRadius: AtomicRadius.pill,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AtomicMotion.fade(context, AtomicMotion.quick),
        constraints: const BoxConstraints(minHeight: AtomicSpace.minTarget),
        padding: const EdgeInsets.symmetric(
            horizontal: AtomicSpace.x4, vertical: AtomicSpace.x2),
        decoration: BoxDecoration(
          color: selected ? c.inverseSurface : c.surfaceInset,
          borderRadius: AtomicRadius.pill,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AtomicType.labelMedium.copyWith(color: fg)),
            ),
            if (selected) Icon(AtomicIcons.check, size: 20, color: fg),
          ],
        ),
      ),
    );
  }
}
