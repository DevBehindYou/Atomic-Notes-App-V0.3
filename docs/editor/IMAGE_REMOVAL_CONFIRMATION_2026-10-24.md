# Confirm image removal

An image is removed from the editor draft only after an explicit decision.
Tapping **Remove image** opens the existing paper/ink editor popup with a bordered
**Keep image** button first and a red **Remove image** button. The popup explains
that **Done** is needed to save the change.

Keep image, Android Back, or backdrop dismissal retains the image. Confirm
removes that image from the isolated draft; the original note and stored image
bytes remain untouched until Done. The note's prose, tags and other images are
preserved. Existing checklist item removal is unchanged.

The pending decision retains the image row's controller identity, then resolves
its current position on confirmation. An intervening row change cannot redirect
removal to a different image or text row. Duplicate requests share one decision;
disposed/closing editors ignore late decisions. Opening the popup cancels any
active dictation through the existing editor session guard.

The popup reuses the editor's scrollable surface, typography and minimum 48px
Material controls. Both decisions remain reachable on 320px screens with 2x text
and keyboard insets.

Focused regressions cover explicit confirmation, Keep/Back/backdrop preservation,
draft-only mutation until Done, selected image identity after another row moves,
duplicate requests, and narrow large-text accessibility. Existing media count
regressions now explicitly confirm removal. Source gates and physical device
acceptance are recorded separately; source tests do not claim a device pass.

Local verification: the missing prompt was reproduced before the fix. All7
focused confirmation tests passed, including unsaved prose and selection
preservation. The complete editor regression gate passed79 tests before the
additional focused selection case; the final focused run passed all7. Whole
worktree fatal Dart analysis and diff whitespace checks passed. Required CI,
independent final review and physical acceptance remain separate gates.
