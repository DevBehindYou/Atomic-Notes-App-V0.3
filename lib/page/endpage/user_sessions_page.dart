import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/api/user_sessions.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/cards/atomic_card.dart';
import 'package:atomic_notes/ui/chips/status_chip.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/feedback/empty_state.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/mascot/mascot_stage.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:flutter/material.dart';

/// Sign-ins (screens spec, Sign-ins): this account's sign-ins as the Server
/// stores them, with "End sign-in" on every sign-in but this one.
///
/// Inventory belongs to this exact account and token revision for this route.
/// Ending another sign-in never clears this device's note cache or bypasses
/// Settings' safe logout flow for the current sign-in.
class UserSessionsPage extends StatefulWidget {
  const UserSessionsPage({super.key, this.api});
  final ApiClient? api;

  static const String title = 'Sign-ins';

  @override
  State<UserSessionsPage> createState() => _UserSessionsPageState();
}

class _UserSessionsPageState extends State<UserSessionsPage> {
  late final _api = widget.api ?? ApiClient.instance;
  late final _owner = _api.currentUserId;
  late final _revision = _api.sessionRevision;
  StreamSubscription<void>? _ended;
  List<UserSession> _rows = const [];
  bool _loading = false, _writing = false, _confirming = false;
  String? _error, _pendingHandle;
  int _read = 0;

  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  bool get _current =>
      mounted &&
      _owner != null &&
      _api.isSignedIn &&
      _api.currentUserId == _owner &&
      _api.sessionRevision == _revision;
  bool get _busy => _loading || _writing || _confirming;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
    // Freeze the binding before starting any I/O.
    final binding = (_owner, _revision);
    assert(binding.$2 >= 0);
    _ended = _api.onSessionEnded.listen((_) => _retire());
    unawaited(_load());
  }

  void _retire() {
    if (!mounted) return;
    _read++;
    setState(() {
      _rows = const [];
      _loading = false;
      _error = 'Your sign-in changed. Return to Settings.';
    });
  }

  Future<void> _load() async {
    if (!_current) {
      _retire();
      return;
    }
    if (_loading || _pendingHandle != null) return;
    final ticket = ++_read;
    setState(() {
      _loading = true;
      _error = null;
      _rows = const [];
    });
    try {
      final inventory = await _api.userSessions();
      if (!_current) {
        _retire();
        return;
      }
      if (ticket != _read) return;
      setState(() => _rows = inventory.sessions);
    } catch (error) {
      if (!_current) {
        _retire();
        return;
      }
      if (ticket == _read) setState(() => _error = _message(error));
    } finally {
      if (_current && ticket == _read) setState(() => _loading = false);
    }
  }

  String _message(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 404) {
        return 'Update the Atomic Notes Server to manage sign-ins. Your notes remain on this device.';
      }
      if (error.code == 'session_logout_active') {
        return 'This sign-in has an unfinished safe logout. Finish it on that device, then refresh.';
      }
      if (error.code == 'current_session_requires_safe_logout') {
        return 'Use Logout in Settings for this sign-in. Atomic will protect unsynced notes.';
      }
      if (error.statusCode == 409) {
        return 'The Server could not safely manage these sign-ins. Refresh or try again later.';
      }
    }
    return 'Could not load or update sign-ins. Check your connection and retry.';
  }

  Future<void> _confirm(UserSession session) async {
    if (!_current) {
      _retire();
      return;
    }
    if (_busy || _pendingHandle != null || session.isCurrent) return;
    setState(() => _confirming = true);
    final confirmed = await showAtomicDialog<bool>(
      context: context,
      // Destructive: only the buttons close it.
      barrierDismissible: false,
      destructive: true,
      icon: AtomicIcons.logout,
      title: 'End this sign-in?',
      body: 'It will need Google sign-in again. Unsynced notes remain on that '
          'device; sign back into the same account to recover them. Requests '
          'already in progress may still finish.',
      actions: const [
        AtomicDialogAction(label: 'Cancel', result: false),
        AtomicDialogAction(
          label: 'End sign-in',
          result: true,
          variant: AtomicButtonVariant.danger,
        ),
      ],
    );
    if (!_current) {
      _retire();
      return;
    }
    setState(() => _confirming = false);
    if (confirmed != true ||
        !_rows.any((row) => row.handle == session.handle && !row.isCurrent)) {
      return;
    }
    await _revoke(session.handle);
  }

  Future<void> _revoke(String handle) async {
    if (!_current) {
      _retire();
      return;
    }
    if (_busy ||
        (_pendingHandle != null && _pendingHandle != handle) ||
        !_rows.any((row) => row.handle == handle && !row.isCurrent)) {
      return;
    }
    setState(() {
      _writing = true;
      _pendingHandle = handle;
      _error = null;
    });
    try {
      await _api.revokeUserSession(handle);
      if (!_current) {
        _retire();
        return;
      }
      setState(() {
        _pendingHandle = null;
        _rows =
            _rows.where((row) => row.handle != handle).toList(growable: false);
      });
      await _load();
    } catch (error) {
      if (!_current) {
        _retire();
        return;
      }
      final refused = error is ApiException &&
          error.statusCode >= 400 &&
          error.statusCode < 500;
      setState(() {
        if (refused) _pendingHandle = null;
        _error = refused
            ? _message(error)
            : 'Could not confirm whether this sign-in ended. Retry repeats the same request safely. Your local notes have not been removed.';
      });
    } finally {
      if (_current) setState(() => _writing = false);
    }
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  void dispose() {
    _read++;
    unawaited(_ended?.cancel());
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = _current;
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
                  title: UserSessionsPage.title,
                  showTitle: away,
                  actions: [
                    if (current)
                      AtomicIconButton(
                        key: const ValueKey('refresh-sessions'),
                        icon: AtomicIcons.refresh,
                        tooltip: 'Refresh',
                        onPressed:
                            _busy || _pendingHandle != null ? null : _load,
                      ),
                  ],
                ),
              ),
              Expanded(child: _body(context, current)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, bool current) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final error = _error;
    final pending = _pendingHandle;
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(margin, 0, margin,
          AtomicSpace.x8 + MediaQuery.paddingOf(context).bottom),
      children: [
        const Entrance(index: 0, child: PageTitle(UserSessionsPage.title)),
        Entrance(
          index: 1,
          child: Text(
            'New sign-ins last up to 180 days from login, without an '
            'inactivity timeout. Older sign-ins can have earlier deadlines. '
            'Issued and expiry times below are the Server’s stored dates, '
            'shown in local time. Up to five sign-ins are retained.',
            style: AtomicType.bodyMedium.copyWith(color: c.textSecondary),
          ),
        ),
        const SizedBox(height: AtomicSpace.x6),
        if (!current)
          Entrance(
            index: 2,
            child: Semantics(
              liveRegion: true,
              child: const AtomicBanner(
                key: ValueKey('sessions-changed'),
                tone: BannerTone.attention,
                icon: AtomicIcons.alertTriangle,
                title: 'Your sign-in changed. Return to Settings.',
              ),
            ),
          )
        else ...[
          if (_loading || _writing)
            Entrance(
              index: 2,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AtomicSpace.x4),
                child: _Progress(writing: _writing),
              ),
            ),
          if (error != null)
            Entrance(
              index: 2,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AtomicSpace.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: AtomicBanner(
                        key: const ValueKey('sessions-error'),
                        tone: BannerTone.danger,
                        icon: AtomicIcons.alertCircle,
                        title: error,
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x3),
                    AtomicButton.tonal(
                      key: const ValueKey('retry-sessions'),
                      label: pending == null ? 'Retry' : 'Retry ending sign-in',
                      icon: AtomicIcons.refresh,
                      onPressed: _busy
                          ? null
                          : () => pending == null ? _load() : _revoke(pending),
                    ),
                  ],
                ),
              ),
            ),
          if (!_loading && error == null && _rows.isEmpty)
            const Entrance(
              index: 2,
              child: Padding(
                padding: EdgeInsets.only(top: AtomicSpace.x8),
                child: EmptyState(
                  key: ValueKey('sessions-empty'),
                  title: 'No sign-ins were returned',
                  body: 'Refresh to check again.',
                ),
              ),
            ),
          for (final (i, session) in _rows.indexed)
            Stagger(
              key: ValueKey('session-${session.handle}'),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AtomicSpace.x3),
                child: _SignInCard(
                  session: session,
                  issued: _date(session.createdAt),
                  expires: _date(session.expiresAt),
                  ending: _writing && pending == session.handle,
                  // One sign-in at a time, and never while another request
                  // or the confirmation is open.
                  onEnd:
                      _busy || pending != null ? null : () => _confirm(session),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Loading or ending, read out as it changes.
class _Progress extends StatelessWidget {
  const _Progress({required this.writing});

  final bool writing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const stage = 56.0;
    return Row(
      children: [
        MascotStage(
          size: stage,
          child: DevBehindYouMascot(size: MascotStage.artSize(stage)),
        ),
        const SizedBox(width: AtomicSpace.x3),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              writing ? 'Ending sign-in…' : 'Loading sign-ins…',
              style: AtomicType.bodyMedium.copyWith(color: c.textSecondary),
            ),
          ),
        ),
        const SizedBox(width: AtomicSpace.x3),
        const ExcludeSemantics(child: ProgressRing(size: 20)),
      ],
    );
  }
}

/// One sign-in: what the Server stores about it, and either the way to end
/// it or, for this sign-in, where to log out safely instead.
class _SignInCard extends StatelessWidget {
  const _SignInCard({
    required this.session,
    required this.issued,
    required this.expires,
    required this.ending,
    required this.onEnd,
  });

  final UserSession session;
  final String issued;
  final String expires;
  final bool ending;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hint = session.agentLabel;
    final secondary = AtomicType.bodySmall.copyWith(color: c.textSecondary);
    return AtomicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.surfaceInset,
                    borderRadius: AtomicRadius.mediumAll,
                  ),
                  // The hint is unverified, so no device type is implied.
                  child:
                      Icon(AtomicIcons.devices, size: 20, color: c.textPrimary),
                ),
              ),
              const SizedBox(width: AtomicSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.isCurrent ? 'This sign-in' : 'Other sign-in',
                      style:
                          AtomicType.titleMedium.copyWith(color: c.textPrimary),
                    ),
                    if (session.isCurrent) ...[
                      const SizedBox(height: AtomicSpace.x1),
                      const StatusChip('This device', tone: StatusTone.accent),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AtomicSpace.x3),
          Text('Issued: $issued', style: secondary),
          Text('Expires: $expires', style: secondary),
          const SizedBox(height: AtomicSpace.x2),
          Text(
            'Client hint (unverified): '
            '${hint == null || hint.isEmpty ? 'Unavailable' : hint}',
            style: AtomicType.bodySmall.copyWith(color: c.textPrimary),
          ),
          Text(
            'This hint does not verify a device or show its last activity.',
            style: secondary,
          ),
          const SizedBox(height: AtomicSpace.x3),
          if (session.isCurrent)
            Text(
              'Use Logout in Settings for this sign-in so unsynced notes are '
              'protected.',
              style: secondary,
            )
          else
            AtomicButton.danger(
              key: ValueKey('end-${session.handle}'),
              label: 'End sign-in',
              icon: AtomicIcons.logout,
              size: AtomicButtonSize.compact,
              onCard: true,
              busy: ending,
              onPressed: onEnd,
            ),
        ],
      ),
    );
  }
}
