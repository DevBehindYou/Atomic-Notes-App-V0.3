# W2: inactive browser owner/context fence

This facade is part of `browser_record_boundary.dart`, reusing the existing
public native IndexedDB connection, prepared-batch bounds, cursor reader and
complete/abort settlement. It adds no dependencies and is not wired to App
startup, Hive, authentication, repositories, cloud sync or Android. Browser
editing remains disabled.

## Narrow contract

`BrowserOwnerContext` contains an opaque owner hint (1–128 UTF-8 bytes), schema 1
and a monotonically increasing epoch (1 through 2^53−1). It is a local consistency
token, not an authenticated identity. Its encoded record is stored at
`@atomic/context/v1` in the existing `records` store. Guarded data mutations
refuse the complete `@atomic/` namespace, including deletes and add-only inserts.

`bootstrap(context)` can add that record only when a cursor confirms that the
entire store is empty, in the same readwrite transaction. Existing unowned data,
existing contexts and malformed contexts are refused and retained. Competing
first-bootstrap transactions have at most one winner. No automatic adoption,
clearing or owner overwrite exists.

`transition(expected,next)` reads and compares the current context inside the
same readwrite transaction as its context update. Only the same owner and exact
next epoch are permitted. Overflow and cross-owner changes are refused. It never
touches note or journal records. Actual account switching requires a later
per-owner database/export/orchestration design; it cannot reuse a populated
foreign-owner database through this facade.

`commitBatch(expected,...)` validates/copies prepared input outside the native
transaction, then reads and compares the stored context before synchronously
enqueuing the entire batch inside that same readwrite transaction. Missing,
malformed and mismatched context return distinct safe typed failures and abort
without note/journal changes. No await, network or crypto work runs inside the
active transaction callback. Saving is acknowledged only at native complete;
request success is insufficient, and an abort rolls back the complete batch.

`readSnapshot(expected)` verifies context before opening its cursor in the same
readonly transaction. It returns no rows on a missing/malformed/stale/foreign
context. The context row is omitted from returned domain data and excluded from
the inherited 256-domain-row/4-MiB snapshot budget. It refuses oversized domain
views rather than truncating them. These are experimental technical caps, not
account capacity or financial policy.

## Deliberate limitations

The low-level unconditional boundary and direct same-origin script access can
bypass/modify this local token. This is not authentication, XSS protection or a
cross-tab leader/lock. Two browser connections in one test execution context do
not establish tab leadership, process crash recovery or disk durability.

An unchanged epoch does NOT imply unchanged note/journal contents. Guarded commit
does not compare record preimages. A future sync journal must additionally check
exact expected note/journal records (including expected absence) in the same
transaction before admission or settlement. It must not clear dirty flags or
remove pending requests based only on this owner token. No server replay,
request hashing, cloud call, authentication or vault operation is implemented.

## CI proof and release boundary

The existing three Hive characterization cases and thirteen native-boundary
cases remain unchanged. The owned Chromium storage job additionally runs the
fourteen exact F1–F14 cases in `test/browser_owner_fence_test.dart`. They cover
reopen, missing/malformed context retention, competing first owners, stale reads
and writes, reserved/invalid preflight with no transaction, same-owner transition,
cross-owner/overflow refusal, both ordered two-connection races, exactly one
concurrent transition winner, late abort rollback, domain caps and closed
admission. Every case closes/deletes only its generated database, checks absence,
and restores all test-only prototype hooks before its fixed cleanup receipt.

`sanitized-browser-owner-proof/ci-browser-owner-proof.json` contains only twenty
fixed fields: version, scope, sourceHead, phase, outcome, flutterVersion,
chromeVersion, primitiveSha256, fenceSha256, testSha256, lockSha256,
browserExitCode, cases, cleanup and the six disabled acceptance flags. Nineteen
parser controls reject incomplete/duplicate/unknown/skipped cases, malformed
terminal/loading events and unowned cleanup. Raw records and logs are not exported.

Local verification is formatter/parser checks only. Actual browser claims require
exact-head CI, review and repeated merged-main proof. Editing/cloud, production
adapter, page reload, forced crash and cross-tab acceptance flags remain false.
Actual browser reload/crash, natural quota/denial, eviction, multi-tab ownership,
non-Chromium coverage, export fallback, session/vault lifecycle and Android–Web
synchronization remain mandatory before browser editing is enabled.
