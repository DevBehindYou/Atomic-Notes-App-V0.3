# Three images per note

New image additions share one limit of **three images total per note**, regardless
of the source format. The existing gallery pipeline supports JPEG and PNG input
and stores automatically optimized JPEG bytes. Source formats do not create
separate allowances. The owner's later quality update raises new images to at
most 60,000 raw bytes each, with a 180,000-byte aggregate budget. Complete-note
plaintext/encrypted sync bounds still apply; see
[the current 60 KB implementation](IMAGES_60KB_2026-10-24.md).

## Behavior and compatibility

- The editor checks the count before opening the gallery and again after the
  awaited result. At the limit it explains: “Use up to 3 images per note. Remove
  an image first.” No image is attached and the draft remains editable.
- `NoteDocument.insertImageAfter` enforces the same rule atomically, protecting
  callers that bypass the editor or use an injected image adapter.
- The rule applies to insertion only. Decoding and saving existing notes with
  more than three images remain supported without truncation, recompression,
  schema migration, or changes to existing image bytes. Removing images remains
  available; a new image can be added when fewer than three remain.
- This is a client editor policy. It adds no server rejection that would block
  synchronization of already saved legacy notes. Other clients need the same
  insertion policy before claiming the limit across every platform.

## Focused verification

Meaningful regressions cover the third insertion, fourth rejection before any
picker call, atomic direct model insertion, unchanged four-image legacy save,
removal and restored capacity, and actual JPEG/PNG compute inputs sharing the
same cap. Existing per-image, aggregate, metadata and draft-preservation tests
remain relevant. Physical device acceptance is a separate gate; do not delete
legacy device images to manufacture compliance.

Local verification on this branch: **88 tests passed** across the complete editor
suite and note document, rich content, Hive persistence and notes BLoC suites.
The missing insertion cap was reproduced before the fix. These are source
checks; final required CI and physical acceptance remain separate gates.

Fatal analysis also passed with no issues using both Flutter's analyzer and the
SDK's direct `dart analyze --fatal-infos --fatal-warnings` command. `git diff
--check` passed. No device data was modified by these local checks.
