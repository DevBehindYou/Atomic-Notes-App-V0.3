# Notes home and editor migration — 13 October 2026

Scope: the owner's Notes Home and Note Editor HTML references are visual specifications, not runtime code. No React scripts, dependencies, remote fonts or mock note data are included in the application.

## Behavior

- Home preserves its existing header, navigation, filters, capacity enforcement, selection and live mascot status. Search and DevBehindYou share one centered row, above the existing filters.
- A leading pinned note occupies the full width. Other notes use the existing lazy masonry layout, with a single column on narrow windows or large text. Dates, pin indicators and checklist progress come from the note. Inline checklist toggles remain functional.
- The single New note action replaces the separate Checklist creation button. Checklist creation is available using the editor's mode switch.
- The editor uses existing paper/ink/signal tokens and bundled fonts. It includes title, body/checklist, pin, copy, word/progress counts and Done.
- Changes remain an isolated draft until Done or Save in the back-navigation prompt. Explicit Discard leaves the caller's note untouched. Save retains the existing caller/Bloc/repository persistence contract; the editor does not claim the draft is already saved or uploaded.
- Text/checklist conversion reads current controllers; copying never filters the live checklist's rows. A mode round trip with unchanged rows preserves check marks.
- There are no pretend formatting, image, voice, folder, tag, history or automatic-save controls. Those mockup features require separate model and persistence work. Existing selection-based deletion remains on Home.

## Validation and boundaries

Widget tests cover draft save/discard/back, copy with empty rows, mode conversion, capacity enforcement, leading-card placement, search/mascot placement, metadata, selection and narrow/large-text/keyboard layouts. CI additionally runs strict analysis, the complete Flutter suite, existing disposable App–Server tests and a debug Android build.

The bounded notes UI artifact contains outcomes and source-line references only. Three synthetic, font-loaded widget previews are generated for visual inspection; these are not screenshots from a connected phone. No real account or notes are read. Production deployment, signed release, WebApp readiness and device acceptance remain separate gates.

## Roadmap integration

This is an Android 2.03.9 UI increment on the accepted V0.3 base. It adds no backend, schema, session, encryption or asset-wire changes. Reuse these Flutter components for the WebApp after its platform isolation and browser durability gates pass.

The accompanying refined architecture proposal is reviewed separately: multiple API entry points require one authoritative mutation protocol. A shared database alone does not make unchanged legacy and optimized writers compatible. The proposed multi-host rollout must be reconciled with the previously recorded same-URL rollout before infrastructure changes.

Original optimization acceptance stays 19/28 implemented (68%), 7/28 partial (25%), 2/28 open (7%). This UI increment does not close unrelated migration, recovery or production gates.
