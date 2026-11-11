#!/usr/bin/env python3
"""Build seamless variants of the terrain tiles in assets/tiles_seamless/.

Why: every source tile in Tín's sheet is drawn as a rounded "cushion" —
a highlight bevel on the top/left and a dark shadow bevel along the
bottom (measured on the sliced PNGs: bottom shadow band ~10-12% of tile
height, left highlight ~5%, right ~6%, top ~5%). Placed side by side,
those rims read as a quilted grid over the whole map.

Fix: crop a uniform CROP fraction off all four sides of every tile
(interior only) and scale back up to the original size. The SAME
fraction is applied to shore tiles, so their sand/water boundary keeps
the same relative position and the shoreline is unchanged. In-game,
world.gd additionally draws full tiles with checkerboard mirror
flipping, so same-texture neighbours share identical edge columns.

Only the tiles world.gd loads are processed (GROUND_TILE_NAMES there).
Re-runnable: python3 tools/make_seamless_tiles.py
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "assets", "tiles")
OUT_DIR = os.path.join(ROOT, "assets", "tiles_seamless")
CROP = 0.12  # per side; measured rim: bottom ~0.10-0.12, others ~0.05-0.06

NAMES = [
    "grass_0", "grass_1", "grass_2", "dirt",
    "water_0", "water_1", "water_2",
    "shore_sand_n", "shore_sand_e", "shore_sand_s", "shore_sand_w",
    "shore_sand_ne", "shore_sand_nw", "shore_sand_se", "shore_sand_sw",
]

# Variant families whose members sit side by side on open ground. Their
# mean tones are matched to the family average so swapping variants
# does not draw a visible rectangle (grass_2's interior averages ~10%
# darker than grass_0's — an abrupt tone step at every variant border).
TONE_GROUPS = [
    ["grass_0", "grass_1", "grass_2"],
    ["water_0", "water_1", "water_2"],
]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    info = {"crop_per_side": CROP, "tiles": {}}
    cropped = {}
    for name in NAMES:
        src = os.path.join(SRC_DIR, name + ".png")
        im = Image.open(src).convert("RGB")
        w, h = im.size
        cx = int(round(w * CROP))
        cy = int(round(h * CROP))
        inner = im.crop((cx, cy, w - cx, h - cy))
        cropped[name] = (inner, (w, h), (cx, cy))
        info["tiles"][name] = {"size": [w, h], "crop_px": [cx, cy]}
        print(f"{name}: {w}x{h} crop {cx}px/{cy}px per side")

    # Scalar (luminance) gains only — per-channel gains would wreck the
    # hues (the variants' blue-channel means differ several-fold).
    gains = {}
    for group in TONE_GROUPS:
        lums = {n: float(np.asarray(cropped[n][0]).astype(float).mean())
                for n in group}
        target = sum(lums.values()) / len(lums)
        for n in group:
            gains[n] = target / lums[n]
            print(f"tone-match {n}: lum {lums[n]:.1f} -> {target:.1f}, "
                  f"gain {gains[n]:.3f}")

    for name in NAMES:
        inner, (w, h), _ = cropped[name]
        if name in gains:
            arr = np.asarray(inner).astype(float) * gains[name]
            inner = Image.fromarray(np.clip(arr, 0, 255).astype("uint8"))
        out = inner.resize((w, h), Image.BILINEAR)
        out.save(os.path.join(OUT_DIR, name + ".png"))
    with open(os.path.join(OUT_DIR, "seamless.json"), "w") as f:
        json.dump(info, f, indent=1, sort_keys=True)
    print(f"saved {len(NAMES)} seamless tiles to {OUT_DIR}")


if __name__ == "__main__":
    main()
