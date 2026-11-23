import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/profile/profile_store.dart';
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

/// What [ProfileUsernameUpdater.update] established (review R32).
enum UsernameUpdateOutcome {
  /// The Server took the name and this device cached it.
  saved,

  /// The Server answered with a failure status: it did not take the name.
  rejected,

  /// The Server took the name, but caching it on this device failed. The
  /// update is not a failure; refresh the handle to reconcile.
  savedUncached,

  /// No answer arrived (a timeout or a broken connection), so the Server may
  /// or may not have taken the name (review R37). Neither is assumed: the
  /// draft stays for a retry.
  uncertain,

  /// The Server answered with a success status, but its reply could not be
  /// read (review R40). That is not a rejection, and the unreadable reply is
  /// not a confirmation either: nothing is cached, and the page reads the
  /// handle back, read-only, to decide. The update is never resent.
  unconfirmed,

  /// The sign-in that sent the update has ended. Its answer belongs to the
  /// old session: nothing is shown and nothing is cached (review R37).
  retired,
}

/// The Profile page's username save: the same calls, in the same order, as
/// `AuthServices.updateUserInfo`, with a typed outcome instead of a message so
/// the page never reads success from visible copy (review R32).
class ProfileUsernameUpdater {
  /// [api] defaults to [ApiClient.instance]; tests pass a fixture client.
  ProfileUsernameUpdater({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<UsernameUpdateOutcome> update(String username) async {
    final int session = _api.sessionRevision;
    try {
      await _api.setUsername(username);
    } on ApiException catch (error) {
      if (error.code == 'session_changed') return UsernameUpdateOutcome.retired;
      // A success status whose reply could not be read (review R40).
      if (error.statusCode >= 200 && error.statusCode < 300) {
        return UsernameUpdateOutcome.unconfirmed;
      }
      // The Server answered, and the answer was no.
      return UsernameUpdateOutcome.rejected;
    } catch (_) {
      // A timeout or a lost connection proves neither outcome.
      return UsernameUpdateOutcome.uncertain;
    }
    // The cache key is the current account: never write it for a newer one.
    if (_api.sessionRevision != session) return UsernameUpdateOutcome.retired;
    try {
      await ProfileStore.instance.cacheUsername(username);
    } catch (_) {
      return UsernameUpdateOutcome.savedUncached;
    }
    return UsernameUpdateOutcome.saved;
  }
}

/// Where a [ProfileHandleRead] came from.
enum ProfileHandleSource {
  /// The Server's answer: authoritative.
  server,

  /// The Server could not be read; this is the name this device last cached,
  /// which may be stale.
  cache,

  /// Neither the Server nor the cache could be read.
  unavailable,

  /// The sign-in that asked has ended; the answer must not be shown.
  retired,
}

/// One read of the account handle (review R37): the authoritative refresh is
/// separate from the best-effort cache, so a cache failure can neither hide a
/// valid Server answer nor turn it into an error.
class ProfileHandleRead {
  const ProfileHandleRead(this.source, {this.username, this.cacheFailed = false});

  /// The username without "@"; null when [source] is unavailable or retired.
  final String? username;
  final ProfileHandleSource source;

  /// This device could not write (or read) its copy of the handle.
  final bool cacheFailed;

  bool get authoritative => source == ProfileHandleSource.server;
}

/// The Profile page's handle reader: the Server's `GET /atomicuser`, then a
/// best-effort cache write; the cache is read only when the Server cannot be.
/// It replaces `AuthServices.getUserInfo` on this page, whose cache write sits
/// between a valid answer and its return (review R37).
class ProfileHandleReader {
  /// [api] defaults to [ApiClient.instance]; tests pass a fixture client.
  ProfileHandleReader({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  /// Shown when the Server has no name for the account, as before.
  static const String placeholder = 'atomicuser';

  Future<ProfileHandleRead> read() async {
    final int session = _api.sessionRevision;
    String? answer;
    try {
      answer = await _api.getUsername();
    } on ApiException catch (error) {
      if (error.code == 'session_changed') {
        return const ProfileHandleRead(ProfileHandleSource.retired);
      }
    } catch (_) {
      // Offline or the Server is down: fall back to the cache below.
    }
    if (_api.sessionRevision != session) {
      return const ProfileHandleRead(ProfileHandleSource.retired);
    }
    if (answer != null) {
      if (answer.isEmpty) {
        return const ProfileHandleRead(ProfileHandleSource.server,
            username: placeholder);
      }
      var cacheFailed = false;
      try {
        await ProfileStore.instance.cacheUsername(answer);
      } catch (_) {
        cacheFailed = true;
      }
      return ProfileHandleRead(ProfileHandleSource.server,
          username: answer, cacheFailed: cacheFailed);
    }
    try {
      final String? cached = ProfileStore.instance.cachedUsername;
      return ProfileHandleRead(ProfileHandleSource.cache,
          username: cached ?? placeholder);
    } catch (_) {
      return const ProfileHandleRead(ProfileHandleSource.unavailable,
          cacheFailed: true);
    }
  }
}

/// Profile (screens spec, Profile): the picture, the username, and the
/// privacy and security choices.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({
    super.key,
    this.loadUsername,
    this.readHandle,
    this.updateUsername,
    this.checkConnectivity,
  });

  static const String title = 'Profile';

  /// Reads the account handle ("@name") as a Server answer; a throw counts
  /// as an unreadable handle. Injectable so tests stay off the network.
  /// [readHandle] takes precedence.
  final Future<String> Function()? loadUsername;

  /// Reads the account handle with its source. Defaults to
  /// [ProfileHandleReader.read]; injectable for tests.
  final Future<ProfileHandleRead> Function()? readHandle;

  /// Saves a new username and says what happened. Defaults to
  /// [ProfileUsernameUpdater.update]; injectable for tests.
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
  final ProfileUsernameUpdater _updater = ProfileUsernameUpdater();
  final ProfileHandleReader _reader = ProfileHandleReader();

  /// The sign-in this page belongs to. An answer that arrives after it has
  /// ended neither changes this page nor starts anything (review R37).
  final int _session = ApiClient.instance.sessionRevision;

  /// The username without the leading "@", or null until it has loaded: the
  /// Server's last answer, or this device's copy until the Server answers.
  String? _username;
  bool _editing = false;
  bool _saving = false;
  bool _refreshing = false;

  /// Said under the handle after an acknowledged update it could not show
  /// yet, or when this device could not keep a copy; null otherwise.
  String? _note;

  /// The handle could not be read from the Server: the username row offers
  /// a read-only refresh beside Copy and Edit, without moving the page.
  bool _canRefresh = false;

  /// The shown handle is this device's cached copy, not a Server answer: the
  /// username row says it may be out of date (review R40).
  bool _shownFromCache = false;

  /// Only the latest read may change the handle.
  int _reads = 0;

  static const String _acknowledgedNote =
      "Username updated. Couldn't refresh it yet.";
  static const String _uncachedNote =
      "This device couldn't keep a copy of your username.";
  static const String _uncertainMessage =
      "Couldn't confirm the update. Check your connection and try again.";
  static const String _unconfirmedMessage =
      "Couldn't confirm the update. Try again.";

  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
    _usernameController.addListener(_edited);
    _refresh(afterSave: false);
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

  /// Mounted, and still under the sign-in it was opened with.
  bool get _current =>
      mounted && ApiClient.instance.sessionRevision == _session;

  Future<ProfileHandleRead> _readHandle() async {
    final custom = widget.readHandle;
    if (custom != null) return custom();
    final legacy = widget.loadUsername;
    if (legacy == null) return _reader.read();
    try {
      final String name = await legacy();
      return ProfileHandleRead(ProfileHandleSource.server,
          username: name.startsWith('@') ? name.substring(1) : name);
    } catch (_) {
      return const ProfileHandleRead(ProfileHandleSource.unavailable);
    }
  }

  /// Reads the handle and shows what it established. Returns null when the
  /// answer no longer belongs here: the page left, the sign-in changed, or a
  /// newer read started. Only a Server answer replaces the shown handle; a
  /// cached one fills it only before anything has loaded (review R37).
  Future<ProfileHandleRead?> _refresh({required bool afterSave}) async {
    final int ticket = ++_reads;
    final ProfileHandleRead read = await _readHandle();
    if (!_current ||
        ticket != _reads ||
        read.source == ProfileHandleSource.retired) {
      return null;
    }
    setState(() {
      if (read.authoritative) {
        _username = read.username;
        _canRefresh = false;
        _shownFromCache = false;
        _note = read.cacheFailed ? _uncachedNote : null;
      } else {
        if (_username == null) {
          _username = read.username ?? ProfileHandleReader.placeholder;
          _shownFromCache = read.source == ProfileHandleSource.cache &&
              read.username != null &&
              read.username != ProfileHandleReader.placeholder;
        }
        _canRefresh = true;
        if (afterSave) _note = _acknowledgedNote;
      }
    });
    return read;
  }

  /// Reads the handle again without sending the update again.
  Future<void> _retryRefresh() async {
    if (_refreshing || _saving) return;
    setState(() => _refreshing = true);
    try {
      await _refresh(afterSave: false);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
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
  /// failed or unconfirmed update keeps the draft for a retry. When the
  /// Server took the name but this device could not cache it, a refreshed
  /// Server handle decides; a refresh that cannot reach the Server leaves the
  /// acknowledged update standing and offers a read-only retry (review R37).
  /// A success status with an unreadable reply is neither a rejection nor a
  /// confirmation: a read-only refresh decides, and the draft stays unless
  /// the Server's handle is the draft (review R40). The admission is held
  /// through that refresh, so it cannot start a second update.
  /// Nothing from a sign-in that has ended reaches this page.
  Future<void> _save() async {
    if (_saving || !_current) return;
    setState(() => _saving = true);
    var saved = false;
    try {
      final List<ConnectivityResult> link = await (widget.checkConnectivity ??
          () => Connectivity().checkConnectivity())();
      if (!_current) return;
      if (link.contains(ConnectivityResult.none)) {
        _say('No Internet Connection!');
        return;
      }

      final String name = _usernameController.text.trim().toLowerCase();
      if (!_editing || name.isEmpty) {
        _say('Please enter your username');
        return;
      }

      final UsernameUpdateOutcome outcome;
      try {
        outcome = await (widget.updateUsername ?? _updater.update)(name);
      } catch (_) {
        if (!_current) return;
        _say('Error occurred while updating user info');
        return;
      }
      if (!_current) return;
      switch (outcome) {
        case UsernameUpdateOutcome.rejected:
          _say('Error updating username', 1500);
          return;
        case UsernameUpdateOutcome.uncertain:
          _say(_uncertainMessage);
          return;
        case UsernameUpdateOutcome.unconfirmed:
          final ProfileHandleRead? check = await _refresh(afterSave: false);
          if (check == null) return;
          if (check.authoritative && check.username == name) {
            _say('Username updated', 1500);
            saved = true;
          } else if (check.authoritative) {
            _say(_unconfirmedMessage);
          } else {
            _say(_uncertainMessage);
          }
          return;
        case UsernameUpdateOutcome.retired:
          return;
        case UsernameUpdateOutcome.saved:
        case UsernameUpdateOutcome.savedUncached:
          _say('Username updated wait for refresh', 1500);
      }
      final ProfileHandleRead? read = await _refresh(afterSave: true);
      if (read == null) return;
      // A Server handle other than the draft, after an uncached save, keeps
      // the draft: the Server's answer is the evidence.
      saved = !(outcome == UsernameUpdateOutcome.savedUncached &&
          read.authoritative &&
          read.username != name);
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
        if (_note != null) ...[
          const SizedBox(height: AtomicSpace.x2),
          Text(
            _note!,
            key: const ValueKey('profile-handle-note'),
            textAlign: TextAlign.center,
            style: AtomicType.bodySmall.copyWith(color: c.textSecondary),
          ),
        ],
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
          onRefresh: _canRefresh ? _retryRefresh : null,
          stale: _canRefresh && _shownFromCache,
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
    this.onRefresh,
    this.stale = false,
  });

  final String? username;
  final bool editing;
  final TextEditingController controller;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onCopy;
  final VoidCallback onSubmitted;

  /// Shown only while the handle could not be read from the Server: reads it
  /// again, never resubmits (review R37).
  final VoidCallback? onRefresh;

  /// The shown name is this device's cached copy: say it may be out of date
  /// (review R40).
  final bool stale;

  static const String staleLabel = 'Saved on this device · may be out of date';

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
                        if (stale)
                          Text(staleLabel,
                              key: const ValueKey('profile-handle-stale'),
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
              if (onRefresh != null)
                AtomicIconButton(
                  key: const ValueKey('profile-handle-refresh'),
                  icon: AtomicIcons.refresh,
                  tooltip: 'Refresh username',
                  onCard: true,
                  onPressed: onRefresh,
                ),
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
