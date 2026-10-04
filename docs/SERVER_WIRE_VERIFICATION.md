# Disposable App to Server contract: first stage

This characterization stage connects real Flutter ApiClient, NotesRepository,
Hive and CloudNotesCubit through loopback HTTP to real Server notes/auth routes,
transactions and indexes on a generated disposable MongoDB replica-set namespace.
Server fixture main is pinned to `925a0a6b415b2a13a9413f5efefe81b0374a8f28`:
PR #29 and main CI both passed, including fixture replay and cleanup checks.
Google Drive is an in-memory adapter. Sessions and independent per-device secure
stores are synthetic. Automatic timers are disabled by the existing test factory.

Four live cases cover create/pull/account isolation, free receive-only sync with
unchanged actual wallet/ledger, stale offline edit conflict with both versions
preserved and no stale Drive write, and cloud count without local/server mutation.
The conflict copy is uploaded on the next manual attempt, as the current client
implements. These are existing-behaviour characterizations, not failing-before
production bug reproductions.

Without `ATOMIC_FIXTURE_ORIGIN`, those four cases explicitly skip; ordinary unit
tests cannot be cited as live wire proof. Nine origin guard tests pass locally,
and strict local Flutter analysis passes. The full local suite passes 457 tests
with these four live cases explicitly skipped. Dedicated CI executes the live cases
and checks that graceful fixture shutdown removes its exact generated namespace.
Only fixed case/setup codes and outcomes are uploaded as sanitized evidence.

The initial PR head `c0c7526` failed during wire setup (sanitized outcomes were
empty). Flutter's test binding installs a synthetic HTTP override; the fixture
transport now directly constructs the base dart:io client and disables proxies,
without changing global overrides. All ten targeted safety/transport tests pass,
including an actual loopback request under that binding; four live cases still
await a corrected CI run. This was test plumbing, not a production defect claim.

The corrected transport let three live cases pass. Sanitized run `37228627291`
at head `f7ddd186` confirmed accepted content was preserved in the conflict case;
only its hard-coded version assertion failed. Server `src/lib/noteMetadata.ts`
seeds fresh versions from the account sequence (including after a wipe), so a
new note need not start at one. The fixture now captures the actual base version
and requires the accepted edit to advance it by exactly one. Preservation,
no-stale-write and wallet/refund assertions remain unchanged; no production
source was changed to satisfy an incorrect fixture assumption.

Boundaries: this is not full `src/app.ts` middleware, CORS/global body-limit,
Google OAuth/Drive, Vercel/Atlas, Android Keystore, two physical devices, production
upgrade or recovery proof. Committed-but-lost responses across client restart,
partial write refunds, delete/edit conflicts, vault locked/unreadable pull and
large Unicode payload scenarios remain separate matrix stages. R25/Q8 remains
partial. No release, production configuration, schema or dependency change.
