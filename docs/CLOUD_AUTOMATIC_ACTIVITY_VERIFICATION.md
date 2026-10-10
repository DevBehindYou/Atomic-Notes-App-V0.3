# Cloud Notes automatic activity — 10 October 2026

R19/R25 remain partial. This corrects one observable busy-state gap; it is not native navigation, connectivity or release acceptance.

## Problem and scope

**Verified in baseline code:** on App main `4e025c5dacc51b5ab97d9145e339f7ae0097b119`, `CloudNotesCubit._read` copies `base.working` without consulting `NotesSource.isSyncing` (`lib/state/cloud_notes/cloud_notes_cubit.dart:118–126`). The screen uses that state for its progress indicator and disabling Check cloud, Sync now and Upload all (`lib/page/endpage/cloud_notes_page.dart:136,168–179,283–302`). An automatic sync can therefore leave the screen showing idle controls. Existing repository join behavior limits the effect; this is not evidence of a duplicate charge or upload.

**Inferred from those source paths:** mount or notify the page while `source.isSyncing` is true; its busy indicator remains absent and controls remain available. One must retain a separate manual-request owner because repository notifications can arrive before this screen's own receipt, while that request still needs to block overlapping actions.

## Controlled baseline and change

Five new tests exercise mount-during-sync, automatic enter/exit, manual work surviving idle notifications, manual completion preserving continuing source activity, and the actual Cloud Notes spinner/actions. They use the existing source injection and an in-memory source; they make no network or database requests. The widget test checks that count/upload calls do not overlap automatic activity, then that Sync now becomes usable after it ends. Existing receipt, session-ownership, count-only and failure fixtures remain unchanged.

**Verified in CI metadata:** unchanged production source plus these tests, test-only head `d99da1e18a4485710b0e96df9c371636d2be726a`, [baseline run 38039087375](https://github.com/DevBehindYou/Atomic-Notes-App-V0.3/actions/runs/38039087375), passes strict analysis and fails the Run existing tests step. Raw logs were not retrieved, so this record does not claim a per-case baseline failure count or diagnostic. Causal attribution to the new scenarios is an inference from the green base, the isolated test-only diff and the source path above.

**Verified in changed code:** busy state reflects `source.isSyncing` on mount and every notification, combined with a private manual-request flag (`lib/state/cloud_notes/cloud_notes_cubit.dart:106,124,147–149`). A manual action samples current source state before it starts (`:188–194`), and its finally block releases its own flag while resampling source activity (`:223–227`). Repository events cannot release an unfinished manual request, and manual completion cannot hide a still-active automatic sync. Session/report identity checks, receipts and billing messages are preserved. No timers, sync policy, API, prices, note writes or storage formats change.

Final exact-head strict analysis, complete test suite, CI debug APK and all existing disposable wire proofs remain required before root-coordinated merge. This publication record does not claim future checks have passed.

The first fixed-source run 38039315761 also failed its full Tests step after passing strict analysis. Its cause remains unverified because raw logs were not fetched. A bounded CI-only runner now executes just these five scenarios and discards messages/stacks/output, retaining only allowlisted pass/fail IDs and the last fixed widget checkpoint in `sanitized-cloud-activity-proof` / `ci-cloud-activity-proof.json`. Parse/crash/missing/duplicate cases cannot count as a pass. This diagnostic artifact is separate from the existing wire proofs and is required alongside full CI checks; targeted success cannot excuse a failing full suite.

## Verification boundaries and rollback

Installed Dart formats the test; local Flutter analysis/tests are unavailable because caches are incomplete. No dependency refresh, Flutter bootstrap, local APK, phone action or production access occurred. Controlled source/widget tests do not prove Android lifecycle timing, Google account changes, real network reconnects or physical navigation. Count checks still count notes without comparing content. Automatic sync receipts remain owned by their existing caller; this page does not borrow another request's billing history.

Rollback is the isolated Cubit/test/document change. No migration or production configuration change is required. Original equal-weight finding accounting stays 17/28 complete, 9 partial and 2 open; this milestone advances a partial finding without closing its remaining acceptance gates.
