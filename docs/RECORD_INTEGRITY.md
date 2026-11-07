# Local record and tombstone integrity (C19)

`lib/recovery/record_integrity.dart` scans a raw notes store (the
`key → value` map of `notesBox`) and reports records that are not sound
notes. It only reads.

## Why it is needed

Today the repository's `_loadFromDisk` handles bad rows quietly:

- It **skips** values that are not maps, or that have no string `id`.
- `Note.fromMap` **coerces** wrong field types, for example `toString()` on a
  title, and **defaults** fields that are missing.

So damaged rows either vanish from the UI without any notice, or reappear
silently altered. The scanner makes both cases visible.

## What it reports

Reserved bookkeeping keys (`__cache_owner__`, `__sync_cursor__` and other
`__…` keys) are skipped. Each finding is a key plus a code:

| Code | Meaning |
| --- | --- |
| `invalidKey` | The key is not a note id. |
| `notARecord` | The value is not a map, or has no string id. |
| `idMismatch` | The id inside the record differs from its key. |
| `duplicateId` | The same id is stored twice in different letter case. |
| `malformedFields` | A field has the wrong type or an unknown value (kind, flags, dates, items, `serverVersion`, `syncedSig`). |
| `malformedRichContent` | A rich document fails to parse. These are the rows the editor would open read-only. |
| `contradictorySealing` | The vault fields contradict each other: a payload without `enc_v`, `enc_v ≥ 1` without a payload, or sealed and readable content in the same row. |

The tests confirm that these sound shapes are not flagged:

- plain rows, checklists and rich documents with tags and images;
- tombstones;
- sealed rows (readable fields empty, payload present);
- legacy rows (no flags, no vault fields, `text`/`done` item keys).

A tombstone that still holds its content is **sound**. The recycle bin keeps
that content on purpose.

## What it never does

- It never deletes, rewrites, merges or repairs a record.
- `preserveCopies` copies each flagged record, exactly as stored, into a
  `QuarantinePort` (an add-only port) together with its problem codes and its
  raw key. The source stays where it is.
- Each flagged record has a collision-free, type-tagged locator: `i:<n>` for
  an int key and `s:<text>` for a String key. Int `1` and String `'1'` are
  two records (`i:1`, `s:1`), and a String key such as `'i:1'` becomes
  `s:i:1`, so it cannot forge another locator. Keys of any other type, which
  Hive never stores, get an ordinal `o:<n>:<type>`. Records are looked up by
  their typed raw key, never by its text.
- Findings hold ids and codes only, never note content.
- It is not wired to the device repository. `notes_repository.dart` is
  reserved, and integrating the scanner waits for its owner gate.

## Verification

```text
flutter test --no-pub test/recovery/record_integrity_test.dart   # 6 passed
flutter analyze --no-pub --fatal-warnings --fatal-infos
flutter test --no-pub                                             # 1171 passed, 33 skipped
```

## Open decisions

- Where quarantined copies live on the device, and for how long.
- Whether the UI should show the scan (C20 diagnostics).
- Any automatic repair. None is proposed.
