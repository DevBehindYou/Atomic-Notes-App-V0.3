"""Synthetic APK controls for retained assets; no Android build or device needed."""
import io
import unittest
from urllib.parse import quote
import zipfile

import verify_mascot_assets as verifier


class ApkAssetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.clips = verifier.records()
        cls.files = {verifier.APK_PREFIX + c["asset_path_from_app_root"]:
                     (verifier.ROOT / c["asset_path_from_app_root"]).read_bytes() for c in cls.clips}
        cls.files.update({verifier.APK_PREFIX + p: (verifier.ROOT / p).read_bytes()
                          for p in verifier.SPLASH_STILLS})

    def check(self, files):
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as archive:
            for name, data in files.items():
                archive.writestr(name, data)
        with zipfile.ZipFile(output) as archive:
            verifier.verify_apk(archive, self.clips)

    def test_all_retained_originals_and_static_splash_pass(self):
        self.check(self.files)

    def test_flutter_uri_encoded_asset_names_pass(self):
        self.check({quote(name, safe="/"): data for name, data in self.files.items()})

    def test_mixed_path_spellings_cannot_duplicate_a_clip(self):
        files = dict(self.files)
        name = next(iter(files))
        files[quote(name, safe="/")] = files[name]
        with self.assertRaises(ValueError):
            self.check(files)

    def test_missing_clip_fails(self):
        files = dict(self.files)
        files.pop(next(iter(files)))
        with self.assertRaises(ValueError):
            self.check(files)

    def test_changed_clip_fails(self):
        files = dict(self.files)
        name = next(iter(files))
        files[name] = bytes([files[name][0] ^ 1]) + files[name][1:]
        with self.assertRaises(ValueError):
            self.check(files)

    def test_retired_clip_fails(self):
        name = verifier.APK_PREFIX + verifier.MASCOT_PREFIX + "061 Cubie/061-cubie-1-bounce.gif"
        for spelling in (name, quote(name, safe="/")):
            files = {**self.files, spelling: b"retired"}
            with self.assertRaises(ValueError):
                self.check(files)

    def test_bundled_splash_animation_fails(self):
        files = dict(self.files)
        files[verifier.APK_PREFIX + verifier.SPLASH_ANIMATIONS[0]] = b"GIF89a"
        with self.assertRaises(ValueError):
            self.check(files)

    def test_missing_or_changed_still_fails(self):
        name = verifier.APK_PREFIX + verifier.SPLASH_STILLS[0]
        for replacement in [None, b"changed"]:
            files = dict(self.files)
            if replacement is None:
                files.pop(name)
            else:
                files[name] = replacement
            with self.assertRaises(ValueError):
                self.check(files)


if __name__ == "__main__":
    unittest.main()
