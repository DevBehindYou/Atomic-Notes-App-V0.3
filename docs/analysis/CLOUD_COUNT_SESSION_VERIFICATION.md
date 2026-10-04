# Cloud Notes count ownership — 4 October 2026

Status: failing-before proof recorded; implementation pending. Linked findings: R19 (status correctness), R25 (critical-path regression coverage). This does not close either full finding.

Baseline: `de7965c9c235362a5ba0d5a329e43d66e0873a96` (App main, #31 merged). Count checks currently retain cached count/check time across a source identity change and have no caller/session ownership after their await. An unexpected source exception can leave the checking flag set.

Hypothesis: clear count-derived state when the repository lifecycle or API session changes; accept only the latest check belonging to the current identity. A failed check must finish with the existing unavailable-count verdict and allow another check.

Proof method: deterministic Cubit and actual Cloud Notes widget fixtures controlling count completion, identity changes, exceptions and closure. Add tests first on the unchanged baseline, record failures and passing controls, then run strict analysis and the full suite. CI must also pass analysis, tests and its non-production debug APK on the exact PR head before merging; verify destination main afterward.

Target: no cached count/check timestamp from a retired identity, no stale completion overwriting a newer check or releasing its busy state, no stuck checking flag on failure, and no note mutation/upload caused by a count check. Preserve current sync receipt ownership and controls for sources without the optional report capability.

Risk/blast radius: in-memory Cloud Notes state and its count verdict only. No API payload, price, storage format, dependency, repository sync algorithm or production action changes. Rollback: revert this isolated PR; no data migration required. Effort: one bounded proof/fix/verification stage, not a release estimate.

Boundaries: ApiClient already rejects responses from retired API revisions (`lib/api/atomic_notes_api.dart:142`); SessionGuard resets navigation after teardown (`lib/authentication/auth_services/session_guard.dart:60–78`). Therefore this source-level issue is not evidence of a deployed cross-account note leak. Native logout/navigation timing, real account switching and device recovery remain unverified by these fixtures. Count equality still does not compare note content.

## Before evidence

On unchanged main production code, Flutter 3.44.8 on Windows, shared `PUB_CACHE=C:/dev/pub-cache`, `flutter test --no-pub --reporter expanded test/cloud_count_session_test.dart` exits 1: **10 failing cases, 5 passing controls**. These are scenarios for one count-state ownership/error boundary, not ten independent product defects. The failures reproduce retained 71-count state, stale responses overwriting a newer 2-count state, blocked/released new checks, an uncaught count error, and actual page cache/error verdict failures. Controls preserve count-only behavior, ordinary note notifications, duplicate-check suppression, closure and legacy sources. No dependencies installed, APK built locally, phone action or production request was performed.
