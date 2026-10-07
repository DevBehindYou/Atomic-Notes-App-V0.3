# Committed reply withheld from client: restart and replay

The real HTTP transport drains one successful push response and then throws a
synthetic connection error before ApiClient receives it. Actual Server diagnostics
must prove a note/Drive write and one wallet debit committed. The test closes and
reopens that logical device's Hive box, recreates API/repository/Cubit, and requires
the identical persisted body/requestId/mode to replay with no further Drive write,
wallet debit or ledger change. The recovered receipt remains the historical cost.

This characterizes a client losing acknowledgement of an actual committed operation.
It does not drop a physical TCP connection, kill Android, crash Vercel, exercise a
Server pending-operation crash or prove durable Drive/Mongo recovery. Sessions,
storage and Drive remain synthetic; Mongo, routes, transaction and HTTP are real.
The independently pinned Server fixture is unchanged. No production code is edited.

Local analysis, targeted test compilation (live case skips outside dedicated CI),
exact-head normal/wire CI and destination-main CI are required before completion.

Publication checkpoint: strict local analysis and ten targeted safety/transport
tests pass; the five live wire cases explicitly skip locally and await dedicated CI.
