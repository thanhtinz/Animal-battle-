#!/usr/bin/env python3
"""Derive the Desert and Snow seamless tile sets from the Grassland set.

The Grassland seamless tiles (assets/tiles_seamless/, see
make_seamless_tiles.py) are colour-graded POINTWISE — every pixel's
new colour is a pure function of its old colour. A pointwise grade
commutes with the checkerboard mirror flipping world.gd draws with,
and the 12% rim crop is untouched, so both derived sets stay exactly
as seamless as the original. Same filenames in each output dir, so
world.gd's tile-key logic is biome-agnostic.

  Desert: grass hue-rotated from yellow-green (~80 deg) to sand
          (~44 deg); dirt warmed; oasis water nudged teal; the shore
          tiles are already sand+water, only lifted slightly.
  Snow:   grass remapped up a luminance ramp to blue-white snow;
          dirt to grey-blue slush; water flattened up an ice ramp;
          shore split per-pixel (warm sand -> snow, blue -> ice).

Re-runnable: python3 tools/make_biome_tiles.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "assets", "tiles_seamless")
DESERT_DIR = os.path.join(ROOT, "assets", "tiles_desert")
SNOW_DIR = os.path.join(ROOT, "assets", "tiles_snow")

NAMES = [
    "grass_0", "grass_1", "grass_2", "dirt",
    "water_0", "water_1", "water_2",
    "shore_sand_n", "shore_sand_e", "shore_sand_s", "shore_sand_w",
    "shore_sand_ne", "shore_sand_nw", "shore_sand_se", "shore_sand_sw",
]


def to_hsv(arr):
    """arr: float RGB in [0,1] (...,3) -> (h, s, v) each in [0,1]."""
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    mx = arr.max(axis=-1)
    mn = arr.min(axis=-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-9
    idx = nz & (mx == r)
    h[idx] = ((g - b)[idx] / d[idx]) % 6.0
    idx = nz & (mx == g)
    h[idx] = (b - r)[idx] / d[idx] + 2.0
    idx = nz & (mx == b)
    h[idx] = (r - g)[idx] / d[idx] + 4.0
    h = h / 6.0
    s = np.where(mx > 1e-9, d / np.maximum(mx, 1e-9), 0.0)
    return h, s, mx


def from_hsv(h, s, v):
    h6 = (h % 1.0) * 6.0
    i = np.floor(h6).astype(int) % 6
    f = h6 - np.floor(h6)
    p = v * (1.0 - s)
    q = v * (1.0 - s * f)
    t = v * (1.0 - s * (1.0 - f))
    out = np.zeros(h.shape + (3,), dtype=float)
    conds = [
        (v, t, p), (q, v, p), (p, v, t),
        (p, q, v), (t, p, v), (v, p, q),
    ]
    for k, (rr, gg, bb) in enumerate(conds):
        m = i == k
        out[..., 0] = np.where(m, rr, out[..., 0])
        out[..., 1] = np.where(m, gg, out[..., 1])
        out[..., 2] = np.where(m, bb, out[..., 2])
    return out


def lum(arr):
    return 0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]


def ramp(arr, dark, light, lo=0.2, hi=0.8):
    """Map luminance up a two-colour ramp, keep a whisper of the source."""
    l = lum(arr)
    t = np.clip((l - lo) / (hi - lo), 0.0, 1.0)[..., None]
    dark = np.array(dark, dtype=float)
    light = np.array(light, dtype=float)
    graded = dark + (light - dark) * t
    return graded * 0.92 + arr * 0.08


def grade_desert(name, arr):
    h, s, v = to_hsv(arr)
    if name.startswith("grass"):
        h = h - 33.0 / 360.0  # yellow-green -> sand gold
        s = s * 0.68  # sand is pale: high saturation reads as autumn soil
        v = np.clip(v * 1.14, 0.0, 1.0)
        return from_hsv(h, s, v)
    if name == "dirt":
        h = h - 6.0 / 360.0
        s = s * 0.85
        v = np.clip(v * 1.02, 0.0, 1.0)
        return from_hsv(h, s, v)
    if name.startswith("water"):
        h = h + 5.0 / 360.0  # oasis teal nudge
        s = s * 1.05
        return from_hsv(h, np.clip(s, 0, 1), v)
    # shore: already a sand beach — just lift.
    return np.clip(arr * 1.03, 0.0, 1.0)


def grade_snow(name, arr):
    if name.startswith("grass"):
        return ramp(arr, (0.60, 0.70, 0.88), (0.97, 0.985, 1.0), 0.25, 0.75)
    if name == "dirt":
        slush = np.array([0.55, 0.62, 0.75])
        return arr * 0.35 + slush * 0.65 * (0.6 + 0.4 * lum(arr)[..., None])
    if name.startswith("water"):
        return ice_ramp(arr)
    # shore: warm pixels (sand) -> snow ramp, blue pixels -> ice.
    is_water = (arr[..., 2] > arr[..., 0] + 0.05)[..., None]
    snow_part = ramp(arr, (0.60, 0.70, 0.88), (0.97, 0.985, 1.0), 0.25, 0.8)
    return np.where(is_water, ice_ramp(arr), snow_part)


def ice_ramp(arr):
    """Pale ice: source water is dark (lum ~0.35), so the ramp sits
    high — deep cracks stay visible as blue-grey seams."""
    l = lum(arr)
    flat = np.clip(0.74 + (l - 0.35) * 0.38, 0.0, 1.0)
    ice = np.stack([flat * 0.86, flat * 0.94, np.clip(flat * 1.05, 0, 1)], axis=-1)
    return ice * 0.92 + arr * 0.08


def main():
    for out_dir, grader in [(DESERT_DIR, grade_desert), (SNOW_DIR, grade_snow)]:
        os.makedirs(out_dir, exist_ok=True)
        for name in NAMES:
            src = os.path.join(SRC_DIR, name + ".png")
            im = Image.open(src).convert("RGB")
            arr = np.asarray(im).astype(float) / 255.0
            out = grader(name, arr)
            Image.fromarray((np.clip(out, 0, 1) * 255).astype("uint8")).save(
                os.path.join(out_dir, name + ".png"))
        print(f"saved {len(NAMES)} tiles to {out_dir}")


if __name__ == "__main__":
    main()
