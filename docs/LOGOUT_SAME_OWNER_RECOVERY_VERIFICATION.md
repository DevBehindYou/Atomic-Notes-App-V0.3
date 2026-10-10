# Explicit same-owner saved logout recovery

10 October 2026. Inactive integration; CI results must be checked against the
published PR head. No production activation, migration, account selection or
device action is part of this change.

## Behavior verified by source

`ApiClient.commitLogoutRecovery` sends the same bounded metadata manifest to
`POST /api/notes/logout-attempt/recovery-commit`. The existing strict receipt
decoder validates exact request/row identities, billing/count invariants, result
versions/times and the response byte ceiling. A prepared reply is rejected.
The existing API session revision fence rejects replies from replaced auth.

`logoutSafely` only invokes recovery during an explicit Settings logout when the
saved plan has a different session hash. `LogoutPlanStore.loadForRecovery`
validates the raw cache owner and frozen previous plan without rebinding it.
It never sends the old envelopes for upload with the fresh token. Different
owners, malformed pending envelopes/snapshot maps, hidden locked rows and
missing/pending Server receipts fail closed and retain local work.

Successful full acknowledgements update metadata through the existing serialized
Hive note writer. A later Server version is not regressed; edits with a different
content signature remain dirty. Conflicts retain a deterministic separate copy;
replay never overwrites an edited copy or newer dirty original. A reset pull
obtains the other device's version while preserving all dirty local rows. The
old plan remains the replay journal until note writes and cursor changes are
flushed. Only matching pending request metadata and the validated old plan are
then consumed; remaining work cancels logout and requires a new explicit attempt
with the Server's current funding decision. A plaintext frozen acknowledgement
never clears later same-content vault sealing intent: the existing
`rowNeedsSealing` policy keeps it dirty for a new sealed attempt. Cleared
`syncedSig` alone is not treated as evidence of new intent because ordinary
first uploads use that same marker.

Existing LoginPage uses the user's manual Google sign-in and routes to Splash.
SplashRouteResolver continues the existing device lock, device TOTP, vault and
onboarding order. Recovery is never invoked by startup, account switch or the
advisory status endpoint. SessionGuard hides runtime state on expiry while
retaining disk notes; foreign-owner pending-cache protection is unchanged.

## Verification boundaries

Controlled tests use actual Hive reopen and public synthetic auth/receipts. They
cover paid/free push and completion recovery, newer edits, foreign-account and
locked-ciphertext refusal, missing receipts, tampering, late same-owner replacement,
reply/write/flush interruption, before/after pending and plan metadata deletion,
same-instance/reopened conflict-copy put loss and edited conflict-copy replay. A
bounded CI runner emits 24 fixed outcome codes, including actual Hive reopen
after same-content vault migration, discarding all raw machine/log
output, in `sanitized-logout-recovery-controls-proof`. Transport controls
reject nonterminal commit replies without changing auth/completion markers.

The CI-only handoff runner starts a fresh generated localhost Mongo namespace per
scenario. Two scenarios use real App API/repository/Hive and actual opt-in Server
routes/transactions: paid upload with lost push and recovery-commit replies, and
an already completed old session. They verify a single upload/debit, unchanged
wallet/ledger/Drive-write counters during recovery, fresh auth remains live after
the old commit, and explicit local teardown signs out that fresh session last.
The pre-existing regression/logout/read-only wire cases remain unchanged. The
named `sanitized-logout-handoff-server-wire-proof` contains fixed outcomes and
owned-namespace cleanup codes only.

Local Dart formatting/parser checks do not constitute Flutter analysis/tests.
Local dependency caches remain incomplete; no install or cache refresh was run.
Required CI includes strict analysis, all tests, disposable wire acceptance and
the non-production debug APK. Merge and exact merged-main CI must both succeed
before copying this source into the optimized mirror.

Google authentication, Android keystore/secure storage, native device/TOTP UI,
real Drive, two physical phones and signed 2.03.5-to-2.03.9 upgrade preservation
are not exercised by these synthetic proofs. Missing/pending receipt ambiguity,
plans over 250 rows, rollout drain/rollback and inactive Drive recovery journal
activation remain separate acceptance gates. Nothing here authorizes deleting
notes from a summary-only status reply or guessing that a missing operation
never ran.
