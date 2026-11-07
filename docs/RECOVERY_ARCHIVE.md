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
