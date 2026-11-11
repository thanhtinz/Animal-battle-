#!/usr/bin/env python3
"""De-rim the building sprites (assets/buildings/*.png).

The chart cuts have the same white-page rim problem the character
sheets had: a 1-2 px band of nearly opaque pixels whose RGB is the
paint colour pre-blended over the chart's white background (brightest
along roof and thatch edges). This pass ONLY un-blends that rim:

  * for rim pixels (alpha > 0, within 2 px of transparency), estimate
    the true coverage t against the nearest deep-interior colour F —
    per channel (255 - C) / (255 - F) — and where t < 0.97 store the
    pure interior colour at alpha t, so the edge composites correctly
    on the game terrain instead of glowing pale;
  * bleed interior colours a few px under the transparent margin so
    sampling near the edge never picks up bare stored RGB.

Deliberately NOT done (unlike the characters): no erosion, no shadow
conversion, no dust/component dropping — buildings keep their crisp
dark outlines, their detached props and their NEAREST rendering.
Overwrites the PNGs in place, same sizes.
"""
import glob
import os

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
BLDG = os.path.join(HERE, "..", "assets", "buildings")
BLEED_DIST = 3


def nearest_colour(rgb, good):
    _, inds = ndimage.distance_transform_edt(~good, return_indices=True)
    return rgb[inds[0], inds[1]]


def process(path):
    arr = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64)
    rgb, a = arr[..., :3], arr[..., 3]
    solid = a > 0
    dist = ndimage.distance_transform_edt(solid)
    interior = solid & (dist >= 3)
    if not interior.any():
        return 0, 0, 0
    near_f = nearest_colour(rgb, interior)
    rim = solid & (dist <= 2) & (dist > 0)
    lum = rgb.mean(axis=2)
    pale_before = int((rim & (lum > 200)).sum())
    # Coverage estimation only where the interior colour is dark enough
    # for the estimate to be defined (a near-white interior means the
    # pixel may be honest pale paint — leave it alone).
    estimable = (255.0 - near_f).min(axis=2) > 18
    ys, xs = np.where(rim & estimable)
    changed = 0
    if len(ys):
        c = rgb[ys, xs]
        f = near_f[ys, xs]
        t = np.clip((255.0 - c) / np.maximum(255.0 - f, 1.0), 0.0, 1.0).mean(axis=1)
        hit = t < 0.97
        if hit.any():
            ys2, xs2 = ys[hit], xs[hit]
            arr[ys2, xs2, :3] = f[hit]
            arr[ys2, xs2, 3] = np.clip(t[hit], 0.05, 1.0) * 255.0
            changed = int(hit.sum())
    # Colour bleed under the transparent margin.
    dist_t = ndimage.distance_transform_edt(arr[..., 3] <= 0)
    margin = (arr[..., 3] <= 0) & (dist_t <= BLEED_DIST)
    arr[margin, :3] = near_f[margin]
    Image.fromarray(arr.astype(np.uint8), "RGBA").save(path)
    a2 = arr[..., 3]
    rim2 = (a2 > 0) & (ndimage.distance_transform_edt(a2 > 0) <= 2)
    pale_after = int((rim2 & (arr[..., :3].mean(axis=2) > 200)
                      & (a2 >= 250)).sum())
    return changed, pale_before, pale_after


def main():
    total = 0
    for path in sorted(glob.glob(os.path.join(BLDG, "*.png"))):
        ch, pb, pa = process(path)
        total += ch
        print("%-24s rim px unblended=%5d  opaque pale rim px %d -> %d"
              % (os.path.basename(path), ch, pb, pa))
    print("TOTAL rim px unblended:", total)


if __name__ == "__main__":
    main()
