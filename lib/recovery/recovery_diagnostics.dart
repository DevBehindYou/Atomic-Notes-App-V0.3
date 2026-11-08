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
    this.quarantinedCopies = 0,
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

  /// Record integrity findings by problem, as counts. A count is of
  /// findings, not of distinct notes: one record can have several.
  final Map<IntegrityProblem, int> integrity;

  /// Unreadable records whose copies are confirmed kept aside. Zero unless
  /// the integrity source says so; nothing here infers it.
  final int quarantinedCopies;
}

/// The build a report comes from. Fixed values only.
enum DiagnosticFlavor { development, staging, production }

/// The platform a report comes from. Fixed values only.
enum DiagnosticPlatform { android, ios, web, windows, macos, linux }

/// The app facts a redacted report may carry. Each is typed: there is no
/// field for free text, and a version that is not `major.minor.patch+build`
/// is reported as `invalid`.
class DiagnosticApp {
  const DiagnosticApp({this.version, this.flavor, this.platform});

  final String? version;
  final DiagnosticFlavor? flavor;
  final DiagnosticPlatform? platform;

  static final _version = RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}\+\d{1,9}$');

  Map<String, Object?> toReport() => {
        'version': version == null
            ? null
            : _version.hasMatch(version!)
                ? version
                : 'invalid',
        'flavor': flavor?.name,
        'platform': platform?.name,
      };
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
              'Some stored records could not be read.'
                  '${f.quarantinedCopies > 0 ? ' ${f.quarantinedCopies} ${f.quarantinedCopies == 1 ? 'copy is' : 'copies are'} kept aside.' : ''}',
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

  /// The [ArchiveFormatException] codes a report may name. Any other value
  /// is reported as `other`.
  static const archiveErrorCodes = {
    'authentication_failed',
    'duplicate_id',
    'invalid_checksum',
    'invalid_id',
    'invalid_path',
    'invalid_size',
    'key_required',
    'limit_exceeded',
    'malformed',
    'too_large',
    'truncated',
    'unknown_field',
    'unsupported_kdf',
    'unsupported_version',
  };

  /// A report for support. Every value comes from a fixed set: issue codes,
  /// counts, flags, problem names, a known archive error code and typed app
  /// facts. No string from the caller is copied in except a version that
  /// matches `major.minor.patch+build`, so the report cannot carry note
  /// content, a token or a key.
  static String redactedReport(RecoveryFacts f,
      {DiagnosticApp app = const DiagnosticApp()}) {
    final error = f.archiveError;
    final report = {
      'v': 1,
      'issues': [for (final issue in diagnose(f)) issue.code],
      'pendingWrites': f.pendingWrites,
      'vaultLocked': f.vaultLocked,
      'cacheOwnerMatches': f.cacheOwnerMatches,
      'providerAvailable': f.providerAvailable,
      'online': f.online,
      'archiveError': error == null
          ? null
          : archiveErrorCodes.contains(error)
              ? error
              : 'other',
      'integrity': {for (final e in f.integrity.entries) e.key.name: e.value},
      'quarantinedCopies': f.quarantinedCopies,
      'app': app.toReport(),
    };
    return const JsonEncoder.withIndent('  ').convert(report);
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
                    Text(
                        'That did not finish. Your notes on this device are kept; you can try again.',
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
