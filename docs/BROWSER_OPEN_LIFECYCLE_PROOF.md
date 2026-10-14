# W2: owned browser opening lifecycle proof

This is a separate CI-only test suite for the existing inactive
`BrowserRecordBoundary.open` implementation. It changes no primitive, startup,
Hive dependency, note repository, authentication or cloud behavior. The existing
three Hive tests and thirteen record-boundary cases remain unchanged. Browser
note editing remains disabled.

## Five exact cases

1. **O1 native delete queue times out and aborts late schema upgrade:** an owned
   version-1 connection deliberately ignores its native version-change event.
   A real native delete request becomes blocked behind it. The boundary's open
   request queues behind deletion, returns `openTimedOut` after five seconds,
   then observes a late upgrade when the blocker closes. That upgrade must abort;
   the late native request errors and the owned database remains absent.
2. **O2 native upgrade queue times out and closes late successful connection:**
   native successful readonly requests keep an owned version-1 schema upgrade
   active. A second native open waits behind the upgrade and times out. Releasing
   the request chain commits the initial upgrade and closes its connection. The
   queued open succeeds late. Its connection must already have been closed by
   the boundary: an owned delete must succeed without closing the observer's
   handle and without a blocked event. Keepalive is bounded by 500,000 requests
   and a 14-second wall-clock deadline; wait helpers have ten-second bounds.
3. **O3 synthetic unavailable IndexedDB returns safe failure and recovers:** a
   test-only global getter returns null. Opening returns only typed `openFailed`;
   restoration permits a fresh open, commit and snapshot.
4. **O4 synthetic denied IndexedDB getter returns safe failure and recovers:** a
   test-only getter throws a public synthetic `SecurityError`; the same typed
   failure and successful restoration are required.
5. **O5 synthetic denied owned factory open returns safe failure and recovers:**
   a factory-method hook throws only for the exact owned database name; typed
   failure and recovery are required.

O1 and O2 use actual native IndexedDB queue/upgrade events and the primitive's
real timer; no synthetic open events or global timer overrides are used. O3–O5
are explicitly injected conditions, not proof of an actual denied browser policy.
The fixed version-1 open cannot naturally require an upgrade of an existing
version-1 database, so `openBlocked` is not claimed as reproduced. O1's blocked
event belongs to the real delete request, not the boundary open request.

## Isolation, artifacts and acceptance

Flutter launches Chrome against its generated local test origin in CI, never a
production site. Names are generated solely for these synthetic cases. No real
notes, accounts or device storage are accessed. Finally paths release keepalive,
close all owned handles, restore the original factory method and global getter
descriptor, delete exactly the owned database and check its absence. Each case
emits one fixed cleanup receipt only after restoration and absence are checked.

The separate `browser-open-proof.yml` workflow pins Flutter 3.44.8 and the
existing lockfile. It runs twenty-one parser controls and this five-case suite.
`sanitized-browser-open-proof` contains only `ci-browser-open-proof.json`.
Raw test/compiler output and synthetic records never enter the artifact.

The fixed nineteen-field schema is `version`, `scope`, `sourceHead`, `phase`,
`outcome`, `flutterVersion`, `chromeVersion`, `primitiveSha256`, `testSha256`,
`lockSha256`, `browserExitCode`, `cases`, `cleanup`, `appEditingEnabled`,
`cloudEnabled`, `productionAdapterAccepted`, `pageReloadProved`,
`forcedCrashProved`, and `crossTabProved`. The last six remain false. A proof
requires all five case values and all five cleanup values true, successful SDK
identity and source/hash checks, a successful terminal event and exit code zero.
Unknown, duplicated, skipped, incomplete or malformed test streams cannot pass.
Only failing reports may additionally contain `failureStages`, mapping a failed
known case to its last fixed public fixture marker. Native messages, unknown
markers, records and completed successful cases are never retained.

Local validation comprises formatting and parser controls only. Browser claims
require exact-head CI, independent source review and repeated merged-main proof.
This suite does not prove reload/crash durability, quota exhaustion, cross-tab
ownership, browser eviction, physical disk flush or browser note editing. It does
not replace the owner fence, durable sync journal, export, vault and cross-platform
synchronization work required before WebApp release.
