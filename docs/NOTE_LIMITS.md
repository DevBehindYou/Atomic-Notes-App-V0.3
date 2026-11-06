# Note limits: where each one is enforced (C08)

| Limit | Unit | Enforced | Where | Legacy content |
| --- | --- | --- | --- | --- |
| 3,000 words | `\S+` runs (Unicode whitespace) over the title and text lines | On save. The counter turns red while editing. | `NoteWordLimit`, editor `_finish` | A note already over the limit can keep up to its original count (`LEGACY MAX`). |
| 3 tags | Case-insensitive unique tags | When a tag is added | `NoteDocument.setTags` | Kept. Removing a tag is always allowed. |
| 15 characters per tag | Grapheme clusters (`characters`); a leading `#` is stripped first | When a tag is added | `NoteDocument.setTags` and the tag dialog | Kept (legacy reader: up to 40 UTF-16 units). |
| 3 images | Image lines | When an image is inserted | `NoteDocument.insertImageAfter`, editor `_pickImage` | Kept. Images can still be removed. |
| 60,000 bytes per new image | Raw JPEG bytes | On pick | `PlatformEditorImageInput` | Reader still accepts 60 KiB. |
| 180 KB of images | Raw bytes, summed | On insert and on save | `NoteDocument`, `NoteContentBudget` | — |
| 300-character title | UTF-16 code units, matching the Server | On save | `NoteContentBudget.maxTitleLength` | — |
| Body, payload and wire size | See `NoteContentBudget` | On save | `NoteContentBudget.errorFor` | — |

Notes are never truncated when they are read, synced or saved. Every limit
either refuses the action with a message or blocks the save, and the draft
stays as it was.

## Changes in C08

- **The tag dialog no longer cuts pasted text.** The field used to apply
  `maxLength` enforcement, so a pasted 20-character tag was silently shortened
  to 15. A leading `#` also counted against the limit. The counter still shows,
  and an over-long tag is now refused on Add with "Tags must be 15 characters
  or less".
- **The title error names only the title.** It used to add "Shorten the note
  or remove an image".

## Ambiguities (documented, not changed)

- **Text with no spaces counts as one word per run.** Languages written without
  spaces (Chinese, Japanese, Thai) can therefore exceed 3,000 visible words
  without reaching the word limit. The size limits still apply.
- **The title counts UTF-16 units, but tags count visible characters.** Emoji
  therefore count double in titles. This matches the Server bound.
- **Words are checked only on save.** Paste and dictation can take a draft over
  the limit. The counter shows it, and the save is refused without losing text.
