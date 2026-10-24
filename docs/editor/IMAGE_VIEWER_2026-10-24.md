# Note image preview

## Accepted behavior

Tapping an embedded image opens a read-only, paper/ink popup. The image initially fits fully inside the safe viewport with its intrinsic aspect ratio; portrait and landscape images therefore produce different popup proportions. The popup stays bounded when the screen rotates, the keyboard is visible or text is enlarged.

Pinch to zoom up to 5x and pan to inspect details. Accessible, keyboard-operable 48px controls also provide Zoom in, Zoom out, Reset zoom and Close. System Back, Escape and the outside barrier dismiss the preview. Resizing the viewport resets zoom so a previous pan cannot leave a rotated image offscreen. A decode error keeps an accessible Close control available.

Opening the preview cancels any active dictation and clears the actual text-field focus, avoiding keyboard reopening on dismissal. Late speech results cannot alter the draft. Viewing an image never invokes the picker, compressor, repository or server. The preview reuses the editor's cached original bytes through Flutter's shared image cache; it does not recompress, replace or save content. Closing preserves unsaved text and original image bytes. Done remains the only commit action.

## Implementation ownership

- `lib/editor/note_image_viewer.dart`: popup sizing, asynchronous image dimensions, listener/image-handle disposal, transformation controller, controls and decoding failure.
- `lib/page/notes_editor_page.dart`: accessible image opener and existing speech/focus seams only.
- `test/editor/note_image_viewer_test.dart`: portrait/landscape fit; 320px/2x text/keyboard and rotation; real two-pointer pinch, pan and buttons; keyboard/semantics; invalid decoding; Close/Back/barrier draft and byte preservation; late dictation cancellation.

The separate three-image insertion limit belongs to the media/document addition path. Existing image decoding and old notes remain compatible; this preview introduces no schema, package, permission, server or network change.

## Verification gates

Run the focused viewer tests, nearest editor regression suite and fatal analysis before publishing. Independent review, required CI checks and conflict checks must pass before merge. Physical pinch/fit/close acceptance requires an exact-source APK after dependent image-limit work is integrated; source tests are not a device acceptance claim. Device replacement must preserve a fresh current snapshot, including the existing test note with four images and all latest user edits.

## Local proof, 24 October 2026

- Final focused viewer suite: 8 passed, including two-pointer pinch and accessible error dismissal.
- Nearest regression: all 70 tests in `test/editor` passed.
- Final `dart analyze --fatal-infos --fatal-warnings`: no issues.
- `git diff --check`: clean. No device operations or production requests were performed by this slice. Required CI, independent review and exact-source physical acceptance remain separate gates.
