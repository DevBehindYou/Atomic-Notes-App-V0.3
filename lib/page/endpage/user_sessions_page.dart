import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/api/user_sessions.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:flutter/material.dart';

/// Inventory belongs to this exact account and token revision for this route.
/// Ending another sign-in never clears this device's note cache or bypasses
/// Settings' safe logout flow for the current sign-in.
class UserSessionsPage extends StatefulWidget {
  const UserSessionsPage({super.key, this.api});
  final ApiClient? api;

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this other sign-in?'),
        content: const Text(
          'That sign-in will need Google login again. Unsynced notes remain on that device; sign back into the same account to recover them. Requests already in flight may still finish.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-session-revoke'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('confirm-session-revoke'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End sign-in'),
          ),
        ],
      ),
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
        _rows = _rows
            .where((row) => row.handle != handle)
            .toList(growable: false);
      });
      await _load();
    } catch (error) {
      if (!_current) {
        _retire();
        return;
      }
      final refused =
          error is ApiException &&
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    appBar: const MyAppBar(text: 'Sign-ins'),
    body: ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [
        const SectionHeader('YOUR SIGN-INS'),
        const SizedBox(height: AppSpace.sm),
        const Text(
          'New sign-ins last up to 180 days from login, without an inactivity timeout. Older sign-ins can have earlier deadlines. Issued and expiry times below are the Server’s stored dates, shown in local time. Up to five sign-ins are retained.',
          style: AppType.bodySm,
        ),
        const SizedBox(height: AppSpace.md),
        if (!_current)
          const EditorialModule(
            child: Text('Your sign-in changed. Return to Settings.'),
          )
        else ...[
          if (_loading || _writing) ...[
            const Center(child: DevBehindYouMascot(size: 56)),
            Semantics(
              liveRegion: true,
              child: Text(
                _writing ? 'Ending sign-in…' : 'Loading sign-ins…',
                style: AppType.bodySm,
              ),
            ),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            EditorialModule(child: Text(_error!, style: AppType.bodySm)),
            const SizedBox(height: AppSpace.sm),
            InkActionButton(
              key: const ValueKey('retry-sessions'),
              label: _pendingHandle == null ? 'Retry' : 'Retry ending sign-in',
              onTap: _busy
                  ? null
                  : () => _pendingHandle == null
                        ? _load()
                        : _revoke(_pendingHandle!),
            ),
          ],
          if (!_loading && _error == null && _rows.isEmpty)
            const EditorialModule(
              child: Text('No sign-ins were returned. Refresh to check again.'),
            ),
          for (final session in _rows) ...[
            const SizedBox(height: AppSpace.md),
            EditorialModule(
              key: ValueKey('session-${session.handle}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MonoLabel(
                    session.isCurrent ? 'THIS SIGN-IN' : 'OTHER SIGN-IN',
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'Issued: ${_date(session.createdAt)}\nExpires: ${_date(session.expiresAt)}',
                    style: AppType.bodySm,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'Client hint (unverified): ${session.agentLabel == null || session.agentLabel!.isEmpty ? 'Unavailable' : session.agentLabel}',
                    style: AppType.bodySm,
                  ),
                  const Text(
                    'This hint does not verify a device or show its last activity.',
                    style: AppType.bodySm,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  if (session.isCurrent)
                    const Text(
                      'Use Logout in Settings for this sign-in so unsynced notes are protected.',
                      style: AppType.bodySm,
                    )
                  else
                    InkActionButton(
                      key: ValueKey('end-${session.handle}'),
                      label: 'End sign-in',
                      danger: true,
                      onTap: _busy || _pendingHandle != null
                          ? null
                          : () => _confirm(session),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          InkActionButton(
            key: const ValueKey('refresh-sessions'),
            label: 'Refresh',
            onTap: _busy || _pendingHandle != null ? null : _load,
          ),
        ],
      ],
    ),
  );
}
