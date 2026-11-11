#!/usr/bin/env python3
"""Re-slice the Minigame mode badge: medallion redesign (Tín's word:
the old crown+wings+shield badge read like Đấu Hạng — "Nút minigame
nhìn giống đấu hạng vậy"). New art: round golden medallion, purple
field, trophy + two oversized dice, laurel, purple "Minigame" ribbon
(media-generated on pure black, art_candidates/).

Same recovery recipe as gen/mode_badges_extra_build.py (flood-fill
from the borders through very dark + near-neutral pixels, soft
alpha, nearest-badge-colour inpainting for weak-alpha pixels), then
fitted CONTAIN-centred onto the EXACT canvas of the outgoing asset
(624x615) so the mode panel layout does not move at all.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path.home() / "workspace/empire-age"
SRC = (ROOT / "art_candidates"
       / "media-generation-mode-badge-minigame-medallion-0-"
         "3b55b4b0-2136-40b5-9bf4-2b986834866a.webp")
OUT = ROOT / "godot/assets/nav_buttons/mode_minigame.png"
CANVAS_W, CANVAS_H = 624, 615

BG_VAL_MAX = 26
BG_SAT_MAX = 20
CORE_SAT_MIN = 25
CORE_VAL_MIN = 60
PAD = 2


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    a = np.asarray(im).astype(np.int32)
    h, w, _ = a.shape
    mx = a.max(axis=2)
    sat = mx - a.min(axis=2)

    bg_like = (mx <= BG_VAL_MAX) & (sat <= BG_SAT_MAX)
    lab, _ = ndimage.label(bg_like)
    border_labels = set(np.unique(np.concatenate([
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))) - {0}
    background = np.isin(lab, list(border_labels))
    hard = ~background

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
    crop = Image.fromarray(rgba_full[cy0:cy1 + 1, cx0:cx1 + 1], "RGBA")

    scale = min(CANVAS_W / crop.width, CANVAS_H / crop.height)
    new_size = (round(crop.width * scale), round(crop.height * scale))
    fitted = crop.resize(new_size, Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    canvas.alpha_composite(
        fitted, ((CANVAS_W - new_size[0]) // 2,
                 (CANVAS_H - new_size[1]) // 2))
    canvas.save(OUT)
    opaque = float((np.asarray(canvas)[:, :, 3] > 8).mean())
    print(f"mode_minigame: src bbox {bx1-bx0+1}x{by1-by0+1} "
          f"crop {crop.width}x{crop.height} fitted {new_size} "
          f"canvas {CANVAS_W}x{CANVAS_H} opaque {opaque:.2%} -> {OUT}")


if __name__ == "__main__":
    sys.exit(main())
