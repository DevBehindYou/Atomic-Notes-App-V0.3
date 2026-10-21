# Mascot tap status — 21 October 2026

User requested removing the adjacent reload/status icon and making the mascot itself show information while changing animation. Reuse the existing player activation callback and live NotesBloc bubble. Preserve the three-second timeout, second-tap dismissal, no-sync side effects, favorite, offline playback and reduced motion. Home's accessible action names both effects; settings keeps its animation-only action.

- [x] Change Home regression checks to require mascot-only status activation and no adjacent status button; observe failure.
- [x] Forward optional activation callback and semantic action through the existing branding wrapper to the player. Remove only the adjacent status control.
- [x] Verify live status, timeout/disposal, touch/keyboard/semantics, small-screen layout and existing mascot behavior. Update bundled acceptance docs.
- [ ] Independently review a focused PR, pass required CI, merge without conflicts, then build and verify on the connected synthetic acceptance app.

The separately requested cloud-button size adjustment belongs in a separate focused PR. Physical-device performance and staging acceptance remain in progress; synthetic acceptance does not prove Google OAuth, real Drive, iOS or production readiness.

Local verification: initial no-adjacent-button regression failed on the existing IconButton before the change. After implementation, targeted analysis is clean and 105 Home/live-status/mascot tests pass, including keyboard and semantic activation. Physical-device proof and CI/review remain pending.
