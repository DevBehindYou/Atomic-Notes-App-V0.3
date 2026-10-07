# Later edit survives committed-reply loss, restart and replay

This case extends the actual App/HTTP/notes/auth/Mongo fixture with simulated
Drive. Its prerequisite is the two-direction delete/edit proof in App #38;
the final PR diff must be assessed after that prerequisite reaches main.

The test receives and deliberately withholds a successful committed reply at
the client transport boundary. It checks actual wallet/Drive state and the
accepted Server version, then edits the local note while its saved operation is
unanswered. The pending operation must remain unchanged. It closes/reopens the
real Hive box and reconstructs ApiClient, repository and Cubit.

On retry, the original request body/ID/mode must replay exactly. Its historical
acknowledgement must not clear the later edit. A second, fresh request must send
that edit with the acknowledged base version. The final local and pulled note
must contain the later edit, be clean and advance exactly one accepted version.
Actual wallet/ledger/Drive facts require only one additional debit/write after
the already committed upload. The report includes both the historical 10-energy
receipt and the new 10-energy operation; its total is not a second replay debit.

Local strict analysis and ten transport/origin controls pass. Nine live cases
skip locally and require the dedicated CI job. No production source, schema,
dependency, workflow, policy or fixture adapter is changed by this test.
The simulated loss is after the full response arrives at the client transport,
not a physical TCP interruption, server crash, Android process death or durable
Drive/Mongo recovery. Native storage, two phones, Google/Atlas/Vercel and signed
upgrade remain separate; R25 remains partial. Exact-head and main CI required.
