# R19: clear the notes UI cooldown when the source clears it

1 October 2026. This change fixes only the stale nullable deadline part of R19. It does not change Server cooldowns, sync timers, energy charges, automatic-sync feedback or Cloud Notes count-based verdicts.

`NotesBloc._snapshot` always receives the source's current deadline, but `NotesState.copyWith` previously treated null as “keep the old value.” A future deadline could survive a source reset. The snapshot now explicitly clears it when the source returns null; unrelated state updates continue to preserve it. Reading the source getter once avoids an inconsistent value/clear decision across a clock boundary.

Two new regressions fail against unchanged main production code at test-only commit `c361477` (main base `031a9cc`):

- The Bloc retains a future deadline when the source clears it. The test expects null and one emitted state; after the fix it also checks preservation of query/selection, suppression of unchanged notifications, and a later replacement deadline.
- The HomePage mascot still shows a future wait when tapped again after the source clears its deadline. The test expects the existing no-wait message. No new user-facing wording is introduced.

The focused pre-fix run passed 51 existing tests and failed these two. The deterministic fake source uses the existing listener interface; no Hive, HTTP, device or production data is involved. This establishes behavior after a source notification, not a full native logout/account-switch trace.

The mascot already treats a naturally elapsed timestamp as an open window. This fix does not claim that ordinary clock expiry kept showing a wait. An already open mascot bubble captures its text at tap time and is not made live-updating here; the widget regression closes and reopens it.

Validation requires strict Flutter analysis, the full test suite and CI's debug APK build before review. Rollback is a code revert; no wire format, storage, dependency, economy or schema migration changes.
