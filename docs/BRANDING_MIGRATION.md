# DevBehindYou mascot and Atomic Notes icon migration

Status: implementation candidate; build and visual acceptance are pending. This
adds a branding workstream to the 2.03.9 optimization plan. It does not change
account ownership, notes, sync wire formats, Energy, vault keys or app identity.

## Architecture and verified platform boundary

Verified in source at the accepted App #56 baseline: Home is driven by
`NotesBloc` (`lib/page/home_page.dart:6`), with a local-first Hive repository and
separate API client. `LogoContainer` composes `InkLogoMark`
(`lib/utility/component/logo_container.dart:21`) and is shared by login,
Settings, splash, device lock, TOTP and vault unlock. Reusing these components
updates those screens consistently rather than duplicating branding per page.
The existing `flutter_svg` and launcher tooling are already dependencies
(`pubspec.yaml:53`, `pubspec.yaml:82`); no runtime package is added.

Android is the configured release target: the verification workflow builds a
debug APK (`.github/workflows/flutter-ci.yml`), and
`.github/workflows/release-android.yml` contains the manually dispatched signed
release. `android/app/build.gradle` declares `com.notes.atomic`, minimum API 28
and target API 35. Those identifiers and signing settings must remain unchanged
for installation upgrades. `MainActivity.kt` owns the screen-security bridge and
FLAG_SECURE; icon migration must not modify it.

iOS/macOS, Windows/Linux and web directories are present, but directory presence
does not establish product support. No corresponding verified release pipeline
exists here. iOS/macOS have incomplete product/auth configuration; the desktop
scaffolds lack the shared Google sign-in implementation. Their packaging is
outside this Android migration. GitHub Pages deploys the documentation showcase,
not an installable Flutter PWA (`.github/workflows/deploy-pages.yml:9`). No claim
of iOS, PWA or desktop compatibility is made.

## Source audit and visual provenance

The supplied JPEG master is 1080 by 1080 RGB, 36,603 bytes, with no alpha. Its
SHA-256 is `3114c97ad9fe8ce43d5760e9399be135c0a0a1608b528e3aab6f4155bfa546e9`.
The supplied `assets/new-atomic-icons` pack includes editable transparent vector
companions and light/dark/monochrome raster versions. These preserve the logo
identity but are geometric reconstructions, not pixel-identical JPEG cutouts.
The dark companion changes the dark orbit/nucleus to Paper for contrast. Reuse
these supplied native sources, retaining the JPEG as artwork provenance; do not
threshold the JPEG background or pretend a renamed JPEG has transparency.

The Worker GIF is 1285 by 1285, 52 frames, a four-second loop, 218,176 bytes.
Dotgrid is 400 by 480, 109 frames, a 4.82-second loop, 827,440 bytes. Both contain
transparent frames. Compressed size alone understates decoded memory: one full
Worker RGBA frame is about 6.6 MB. Runtime image decoding therefore follows the
logical display size times device pixel ratio, with a bounded decode width.

Word-bounded `Atomi` appears only in two Home comments at the baseline
(`lib/page/home_page.dart:258`, `:263`) and the original license's reserved names
(`LICENSE:94`). The active mascot was dotgrid; no Atomi class or filename was
found. Home comments and active mascot identity change to DevBehindYou. Preserve
the license wording as a legal exception, not a current branding statement.

## Workstream and dependencies

| Priority | Work | Dependency / acceptance |
|---|---|---|
| P0 | Preserve app identity, account/data gates and the original licenses | Unchanged namespace/applicationId/security bridge; all existing wire and logout checks remain required |
| P1 | Complete live mascot status fix in App #58 | Preserve its truthful local-pending wording and live overlay; rebase this branding branch after that PR |
| P1 | Build reproducible Android icon and splash library | Inspect supplied sources; verify alpha, safe zones, density sizes, resource references and asset budgets |
| P1 | Use Worker on Home and dotgrid as secondary activity accent | Shared component; fixed layout; reduced-motion/static fallback; no sync or navigation dependency on decoding |
| P1 | Replace shared logo references | Shared mark covers login, Settings, lock/TOTP/vault, splash and About; logout uses dark variant |
| P2 | Remove obsolete active assets after reference audit | Delete only proven unused old runtime artwork; preserve user design libraries, historical evidence and license |
| P2 | CI and visual acceptance | Strict analysis, entire suite, controlled recovery/wire evidence, debug APK and native resource inspection |
| Release gate | Physical launcher/splash and signed upgrade acceptance | Circular/rounded/themed/light/dark icons, reduced motion, Android API coverage and existing-data upgrade; separately authorized device/release work |

This work can run alongside the inactive Server readback guard because there is
no shared API/schema change. Home source is serialized after App #58 to avoid
overwriting its status correction. Asset/config work and source audit can run
before that dependency merges. Branding is tracked separately from the original
28 findings; adding it does not inflate their completion percentage.

## Runtime and native behavior

The shared mascot selects Worker by default and dotgrid for small secondary
activity accents. Static exported frames replace GIFs when reduced motion is
requested or a route is inactive. Home retains its 72-pixel clip and existing
sync bubble interaction, with the accessible name “DevBehindYou sync status.”
The mark selects a contrast variant for its actual background. Neither asset
loading nor animation completion is awaited by startup or logout.

Native Android splash assets are static vectors with light/dark backgrounds.
GIFs are post-launch Flutter assets only. An AnimatedVectorDrawable is optional,
not necessary for this migration; a static native splash avoids an extra
animation handoff and dependency. Existing startup routing still contains its
historical fixed display waits; new animation does not extend those waits. Their
removal requires a separate actual-startup navigation check rather than an
untested change to security gates.

The API notification feed does not implement native push notification channels.
The simplified single-color notification resource is prepared for compatibility;
generating it does not add a native push service or claim delivery support.
Only the two logo PNGs and two static mascot frames are added to Flutter's
runtime asset declarations. Optional rotating-logo GIFs, previews, monochrome
design sources and native/store artwork are not bundled by that declaration.
The named Worker and dotgrid GIFs remain in the existing animation directory.
Nine exact obsolete files were removed after reference checks: the old three
root artwork files, showcase icon and five unused adaptive foreground mipmaps.
Unreferenced user-supplied design libraries remain preserved.

Android adaptive layers use the 108 dp canvas and central 66 dp artwork limit,
with separate monochrome artwork. Legacy launcher PNGs use the five requested
density dimensions. Google Play artwork is a square, opaque-background 512 px
32-bit PNG below 1 MB, without manually rounded corners or shadow. See the
[Android adaptive icon specification](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive),
[native splash specification](https://developer.android.com/develop/ui/views/launch/splash-screen),
and [Google Play icon specification](https://developer.android.com/distribute/google-play/resources/icon-design-specifications).

## Validation and risks

Passed locally: deterministic packaging and its independent standard-library
verifier's eight cases (source assets, library hashes, adaptive layers, launcher
densities, native splashes, Play icon, mascot frames and notification artwork).
Mask previews were visually inspected with the 72 dp visible viewport cropped
from the full 108 dp adaptive layer. These are mathematical previews, not phone
screenshots. The Play PNG carries an explicit sRGB chunk.

Pending acceptance: exact-head CI asset proof; six controlled runtime branding
cases; existing Home/live
mascot tests; strict analysis; all wire/logout fixtures; complete suite and debug
APK. Source review and a generated icon preview cannot prove launcher behavior
on every OEM or signed-release upgrade. Native visual/device checks, app store
submission and production deployment remain separate verification boundaries.

Risks to check: artwork clipping under masks; dark orbit contrast; narrow strokes
at low density; incorrect monochrome resource selection; API-31 splash resource
resolution; GIF memory/reduced-motion behavior; unnoticed old references; and
accidentally bundling large previews. The canonical asset manifest and generated
size/hash inventory record the selected sources and outputs. Do not declare this
candidate production-ready until the required gates pass.
