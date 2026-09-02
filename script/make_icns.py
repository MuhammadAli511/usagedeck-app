#!/usr/bin/env python3
"""Regenerate assets/AppIcon.prebuilt/AppIcon.icns from the UsageDeck mark.

Why this exists: assets/AppIcon.icon is an Icon Composer source, and actool crashes compiling it on
every Xcode from 26.4 onward (Apple regression FB20183399), including GitHub's macOS runners. That
leaves the release build with no icon at all. This script draws the same mark directly and produces
a classic .icns, which needs only iconutil and so works everywhere.

Requires Pillow. Run it after changing the mark, then commit the regenerated .icns:

    python3 script/make_icns.py
"""
import pathlib
import shutil
import subprocess
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow is required: pip install Pillow")

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "AppIcon.prebuilt"

GRAPHITE = (41, 43, 48, 255)
MARK = (255, 255, 255, 255)

# The mark in its 24x24 SVG coordinate space: three rounded bars, decreasing width.
BARS = [(4, 4, 20, 7), (4, 10, 15, 13), (4, 16, 10, 19)]
BAR_RADIUS = 1.5
GLYPH_BOX = (4, 4, 20, 19)


def render(size: int) -> Image.Image:
    # Draw at 4x and downsample, so the rounded corners stay clean at small sizes.
    ss = size * 4
    img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # macOS icon grid: the rounded square occupies 824/1024 of the canvas.
    plate = ss * 824 / 1024
    inset = (ss - plate) / 2
    draw.rounded_rectangle(
        [inset, inset, inset + plate, inset + plate],
        radius=plate * 185.4 / 824,
        fill=GRAPHITE,
    )

    gx0, gy0, gx1, gy1 = GLYPH_BOX
    scale = (plate * 0.56) / (gx1 - gx0)
    off_x = (ss - (gx1 - gx0) * scale) / 2
    off_y = (ss - (gy1 - gy0) * scale) / 2
    for x0, y0, x1, y1 in BARS:
        draw.rounded_rectangle(
            [
                off_x + (x0 - gx0) * scale,
                off_y + (y0 - gy0) * scale,
                off_x + (x1 - gx0) * scale,
                off_y + (y1 - gy0) * scale,
            ],
            radius=BAR_RADIUS * scale,
            fill=MARK,
        )
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    iconset = OUT_DIR / "AppIcon.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True, exist_ok=True)

    for base in (16, 32, 128, 256, 512):
        render(base).save(iconset / f"icon_{base}x{base}.png")
        render(base * 2).save(iconset / f"icon_{base}x{base}@2x.png")

    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(OUT_DIR / "AppIcon.icns")],
        check=True,
    )
    shutil.rmtree(iconset)
    print(f"Wrote {OUT_DIR / 'AppIcon.icns'}")


if __name__ == "__main__":
    main()
