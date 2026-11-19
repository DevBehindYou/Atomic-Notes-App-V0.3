import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/authentication/auth_services/auth_service.dart';
import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:atomic_notes/state/two_factor/two_factor_armed_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/fields/atomic_text_field.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:atomic_notes/ui/rows/settings_row.dart';
import 'package:atomic_notes/utility/component/avatar_picker_dialog.dart';
import 'package:atomic_notes/utility/component/profile_avatar.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Profile (screens spec, Profile): the picture, the username, and the
/// privacy and security choices.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({
    super.key,
    this.loadUsername,
    this.updateUsername,
    this.checkConnectivity,
  });

  static const String title = 'Profile';

  /// Reads the account handle ("@name"). Defaults to
  /// [AuthServices.getUserInfo]; injectable so tests stay off the network.
  final Future<String> Function()? loadUsername;

  /// Saves a new username and says what happened. Defaults to
  /// [AuthServices.updateUsername]; injectable for tests.
  final Future<UsernameUpdateOutcome> Function(String username)?
      updateUsername;

  /// Defaults to `Connectivity().checkConnectivity()`; injectable for tests.
  final Future<List<ConnectivityResult>> Function()? checkConnectivity;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final String _email = ApiClient.instance.currentUserEmail ?? '';
  final TextEditingController _usernameController = TextEditingController();
  final AuthServices _serve = AuthServices();

  /// The username without the leading "@", or null until it has loaded.
  String? _username;
  bool _editing = false;
  bool _saving = false;

  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
    _usernameController.addListener(_edited);
    _loadUsername();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  void _edited() {
    if (_editing && mounted) setState(() {});
  }

  /// "Save changes" shows only while the field differs from the username.
  bool get _changed =>
      _editing &&
      _usernameController.text.trim().toLowerCase() != (_username ?? '');

  Future<void> _loadUsername() async {
    final String name = await (widget.loadUsername ?? _serve.getUserInfo)();
    if (!mounted) return;
    setState(() => _username = name.startsWith('@') ? name.substring(1) : name);
  }

  void _say(String text, [int ms = 2000]) =>
      AtomicSnackBar(text: text, millis: ms).show(context);

  void _startEditing() {
    setState(() {
      _usernameController.text = _username ?? '';
      _editing = true;
    });
  }

  void _stopEditing() => setState(() => _editing = false);

  Future<void> _copyUsername() async {
    final String? name = _username;
    if (name == null) return;
    await Clipboard.setData(ClipboardData(text: name));
    if (!mounted) return;
    _say('Username copied', 1500);
  }

  /// One save at a time. The admission is claimed before the first await
  /// (the connectivity check), so a second tap during that check does not
  /// start a second update (review R30), and it is released on every exit.
  /// Editing closes only on a confirmed save (review R32); a rejected or
  /// failed update keeps the draft for a retry. When the Server took the name
  /// but this device could not cache it, the refreshed handle decides.
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    var saved = false;
    try {
      final List<ConnectivityResult> link = await (widget.checkConnectivity ??
          () => Connectivity().checkConnectivity())();
      if (!mounted) return;
      if (link.contains(ConnectivityResult.none)) {
        _say('No Internet Connection!');
        return;
      }

      final String name = _usernameController.text.trim().toLowerCase();
      if (!_editing || name.isEmpty) {
        _say('Please enter your username');
        return;
      }

      try {
        final UsernameUpdateOutcome outcome =
            await (widget.updateUsername ?? _serve.updateUsername)(name);
        if (!mounted) return;
        switch (outcome) {
          case UsernameUpdateOutcome.saved:
            saved = true;
            _say('Username updated wait for refresh', 1500);
            await _loadUsername();
          case UsernameUpdateOutcome.savedUncached:
            _say('Username updated wait for refresh', 1500);
            await _loadUsername();
            saved = mounted && _username == name;
          case UsernameUpdateOutcome.rejected:
            _say('Error updating username', 1500);
        }
      } catch (_) {
        if (!mounted) return;
        _say('Error occurred while updating user info');
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          if (saved) _editing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final showSave = _changed || _saving;
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
                    title: EditProfilePage.title, showTitle: away),
              ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(margin, 0, margin,
                      AtomicSpace.x8 + bottom + (showSave ? 88 : 0)),
                  children: [
                    const Entrance(
                        index: 0, child: PageTitle(EditProfilePage.title)),
                    const SizedBox(height: AtomicSpace.x4),
                    Entrance(index: 1, child: _identity(context)),
                    const SizedBox(height: AtomicSpace.sectionGap),
                    Entrance(index: 2, child: _account(context)),
                    const SizedBox(height: AtomicSpace.sectionGap),
                    Entrance(index: 3, child: _privacy()),
                  ],
                ),
              ),
              // Pinned to the bottom, shown only when something changed.
              AnimatedSize(
                duration: AtomicMotion.fade(context, AtomicMotion.quick),
                alignment: Alignment.topCenter,
                child: showSave
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(margin, AtomicSpace.x3,
                            margin, AtomicSpace.x4 + bottom),
                        child: AtomicButton.primary(
                          key: const ValueKey('profile-save'),
                          label: 'Save changes',
                          size: AtomicButtonSize.large,
                          expand: true,
                          busy: _saving,
                          onPressed: _save,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- identity -----------------------------------------------------------

  Widget _identity(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Center(
          child: AtomicPressable(
            key: const ValueKey('profile-photo'),
            semanticsLabel: 'Change profile photo',
            excludeSemantics: true,
            borderRadius: BorderRadius.circular(48),
            onTap: () => AvatarPickerDialog.show(context),
            child: SizedBox.square(
              dimension: 96,
              child: Stack(
                children: [
                  const Positioned(
                    left: 4,
                    top: 4,
                    child: ProfileAvatar(size: 88, frame: 0),
                  ),
                  PositionedDirectional(
                    end: 0,
                    bottom: 0,
                    child: Container(
                      height: 32,
                      width: 32,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.canvas, width: 2),
                      ),
                      child:
                          Icon(AtomicIcons.pencil, size: 16, color: c.onAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AtomicSpace.x3),
        Text(
          _username == null ? 'Loading…' : '@$_username',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AtomicType.headlineMedium.copyWith(color: c.textPrimary),
        ),
      ],
    );
  }

  // ---- account ------------------------------------------------------------

  Widget _account(BuildContext context) {
    return SettingsGroup(
      label: 'Account',
      children: [
        _UsernameRow(
          username: _username,
          editing: _editing,
          controller: _usernameController,
          onEdit: _startEditing,
          onCancel: _stopEditing,
          onCopy: _copyUsername,
          onSubmitted: _save,
        ),
        SettingsRow(
          icon: AtomicIcons.mail,
          title: _email.isEmpty ? 'Email' : _email,
          caption: 'Verified via Google',
          chevron: false,
        ),
      ],
    );
  }

  // ---- privacy and security -----------------------------------------------

  Widget _privacy() {
    return BlocProvider(
      create: (_) => TwoFactorArmedCubit(),
      child: BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, profile) => BlocBuilder<TwoFactorArmedCubit, bool>(
          builder: (context, armed) => SettingsGroup(
            label: 'Privacy and security',
            children: [
              // Shown for the look of the profile only: nothing else in the
              // app reads it.
              SettingsRow.toggle(
                key: const ValueKey('profile-public'),
                icon: AtomicIcons.eye,
                title: 'Public profile',
                caption: 'Allow others to discover your profile',
                value: profile.publicProfile,
                onChanged: context.read<ProfileCubit>().setPublicProfile,
              ),
              SettingsRow(
                key: const ValueKey('profile-two-factor'),
                icon: AtomicIcons.shieldLock,
                title: 'Two-factor authentication',
                caption: armed ? 'Enabled' : 'Off',
                onTap: () => Navigator.pushNamed(context, '/twofactor'),
              ),
              // Google is the only sign-in there is; the row is informational.
              const SettingsRow(
                key: ValueKey('profile-connected'),
                icon: AtomicIcons.brandGoogle,
                title: 'Connected accounts',
                caption: 'Google · Connected',
                chevron: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The username row of the Account group: the name with Copy and Edit, or a
/// field with Cancel while editing.
class _UsernameRow extends StatelessWidget {
  const _UsernameRow({
    required this.username,
    required this.editing,
    required this.controller,
    required this.onEdit,
    required this.onCancel,
    required this.onCopy,
    required this.onSubmitted,
  });

  final String? username;
  final bool editing;
  final TextEditingController controller;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onCopy;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = username == null ? 'Loading…' : '@$username';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SettingsRow.minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AtomicSpace.x4, vertical: AtomicSpace.x3),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration:
                  BoxDecoration(color: c.surfaceInset, shape: BoxShape.circle),
              child: Icon(AtomicIcons.user, size: 20, color: c.textPrimary),
            ),
            const SizedBox(width: AtomicSpace.x3),
            Expanded(
              child: editing
                  ? AtomicTextField(
                      key: const ValueKey('profile-username-field'),
                      controller: controller,
                      label: 'Username',
                      hintText: 'Enter username',
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => onSubmitted(),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Username',
                            style: AtomicType.titleMedium
                                .copyWith(color: c.textPrimary)),
                        Text(shown,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AtomicType.bodySmall
                                .copyWith(color: c.textSecondary)),
                      ],
                    ),
            ),
            const SizedBox(width: AtomicSpace.x2),
            if (editing)
              AtomicIconButton(
                icon: AtomicIcons.x,
                tooltip: 'Cancel',
                onCard: true,
                onPressed: onCancel,
              )
            else ...[
              AtomicIconButton(
                icon: AtomicIcons.copy,
                tooltip: 'Copy username',
                onCard: true,
                onPressed: username == null ? null : onCopy,
              ),
              AtomicIconButton(
                key: const ValueKey('profile-username-edit'),
                icon: AtomicIcons.pencil,
                tooltip: 'Edit username',
                onCard: true,
                onPressed: username == null ? null : onEdit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
