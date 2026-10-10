# Client validation of retained logout receipts

10 October 2026. Transport/decoder only; no reauthentication, plan adoption,
handoff commit, Hive acknowledgement application or local erasure. The Server
feature gate remains default off. Receipt delivery alone does not authorize any
of these operations.

`ApiClient.readLogoutRecoveryReceipts` sends the existing metadata-only query to
the distinct receipt endpoint, using the existing session-revision fence and
bounded strict UTF-8 transport with a 128 KiB response limit. Historical charges
and refunds do not cause or represent a second debit on an HTTP replay.

`LogoutRecoveryReceipts.parse` requires exact top-level/batch keys, matching
attempt and ordered request IDs, all exact unique frozen note IDs and one result
per submitted row. Results are detached typed immutable values. Success requires
a positive safe integer version and a valid UTC ISO time; failure requires a
bounded fixed-code error. Optional sequence/version values must be positive
safe integers and unchanged must be boolean. Unknown fields, malformed/partial
results, duplicate/foreign note IDs and unsafe values fail closed. Counts and
state/charge/refund invariants reuse the existing status decoder.

UTC timestamps accept current Server ISO milliseconds or whole seconds, and
must round-trip exactly. Dart normalizes impossible dates; those must not become
valid acknowledgements. Legacy/noncanonical timestamp formats are refused and
local notes remain retained rather than guessed or rewritten.

Dedicated mock tests cover immutable projection, accepted/conflict/failed rows,
optional original metadata, invalid identities/types/times/refunds/states/errors,
bounded/malformed/disabled replies without fallback, and delayed same/different
owner replacement. They are not native keystore/Google login tests.

The existing read-only real-wire scenario now additionally fetches and replays
retained acknowledgements after a real paid push and completion, compares IDs,
version/time/sequence and historical cost/refund to the original reply, and
reasserts reopened Hive dirty note/plan, current local auth, wallet/ledger/notes
and fake Drive counters unchanged. Its sanitized artifact scope explicitly says
status **and receipts**. The separate 22 regression and seven logout cases remain
unchanged; the total is still 30 live scenarios, not 31. Fixture is pinned to
accepted Server #66 main `cc7b937f5b8dcb185788d9807effe5d45c8d11a9`.

Strict CI analysis, all Flutter tests, debug APK and wire checks must pass at the
exact PR head, followed by exact merged-main CI before copying files. Local Dart
formatting only: no current local analysis/tests are claimed, because the shared
package cache is incomplete. No install, refresh, local APK, production data,
index, migration, deployment, flag, signing, phone or real-account action.

Full acknowledgement parsing is a necessary recovery boundary, not completion
of the recovery feature. Manual same-owner reauthentication, transactional
session/attempt fences, durable local acknowledgement through the write queue,
newer-edit/conflict retention, lost-reply/restart proofs, uncertain/missing
operations, over-250 plans and rollout drain/rollback remain separate gates.
