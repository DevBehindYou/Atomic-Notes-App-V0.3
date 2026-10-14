# W2: inactive native browser record boundary

This primitive is not imported by startup, repositories, Hive, authentication,
cloud sync or Android code. Browser editing remains disabled. It uses Dart's
existing public JS interop and native IndexedDB, without adding dependencies.
It is a bounded storage building block, not a production notes adapter.

## Contract

`commitBatch` copies prepared string records before admission, refuses empty,
overlapping or empty-key batches, and caps one admission at 256 operations and
4 MiB of UTF-8 keys plus values. Puts, add-only inserts and deletions share one
native transaction. A successful individual request never acknowledges saving:
the future settles only at transaction completion or abort. Request failures
explicitly abort even if another listener cancels the browser's default action.
Synchronous enqueue failures also abort earlier admitted requests.

`readSnapshot` pairs cursor keys and values in one readonly transaction and
returns a detached immutable map after completion. Non-string/empty-key records,
more than 256 rows or more than 4 MiB of aggregate UTF-8 reject the whole result;
the method never returns a truncated snapshot. These technical bounds are not
note-capacity or economy policy.

Close fences subsequent admissions without canceling already admitted native
transactions. Version changes close the connection. Opening validates the fixed
store, refuses missing schema instead of repairing it, and reports safe typed
errors without retaining native messages, database names or record contents.
The five-second opening timeout closes late successful connections and aborts
late schema upgrades. Timeout and blocked-opening behavior remain source-reviewed
but are not reproduced by this real-browser suite.

## CI proof

The existing Hive behavior probe and its three cases remain unchanged. The same
owned Chromium job additionally executes `test/browser_record_boundary_test.dart`
through `tool/run_browser_record_proof.py`. No local Flutter/browser execution is
required. The new fixed artifact is `sanitized-browser-record-proof`, containing
`ci-browser-record-proof.json`; raw output and synthetic records are never
exported. Nineteen parser controls reject incomplete/duplicate/unknown/skipped
case streams, loading failures, malformed terminal events and unowned cleanup.

Thirteen exact cases cover:

1. **B1:** note and journal commit acknowledgment follows native completion;
   subsequent caller-map mutation does not change admitted data; detached
   immutable snapshot survives graceful close/reopen.
2. **B2:** abort after successful requests refuses saving and preserves previous
   committed values and the caller's exportable draft.
3. **B3:** duplicate add request error, with its browser default action canceled
   by a test listener, still aborts the whole batch.
4. **B4:** synchronous enqueue fault after an earlier put rolls back the batch.
5. **B5:** committed deletion keeps unrelated records after reopen.
6. **B6:** empty, overlap, empty-key, row-cap and UTF-8-cap preflight failures admit
   no native write transaction and leave the sentinel unchanged.
7. **B7:** malformed native value refuses the whole snapshot with a safe code.
8. **B8:** native-seeded row 257 and aggregate UTF-8 overflow refuse the snapshot
   rather than returning a partial view.
9. **B9:** one readonly snapshot remains coherent while another connection queues
   a write; a later snapshot sees the new paired values.
10. **B10:** close refuses new admissions while a pending commit settles.
11. **B11:** native version change closes the connection; opening a lower version
    returns a safe failure.
12. **B12:** missing store and invalid database name are refused.
13. **B13:** a thrown schema callback returns a safe failure and aborts upgrade;
    a later successful reopen demonstrates recovery; exact owned deletion in
    teardown verifies that no connection remains to block cleanup.

Fault hooks modify native prototypes only for an exact generated database name.
Every case closes its connections, deletes exactly its owned database, checks
absence, restores all altered methods and verifies restoration before emitting
one fixed cleanup receipt. The prototype hooks are test-only; no application code
imports them. B9 exercises two connections in one browser execution context; it
does not establish cross-tab exclusive writers or owner isolation.

The report's fixed 19 fields are `version`, `scope`, `sourceHead`, `phase`,
`outcome`, `flutterVersion`, `chromeVersion`, `primitiveSha256`, `testSha256`,
`lockSha256`, `browserExitCode`, `cases`, `cleanup`, `appEditingEnabled`,
`cloudEnabled`, `productionAdapterAccepted`, `pageReloadProved`,
`forcedCrashProved`, and `crossTabProved`. The last six are always false.

## Verification boundaries and remaining dependencies

Local checks comprise formatting and parser controls only. Real-browser claims
require exact-head CI acceptance and repeated merged-main proof. Forced abort
is deterministic injection, not naturally exhausted quota or a power-loss test.
Graceful close/reopen does not prove page reload, process crash, browser eviction,
physical disk flush, non-Chromium support or multi-tab recovery.

Still required before browser note editing: owner-scoped durable adapter, actual
note serialization and migration, journal/replay protocol, reload/crash recovery,
quota/denied-storage handling, exclusive writer handoff, export fallback, session
and vault transitions, and Android/Web/Android synchronization. The primitive's
whole-store 256-row/4-MiB snapshot caps are an intentional experimental boundary;
a production adapter must define appropriate domain bounds and complete views.
