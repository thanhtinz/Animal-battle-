#!/usr/bin/env python3
"""Extract the SELF-DRAWN assets (Bé-generated charts, 2026-11-08) with
the same pipeline as the accepted families: build_alpha detection ->
slab removal -> smooth matte (recut_buildings_smooth.process_mask).

Sources live in ~/workspace/empire-age/gen/ (media-generated, style-gated
against Tín's lumber-camp chart):
  farm_chart.png   - 4 farm tiers in a row, white bg, label pills below
  castle_chart.png - 4 castle tiers in a row, white bg, label pills below
  wall_sheet.png   - 6 wall pieces in a row: wood straight / wood corner /
                     wood gate / stone straight / stone corner / stone gate
  crop_sheet.png   - 4 growth stages of one field plot (NO slab removal:
                     the plot IS the asset)

Outputs:
  assets/buildings/farm_t1..t4.png, castle_t1..t4.png
  assets/buildings/wallwood.png, wallwood_corner.png, gatewood.png,
                   wallstone.png, wallstone_corner.png, gatestone.png
  assets/fields/field_s1..s4.png

Re-runnable: python3 tools/extract_new_assets.py
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import extract_buildings as eb
import recut_buildings_smooth as rbs
from extract_buildings import build_alpha

eb.orig_slab_masks = eb.slab_masks

GEN = os.path.expanduser("~/workspace/empire-age/gen")
BLDG_DIR = os.path.join(HERE, "..", "assets", "buildings")
FIELD_DIR = os.path.join(HERE, "..", "assets", "fields")


def components(rgb):
    fg = build_alpha(rgb)
    lab, n = ndimage.label(fg)
    comps = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        comps.append({"id": i, "sl": sl,
                      "area": int((lab[sl] == i).sum()),
                      "cx": (sl[1].start + sl[1].stop) / 2.0,
                      "cy": (sl[0].start + sl[0].stop) / 2.0,
                      "w": sl[1].stop - sl[1].start,
                      "h": sl[0].stop - sl[0].start})
    return fg, lab, comps


def is_label_pill(c, img_h):
    """Beige chart label pills: very wide, short, low in the frame."""
    return c["w"] > 2.0 * c["h"] and c["cy"] > 0.62 * img_h


def _wide_grass_slab_masks(a):
    """The generated charts' plots are a lighter yellow-green than
    Tín's charts, so widen the grass test (thatch/wheat stay safe:
    there g < r - 25)."""
    grass, dirt, fringe = eb.orig_slab_masks(a)
    r = a[..., 0].astype(np.int32)
    g = a[..., 1].astype(np.int32)
    b = a[..., 2].astype(np.int32)
    gen_grass = (g >= 95) & ((g - b) >= 45) & (g >= r - 25) & (b <= 145)
    # The plot's dark-green outline stroke: the flood must cross it to
    # reach the plot's front face (building outlines are dark BROWN,
    # r >= g, so they stay impassable).
    dark_edge = (r <= 115) & (g >= 70) & (g <= 165) & ((g - b) >= 25) \
        & (g > r) & (b <= 100)
    return grass | gen_grass | dark_edge, dirt, fringe


def column_saucer_cut(mask, max_run=48, min_gap=3):
    """Drop the plot's outline saucer: after the slab flood eats the
    plot interior, the plot's dark outline ring survives as a flat
    detached run at the bottom of many columns, separated from the
    building by a transparent gap. Per column, delete bottom runs
    that sit below such a gap (bridges at real props are continuous
    runs and survive)."""
    out = mask.copy()
    h, w = mask.shape
    cut = 0
    for x in range(w):
        col = mask[:, x]
        if not col.any():
            continue
        # runs of kept pixels, top to bottom
        runs = []
        y = 0
        while y < h:
            if col[y]:
                y0 = y
                while y < h and col[y]:
                    y += 1
                runs.append([y0, y])
            else:
                y += 1
        while len(runs) >= 2:
            b0, b1 = runs[-1]
            gap = b0 - runs[-2][1]
            if (b1 - b0) <= max_run and gap >= min_gap:
                out[b0:b1, x] = False
                cut += b1 - b0
                runs.pop()
            else:
                break
    if cut:
        print("    saucer cut: %d px" % cut)
    return out


def process_tier(rgb, fg, mask, name):
    """recut_buildings_smooth.process_mask + the saucer cut."""
    cleaned = eb.remove_slab(rgb, mask, name)
    cleaned = column_saucer_cut(cleaned)
    forbidden = ndimage.binary_dilation(mask & ~cleaned, iterations=2)
    img, lost, resurrect = rbs.matte_component(rgb, cleaned, fg,
                                               forbidden)
    out_path = os.path.join(BLDG_DIR, name + ".png")
    img.save(out_path)
    halo, pale = rbs.metrics(out_path)
    print("    [%s] saved size=%s halo=%.1f pale_rim=%d interior_lost=%d "
          "grass_px=%d" % (name, img.size, halo, pale, lost, resurrect))


def extract_tier_chart(filename, prefix):
    im = Image.open(os.path.join(GEN, filename)).convert("RGB")
    rgb = np.asarray(im)
    fg, lab, comps = components(rgb)
    cand = [c for c in comps if not is_label_pill(c, rgb.shape[0])]
    cand.sort(key=lambda c: -c["area"])
    tiers = cand[:4]
    tiers.sort(key=lambda c: c["cx"])
    print("[%s] comps=%d areas=%s" % (prefix, len(comps),
                                      [c["area"] for c in cand[:6]]))
    rbs.OUT_DIR = BLDG_DIR
    eb.slab_masks = _wide_grass_slab_masks
    try:
        for idx, c in enumerate(tiers, start=1):
            name = "%s_t%d" % (prefix, idx)
            process_tier(rgb, fg, lab == c["id"], name)
    finally:
        eb.slab_masks = eb.orig_slab_masks


def extract_wall_sheet():
    im = Image.open(os.path.join(GEN, "wall_sheet.png")).convert("RGB")
    rgb = np.asarray(im)
    fg, lab, comps = components(rgb)
    comps.sort(key=lambda c: -c["area"])
    pieces = comps[:6]
    pieces.sort(key=lambda c: c["cx"])
    names = ["wallwood", "wallwood_corner", "gatewood",
             "wallstone", "wallstone_corner", "gatestone"]
    print("[wall] comps=%d areas=%s" % (len(comps),
                                        [c["area"] for c in pieces]))
    # The grass strip is grass-coloured only; never let the dirt test eat
    # the wooden gate doors (their brown passes the dirt colour test).
    orig = eb.slab_masks
    eb.slab_masks = lambda a: (orig(a)[0], np.zeros(a.shape[:2], bool),
                               orig(a)[2])
    rbs.OUT_DIR = BLDG_DIR
    try:
        for c, name in zip(pieces, names):
            rbs.process_mask(rgb, fg, lab == c["id"], name, name)
    finally:
        eb.slab_masks = orig


def extract_crops():
    im = Image.open(os.path.join(GEN, "crop_sheet.png")).convert("RGB")
    rgb = np.asarray(im)
    fg, lab, comps = components(rgb)
    comps.sort(key=lambda c: -c["area"])
    stages = comps[:4]
    stages.sort(key=lambda c: c["cx"])
    print("[crops] comps=%d areas=%s" % (len(comps),
                                         [c["area"] for c in stages]))
    os.makedirs(FIELD_DIR, exist_ok=True)
    for idx, c in enumerate(stages, start=1):
        mask = lab == c["id"]
        forbidden = ndimage.binary_dilation(~fg, iterations=2)
        img, lost, resurrect = rbs.matte_component(rgb, mask, fg, forbidden)
        out = os.path.join(FIELD_DIR, "field_s%d.png" % idx)
        img.save(out)
        print("    [field_s%d] saved size=%s interior_lost=%d"
              % (idx, img.size, lost))


def main():
    for src, dst in [("media-generation-empire-farm-chart-0-b05acc47-c0b9-4db1-bb19-1df209e5a028.webp", "farm_chart.png"),
                     ("media-generation-empire-castle-chart-0-98320f25-c800-4922-9f8e-4a57f357cd7f.webp", "castle_chart.png"),
                     ("media-generation-empire-wall-sheet-0-ac8320ab-e0b2-49fd-a632-c2cd89d13cbc.webp", "wall_sheet.png"),
                     ("media-generation-empire-crop-sheet-0-27184f05-1c50-4d3b-b402-1b4d59b5f04a.webp", "crop_sheet.png")]:
        p = os.path.join(GEN, src)
        q = os.path.join(GEN, dst)
        if os.path.exists(p) and not os.path.exists(q):
            Image.open(p).convert("RGB").save(q)
            print("converted", dst)
    extract_tier_chart("farm_chart.png", "farm")
    extract_tier_chart("castle_chart.png", "castle")
    extract_wall_sheet()
    extract_crops()


if __name__ == "__main__":
    main()
