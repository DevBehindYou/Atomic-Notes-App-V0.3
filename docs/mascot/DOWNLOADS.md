# Superseded: optional mascot downloads

On 21 October 2026 the user replaced the optional-download architecture with a bundled-only implementation. All 13 supplied characters and 52 unchanged GIFs ship in the app. There is no mascot HTTP client, release delivery, private pack storage, download, preview-fetch, or removal flow. Favorites and motion preferences remain local. The original download implementation was reviewed and merged in PR75 before this scope change; it is removed by the follow-up bundled implementation. See BUNDLED.md for current behavior and acceptance gates.
