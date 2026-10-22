"""Export exact GIF first frames; verify supplied art with existing Pillow only."""
import argparse
import hashlib
from pathlib import Path

from PIL import Image
from generate_android_branding import save_png

ROOT = Path(__file__).resolve().parents[1]
HASHES = {
    "on-light": "f69699310495b8e5cba138ea57b978f927f60b464deb5ab4f99e51bb1d475b28",
    "on-dark": "37be0cbe56f1d787a4c72ee8fbe9c203116a76be70a10b051569f1b732f91cfe",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    for variant, expected in HASHES.items():
        source = ROOT / f"assets/new-atomic-icons/gif/atomic-spin-{variant}.gif"
        target = ROOT / f"assets/atomic-splash/atomic-spin-{variant}-static.png"
        assert hashlib.sha256(source.read_bytes()).hexdigest() == expected
        with Image.open(source) as animation:
            assert animation.size == (480, 480) and animation.n_frames == 100
            first = animation.convert("RGBA")
            if not args.verify_only:
                save_png(target, first)
            with Image.open(target) as still:
                assert still.mode == "RGBA" and still.size == first.size
                assert still.tobytes() == first.tobytes()
    print('{"outcome":"pass","scope":"unchanged supplied GIFs and exact first-frame PNGs"}')


if __name__ == "__main__":
    main()
