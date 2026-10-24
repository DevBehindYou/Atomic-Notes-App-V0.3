# Automatic note images under 24 KB

**Historical policy:** the owner's later quality request supersedes the 24 KB
cap with [60 KB per image](IMAGES_60KB_2026-10-24.md). The automatic, no-prompt
insertion flow remains; the limits and quality settings below record the earlier release.

The 2026-10-24 user request supersedes the manual image optimizer. Selecting a
new gallery image automatically prepares and inserts it into the isolated draft.
There is no quality sheet, settings step, or attachment confirmation. Done still
saves the note; discard and picker cancellation preserve the original note.

## Bounds and compatibility

- Every newly inserted JPEG must contain at most **23,999 bytes**, strictly less
  than 24,000 bytes. The adapter clamps larger caller budgets to this limit.
- The editor also applies the remaining aggregate image budget (60 KiB) and the
  existing full-note plaintext/encrypted wire checks before inserting anything.
- Legacy embedded JPEGs up to 60 KiB remain readable and are never recompressed
  when a note is opened or saved. The rich-document schema and server stay unchanged.
- Native selection stays bounded to 1024 pixels; source reads stay under 8 MiB.
  Header validation rejects dimensions over 4096 or more than 4 Mi pixels before
  pixel decode. JPEG output strips source metadata and preserves aspect ratio.
- The existing compute isolate tries quality 70, 55, then 40, reducing maximum
  dimensions through 1024, 768, 512, 384, 256, 192, and 128 as needed. It never
  enlarges a source. If the available budget cannot fit an image, the draft stays
  editable and a clear error explains that no image was attached.
- `_picking` prevents overlapping operations. No new dependencies, permissions,
  uploads, HTTP image fetches, server fields, or original-image rewrites are added.

## Verification and ownership

This slice owns the image adapter, its tests, the editor's `_pickImage` flow, and
media integration tests. It removes the obsolete manual optimizer module/tests.
Popup and selection-toolbar work continues independently in the other worktree.

Required checks: high-entropy automatic downsizing; strict per-image and remaining
budgets; full-note rejection without draft loss; direct insert/save/reopen; picker
cancel; error recovery; unchanged old JPEG bytes; adapter and editor regressions.
Record actual test results after running them; source checks are not device acceptance.

Focused local verification passed 36 adapter/editor integration tests, including
actual compute and direct insertion, high-entropy downsizing, exact 24,000-byte
rejection, complete-note budget rejection with draft preservation, and unchanged
legacy image bytes. Independent source review found no actionable bugs. Full
combined regression, CI and physical acceptance remain separate gates.
