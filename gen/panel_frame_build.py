#!/usr/bin/env python3
"""Slice Tín's painted mode-panel frame into a transparent PNG.

Source: a JPEG (no alpha) on a pure-white background holding ONE
ornate gold panel frame (red gems top/bottom centre, dark navy
glass interior, aspect ~1.51). Same recovery as the other sheets:
flood-fill from the borders through background-like pixels (very
light + near-neutral) — the frame's gold is saturated and the navy
glass is dark and enclosed, so the flood only takes the outside
white. Soft alpha + nearest-core-colour inpainting kills the
white JPEG halo.

Output: godot/assets/nav_buttons/mode_frame.png, tight-cropped
(+2px pad). The mode panel in home_lobby.gd is sized FROM this
texture's aspect, and its content is laid out inside the glass
area (measured inner fractions: glass spans roughly x 0.06..0.95,
y 0.16..0.81 of the frame; content uses a safer inset).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = Path.home() / ("workspace/user/files/"
                     "F7774AE8-ADBF-419E-A74E-CF7666A8CCF8-"
                     "photo-41D12029-6A23-4EFA-AC52-C45FDFFB2D4B.jpg")
OUT = Path.home() / ("workspace/empire-age/godot/assets/nav_buttons/"
                     "mode_frame.png")

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
    print(f"mode_frame: bbox {bx1-bx0+1}x{by1-by0+1} "
          f"saved {crop.shape[1]}x{crop.shape[0]} "
          f"aspect {crop.shape[1]/crop.shape[0]:.3f} "
          f"opaque {opaque:.2%} -> {OUT.name}")
    print("done")


if __name__ == "__main__":
    sys.exit(main())
