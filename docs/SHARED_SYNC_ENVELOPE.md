# Shared sync envelope scope and compatibility

`SyncEnvelope.prepare` builds an immutable, detached standard or instant
operation with stable wire JSON, UTF-8 byte count, and the existing SHA-256
fingerprint over `{rows,mode}`. It performs no sealing, storage, admission,
authentication or dispatch. The App's existing 50-row and 2,500,000-byte bounds
remain in place. Row order and the Server schema's insertion order are part of
operation identity; keys are never sorted.

The source authority is Server commit
`95070c0cff488e4984bd669d31bfdf348ec74aca`: `src/types/noteWire.ts`,
`src/types/atomicFile.ts`, and `src/lib/syncFingerprint.ts`. Existing cryptography
is reused. Native `LogoutEnvelope` delegates to the shared projector and retains
its public API, validation/error strings, wire field ordering, manifest, golden
bytes and fingerprint. Its historical per-field checklist alias fallback,
integral-double `enc_v` acceptance and unrestricted nonnegative integer version
acceptance remain unchanged. Ordinary preparation instead selects one complete
checklist union branch, requires integer `enc_v`, and rejects explicit null,
fractional or unsafe versions above `2^53 - 1`. JavaScript has one Number type;
VM-only integral-double refusal checks do not claim browser distinction.

This is a projector with client batch bounds, not a replacement for Server date,
content, per-field and per-row validation. Missing payload projects to null;
missing base version projects to zero. Optional updated time presence is
preserved. Browser admission still requires its separate strict validation.

The storage proof workflow uses Flutter 3.44.8, the locked Server checkout and
its locked Node dependencies. It executes the actual Server Zod projector and
fingerprint function with 16 public synthetic vectors, then the same vectors
and five controls on Dart VM and an owned Chrome test session. Coverage includes
Unicode/emoji, lone UTF-16 surrogates and controls, input key order, row order,
mode identity, both checklist aliases and collisions, optional dates, default
versions, sealed payloads, tombstones, numeric guards, immutable detachment,
exact legacy errors, 50/51 rows and exact/one-byte-over client limits. Existing
tracked tests remain byte unchanged.

`ci-sync-envelope-proof.json` schema version 1 records exact App/Server heads,
Flutter/Chrome identity, SHA-256 bindings for source/tests/locks, process exit
codes, and complete fixed-name boolean outcome maps (`nodeCases`, `vmCases`,
`chromeCases`, `nodeVmWireCases`, `nodeChromeWireCases`). Both Dart runtimes emit
public synthetic wires only into transient private streams; Node reparses each
actual wire through the locked Server schema and fingerprint function and
checks canonical bytes and projected-row hashes against the fixed independent
expectations. Wire emission is enabled only by the runner's compile-time proof
flag; ordinary full-suite runs emit no wire receipts. The parser
rejects missing, skipped, duplicate, unknown or
post-terminal events. Raw process output stays transient and private; only the
fixed schema is uploaded. Scope flags state editing/cloud/journals remain
disabled or unimplemented. No journal, web editing, startup, auth, cloud wiring,
production adapter, deployment, device, database or Drive behavior is added.
