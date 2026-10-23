# Atomic Notes Android branding library

The unchanged `assets/atomic-icon.jpg` is the supplied master artwork. It is a
1080 × 1080 opaque JPEG, not a transparent logo. Transparent PNGs, clean SVGs and
Android vectors reuse the supplied editable companion geometry. That companion
is a symmetric reconstruction of the same visual identity, **not a pixel-identical
extraction of the JPEG**. The on-dark version substitutes Paper for Ink where
needed for contrast. Original user assets remain untouched in the source folder.

`manifest.json` records source hashes, derivative hashes, sizes, alpha ranges and
specifications. Metadata embedded in the original supplied SVGs is omitted from
clean derivatives; it is not represented as a signature of generated output.

| Folder | Use |
| --- | --- |
| `png/` | Supplied transparent logos and exact decoded first-frame mascot fallbacks; selected Flutter runtime assets |
| `svg/` | Clean editable visual primitives; no embedded provenance payload |
| `android/` | Adaptive raster fallbacks, opaque RGBA 512 px Play icon, 1024 px raster generator source |
| `android/legacy/` | 48/72/96/144/192 px square launcher icons |
| `android/native/` | Exact copies of generated Android resources committed under `android/app/src/main/res` |
| `android/notification/` | Prepared 24/36/48/72/96 px white-alpha small-icon variants |
| `splash/` | Transparent light/dark raster splash logos |
| `gif/` | Unchanged supplied transparent 4-second Atomic GIFs, bundled for the Flutter splash; native Android splash stays static |
| `previews/` | Light/dark, circular/rounded/themed and safe-zone inspection sheet; not bundled |

Android is the configured app release platform. iOS, macOS, Windows, Linux and
web folders currently provide scaffolds without equivalent release verification;
this library does not claim those platforms are supported or package their icons.

The adaptive foreground and distinct monochrome vector use a 108 dp canvas with
all important artwork inside the central 66 dp circle. The monochrome drawable
has one white color and a transparent even-odd nucleus hole; it never reuses the
colored foreground. Legacy icons and the opaque 32-bit Play PNG have no manually
rounded outer corners. The Play PNG is below 1 MiB.

The launcher and Play artwork use a white background (`#FFFFFF`) and dark-purple
atomic lines, electrons and nucleus (`#4B238C`). Launcher orbit strokes are 24
source units instead of the supplied 11 for small-size legibility. The complete
launcher artwork, including its strokes, is scaled to **two-thirds of its previous
size** within the same tile. Adaptive artwork radius is now 22 dp (previously
33 dp); legacy, Play and 1024 px source artwork radius is 28% of canvas width
(previously 42%). Ellipse geometry, electrons and nucleus keep their proportions.
Both colored and themed launcher
orbits use that weight. The supplied SVG/PNG companions, in-app logos and native
splash retain their original strokes. `manifest.json` records this launcher-only
derivation. The mask preview includes actual 48 px and 32 px circular icons.

Android 12+ uses a **static VectorDrawable** on a 288 dp canvas with artwork inside
the central 192 dp circle. Earlier Android versions show the same light/dark
vector and background through the existing launch theme. There is no GIF in a
native splash resource, additional animation wait, new dependency or keep-on-screen
handler. The Atomic icon GIF appears on the existing Flutter splash without
delaying routing. Reduced motion, hidden routes and background lifecycle use
exact first-frame PNGs. Animated mascots belong to the post-launch Flutter UI.
The notification resource is prepared for future use; the app currently has no
native notification channel, and this migration does not add one.

Regenerate with an existing Python/Pillow environment:

```text
python tool/generate_android_branding.py
python tool/generate_android_branding.py --verify-only
```

CI verifies the committed assets without Pillow or package installation:

```text
python tool/verify_branding_assets.py --proof ci-branding-assets-proof.json
python tool/test_verify_branding_assets.py
```

The standard-library verifier emits only fixed outcome codes, parses bounded PNG
chunks with CRC and decompression limits, and checks actual RGBA alpha coverage,
native references and library hashes. Its nineteen controls include the valid
library and deliberate in-memory corruption of safe zones, monochrome colors,
store opacity, dimensions, CRC, source hashes and native aliases; oversized
decodes, path escapes and private exception text are also rejected. No source
asset is mutated by those controls. Exact decoded GIF first-frame identity is
verified by the local generation tool; CI checks the committed hashes, dimensions
and alpha of those PNG fallbacks. Three controls reject a dark launcher
background, incorrect purple, or thinner launcher orbit weight.
The artwork-size check measures raster coverage independently of hashes and
manifest metadata. Four controls reject the previous full-size adaptive vector,
adaptive raster, legacy raster and Play icon; a positive control checks the new
22 dp radius. Android still controls the launcher's outer tile size.

The one-time `--import-source <existing-assets-directory>` option validates the
three named JPEG/GIF hashes and imports the supplied vector/PNG/GIF companions.
It copies no unrelated files. No install or download is required. Re-running the
existing optional `flutter_launcher_icons` generator can provide raster adaptive
resources, but run the Python generator afterward to restore the authoritative
native vectors and verify the committed library.

The deterministic verifier checks XML parsing, source hashes, output hashes,
adaptive alpha coverage, a single-color monochrome raster, the Play dimensions /
RGBA / opacity / size, and native-library equality. The preview is a mathematical
mask inspection of the central 72 dp visible viewport of the full 108 dp adaptive
layer, not a physical-device screenshot. Its separate safe-zone row shows the full
layer. Android resource compilation,
actual system launcher/themed/splash appearance and signed upgrade testing require
their respective CI/device/release gates; generation alone does not prove them.

Specifications: [Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive),
[Android native splash](https://developer.android.com/develop/ui/views/launch/splash-screen),
[Google Play icon design](https://developer.android.com/distribute/google-play/resources/icon-design-specifications).
