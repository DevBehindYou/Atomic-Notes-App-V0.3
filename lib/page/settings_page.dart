// ignore_for_file: use_build_context_synchronously, prefer_final_fields, deprecated_member_use

import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/authentication/auth_services/auth_service.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/utility/component/logo_container.dart';
import 'package:atomic_notes/utility/component/logout_dialogbox.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/component/profile_container.dart';
import 'package:atomic_notes/utility/app_info.dart';
import 'package:atomic_notes/utility/component/settings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_ce/hive_ce.dart';

typedef SettingsLogoutOperation = Future<void> Function({
  required Future<void> Function(void Function() checkCurrent) finishLocal,
  void Function(String message)? onProgress,
});

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.api, this.repository, this.finishLogout, this.logoutOperation});
  final ApiClient? api;
  final NotesRepository? repository;
  final Future<void> Function(void Function() checkCurrent)? finishLogout;
  final SettingsLogoutOperation? logoutOperation;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _api = widget.api ?? ApiClient.instance;
  late String? userId = _api.currentUserEmail;
  final AuthServices serve = AuthServices();
  late final NotesRepository repo =
      widget.repository ?? NotesRepository.instance;
  bool _isLoading = false;
  String _logoutStatus = 'Checking notes before logout…';
  String? username = AuthServices.cachedHandle;
  bool _isMounted = true;

  @override
  void dispose() {
    _isMounted = false;
    _isLoading = false;
    super.dispose();
  }

  _showPopUp({required String txt, required Function func}) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) {
        return DialogBoxLogout(
          action: () async {
            // Close confirmation before the long operation; its buttons cannot
            // race a second logout and progress remains visible on Settings.
            Navigator.pop(context);
            await func();
          },
          text: txt,
        );
      },
    );
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
      if (!_isMounted) return;
      MySnackBar(
        text: error is LogoutBlocked
            ? error.message
            : 'Logout could not finish. Your unsynced notes remain on this device.',
        sec: 6000,
      ).showMySnackBar(context);
    } finally {
      if (_isMounted) setState(() => _isLoading = false);
    }
  }

  /// Two cards side by side, the same height however much text each holds.
  Widget _cardRow(Widget left, Widget right) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm + 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpace.sm + 4),
            Expanded(child: right),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: AbsorbPointer(
          absorbing: _isLoading,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EditorialHeading('Settings', style: AppType.headlineLg),
                const SizedBox(height: AppSpace.xs),
                // The signed-in address, as mono metadata rather than a pill.
                MonoLabel(userId ?? '—'),
                const SizedBox(height: AppSpace.md),
                const HairRule(color: AppColors.ink),
                const SizedBox(height: AppSpace.md),

                // logout button section
                ProConatainer(
                  isLoading: _isLoading,
                  logout: () => _showPopUp(
                      txt:
                          "Atomic will sync unsent changes before logging out. Instant Sync uses Energy; if you cannot cover it, Emergency InstaSync for this logout uses no Energy. If sync fails, you stay signed in and your notes are kept.",
                      func: _logOut),
                ),
                if (_isLoading) ...[
                  const SizedBox(height: AppSpace.sm),
                  Semantics(
                      liveRegion: true,
                      child: Text(_logoutStatus, style: AppType.bodySm)),
                  const SizedBox(height: AppSpace.sm),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: AppSpace.lg),
                const SectionHeader('MANAGE'),

                const SizedBox(height: AppSpace.md),
                BlocSelector<NotesBloc, NotesState, int>(
                  selector: (state) => state.binCount,
                  builder: (context, binned) {
                    return Column(
                      children: [
                        _cardRow(
                          SettingsCard(
                            icon: Icons.person_outline,
                            title: 'Profile',
                            caption: 'Photo, name, 2FA',
                            onTap: () => Navigator.pushNamed(
                                context, '/editprofilepage'),
                          ),
                          SettingsCard(
                            icon: Icons.cloud_sync_outlined,
                            title: 'Cloud Sync',
                            caption: 'Drive backup',
                            onTap: () =>
                                Navigator.pushNamed(context, '/cloudsyncpage'),
                          ),
                        ),
                        _cardRow(
                          SettingsCard(
                            icon: Icons.delete_outline,
                            title: 'Recycle Bin',
                            caption: binned == 0 ? 'Empty' : '$binned deleted',
                            onTap: () =>
                                Navigator.pushNamed(context, '/recyclebin'),
                          ),
                          SettingsCard(
                            icon: Icons.lock_outline,
                            title: 'Security',
                            caption: 'Lock, screenshots',
                            onTap: () =>
                                Navigator.pushNamed(context, '/biompage'),
                          ),
                        ),
                        _cardRow(
                          SettingsCard(
                            icon: Icons.enhanced_encryption_outlined,
                            title: 'Encryption',
                            caption: 'End-to-end',
                            onTap: () =>
                                Navigator.pushNamed(context, '/encryptionpage'),
                          ),
                          SettingsCard(
                            icon: Icons.bolt_outlined,
                            title: 'Atomic Energy',
                            caption: 'Coins, quota',
                            onTap: () =>
                                Navigator.pushNamed(context, '/energypage'),
                          ),
                        ),
                        // The destructive entry stands apart, on its own row.
                        SettingsCard(
                          icon: Icons.warning_amber_rounded,
                          title: 'Danger Zone',
                          caption: 'Wipe cloud or this device',
                          danger: true,
                          wide: true,
                          onTap: () =>
                              Navigator.pushNamed(context, '/dangerzone'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpace.xl),

                //logo section
                const LogoContainer(),
                const SizedBox(height: AppSpace.xl),

                // Colophon: inverted module, the system's way of closing a page.
                EditorialModule(
                  inverted: true,
                  padding: const EdgeInsets.all(AppSpace.md + 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MonoLabel('ABOUT ATOMIC', color: AppColors.signal),
                      const SizedBox(height: AppSpace.sm),
                      EditorialHeading(
                        'Local-first notes',
                        style:
                            AppType.headlineMd.copyWith(color: AppColors.paper),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        AppInfoText.versionLabel,
                        style: AppType.labelMonoSm
                            .copyWith(color: AppColors.outlineVariant),
                      ),
                      Text(
                        AppInfoText.copyright,
                        style: AppType.labelMonoSm
                            .copyWith(color: AppColors.outlineVariant),
                      ),
                      const SizedBox(height: AppSpace.md),
                      ArrowLink(
                        'App info',
                        onTap: () => Navigator.pushNamed(context, '/appinfo'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
