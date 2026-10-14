# Home welcome and cloud control — 14 October 2026

The owner requested the editorial greeting/headline and purple cloud control shown in the new reference, followed by a four-second welcome that fades and slides upward while releasing its space for notes. The black half of the supplied GIF defines the busy-ring appearance; no downloaded GIF or new dependency is included.

## Behavior

- The user's profile image, `+ ATOMIC`, handle, notification button and Energy popup remain in the existing MainPage header. Sync remains an instant-sync request; long press retains the Energy popup, including while sync is busy.
- The welcome reads the user's local date and chooses morning (before noon), afternoon (before 17:00), or evening. `CLEAR HEAD.` is Ink and `WRITE IT DOWN.` is Signal. It displays for four seconds, then fades, translates upward and collapses its height over 280 ms. Notes are available immediately.
- Usage, on-device count, pending changes, search, mascot, filters and creation controls remain after the welcome collapses. No cloud total or successful-upload claim is invented.
- Short windows and large-text layouts reuse the existing scrolling header so notes remain reachable before the welcome collapses. The system text scaler and full usage/pending strings remain intact.
- Home owns the welcome's timer and animation, so selection changes and keyboard/responsive layout changes cannot restart it. Backgrounding or leaving the Notes tab cancels the timer; returning refreshes the local greeting/date and starts a fresh four-second welcome. Disposal removes the lifecycle observer, timer and controller. Reduced-motion and accessible-navigation settings collapse immediately at the four-second boundary.
- The cloud control is purple with an Ink outline and hard offset shadow when idle. Its actual `NotesState.syncing` turns the surface Ink and displays a white three-segment rotating ring. Busy includes connectivity checks, receive-only sync and uploads; the accessible status remains the neutral `Syncing`. A busy tap cannot request another sync, while long press remains available.
- The ring is drawn by a small CustomPainter. Its controller exists only while busy, pauses in the background or with TickerMode disabled, and remains static for reduced motion or accessible navigation.

## Verification boundaries

Widget cases cover local date/greeting, the four-second boundary, mid-animation fade/height, released layout space, remaining controls, hidden welcome semantics, reduced motion, lifecycle resume/day rollover, off-tab timing, selection/responsive transitions and disposal. A 320 px / 2× text fixture uses 123 dirty synthetic notes to check full usage/pending strings, the system text scaler, and visible controls/cards before and after collapse. Narrow large-text layouts use a smaller existing display token for the decorative headline without clipping text or clamping the system scaler. Cloud cases cover idle/busy styling, rotation, reduced motion, muted/background behavior, callback accessibility, duplicate-tap prevention, receive-only activity and an offline manual connectivity check.

Five synthetic font-loaded previews retain Home, text editor and checklist editor, and add collapsed Home plus the busy cloud control at its actual 48×44 logical size. The busy scene uses a preview app bar rather than an authenticated MainPage. The existing synthetic Home preview uses an injected date to make visual evidence repeatable. This work adds no session, note-model, wire-format, Energy-charge or synchronization-policy changes. The existing Energy popup implementation is reused without modification.

At preparation time, installed Dart formatting/parser checks have completed. Flutter analysis, widget execution, synthetic preview inspection, disposable App–Server tests and Android debug-build results must be checked in CI before accepting or merging this increment. A signed release, production deployment and connected-device appearance remain separate acceptance gates.
