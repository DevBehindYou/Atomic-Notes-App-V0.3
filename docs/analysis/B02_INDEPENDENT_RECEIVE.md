# B02 independent receive — 25 October 2026

Base: B01 `bb3db75aefa0fc45c6154138b7ed7bbd496c61f6`, stacked on App main `127c12170e17419c231415a18b20dd8ebeada4db`. B01 must merge first.

A new upload refused with typed `ApiException`, exact code `insufficient_energy` and HTTP 409 now permits an independent pull. Only the matching owner/request envelope is removed, after checking the active session, lifecycle and cloud-wipe generation. Before this independent pull, the combined sync rechecks these fences plus vault-lock/logout/wipe state. Receiving preserves dirty same-ID notes through the existing merge guard. Existing acknowledged-upload/wipe ordering remains unchanged.

The operation remains incomplete while the upload waits. Its receipt totals remain unknown without a confirmed receipt. A later funded attempt snapshots the latest edit under a new request ID. The successful receive message says cloud notes were checked, which also covers a valid empty response.

Recovered unknown requests remain frozen and block pull even if a later response reports HTTP 409 `insufficient_energy`. The same code on HTTP 503, other/substring codes, generic error text and network failures cannot authorize receiving or erase the saved request. This conservative recovery rule deliberately requires reconciliation of the original operation before independent receive.

The private `_PushOutcome` distinguishes drained, pending, refused admission and retired work. All four `_push` call sites were inspected: ordinary sync handles the distinct outcomes; the three logout callers already replay saved envelopes and ignore the prior boolean return. Existing validation and cooldown behavior are retained. No API, schema, billing/refund policy, migration admission, dependency or workflow changes are included.

## Verification

Tests were written before production edits. On unchanged B01 code, the targeted B02 run exited 1 with **six failures and five passing controls**: missing receive in both modes, erased journal for a same-code 503, erased recovered request on later 409, missing independent pull-failure observation, and erased replacement envelope. After the focused implementation, all **11 B02 cases passed**.

The two converted receive cases also verify an edit made while admission is pending, a competing remote row for the same ID, an unrelated remote note, unknown receipt totals, and a later funded retry carrying the latest content. Additional cases cover failed pull/cursor preservation, wipe overlap, replacement envelope, and the existing same-owner/new-owner session replacement controls.

Final verification commands use the existing Flutter SDK directly through `dart.exe flutter_tools.snapshot` with `PUB_CACHE=C:/dev/pub-cache` and `FLUTTER_ROOT=C:/dev/flutter`:

Final results on the corrected implementation: **164 tests passed** across the eight listed suites (exit 0); strict analysis of both changed source files reported **No issues found** (exit 0); `git diff --check` passed. The broader run caught an initial fence applied too broadly to already-acknowledged uploads; narrowing it to refused admission restored the existing wipe-ordering control without changing its assertion.

```text
flutter test --no-pub --reporter expanded test/sync_http_repository_test.dart test/push_ack_boundary_test.dart test/notes_repository_lifecycle_test.dart test/account_cache_preservation_test.dart test/vault_migration_test.dart test/logout_orchestration_test.dart test/logout_same_owner_recovery_test.dart test/r2_logout_causal_test.dart
flutter analyze --no-pub --fatal-warnings --fatal-infos lib/database/notes_repository.dart test/sync_http_repository_test.dart
git diff --check
```

These tests use real App parsing/repository logic and isolated Hive with synthetic in-process HTTP responses. They establish local flow and compatibility, not a real account balance, live Server/Drive/Mongo behavior, native process-death durability, full-value refunds, free migration or device acceptance. No network service, device, local APK build or dependency installation is used. Exact-head CI and independent review remain separate merge gates.

Rollback reverts this focused App flow and tests; it changes no stored schema and preserves existing pending request readers. B05 settlement journaling and B04 free migration remain separate tasks.
