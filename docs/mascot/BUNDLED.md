# Bundled mascot implementation — 21 October 2026

## Current decision

The user superseded optional downloads on 21 October: ship all 13 supplied characters and all 52 unchanged GIFs in the app. No mascot network request, GitHub release, private download store, download/preview-fetch control, or asset removal flow remains. This is an implementation choice; no Play policy compliance claim is inferred from it. Earlier download plans and PR75 are historical and superseded.

The complete source artwork totals 18,721,297 bytes (17.85 MiB), 16,513,252 bytes (15.75 MiB) more than Cubie alone. These are raw asset totals; compressed APK/AAB and store delivery sizes must be measured. Assets are copied directly from the user directory and SHA-256 checked without conversion. The source directory remains untouched.

## Behavior and boundaries

Cubie is the default. Settings offers every character offline and saves the favorite and motion setting only on this device. One selected hero animates; list cards display still first frames and are built lazily. Touching the Home character changes animation within the favorite and opens the existing live NotesBloc status bubble. Keyboard and assistive activation use the same action, named "show sync status and change animation". The bubble retains its three-second deadline and second-tap dismissal. No adjacent reload button is shown, and mascot activation starts no note, sync, account or Energy operation.

Playback uses a shuffled bag of four original animations, encoded timing and bounded image ownership. Reduced motion, hidden routes, TickerMode, and background lifecycle suspend animation. Small activity accents stay still. Startup preference reads do not block the child or note loading. Future preference schemas remain read-only, with original data preserved.

All 52 clips are app-pinned and verified locally before decoding. The resolver deduplicates in-flight reads, rejects altered bytes, and keeps at most 4 MiB of encoded data in an LRU cache. Open leases retain their own references outside that cache until the decoder finishes. This is a cache bound, not a claim about total engine memory. The Flutter GIF engine still returns native 480px frame buffers despite a smaller decode hint; device memory and frame performance remain unmeasured.

## Automated evidence and release gates

Run `dart run tool/verify_mascot_catalog.dart` to validate the 13-by-four catalog, all source sizes/digests and bundle declarations; the optional original audit manifest argument also checks historical provenance. Runtime tests cover all 52 local resolutions, cache bounds, concurrent read deduplication, corrupt-byte rejection/retry, nonblocking preferences, and live non-default favorite changes. Player tests include native decoding, frame counts and full encoded-cycle durations for all 52 clips. Settings tests cover all choices, local selection and 320px/200-percent text controls. Existing live sync-status assertions and screenshot pixel checks remain enabled.

Whole-project analysis and tests, all required GitHub checks, and independent review must pass before merge. Physical Android sequence tests, screen-reader/touch exploration, light/dark visual review of every animation, photosensitive-motion review, battery/memory/frame profiling, and isolated staging sync tests remain release gates. No deployment green flag is established by unit tests or an APK build. The separate WebApp still depends on its accepted shell/browser platform work; iOS and browser delivery are not certified by Android implementation.
