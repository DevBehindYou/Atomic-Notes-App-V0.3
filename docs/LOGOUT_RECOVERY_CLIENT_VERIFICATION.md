# Read-only logout recovery client boundary

10 October 2026. This change adds transport and validation only. It does not
enable production logout, reauthenticate a user, adopt a previous plan, apply a
receipt, erase Hive, or complete/revoke a session. A completed status is advisory.

## Code boundary

`lib/api/logout_recovery.dart` accepts existing immutable envelopes, requires
one attempt, unique request and note IDs across at most five batches, and sends
only the prior session hash and the manifest. Metadata is capped at 16 KiB;
note text, ciphertext, owner IDs and raw previous tokens are not transmitted.

The status decoder requires exact object keys, matching attempt and ordered
request IDs, one summary per batch, safe nonnegative integer amounts/counts,
accepted plus failed equal to the frozen row count, refund no larger than charge,
zero refund for all-success receipts, uniform historical charge, and no failed
rows for a completed attempt. Historical amounts are summaries, not a price
decision or evidence of another debit. The Server still decides funding.

`ApiClient.inspectLogoutRecovery` retains the existing session-revision fence,
including same-account replacement. Its response stream is capped at 16 KiB
without trusting Content-Length, is cancelled on overflow, and uses strict UTF-8
before JSON decoding. Other endpoints keep their existing response policy.
Malformed/disabled/ambiguous status has no write or completion fallback.

The bounded transport has the existing request timeout semantics; it does not
introduce a general transport cancellation redesign. Full result IDs, versions
and timestamps are intentionally absent from this summaries-only DTO. They must
be validated in a distinct future immutable-receipt transport before recovery
can authorize durable local reconciliation.

## Verification intended for this PR

- Dedicated mock controls cover query immutability, duplicates, foreign attempts,
  the maximum 250-row manifest, malformed identities/counts/refunds/states,
  ordered multi-batch summaries, no fallback, boundary/oversized/invalid UTF-8
  replies, cancellation with a false Content-Length, and delayed same/different
  owner replies. They cannot verify real native secure storage or Google login.
- A separate real HTTP/Hono/Mongo inspection scenario prepares and durably saves
  a real Hive note/plan, proves active old-session refusal leaves the diagnostic
  wallet/note/ledger/Drive counts unchanged, accepts a real logout push, completes
  that old session, reopens Hive without consuming local state, then inspects and
  repeats inspection using another pre-seeded same-owner session. Both replies
  leave the dirty note, completing plan, new local auth, wallet/ledger/notes and
  fake Drive counters unchanged. This is not a user reauthentication test or
  complete expired-session recovery implementation. Server #65 separately tests
  full session/attempt/operation snapshot immutability.
- The existing 22 regression cases and seven logout scenarios remain separate.
  CI pins accepted Server #65 main `cd66983e3119b85912abf6d73563aee5e337fd5c`.
  The new fixed-schema artifact is `sanitized-logout-recovery-server-wire-proof`.
  Only fixed phase/outcome/cleanup codes are exported; no identifiers or contents.
- CI strict analysis, all Flutter tests, debug APK and the independent real-wire
  job must all pass at the exact PR head; exact merged-main CI is a separate gate.

No new local analysis/test pass is claimed. The installed SDK is used only for
direct Dart formatting because the shared package cache is incomplete. No SDK
refresh, package installation, local APK, phone, production database/index,
deployment, signing, migration or rollout flag change is part of this PR.

Fresh same-owner reauthentication, transactional settled-only recovery commit,
immutable acknowledgement delivery/application, crash/concurrency proofs,
ambiguous or missing receipts, plans over 250 rows and rollout drain/rollback
remain separate work. This transport does not satisfy those release gates.
