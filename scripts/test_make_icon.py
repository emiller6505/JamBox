#!/usr/bin/env python3
"""
Tests for make_icon.py.

Creates a synthetic 2000x2000 image with a colored circle in the middle
surrounded by white padding, runs make_icon.py on it, and checks:
  - all 7 unique pixel sizes are written
  - each output PNG has the expected dimensions
  - Contents.json has 10 entries with valid filenames
  - corners are transparent (rounded mask applied)
  - white border is gone (cropped)

Run:  python3 scripts/test_make_icon.py
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parent.parent
APPICON_DIR = REPO_ROOT / "JamBox" / "Media.xcassets" / "AppIcon.appiconset"
SCRIPT = REPO_ROOT / "scripts" / "make_icon.py"

EXPECTED_SIZES = [16, 32, 64, 128, 256, 512, 1024]


def make_fixture(path: Path) -> None:
    """A 2000x2000 white image with a magenta circle inset by 200px."""
    img = Image.new("RGBA", (2000, 2000), (255, 255, 255, 255))
    draw = ImageDraw.Draw(img)
    draw.ellipse((200, 200, 1799, 1799), fill=(255, 0, 200, 255))
    img.save(path)


def backup_existing() -> Path:
    """Snapshot the current AppIcon dir so the test doesn't clobber real assets."""
    backup = Path(tempfile.mkdtemp(prefix="appicon_backup_"))
    if APPICON_DIR.exists():
        shutil.copytree(APPICON_DIR, backup / "AppIcon.appiconset")
    return backup


def restore_backup(backup: Path) -> None:
    if APPICON_DIR.exists():
        shutil.rmtree(APPICON_DIR)
    src = backup / "AppIcon.appiconset"
    if src.exists():
        shutil.copytree(src, APPICON_DIR)
    shutil.rmtree(backup)


def run_check(name: str, cond: bool, detail: str = "") -> bool:
    mark = "PASS" if cond else "FAIL"
    print(f"  [{mark}] {name}" + (f"  ({detail})" if detail else ""))
    return cond


def run_tests() -> int:
    backup = backup_existing()
    failures = 0
    try:
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / "fixture.png"
            make_fixture(fixture)

            print(f"running {SCRIPT.name} on synthetic fixture...")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(fixture)],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                print("  script failed:")
                print(result.stdout)
                print(result.stderr)
                return 1

            print("checking output:")

            # 1. All 7 PNG files exist with correct dimensions.
            for px in EXPECTED_SIZES:
                f = APPICON_DIR / f"icon_{px}x{px}.png"
                if not run_check(f"icon_{px}x{px}.png exists", f.exists()):
                    failures += 1
                    continue
                w, h = Image.open(f).size
                if not run_check(
                    f"icon_{px}x{px}.png is {px}x{px}",
                    (w, h) == (px, px),
                    f"got {w}x{h}",
                ):
                    failures += 1

            # 2. Contents.json valid and has 10 entries.
            cj = APPICON_DIR / "Contents.json"
            if not run_check("Contents.json exists", cj.exists()):
                failures += 1
            else:
                data = json.loads(cj.read_text())
                if not run_check(
                    "Contents.json has 10 image entries",
                    len(data["images"]) == 10,
                    f"got {len(data['images'])}",
                ):
                    failures += 1
                # Every referenced filename must exist on disk.
                for entry in data["images"]:
                    fname = entry.get("filename")
                    if fname and not (APPICON_DIR / fname).exists():
                        run_check(f"referenced {fname} exists", False)
                        failures += 1

            # 3. Corners are transparent on the 1024 image (rounded mask).
            big = Image.open(APPICON_DIR / "icon_1024x1024.png").convert("RGBA")
            corner_alpha = big.getpixel((2, 2))[3]
            center_alpha = big.getpixel((512, 512))[3]
            if not run_check(
                "top-left corner is transparent",
                corner_alpha == 0,
                f"alpha={corner_alpha}",
            ):
                failures += 1
            if not run_check(
                "center is opaque",
                center_alpha == 255,
                f"alpha={center_alpha}",
            ):
                failures += 1

            # 4. White border was cropped: the magenta should reach near the edges
            #    on the 1024 image (within ~50px of the rounded edge midpoint).
            mid_left = big.getpixel((10, 512))  # may be transparent (rounded)
            mid_left_inset = big.getpixel((60, 512))  # should be magenta-ish
            r, g, b, a = mid_left_inset
            if not run_check(
                "white border was cropped (magenta near edge)",
                a == 255 and r > 200 and b > 100,
                f"rgba={mid_left_inset}",
            ):
                failures += 1

    finally:
        restore_backup(backup)
        print("(restored original AppIcon assets)")

    if failures:
        print(f"\n{failures} check(s) failed")
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(run_tests())
