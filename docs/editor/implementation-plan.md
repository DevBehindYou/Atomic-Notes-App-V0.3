# Note editor implementation and acceptance plan

Reference: user-supplied `02 · Note Editor-html.zip`, inspected as data, never executed. Its fixed 390 × 844 layout and mostly inert controls are visual references rather than working requirements. User requested implementation, retained round actions, and chose speech dictation. Latest refinement: a persistent B / I / U / S / H row **above** the platform Cut / Copy / Share / Select all selection actions; successive toggles retain the selection.

## Design and scope

- Keep paper #F4F5F1, ink #15171B, signal #3A2FF0, existing type families, current 24px note title, white important-card titles and accepted launcher/splash. Dark theme remains cancelled.
- Compact back/breadcrumb/editor heading, pin and important actions. Keep Copy accessible. No decorative history button without history storage.
- Show last saved edit time separately from draft status. Done commits through existing repository; no false autosave or cloud-save claims.
- Tags: add/remove, trim and deduplicate, bounded count/length; persist with encrypted content. No invented folder hierarchy.
- Selection styles: bold, italic, underline, strike, paragraph heading. H means Heading as requested, although the prototype labels it Highlight. Preserve native selection actions and keep styles independently toggleable. Provide 48px touch targets, selected semantics, keyboard-safe placement and overflow for narrow screens.
- Round bottom actions: text line, checklist, image, dictation, delete; Done remains visible. Footer wraps/scrolls at narrow widths and large text instead of shrinking targets. Live visible words, ceiling reading time at 200 words/minute, completed/nonempty task count. No JSON/base64 in counts, preview, search or clipboard.
- Images are bounded compressed JPEG blocks embedded in encrypted note content, not externally hosted. Picker cancellation/error preserves draft. Reject oversize notes before commit with an actionable message.
- Dictation inserts at the current selection. Partial recognition replaces its own segment rather than accumulating duplicates. Explicit start/stop, cancel on lifecycle/route exit, permission only on use. The device speech service may process audio remotely; tell the user before first use. No audio file storage.
- Delete uses the normal recycle-bin repository action after explicit confirmation, not clearing text and saving an empty note. Unsaved notes can be discarded locally.

## Architecture and compatibility

Versioned typed document in existing body plus exact reserved item marker, `atomic-notes:rich-document:v2`. No new Hive adapter, outer wire field or server field. Existing seal/open, signature and sync envelope carry content. Plain and task-lines-v1 notes retain bytes until changed; unmarked JSON/Markdown stays literal. Unknown or malformed versions open read-only and preserve opaque bytes. Shared projection drives preview, search, counts, clipboard and task toggles.

The richer format is not safe to edit with older released clients. Source merge and staging verification are distinct from production rollout: a mixed-client minimum-format/capability policy is a release gate before enabling new content against production. No production deployment or staging green flag is implied by this work.

Image aggregate ceiling 60 KiB, subject to actual full-note body, sealed ciphertext and JSON row budgets. UTF-8, escapes and base64 overhead must be measured; never bypass limits with large item strings. Existing very long synthetic notes must still reopen without eager rewriting.

## Parallel ownership and dependency order

1. Storage agent: rich model/codec, budgets, Note/Bloc/repository projections and regression tests; `note_document.dart`, `note_rich_content.dart`, Note and state seams. PR foundation first.
2. Formatting agent: `editor/rich_text_controller.dart` and controller tests only. UTF-16 ranges, composing spans, edit transforms and paragraph-heading boundaries. Depends on public style model.
3. Media agent: injectable gallery/JPEG and speech adapters, dependencies/lockfile, Android microphone/service manifest and adapter tests. No editor widget edits.
4. Root: responsive editor integration, selection menu above native actions, tags, footer/read status, Home rendering/routing and integration tests. Review foundation then integrate UI in a focused dependent PR. No concurrent edits to owned files.

Do not commit private device caches, old notes, credentials or original dirty mirrors. Work in the existing small C: checkout; no D: usage or duplicate full project copies.

## Verification gates

- First reproduce missing functionality with failing tests; then unit-test typed roundtrip, legacy unchanged signatures, malformed/unknown versions, limits, style combination/edit transformations, UTF-16/IME, headings, JPEG bounds, speech partial/final/cancel behavior.
- Widget tests: Save/Discard/system Back, tags/styles/media persistence, empty-block cleanup, native actions retained beneath live formatting row, repeated toggles retain selection, delete uses recycle bin, narrow/landscape/keyboard/large text, denied/cancelled media preserve draft, no raw payload leakage in cards/search.
- Run analyzer and relevant/full tests. Independent diff review; fix real findings. Create focused PRs, attach, wait for required CI, confirm review and no conflicts, then merge under standing authorization.
- Build exact merged source in Actions. Before installation, snapshot latest Atomic Test data privately; preserve all existing 20 synthetic notes and any subsequent user edits. Device test uses a separate synthetic editor note. Do not grant microphone permission silently or operate other apps.
- Device: text/checklist alternation, styles/stacked selection menu, tags, JPEG, dictation where user/system permission allows, Save/reopen, search keyboard stability, dark-card white title, safe-area/keyboard and staging roundtrip. Report actual passed/blocked checks; UI tests and CI do not establish production, iOS or Web readiness.

## Progress reporting

Report this editor batch as analysis / implementation / verification, with blockers. Broader program percentages remain estimates tied to documented scope; do not treat a completed editor slice as whole-app completion. Record exact source, test evidence and remaining rollout gates for the next agent.

## Primary API references consulted

- Flutter local SDK `TextEditingController`, `EditableTextState.contextMenuButtonItems`, `TextSelectionToolbar` and `AdaptiveTextSelectionToolbar` implementations.
- https://github.com/csdcorp/speech_to_text/blob/main/speech_to_text/README.md
- https://pub.dev/packages/image_picker and https://pub.dev/packages/image_picker_android
