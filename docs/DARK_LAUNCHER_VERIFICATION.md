# Dark launcher icon

The Android launcher was difficult to see at small sizes. It now uses the
existing dark Atomic Notes companion on Ink (#15171B), with orbit width increased
from 11 to 15 source units. All other geometry, colors and adaptive safe-area
scaling are preserved. The monochrome themed launcher receives the same weight.
Legacy densities, adaptive native/raster layers, Play artwork and optional
Flutter launcher configuration agree on the dark variant.

The supplied master and companion assets, Flutter logos, mascots, notification
icon and native splash are unchanged. iOS is explicitly disabled in launcher
configuration and has no verified release pipeline, so its scaffold is outside
this change. No app identity or signing setting changes.

Validation commands:

```text
python tool/generate_android_branding.py
python tool/generate_android_branding.py --verify-only
python tool/verify_branding_assets.py
python tool/test_verify_branding_assets.py
```

The independent verifier pins the dark background in actual PNGs, native color
resources and optional generator configuration, and the three original dark
orbit colors plus the 15-unit weight in native vectors. Its failure controls
reject the old light background and thin orbit width. Existing safe-area,
opacity, source hash, library hash and resource checks remain active.

Inspect `assets/new-atomic-icons/previews/android-masks-safe-zones.png` for circle,
rounded and themed masks, safe-zone bounds, previous-light comparison and actual
48/32 px icons. This is a generated preview, not a device screenshot. Android
resource compilation and the full CI suite remain required before merge; actual
OEM launcher appearance remains a physical-device acceptance boundary.
