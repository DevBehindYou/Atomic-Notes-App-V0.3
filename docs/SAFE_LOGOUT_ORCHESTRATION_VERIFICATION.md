# Safe logout orchestration — 10 October 2026

Local final gate: strict analysis reports no issues and all 560 tests pass;
22 existing live wire cases are skipped locally and run in CI. The 29 additional
tests are 25 orchestration/UI cases and four transport/session cases. Earlier UI
fixture attempts exposed simulated-clock/real-IO deadlocks and were replaced by
the controlled UI coordinator; the accepted full run uses stable source.

One manifest supports at most five batches of 50 rows, each at most 2.5 MB.
Oversized work refuses logout and retains local notes. Very large backlogs of
tombstones require a separate bounded continuation design before claiming that
every possible backlog can be cleared by one emergency logout attempt.

Settings delegates logout to the repository. The repository fences new note
writers, sync, wipe and vault mutation, and refuses to overtake an already-running
note mutation. It drains the active sync and Hive writes before preparing work.
Raw dirty rows, unanswered requests and live local-only rows count as work;
hidden encrypted rows require unlocking. Cloud Sync opt-out and offline state
are respected. Clean, acknowledged caches can still log out without sync.

The frozen manifest is saved and flushed before admission. The Server decides
paid versus emergency funding for the whole bounded attempt; the App displays
that decision. An already-issued ordinary request replays its original mode and
request ID. Logout batches require complete, matching note acknowledgements and
explicit billing receipts. Lost replies keep the pending request. A saved later
batch is reconciled before earlier receipts replay. Settled failures/conflicts
retain notes and copies; only an acknowledged abort permits a new manifest.

Completion intent is persisted before HTTP. Restart retries completion before
admission or push, since the Server may already have revoked the token. A local
completed marker is not sufficient proof: the matching Server receipt is replayed.
Local vault unlock during this phase loads ciphertext only, without pull,
conversion or cursor changes. Writers remain blocked. Terminal plan consumption
removes metadata only; local notes/key/authentication are cleared only after
receipts and a final identity/local-work check. Settings shows progress and
blocks duplicate logout and navigation during the operation.

Repository tests use actual disposable Hive, including close/reopen, with a
synthetic receipt transport. They cover paid/free multi-batch reply loss,
completion loss, partial failures, abort loss, conflict copies, offline/disabled
sync, unsupported Servers, locked hidden notes, cloud-wipe local-only rows,
corrupt plans, tampered snapshots, session changes and mutation races. Transport
tests use mocked HTTP and reject incomplete/malformed receipts. The Settings
widget uses a controlled coordinator to verify confirmation, visible emergency
progress and navigation/input fencing; it does not exercise Hive or native auth.

Verification boundaries: existing CI wire cases are regression coverage, not
live logout acceptance. App/Hive -> real HTTP -> generated Mongo/fake Drive
logout scenarios are the next gate, using the explicit disposable fixture opt-in.
No native keystore/Google logout, signed upgrade, phone action, real Drive write,
production flag, migration, index, deployment or notice is part of this change.

Release must remain blocked on expired/replaced-session recovery of saved plans,
uncertain mutable Drive writes, and live logout acceptance. A saved plan never
silently adopts another session or discards local changes. Old workers that ignore
logout envelopes must be drained before activation; capability preflight alone
does not prove a mixed-worker cutover is safe. The Server feature remains disabled
unless explicitly enabled. Emergency funding is once per logout attempt, as
selected by the owner, and does not bypass note capacity or account/Drive access.
