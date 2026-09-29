# State management

Atomic Notes uses the [bloc](https://pub.dev/packages/bloc) library (`bloc`, `flutter_bloc`, `equatable`;
`bloc_test` for tests). This file says where state lives, how a screen reads it, and how to add a
new one. Nothing here changes what a screen looks like: the widgets, layouts and texts are the same
as before the move.

## Three layers

| Layer | Where | What it does |
|---|---|---|
| Data | `lib/database`, `lib/profile`, `lib/api`, `lib/security` | Hive, the Server API, the vault. Singletons such as `NotesRepository`, `EnergyService`, `ProfileStore`, `NotificationService`. They keep the data and do the work; the Server stays the authority over balances. |
| State | `lib/state` | One bloc or cubit per feature. It listens to a data-layer object and turns every change into one immutable, equatable state. |
| Screens | `lib/page`, `lib/utility/component` | Draw a state with `BlocBuilder`, `BlocSelector` and `BlocListener`. They send events or call cubit methods. They never listen to a singleton themselves. |

The state layer does not see the singletons directly. It sees a small interface next to each of them
(`NotesSource`, `EnergyStore`, `ProfileSource`, `NotificationsSource`), so the tests use a fake in memory
and need neither Hive nor the network (`test/support`).

## What owns what

| State | Class | Created | Read by |
|---|---|---|---|
| Notes list, filter, search, selection, header counts, bin count, sync button | `NotesBloc` (events) | once, above the app (`AppBlocs`) | Notes screen, app bar sync button, Settings cards |
| Profile picture, Public Profile switch | `ProfileCubit` | once, above the app | every `ProfileAvatar`, the avatar popup, the profile screen |
| Notification feed and the bell badge | `NotificationsCubit` | once, above the app | app bar bell, Notification Center |
| Recycle Bin | `RecycleBinCubit` | with the screen | Recycle Bin |
| Device against cloud | `CloudNotesCubit` | with the screen | Cloud Notes |
| The two wipes | `DangerZoneCubit` | with the screen | Danger Zone |
| Energy, coins, prices, activity | `EnergyCubit` | with the screen or popup | Atomic Energy screen, the long-press popup |

`NotesBloc` uses events because the order of what happens to the list matters (select, delete, sync).
The others are cubits: their actions are a request and an answer, and a dialog often has to wait for it.

## Rules

1. **A state that did not change is not emitted.** States are `Equatable`. Bloc drops an equal state,
   but not the very first one, so each handler goes through `_put`, which emits only when the next state
   differs. A store that says "I am syncing" and changes nothing on screen therefore rebuilds nothing.
2. **Notes are edited in place, so states compare a signature.** `NotesState.signature` (see
   `noteSignature`) changes whenever a note on view changes its text, ticks, pin, deleted flag or sync
   state. The list itself is not part of equality.
3. **A widget listens to the fields it draws.** `BlocSelector` for one value, `BlocBuilder` with
   `buildWhen` for a few. On the notes screen the title row, the filter chips, the search box, the grid
   and the add menu each listen on their own, so typing in the search box rebuilds the grid and nothing
   else. `test/home_page_test.dart` counts the rebuilds and fails if that grows.
4. **An action answers with a message.** Cubit methods that end a dialog return a `UiMessage`; the screen
   shows it when it is ready to (after the dialog has closed, as before).
5. **Money never moves on the client.** `EnergyCubit` reads balances and asks the Server to change them.

## Adding a screen

1. If the data already has a singleton, add what the screen needs to its interface in the data layer.
2. Write the state (`Equatable`, immutable) and the cubit or bloc in `lib/state/<feature>`. Read the
   store in one static method, and emit only when the result differs.
3. Provide it. Shared by several screens: add it to `AppBlocs`. Used by one screen: create it in the
   screen's `BlocProvider` (the screen takes an optional store for tests, like `RecycleBinPage(source:)`).
4. Test the state with a fake, and the screen with `pumpWidget`. Use a tall test screen
   (`tester.view.physicalSize = Size(1080, 4800)`) so nothing needs scrolling.

## What is not in a bloc, and why

- `Vault`, `TwoFactor`, `ApiClient`, `SessionGuard`, `SyncStatusHelper`: services that do work. Their
  screens (encryption, unlock, two-factor, sign-out) are step-by-step flows whose state is only that
  screen's own (`setState`) and nothing else reads it. Two small reads of `TwoFactor` (the "armed" row
  on the profile screen and the two-factor screen) still use an `AnimatedBuilder`.
- Startup routing in `SplashPage`: navigation, not state.

## Known edges

- `ProfileStore` keeps the picture per account and nothing announces a new sign-in, so the main screen
  calls `ProfileCubit.refresh()` when it opens.
- `NotesBloc` lives above the app. The screen resets the filter, the search and the selection when it
  opens (`NotesViewReset`), as a fresh screen did before.
- A note's deleted state and the bin count come from the same store, so both update together.
