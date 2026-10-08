# Cloud wipe and sync ordering verification

## Confirmed defects and causal baseline

On App main `674cebd276f9f332c4a94ce2a5f1a2f4fbb0c772`, test-only
commit `5170f7f71feb0e2a3e5bed717148a32938f6e11e` leaves production code
unchanged and reproduces five failures, with two controls passing:

- Wipe calls the API before an in-flight push reply is consumed.
- Another sync can begin while the wipe request is pending.
- A late wipe reply resets cloud versions in a newer repository lifecycle
  for the same account.
- A sync waiting for connectivity can start after a completed wipe, using
  an intention formed before the wipe.
- Two overlapping wipes issue two API calls.

The normal successful-wipe and failed-wipe preservation controls pass before
the fix. The first attempted run could not compile because this fresh review
worktree lacked the ignored credential stub; that is not causal evidence.
The stub is copied only from the tracked public `cred.example.dart`.

## Correction

`lib/database/notes_repository.dart` fences sync admission during a cloud wipe,
retires connecting attempts using a runtime wipe revision, and consumes an
earlier sync's result before requesting deletion. Wipe captures both repository
lifecycle and API session revision; a late response cannot reset a newer
session's local cache. Overlapping wipes are refused. Busy state includes wipe.

Local text, dirty flags and the existing Hive format remain intact. A current
successful wipe resets cloud versions/signatures and forgets the obsolete saved
push. A failed request preserves the cache. Automatic dirty-work scheduling
resumes under the existing sync policy when the wipe ends; this does not promise
that the cloud remains empty while dirty local work is eligible to upload.

This is a client ordering correction. Another device or an old Server worker
can still race deletion. A response retired locally may already have completed
remote deletion; no rollback of that deletion is claimed.

## Verification

Eight isolated Flutter/Hive lifecycle cases cover the five reproduced defects,
two existing-behaviour controls, and an additional same-owner API-session change.
The first corrected seven-case run and strict analysis passed. Final local
verification with Flutter 3.44.8 passes all 488 tests, with 22 dedicated live
wire cases intentionally skipped, and strict analysis finds no issues.
CI results are recorded in the PR and root acceptance report.

`test/server_wire_integration_test.dart` adds
`cloud_wipe_waits_for_committed_reply_and_preserves_local_reset`: a transport
barrier fully receives a real successful push reply after commit, then withholds
it while the App requests a wipe. Deletion must not start before reply release.
The case checks local text and Hive version reset, removal of the pending
request, one ten-energy charge, no charge for wipe, cloud metadata removal and
other-owner isolation. The generated owner's budget is restored using the real
admin route with a fixed public loopback-only fixture key, before the measured
baseline. It does not grant production energy.

The two CI jobs run concurrently. The wire job pins verified Server main
`25b89e46b7efa18efe33a6d1596b46d04dcd1d0f` (Server #55), whose main run
`37799905348` passed. Only the fixed-code `sanitized-server-wire-proof` artifact
and workflow metadata are used for acceptance; raw CI logs and compiler
artifacts are not retrieved.

## Boundaries

The wire fixture uses real Flutter API/repository/Hive/Cubit, actual notes,
auth and admin routes, generated disposable MongoDB transactions, and fake
Drive. It is not a native Android keystore, OAuth, real Drive, two physical
devices, signed upgrade or production-deployment proof. Local live wire tests
are intentionally skipped without the dedicated loopback fixture. The debug
APK is built in CI only. Production recovery modules remain inactive.
