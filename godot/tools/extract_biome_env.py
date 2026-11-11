#!/usr/bin/env python3
"""Extract biome environment sprites from the CraftPix packs Tín
already provided (STEP-0 inventory result: the packs already contain
palms, snow trees, snow bushes and cacti — nothing had to be drawn).

  Desert wood  = Palm trees (trees pack)          -> env/tree_desert_*
  Desert food  = Cactus2, the prickly-pear bush   -> env/bush_desert_*
  Desert decor = Cactus1                          -> env/cactus_*
  Snow wood    = Snow trees + snow pines          -> env/tree_snow_*
  Snow food    = Snow bushes                      -> env/bush_snow_*

Only the rock families had no biome variants in the packs, so those
are colour grades of the existing game rocks (same pointwise trick
as the tiles: warm sandstone for desert, pale blue-white for snow),
plus matching grades of the flat rock and the ruins for snow decor.

Sprites are normalised to the sizes ResourceNode/Decor already draw
(trees 128, bushes/rocks 64) with NEAREST resampling (pixel art).

Re-runnable: python3 tools/extract_biome_env.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "..", "assets-src", "craftpix")
ENV = os.path.join(ROOT, "assets", "env")
TREES = os.path.join(SRC, "trees", "PNG", "Assets_separately", "Trees")
BUSHES = os.path.join(SRC, "bushes", "PNG", "Assets")

COPIES = [
    # (source, dest, size)
    ("Palm_tree1_1.png", "tree_desert_0.png", 128),
    ("Palm_tree1_2.png", "tree_desert_1.png", 128),
    ("Palm_tree1_3.png", "tree_desert_2.png", 128),
    ("Palm_tree2_1.png", "tree_desert_3.png", 128),
    ("Palm_tree2_2.png", "tree_desert_4.png", 128),
    ("Snow_tree1.png", "tree_snow_0.png", 128),
    ("Snow_tree2.png", "tree_snow_1.png", 128),
    ("Snow_tree3.png", "tree_snow_2.png", 128),
    ("Snow_christmass_tree1.png", "tree_snow_3.png", 128),
    ("Snow_christmass_tree2.png", "tree_snow_4.png", 128),
]
BUSH_COPIES = [
    ("Cactus2_1.png", "bush_desert_0.png", 64),
    ("Cactus2_2.png", "bush_desert_1.png", 64),
    ("Cactus2_3.png", "bush_desert_2.png", 64),
    ("Snow_bush1.png", "bush_snow_0.png", 64),
    ("Snow_bush2.png", "bush_snow_1.png", 64),
    ("Snow_bush3.png", "bush_snow_2.png", 64),
    ("Cactus1_1.png", "cactus_0.png", 64),
    ("Cactus1_2.png", "cactus_1.png", 64),
    ("Cactus1_3.png", "cactus_2.png", 64),
]


def save_norm(im, dest, size):
    if im.size != (size, size):
        im = im.resize((size, size), Image.NEAREST)
    im.save(os.path.join(ENV, dest))
    print("copy", dest, im.size)


def warm_grade(arr):
    """Grey rock -> warm sandstone (channel gains + a tan floor)."""
    out = arr.copy()
    out[..., 0] = np.clip(out[..., 0] * 1.14 + 0.03, 0, 1)
    out[..., 1] = np.clip(out[..., 1] * 1.0 + 0.01, 0, 1)
    out[..., 2] = np.clip(out[..., 2] * 0.74, 0, 1)
    return out


def snow_grade(arr, strength=0.5):
    """Mix toward pale blue-white, weighted by luminance (tops whiten)."""
    l = (0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2])[..., None]
    target = np.array([0.88, 0.92, 1.0])
    w = strength * (0.45 + 0.55 * l)
    rgb = arr[..., :3] * (1 - w) + target * w
    out = arr.copy()
    out[..., :3] = np.clip(rgb, 0, 1)
    return out


def grade_file(src_name, dest, fn, strength=None):
    im = Image.open(os.path.join(ENV, src_name)).convert("RGBA")
    arr = np.asarray(im).astype(float) / 255.0
    out = fn(arr) if strength is None else fn(arr, strength)
    Image.fromarray((np.clip(out, 0, 1) * 255).astype("uint8")).save(
        os.path.join(ENV, dest))
    print("grade", src_name, "->", dest)


def main():
    for src_name, dest, size in COPIES:
        save_norm(Image.open(os.path.join(TREES, src_name)).convert("RGBA"), dest, size)
    for src_name, dest, size in BUSH_COPIES:
        save_norm(Image.open(os.path.join(BUSHES, src_name)).convert("RGBA"), dest, size)
    for i in range(3):
        grade_file(f"rock_{i}.png", f"rock_desert_{i}.png", warm_grade)
        grade_file(f"rock_{i}.png", f"rock_snow_{i}.png", snow_grade, 0.5)
    grade_file("rockflat_0.png", "rockflat_snow_0.png", snow_grade, 0.6)
    for i in range(2):
        grade_file(f"ruin_{i}.png", f"ruin_snow_{i}.png", snow_grade, 0.5)


if __name__ == "__main__":
    main()
