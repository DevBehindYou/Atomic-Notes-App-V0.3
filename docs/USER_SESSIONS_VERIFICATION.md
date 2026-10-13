# User sign-in inventory and manual revocation

12 October 2026. Settings adds **Sign-ins**, using the existing editorial
components and DevBehindYou loading mascot. This page manages other bearer
sessions only. Current-device Logout continues through the existing safe logout
flow; this feature never clears local note storage or vault keys.

## Contract and ownership

`GET /api/auth/sessions` returns a bounded inventory of at most five rows, with
an opaque 43-character base64url `session_handle`, ISO UTC `created_at` and
`expires_at`, `is_current`, and nullable `agent_label`. A nonempty inventory must
have exactly one current session. The untrusted hint is bounded to 80 Unicode
codepoints; it is not verified device identity or last activity. The client
accepts an empty list defensively and provides Refresh. Unexpected identities,
duplicates, dates, fields, size, count or current flags fail closed.

`POST /api/auth/sessions/revoke` sends only the selected opaque handle and
requires `{ "ok": true }`. Both reads and writes reuse ApiClient's authenticated
transport, 16 KiB response bound, timeouts and exact-session revision fencing.
The inventory never contains a bearer token or Mongo token hash.

The page freezes account ID and token revision before starting I/O. Loading,
confirmation, revoke and refresh results recheck both plus mounting. Sign-out
events retire displayed data. A late response after another-account login,
same-account reauthentication or unmount cannot publish inventory, refresh the
new account, or delete its credentials.

Other-session revocation requires explicit confirmation. The notice explains
that unsynced notes remain on the other device and can be recovered by signing
back into the same account; already admitted in-flight requests may finish.
Only one confirmation/write is active. Ambiguous failures retain the same handle
for a serialized retry; selecting another session cannot change that pending
request. A documented 4xx refusal releases the retry selection without claiming
that revocation happened. Reopening the page reads authoritative inventory.
The Server independently blocks current-session revoke and sessions bound to
unfinished logout plans. The client displays safe-logout guidance for those
refusals; no local logout endpoint or note-clearing shortcut is added.

## Lifetime and compatibility

New App sessions use the Server's 180-day issuance policy with no inactivity
timeout. Inventory displays each stored deadline, including older shorter
sessions. The page does not derive a new deadline from the policy text or change
Google OAuth token lifetime. There is no client expiration timer: offline auth
restoration retains the cached token until an authoritative Server response
retires it. This is not an exact offline 180-day logout promise.

Older Servers returning 404 receive an update notice with Retry. The additive
inventory APIs do not change existing sign-in, sync, wallet or logout contracts.
Controller authentication/cookies are independent and remain unchanged.

## Verification boundaries

Thirteen controlled real-widget cases use the real ApiClient and synthetic
secure-storage/HTTP responses: narrow-screen enlarged-text rendering, stored
dates/current guidance, load error/retry, empty refresh, cancellation,
confirmation, protected-session refusal, ambiguous identical retry, foreign and
same-owner delayed reads, unmount, foreign delayed revoke, session change during
confirmation, and strict DTO bounds. Every case unmounts and drains its owned
responses before cleanup. A private machine-output runner emits only fixed case
and cleanup codes in `ci-user-sessions-proof.json`; it never retains error text,
payloads or raw Flutter output. Six local generated-event guards verify artifact
classification, duplicate/unknown/skip refusal and message exclusion.

Existing nine App proof schemas remain acceptance requirements. Full exact-head
strict analysis, tests, debug APK and existing live wire jobs must pass. Local
installed Dart parsing/formatting does not establish analysis or runtime success.
No local Flutter bootstrap, installation, dependency refresh, build or device
action is performed.

Actual localhost HTTP/Hive session-management proof pins accepted Server main
`95070c0cff488e4984bd669d31bfdf348ec74aca` (Server #77, exact-main CI
38435083132, 35 fixed proof records verified). App CI must independently prove
the client behavior; Server acceptance is not App acceptance. Its dedicated owned namespace
exercises real inventory, current-session refusal, foreign-handle privacy no-op,
other-session revoke and identical retry. The revoked client's real 401 clears
synthetic credentials/runtime while preserving dirty Hive notes and owner tag;
another existing valid same-owner fixture token restores those notes. Fake
Drive writes and wallet/history remain unchanged. This test uses the exact
repository stop/clearMemory sequence, not singleton native SessionGuard
navigation, native Google reauthentication or new token issuance.

The runner emits only `ci-user-sessions-server-wire-proof.json` with fixed phase
and cleanup codes. Existing nine proofs plus both new proofs are required.
Native Google login, keystore, physical device
navigation, signed release and production deployment remain separate boundaries.
