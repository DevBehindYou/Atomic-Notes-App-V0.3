# Cloud Notes count ownership — 4 October 2026

Status at publication: implemented and locally verified; exact-head PR CI and destination-main verification remain merge gates. Linked findings: R19 (status correctness), R25 (critical-path regression coverage). This does not close either full finding.

Baseline: `de7965c9c235362a5ba0d5a329e43d66e0873a96` (App main, #31 merged). Count checks currently retain cached count/check time across a source identity change and have no caller/session ownership after their await. An unexpected source exception can leave the checking flag set.

Hypothesis: clear count-derived state when the repository lifecycle or API session changes; accept only the latest check belonging to the current identity. A failed check must finish with the existing unavailable-count verdict and allow another check.

Proof method: deterministic Cubit and actual Cloud Notes widget fixtures controlling count completion, identity changes, exceptions and closure. Add tests first on the unchanged baseline, record failures and passing controls, then run strict analysis and the full suite. CI must also pass analysis, tests and its non-production debug APK on the exact PR head before merging; verify destination main afterward.

Target: no cached count/check timestamp from a retired identity, no stale completion overwriting a newer check or releasing its busy state, no stuck checking flag on failure, and no note mutation/upload caused by a count check. Preserve current sync receipt ownership and controls for sources without the optional report capability.

Risk/blast radius: in-memory Cloud Notes state and its count verdict only. No API payload, price, storage format, dependency, repository sync algorithm or production action changes. Rollback: revert this isolated PR; no data migration required. Effort: one bounded proof/fix/verification stage, not a release estimate.

Boundaries: ApiClient already rejects responses from retired API revisions (`lib/api/atomic_notes_api.dart:142`); SessionGuard resets navigation after teardown (`lib/authentication/auth_services/session_guard.dart:60–78`). Therefore this source-level issue is not evidence of a deployed cross-account note leak. Native logout/navigation timing, real account switching and device recovery remain unverified by these fixtures. Count equality still does not compare note content.

## Before evidence

On unchanged main production code, Flutter 3.44.8 on Windows, shared `PUB_CACHE=C:/dev/pub-cache`, `flutter test --no-pub --reporter expanded test/cloud_count_session_test.dart` exits 1: **10 failing cases, 5 passing controls**. These are scenarios for one count-state ownership/error boundary, not ten independent product defects. The failures reproduce retained 71-count state, stale responses overwriting a newer 2-count state, blocked/released new checks, an uncaught count error, and actual page cache/error verdict failures. Controls preserve count-only behavior, ordinary note notifications, duplicate-check suppression, closure and legacy sources. No dependencies installed, APK built locally, phone action or production request was performed.

Before-test commit: `17b1ecc991046b5f90ccbcfd5d5c2f510e50176b`. Only an unused import was removed from the fixture after the before run; scenario assertions are unchanged.

## Implementation and after evidence

**Verified in code:** `CloudNotesState.copyWith` can explicitly clear `checkedAt` (`lib/state/cloud_notes/cloud_notes_cubit.dart:59,71`). A source identity change invalidates both cached count/check state and the active count revision while preserving the separate sync working flag (`:129–147`). Checks capture identity/revision, handle unavailable results/errors and ignore retired completions (`:156–180`). The page distinguishes an idle unchecked session from an active check (`lib/page/endpage/cloud_notes_page.dart:75–89`). Real source identity includes repository lifecycle and API session revision (`lib/database/notes_repository.dart:555`); legacy test sources without this optional capability retain their original behavior.

**Verified in executed controlled tests:** all **15 new cases pass**, and all **47 targeted tests** pass together with existing count/receipt/verdict/button fixtures. The visible Check cloud button can run after retirement or a count failure; no old count or raw exception text is rendered. Retired completions neither overwrite new counts/timestamps nor end a newer pending check. Count-only controls verify note maps, dirty flags and absence of save/delete/upload/sync actions (`test/cloud_count_session_test.dart:72–306`). These fixtures do not measure native account switching or network performance.

**Verified locally:** strict `flutter analyze --no-pub --fatal-infos` passes; the complete `flutter test --no-pub --reporter expanded` suite passes **438 tests** on the review source. The first strict pass caught the test's unused import before publication; it was removed and strict analysis/full suite rerun successfully. No warnings were bypassed. `git diff --check` passes.

CI and merge metadata must be recorded separately for the exact final head; this publication record does not claim a future run or a completed release. R19/R25 remain partial and the original finding totals stay **17/28 implemented (61%), 9 partial (32%), 2 open (7%)**. This is finding accounting, not a readiness/effort/coverage percentage.
