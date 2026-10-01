# R26: name the sync control and expose its actions

1 October 2026. CloudButton exposes one semantics node with the button role and the name “Sync now.” The busy value is “Syncing.” When Atomic Energy is available, a hint describes the long press and that accessibility action invokes the same callback as the pointer gesture.

MainPage now supplies its existing Energy callback directly to CloudButton. Keeping both gestures and their semantics inside the control avoids an unnamed parent action or duplicate icon/progress semantics. Busy mode removes the sync tap action while retaining the Energy action, matching the previous pointer behavior. The node remains enabled while that secondary action is available; it is disabled if busy without a secondary action. The dimensions, appearance, sync scheduling and charging are unchanged.

## Proof

Test-only baseline `9743ded` uses MainPage's original parent-GestureDetector composition. Idle and busy tests fail because no “Sync now” semantics node exists; the pointer tap/long-press control passes. The baseline was rerun after correcting test-only semantics-handle disposal to use try/finally before Flutter's end-of-test checks. No production code changed in that reproduction.

The final test fixture matches MainPage's new callback composition. It uses current Flutter semantics APIs to assert the button role, idle tap and long-press actions, busy value and lack of a busy tap action. It invokes both accessibility actions and verifies callback counts. The pointer test verifies one sync tap across idle/busy states and Energy access in both states. Initial fixture cleanup/deprecated-API errors were corrected and are not counted as product defects.

Strict analysis, the full Flutter suite and CI debug APK compilation are required before review. No physical TalkBack, keyboard-navigation, native accessibility-service or authenticated phone session was run. This closes the demonstrated name/role/action gap in the Flutter semantics tree; it is not a WCAG or MASVS certification or a claim of complete app accessibility. An automatic repository sync still does not set this button's manual-sync busy state; that separate R19 issue is unchanged.

Rollback: revert this isolated control/call-site change. No storage, API, schema, dependency or production action is involved.
