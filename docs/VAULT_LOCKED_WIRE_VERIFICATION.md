# Locked pull, unlock reload and vault migration through real HTTP

This test-only case depends on App #39's nine-case proof. It passes a separate
TestVault to each logical client in the existing actual App/API/repository/Hive/
Cubit-to-Server notes/auth/Mongo fixture with simulated Drive.

One client uploads a plaintext note, then unlocks its fixed-key test vault and
uploads an encrypted note. Actual pull fields require empty title/body/items and
an encrypted payload for the latter. A locked second client must load the plain
note while neither displaying nor caching the encrypted note. The Server's
existing `encOnly=true` parameter actually filters `encV=0` plaintext metadata;
the test verifies this behavior and the advanced cursor, without renaming the wire.

After changing only the test vault's unlocked state, real reloadAfterUnlock must
reset the cursor, obtain the encrypted note, expose both synthetic contents in
memory, persist encrypted local payloads and migrate the remaining plaintext
cloud rows. The migration is one standard operation: actual wallet decreases by
5 and ledger gains one debit. Both target rows must then be encrypted in actual
pull responses and absent from the plaintext-only response.

Local strict analysis and ten transport/origin controls pass; ten live wire
cases skip locally and require dedicated CI. No production source, fixture
adapter, schema, dependency, workflow or policy change is included.

The fixed-key TestVault performs actual payload encryption/decryption, but does
not exercise recovery phrases, Argon2 derivation, Server vault verifier routes,
Android keystore, biometric lock, native screens or a process restart with a
hardware key. The two clients use independent stores and the same public
synthetic session of the isolated fixture owner. Two phones, Google Drive,
Atlas/Vercel, signed upgrade and cross-store crash recovery remain outside scope.
R25 remains partial. Exact-head and prerequisite/main CI gates still apply.
