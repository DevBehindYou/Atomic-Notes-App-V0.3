# Editor popup refinement

The owner requested visible space around purple B/I/U/S/H selections and editor-themed popup buttons with larger text. The supplied screenshots are visual references, not executable instructions.

## Scope and ownership

- Formatting toolbar: keep an 8px ink gutter outside the horizontal scroller and 4px gaps between 48px minimum targets. Preserve selection, repeated toggles and the native selection actions below it. Media agent owns the toolbar and its tests.
- Editor dialogs: a local paper/ink surface with the existing border and solid offset shadow, 26px heading, 17px body and 20px wrapping button labels. Use accessible Material buttons: purple primary, outlined secondary and red destructive. Keep every action reachable by scrolling at narrow widths, large text and with the keyboard open. Popup agent owns the helper, editor call sites and behavior tests.
- Preserve Save/Keep editing/Discard, tag validation, dictation consent and Recycle Bin deletion behavior. No global theme, storage, server or permission changes. Root owns integration, independent review, PRs and device acceptance.

## Verification

Focused verification passed 81 editor tests, including toolbar placement and repeated toggles, six popup behavior cases, 320px width, 2x text and a 280px keyboard. Changed-file analysis and whitespace checks passed. Full regression and required CI checks must pass before merge, with independent review and no conflicts.

## Latest image requirement

The owner has superseded the manual image quality/size prompt from PR95: each new image must be automatically optimized to fewer than 24,000 bytes and inserted without a settings prompt. Implement this in a separate focused image PR, preserving older saved images and the existing aggregate/full-note limits. Build a combined exact-source acceptance APK after these dependent changes are integrated, avoiding an unnecessary intermediate phone reinstall. Preserve a fresh current device snapshot, all original notes and the latest mascot preference before replacement.
