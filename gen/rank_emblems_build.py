#!/usr/bin/env python3
"""Slice Tín's rank-emblem sheet into 8 per-tier transparent PNGs.

Source: a JPEG (no alpha) whose "transparent" background is baked in
as a near-uniform light neutral (val 246-255, saturation ~0). The
emblems themselves are saturated, so the background is recovered by
flood-filling from the image borders through background-like pixels
(very light + near-neutral). Interior light regions of an emblem
(silver highlights) are enclosed by non-background pixels, so the
flood never reaches them.

Edge cleanliness: JPEG leaves a ~1px light halo around each emblem.
The final alpha is a slightly blurred version of the hard flood
mask, and every pixel whose alpha < 0.98 (halo band + fully
transparent surround) gets its RGB replaced by the nearest
definitely-emblem pixel's colour. Result: no white fringe on dark
backgrounds, and texture filtering/mipmaps never bleed white.

Output: godot/assets/rank_emblems/tier_0.png .. tier_7.png on one
shared canvas (max emblem w x h), each emblem centred.
Order left->right = ladder order:
  0 Tân Binh (bronze) · 1 Chiến Binh (silver) · 2 Kỵ Sĩ (gold-blue)
  3 Nam Tước (purple) · 4 Bá Tước (ice-blue) · 5 Hầu Tước (red-gold)
  6 Công Tước (gold) · 7 Hoàng Đế (gold-pink)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = Path.home() / ("workspace/user/files/"
                     "9E6B2C9D-499A-4D5D-9CBA-3D5FF007E2D3-"
                     "photo-03A16C20-4346-4212-B4EC-79DEECB42A19.jpg")
OUT_DIR = Path.home() / "workspace/empire-age/godot/assets/rank_emblems"

# Background-like: very light and near-neutral.
BG_VAL_MIN = 235
BG_SAT_MAX = 18
# Definitely-emblem (colour source for halo inpainting).
CORE_SAT_MIN = 25
CORE_VAL_MAX = 215


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
    hard = ~background  # emblem silhouette (hard alpha)

    # Column runs of the silhouette -> the 8 emblems.
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
    assert len(runs) == 8, f"expected 8 emblems, found {len(runs)} runs"

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

    boxes = []
    for (x0, x1) in runs:
        sub = hard[:, x0:x1 + 1]
        ys, xs = np.nonzero(sub)
        boxes.append((x0 + xs.min(), ys.min(), x0 + xs.max(), ys.max()))
    cw = max(b[2] - b[0] + 1 for b in boxes)
    ch = max(b[3] - b[1] + 1 for b in boxes)
    print(f"shared canvas {cw}x{ch}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rgba_full = np.dstack([rgb, (alpha * 255).astype(np.uint8)])
    for i, (bx0, by0, bx1, by1) in enumerate(boxes):
        crop = rgba_full[by0:by1 + 1, bx0:bx1 + 1]
        canvas = np.zeros((ch, cw, 4), dtype=np.uint8)
        oy = (ch - crop.shape[0]) // 2
        ox = (cw - crop.shape[1]) // 2
        canvas[oy:oy + crop.shape[0], ox:ox + crop.shape[1]] = crop
        out = OUT_DIR / f"tier_{i}.png"
        Image.fromarray(canvas, "RGBA").save(out)
        opaque = float((canvas[:, :, 3] > 8).mean())
        print(f"tier_{i}: bbox {bx1-bx0+1}x{by1-by0+1} "
              f"opaque {opaque:.2%} -> {out.name}")
    print("done")


if __name__ == "__main__":
    sys.exit(main())
