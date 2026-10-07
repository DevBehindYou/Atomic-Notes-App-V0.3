# App preserves cache and cursor on unreadable/mismatched HTTP pages

The fixture pins Server main `b6b113cf49594a8bcc748e1cc1921221e8097778`
(#32). Its exact-head and destination-main CI must pass before publication.
The only workflow change is this reviewed fixture pin; production App/Server
source, dependencies, schemas, policies and credentials are unchanged.

The new case captures an actual successful pull's Hive snapshot/cursor. A writer
uploads two new notes in one charged request. For missing, corrupt and mismatched
fake Drive reads, an independent logical client starts from that earlier valid
snapshot. Two real sync attempts must fail with readable guidance, no upload
operations, no partial-page merge and an identical on-disk snapshot/cursor.
The intact sibling row must not leak through the failed page either.

Disabling the simulated read fault makes the same cursor return both new rows.
Existing cached rows remain unchanged, errors clear, and the cursor advances
only after that successful response. Actual Server wallet/ledger/live-note counts
and Drive write count remain unchanged by failed pulls and recovery. The seeded
owner has exhausted its upload energy by this point, so receive-only recovery is
also required to work without another upload charge.

Local strict analysis and ten transport/origin controls pass. Eleven live cases
explicitly skip locally and execute only in the disposable CI job. The additional
fixed-code artifact phase names identify the fault mode without note contents,
identifiers, tokens or raw errors. Earlier ten scenarios remain enabled.

This exercises real App/API/repository/Hive/Cubit, actual notes/auth routes and
Mongo transactions, with simulated Drive faults. Restoring reads is not real
Drive repair, transaction compensation or historical anomaly recovery. Native
keystore/navigation, two phones, Google/Atlas/Vercel and signed upgrade remain
separate. R11/R16/R25 remain partial. Exact-head and destination-main gates apply.
