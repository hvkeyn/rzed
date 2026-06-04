#!/usr/bin/env python3
"""Generate RZed PNG/ICO assets from a source image."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "crates" / "zed" / "resources"
WINDOWS = RESOURCES / "windows"

PNG_BASES = [
    "app-icon",
    "app-icon-dev",
    "app-icon-nightly",
    "app-icon-preview",
]

ICO_FILES = [
    "app-icon.ico",
    "app-icon-dev.ico",
    "app-icon-nightly.ico",
    "app-icon-preview.ico",
]


def write_png_pair(stem: str, image: Image.Image) -> None:
    image_512 = image.resize((512, 512), Image.Resampling.LANCZOS)
    image_1024 = image.resize((1024, 1024), Image.Resampling.LANCZOS)
    image_512.save(RESOURCES / f"{stem}.png", format="PNG", optimize=True)
    image_1024.save(RESOURCES / f"{stem}@2x.png", format="PNG", optimize=True)


def write_ico(path: Path, image: Image.Image) -> None:
    sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    images = [image.resize(size, Image.Resampling.LANCZOS) for size in sizes]
    images[0].save(
        path,
        format="ICO",
        sizes=[(img.width, img.height) for img in images],
        append_images=images[1:],
    )


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: update_rzed_icons.py <source.png>", file=sys.stderr)
        return 1

    source = Path(sys.argv[1]).resolve()
    if not source.is_file():
        print(f"missing source: {source}", file=sys.stderr)
        return 1

    image = Image.open(source).convert("RGBA")

    for stem in PNG_BASES:
        write_png_pair(stem, image)
        print(f"wrote {stem}.png and {stem}@2x.png")

    for ico_name in ICO_FILES:
        out = WINDOWS / ico_name
        write_ico(out, image)
        print(f"wrote {out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
