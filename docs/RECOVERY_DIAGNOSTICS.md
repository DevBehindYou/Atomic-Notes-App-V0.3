# Actionable recovery diagnostics (C20)

`lib/recovery/recovery_diagnostics.dart` decides what a recovery or status
screen should say, and which single safe next step it offers. The facts it
works from come from ports. It is not on any route yet, because the recovery
page stays behind `ATOMIC_RECOVERY_PREVIEW`.

## States

| Code | When | Next step |
| --- | --- | --- |
| `wrong_owner` | The cached notes belong to another account | Sign in with the owning account. The notes are kept. |
| `vault_locked` | Encrypted notes exist and the key is not on this device | Unlock with the recovery phrase |
| `pending_writes` | Local changes are not yet synced | Sync now. When offline or the provider is down, the message says they will upload later instead. |
| `offline` / `provider_unavailable` | No network, or Google Drive is not answering | Try later. Notes keep saving locally. |
| `archive_password`, `archive_password_needed`, `archive_unsupported`, `archive_damaged` | Codes from the last backup read | Choose another backup. Nothing was changed. |
| `damaged_records` | C19 integrity findings | None. The message says only that some stored records could not be read. Counts are of findings per problem, not of distinct notes, and appear only in the redacted report. Kept-aside copies are mentioned only when the `quarantinedCopies` fact confirms them. |

Issues are listed in this order: ownership, lock, pending work, then
connectivity, backups and damaged records. No action deletes or overwrites
anything.

## Status panel

`RecoveryStatusPanel` shows each issue with its action.

- **One run at a time.** A running action disables every button and shows
  "Working…", so a retry is never submitted twice.
- **Failures.** An action can fail part way, so the panel does not claim
  that nothing changed. It says: "That did not finish. Your notes on this
  device are kept; you can try again." The action can be tried again.
- **Accessibility.**
  - Issues are live-region announcements.
  - Buttons are at least 48 dp and labelled.
  - The panel has no overflow at 2x text size.

## Redacted report

`redactedReport` produces JSON in which every value comes from a fixed set.
Redaction does not rely on how a value looks.

- **Diagnostic facts.** Issue codes, counts, flags, integrity problem names and
  `quarantinedCopies`.
- **Archive error.** A known `ArchiveFormatException` code
  (`RecoveryDiagnostics.archiveErrorCodes`). Any other value becomes `other`.
- **App facts.** These come from `DiagnosticApp`, which has three typed fields
  and no free-form map:
  - `version`: kept only when it matches `major.minor.patch+build`, otherwise
    `invalid`.
  - `flavor`: a `DiagnosticFlavor` value.
  - `platform`: a `DiagnosticPlatform` value.
- **Tests.** Tests plant canaries in the archive error and the version: a
  note title, an email, a token, a JWT, key material, and short code-shaped
  values (`diabetes`, `short-secret`, `abc`). None of them appears in the
  report or in the issue messages.

## Open

- **Wiring.** The real fact sources still need to be connected: vault state,
  the cache owner, the pending-operation count from the native repository
  (reserved; B05), and provider health.
- **Device checks.** TalkBack and VoiceOver acceptance needs a device.
