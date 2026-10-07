# Preserve local work when refund headroom is limited

Fixture-only extension from App main
`92c7f86d77fe4af0a31dd28a60a37629098df7c9`. Two new cases exercise actual
ApiClient, NotesRepository, Hive and CloudNotesCubit through loopback HTTP to
the real notes/admin routes and disposable MongoDB transactions with fake Drive.
The workflow pins Server main `bd37028fe6026da1ad4c1f0466fd4826cafa56cb`
after PR #36 and exact-main run 37657574718 passed. No production source or
policy changes.

The synthetic owner's budget is restored through the real admin API using the
deliberately public fixture key. A bounded fault interleaves one real admin grant
after a ten-energy instant debit, fills the wallet to 119 or 120, and fails the
selected fake Drive write. The App must show a ten-energy charge and a one- or
zero-energy refund: net nine or ten. Its original body remains dirty in Hive and
its completed failed request marker is removed. Actual wallet, write, metadata
and ledger changes are checked; ledger differences preserve duplicate counts
without assuming query ordering.

An explicit ApiClient replay sends the identical captured envelope and request ID.
It must return the same historical receipt without another ledger mutation,
grant, debit, refund or Drive write. After disabling the fault, a new request
uploads the retained note once, costs ten energy and leaves Hive clean.

Local strict analysis and ten origin/transport controls must pass; all eighteen
real HTTP/Mongo cases are deliberately skipped locally. CI runs the full wire
suite and the independent Flutter analysis/test/debug-build job in parallel.
Only the fixed-code wire artifact is retrieved. Synthetic stores are logical
clients: this does not verify native keystore, Google sign-in, real Drive,
Atomic Controller browser login, physical two-device behavior or production.
R25 remains partial; exact-head and destination-main gates still apply.
