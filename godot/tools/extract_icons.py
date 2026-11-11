#!/usr/bin/env python3
"""Extract Tín's painted HUD icon set into game-ready PNGs with transparency.

Sources (originals in ~/workspace/user/files/):
  * Icon sheet 91718559...jpg — WHITE background, 15 painted icons in
    3 loose rows (row 3 sits lower and larger):
      row 1: food (drumstick), wood (logs), gold (bars), stone (rocks),
             iron (ingots), pop (villagers)
      row 2: timer (stopwatch), chat (speech bubbles), friends (people
             + green plus), gear (settings), build (hammer + wrench),
             train (crossed swords), tech (open book)
      row 3: age_1 (thatch hut badge, green), age_2 (castle, blue),
             age_3 (grand castle, purple)
  * Age 4 badge 8822AA9F...jpg — single Roman-temple badge on white.

Outputs (in ../assets/icons/): food.png, wood.png, gold.png, stone.png,
iron.png, pop.png, timer.png, chat.png, friends.png, gear.png,
build.png, train.png, tech.png, age_1.png .. age_4.png (RGBA, trimmed).

Method: same white-background removal as tools/extract_buildings.py —
pixels close to white are background candidates; only the connected
components touching the image border count as background, so the cream
chat bubbles / book pages / stopwatch face INSIDE their dark outlines
survive; a rim cleanup strips the near-white JPEG halo hugging the
background. On this sheet every icon is exactly one foreground
component: the 3 badges are identified by area, the 13 small icons are
split into their 2 rows by centre-y and ordered left to right.
Re-runnable: python3 tools/extract_icons.py
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "assets", "icons")
USER = os.path.expanduser("~/workspace/user/files")

SRC_SHEET = os.path.join(
    USER,
    "91718559-216B-46C4-852C-84702E580F62-photo-99E0CBC5-9D0C-4B5C-866F-9BAB217C096C.jpg",
)
SRC_AGE4 = os.path.join(
    USER,
    "8822AA9F-3197-45F6-8EBD-2E9F7FC362BB-photo-AC8E1D37-4386-423A-BB1B-146EC987AA5A.jpg",
)

ROW_NAMES = [
    ["food", "wood", "gold", "stone", "iron", "pop"],
    ["timer", "chat", "friends", "gear", "build", "train", "tech"],
]
BADGE_MIN_AREA = 40000  # badges measure ~50k px; small icons 16-24k px

DIST_TH = 30   # distance from pure white that counts as background candidate
RIM_DIST = 60  # near-white band removed where it touches the background
MAX_SIZE = 320  # longest output side (HUD shows icons at 18-52 px)


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
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out.save(out_path)
    corners = [out.getpixel(p)[3] for p in
               [(0, 0), (out.size[0] - 1, 0), (0, out.size[1] - 1),
                (out.size[0] - 1, out.size[1] - 1)]]
    print("saved %s size=%s bbox=%s corner_alpha=%s" % (
        os.path.basename(out_path), out.size, box, corners))
    return box


def extract_sheet():
    im = Image.open(SRC_SHEET).convert("RGB")
    rgb = np.asarray(im)
    fg = build_alpha(rgb)
    lab, _ = ndimage.label(fg)
    comps = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        area = int((lab[sl] == i).sum())
        comps.append({"id": i, "area": area,
                      "cx": (sl[1].start + sl[1].stop) / 2.0,
                      "cy": (sl[0].start + sl[0].stop) / 2.0})
    badges = sorted([c for c in comps if c["area"] >= BADGE_MIN_AREA],
                    key=lambda c: c["cx"])
    small = [c for c in comps if c["area"] < BADGE_MIN_AREA]
    # Split the small icons into rows at the largest centre-y gap.
    small.sort(key=lambda c: c["cy"])
    gaps = [(small[i + 1]["cy"] - small[i]["cy"], i)
            for i in range(len(small) - 1)]
    split = max(gaps)[1]
    rows = [sorted(small[:split + 1], key=lambda c: c["cx"]),
            sorted(small[split + 1:], key=lambda c: c["cx"])]
    print("[sheet] badges=%d rows=%s" % (
        len(badges), [len(r) for r in rows]))
    assert len(badges) == 3, "expected 3 age badges, got %d" % len(badges)
    for r, names in zip(rows, ROW_NAMES):
        assert len(r) == len(names), "row has %d icons, expected %d" % (
            len(r), len(names))
        for c, name in zip(r, names):
            save_rgba(rgb, lab == c["id"],
                      os.path.join(OUT_DIR, "%s.png" % name))
    for idx, c in enumerate(badges, start=1):
        save_rgba(rgb, lab == c["id"],
                  os.path.join(OUT_DIR, "age_%d.png" % idx))


def extract_age4():
    im = Image.open(SRC_AGE4).convert("RGB")
    rgb = np.asarray(im)
    fg = build_alpha(rgb)
    save_rgba(rgb, fg, os.path.join(OUT_DIR, "age_4.png"))


def main():
    extract_sheet()
    extract_age4()


if __name__ == "__main__":
    main()
