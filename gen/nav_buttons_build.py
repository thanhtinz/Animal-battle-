#!/usr/bin/env python3
"""Slice Tín's painted home-nav button sheet into 4 transparent PNGs.

Source: a JPEG (no alpha) on a pure-white background holding 4 ornate
gold laurel badge-buttons with baked-in labels, left -> right:
  THÀNH TÍCH (trophy) · LỊCH SỬ TRẬN (scroll) · BẢNG XẾP HẠNG
  (podium) · BẠN BÈ (people +)
The background is recovered exactly like gen/rank_emblems_build.py:
flood-fill from the borders through background-like pixels (very
light + near-neutral). Interior light regions (parchment, the silver
people glyphs) are enclosed by gold/dark pixels, so the flood never
reaches them. The final alpha is a slightly blurred hard mask and
every weak-alpha pixel's RGB is replaced by the nearest
definitely-badge colour, so no white JPEG halo survives.

Output: godot/assets/nav_buttons/nav_{profile,history,leaderboard,
friends}.png — each tight-cropped to its own badge (+2px pad), so
each texture keeps its own natural aspect for aspect-preserved
TextureButtons in the home bottom band.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = Path.home() / ("workspace/user/files/"
                     "8CD3936D-1099-4B4C-80E4-B8B10B890E5D-"
                     "photo-17B8403D-A726-404B-A8EA-48A9A90D5432.jpg")
OUT_DIR = Path.home() / "workspace/empire-age/godot/assets/nav_buttons"
NAMES = ["nav_profile", "nav_history", "nav_leaderboard", "nav_friends"]

# Background-like: very light and near-neutral.
BG_VAL_MIN = 235
BG_SAT_MAX = 18
# Definitely-badge (colour source for halo inpainting).
CORE_SAT_MIN = 25
CORE_VAL_MAX = 215
PAD = 2


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    a = np.asarray(im).astype(np.int32)
    h, w, _ = a.shape
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    sat = mx - mn

    bg_like = (mx >= BG_VAL_MIN) & (sat <= BG_SAT_MAX)
    # Flood: label bg-like components, keep only border-touching ones.
    lab, _ = ndimage.label(bg_like)
    border_labels = set(np.unique(np.concatenate([
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))) - {0}
    background = np.isin(lab, list(border_labels))
    hard = ~background  # badge silhouettes (hard alpha)

    # Column runs of the silhouette -> the 4 badges.
    colsum = hard.sum(axis=0)
    runs = []
    inrun = False
    for x in range(w):
        if colsum[x] > 2 and not inrun:
            start = x
            inrun = True
        elif colsum[x] <= 2 and inrun:
            runs.append((start, x - 1))
            inrun = False
    if inrun:
        runs.append((start, w - 1))
    assert len(runs) == 4, f"expected 4 badges, found {len(runs)} runs"

    # Soft alpha + colour inpainting (kills the white JPEG halo).
    alpha = ndimage.gaussian_filter(hard.astype(np.float32), 0.8)
    alpha = np.clip(alpha, 0.0, 1.0)
    core = (sat > CORE_SAT_MIN) | (mx < CORE_VAL_MAX)
    _, inds = ndimage.distance_transform_edt(
        ~core, return_distances=True, return_indices=True)
    nearest_rgb = a[tuple(inds)]  # colour of nearest core pixel
    weak = alpha < 0.98
    rgb = a.copy()
    rgb[weak] = nearest_rgb[weak]
    rgb[alpha <= 0.01] = nearest_rgb[alpha <= 0.01]
    alpha[alpha <= 0.01] = 0.0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # Cast BEFORE stacking: saving an int32 array via PIL corrupts the
    # channels (only R survives). The emblem script avoided this by
    # compositing into a uint8 canvas; here we cast directly.
    rgba_full = np.dstack([rgb.astype(np.uint8),
                           (alpha * 255).astype(np.uint8)])
    for i, (x0, x1) in enumerate(runs):
        sub = hard[:, x0:x1 + 1]
        ys, xs = np.nonzero(sub)
        bx0, bx1 = x0 + xs.min(), x0 + xs.max()
        by0, by1 = ys.min(), ys.max()
        cx0, cx1 = max(0, bx0 - PAD), min(w - 1, bx1 + PAD)
        cy0, cy1 = max(0, by0 - PAD), min(h - 1, by1 + PAD)
        crop = rgba_full[cy0:cy1 + 1, cx0:cx1 + 1]
        out = OUT_DIR / f"{NAMES[i]}.png"
        Image.fromarray(crop, "RGBA").save(out)
        opaque = float((crop[:, :, 3] > 8).mean())
        print(f"{NAMES[i]}: bbox {bx1-bx0+1}x{by1-by0+1} "
              f"saved {crop.shape[1]}x{crop.shape[0]} "
              f"aspect {crop.shape[1]/crop.shape[0]:.3f} "
              f"opaque {opaque:.2%} -> {out.name}")
    print("done")


if __name__ == "__main__":
    sys.exit(main())
