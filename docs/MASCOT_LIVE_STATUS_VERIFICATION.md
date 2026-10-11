# Honest local status in the live mascot bubble

The Home screen's mascot now describes local pending changes. Zero dirty rows say `No local changes waiting.` and retain the existing next-sync timing where applicable. That statement does not imply cloud existence or content equality: a cloud wipe intentionally keeps local notes while clearing their cloud versions and synchronized signatures.

The actual `OverlayPortal` bubble selects its current message from `NotesBloc`. Activity, errors, pending count and cleared cooldowns can change the displayed message while it is open. Existing priority remains activity, then error, then pending/timing. Updates do not start sync or extend the original three-second auto-hide. A second tap closes the bubble; disposal cancels its timer.

## Before evidence

Test-only head `6ac6fe6c68f93492b66a98da0aecee85f81ad9f1`, based on accepted App #56 main `c132bc8a0467639f5ca8a68fa9ad38c6a6eaf59f`, was published in draft #58 before modifying production Home code or its existing expectations. CI [38132421231](https://github.com/DevBehindYou/Atomic-Notes-App-V0.3/actions/runs/38132421231) passed strict analysis, existing five-case Cloud Notes activity and the disposable wire job. Its focused mascot step failed. Only the fixed-schema artifact was inspected; raw CI logs were not read.

| Controlled actual-widget case | Before | Cleanup |
|---|---|---|
| `idle_local` | Fail | Pass |
| `post_wipe` | Fail | Pass |
| `live_activity` | Fail | Pass |
| `live_pending` | Fail | Pass |
| `auto_hide` | Fail | Pass |
| `dispose_timer` | Pass | Pass |

These are five failing cases and one passing control, not a claim that every new assertion has independent failing-before provenance. The artifact's overall failure may also include rejection of non-protocol tool stdout; per-case outcomes are separate from strict runner acceptance.

## Final verification gate

`test/mascot_live_status_test.dart` exercises the real Home widget through `NotesBloc`. The post-wipe case uses real isolated Hive and `NotesRepository.save`, `syncNow` and `wipeRemote` with existing controlled API/vault fixtures. It checks that the local title survives, cloud version becomes zero, synchronized signature is empty, pending count stays zero and the UI makes no cloud-equality claim. Other cases cover open-bubble activity/error/retry/pending/cooldown changes, the original timer deadline and disposal.

The dedicated runner uses Flutter's official JSON file reporter in a unique temporary directory with a fixed filename, discarding stdout/stderr. Its private JSONL is limited to 4 MiB and strictly parsed. It requires six unique known case starts/completions, one successful hidden loader completion, one correctly test-bound cleanup marker per case, terminal success and zero process exit. Timeout, missing/malformed/oversized file, skipped tests, unknown cases, duplicate events and failed temporary-directory cleanup cannot pass. The private report is deleted and is never uploaded. Parser/runner controls exercise these refusals without Flutter or a network.

The final candidate still requires successful strict analysis, the entire existing suite, debug verification APK, all existing sanitized wire/Cloud Notes artifacts and this exact focused schema:

```json
{"version":1,"scope":"controlled live mascot local sync status","phase":"complete","outcome":"pass","cases":{"idle_local":"pass","post_wipe":"pass","live_activity":"pass","live_pending":"pass","auto_hide":"pass","dispose_timer":"pass"},"cleanup":{"idle_local":"pass","post_wipe":"pass","live_activity":"pass","live_pending":"pass","auto_hide":"pass","dispose_timer":"pass"}}
```

No native/device connectivity, authenticated physical navigation, screen-reader announcement or real Drive acceptance is claimed by these controlled tests. Branding assets and launcher icons are a separate change. Source correction and final CI acceptance must be recorded independently before this PR can merge.
