# Encrypted payload byte budgeting and locked-client reload

Two test-only cases extend App main `d04e7239701ce462167e8719cbc82f63131f1667`.
The workflow pins Server main `ac559d92bd4039408e8e8217a5876608b004d980`
after exact-main run 37659138575 passed. App #45's exact-main gate passed before
publishing this follow-up. No production source, schema, dependency or policy changes.

An isolated synthetic owner starts with the existing 30-note free tier and
100 energy. Fourteen notes each contain 180,000 UTF-8 body bytes. Actual
VaultCrypto AES-256-GCM plus base64 expands each sealed payload past 240,000
characters; the real repository must send ten and four rows in separate instant
requests. Each complete captured JSON envelope stays at or below 2,500,000 bytes;
adding the next row exceeds that limit. The tests decrypt the captured payloads,
check each note was sent once, preserve all content, verify ciphertext-only Hive
content and check actual Server writes, ledger entries and total cost of 20.

A second independent logical client starts locked. The real `encOnly=true`
filter excludes all fourteen encrypted rows while advancing the sequence cursor.
Unlocking the test vault and invoking repository reload must reset/revisit the
cursor, receive multiple pages and reconstruct all fourteen notes. It keeps
Hive content sealed and causes no upload, Drive write, wallet or ledger mutation.

TestVault injects a deliberately public fixed synthetic key into actual AES
primitives. No recovery phrase, Argon2 derivation, Server verifier, native
keystore or biometric lifecycle is exercised. Google Drive is simulated; logical
clients are not physical devices. This is wire compatibility evidence, not
cross-store durability, repair or production acceptance. Local strict analysis
and ten controls run; twenty live cases deliberately skip locally and run only
in CI. Parallel Flutter verification includes the CI debug build. Only fixed-code
wire outcomes are retrieved; R25 remains partial.
