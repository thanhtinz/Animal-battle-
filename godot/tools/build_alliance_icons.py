#!/usr/bin/env python3
"""Empire Age 17e addendum — copy the owner's alliance badge
icons into the game assets.

Source (owner sheet, already sliced + verified):
  art_candidates/alliance_icons/icon_01_su_tu.png ... icon_10_*
  (white-silhouette RGBA 256x256, tintable via modulate)
Target:
  assets/alliance_icons/icon_01.png ... icon_10.png

The badge model is icon (1..10) + a colour index into the
game's 8 slot colours (server alliance.go validates; the
client tints the white silhouette with the slot colour).

Usage: python3 tools/build_alliance_icons.py
"""
import glob
import os
import shutil

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.normpath(os.path.join(ROOT, "..", "art_candidates", "alliance_icons"))
OUT = os.path.join(ROOT, "assets", "alliance_icons")


def main():
    os.makedirs(OUT, exist_ok=True)
    files = sorted(glob.glob(os.path.join(SRC, "icon_*.png")))
    files = [f for f in files if os.path.basename(f)[5:7].isdigit()]
    assert len(files) == 10, f"expected 10 icons, found {len(files)}"
    for i, src in enumerate(files, start=1):
        img = Image.open(src)
        assert img.size == (256, 256) and img.mode == "RGBA", (src, img.size, img.mode)
        dst = os.path.join(OUT, f"icon_{i:02d}.png")
        shutil.copyfile(src, dst)
        print(f"icon_{i:02d}.png <- {os.path.basename(src)}")
    print("done:", OUT)


if __name__ == "__main__":
    main()
