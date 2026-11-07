# Guest profile store (C16)

`lib/profile/guest_profile_store.dart` keeps a Guest's notes on this device
only. It needs no session, network connection, Drive, vault or wallet.

No screen uses it yet. Guest entry (C17) stays disabled until its gate is
accepted.

## Layout

- **Registry.** The box `guestProfiles` holds one record under the key
  `profile`: `{v: 1, id: <uuid>, generation: n}`.
- **Notes.** Each generation of a profile has its own notes box, named
  `guest_notes_<id without hyphens>_g<generation>`.
- **Separation from the signed-in account.** The signed-in cache (`notesBox`)
  is never opened, read or written. An existing account is never converted
  into a Guest profile.

## Guarantees

- **Sessions are fenced.** A `GuestSession` records the profile id and the
  generation it was opened at. Every read and write checks both. A session from
  before a reset, or one belonging to a replaced profile, gets
  `GuestSessionStale`.
- **Concurrent opens are shared.** Opening twice at the same moment creates one
  profile.
- **Reset.**
  1. The new generation is written to the registry first. This is the fence.
  2. The old generation's box is deleted.

  Because the new generation always uses a new box, a crash between those two
  steps cannot show the old notes. The next open removes the box the crash
  left behind.
- **Corrupt metadata.**
  - `open()` reports it with `GuestProfileCorrupt` and changes nothing.
  - `recover()` moves the unreadable record to `unreadable:<time>` and creates a
    new profile.
  - Recovery never deletes earlier guest notes boxes.
  - Profile ids must be lowercase UUIDs. A record with any other id is treated
    as corrupt, so it cannot name another box (for example `../notesBox`).

## Verification

```text
flutter test --no-pub test/profile/guest_profile_store_test.dart   # 7 passed
flutter analyze --no-pub --fatal-warnings --fatal-infos
flutter test --no-pub                                              # 1106 passed, 33 skipped
```

The tests cover:

- a restart keeping the profile and its notes;
- concurrent opens;
- corrupt metadata being reported, kept, and replaced only on request;
- reset fencing old sessions;
- a crash in the middle of a reset;
- access from another profile's session;
- the account cache's file bytes staying identical and its box never being
  opened.

## Open questions

- Whether a device may hold more than one Guest profile. Today it holds one.
- The Guest claim, which merges a Guest's notes into an account, belongs to
  C18 and is gated by B05 and the accepted identity contracts.
