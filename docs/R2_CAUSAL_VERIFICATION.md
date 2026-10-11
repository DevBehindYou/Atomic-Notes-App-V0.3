# R2 busy-sync logout: bounded historical causal proof

This test-only work closes the previously unrecorded **R2 failing-before
provenance** if the exact candidate and merged-main gates pass. It does not
change production code, account policy, prices, storage, or the logout protocol.

## Actual source and common scenario

**Verified in code:** historical commit
`2cdc0516935b0ae9b8d7770efcf0d66ae1b8b55a` is the parent of R2/R3 fix
`575fcaed834a8803d0e5e6d73292aea14958bfb5`. Its repository has the previously
approved `forTest` injection seam, but `syncNow` returns `true` immediately
when a sync is already active, `stop` does not await that sync, and `clearLocal`
clears dirty Hive rows. The historical SettingsPage calls `syncNow`, then
`stop` and `clearLocal` if sync reported success. The runner pins the commit
and SHA-256 hashes of that actual repository, SettingsPage and historical
fake prefix. It does not reconstruct or selectively reintroduce the defect.

**Verified in current code:** repository callers join an active sync and check
remaining dirty/pending state. `clearLocal` drains writers and refuses dirty
or pending rows. The existing R2 lifecycle test checks current behavior, but
the historical Wave 1 before table did not record an R2 execution.

The same three test bodies execute against two owned temporary packages:

1. Pause the actual first repository upload after snapshot capture. Save a
   second note through the actual serialized Hive writer. Invoke another
   `syncNow`. Only if it prematurely reports success, call actual `stop` and
   `clearLocal` in the source-verified historical Settings ordering. The
   historical preservation assertion must fail, with fixed observations
   `early_success` and `erased`; current source must pass with `waited` and
   `preserved`, with the later row still dirty and absent from captured uploads.
2. A control confirms the first snapshot contains only its first note, the
   later row remains dirty after release, and it was never uploaded.
3. A control confirms acknowledged clean notes can still be cleared.

**Verification boundary:** this is real repository/Hive causal evidence with a
fake API and synthetic vault. The Settings ordering is source-verified and
called through repository methods; no actual Settings widget click, native
Google sign-in, real Drive, keystore, phone, signed upgrade, or two-device
acceptance is claimed. The common scenario tests outcomes, not a copy of the
fix. Historical/current fake API adapters reflect their actual interface
versions; both use the same test body and assertions.

## Isolation and evidence

The runner exports only dependency-reachable public Dart source from the
fixed historical commit or the checked-out candidate, never a credential
file. `cred.dart` is created exclusively from tracked public
`cred.example.dart`. It reuses CI's already resolved, locked dependency
configuration with relocated package paths; no extra dependency resolution,
installation, bootstrap or cache refresh occurs. Repository-only temporary
packages omit artwork declarations while retaining the same dependency
manifest/lockfile. No source in the candidate checkout is replaced.

Every paused test releases its gate and drains its futures in `finally`.
Isolated Hive boxes close and owned directories are removed in teardown.
The outer runner removes both packages, reports and any remaining owned
data even after failures/timeouts. CI publishes only
`ci-r2-causal-proof.json`: fixed phase/outcome codes, three fixed case results,
allowlisted observations, cleanup results and public historical hashes.
Official JSON file-reporter events are private, UTF-8 bounded to 4 MiB per
phase, never printed or uploaded, and removed. Compilation failure, missing
cases/observations, skips, wrong terminal/process outcomes, malformed events,
duplicate markers or failed cleanup cannot satisfy the proof.

## Required acceptance

Before phase must show one expected preservation failure and two passing
controls; after phase must show all three passing. Both require their exact
observations and all cleanup results. The overall proof passes only when
those contrasting expectations match. Parser controls run first. Existing
strict analysis, full tests, debug APK and all eight previous preservation/
branding proof artifacts remain required and unchanged. Local parser/static
checks do not substitute for CI execution. Exact-head CI, root review, merge
and exact-main CI are pending at the time of this source report.
