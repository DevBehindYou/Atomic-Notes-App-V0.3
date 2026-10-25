# B05 first increment: conflict preservation

Approved scope: preserve local work while settling an ordinary sync conflict.
Base: `4c7542d95e1bc9bb936f8b82ff2903fa2d87913e`.

## Design

Capture a deep note snapshot before any preservation await. A conflict copy
contains the captured checklist, content, importance and pin state. A deleted
source stays a dirty tombstone and creates no live copy. Its definitive failed
result follows existing terminal cleanup so other rows and pulls can proceed.
Reuse a deterministic
copy only when its content and pending state match; otherwise persist and flush
a new local conflict ID without changing request ID, mode or rows. Never replace
an existing edited or deleted note. Retry a reused copy's persistence, then flush
before clearing an unchanged original. Recheck source identity, signature,
timestamp and deletion state and account/session/lifecycle/wipe/request identity
after awaits; retire settlement when its authority changes.

## Implementation and verification

- [x] Add real-Hive causal tests for edited/deleted existing copies, source
  edit/delete/restore during encryption, write/flush failure and same-instance
  or reopened retries. Observe failures on the unmodified base.
- [x] Change only ordinary conflict settlement in `lib/database/notes_repository.dart`.
- [x] Run the new test file with `C:/dev/flutter/bin/flutter.bat test --no-pub`.
- [x] Run strict analysis and the existing HTTP, acknowledgement, lifecycle and
  logout recovery tests.
- [x] Obtain final independent approval after resolving the initial
  account-wide replay-starvation finding.

No remote schema, pricing, vault KDF, B02 classification or new journal version.
This increment does not prove T07 actual process death: durable receipt/checkpoint
settlement and actual termination/relaunch testing remain later B05 work.

## Evidence and remaining boundary

The initial ten cases all failed on unmodified production code. Two additional
causal cases proved that editing/deleting the preserved copy during encryption
also required retaining its source. The expanded file has 24 cases covering
source edit/delete/restore during encryption, put and flush; copy edits/deletes;
session/lifecycle/request/lock/wipe changes; and same-instance/reopened put/flush
failure retries. Reopening closes/reopens synthetic Hive fixtures; it is not
process-death evidence.

The existing lifecycle test at `test/notes_repository_lifecycle_test.dart:472`
explicitly expected a deleted source to become a live conflict copy. That old
behavior contradicts the approved no-resurrection rule. Its contract now requires
the original dirty tombstone/base version to remain, with no live copy or pull
replacement of that dirty source. The known completed operation is retired through
the existing failure path. Other successful rows settle and a cursor-reset pull
receives unrelated cloud work. A causal test checks same-batch success, later
push/pull across reopen, fresh request identity, and the existing Recycle Bin
restore action returning the note to normal conflict handling.

Deletion intent is preserved but unresolved; sync reports incomplete and asks for
review in the Recycle Bin. Manual retries create new requests under the existing
charging/refund contract. The tests retain each attempt's reported charge without
inventing a refund or treating later requests as free. There is no new automatic
retry or delete-wins rebasing policy. Logout can still refuse unresolved work.
The real two-client Server wire test applies the same no-resurrection rule to a
stale local deletion against an accepted remote edit. It checks the complete
local tombstone and persisted Hive row remain unchanged, the known operation
clears, and the accepted remote body/version survive. After closing/reopening the
client's Hive box, a fresh manual request can settle another local note and pull
unrelated remote work while preserving the unresolved tombstone. A refused-only
request reports the actual Server's 10 charge and 10 refund; a mixed request with
one successful row reports 10 charged and no refund. The opposite stale edit
against a remote tombstone still preserves the edit in a live conflict copy.
The existing logout recovery path also validates its immutable plan conflict ID
against pending metadata. Retargeting an occupied copy ID followed by interruption
can leave those IDs different and conservatively block logout recovery; resolving
that pre-existing plan/mapping interaction remains part of the later journal work.

Installed Hive CE 2.20.1 was inspected locally. `BoxBase` documents put futures
as backend-write completion, and VM `StorageBackendVm.flush` serializes writes
before `writeRaf.flush`. Preservation awaits the individual `_persist` result and
then flushes; it never treats the error-swallowing queue tail as write success.

Final local gate (all commands used `PUB_CACHE=C:/dev/pub-cache` and `--no-pub`):

```powershell
C:/dev/flutter/bin/flutter.bat analyze --no-pub --fatal-infos --fatal-warnings
C:/dev/flutter/bin/flutter.bat test --no-pub test/sync_conflict_preservation_test.dart test/sync_http_repository_test.dart test/push_ack_boundary_test.dart test/push_ack_validation_test.dart test/notes_repository_lifecycle_test.dart test/logout_orchestration_test.dart test/logout_same_owner_recovery_test.dart test/logout_same_owner_wire_integration_test.dart test/logout_recovery_test.dart test/logout_recovery_receipts_test.dart test/r2_logout_causal_test.dart --reporter expanded
```

Analysis: no issues, exit 0. Final combined tests: 206 passed, 2 explicitly skipped, exit 0.
The two skips require the dedicated same-owner loopback fixture origin and
selected recovery case; this local gate does not claim those integration cases.
