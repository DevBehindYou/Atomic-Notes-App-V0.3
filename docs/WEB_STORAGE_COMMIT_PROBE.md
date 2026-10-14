# W2: real browser storage commit boundary probe

This slice tests the locked Hive CE 2.20.1 browser implementation using real Chromium. It adds no runtime adapter, dependency, App editing/authentication/cloud path, service worker, or deployment. The production browser entry remains the existing development gate.

## Source-first boundary

The earlier exact-archive audit found regular Box writes await request success, while the native IndexedDB transaction may still abort. `flush()` does not await that transaction. This CI probe observes the real dependency through native prototype hooks scoped to a generated, disposable database namespace. It does not replace Hive with a JavaScript model.

Three fixed cases:

1. A synthetic checklist with Unicode, completion state, dirty/pinned state, version and signature is saved using the existing `Note.toMap`; after native transaction completion and graceful Box close/reopen, `Note.fromMap` reproduces it exactly.
2. Deterministic abort in the native put-request success listener exposes the difference between successful Hive `put`/`flush` futures and transaction settlement. The Box's memory still reports the new value; a fresh Box reopening has no committed value. The caller-owned synthetic draft remains available.
3. Abort after the second successful request of `putAll` leaves neither record committed after reopen. This shows transaction atomicity while exposing the weaker public completion boundary.

An observed early-success/late-abort case **passes the dependency behavior probe**; it does not declare that behavior safe for a production WebApp. The abort is explicit fault injection, not natural quota exhaustion or a reproduction of Android data loss.

All cases close Hive connections, delete only their generated namespace, verify no matching IndexedDB database remains, and restore native methods. The runner exports fixed case/cleanup bits, source/SDK/browser/package identities and lock hash; no record contents, database names, raw streams or bundles leave CI.

## Verification and next dependencies

Local verification is limited to Dart formatting and proof-parser controls. Real Chrome outcomes must be accepted from exact-head CI before declaring these observations reproduced.

**Not proved:** actual page/process reload, forced crash/power loss, browser eviction, denied/quota/block/version-change errors, BoxCollection, coherent snapshots, two tabs, writer handoff, journal/replay recovery, owner transition, Android/browser sync, non-Chromium browsers or a production durable store. Graceful close/reopen is explicitly different from crash recovery.

Next W2 work must design a reviewed browser commit boundary that waits for native transaction completion and observes abort/error, plus coherent reads and one-writer fencing. Prove page/crash/reload and owner/journal boundaries before browser editing or HTTP admission. Existing Android storage behavior remains unchanged.
