#!/usr/bin/env python3
"""Extract building sprites into game-ready PNGs with transparency.

Sources (originals in ~/workspace/user/files/): each building family has
an OFFICIAL 4-tier chart on a WHITE background, 2x2 layout:
T1 top-left, T2 top-right, T3 bottom-left, T4 bottom-right (max).
Every building sits on its own grass patch; the text plaques and the
arrows between tiers are chart furniture, NOT cut.

  barracks    : 0CBE8D64...jpg ("Trai linh" Cap 1..4)
  towncenter  : CDAB6673...jpg (Town Center Cap 1..4, red-roof castle)
  house       : FB82ABFD...jpg ("Nha dan" Cap 1..4, thatch -> manor)
  miningcamp  : F831D77A...jpg ("Mo da" Cap 1..4, mine entrance + cart)
  tower       : CCB443AE...jpg ("Thap canh" Cap 1..4, watch tower)
  blacksmith  : D276A2E8...jpg ("Lo ren" Cap 1..4, forge + anvil)
  camp compound: B55AD4F7...jpg — pixel-art military camp compound
             (palisade, watchtower, tents, dummies). Kept as a SPARE
             asset (camp_compound.png); not wired into the game.

Outputs (in ../assets/buildings/):
  <family>_t1.png .. <family>_t4.png  (RGBA, trimmed, longest side <= 512)
  camp_compound.png                   (RGBA, trimmed, longest side <= 512)

  The game draws the tier matching the current age (age I -> t1) at
  1.5x the building footprint, bottom-anchored (see scripts/building.gd).

Method: same white-background removal as tools/extract_sprites2.py —
pixels close to white are background candidates; only the connected
components touching the image border count as background (so cream tent
fabric / light stone inside a building survives), plus a rim cleanup
that strips near-white JPEG halo pixels hugging the background. For the
tier charts the 4 buildings are the 4 largest foreground components,
ordered by position (top row first, left to right).

Ground-slab removal (added after Tin's review 2026-11-08): every chart
building stands on a baked-in square grass plot with a dirt path — the
game has its own terrain, so the slab is cut away and the building sits
directly on the map. The slab is the flat grass-green / sandy-dirt area
connected to the sprite's bottom edge; a flood fill from the bottom
rows through slab-coloured pixels (grass, dirt, and the pale slab rim)
eats the plot and the path up to the building's own base (stone
foundation / wooden base / mine rocks), which is not slab-coloured and
stops the flood. Small detached debris left in the slab zone (pebbles,
flower specks that sat on the plot) is dropped; real props (barrels,
crates, anvils, target dummies) are far bigger and survive. The
compound's courtyard dirt is interior ground, so its dirt flood is
limited to the apron in front of the gate.
Re-runnable: python3 tools/extract_buildings.py
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "assets", "buildings")
USER = os.path.expanduser("~/workspace/user/files")

CHARTS = [
    ("barracks",
     "0CBE8D64-1616-4F68-9C66-C9FBA5504D9F-photo-DBC77362-1BC3-4CF9-855D-E6D4A7FBAFF3.jpg"),
    ("towncenter",
     "CDAB6673-2ED2-4341-A7FD-BCA0F7322660-photo-9CECA17B-3419-4311-A7FE-8A0D71C95ABE.jpg"),
    ("house",
     "FB82ABFD-C470-450B-8255-F5F374FFE9A9-photo-3099504E-96EF-4DE4-AA26-0F193B938872.jpg"),
    ("miningcamp",
     "F831D77A-D90A-4AFE-9532-216FC1365880-photo-22FCEB02-639C-477C-8355-B8AE038BF7D6.jpg"),
    ("tower",
     "CCB443AE-C05E-4A43-854F-8E9FC25D4FD9-photo-8A7D1CCB-F51D-4425-9B92-A4C4463D2527.jpg"),
    ("blacksmith",
     "D276A2E8-19DC-46E5-833E-2FB7F95AC64A-photo-EA030574-7293-4413-B556-05458414395C.jpg"),
]
SRC_COMPOUND = os.path.join(
    USER,
    "B55AD4F7-1C3D-4112-A72C-9BDBE7684B4E-photo-1007182C-F20B-473C-A9DA-05F63F720C50.jpg",
)

DIST_TH = 30   # distance from pure white that counts as background candidate
RIM_DIST = 60  # near-white band removed where it touches the background
MAX_SIZE = 512  # longest output side (in-game display is ~144 px at 3x3 tiles)


def build_alpha(rgb):
    """Boolean foreground mask for a white-background image (house method)."""
    dist = np.sqrt(((rgb.astype(np.int32) - 255) ** 2).sum(axis=2))
    bgcand = dist <= DIST_TH
    lab, _ = ndimage.label(bgcand)
    border = set(np.unique(np.concatenate(
        [lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))) - {0}
    bgmask = np.isin(lab, list(border))
    fg = ~bgmask
    bgish = dist < RIM_DIST
    near_bg = ndimage.binary_dilation(~fg)
    fg = fg & ~(bgish & near_bg)
    return fg


def slab_masks(rgb):
    """Colour tests for the chart ground slab (calibrated on the charts).

    grass: the plot's lime green — strong green channel, almost no blue.
    dirt:  the sandy path/apron — warm tan, clearly red-dominant; the
           R-G cap keeps forge flames (strong orange) out.
    fringe: the slab's pale rim light where the plot edge catches light.
    """
    r = rgb[..., 0].astype(np.int32)
    g = rgb[..., 1].astype(np.int32)
    b = rgb[..., 2].astype(np.int32)
    grass = (b <= 80) & ((g - b) >= 70) & (g >= r - 15) & (r <= 215) & (g >= 90)
    dirt = ((r >= 140) & (g >= 85) & (b <= 115)
            & ((r - g) >= 30) & ((r - g) <= 95) & ((r - b) >= 70))
    fringe = (r > 175) & (g > 185) & (b > 150) & (g >= r) & (r >= b)
    return grass, dirt, fringe


def _drop_debris(mask):
    """Drop detached remnants of the ground slab (never real props).

    The flood cannot enter slab parts enclosed by dark outline strokes,
    so after it finishes these slab fragments remain as islands:
    - dust specks anywhere (sub-visible at game scale),
    - the plot's side faces: thin crescents hugging the sprite's
      left/right edge,
    - pebbles and flower specks that lay on the plot,
    - the plot's front face / front pebbles along the bottom.
    Zones are measured against the MAIN component's own bbox (the
    building), not the whole mask: debris below the building's base
    would otherwise stretch the mask and hide from the zone tests.
    Real props (barrels, crates, anvils, racks, mine rocks) are far
    bigger, sit higher, or are attached to the building — they survive.
    """
    lab, n = ndimage.label(mask)
    if n <= 1:
        return mask
    areas = ndimage.sum(mask, lab, index=np.arange(1, n + 1))
    slices = ndimage.find_objects(lab)
    main_id = int(np.argmax(areas)) + 1
    main_area = float(areas[main_id - 1])
    msl = slices[main_id - 1]
    mh = msl[0].stop - msl[0].start
    my1 = msl[0].stop  # main component's bottom edge (exclusive)
    h, w = mask.shape
    keep = lab == main_id
    dropped = 0
    for i, sl in enumerate(slices, start=1):
        if i == main_id or sl is None:
            continue
        area = float(areas[i - 1])
        cw = sl[1].stop - sl[1].start
        ch = sl[0].stop - sl[0].start
        dust = area < 64
        side_face = (sl[1].start <= 2 or sl[1].stop >= w - 2) and cw <= 8
        plot_speck = (area < 0.004 * main_area
                      and sl[0].start > my1 - 0.45 * mh)
        front_face = (area <= 0.01 * main_area
                      and sl[0].start >= my1 - 0.25 * mh
                      and sl[0].stop >= my1 - 0.12 * mh
                      and ch <= 0.10 * mh)
        if dust or side_face or plot_speck or front_face:
            dropped += 1
            continue
        keep |= lab == i
    if dropped:
        print("    debris dropped: %d small component(s)" % dropped)
    return keep


def remove_slab(rgb, mask, name, dirt_top_frac=0.0):
    """Remove the baked-in ground slab from one extracted component.

    Works on the component's bbox crop. The flood starts from the
    bottom rows and travels through slab-coloured pixels only, so it
    removes the grass plot and the dirt path right up to the building's
    own base and around free-standing props. dirt_top_frac guards the
    compound: dirt pixels above that fraction of the height are not
    passable (its courtyard dirt is interior, only the gate apron goes).
    Debris dropping runs on the mask re-trimmed to its post-flood
    extent, so edge/zone tests measure the final sprite geometry.
    Returns the cleaned mask at full chart size.
    """
    ys, xs = np.where(mask)
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    sub_rgb = rgb[box[1]:box[3], box[0]:box[2]]
    sub = mask[box[1]:box[3], box[0]:box[2]]
    grass, dirt, fringe = slab_masks(sub_rgb)
    if dirt_top_frac > 0.0:
        dirt = dirt.copy()
        dirt[:int(dirt_top_frac * sub.shape[0]), :] = False
    passable = (grass | dirt | fringe) & sub
    lab, _ = ndimage.label(passable)
    # Seed from the bottom band: some slabs end in a dark outline stroke
    # a few px thick that is not slab-coloured, so the grass region's
    # lowest pixels sit a little above the component's bottom edge.
    band = max(6, int(0.04 * sub.shape[0]))
    seeds = set(np.unique(lab[-band:, :])) - {0}
    if not seeds:
        print("    [%s] slab: no bottom seeds found, mask unchanged" % name)
        return mask
    slab = np.isin(lab, list(seeds))
    removed = int((slab & sub).sum())
    kept = sub & ~slab
    full = np.zeros(mask.shape, dtype=bool)
    full[box[1]:box[3], box[0]:box[2]] = kept
    ys, xs = np.where(full)
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    out = np.zeros(mask.shape, dtype=bool)
    out[y0:y1, x0:x1] = _drop_debris(full[y0:y1, x0:x1])
    top = int(np.where(slab.any(axis=1))[0].min()) if slab.any() else -1
    print("    [%s] slab removed %d px (%.1f%% of component), flood top row %d/%d"
          % (name, removed, 100.0 * removed / max(1, int(sub.sum())),
             top, sub.shape[0]))
    return out


def save_rgba(rgb, mask, out_path):
    """Save one component (boolean mask) as a trimmed RGBA PNG."""
    ys, xs = np.where(mask)
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    rgba = np.dstack([rgb, np.where(mask, 255, 0).astype(np.uint8)])
    out = Image.fromarray(rgba, "RGBA").crop(box)
    # Kill the RGB stored under fully transparent pixels (JPEG white), so
    # downscaling cannot bleed a white halo into the silhouette edge.
    arr = np.asarray(out).copy()
    arr[arr[:, :, 3] == 0, :3] = 0
    out = Image.fromarray(arr, "RGBA")
    if max(out.size) > MAX_SIZE:
        scale = MAX_SIZE / float(max(out.size))
        new_size = (round(out.size[0] * scale), round(out.size[1] * scale))
        out = out.resize(new_size, Image.BILINEAR)
    # Final-space debris pass: the bilinear downscale can sever the
    # hairline bridges that connected a slab remnant to the building,
    # so re-run the same drop rules on the exact pixels being shipped.
    arr = np.asarray(out).copy()
    clean = _drop_debris(arr[:, :, 3] > 0)
    if not clean.all():
        arr[~clean] = 0
        out = Image.fromarray(arr, "RGBA")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out.save(out_path)
    corners = [out.getpixel(p)[3] for p in
               [(0, 0), (out.size[0] - 1, 0), (0, out.size[1] - 1),
                (out.size[0] - 1, out.size[1] - 1)]]
    print("saved %s size=%s bbox=%s corner_alpha=%s" % (
        out_path, out.size, box, corners))
    return box


def extract_chart(prefix, filename):
    path = os.path.join(USER, filename)
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
    print("[%s] top components (area, bbox y0,y1,x0,x1):" % prefix)
    for c in comps[:8]:
        sl = c["sl"]
        print("  area=%7d  y=%4d..%4d  x=%4d..%4d" % (
            c["area"], sl[0].start, sl[0].stop, sl[1].start, sl[1].stop))
    buildings = comps[:4]
    # Reading order: top row first (by centre y), left to right within a row.
    buildings.sort(key=lambda c: (c["cy"] > rgb.shape[0] / 2.0, c["cx"]))
    for idx, c in enumerate(buildings, start=1):
        name = "%s_t%d" % (prefix, idx)
        cleaned = remove_slab(rgb, lab == c["id"], name)
        save_rgba(rgb, cleaned, os.path.join(OUT_DIR, "%s.png" % name))


def extract_compound():
    im = Image.open(SRC_COMPOUND).convert("RGB")
    rgb = np.asarray(im)
    fg = build_alpha(rgb)
    # The courtyard dirt is the compound's own interior ground: only the
    # apron in front of the gate (bottom ~15% of the sprite) may flood.
    cleaned = remove_slab(rgb, fg, "camp_compound", dirt_top_frac=0.85)
    save_rgba(rgb, cleaned, os.path.join(OUT_DIR, "camp_compound.png"))


def main():
    for prefix, filename in CHARTS:
        extract_chart(prefix, filename)
    extract_compound()


if __name__ == "__main__":
    main()
