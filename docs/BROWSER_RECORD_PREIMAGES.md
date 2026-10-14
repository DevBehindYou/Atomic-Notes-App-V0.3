# Inactive owner-fenced exact record comparison

This change is a browser-only persistence seam and disposable Chromium proof. It is not integrated into App startup, Hive, authentication, cloud sync, an actual pending-request journal, or the release WebApp. All six runtime/release acceptance flags remain false.

## Contract

`BrowserOwnerFence.compareAndCommit(expected: context, expectedRecords: predicates, puts: ..., inserts: ..., deletes: ...)` accepts already prepared strings. Every mutation key must have a predicate. Extra predicates are allowed as dependency reads and are not mutated. A string predicate requires an exact native JS string match; no object/number coercion is allowed. `null` means the native record must actually be absent. Native `count(key)` distinguishes an absent key from an existing record whose value is native null. Native null is retained and refused, never interpreted as absence.

Input preparation occurs before opening a native transaction. Each group is separately bounded: at most 256 predicates and 4 MiB UTF-8 predicate keys plus non-null values; at most 256 mutations and 4 MiB UTF-8 mutation keys plus put/insert values. Thus the prepared comparison and mutations may together approach 8 MiB. These are technical operation limits, not user note-capacity or economy policy. Oversized predicate maps are refused before copying. Oversized individual strings are refused before UTF-8 encoding; each accumulated UTF-8 budget short-circuits on overflow. Empty keys, empty predicate sets, missing mutation predicates, overlapping mutations, reserved `@atomic/` keys, invalid contexts and closed connections fail before native transaction admission. Caller collections are detached before admission.

The context read, every count/value preimage read, and all admitted mutations use the SAME readwrite transaction. Mutation enqueue begins only when every predicate matches. No await, encryption, hashing, network, UI prompt or future callback is used while that transaction is active. The future resolves only at native transaction complete. Mismatch, malformed native values, synchronous enqueue errors, canceled-default request errors and native abort reject without partial write or journal removal.

## Why this seam is needed

An owner/epoch alone does not prevent a same-account edit or pending-request replacement while a remote sync response is in flight. A later adapter must retain the exact note and journal records used by the request, prepare result records outside the transaction, then conditionally settle against those exact preimages. A newer same-epoch note or journal must cause settlement refusal and recovery/reconciliation; it must not be marked clean or deleted by the stale receipt. This seam supplies admission mechanics only. It does not define server receipts, replay decisions, encoding, journal versioning, account switching, or recovery UI.

## Disposable verification

`test/browser_record_preimages_test.dart` defines P1–P20. Actual `Note.toMap` JSON plus a synthetic opaque pending request settle together and survive graceful reopen. Cases cover changed notes, replaced journals, absent/native-null and strict nonstring values, missing strings, malformed counts, missing/malformed/foreign/invalid/stale contexts, reserved/oversized/UTF-8 input, matching dependency reads, ordered two-connection edits/settlement/journal replacement, canceled count/mutation request errors, synchronous count/get/put faults, late comparison/write aborts, detached input and closed admission.

Test-only JS fault hooks affect only generated exact database names. Teardown deletes only the owned database, verifies it is absent, restores original native methods and verifies restoration before emitting a fixed cleanup receipt. No real account, note, Drive, server or production database is accessed.

The existing 3 Hive commit/abort, 13 native record, and 15 owner fence cases and their runners are unchanged. The storage workflow also runs 19 strict preimage parser controls and emits only `ci-browser-preimage-proof.json` in `sanitized-browser-preimage-proof`. It binds the exact source head, primitive/fence/comparison/test/lock hashes, Flutter 3.44.8 identity, Chrome identity, exact P1–P20 success bits and per-case owned cleanup bits. Raw compiler/test output stays CI-private and is not included in that artifact.

## Acceptance boundaries

At source preparation, browser outcomes are pending CI. Even a passing run proves only these controlled native IndexedDB cases. Graceful close/reopen is not page reload, forced crash, power-loss durability or true independent-tab leadership. Existing raw same-origin IndexedDB access and the generic boundary can bypass the facade; this is consistency fencing, not an authorization boundary or XSS protection. Production use must route every domain write through a reviewed adapter and prove owner isolation, durable journals, reload/crash/export, quota recovery and cross-tab coordination before browser editing or cloud access is enabled. No dependencies, production migrations, deploys, device actions or signing changes are introduced.
