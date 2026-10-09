# Durable logout plan verification

The App now has an unused, bounded logout-plan builder and Hive store. This is
preparation for repository/UI orchestration; it does not change the logout button.

Plans contain frozen normalized push envelopes, request/attempt IDs, a hashed
session binding and local acknowledgement/conflict-copy metadata. They split at
50 rows and 2,500,000 complete UTF-8 envelope bytes, with at most five batches.
Oversized plans refuse as a whole. Protected rows must already be sealed and
cannot retain plaintext alongside their ciphertext. No raw session token or key
is accepted by the plan schema. The caller still owns encryption and session fencing.

Restoration recomputes every fingerprint and byte count, validates owner/session,
unique IDs and complete acknowledgement metadata, and refuses damaged state.
The Hive store checks the cache owner, serializes its writes, flushes before
returning, allows exact replay, and refuses to overwrite another pending plan.
It has no API to delete notes or authorize logout. The repository must own one
store instance and quiesce external writers; this is not a global Hive lock.

Verified locally: strict analysis and 518 tests passed, including eleven new
cases. Twenty-two live wire cases are skipped locally and run in CI. The new
tests exercise actual disposable Hive close/reopen, exact replay, overlapping
save refusal, corrupt-record retention, foreign/newer-session refusal, row and
UTF-8 splitting, plan bounds, snapshot identity and protected content checks.
Ciphertext in the storage tests is a public synthetic sentinel, not a crypto test.

Remaining: integrate the store and its reserved key into repository lifecycle and
cache guards, obtain the current hashed session binding from ApiClient, freeze
writers, reconcile earlier pushes, apply receipts safely, resume interrupted
attempts, and connect Settings with clear paid/emergency/retry messages. No
current production caller stores these plans. Actual App-to-Server interruption
and native upgrade acceptance are not established by these local tests.
