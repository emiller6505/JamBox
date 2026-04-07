#!/usr/bin/env python3
"""
Turn any square-ish image into the macOS AppIcon set for JamBox.

Usage:  python3 scripts/make_icon.py path/to/image.png

Steps:
  1. Crop white border (auto-detect non-white bbox).
  2. Round the corners (~22% radius, matching macOS).
  3. Resize to all 10 macOS icon slots.
  4. Write Contents.json.

Requires Pillow:  pip3 install --user Pillow
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = Path(__file__).resolve().parent.parent
APPICON_DIR = REPO_ROOT / "JamBox" / "Media.xcassets" / "AppIcon.appiconset"

# (slot_size, scale) -> pixel size
SLOTS = [
    ("16x16", "1x", 16),
    ("16x16", "2x", 32),
    ("32x32", "1x", 32),
    ("32x32", "2x", 64),
    ("128x128", "1x", 128),
    ("128x128", "2x", 256),
    ("256x256", "1x", 256),
    ("256x256", "2x", 512),
    ("512x512", "1x", 512),
    ("512x512", "2x", 1024),
]

WHITE_THRESHOLD = 240  # R,G,B all >= this -> treat as white
CORNER_RADIUS_RATIO = 0.2237  # macOS squircle approximation


def crop_white_border(img: Image.Image) -> Image.Image:
    """Crop to the bounding box of non-white pixels, kept square."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    left, top, right, bottom = w, h, 0, 0
    found = False
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0 and not (r >= WHITE_THRESHOLD and g >= WHITE_THRESHOLD and b >= WHITE_THRESHOLD):
                found = True
                if x < left: left = x
                if x > right: right = x
                if y < top: top = y
                if y > bottom: bottom = y
    if not found:
        return img  # nothing to crop
    side = max(right - left + 1, bottom - top + 1)
    cx = (left + right) // 2
    cy = (top + bottom) // 2
    half = side // 2
    box = (max(0, cx - half), max(0, cy - half), min(w, cx + half), min(h, cy + half))
    return img.crop(box)


def sharpen(img: Image.Image) -> Image.Image:
    """Apply a mild unsharp mask. Helps when the source has been upscaled
    or has soft anti-aliased edges."""
    return img.filter(ImageFilter.UnsharpMask(radius=2, percent=120, threshold=3))


def round_corners(img: Image.Image, size: int = 1024) -> Image.Image:
    """Resize to size x size and apply a rounded-square alpha mask."""
    img = img.resize((size, size), Image.LANCZOS)
    img = sharpen(img)
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    radius = int(size * CORNER_RADIUS_RATIO)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def write_contents_json(dest: Path) -> None:
    images = [
        {
            "filename": f"icon_{px}x{px}.png",
            "idiom": "mac",
            "scale": scale,
            "size": slot,
        }
        for slot, scale, px in SLOTS
    ]
    data = {"images": images, "info": {"author": "xcode", "version": 1}}
    (dest / "Contents.json").write_text(json.dumps(data, indent=2) + "\n")


def clean_dir(dest: Path) -> None:
    """Remove old PNGs so renames don't leave orphans."""
    for f in dest.glob("*.png"):
        f.unlink()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    src_path = Path(sys.argv[1]).expanduser().resolve()
    if not src_path.exists():
        print(f"error: {src_path} not found")
        return 1

    print(f"reading  {src_path}")
    src = Image.open(src_path)
    print(f"  source size: {src.size}")

    cropped = crop_white_border(src)
    print(f"  cropped to:  {cropped.size}")

    clean = round_corners(cropped, size=1024)

    APPICON_DIR.mkdir(parents=True, exist_ok=True)
    clean_dir(APPICON_DIR)

    unique_pixels = sorted({px for _, _, px in SLOTS})
    for px in unique_pixels:
        out = clean.resize((px, px), Image.LANCZOS)
        out.save(APPICON_DIR / f"icon_{px}x{px}.png")
        print(f"  wrote icon_{px}x{px}.png")

    write_contents_json(APPICON_DIR)
    print(f"  wrote Contents.json")
    print("done. rebuild the app to see the new icon.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
