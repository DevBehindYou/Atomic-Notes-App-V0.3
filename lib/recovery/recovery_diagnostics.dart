import 'dart:convert';

import 'package:atomic_notes/recovery/record_integrity.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Actionable recovery diagnostics (C20): the problems a recovery or status
/// screen can face, each with a plain message and one safe next step, plus a
/// redacted report that support can read without seeing any note content,
/// token or key.
///
/// The facts come from ports; this file decides only what to say and offer.
/// It is not yet on any route: the recovery page stays behind its gate.

/// The safe next step for a problem. None of them deletes or overwrites.
enum RecoveryAction {
  unlockVault,
  signInAgain,
  retrySync,
  chooseAnotherBackup,
  tryLater,
  none
}

/// What the device currently knows. Counts and codes only.
class RecoveryFacts {
  const RecoveryFacts({
    this.vaultLocked = false,
    this.cacheOwnerMatches = true,
    this.pendingWrites = 0,
    this.archiveError,
    this.providerAvailable = true,
    this.online = true,
    this.integrity = const {},
  });

  /// Encrypted notes exist and the vault key is not on this device.
  final bool vaultLocked;

  /// The notes cached on this device belong to the signed-in account.
  final bool cacheOwnerMatches;

  /// Local changes not yet accepted by the server.
  final int pendingWrites;

  /// An [ArchiveFormatException] code from the last backup read, if any.
  final String? archiveError;

  /// The storage provider (Google Drive) answered recently.
  final bool providerAvailable;
  final bool online;

  /// Record integrity findings by problem, as counts.
  final Map<IntegrityProblem, int> integrity;
}

class RecoveryIssue {
  const RecoveryIssue(this.code, this.message, this.action);

  /// Stable code for the redacted report and tests.
  final String code;
  final String message;
  final RecoveryAction action;
}

abstract final class RecoveryDiagnostics {
  /// Issues in the order a person should deal with them. An empty list means
  /// nothing needs attention.
  static List<RecoveryIssue> diagnose(RecoveryFacts f) => [
        if (!f.cacheOwnerMatches)
          const RecoveryIssue(
              'wrong_owner',
              'The notes on this device belong to a different account. They are kept and will not sync to this one. Sign in with the account that owns them.',
              RecoveryAction.signInAgain),
        if (f.vaultLocked)
          const RecoveryIssue(
              'vault_locked',
              'Encrypted notes are locked on this device. Enter your recovery phrase to open them; nothing is lost while they stay locked.',
              RecoveryAction.unlockVault),
        if (f.pendingWrites > 0)
          RecoveryIssue(
              'pending_writes',
              '${f.pendingWrites} ${f.pendingWrites == 1 ? 'change is' : 'changes are'} saved on this device but not yet synced. '
                  '${f.online && f.providerAvailable ? 'Sync now to upload them.' : 'They will upload when you are back online.'}',
              f.online && f.providerAvailable
                  ? RecoveryAction.retrySync
                  : RecoveryAction.tryLater),
        if (!f.online)
          const RecoveryIssue(
              'offline',
              'You are offline. Notes keep saving on this device.',
              RecoveryAction.tryLater)
        else if (!f.providerAvailable)
          const RecoveryIssue(
              'provider_unavailable',
              'Google Drive is not answering right now. Your notes are safe on this device; try again in a few minutes.',
              RecoveryAction.tryLater),
        if (f.archiveError != null) _archiveIssue(f.archiveError!),
        if (f.integrity.values.any((n) => n > 0))
          RecoveryIssue(
              'damaged_records',
              '${f.integrity.values.fold<int>(0, (a, b) => a + b)} stored notes could not be read. Copies are kept aside; nothing was deleted.',
              RecoveryAction.none),
      ];

  static RecoveryIssue _archiveIssue(String code) => switch (code) {
        'authentication_failed' => const RecoveryIssue(
            'archive_password',
            'The backup password is wrong, or the backup is damaged.',
            RecoveryAction.chooseAnotherBackup),
        'key_required' => const RecoveryIssue(
            'archive_password_needed',
            'This backup is protected. Enter its password.',
            RecoveryAction.none),
        'unsupported_version' || 'unsupported_kdf' => const RecoveryIssue(
            'archive_unsupported',
            'This backup was made by a newer or different version and cannot be opened here. Nothing was changed.',
            RecoveryAction.chooseAnotherBackup),
        _ => const RecoveryIssue(
            'archive_damaged',
            'This backup is damaged or incomplete. Nothing was changed; choose another backup.',
            RecoveryAction.chooseAnotherBackup),
      };

  /// A report for support: issue codes, counts and app facts only. Free text
  /// is never copied in, and any value that looks like a secret, an email
  /// address or long text is replaced, so it cannot carry note content.
  static String redactedReport(RecoveryFacts f,
      {Map<String, Object?> app = const {}}) {
    final report = {
      'v': 1,
      'issues': [for (final issue in diagnose(f)) issue.code],
      'pendingWrites': f.pendingWrites,
      'vaultLocked': f.vaultLocked,
      'cacheOwnerMatches': f.cacheOwnerMatches,
      'providerAvailable': f.providerAvailable,
      'online': f.online,
      'archiveError': f.archiveError == null ? null : _code(f.archiveError!),
      'integrity': {for (final e in f.integrity.entries) e.key.name: e.value},
      'app': {for (final e in app.entries) _code(e.key): _value(e.value)},
    };
    return const JsonEncoder.withIndent('  ').convert(report);
  }

  static final _codePattern = RegExp(r'^[a-z][A-Za-z0-9_.-]{0,39}$');
  static final _emailPattern = RegExp(r'[^\s@]+@[^\s@]+\.[^\s@]+');
  static final _secretPattern = RegExp(
      r'(ya29\.|1//0|GOCSPX-|AIza|eyJ[0-9A-Za-z_-]{8,}\.|-----BEGIN|[0-9A-Za-z+/_-]{32,})');

  static String _code(String value) =>
      _codePattern.hasMatch(value) ? value : 'redacted';

  static Object? _value(Object? value) {
    if (value == null || value is bool || value is num) return value;
    final text = '$value';
    if (text.length > 40 ||
        _emailPattern.hasMatch(text) ||
        _secretPattern.hasMatch(text)) {
      return 'redacted';
    }
    return _codePattern.hasMatch(text) ||
            RegExp(r'^\d+(\.\d+)*(\+\d+)?$').hasMatch(text)
        ? text
        : 'redacted';
  }
}

/// Shows each issue with its next step. A step's button is disabled while it
/// runs, so a retry is never submitted twice.
class RecoveryStatusPanel extends StatefulWidget {
  const RecoveryStatusPanel(
      {required this.facts, required this.onAction, super.key});
  final RecoveryFacts facts;
  final Future<void> Function(RecoveryAction action) onAction;

  @override
  State<RecoveryStatusPanel> createState() => _RecoveryStatusPanelState();
}

class _RecoveryStatusPanelState extends State<RecoveryStatusPanel> {
  RecoveryAction? _running;
  RecoveryAction? _failed;

  static const _labels = {
    RecoveryAction.unlockVault: 'Unlock encrypted notes',
    RecoveryAction.signInAgain: 'Sign in with the owning account',
    RecoveryAction.retrySync: 'Sync now',
    RecoveryAction.chooseAnotherBackup: 'Choose another backup',
  };

  Future<void> _run(RecoveryAction action) async {
    if (_running != null) return;
    setState(() {
      _running = action;
      _failed = null;
    });
    var failed = false;
    try {
      await widget.onAction(action);
    } catch (_) {
      failed = true;
    }
    if (mounted) {
      setState(() {
        _running = null;
        _failed = failed ? action : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final issues = RecoveryDiagnostics.diagnose(widget.facts);
    if (issues.isEmpty) {
      return const Text('Nothing needs attention.',
          key: ValueKey('recovery-status-ok'), style: AppType.bodyMd);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final issue in issues)
          Semantics(
            container: true,
            liveRegion: true,
            child: Padding(
              key: ValueKey('recovery-issue-${issue.code}'),
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(issue.message, style: AppType.bodyMd),
                  if (_failed == issue.action)
                    Text('That did not work. Nothing was changed; try again.',
                        key: ValueKey('recovery-failed-${issue.code}'),
                        style: AppType.bodyMd.copyWith(color: AppColors.error)),
                  if (_labels[issue.action] case final label?)
                    TextButton(
                      key: ValueKey('recovery-action-${issue.code}'),
                      style:
                          TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed:
                          _running == null ? () => _run(issue.action) : null,
                      child:
                          Text(_running == issue.action ? 'Working…' : label),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
