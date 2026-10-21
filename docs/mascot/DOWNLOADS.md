# Verified optional mascot packs

Cubie is bundled. Other supplied characters are fetched only after an explicit Preview or Download and use action. Playback only opens local verified bytes and never initiates HTTP.

Each download is pinned to the catalog size and SHA-256 digest, bounded to 2 MiB per GIF, with HTTPS redirects restricted to GitHub release hosts. An entire pack becomes ready only after all four original GIFs verify. Partial and cancelled work cannot become an installed pack. Retry is bounded and reuses already verified files. Downloading needs no GitHub account or app credentials.

The private store caps installed packs at 32 MiB, preview data at 2 MiB, and staging at 6 MiB. An injected platform free-space check reserves an additional 1 MiB before writes. One preview is cached; replacing it evicts old disk and in-memory preview data. Removal refuses Cubie, the selected character, and packs with active byte leases. File operations reject symbolic links under the owned store. Selection is rechecked at the deletion boundary; a reserved removal temporarily makes that pack unavailable to Settings.

## Validation

The focused download-client suite has six cases. The store and repository suites have eighteen, including modified hashes, oversized responses, cancellation, hostile redirects, retry limits, atomic readiness, preview eviction, lease/removal races, and linked paths. Native integration, public release delivery, and real-device acceptance are separate gates.

The release assets have not been published at this step. See RELEASE.md when available for the asset inventory and anonymous delivery checks. Android private storage is integrated in the following app-wiring change. iOS and browser download adapters remain conditional on their platform foundations.
