#!/usr/bin/env python3
"""Defringe the character sheets (villager / militia / archer / portrait).

Diagnosis (measured on the shipped PNGs): the sheets come from opaque
JPG art, so most of the visible fringe is NOT semi-transparent pixels —
it is a rim of nearly OPAQUE pixels whose RGB is the character colour
pre-blended over the white page (e.g. hair edge ships as (145,143,141)
at alpha 251). Unblending alone cannot touch those. Three defects,
three fixes:

1. Contact-shadow blob: the art's ground shadow ships as opaque light
   grey (sat < 6%, lum > 150) under the feet — a white smear on grass.
   Converted (seeded from each frame's bottom rows, grown through
   matching pixels in the frame's lower zone) into a proper translucent
   black shadow: alpha = (255 - lum) * 1.7, capped.
2. Opaque rim: for pixels with a >= 0.9 within 2 px of transparency,
   estimate the true coverage t against the nearest deep-interior
   colour F (per-channel (255 - C) / (255 - F)); if t < 0.92 the pixel
   was mostly page — set RGB = F and alpha *= t. Dark pixels (bow,
   sword, straps) yield t ~= 1 and are left untouched; near-white F
   (white cloth) is skipped because t is unrecoverable there.
3. Semi-transparent ring (graded alpha from the pipeline's resize):
   classic white-matte unblend F = (C - (1 - a) * 255) / a, then a
   gentle bleed toward the nearest opaque colour, and opaque colours
   bled a few px into the transparent margin so texture filtering
   never samples bare black/white from under transparency.

villager_portrait.png (binary alpha, never resized) instead gets a
1 px anti-aliased alpha ramp (Gaussian coverage of its silhouette);
pixels the ramp newly covers outside the old mask take the nearest
interior colour. Its shadow blob gets fix 1 with tighter zones.

Overwrites the four PNGs in place (same sizes, manifests untouched).
Re-runnable: python3 tools/defringe_characters.py
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "assets")
SHEETS = ["villager", "militia", "archer"]
PORTRAIT = "villager_portrait.png"
BLEED_DIST = 4  # px of colour bleed into the transparent zone


def nearest_colour(rgb, good):
    """RGB of the nearest 'good' pixel for every pixel (EDT indices)."""
    _, inds = ndimage.distance_transform_edt(~good, return_indices=True)
    return rgb[inds[0], inds[1]]


def convert_shadow(rgba, cell_w, cell_h, seed_frac=0.18, zone_frac=0.45):
    """Fix 1: opaque light-grey contact shadow -> translucent black."""
    rgb = rgba[..., :3]
    a = rgba[..., 3]
    lum = rgb.mean(axis=2)
    sat = (rgb.max(axis=2) - rgb.min(axis=2)) / np.maximum(rgb.max(axis=2), 1)
    cand = (a > 0) & (sat < 0.06) & (lum > 150)
    h, w = a.shape
    total = 0
    for y0 in range(0, h, cell_h):
        for x0 in range(0, w, cell_w):
            sub = cand[y0:y0 + cell_h, x0:x0 + cell_w]
            if not sub.any():
                continue
            chh, cww = sub.shape
            zone = np.zeros_like(sub)
            zone[int((1 - zone_frac) * chh):, :] = True
            seeds = np.zeros_like(sub)
            seeds[int((1 - seed_frac) * chh):, :] = True
            grow = sub & zone
            lab, n = ndimage.label(grow, structure=np.ones((3, 3)))
            if n == 0:
                continue
            hit = set(np.unique(lab[seeds & grow])) - {0}
            if not hit:
                continue
            blob = np.isin(lab, list(hit))
            # Detached shadow tails (split from the blob by a shoe) in
            # the cell's bottom rows are shadow too — convert them all.
            blob |= sub & seeds & (np.indices(sub.shape)[0]
                                   >= int(0.92 * chh))
            ys, xs = np.where(blob)
            gy, gx = ys + y0, xs + x0
            new_a = np.clip((255.0 - lum[gy, gx]) / 255.0 * 1.7, 0.0, 0.55)
            rgba[gy, gx, 3] = new_a * 255.0
            rgba[gy, gx, :3] = 0.0
            total += len(gy)
    return total


def refine_rim(rgba):
    """Fix 2: coverage-estimate the opaque rim; returns pixels changed."""
    rgb = rgba[..., :3]
    a = rgba[..., 3] / 255.0
    dist = ndimage.distance_transform_edt(a > 0)
    interior = (dist >= 3) & (a >= 0.9)
    if not interior.any():
        return 0
    near_f = nearest_colour(rgb, interior)
    rim = (a >= 0.9) & (dist <= 2) & (dist > 0)
    # skip where the interior colour itself is near-white (t undefined)
    estimable = (255.0 - near_f).min(axis=2) > 18
    ys, xs = np.where(rim & estimable)
    if len(ys) == 0:
        return 0
    c = rgb[ys, xs]
    f = near_f[ys, xs]
    t = np.clip((255.0 - c) / np.maximum(255.0 - f, 1.0), 0.0, 1.0).mean(axis=1)
    hit = t < 0.92
    if not hit.any():
        return 0
    ys, xs = ys[hit], xs[hit]
    rgba[ys, xs, :3] = f[hit]
    rgba[ys, xs, 3] = (a[ys, xs] * t[hit] * 255.0)
    return int(hit.sum())


def unblend_and_bleed(rgba, refined):
    """Fix 3: unblend semi pixels (except rim-refined ones), then bleed."""
    rgb = rgba[..., :3]
    a = rgba[..., 3] / 255.0
    semi = (a > 0.0) & (a < 0.9) & ~refined
    fixed = rgb.copy()
    av = a[semi]
    fixed[semi] = np.clip(
        (rgb[semi] - (1.0 - av)[:, None] * 255.0) / av[:, None], 0, 255)
    opaque = a >= 0.9
    near = nearest_colour(fixed, opaque)
    lean = ((a > 0.0) & (a < 0.9))
    w = np.where(lean, 0.45 * (1.0 - a), 0.0)
    fixed = fixed * (1.0 - w[..., None]) + near * w[..., None]
    dist = ndimage.distance_transform_edt(a <= 0.0)
    margin = (a <= 0.0) & (dist <= BLEED_DIST)
    fixed[margin] = near[margin]
    rgba[..., :3] = fixed


def drop_dust(rgba, cell_w, cell_h):
    """Drop detached islands of <= 4 px per frame cell (JPEG dust and
    shadow breakup). Real detached props (carried logs, ore) are far
    bigger; the largest component of each cell is always kept."""
    a = rgba[..., 3] > 0
    h, w = a.shape
    total = 0
    for y0 in range(0, h, cell_h):
        for x0 in range(0, w, cell_w):
            sub = a[y0:y0 + cell_h, x0:x0 + cell_w]
            if not sub.any():
                continue
            lab, n = ndimage.label(sub)
            if n <= 1:
                continue
            areas = ndimage.sum(sub, lab, index=np.arange(1, n + 1))
            main_id = int(np.argmax(areas)) + 1
            drop = [i for i in range(1, n + 1)
                    if i != main_id and areas[i - 1] <= 4]
            if not drop:
                continue
            kill = np.isin(lab, drop)
            ys, xs = np.where(kill)
            rgba[ys + y0, xs + x0, 3] = 0.0
            total += len(ys)
    return total


def halo_score(rgba, bg=(16.0, 24.0, 48.0)):
    """Mean luminance of the composited edge ring on navy (diagnostic)."""
    rgb = rgba[..., :3].astype(np.float64)
    a = rgba[..., 3:].astype(np.float64) / 255.0
    comp = rgb * a + np.array(bg) * (1.0 - a)
    ring = (a[..., 0] > 0.02) & (a[..., 0] < 0.98)
    if ring.sum() == 0:
        return 0.0
    lum = comp[..., 0] * 0.299 + comp[..., 1] * 0.587 + comp[..., 2] * 0.114
    return float(lum[ring].mean())


def process_sheet(name):
    path = os.path.join(ASSETS, name + ".png")
    man = json.load(open(os.path.join(ASSETS, name + "_frames.json")))
    arr = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64)
    before = halo_score(arr)
    n_shadow = convert_shadow(arr, man["cell_w"], man["cell_h"])
    refined = np.zeros(arr.shape[:2], dtype=bool)
    # refine_rim edits alpha; track which pixels it touched so the
    # unblend phase leaves their (already correct) colours alone
    pre_alpha = arr[..., 3].copy()
    n_rim = refine_rim(arr)
    refined = arr[..., 3] != pre_alpha
    unblend_and_bleed(arr, refined)
    n_dust = drop_dust(arr, man["cell_w"], man["cell_h"])
    after = halo_score(arr)
    Image.fromarray(arr.astype(np.uint8), "RGBA").save(path)
    print("%s.png: shadow px=%d, rim px=%d, dust px=%d, ring luminance %.1f -> %.1f"
          % (name, n_shadow, n_rim, n_dust, before, after))


def process_portrait():
    path = os.path.join(ASSETS, PORTRAIT)
    arr = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64)
    n_shadow = convert_shadow(arr, arr.shape[1], arr.shape[0],
                              seed_frac=0.06, zone_frac=0.10)
    mask = arr[..., 3] > 0
    blurred = ndimage.gaussian_filter(mask.astype(np.float64), 0.85)
    arr[..., 3] = np.clip(blurred, 0.0, 1.0) * 255.0
    # pixels newly covered outside the old mask: nearest interior colour
    near = nearest_colour(arr[..., :3], mask)
    outside = ~mask & (arr[..., 3] > 0)
    arr[outside, :3] = near[outside]
    # colour margin under full transparency for filtered sampling
    dist = ndimage.distance_transform_edt(arr[..., 3] <= 0)
    margin = (arr[..., 3] <= 0) & (dist <= BLEED_DIST)
    arr[margin, :3] = near[margin]
    drop_dust(arr, arr.shape[1], arr.shape[0])
    Image.fromarray(arr.astype(np.uint8), "RGBA").save(path)
    semi = int(((arr[..., 3] > 0) & (arr[..., 3] < 255)).sum())
    print("%s: shadow px=%d, AA ramp semi px=%d" % (PORTRAIT, n_shadow, semi))


def main():
    for name in SHEETS:
        process_sheet(name)
    process_portrait()


if __name__ == "__main__":
    main()
