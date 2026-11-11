#!/usr/bin/env python3
"""Slice Tín's painted START button into a transparent PNG.

Source: a JPEG (no alpha) on a pure-white background holding ONE
ornate red-gem / gold button with "BẮT ĐẦU" baked in (~2.9:1).
Same recovery as gen/rank_emblems_build.py / nav_buttons_build.py:
flood-fill from the borders through background-like pixels (very
light + near-neutral); the button's own light gold highlights are
enclosed by saturated/dark pixels so the flood never reaches them.
Soft alpha + nearest-core-colour inpainting kills the white halo.

Output: godot/assets/nav_buttons/start_button.png, tight-cropped
(+2px pad), natural aspect preserved for the home bottom band's
height-limited TextureButton.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = Path.home() / ("workspace/user/files/"
                     "9AEF9E4F-0456-470E-A743-A4B34E780F57-"
                     "photo-5C0F1419-4C3F-456A-8012-B4DBCA6C0F4F.jpg")
OUT = Path.home() / ("workspace/empire-age/godot/assets/nav_buttons/"
                     "start_button.png")

BG_VAL_MIN = 235
BG_SAT_MAX = 18
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
    lab, _ = ndimage.label(bg_like)
    border_labels = set(np.unique(np.concatenate([
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))) - {0}
    background = np.isin(lab, list(border_labels))
    hard = ~background

    alpha = ndimage.gaussian_filter(hard.astype(np.float32), 0.8)
    alpha = np.clip(alpha, 0.0, 1.0)
    core = (sat > CORE_SAT_MIN) | (mx < CORE_VAL_MAX)
    _, inds = ndimage.distance_transform_edt(
        ~core, return_distances=True, return_indices=True)
    nearest_rgb = a[tuple(inds)]
    weak = alpha < 0.98
    rgb = a.copy()
    rgb[weak] = nearest_rgb[weak]
    rgb[alpha <= 0.01] = nearest_rgb[alpha <= 0.01]
    alpha[alpha <= 0.01] = 0.0

    ys, xs = np.nonzero(hard)
    bx0, bx1, by0, by1 = xs.min(), xs.max(), ys.min(), ys.max()
    cx0, cx1 = max(0, bx0 - PAD), min(w - 1, bx1 + PAD)
    cy0, cy1 = max(0, by0 - PAD), min(h - 1, by1 + PAD)
    rgba_full = np.dstack([rgb.astype(np.uint8),
                           (alpha * 255).astype(np.uint8)])
    crop = rgba_full[cy0:cy1 + 1, cx0:cx1 + 1]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(crop, "RGBA").save(OUT)
    opaque = float((crop[:, :, 3] > 8).mean())
    print(f"start_button: bbox {bx1-bx0+1}x{by1-by0+1} "
          f"saved {crop.shape[1]}x{crop.shape[0]} "
          f"aspect {crop.shape[1]/crop.shape[0]:.3f} "
          f"opaque {opaque:.2%} -> {OUT.name}")
    print("done")


if __name__ == "__main__":
    sys.exit(main())
