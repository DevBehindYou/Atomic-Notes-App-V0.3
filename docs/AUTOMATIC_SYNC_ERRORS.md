# R19 automatic-sync failure status

Automatic repository failures do not enter the NotesBloc snapshot, so tapping
the mascot can say all notes synced after a failed receive-only pull. A known
offline attempt sets lastError without notifying listeners. A late sync failure
can also repopulate lastError after session teardown.

Snapshot the repository's latest failure in nullable NotesState.syncError,
including explicit clearing and equality. The mascot prefers current activity,
then the known failure, then the existing waiting/window message. A receive-only
attempt says Checking for cloud changes. No automatic snackbars are added.

Known offline failures notify listeners after validating the current lifecycle.
clearMemory clears the old failure. Retired-session timeout/error catches do not
publish errors or schedule retries. The local busy guard moves before handling
connectivity so stale offline checks cannot publish a failure to a new session.
No sync wire, data, energy, debounce or retry-delay policy changes.

Test-only baseline `479be8668fced8376e3a73c88c24e20af004e505` on main
`3a26c2cd19ef59356815bda686e12f057cf1f8db`: five regressions fail and one existing
activity control passes. After all six pass. Strict local Flutter analysis and
all 357 tests pass. Tests use memory UI fixtures, disposable Hive and a fake API.
An initial invalid exception-constructor fixture and lint-failing intermediate
run are excluded; the saved proof uses corrected before/after runs.

R19 remains partial: other count/status semantics and real-device delivery are
not fully established. Failure text is shown when tapping the mascot, not as a
permanent banner. An already open bubble retains its message until reopened.
Other successful/no-pending wording and Cloud Notes billing/count computations
are unchanged. Rollback: revert the complete PR including state and lifecycle
guards. No production, device, storage reset or account actions were performed.
