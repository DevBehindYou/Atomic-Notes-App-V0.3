# Preserve push operation receipts at the transport boundary

The Server returns row acknowledgements plus charged/refunded amounts. The App
previously reduced that response to its results list. ApiClient.pushNotes now
returns PushReply: the same row results, the submitted request ID and mode, and
an optional PushReceipt containing the Server's nonnegative integer totals.
Refunds cannot exceed the recorded charge. Missing or malformed billing fields
mean unknown cost, without discarding otherwise valid note acknowledgements.

A replay returns the original operation's historical totals. Those amounts are
not a new wallet debit for each HTTP attempt. The refund may be capped by the
wallet's remaining energy capacity. Clients must not reconstruct it from a
fixed price, infer free sync from absent fields, or sum retries as new charges.

This is transport preparation for R8. NotesRepository consumes reply.results
with its existing acknowledgement, persistence and conflict behavior. It does
not yet publish receipts to the UI. No wire fields, prices, Server behavior,
pending-request storage or dependencies change. Existing session binding
rejects a late reply before its receipt is decoded, including same-account
re-login.

Before-proof dd4d1ca on main f575618: 13 receipt-contract failures and two
controls passing. The final fixture also includes a cap-limited refund and
mixed accepted/rejected rows. Targeted tests verify ordinary failure, session
retirement, legacy responses, request identity/mode and row preservation.
Strict analysis, the full suite and CI/debug APK remain required on this PR.

R8 remains partial until operation-level aggregation and accurate UI reporting
are separately verified. This fixture cannot prove a real wallet debit, device
keystore behavior, actual Drive results or production replay safety. Rollback
reverts the typed reply and both callers together; no data migration is needed.
