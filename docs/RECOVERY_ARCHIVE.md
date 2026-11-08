# Portable recovery archive (C11–C12)

These modules are not connected to anything yet. No screen, repository or sync
path calls them. Export UI (C15) and restore (C13/C14) will build on them.

## Manifest (C11, `lib/recovery/archive_manifest.dart`)

Format `atomic-notes-archive`, version 1. The manifest is a JSON table of
contents with one entry per note:

- `id` (exact UUID)
- `path` (always `notes/<id>.json`)
- `kind`
- `deleted`
- `sealed`
- `bytes`
- `sha256`
- `updatedAt`

Optional vault parameters hold the KDF settings only.

The schema is closed. Unknown fields are refused anywhere except under `ext`,
so a misplaced token cannot travel with the archive. An unknown major version
or an unknown entry in `requires` is refused as unsupported.

Bounds are checked before any entry is read:

| Limit | Value |
| --- | --- |
| Manifest size | 4 MiB |
| Entries | 5,000 |
| Entry size | 1 MiB each |
| Total declared size | 256 MiB |

Entries carry content and identity only. Device sync state (`dirty`,
`serverVersion`, `syncedSig`) is never written. A sealed device row travels
as its vault payload, with its readable fields empty.

## Container (C12, `lib/recovery/export_writer.dart`)

```text
header : 'ATNA' | version 1 | mode (0 plain, 1 password)
         mode 1: kdf 1 = Argon2id | memory u32 | iterations u32 |
                 parallelism u8 | salt 16 bytes
frames : u32 length | payload
         frame 0 manifest, frames 1..n entries in manifest order,
         final frame trailer {"entries": n}
```

- **Mode 0 (plain).** Each entry is checked against the SHA-256 recorded in
  the manifest. The trailer detects truncation, and any bytes after it are
  refused.
- **Mode 1 (password).**
  - Each frame is sealed with AES-256-GCM (`VaultCrypto.aes`). The key is
    derived from an export password with `VaultCrypto.deriveKey`, using the
    vault's own Argon2id parameters: 65,536 KiB, 3 iterations, parallelism 1.
    A random 16-byte salt is stored in the header.
  - The associated data for each frame is SHA-256(header), the frame index
    and a trailer flag. This makes reordering, dropping, truncating or moving
    a frame between archives fail authentication.
  - The password and key are never stored.
  - A wrong password and a damaged frame give the same
    `authentication_failed` error.
  - Out-of-range KDF settings in the header are refused before any key
    derivation runs.
- **This is a new key context, not the note vault key.** It does not change
  the note KDF, salts or vault formats.

## Writer guarantees

- **Snapshot.** Sources are deep-copied before writing, so edits made after
  the export starts are not included.
- **Bounded memory.**
  - The writer encodes each entry twice: once to build the manifest, and once
    to write it.
  - Only one entry is held in memory at a time.
  - If the second encoding differs from the manifest, the export fails.
- **Atomic finalization.**
  - Output goes to `<target>.partial-<random>`. After flush and close, it is
    renamed over the target.
  - Any failure or cancellation deletes the temporary file and leaves the
    previous export untouched. Failures include a full disk and an I/O error.
    Cancellation is checked between entries.
  - On Windows, the old file is deleted only after the new one is complete.
    Android and iOS use a replacing rename.
- **Early refusal.** Invalid input is refused before any file is created, for
  example sealed rows without vault parameters, or ids the Server cannot hold.

## Verification

```text
flutter test --no-pub test/recovery        # 28 passed (15 manifest, 13 export)
flutter analyze --no-pub --fatal-warnings --fatal-infos
flutter test --no-pub                      # 1100 passed, 33 skipped
```

The tests cover the following:

- Plain round trip, read back from the file.
- Encrypted round trip with the right key, the wrong key and no key.
- A real Argon2id derivation of the export password.
- Changed bytes at 37-byte steps across a whole encrypted archive.
- A changed plain entry failing its checksum.
- Swapped frames in both modes.
- Truncation at several points, a dropped trailer, and trailing bytes.
- A hostile frame length and hostile KDF settings in the header.
- A full disk at 4 budgets, with the previous file preserved and no temporary
  file left.
- Cancellation.
- Edits made during an export.
- Write sizes staying frame-bounded.

## Open decisions (Codex/user)

- **Export password policy.** Minimum length or strength, and the UI wording.
  C15 owns the UI.
- **Plaintext rows of a vault account.** For now the writer exports what the
  caller passes. Whether such rows should be exported sealed is undecided.
- **Bounds.** Whether 5,000 entries and 256 MiB are right.

## Restore validation and preview (C13)

Two pieces cover this step. Neither is connected to a screen yet:

- `lib/recovery/import_validator.dart`
- `lib/recovery/import_preview_view.dart`

`ImportValidator.inspect` reads an archive through `ArchiveReader` and writes
nothing. Its only access to the device is a read-only `LocalNotesView.byId`.
It produces an `ImportPreview`.

### What `inspect` checks

- Every frame is authenticated. Every entry is checked for size and SHA-256
  before decoding.
- Each readable note is then held to the rules a save enforces, through
  `NoteContentBudget.errorFor`:
  - the format is supported, and images are valid JPEGs within 180 KB;
  - the title is at most 300 characters;
  - the note fits the sync size limits.
- A sealed (vault) note is always an issue, `sealed_unsupported`, so an
  archive that holds one cannot be restored yet. Its payload is sealed under a
  key derived from the recovery phrase and a salt bound to the source
  account's user id. The export password does not make it portable, and the
  archive carries no verified source-account context, so restoring it could
  write notes that never open. Supporting it needs a verified source context
  and a cross-account rekey path (open decision).
- The trailer must confirm the archive is complete.
- If the archive is damaged, truncated, unsupported or opened with the wrong
  password, `inspect` throws `ArchiveFormatException` and returns nothing.

### What the preview contains

- Counts: total, in use, in the recycle bin, checklists, images, encrypted.
- Ids sorted into three groups: new to this device, unchanged, or in conflict.
  A sealed note whose id already exists here counts as a conflict.
- One issue per note that cannot be restored, giving its id, a code and a
  limit message.
- No titles, bodies or images.
- For an encrypted archive opened without a password, a **locked** preview.
  It holds nothing, and not even the local note ids are compared.

### Restore button

`canRestore` is true only when the preview is unlocked and has no issues.
`ImportPreviewView` shows the counts and reasons, and enables "Review restore"
only in that case. Restore itself is C14: conflicts need an explicit choice,
and notes are never merged silently.

### Verification

`test/recovery/import_validator_test.dart` (9 tests) covers:

- counts and comparison with the device;
- locked preview, with no local reads;
- wrong password;
- corruption and truncation;
- unsupported container and manifest versions;
- duplicate ids;
- a damaged image, an over-long title and an over-size body;
- the preview widget: no note content shown, restore enabled or disabled.

Full suite: 1109 passed, 33 skipped.

## Transactional restore coordinator (C14)

`lib/recovery/restore_coordinator.dart` writes only through the
`RestoreStore` port. No adapter for the native repository is part of this
change. `notes_repository.dart` is reserved, and activating restore on devices
waits for B05 and the accepted backup gates.

### Steps

1. **Preflight (writes nothing).**
   - Refuses if an earlier restore has not finished.
   - Takes the `ImportPreview` the user approved. It must be unlocked and
     restorable, and carry a `digest`.
   - Inspects the archive again with `ImportValidator`, and requires
     `canRestore` and the approved `digest`.
   - Requires a `ConflictChoice` (`keepDevice` or `useArchive`) for every
     conflicting note. Notes are never merged and never guessed.
2. **Staging.**
   - Opens the archive again and reads its header and manifest. Their digest
     must still be the approved one, and no entry may be sealed. Otherwise
     the restore is refused before anything is written.
   - Writes a `staging` marker.
   - Reads every planned note. Each frame is authenticated and checked
     against the approved manifest's SHA-256 for that entry.
   - Writes a staged copy of each note. The target is not touched.
3. **Commit.**
   - Writes a `committing` marker.
   - For each note: backs up the target's previous version (once, or `null`
     if the note is new), then writes the staged copy.
   - Every step is idempotent.
4. **Cleanup.**
   - Writes a `cleanup` marker, discards the staged copies, then clears the
     marker. Backups are kept for the caller.

### Binding to the approved archive

`archiveDigest` is the SHA-256 of the header digest followed by the
authenticated manifest frame exactly as stored. The manifest lists each
entry's id, kind, flags, size and SHA-256, and the reader refuses an entry
that does not match, so an archive with the same digest yields the same notes.
An archive replaced after approval, or between preflight and staging, is
refused even when its ids and sizes match.

### What gets written

- Notes that are new on this device, and conflicting notes chosen as
  `useArchive`, are written as local changes: `dirty`, server version 0,
  empty `syncedSig`. The next sync uploads them.
- A sealed note keeps its `enc_v` and `payload`.
- Unchanged notes, notes chosen as `keepDevice`, and notes not in the archive
  are not touched.

### Resuming after a crash

`resume()` reads the marker:

- `staging`: discards the staged copies. The old target is intact.
- `committing`: repeats the commit.
- `cleanup`: finishes the cleanup.

### Verification

`test/recovery/restore_coordinator_test.dart` (8 tests) covers:

- The happy path: new and chosen notes are written, the rest are kept, and
  replaced versions are backed up.
- Refusals that write nothing:
  - a conflict with no choice;
  - an archive with issues;
  - a wrong export password;
  - an unfinished earlier restore.
- An encrypted archive restored with its key.
- **A crash at every one of the run's persistence boundaries.** Before
  `committing`, the target is byte-identical to the original, and `resume`
  undoes the restore. After it, `resume` finishes the restore exactly.
- A crash during `resume` itself, at successive boundaries, followed by a
  successful resume.

Full suite: 1117 passed, 33 skipped.

### Open decisions

- How long backups are kept, and the UI to undo a finished restore (C15/C20).
- Whether a partial restore (skipping invalid notes) is allowed.
- The native store adapter, which waits for B05.

## Recovery UI and backup status (C15)

`lib/recovery/recovery_page.dart` adds the "Backup and restore" page.

### Availability

The page is not on any route yet. It only works in builds made with
`--dart-define=ATOMIC_RECOVERY_PREVIEW=true`. In every other build it shows a
plain "not available yet" message and offers no actions. The native port
adapter waits for B05, because `notes_repository.dart` is reserved.

### Status shown

The page reports three facts. It never combines them into a single "your notes
are safe" claim:

- the number of notes saved on this device;
- the cloud sync status as the port states it, or "unknown";
- the last backup that actually finished.

### Backing up

- The user can set an optional password. The helper text warns that without
  one, anyone who has the file can read the notes.
- Progress is shown as "Saving n of m notes", using
  `ExportWriter.write(onProgress:)`, with a Cancel button.
- `recordBackup` runs only after the archive has been committed to its final
  location. If the export fails or is cancelled, no backup is recorded and the
  previous backup record is left unchanged.
- Encrypted vault notes are exported as they are, but restore refuses them
  (C13). When a backup holds any, the saved message and the "Last backup"
  line both say how many are included but cannot be restored from a backup
  yet, so the backup is never presented as a full restorable copy.

### Restoring

1. Choose an archive. If it is encrypted, it opens locked: enter the password
   and choose "Open with the password above".
2. The `ImportPreviewView` summary appears.
3. Each note that differs between the backup and the device gets its own
   switch. The default is "Choose before restoring", and "Review restore" stays
   disabled until every differing note has a choice.
4. `RestoreCoordinator` then restores the archive the user approved, passing
   that preview, and reports how many notes were written and how many were
   kept as they were on the device. If the archive changed since the preview,
   the restore is refused before anything is written.

An archive whose header asks for password settings other than the supported
profile is refused when its header is read, before any key is derived, with
a plain "not supported" message.

The preview never shows note content.

### Verification

`test/recovery/recovery_page_test.dart` has 9 tests:

- the feature gate is off by default and the page offers no actions;
- the three status facts appear separately;
- a finished backup is recorded;
- a failed backup and a cancelled backup are both never recorded, and the
  previous record stays unchanged;
- restore waits for every choice and then reports the result, with the
  replaced version backed up;
- a protected archive stays locked until its password is entered;
- a backup holding vault notes says they cannot be restored, and restoring
  it is refused with nothing written;
- unsupported password settings are refused with no key derivation.

### Open decisions

- Export password policy and final wording.
- Where the page sits in Settings.
- Who owns `recordBackup` storage and the native adapters (B05).
