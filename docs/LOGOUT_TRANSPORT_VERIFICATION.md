# Logout transport verification

This change adds an unused App transport for the gated Server logout protocol.
It does not yet replace the Settings logout action or clear Hive/authentication.

`LogoutEnvelope` freezes the normalized note rows, computes the existing Server
SHA-256 fingerprint and measures the complete UTF-8 push envelope. Admission
sends only request identifiers, fingerprints, note identifiers and byte counts.
The Server remains responsible for choosing paid or emergency funding.

Three public synthetic golden fixtures were generated using the Server's actual
`remoteNoteRowSchema` and `logoutBatchFingerprint` on Server PR #61. They cover
Unicode, default base versions, compact checklist items, ciphertext and dates.
The App tests compare both fingerprints and UTF-8 byte counts. Input mutation
cannot alter a prepared envelope. The Server still validates content limits.

API tests verify recoverable 502 results and zero-cost receipts, unavailable
Server behavior without paid fallback, explicit completion/abort validation,
completion replay without clearing local authentication, and late responses
after a different or newer same-owner session. Existing session tests also pass.

Local strict analysis and all 23 targeted protocol/session tests pass. Full App
tests and CI are additional merge gates. The existing live wire fixture does
not yet invoke this logout protocol; its passing result is regression evidence.

Remaining acceptance: persist the frozen request before HTTP, quiesce writers,
reconcile earlier pending sync, handle sealed and local-only rows, apply results
without losing newer edits/conflict copies, retry after restart, and connect the
user-facing logout flow. Actual App-to-Server logout and native upgrade checks
remain required. No rollout flag, production deployment or device change occurs.
