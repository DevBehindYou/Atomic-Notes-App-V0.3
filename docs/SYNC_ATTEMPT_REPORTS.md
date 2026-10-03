# Caller-owned sync reports

NotesRepository.syncWithReport runs the existing sync flow while collecting
only that caller's submitted upload requests and their optional Server totals.
The existing syncNow boolean and its callers are unchanged. No UI consumes the
new report yet. This change depends on the typed transport from App #29.

Each report is immutable. Requests are keyed by request ID; a recovered pending
request keeps its original mode and is explicitly marked recovered. Totals are
historical operation amounts, not proof of new debits during this tap. Any
missing/malformed receipt or unanswered request makes the overall cost unknown;
individual confirmed receipts remain available. A started receive-only attempt
has zero upload requests. A caller waiting for another sync receives no receipts
belonging to that other attempt. Offline/not-started attempts have no known cost.

Repository lifecycle or transport-session changes retire the report and remove
all receipts and errors before returning, including same-account re-login.
Errors are captured before completion listeners can alter shared state. No
global last-receipt field, persisted receipt history or new storage format is
introduced. A failed pull does not erase the preceding upload receipt.

Proof scaffold 80a164b wraps the pre-existing boolean with an empty report so
the new contract can execute against unchanged sync behavior. All 12 initial
report cases fail there; these are missing-contract demonstrations, not 12
independent production bugs. Three further cases cover a lost later batch,
transport revision before teardown and error snapshot isolation. Existing
repository/transport controls remain required alongside strict full-suite CI.

This is the repository stage of R8. User-facing receipt presentation, actual
wallet/Drive/native behavior and end-to-end release acceptance remain separate.
Prices, requests, note acknowledgements, retry policy and pending persistence
are unchanged. Rollback removes this report API/collector and its model/tests;
the typed transport can remain. Publish against main only after #29 is merged.
