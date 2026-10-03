# Unreadable device vault cache at startup

The owner reported a 2.03.5 startup screen containing a native secure-storage
`BadPaddingException` during a read. The exact entry and device trigger remain
unknown. Source inspection identified unhandled vault cache reads as a matching
startup failure path, also present in the 2.03.9 candidate.

Vault initialization now catches failed reads and invalid cached AES key data,
leaves the entry untouched and keeps protected content locked. When the Server
cannot establish vault state, an unreadable cache cannot establish that encryption
is off. A confirmed Server 404 still represents an account without a vault.
Successful cache reads still allow offline automatic unlock. Initialization reads
once instead of twice in the offline path and never resets, writes or deletes the
cache as recovery.

## Proof

Test-only baseline `24a32b397ba25e5e2ac69393b638b4bd4a920552` adds a constructor
injection seam without changing startup decisions. Five regressions fail against
the original behavior: online/offline read failure, invalid base64, invalid AES
key length, and retry after a temporary failure. Two controls pass: healthy
offline unlock and a confirmed account without a vault. All seven pass after the
fix. Tests assert no storage writes/deletes, reject encryption while locked and
decrypt retained fixture content after a healthy retry.

```text
flutter test --no-pub --reporter expanded test/vault_cache_failure_test.dart
```

## Verification boundaries

Fake secure storage and HTTP establish the Dart behavior, not native keystore
repair or recovery on the owner's phone. Root cause, Google sign-in, session-store
failures, permanently lost keys, phrase-unlock cache writes and the installed
APK's backup configuration remain unverified. A successful initialization in this
fixture does not prove that the whole affected phone can log in or recover every
note. The existing recovery phrase flow is unchanged. Generic startup advice for
other failures is unchanged and still needs classification work.

No device actions, production calls, new services, dependencies, encryption
formats, key derivation settings or storage resets are included. Revert the PR
for rollback; there is no data migration. The original 28-finding percentage does
not count this newly reported incident as an original finding.
