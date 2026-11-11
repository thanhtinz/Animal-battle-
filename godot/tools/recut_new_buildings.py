#!/usr/bin/env python3
"""Cut the 4 NEW building families (Lumber Camp, Storage, Market, Dock —
4 tiers each, Tín's charts 2026-11-08).

SECOND cut (v2 of these families). The first cut shipped with four
defects Tín rejected at 4x zoom ("Cat xau qua"):
  1. BLACK-BG HALO — Storage/Market/Dock (black charts) carried a thick
     dark blob rim: the detection prior includes a 1-2 px shell of
     JPEG-ringing pixels around the silhouette, and the old ratio
     matte handed that shell partial coverage in its own contaminated
     dark colour.
  2. PLOT-OUTLINE DEBRIS — the grass plot's dark outline survived the
     ground flood as detached dashed strokes / a full curved sweep
     floating around and below the buildings, plus floating stone
     slabs at the bases.
  3. EATEN BASES — the colour flood bit unevenly into the base row
     (a post footing left as a thin hanging sliver, scalloped cut
     line under the crates).
  4. LUMBER T1 RIDGE — the roof ridge block floated, severed from the
     roof: its thin neck is all "edge" pixels, and the ratio matte
     gave the neck ~0.3 alpha, which the premultiplied downscale
     then thinned to invisibility.

Pipeline now (per building component):
  * Detection: background-candidate flood from the chart borders
    (corner-sampled bg colour — white for Lumber, black for the
    other three) -> the 4 tall components are the 4 tiers.
  * Ground removal: the colour flood + per-column ground run of the
    first cut (grass plot / Dock water puddle / label pill).
  * REPAIR: pixels the flood removed that are NOT ground-coloured
    and sit at/above the building's structural base line (a smoothed
    per-column bottom of the kept main component) are restored —
    the flood's overshoot into footings and base trim is undone.
  * COMPONENT DISCIPLINE: the final silhouette is the main connected
    mass ONLY. Every other source component (plot-outline strokes,
    front-face bands, floating slabs, plot specks) is dropped and
    counted in the printed audit. No legit prop is detached at
    source resolution in these charts — crates, sacks, barrels,
    the hanging crane crates and the Dock Lv4 boat are all connected
    to the main mass (verified per chart).
  * BASE LINE (grass families): the main mass is trimmed to a clean
    per-column base line — a wide-median smoothing of its own bottom
    contour plus a small tolerance — so dangling slivers below the
    structural bottom are cut and the building sits evenly. The
    Dock is exempt: its structural bottom is the pier posts.
  * MATTE: a signed-distance matte, not a colour ratio. Alpha =
    smoothstep over (signed distance - CHOKE): coverage reaches 1
    only CHOKE+FEATHER/2 px inside the strict silhouette and is 0
    at/outside it, so the contaminated shell (defect 1) can never
    contribute a pixel. Thin structures survive via a BRIDGE BOOST:
    silhouette pixels with foreground on both sides within 3 px
    (the Lumber ridge neck, crane ropes, lantern chains) are firmed
    to high alpha along their spine. Edge-band RGB is unblended from
    the bg colour and leaned hard toward the nearest deep-interior
    colour; the transparent margin carries interior colour too, so
    filtered sampling never sees chart-edge pixels.
  * Premultiplied downscale to <=512 px, then a FINAL component
    audit on the shipped pixels: any component that is not the main
    mass and not on the explicit per-sprite whitelist (props a hair
    -thin connector lost in the downscale) is dropped, whatever its
    size; the audit prints what was removed.

Outputs: ../assets/buildings/{lumbercamp,storage,market,dock}_t1..t4.png
The matching .import files carry mipmaps/generate=true (editor
import pass). Re-runnable: python3 tools/recut_new_buildings.py
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from extract_buildings import MAX_SIZE, OUT_DIR
from recut_smooth import halo_score, resize_premul, smoothstep

USER = os.path.expanduser("~/workspace/user/files")
NEW_CHARTS = [
    ("lumbercamp",
     "25962E62-865E-45FD-93D8-E6F0719038B5-photo-D98B7100-7BAC-4F91-BCB4-CF3A4F4A40F2.jpg",
     "grass"),
    ("storage",
     "287C58D1-42C8-48DA-A272-0718BC6E0283-photo-F44FCFE1-A760-4F3D-A72C-3D009129636A.jpg",
     "grass"),
    ("market",
     "11A0B714-B9AE-461E-898D-9846A921B1CA-photo-E8EA6913-B077-406E-8892-9A5784BDB617.jpg",
     "grass"),
    ("dock",
     "10B22B1B-D6F3-4C12-B1B1-9E9177D16931-photo-73E4C941-EFE9-404B-985C-C7530AEED13A.jpg",
     "water"),
]

PAD = 6        # source px of margin kept around each component
DIST_TH = 30   # bg-candidate distance (same calibration as the house method)
RIM_DIST = 60  # near-bg rim band stripped where it touches the background

CHOKE = 1.3    # px the matte edge sits inside the strict silhouette
FEATHER = 2.2  # px over which coverage ramps 0 -> 1 inside the edge

# Explicit per-sprite whitelist for the FINAL (post-downscale) audit:
# a severed prop may be kept only if it matches one of these rules
# (centre position as a fraction of the sprite, minimum area in
# output px). Everything else that is not the main mass is dropped.
# Filled from visual inspection of the first v2 run — see the audit
# output. Keys are sprite names; each rule: (min_area, cx_lo, cx_hi,
# cy_lo, cy_hi, description).
OUT_WHITELIST = {
    # The Lv4 boat floats right of the pier; if its hairline contact
    # with the pier is lost in the downscale it must still survive.
    "dock_t4": [(400, 0.62, 1.00, 0.55, 1.00, "Lv4 boat")],
    # Hanging crane crates: kept if the rope thins out in downscale.
    "storage_t3": [(250, 0.60, 1.00, 0.35, 0.80, "hanging crane crate")],
    "dock_t3": [(250, 0.60, 1.00, 0.35, 0.80, "hanging crane crate")],
}


# --------------------------------------------------------------------------
# Detection against an arbitrary flat background colour
# --------------------------------------------------------------------------
def sample_bg(rgb):
    """Background colour = mean of the four chart corners."""
    corners = np.array([rgb[2, 2], rgb[2, -3], rgb[-3, 2], rgb[-3, -3]],
                       dtype=np.float64)
    return corners.mean(axis=0)


def build_alpha_bg(rgb, bg):
    """Foreground mask for a flat-bg chart (build_alpha generalised)."""
    dist = np.sqrt(((rgb.astype(np.float64) - bg) ** 2).sum(axis=2))
    bgcand = dist <= DIST_TH
    lab, _ = ndimage.label(bgcand)
    border = set(np.unique(np.concatenate(
        [lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))) - {0}
    fg = ~np.isin(lab, list(border))
    bgish = dist < RIM_DIST
    near_bg = ndimage.binary_dilation(~fg)
    fg = fg & ~(bgish & near_bg)
    return fg


# --------------------------------------------------------------------------
# Ground (plot / puddle / pill) removal — the first cut's flood pattern
# --------------------------------------------------------------------------
def ground_passable(rgb, kind):
    """Colours the bottom flood may travel through, per ground kind."""
    r = rgb[..., 0].astype(np.int32)
    g = rgb[..., 1].astype(np.int32)
    b = rgb[..., 2].astype(np.int32)
    # Sandy beige: the Market Lv4 front path, the Dock label pills.
    sand = ((r >= 190) & (g >= 160) & (b <= 110)
            & ((r - b) >= 50) & ((r - b) <= 110)
            & ((g - b) >= 25) & ((g - b) <= 70))
    if kind == "grass":
        # Lime plot: yellow-green (r >= 0.62 g separates it from the
        # deeper green of pine foliage / side bushes).
        grass = ((b <= 90) & ((g - b) >= 60) & (g >= r - 20)
                 & (r <= 245) & (g >= 85) & (5 * r >= 3 * g))
        # The plot's shadowed front rim (dark olive stroke, always in
        # shadow so g stays low; vivid bush green has g > 120).
        rim = ((b <= 45) & (g >= 25) & (g <= 120) & ((g - b) >= 18)
               & (r <= 110) & ((r - b) >= 10))
        # Pale rim light where the plot edge catches light.
        fringe = (r > 175) & (g > 185) & (b > 150) & (g >= r) & (r >= b)
        return grass | rim | sand | fringe
    # Dock: blue puddle + its deep navy rim + the beige label pill.
    water = (b >= 90) & ((b - r) >= 50) & ((b - g) >= 15)
    wrim = ((b >= 40) & (b <= 110) & ((b - r) >= 25)
            & ((b - g) >= 10) & (g <= 90))
    return water | wrim | sand


def column_ground(sub_rgb, sub, kind):
    """Per-column ground run: from the component's lowest pixel in the
    column upward, ground colours are eaten, crossing at most 2 thin
    non-ground gaps (object outline strokes <= 6 px, plus an initial
    drop-shadow gap below the first ground pixel). This eats plot
    segments that 2-D labelling separates from the main ground mass
    while stopping dead at long non-ground runs — a sack's outline +
    body, a boat hull, a bush — so objects standing ON the ground
    survive."""
    pas = ground_passable(sub_rgb, kind) & sub
    init_gap = 18 if kind == "water" else 10
    h, w = sub.shape
    out = np.zeros_like(sub)
    for x in range(w):
        col = sub[:, x]
        ys = np.where(col)[0]
        if len(ys) == 0:
            continue
        y = int(ys.max())
        y_min = int(ys.min())
        phase = 0  # 0 = before the first ground pixel (drop shadow)
        gaps = 0
        run_gap = 0
        while y >= y_min and col[y]:
            if pas[y, x]:
                out[y, x] = True
                phase = 1
                run_gap = 0
            else:
                run_gap += 1
                if phase == 0:
                    if run_gap > init_gap:
                        break
                else:
                    if run_gap == 1:
                        gaps += 1
                        if gaps > 2:
                            break
                    if run_gap > 6:
                        break
            y -= 1
    return out


def _drop_debris(mask):
    """Drop dust-size detached components (the extract_buildings rule,
    re-implemented locally so this tool no longer depends on the old
    module's internals beyond constants). Zones are measured against
    the MAIN component's bbox."""
    lab, n = ndimage.label(mask)
    if n <= 1:
        return mask
    areas = ndimage.sum(mask, lab, index=np.arange(1, n + 1))
    slices = ndimage.find_objects(lab)
    main_id = int(np.argmax(areas)) + 1
    main_area = float(areas[main_id - 1])
    msl = slices[main_id - 1]
    mh = msl[0].stop - msl[0].start
    my1 = msl[0].stop
    h, w = mask.shape
    keep = lab == main_id
    dropped = 0
    for i, sl in enumerate(slices, start=1):
        if i == main_id or sl is None:
            continue
        area = float(areas[i - 1])
        cw = sl[1].stop - sl[1].start
        dust = area < 64
        side_face = (sl[1].start <= 2 or sl[1].stop >= w - 2) and cw <= 8
        plot_speck = (area < 0.004 * main_area
                      and sl[0].start > my1 - 0.45 * mh)
        front_face = (area <= 0.01 * main_area
                      and sl[0].start >= my1 - 0.25 * mh
                      and sl[0].stop >= my1 - 0.12 * mh
                      and (sl[0].stop - sl[0].start) <= 0.10 * mh)
        if dust or side_face or plot_speck or front_face:
            dropped += 1
            continue
        keep |= lab == i
    if dropped:
        print("    debris dropped: %d small component(s)" % dropped)
    return keep


def ground_flood(rgb, mask, kind):
    """Colour flood + per-column run from the component's bottom rows.
    Returns the kept mask at full chart size (before discipline)."""
    ys, xs = np.where(mask)
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    sub_rgb = rgb[box[1]:box[3], box[0]:box[2]]
    sub = mask[box[1]:box[3], box[0]:box[2]]
    passable = ground_passable(sub_rgb, kind) & sub
    lab, nlab = ndimage.label(passable)
    band = max(6, int(0.04 * sub.shape[0]))
    seeds = set(np.unique(lab[-band:, :])) - {0}
    if kind == "water":
        # The Dock puddle's main label ends at ~0.80 of the component
        # height and the pill's beige is fragmented by its dark text
        # into small labels — seed every sizeable ground label whose
        # bottom sits in the component's lower quarter.
        slices = ndimage.find_objects(lab)
        areas = ndimage.sum(passable, lab, index=np.arange(1, nlab + 1))
        for i, sl in enumerate(slices, start=1):
            if sl is not None and areas[i - 1] >= 40 \
                    and sl[0].stop >= 0.75 * sub.shape[0]:
                seeds.add(i)
    ground = np.isin(lab, list(seeds)) if seeds else np.zeros_like(sub)
    ground |= column_ground(sub_rgb, sub, kind)
    removed = int((ground & sub).sum())
    kept = sub & ~ground
    full = np.zeros(mask.shape, dtype=bool)
    full[box[1]:box[3], box[0]:box[2]] = kept
    # Restore interior bites: a removed region fully enclosed by the
    # kept mask (a flood leak into a sack's fold) is object interior.
    ys, xs = np.where(full)
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    trimmed = ndimage.binary_fill_holes(full[y0:y1, x0:x1])
    out = np.zeros(mask.shape, dtype=bool)
    out[y0:y1, x0:x1] = trimmed
    print("    ground flood removed %d px (%.1f%% of component)"
          % (removed, 100.0 * removed / max(1, int(sub.sum()))))
    return out


# --------------------------------------------------------------------------
# Base line helpers
# --------------------------------------------------------------------------
def column_bottoms(mask):
    """Per-column bottom row (exclusive) of the mask, or -1."""
    h, w = mask.shape
    idx = np.where(mask.any(axis=0))[0]
    bottoms = np.full(w, -1, dtype=np.int64)
    if len(idx):
        rev = mask[::-1, :]
        first = np.argmax(rev, axis=0)  # distance from bottom edge
        bottoms = np.where(mask.any(axis=0), h - first, -1)
    return bottoms


def smooth_base_line(mask, win_px):
    """A clean structural base line: the mask's per-column bottom,
    gap-filled by interpolation and smoothed with a wide median so
    thin dips (a hanging sliver, a dripped stroke) cannot pull the
    line down, while wide structures (front crates, the stump)
    still shape it. Returns an array of bottom rows per column.
    win_px is sized by the caller from the COMPONENT's width."""
    bottoms = column_bottoms(mask)
    xs = np.where(bottoms >= 0)[0]
    if len(xs) == 0:
        return bottoms
    filled = np.interp(np.arange(mask.shape[1]), xs, bottoms[xs])
    win = max(7, int(win_px) | 1)
    line = ndimage.median_filter(filled, size=win, mode="nearest")
    return line


def _bbox(mask):
    ys, xs = np.where(mask)
    return (int(ys.min()), int(ys.max()) + 1, int(xs.min()),
            int(xs.max()) + 1)


# --------------------------------------------------------------------------
# Repair + component discipline + base-line trim
# --------------------------------------------------------------------------
def clean_silhouette(rgb, orig, kept, name, kind):
    """orig: detection component. kept: after the ground flood.
    Returns the final strict silhouette (main mass only, repaired,
    base-trimmed for the grass families) and prints the audit."""
    lab, n = ndimage.label(kept)
    areas = ndimage.sum(kept, lab, index=np.arange(1, n + 1))
    main_id = int(np.argmax(areas)) + 1
    main = lab == main_id
    by0, by1, bx0, bx1 = _bbox(main)
    comp_w = bx1 - bx0
    comp_h = by1 - by0

    # --- repair: restore non-ground pixels the flood ate at/above
    # the structural base line of the kept main mass.
    line = smooth_base_line(main, max(9, int(0.15 * comp_w)))
    yy = np.arange(rgb.shape[0])[:, None]
    above_line = yy <= (line[None, :] + 2)
    restorable = orig & ~kept & ~ground_passable(rgb, kind) & above_line
    restored_n = int(restorable.sum())
    pool = main | restorable
    lab2, _ = ndimage.label(pool)
    # The component of the pool that contains the old main mass.
    ids = np.unique(lab2[main])
    ids = ids[ids != 0]
    final = np.isin(lab2, list(ids)) if len(ids) else main

    # --- discipline audit: everything in kept/restored that is not
    # the final main mass is debris (plot strokes, bands, slabs).
    dropped = (kept | restorable) & ~final
    audit = []
    if dropped.any():
        lab3, n3 = ndimage.label(dropped)
        a3 = ndimage.sum(dropped, lab3, index=np.arange(1, n3 + 1))
        audit = sorted((int(a) for a in a3 if a > 20), reverse=True)
    print("    [%s] repair restored %d px; discipline dropped %d "
          "component(s) >20px: %s"
          % (name, restored_n, len(audit), audit))

    # --- base-line trim (grass families): cut dangling slivers
    # below the clean structural base line.
    if kind == "grass":
        line2 = smooth_base_line(final, max(9, int(0.11 * comp_w)))
        tol = max(2.0, 0.012 * comp_h)
        below = yy > (line2[None, :] + tol)
        trimmed = final & ~below
        cut_n = int((final & below).sum())
        lab4, _ = ndimage.label(trimmed)
        a4 = ndimage.sum(trimmed, lab4, index=np.arange(1, lab4.max() + 1)) \
            if lab4.max() else np.array([0])
        final = lab4 == (int(np.argmax(a4)) + 1)
        print("    [%s] base-line trim cut %d px below the line"
              % (name, cut_n))
    # Plot-outline hooks that touch the silhouette (both families).
    final = prune_stray_runs(final)
    return final


def _row_runs(row):
    lab, n = ndimage.label(row)
    runs = []
    for i in range(1, n + 1):
        xs = np.where(lab == i)[0]
        runs.append((int(xs.min()), int(xs.max())))
    return runs


def _prune_pass(m):
    """One directional pass: drop thin runs that are separated from
    the row's widest run by a gap and lack STANDING persistence:
    a matching run at nearly the same offset 6-12 rows away on BOTH
    sides. A pole/post/rope stands still and passes; the plot rim
    is an arc — it drifts ~1 px per row, so its far rows no longer
    overlap the run's own interval and it is pruned."""
    h, w = m.shape
    rows_runs = [_row_runs(m[y]) for y in range(h)]

    def far_support(y, a, b, lo, hi):
        cnt = 0
        for yy in range(max(0, y + lo), min(h, y + hi + 1)):
            if any(not (rb < a - 2 or ra > b + 2)
                   for (ra, rb) in rows_runs[yy]):
                cnt += 1
        return cnt

    kill = np.zeros_like(m)
    for y in range(h):
        runs = rows_runs[y]
        if len(runs) <= 1:
            continue
        widest = max(runs, key=lambda r: r[1] - r[0])
        for (a, b) in runs:
            if (a, b) == widest or b - a + 1 > 6:
                continue
            gap = max(a - widest[1], widest[0] - b) - 1
            if gap < 3:
                continue
            if far_support(y, a, b, -12, -6) >= 3 and \
                    far_support(y, a, b, 6, 12) >= 3:
                continue  # a standing thin structure — keep
            kill[y, a:b + 1] = True
    return m & ~kill, int(kill.sum())


def prune_stray_runs(mask):
    """Remove plot-outline HOOKS that touch the silhouette: thin
    detached-looking runs hugging the posts at the plot-rim height.
    They are separated from the main run in their row/column, are
    <=6 px wide and do not persist — unlike ropes, poles, fence
    posts and railings, which persist across many rows/columns at
    the same offset and are kept. Runs in both directions, then the
    main component is re-taken (a hook may have been a prop's only
    bridge — nothing legit hangs by a <=6 px separated thread in
    these charts)."""
    out, k1 = _prune_pass(mask)
    out, k2 = _prune_pass(out.T)
    out = out.T
    lab, n = ndimage.label(out)
    if n > 1:
        areas = ndimage.sum(out, lab, index=np.arange(1, n + 1))
        out = lab == (int(np.argmax(areas)) + 1)
    print("    stray-run prune removed %d + %d px" % (k1, k2))
    return out


# --------------------------------------------------------------------------
# Signed-distance matte with choke + bridge boost
# --------------------------------------------------------------------------
def _shift(mask, dy, dx):
    out = np.zeros_like(mask)
    ys = slice(max(0, dy), mask.shape[0] + min(0, dy))
    xs = slice(max(0, dx), mask.shape[1] + min(0, dx))
    yt = slice(max(0, -dy), mask.shape[0] + min(0, -dy))
    xt = slice(max(0, -dx), mask.shape[1] + min(0, -dx))
    out[yt, xt] = mask[ys, xs]
    return out


def matte_component(rgb, prior, bg):
    """Smooth-matte one cleaned component at full chart size.

    rgb: uint8 chart RGB. prior: bool strict silhouette. bg: sampled
    background colour. Returns a uint8 RGBA PIL image trimmed to the
    alpha bbox (not yet downscaled)."""
    ys, xs = np.where(prior)
    H, W = prior.shape
    x0, x1 = max(0, int(xs.min()) - PAD), min(W, int(xs.max()) + 1 + PAD)
    y0, y1 = max(0, int(ys.min()) - PAD), min(H, int(ys.max()) + 1 + PAD)
    crop = rgb[y0:y1, x0:x1].astype(np.float64)
    pri = prior[y0:y1, x0:x1]
    bgv = np.asarray(bg, dtype=np.float64)

    dist_in = ndimage.distance_transform_edt(pri)
    dist_out = ndimage.distance_transform_edt(~pri)
    s = dist_in - dist_out
    # Choked, re-feathered coverage: 0 at the strict edge, 1 only
    # CHOKE + FEATHER/2 px inside it. Nothing outside the silhouette
    # contributes — the JPEG shell is excluded by construction.
    alpha = smoothstep(CHOKE - FEATHER / 2.0, CHOKE + FEATHER / 2.0, s)
    # Bridge boost: thin connectors (ridge neck, ropes, chains) have
    # foreground on both sides within 3 px; firm their spine so the
    # choke + downscale cannot sever them.
    both = (_shift(pri, 0, 3) & _shift(pri, 0, -3)) | \
           (_shift(pri, 3, 0) & _shift(pri, -3, 0))
    bridge = ndimage.binary_dilation(both, iterations=1) & pri
    alpha = np.where(bridge & (dist_in >= 0.6), np.maximum(alpha, 0.9), alpha)
    alpha = np.clip(alpha, 0.0, 1.0)

    # Guard: deep-interior paint that lost alpha (must be 0).
    lost_n = int((pri & (dist_in >= 4) & (alpha < 0.5)).sum())

    # RGB: unblend the edge band from the bg colour, lean it toward
    # the nearest deep-interior colour; the fully transparent margin
    # carries interior colour for filtered sampling.
    interior = dist_in >= 3
    _, inds = ndimage.distance_transform_edt(~interior, return_indices=True)
    near_rgb = crop[inds[0], inds[1]]
    F = crop.copy()
    semi = (alpha > 0.02) & (alpha < 0.98)
    av = alpha[semi]
    F[semi] = np.clip((crop[semi] - (1.0 - av)[:, None] * bgv) / av[:, None],
                      0, 255)
    lean = (alpha > 0.0) & (alpha < 0.9)
    wgt = np.where(lean, 0.45 * (1.0 - alpha), 0.0)
    F = F * (1.0 - wgt[..., None]) + near_rgb * wgt[..., None]
    margin = (alpha <= 0.0) & (dist_out <= 3)
    F[margin] = near_rgb[margin]

    out = np.dstack([F, alpha * 255.0])
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    bbox = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if bbox:
        img = img.crop(bbox)
    return img, lost_n


# --------------------------------------------------------------------------
# Final (output-space) component discipline
# --------------------------------------------------------------------------
def output_discipline(img, name):
    """Drop every non-main component of the shipped pixels that is
    not whitelisted for this sprite; print the audit."""
    arr = np.asarray(img).copy()
    solid = arr[..., 3] > 25
    lab, n = ndimage.label(solid)
    if n <= 1:
        print("    [%s] output audit: single component" % name)
        return img
    areas = ndimage.sum(solid, lab, index=np.arange(1, n + 1))
    slices = ndimage.find_objects(lab)
    main_id = int(np.argmax(areas)) + 1
    H, W = solid.shape
    rules = OUT_WHITELIST.get(name, [])
    removed = []
    kept_extra = []
    drop_mask = np.zeros_like(solid)
    for i, sl in enumerate(slices, start=1):
        if i == main_id or sl is None:
            continue
        area = int(areas[i - 1])
        cx = (sl[1].start + sl[1].stop) / 2.0 / W
        cy = (sl[0].start + sl[0].stop) / 2.0 / H
        hit = None
        for (min_area, xlo, xhi, ylo, yhi, desc) in rules:
            if area >= min_area and xlo <= cx <= xhi and ylo <= cy <= yhi:
                hit = desc
                break
        if hit:
            kept_extra.append((area, hit))
        else:
            drop_mask |= lab == i
            removed.append(area)
    if removed:
        arr[drop_mask] = 0
        img = Image.fromarray(arr, "RGBA")
        bbox = img.getchannel("A").point(
            lambda v: 255 if v > 8 else 0).getbbox()
        if bbox:
            img = img.crop(bbox)
    big = [a for a in removed if a > 20]
    print("    [%s] output audit: removed %d component(s) %s "
          "(>20px: %s); whitelisted kept: %s"
          % (name, len(removed), sorted(removed, reverse=True), big,
             kept_extra))
    return img


def ground_guard(img, kind):
    """Visible pixels in the sprite's BOTTOM 15% of rows still
    coloured like the chart ground — ground remnants would sit
    there; the same colour tests also match light wood trim higher
    up, so only the base band is a meaningful guard."""
    arr = np.asarray(img).astype(np.int32)
    if arr.shape[0] == 0:
        return 0
    band = arr[int(arr.shape[0] * 0.85):]
    pas = ground_passable(band[..., :3], kind)
    return int((pas & (band[..., 3] > 25)).sum())


# --------------------------------------------------------------------------
# Drivers
# --------------------------------------------------------------------------
def process_chart(prefix, filename, kind):
    path = os.path.join(USER, filename)
    im = Image.open(path).convert("RGB")
    rgb = np.asarray(im)
    bg = sample_bg(rgb)
    fg = build_alpha_bg(rgb, bg)
    lab, n = ndimage.label(fg)
    comps = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        area = int((lab[sl] == i).sum())
        height = sl[0].stop - sl[0].start
        comps.append({"id": i, "sl": sl, "area": area, "h": height,
                      "cx": (sl[1].start + sl[1].stop) / 2.0})
    # Buildings are the tall components (label pills are ~50 px high);
    # take the 4 largest of those, ordered left -> right.
    tall = [c for c in comps if c["h"] >= 150]
    tall.sort(key=lambda c: -c["area"])
    buildings = tall[:4]
    buildings.sort(key=lambda c: c["cx"])
    print("[%s] bg=%s components=%d tall=%d areas=%s"
          % (prefix, np.round(bg, 1), n, len(tall),
             [c["area"] for c in buildings]))
    assert len(buildings) == 4, "expected 4 buildings in %s" % filename
    for idx, c in enumerate(buildings, start=1):
        name = "%s_t%d" % (prefix, idx)
        mask = lab == c["id"]
        kept = ground_flood(rgb, mask, kind)
        kept = _drop_debris(kept)
        final = clean_silhouette(rgb, mask, kept, name, kind)
        img, lost_n = matte_component(rgb, final, bg)
        if max(img.size) > MAX_SIZE:
            scale = MAX_SIZE / float(max(img.size))
            img = resize_premul(img, (round(img.size[0] * scale),
                                      round(img.size[1] * scale)))
        img = output_discipline(img, name)
        out_path = os.path.join(OUT_DIR, name + ".png")
        img.save(out_path)
        halo = halo_score(np.asarray(img))
        guard = ground_guard(img, kind)
        print("    [%s] saved size=%s halo=%.1f ground_px=%d interior_lost=%d"
              % (name, img.size, halo, guard, lost_n))


def main():
    for prefix, filename, kind in NEW_CHARTS:
        process_chart(prefix, filename, kind)


if __name__ == "__main__":
    main()
