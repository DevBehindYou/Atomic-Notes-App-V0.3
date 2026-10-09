# Logout lifecycle and completion markers

This prepares safe orchestration; Settings still uses the existing logout flow.
There is no production caller creating a logout plan yet.

`ApiClient.logoutSessionHash` exposes only a SHA-256 binding for the current
token. It is stable across restart and changes on a new login. Before completion
HTTP, ApiClient persists a bound completion marker in existing secure storage.
Until resolved, ordinary authenticated requests are refused locally. A prior
in-flight 401 cannot clear the token needed to replay a lost completion response.
The same attempt can retry after initialization; a different attempt cannot
replace it. Explicit incomplete/unavailable replies reopen normal reconciliation.
Unknown transport failures and ambiguous replies retain the marker. New sessions
do not inherit an old token's marker. No raw token/key is added to Hive or logs.

Hive plan progress advances from prepared to completing to completed. Completion
intent must precede acknowledgement and cannot regress through ordinary save or
replay. These are local progress markers, never independent proof of a Server
commit and never permission to delete notes. Callers must validate actual receipts.

Any reserved logout-plan key, including null/corrupt data, blocks cache erasure,
foreign-account replacement, cloud wipe and ordinary sync. A version-zero note
included in an unresolved logout remains dirty when deleted: its first upload may
already have reached the Server. Guards remain safe before Hive initialization.

Verification uses mocked HTTP/secure storage and actual disposable Hive. Cases
include restart after completion response loss, an earlier ordinary 401, invalid
identity, incomplete reply, replacement attempt refusal, phase persistence and
monotonicity, corrupt/foreign records, cache/account/wipe guards and deletion of
an uncertain upload. Existing Danger Zone tests caught an early guard accessing
Hive before initialization; the guard now checks cache readiness. An earlier
full run overlapped a source edit and is not accepted as a final-source gate.
The final stable source passes strict analysis and all 531 local tests (22 live
wire cases skip locally). CI live regression and debug APK remain merge gates.

Unfinished: acquire the repository's complete writer/session fence; reconcile
previous paid requests; assemble/unlock all unsent rows; apply receipts and
conflict copies; finish/abort plans safely; connect Settings and explanatory UI;
handle a genuinely expired/replaced session's old plan; verify actual
App-to-Server completion interruption. A lost token or expired Server receipt
requires reconciliation and must not become permission to clear local notes.
Native keystore, signed upgrade, real two-device and production rollout remain
separate gates. Server logout remains disabled by default.
