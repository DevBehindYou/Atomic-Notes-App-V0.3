import 'dart:async';

import 'package:atomic_notes/authentication/auth_services/auth_service.dart';
import 'package:atomic_notes/page/home_page.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/state/notifications/notifications_cubit.dart';
import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/utility/component/energy_popup.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/component/profile_avatar.dart';
import 'package:atomic_notes/utility/intropages/energy_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_ce/hive_ce.dart';

/// The signed-in shell (screens spec, Shell). It hosts Home only: Settings is
/// a pushed route opened from the avatar in the Home header, so there is no
/// app bar, tab stack or bottom bar here. The shell keeps the app-level duties
/// it always had: Back twice to exit, the one-time Energy intro, refreshing
/// the profile, and showing the answer to a sync.
class MainPage extends StatefulWidget {
  const MainPage({super.key, this.refreshHandle, this.energyIntroSeen});

  /// Refreshes the cached account handle that Settings shows. Defaults to
  /// [AuthServices.getUserInfo]; injectable so tests stay off the network.
  final Future<void> Function()? refreshHandle;

  /// Whether the Energy intro was already shown. Defaults to the
  /// `authBox` flag; injectable for tests.
  final bool Function()? energyIntroSeen;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  void initState() {
    super.initState();
    // Sign-out handling lives in SessionGuard, not per screen.
    unawaited(_refreshHandle());
    // The picture is kept per account and nothing announces a new sign-in, so read it afresh.
    context.read<ProfileCubit>().refresh();
    _maybeShowEnergyIntro();
  }

  /// The header no longer shows the handle, but Settings reads the cached
  /// one, so keep warming it on entry as the old masthead did.
  Future<void> _refreshHandle() async {
    try {
      await (widget.refreshHandle ?? () => AuthServices().getUserInfo())();
    } catch (_) {
      // Offline or signed out: Settings keeps the handle it last had.
    }
  }

  /// Show the Atomic Energy feature tour once, the first time the home screen
  /// is reached after this update. This is the universal post-auth landing
  /// (biometric/vault gates route here too), so hooking it here covers every
  /// entry path. Pushed (not replaced) so it pops back to the notes screen.
  void _maybeShowEnergyIntro() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bool seen;
      try {
        seen = widget.energyIntroSeen?.call() ??
            Hive.box<bool>('authBox')
                .get(EnergyIntroScreen.seenFlag, defaultValue: false) ??
            false;
      } catch (_) {
        seen = true; // if the box isn't ready, don't nag; skip this launch
      }
      if (!seen && mounted) {
        Navigator.of(context).pushNamed('/energyintro');
      }
    });
  }

  // ---- back button: press twice to exit -----------------------------------

  DateTime? _lastBackPress;

  /// This is the app's root screen, so a back press here used to just drop
  /// the app into the background (Android's default for a screen with
  /// nothing to pop). The second press within the window actually exits.
  void _handleBack() {
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    const MySnackBar(
      text: 'Press back again to exit',
      sec: 1500,
    ).showMySnackBar(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: BlocListener<NotesBloc, NotesState>(
        // The answer to the sync button; the notes list shows its own.
        listenWhen: (previous, current) =>
            previous.notice != current.notice &&
            current.notice != null &&
            current.notice!.fromSync,
        listener: (context, state) => MySnackBar(
          text: state.notice!.text,
          sec: state.notice!.millis,
        ).showMySnackBar(context),
        child: const HomePage(
          headerActions: [
            _SyncButton(),
            _NotificationBell(),
            _SettingsAvatar()
          ],
        ),
      ),
    );
  }
}

/// Sync (components spec, Progress and sync indicator). Tap syncs at once
/// (INSTANT, 10 energy: the energy gate inside the sync charges only when
/// there are changes to upload and refuses when the balance is short).
/// Long-press opens the Atomic Energy popup. A ring runs around the button
/// while a sync is in flight, and a dot shows when changes wait to sync.
class _SyncButton extends StatelessWidget {
  const _SyncButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesBloc, NotesState>(
      buildWhen: (previous, current) =>
          previous.syncing != current.syncing ||
          previous.pending != current.pending,
      builder: (context, state) {
        final waiting = state.pending > 0;
        final label = state.syncing
            ? 'Sync now, syncing'
            : (waiting
                ? 'Sync now, ${state.pending} '
                    '${state.pending == 1 ? 'change' : 'changes'} waiting'
                : 'Sync now');
        return SizedBox.square(
          dimension: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AtomicIconButton(
                icon:
                    waiting ? AtomicIcons.cloudUpload : AtomicIcons.cloudCheck,
                tooltip: 'Sync now',
                semanticsLabel: label,
                dot: waiting && !state.syncing,
                onPressed: state.syncing
                    ? null
                    : () => context
                        .read<NotesBloc>()
                        .add(const NotesSyncRequested(instant: true)),
                onLongPress: () => showEnergyPopup(context),
              ),
              if (state.syncing)
                IgnorePointer(
                  child: ExcludeSemantics(
                    // Under reduced motion the ring stays visible as a still
                    // arc instead of spinning (Codex R22).
                    child: ProgressRing(
                      key: const ValueKey('home-sync-ring'),
                      size: AtomicIconButton.size + 4,
                      value: AtomicMotion.reduced(context) ? 0.75 : null,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The notification bell with its unread badge ("9+" above nine). Opens the
/// Notification Center and rebuilds with the feed so the badge stays live.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<NotificationsCubit, NotificationsState, int>(
      selector: (state) => state.unreadCount,
      builder: (context, count) => AtomicIconButton(
        icon: AtomicIcons.bell,
        tooltip: 'Notifications',
        semanticsLabel: count > 0 ? 'Notifications, $count unread' : null,
        badgeCount: count,
        onPressed: () => Navigator.pushNamed(context, '/notifications'),
      ),
    );
  }
}

/// The account picture as a 40 dp circle in a 48 target: the Settings entry
/// point now that the bottom bar is gone (components spec, Avatar).
class _SettingsAvatar extends StatelessWidget {
  const _SettingsAvatar();

  static const String label = 'Settings and profile';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: AtomicPressable(
        onTap: () => Navigator.pushNamed(context, '/settingspage'),
        semanticsLabel: label,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.surfaceInset,
                shape: BoxShape.circle,
              ),
              child: const ClipOval(child: ProfileAvatar(size: 40, frame: 0)),
            ),
          ),
        ),
      ),
    );
  }
}
