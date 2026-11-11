#!/usr/bin/env python3
"""Re-cut the BUILDING sprites from the original tier charts with the
same smooth alpha matting that fixed the characters in v3
(tools/recut_smooth.py) — the v4 smooth-edge pass for buildings.

Why: the buildings only got the light derim touch (rim unblend on a
BINARY alpha, NEAREST rendering kept). At the in-game fractional scale
(art drawn 1.5x footprint, camera zooms) the hard 1-2 px alpha steps
still read as chunky, smeared edges ("lem") — Tín asked for the
buildings to get the full treatment too.

Pipeline per chart (geometry identical to tools/extract_buildings.py):
  1. build_alpha detection (copied there) -> the 4 largest components
     are the 4 tiers, reading order; the compound is one whole mask.
  2. remove_slab (verbatim from extract_buildings) cuts the baked-in
     grass plot / dirt path out of the binary mask — the building's own
     stone foundation / wooden base / rock base and the detached props
     survive, exactly as the shipped sprites.
  3. Smooth matte of the cleaned silhouette (matte_crop's maths from
     recut_smooth): per-pixel coverage from the whiteness ratio
     against the nearest interior colour, gaussian-smoothed over a
     3 px support band, RGB unblended from white and bled from the
     interior, so the silhouette edge is a soft gradient instead of a
     binary step.
  Two building-specific guards on top of the character recipe:
  * FORBIDDEN zone: pixels the slab removal cut (component minus
    cleaned mask, dilated) keep alpha 0 — the feather band must not
    reach down into the chart's grass/dirt and resurrect the slab as
    a green fringe under the foundation.
  * Interior firm-up only outside classified page HOLES: near-white
    regions are labelled — a region is a hole when it touches the
    outside of the silhouette / the forbidden zone (the page, tower
    gaps open to the slab), or when it is a large flat page-white
    expanse (inscribed radius >= 8 px and mean whiteness-distance
    < 0.05: the crane-frame wedge in miningcamp_t4, tower windows).
    Enclosed pale PAINT (sunlit stone-top highlights, cream cloth)
    fails both tests and is firmed back to opaque — the first v4 cut
    ate those highlight strips as dotted holes in the rocks.
  4. Trim to the alpha bbox and downscale to <=512 px in PREMULTIPLIED
     space (the old bilinear straight-RGBA resize smeared edge colour).

Rendering side (done alongside, see scripts/building.gd): the art
sprite now uses TEXTURE_FILTER_LINEAR_WITH_MIPMAPS and the building
.import files generate mipmaps, matching the characters and HUD.

Prints per-sprite before/after metrics: edge-ring luminance on navy
(the defringe/halo metric) and the opaque pale-rim pixel count (the
derim metric), plus interior-loss and slab-resurrection guards.
Re-runnable: python3 tools/recut_buildings_smooth.py
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from extract_buildings import (CHARTS, MAX_SIZE, OUT_DIR, SRC_COMPOUND,
                               build_alpha, remove_slab, slab_masks)
from recut_smooth import halo_score, resize_premul, smoothstep

PAD = 6  # source px of matting margin kept around each component
BACKUP = "/tmp/bldg_v4/backup"  # pre-v4 sprites, for before/after metrics


# --------------------------------------------------------------------------
# Smooth matting (adapted from recut_smooth.matte_crop)
# --------------------------------------------------------------------------
def matte_component(rgb, prior, fg_full, forbidden):
    """Smooth-matte one cleaned component at full chart size.

    rgb: uint8 chart RGB. prior: bool cleaned silhouette (slab already
    removed). fg_full: detection foreground (keeps neighbouring chart
    furniture out of the support band). forbidden: bool pixels removed
    by the slab cut — alpha stays 0 there.
    Returns a uint8 RGBA PIL image trimmed to the alpha bbox.
    """
    ys, xs = np.where(prior)
    H, W = prior.shape
    x0, x1 = max(0, int(xs.min()) - PAD), min(W, int(xs.max()) + 1 + PAD)
    y0, y1 = max(0, int(ys.min()) - PAD), min(H, int(ys.max()) + 1 + PAD)
    crop = rgb[y0:y1, x0:x1].astype(np.float64)
    pri = prior[y0:y1, x0:x1]
    fgc = fg_full[y0:y1, x0:x1]
    forb = forbidden[y0:y1, x0:x1]

    d = np.sqrt(((255.0 - crop) ** 2).sum(axis=2)) / (255.0 * np.sqrt(3.0))
    dist_in = ndimage.distance_transform_edt(pri)
    interior = dist_in >= 2
    _, inds = ndimage.distance_transform_edt(~interior, return_indices=True)
    near_rgb = crop[inds[0], inds[1]]
    d_near = d[inds[0], inds[1]]
    # Coverage: whiteness ratio against the nearest interior colour.
    alpha = np.clip(d / np.maximum(d_near, 0.08), 0.0, 1.0)
    nearwhite = d_near < 0.08
    alpha = np.where(nearwhite, smoothstep(0.03, 0.20, d), alpha)
    alpha = np.where(d < 0.025, 0.0, alpha)
    support = ndimage.binary_dilation(pri, iterations=3) & (pri | ~fgc) & ~forb
    alpha = np.where(support, alpha, 0.0)
    alpha = ndimage.gaussian_filter(alpha, 0.7)
    alpha = np.where(support, alpha, 0.0)
    # Gentle alpha contrast (same as the character pass).
    alpha = smoothstep(0.06, 0.94, alpha)
    # Classify near-white regions: page HOLES vs honest pale paint.
    # A region is a hole when it touches the outside of the silhouette
    # or the forbidden zone, or when it is a large flat page-white
    # expanse. Enclosed pale paint (stone-top highlights) is neither.
    whiteish = d < 0.10
    lab_w, nw = ndimage.label(whiteish)
    hole = np.zeros_like(pri)
    if nw:
        idx = np.arange(1, nw + 1)
        touch_ids = set(np.unique(lab_w[(~pri) | forb])) - {0}
        edt_w = ndimage.distance_transform_edt(whiteish)
        maxedt = ndimage.maximum(edt_w, lab_w, index=idx)
        meand = ndimage.mean(d, lab_w, index=idx)
        hole_ids = [i for i in idx
                    if i in touch_ids or (maxedt[i - 1] >= 8 and meand[i - 1] < 0.05)]
        if hole_ids:
            hole = np.isin(lab_w, hole_ids)
    # Firm up the deep interior — but never resurrect a page hole as
    # opaque white; holes keep the low alpha their whiteness earns.
    alpha = np.where((dist_in >= 3) & ~hole, 1.0, alpha)
    alpha = np.where(hole, np.minimum(alpha, smoothstep(0.03, 0.20, d)), alpha)
    alpha = np.where(forb, 0.0, alpha)
    alpha = np.clip(alpha, 0.0, 1.0)

    # Guard: deep-interior PAINT pixels that lost their alpha (would
    # read as a hole punched in painted wall/roof).
    lost = pri & (dist_in >= 4) & (alpha < 0.5) & ~hole
    lost_n = int(lost.sum())

    # Unblend RGB from white, then bleed toward the interior colour.
    F = crop.copy()
    semi = (alpha > 0.02) & (alpha < 0.98)
    av = alpha[semi]
    F[semi] = np.clip((crop[semi] - (1.0 - av)[:, None] * 255.0) / av[:, None], 0, 255)
    lean = (alpha > 0.0) & (alpha < 0.9)
    wgt = np.where(lean, 0.35 * (1.0 - alpha), 0.0)
    F = F * (1.0 - wgt[..., None]) + near_rgb * wgt[..., None]
    # Colour margin under full transparency for filtered sampling.
    dout = ndimage.distance_transform_edt(alpha <= 0.0)
    margin = (alpha <= 0.0) & (dout <= 3)
    F[margin] = near_rgb[margin]

    out = np.dstack([F, alpha * 255.0])
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    # Trim to the visible alpha bbox, downscale premultiplied.
    bbox = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if bbox:
        img = img.crop(bbox)
    if max(img.size) > MAX_SIZE:
        scale = MAX_SIZE / float(max(img.size))
        img = resize_premul(img, (round(img.size[0] * scale),
                                  round(img.size[1] * scale)))
    # Slab-resurrection guard: visible pixels OUTSIDE the cleaned
    # silhouette whose colour is chart plot grass (a green fringe
    # under the foundation would show up here).
    arr = np.asarray(img).astype(np.int32)
    grass, _, _ = slab_masks(arr[..., :3])
    resurrect = int((grass & (arr[..., 3] > 25)).sum())
    return img, lost_n, resurrect


# --------------------------------------------------------------------------
# Metrics (identical definitions to the earlier passes)
# --------------------------------------------------------------------------
def pale_rim_count(rgba):
    """Opaque pale rim pixels — the derim_buildings metric."""
    a = rgba[..., 3].astype(np.float64)
    solid = a > 0
    rim = solid & (ndimage.distance_transform_edt(solid) <= 2)
    return int((rim & (rgba[..., :3].mean(axis=2) > 200) & (a >= 250)).sum())


def metrics(path):
    rgba = np.asarray(Image.open(path).convert("RGBA"))
    return halo_score(rgba), pale_rim_count(rgba)


# --------------------------------------------------------------------------
# Drivers — component selection mirrors extract_buildings.extract_chart
# --------------------------------------------------------------------------
def process_mask(rgb, fg, mask, name, out_name, dirt_top_frac=0.0):
    cleaned = remove_slab(rgb, mask, name, dirt_top_frac=dirt_top_frac)
    forbidden = mask & ~cleaned
    if dirt_top_frac > 0.0:
        # The compound's guards live inside remove_slab; pixels outside
        # the detection mask were never part of the sprite either.
        forbidden = forbidden | ~fg
    forbidden = ndimage.binary_dilation(forbidden, iterations=2)
    img, lost_n, resurrect = matte_component(rgb, cleaned, fg, forbidden)
    out_path = os.path.join(OUT_DIR, out_name + ".png")
    img.save(out_path)
    halo, pale = metrics(out_path)
    print("    [%s] saved %s size=%s halo=%.1f pale_rim=%d interior_lost=%d grass_px=%d"
          % (name, out_name + ".png", img.size, halo, pale, lost_n, resurrect))
    return halo, pale


def extract_chart(prefix, filename):
    path = os.path.join(os.path.expanduser("~/workspace/user/files"), filename)
    im = Image.open(path).convert("RGB")
    rgb = np.asarray(im)
    fg = build_alpha(rgb)
    lab, n = ndimage.label(fg)
    comps = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        area = int((lab[sl] == i).sum())
        comps.append({"id": i, "sl": sl, "area": area,
                      "cx": (sl[1].start + sl[1].stop) / 2.0,
                      "cy": (sl[0].start + sl[0].stop) / 2.0})
    comps.sort(key=lambda c: -c["area"])
    buildings = comps[:4]
    buildings.sort(key=lambda c: (c["cy"] > rgb.shape[0] / 2.0, c["cx"]))
    print("[%s] %d components, top-4 areas=%s" % (
        prefix, n, [c["area"] for c in buildings]))
    results = {}
    for idx, c in enumerate(buildings, start=1):
        name = "%s_t%d" % (prefix, idx)
        results[name] = process_mask(rgb, fg, lab == c["id"], name, name)
    return results


def extract_compound():
    im = Image.open(SRC_COMPOUND).convert("RGB")
    rgb = np.asarray(im)
    fg = build_alpha(rgb)
    print("[camp_compound] whole-mask matte")
    return {"camp_compound": process_mask(rgb, fg, fg, "camp_compound",
                                          "camp_compound", dirt_top_frac=0.85)}


def main():
    before = {}
    if os.path.isdir(BACKUP):
        for f in sorted(os.listdir(BACKUP)):
            if f.endswith(".png"):
                before[f[:-4]] = metrics(os.path.join(BACKUP, f))
    after = {}
    for prefix, filename in CHARTS:
        after.update(extract_chart(prefix, filename))
    after.update(extract_compound())
    print("\n==== before (derimmed binary cut) -> after (smooth v4) ====")
    tot_h_b = tot_h_a = tot_p_b = tot_p_a = 0.0
    for name in sorted(after):
        hb, pb = before.get(name, (float("nan"), -1))
        ha, pa = after[name]
        tot_h_b += hb if hb == hb else 0.0
        tot_h_a += ha
        tot_p_b += max(pb, 0)
        tot_p_a += pa
        print("%-18s halo %6.1f -> %6.1f | opaque pale rim %5d -> %5d"
              % (name, hb, ha, pb, pa))
    print("TOTAL              halo %6.1f -> %6.1f | opaque pale rim %5.0f -> %5.0f"
          % (tot_h_b, tot_h_a, tot_p_b, tot_p_a))


if __name__ == "__main__":
    main()
