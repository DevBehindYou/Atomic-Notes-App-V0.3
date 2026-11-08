# Editor accessibility (C10)

Scope: the note editor (`lib/page/notes_editor_page.dart`), its formatting bar
(`lib/editor/rich_selection_toolbar.dart`), the image thumbnail and viewer, and
the editor dialogs (save on close, image removal, add tag). Mascot files are
out of scope.

## Method

The audit came before any change. A widget-test probe ran Flutter's
`androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline`
and `textContrastGuideline` on a mixed note (prose, checklist item, image,
tag) at 1x and at `TextScaler.linear(2)` on a 320x640 screen. It also ran them
on the formatting bar, the add-tag and save dialogs, and the image viewer. It
dumped every tappable, text-field and image semantics node, and recorded the
Tab focus sequence. Only defects the probe showed were fixed.

## Findings

| # | Control | Defect (evidence) | Fix |
|---|---------|-------------------|-----|
| 1 | Formatting B/I/U/S/H | Button label was the glyph letter (`label="B"`, `tooltip="Bold"`), so it was read as "B" plus "Bold". | Glyph wrapped in `ExcludeSemantics`. The tooltip is the only name. |
| 2 | Formatting B/I/U/S/H | The `toggled` state sat on a separate unnamed node around the button. The button node had only `hasSelectedState`. | `MergeSemantics` puts the toggle state on the button node, and it follows the style. |
| 3 | Image thumbnail | `label` and `tooltip` were both "View note image", and the image added a second "Note image" node inside the button. | Tooltip and image are excluded from semantics. There is one button named "View note image". |
| 4 | Add tag button | Read as "Tag". Its "Add tag" tooltip was not on the button node. | `semanticsLabel: 'Add tag'`, and the tooltip is excluded from semantics. The visible "Tag" text is unchanged. |
| 5 | Title, text line, checklist item fields | The only name was the hint. Once a field was filled its name was empty (`label=""`, `value="Groceries"`), so the field type was lost. | `_FieldName` adds `Title` / `Note text` / `List item` as the label when the field has text. An empty field is still named once, by its hint. |

These already passed and are now guarded by tests:

- All four guidelines, at 1x and 2x, in the editor, the dialogs, the
  formatting bar and the image viewer.
- 2x text on a 320x640 screen with no layout exceptions. Done, the tag dialog's
  Add and all three save-dialog actions stay reachable.
- Every icon-only control has a tooltip name: Back, Pin, Important, Copy, the
  round bottom controls, remove item, remove tag and the viewer controls.
- Tab order: Back, Pin, Important, Copy, title, tags, add tag, lines in
  document order (checkbox, field, remove), image view, Remove image, the
  bottom controls, then Done. Focus then wraps to Back.

No colours, control order, visible wording or layout changed.

## Tests

`test/editor/editor_accessibility_test.dart` has 9 tests. Against the code
before the fix, 4 failed: findings 1, 3, 4 and 5. Finding 2 sits behind
finding 1's assertion in the same test. The other 5 passed and are regression
guards.

## Open decisions

- Checkbox and remove-item labels number by document line, not by checklist
  position. In a mixed note the first checklist item is "Complete item 2". The
  labels are left unchanged because existing tests and tooling refer to them.
  The choice is between checklist-position numbering and the item text.
- The tag dialog field is named by its hint, "For example, morning". The
  dialog's "Add tag" heading names the route. A visible label would change the
  dialog's look, so the field is unchanged.

## Not verified

- TalkBack (Android) and VoiceOver (iOS) on real devices. They were not run.
  How each platform announces a combined tooltip, label and toggled/selected
  state is unconfirmed.
- Hardware-keyboard behaviour on devices, and the system text-size settings
  beyond the 2x scale used in tests.
- `textContrastGuideline` samples rendered text in the test font only. It does
  not check the production fonts or non-text contrast (icons, borders).
