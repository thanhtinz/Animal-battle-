#!/usr/bin/env python3
"""Slice the generated Custom / Minigame mode badges into transparent PNGs.

Companion to gen/mode_badges_build.py (same recovery recipe): each
source is ONE painted heraldic badge on a pure-BLACK background
(media-generated WebP in art_candidates/). The background is recovered
by flood-filling from the borders through very dark + near-neutral
pixels (threshold kept LOW so the badges' own dark shield regions —
deep emerald / royal purple, saturated enough to sit above it — are
NOT eaten). The final alpha is a slightly blurred hard mask and every
weak-alpha pixel's RGB is replaced by the nearest definitely-badge
colour, so no black halo survives.

Output: godot/assets/nav_buttons/mode_custom.png and
mode_minigame.png — each tight-cropped to its badge (+2px pad),
keeping its natural aspect, like the existing mode_normal /
mode_ranked pair.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path.home() / "workspace/empire-age"
JOBS = [
    (ROOT / "art_candidates"
     / "media-generation-mode-badge-custom-gen-0-"
       "4c8941c7-bba4-4e40-be1c-e32187403778.webp",
     "mode_custom"),
    (ROOT / "art_candidates"
     / "media-generation-mode-badge-minigame-gen-0-"
       "b6dbceb6-e347-4924-88e0-2bbdfe5e0b38.webp",
     "mode_minigame"),
]
OUT_DIR = ROOT / "godot/assets/nav_buttons"

# Background-like: very dark and near-neutral (same as the original
# badge slice — the badges' dark shield edges sit above this).
BG_VAL_MAX = 26
BG_SAT_MAX = 20
# Definitely-badge (colour source for halo inpainting).
CORE_SAT_MIN = 25
CORE_VAL_MIN = 60
PAD = 2


def slice_badge(src: Path, name: str) -> None:
    im = Image.open(src).convert("RGB")
    a = np.asarray(im).astype(np.int32)
    h, w, _ = a.shape
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    sat = mx - mn

    bg_like = (mx <= BG_VAL_MAX) & (sat <= BG_SAT_MAX)
    lab, _ = ndimage.label(bg_like)
    border_labels = set(np.unique(np.concatenate([
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))) - {0}
    background = np.isin(lab, list(border_labels))
    hard = ~background

    # Soft alpha + colour inpainting (kills the black halo).
    alpha = ndimage.gaussian_filter(hard.astype(np.float32), 0.8)
    alpha = np.clip(alpha, 0.0, 1.0)
    core = (sat > CORE_SAT_MIN) | (mx > CORE_VAL_MIN)
    _, inds = ndimage.distance_transform_edt(
        ~core, return_distances=True, return_indices=True)
    nearest_rgb = a[tuple(inds)]
    weak = alpha < 0.98
    rgb = a.copy()
    rgb[weak] = nearest_rgb[weak]
    rgb[alpha <= 0.01] = nearest_rgb[alpha <= 0.01]
    alpha[alpha <= 0.01] = 0.0

    ys, xs = np.nonzero(hard)
    bx0, bx1 = xs.min(), xs.max()
    by0, by1 = ys.min(), ys.max()
    cx0, cx1 = max(0, bx0 - PAD), min(w - 1, bx1 + PAD)
    cy0, cy1 = max(0, by0 - PAD), min(h - 1, by1 + PAD)
    rgba_full = np.dstack([rgb.astype(np.uint8),
                           (alpha * 255).astype(np.uint8)])
    crop = rgba_full[cy0:cy1 + 1, cx0:cx1 + 1]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{name}.png"
    Image.fromarray(crop, "RGBA").save(out)
    opaque = float((crop[:, :, 3] > 8).mean())
    print(f"{name}: bbox {bx1-bx0+1}x{by1-by0+1} "
          f"saved {crop.shape[1]}x{crop.shape[0]} "
          f"aspect {crop.shape[1]/crop.shape[0]:.3f} "
          f"opaque {opaque:.2%} -> {out.name}")


def main() -> None:
    for src, name in JOBS:
        slice_badge(src, name)
    print("done")


if __name__ == "__main__":
    sys.exit(main())
