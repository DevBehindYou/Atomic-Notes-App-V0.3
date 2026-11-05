"""Verify the retained original artwork in source and optionally a built APK."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import unquote
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RETAINED = frozenset(("022-antimatter", "040-vaulty", "047-rocco", "052-tilde",
                      "066-hoot", "073-lappy", "076-pocket"))
MASCOT_PREFIX = "assets/Atomic Notes Mascot/"
SPLASH_STILLS = (
    "assets/atomic-splash/atomic-spin-on-light-static.png",
    "assets/atomic-splash/atomic-spin-on-dark-static.png",
)
SPLASH_ANIMATIONS = (
    "assets/new-atomic-icons/gif/atomic-spin-on-light.gif",
    "assets/new-atomic-icons/gif/atomic-spin-on-dark.gif",
)
APK_PREFIX = "assets/flutter_assets/"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def records(root: Path = ROOT) -> list[dict]:
    audit = json.loads((root / "docs/mascot/catalog-v1.json").read_text())
    clips = [c for c in audit["clips"] if c["mascot_id"] in RETAINED]
    require(len(clips) == 28 and {c["mascot_id"] for c in clips} == RETAINED,
            "Expected exactly seven retained mascots with four clips each")
    for mascot in RETAINED:
        require(sorted(c["slot"] for c in clips if c["mascot_id"] == mascot) == [1, 2, 3, 4],
                "Expected all four original slots")
    return clips


def verify_bytes(data: bytes, clip: dict) -> None:
    require(len(data) == clip["bytes"] and hashlib.sha256(data).hexdigest() == clip["sha256"],
            "Original mascot bytes changed")


def verify_source(root: Path = ROOT) -> list[dict]:
    clips = records(root)
    expected = {c["asset_path_from_app_root"] for c in clips}
    actual = {p.relative_to(root).as_posix() for p in (root / MASCOT_PREFIX).rglob("*") if p.is_file()}
    require(actual == expected, "Source mascot files differ from retained catalog")
    declarations = {line.strip()[2:] for line in (root / "pubspec.yaml").read_text().splitlines()
                    if line.strip().startswith("- assets/")}
    require({p for p in declarations if p.startswith(MASCOT_PREFIX)} ==
            {p.rsplit("/", 1)[0] + "/" for p in expected}, "Mascot bundle declarations differ")
    require(set(SPLASH_STILLS) <= declarations, "Static splash artwork not bundled")
    require(all((root / still).is_file() for still in SPLASH_STILLS),
            "Static splash artwork missing from source")
    require(not any(p in declarations or p.rsplit("/", 1)[0] + "/" in declarations
                    for p in SPLASH_ANIMATIONS), "Unused splash animations still bundled")
    for clip in clips:
        verify_bytes((root / clip["asset_path_from_app_root"]).read_bytes(), clip)
    return clips


def verify_apk(archive: zipfile.ZipFile, clips: list[dict], root: Path = ROOT) -> None:
    expected = {APK_PREFIX + c["asset_path_from_app_root"] for c in clips}
    # Flutter URI-encodes APK asset paths, including spaces in mascot names.
    entries: dict[str, list[zipfile.ZipInfo]] = {}
    for entry in archive.infolist():
        if not entry.is_dir():
            entries.setdefault(unquote(entry.filename), []).append(entry)
    mascot_entries = {name for name in entries if name.startswith(APK_PREFIX + MASCOT_PREFIX)}
    require(mascot_entries == expected and all(len(entries[name]) == 1 for name in expected),
            "APK must contain exactly the 28 retained GIFs, with no duplicates or retired assets")
    for clip in clips:
        name = APK_PREFIX + clip["asset_path_from_app_root"]
        entry = entries[name][0]
        require(entry.file_size == clip["bytes"], "APK mascot size changed")
        verify_bytes(archive.read(entry), clip)
    for still in SPLASH_STILLS:
        name = APK_PREFIX + still
        matches = entries.get(name, [])
        require(len(matches) == 1 and archive.read(matches[0]) == (root / still).read_bytes(),
                "APK static splash missing or changed")
    require(not any(name.startswith(APK_PREFIX + "assets/new-atomic-icons/gif/") for name in entries),
            "APK contains unused splash animations")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path)
    args = parser.parse_args()
    clips = verify_source()
    if args.apk:
        with zipfile.ZipFile(args.apk) as archive:
            verify_apk(archive, clips)
    print(json.dumps({"mascots": 7, "clips": len(clips),
                      "originalBytes": sum(c["bytes"] for c in clips),
                      "staticSplashAssets": len(SPLASH_STILLS), "apkVerified": bool(args.apk)}))


if __name__ == "__main__":
    main()
