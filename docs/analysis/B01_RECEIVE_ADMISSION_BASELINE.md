# B01 receive admission baseline — 25 October 2026

Base: App main `127c12170e17419c231415a18b20dd8ebeada4db`. This is a test-only characterization of the accepted App flow before B02; production code and policy are unchanged.

The six added cases in `test/sync_http_repository_test.dart` join the real ApiClient, NotesRepository and isolated Hive with synthetic in-process HTTP responses. No request leaves the process. Configurable remote rows extend the existing harness instead of duplicating it.

- A definitive HTTP 409 `insufficient_energy` refusal in standard and instant modes leaves a newer edit dirty in memory and Hive and removes the refused request, but currently prevents receiving the offered unrelated remote note. These assertions are explicitly labeled **legacy baseline**, not desired behavior.
- An HTTP 503 provider failure prevents pull/cursor advancement and retains the frozen request. A later local edit survives retry, which reuses the identical request body and original standard mode even when triggered as instant.
- HTTP 429 cooldown receives the remote note while retaining the dirty local edit. A later standard attempt continues receiving without another push during the closed window.
- A late refusal after replacement by another account or a new session for the same account retires the report, preserves the pending request/local edit and performs no pull.

## Evidence

The desired B02 assertion is `expect(repository.byId('remote-receive-fixture'), isNotNull)`. It is temporarily substituted for the legacy null expectation and run in both modes before restoring the committed characterization. The assertion demonstrates the actual missing receive; it must become the permanent expectation with the B02 behavior change.

Observed on the exact HTTP 409 fixture: the desired receive run exited 1 with two failures, both `Expected: not null; Actual: <null>`, after the local-edit and refused-request cleanup assertions passed. After restoring the explicit legacy expectation, the final focused run exited 0 with **103 tests passed**, including the six new cases. Final strict changed-test analysis exited 0, **No issues found**. `git diff --check` passed. This is bounded local baseline evidence; full CI remains a separate gate.

Focused command (existing Flutter 3.44.8 SDK, shared cache, no dependency resolution):

```text
flutter test --no-pub --reporter expanded test/sync_http_repository_test.dart test/push_ack_boundary_test.dart test/notes_repository_lifecycle_test.dart test/account_cache_preservation_test.dart test/vault_migration_test.dart
flutter analyze --no-pub --fatal-warnings --fatal-infos test/sync_http_repository_test.dart
git diff --check
```

Execution uses `C:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe C:/dev/flutter/bin/cache/flutter_tools.snapshot` in place of the Flutter batch wrapper. Exact executed results accompany the commit review.

## B02 and later boundaries

The narrow B02 seam is the admission-error branch after `_push` has a definitive refusal. Require typed `ApiException`, exact `insufficient_energy` code and HTTP 409 before permitting independent receive or discarding its pending envelope. The current code-only classification in `notes_repository.dart:912` also discards a same-code 503; B02 needs a failing regression for that misleading response, plus unknown-write, recovered-request and owner/wipe controls. String matches used for display text cannot authorize receiving. Recheck the active lifecycle/session and cloud-wipe fence before pull. Preserve dirty same-ID notes through the existing merge guard.

This suite does not prove a real zero balance, Server admission/ledger semantics, provider writes, full-value refunds, free vault migration or native crash durability. Existing wire fixtures already characterize capped refunds and historical replay (`server_wire_integration_test.dart:1190`), ordinary lost-reply restart (`sync_http_repository_test.dart`), and repeated/partial vault conversion (`notes_repository_lifecycle_test.dart:813`). Do not duplicate them as new B01 proof.

B05 still needs ordinary-sync crash/restart coverage between each per-note persistence, checkpoint and pending deletion. Existing logout-specific put/flush/delete interruption tests do not establish that ordinary path. Vault migration still invokes ordinary `syncNow()` (`notes_repository.dart:1116`); free migration requires the separately planned Server-validated admission contract.
