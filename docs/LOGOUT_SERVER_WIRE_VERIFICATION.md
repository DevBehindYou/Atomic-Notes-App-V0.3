# Safe logout: disposable App to Server acceptance

This adds test coverage, with no production activation or implementation change.
The Flutter workflow pins Server main `0791687672961a3468f2c1b4efcb116fe583bd1d`
(Server #63, exact-main CI `37987659573` passed). Its default fixture explicitly
disables logout; the dedicated runner opts in with `--logout-sync`.

## Scope and acceptance

Seven scenarios each start a new loopback fixture process and generated MongoDB
database. Real ApiClient, NotesRepository, isolated Hive, Hono routes, MongoDB
transactions and wallet/session accounting participate. Drive is an in-memory
adapter; secure storage and the vault are synthetic. Settings navigation and
native authentication are outside these tests.

| Scenario | Required behavior |
|---|---|
| Paid logout | Debit 10 once, deliver local content, clear only after completion, revoke only the bound session |
| Emergency logout | Zero Energy and ledger mutation; deliver content before clearing |
| Lost push reply | Retain notes and original request; close/reopen Hive; replay without duplicate write/charge |
| Lost completion reply | Retain clean notes and durable completion intent; reopen Hive/API; replay terminal result after session revocation, without repushing |
| Second batch reply lost | 51 notes, two paid batches; restart with batch two pending; stable request bodies/IDs, 20 total Energy and 51 writes |
| Partial failure | Successful row settles, failed row remains local; cancel logout; retry under a new attempt; no free charge/refund entries |
| Conflict | Preserve accepted original and unsent conflict copy, refuse logout; retry uploads the copy before clearing |

Except for the batch account (which has only one seeded session), a second
synthetic device pulls through its own ApiClient, repository and Hive and must
recover each expected body without a write or additional debit. No real user
session, Energy grant, database or Drive file participates.

`tool/run_logout_wire_fixture.py` reuses the existing guarded CI-only runner.
Each fixture is closed through its owned process handle; the runner must prove
its exact generated namespace is absent before accepting the case. The MongoDB
container is owned by this CI job and removed even on failure. No Atlas opt-in,
environment file, broad database deletion or external network service is added.

Only fixed case/outcome/phase and cleanup codes enter
`sanitized-logout-server-wire-proof`. No tokens, account/note identifiers,
content, private errors or raw logs are included. The original 22-case wire
artifact remains independently checked against its existing schema.

## Verification boundaries

First CI head `ecd13416eceaac861832752c6e03b26a44d93945`, run `38027034250`,
passed all 22 existing wire cases and the first six logout cases with owned
namespace cleanup. The conflict setup failed before attempting logout: the
direct synthetic edit omitted the required `enc_v`/`payload` wire fields.
The strict-analysis job also failed; unused async import and a redundant nullable
assertion were removed from the new test. No raw CI/compiler logs were fetched.
These failed gates receive no merge acceptance; corrected-head outcome is pending
until metadata and both named sanitized artifacts are validated.

A passing run proves these seven synthetic scenarios;
it does not prove real Google Drive failures, device keystore behavior, signed
2.03.5 upgrades, Settings interaction or two physical devices. Feature activation,
old-worker exclusion and production rollout remain separate gates.

Expired/replaced sessions with a saved prepared plan and more than 250 pending
rows remain explicit release blockers. The mutable Drive/MongoDB recovery
journal is still inactive and is not exercised by this acceptance suite.
