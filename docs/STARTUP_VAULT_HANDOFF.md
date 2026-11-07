# Startup vault check: single-use handoff to the splash

## Problem

A returning signed-in launch checked the cloud vault twice in a row. `main()`
awaits `Vault.init()` before `NotesRepository.init()` and `runApp`, so cached
keys can decrypt notes on load. The splash then awaited `Vault.init()` again
before routing. PR118 shares only work that is still in flight, so the second
call was a new `GET /vault`. That call can also refresh an expired session first.

Base `6de248b` characterization (`test/startup_vault_network_test.dart`, real
`ApiClient` over a counting HTTP `MockClient`):

- The main vault step does not complete while the cloud answer is held.
- A returning user with an existing vault and a cached key reaches `/mainpage`
  after 2 `GET /api/vault` requests.

## Change

`main()` calls `Vault.initAtStartup()`, and the splash service calls
`Vault.initAfterStartup()`. Both behave like `init()`, with one addition. When
the startup check confirms an existing cloud vault and completes its key-cache
read, the first splash check for the same owner, session revision and vault
generation reuses that result once. It makes no request.

The result is not reused, and the splash refreshes as before, after any of the
following:

- a 404 (no cloud vault), a network failure or the 5-second timeout;
- a failed, malformed or wrong-length key-cache read, or an earlier failed key
  deletion;
- a pending key deletion;
- any other vault call: `init`, `unlock`, `createVault`, `lockThisDevice`,
  `lockMemory` or `clearLocal`. This includes an ordinary `init` that joins the
  in-flight startup check;
- an owner, session or generation change;
- more than 30 seconds since the check;
- the splash it was meant for leaving without using it (foreign pending cache,
  error route), through `SplashPage.dispose`;
- the first use. Later splashes and every `init()` refresh.

Ordering is unchanged: the vault check is still before the repository load and
before the first frame. This increment does not remove the pre-frame network
wait. No storage, wire, KDF (Argon2id 65,536 KiB, 3 iterations, parallelism 1)
or AES-GCM change. Reverting needs no data restore.

## Verification

```text
flutter test --no-pub test/startup_vault_network_test.dart
flutter test --no-pub test/splash_startup_test.dart test/vault_test.dart test/vault_cache_failure_test.dart test/vault_concurrency_test.dart test/vault_migration_test.dart
flutter analyze --no-pub --fatal-warnings --fatal-infos
flutter test --no-pub
```

`startup_vault_network_test.dart` covers the following:

- baseline ordering, and the unchanged ordinary refresh;
- an existing vault, with and without a cached key;
- device-lock and two-factor priority;
- no cloud vault with a stale cache, and a vault created after a negative answer;
- offline, and timeout;
- malformed keys, a failed read and a failed deletion;
- explicit and memory locks, before the splash and in flight;
- logout clear;
- session and account replacement, including in flight;
- ordinary-init withdrawal, staleness and single use;
- discard on a foreign pending cache;
- first login on a second device.

Local tests prove request counts and gating only. They do not show device
latency.

## Device acceptance plan (not executed here)

Execution belongs to the QA scope. Record this as its own startup-vault row,
separate from static splash.

- **Builds:** baseline Actions APK from `6de248b` and candidate APK from this
  PR's merged head. Use the same flavour, package (`com.notes.atomic.staging` or
  the isolated acceptance package once available) and signing identity. Verify
  the source SHA and the APK SHA-256 before install.
- **Controls:**
  - Same device, account and current note corpus. Do not reset or seed.
  - Same vault state: an existing vault with a cached key. Optionally, a second
    pass without a cached key.
  - Same network, and device lock and two-factor off.
  - Take a fresh backup before each install.
- **Metrics, recorded separately:**
  1. Logical `GET /vault` requests per cold launch, from the server's request
     log for that session. Expect baseline 2, candidate 1.
  2. Android `am start -W` TotalTime, which covers the time until the first
     Flutter frame. Expect no change from this PR.
  3. Time from process start to the Home route being visible: observed Home
     readiness, measured the same way for both builds.
- **Samples:** at least 5 cold launches per build, alternating the build order
  and force-stopping between launches. Report every sample, including failures
  and outliers, and the median.
- **Exceptional paths, one each:** offline launch with a cached key, which
  should open; first login. Both builds should behave the same.
- **Preservation:** note-file hashes, or a decoded record comparison, before and
  after; zero crash or ANR records.
