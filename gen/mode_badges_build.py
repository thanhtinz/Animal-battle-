#!/usr/bin/env python3
"""Slice Tín's painted mode-choice badges into 2 transparent PNGs.

Source: a JPEG (no alpha) on a pure-BLACK background holding 2 ornate
emblem badges with baked-in ribbon labels, left -> right:
  Đấu Thường (blue crossed-swords shield) · Đấu Hạng (red-gold
  winged-crown shield)
The background is recovered like gen/nav_buttons_build.py, mirrored
for black: flood-fill from the borders through background-like pixels
(very dark + near-neutral, threshold kept LOW so the badges' own
dark shield edges and navy shadow regions are NOT eaten — those are
either enclosed by gold or sit above the threshold). Interior dark
regions (the navy shield bottoms) are enclosed by gold/dark rims, so
the flood never reaches them. The final alpha is a slightly blurred
hard mask and every weak-alpha pixel's RGB is replaced by the nearest
definitely-badge colour, so no black JPEG halo survives.

Output: godot/assets/nav_buttons/mode_normal.png (left) and
mode_ranked.png (right) — each tight-cropped to its own badge (+2px
pad), keeping its natural aspect for aspect-preserved TextureButtons
in the home mode-choice panel.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = Path.home() / ("workspace/user/files/"
                     "412B1FBE-18C6-4BA6-8482-B07C16666D7F-"
                     "photo-B3B6B09E-37CF-464A-947E-1984B85ECD2B.jpg")
OUT_DIR = Path.home() / "workspace/empire-age/godot/assets/nav_buttons"
NAMES = ["mode_normal", "mode_ranked"]

# Background-like: very dark and near-neutral. Kept conservative so
# the badges' dark shield edges (navy, mx well above this) survive.
BG_VAL_MAX = 26
BG_SAT_MAX = 20
# Definitely-badge (colour source for halo inpainting).
CORE_SAT_MIN = 25
CORE_VAL_MIN = 60
PAD = 2


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    a = np.asarray(im).astype(np.int32)
    h, w, _ = a.shape
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    sat = mx - mn

    bg_like = (mx <= BG_VAL_MAX) & (sat <= BG_SAT_MAX)
    # Flood: label bg-like components, keep only border-touching ones.
    lab, _ = ndimage.label(bg_like)
    border_labels = set(np.unique(np.concatenate([
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))) - {0}
    background = np.isin(lab, list(border_labels))
    hard = ~background  # badge silhouettes (hard alpha)

    # Column runs of the silhouette -> the 2 badges.
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
    assert len(runs) == 2, f"expected 2 badges, found {len(runs)} runs"

    # Soft alpha + colour inpainting (kills the black JPEG halo).
    alpha = ndimage.gaussian_filter(hard.astype(np.float32), 0.8)
    alpha = np.clip(alpha, 0.0, 1.0)
    core = (sat > CORE_SAT_MIN) | (mx > CORE_VAL_MIN)
    _, inds = ndimage.distance_transform_edt(
        ~core, return_distances=True, return_indices=True)
    nearest_rgb = a[tuple(inds)]  # colour of nearest core pixel
    weak = alpha < 0.98
    rgb = a.copy()
    rgb[weak] = nearest_rgb[weak]
    rgb[alpha <= 0.01] = nearest_rgb[alpha <= 0.01]
    alpha[alpha <= 0.01] = 0.0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # Cast BEFORE stacking (int32 via PIL corrupts channels).
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
