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
| `damaged_records` | C19 integrity findings | None. Copies are kept aside, and nothing was deleted. |

Issues are listed in this order: ownership, lock, pending work, then
connectivity, backups and damaged records. No action deletes or overwrites
anything.

## Status panel

`RecoveryStatusPanel` shows each issue with its action.

- **One run at a time.** A running action disables every button and shows
  "Working…", so a retry is never submitted twice.
- **Failures.** A failed action says that nothing was changed, and it can be
  tried again.
- **Accessibility.**
  - Issues are live-region announcements.
  - Buttons are at least 48 dp and labelled.
  - The panel has no overflow at 2x text size.

## Redacted report

`redactedReport` produces JSON with issue codes, counts and a few app facts.

- **Allowed values.** App facts are kept only when the value is a short code
  or a version number.
- **Redacted.** Anything else becomes `redacted`: long text, email
  addresses, Google tokens, JWTs, PEM keys and long base64 runs.
- **Keys.** Keys that are not code-like are renamed to `redacted`.
- **Test.** A test plants a note title, an email, a token, a JWT and key
  material, and checks that none of them appear in the report.

## Open

- **Wiring.** The real fact sources still need to be connected: vault state,
  the cache owner, the pending-operation count from the native repository
  (reserved; B05), and provider health.
- **Device checks.** TalkBack and VoiceOver acceptance needs a device.
