#!/usr/bin/env python3
"""Slice the Empire Age terrain tileset sheet into individual tile PNGs.

Source: the tileset Tín sent 2026-11-08 (dark background, tiles laid out in
a rough grid separated by dark gutters). Detection: a pixel counts as
"gutter" when its brightest channel is < 45; a row/column is gutter when
>= 99% of its pixels are gutter. Content bands between gutters are tiles.

Layout (6 visual rows):
  row 0: full tiles   grass x3, dirt, plowed, dark soil, sand x2, stone x2
  row 1: water x3, water foam, water-over-sand, sand x2, dirt, stone x2
  row 2: plateau edge tops    (grass/dirt/sand/stone x3)
  row 3: plateau edge corners (grass/dirt/sand/stone x3)
  row 4: shore transitions    (grass / sand A / sand B / stone, each
                               [corner-dip-right, straight, corner-dip-left])
  row 5: cliff faces          (grass/dirt/sand/stone x3)

Shore straights are also exported pre-rotated (land side N/E/S/W) and the
two corner pieces give the four diagonal corners, so the game never has to
rotate textures at draw time.

Outputs: assets/tiles/*.png + assets/tiles/manifest.json + a labelled
contact sheet at /tmp/tiles_contact.png for eyeball verification.
Re-runnable: python3 tools/extract_tiles.py [source.jpg]
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else (
    "/home/hatch/workspace/user/files/"
    "341380BD-D748-47D5-AC22-8326AE3A8FAA-photo-BC535872-73A9-40E8-BF57-3BFE6E04E39F.jpg")
OUT_DIR = os.path.join(ROOT, "assets", "tiles")
GUTTER_MAX = 45
GUTTER_FRAC = 0.99
# Columns of the big full tiles have drop-shadow spill in the gutter, so
# the per-column gutter test is looser than the per-row one.
GUTTER_FRAC_COL = 0.90

ROW_NAMES = [
    ["grass_0", "grass_1", "grass_2", "dirt", "plowed", "soil_dark",
     "sand_0", "sand_1", "stone_0", "stone_1"],
    ["water_0", "water_1", "water_2", "water_foam", "water_over_sand",
     "sand_2", "sand_shells", "dirt_brown", "stone_rocky", "stone_brick"],
    ["edge_grass_0", "edge_grass_1", "edge_grass_2",
     "edge_dirt_0", "edge_dirt_1", "edge_dirt_2",
     "edge_sand_0", "edge_sand_1", "edge_sand_2",
     "edge_stone_0", "edge_stone_1", "edge_stone_2"],
    ["edge_grass_3", "edge_grass_4", "edge_grass_5",
     "edge_dirt_3", "edge_dirt_4", "edge_dirt_5",
     "edge_sand_3", "edge_sand_4", "edge_sand_5",
     "edge_stone_3", "edge_stone_4", "edge_stone_5"],
    ["shore_grass_cl", "shore_grass_n", "shore_grass_cr",
     "shore_sand_cl", "shore_sand_n", "shore_sand_cr",
     "shore_sand2_cl", "shore_sand2_n", "shore_sand2_cr",
     "shore_stone_cl", "shore_stone_n", "shore_stone_cr"],
    ["cliff_grass_0", "cliff_grass_1", "cliff_grass_2",
     "cliff_dirt_0", "cliff_dirt_1", "cliff_dirt_2",
     "cliff_sand_0", "cliff_sand_1", "cliff_sand_2",
     "cliff_stone_0", "cliff_stone_1", "cliff_stone_2"],
]

SHORE_SETS = ["grass", "sand", "sand2", "stone"]


def bands(flags, min_size=20, merge_gap=6):
    """flags: list of bool (True = content). Return [(start, end)) bands."""
    out = []
    i = 0
    n = len(flags)
    while i < n:
        if flags[i]:
            j = i
            gap = 0
            last = i
            while j < n and gap <= merge_gap:
                if flags[j]:
                    last = j
                    gap = 0
                else:
                    gap += 1
                j += 1
            if last - i + 1 >= min_size:
                out.append((i, last + 1))
            i = j
        else:
            i += 1
    return out


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    px = im.load()

    def is_gutter(x, y):
        r, g, b = px[x, y]
        return max(r, g, b) < GUTTER_MAX

    row_content = []
    for y in range(h):
        dark = sum(1 for x in range(0, w, 3) if is_gutter(x, y))
        row_content.append(dark < (w // 3) * GUTTER_FRAC)
    row_bands = bands(row_content)
    print("row bands:", row_bands)
    if len(row_bands) != 6:
        print("WARN: expected 6 row bands")

    os.makedirs(OUT_DIR, exist_ok=True)
    manifest = {}
    tiles = {}

    for ri, (y0, y1) in enumerate(row_bands[:6]):
        col_content = []
        for x in range(w):
            dark = sum(1 for y in range(y0, y1, 3) if is_gutter(x, y))
            col_content.append(dark < ((y1 - y0) // 3) * GUTTER_FRAC_COL)
        col_bands = bands(col_content, merge_gap=3)
        names = ROW_NAMES[ri]
        print(f"row {ri}: {len(col_bands)} tiles (expect {len(names)})")
        for ci, (x0, x1) in enumerate(col_bands):
            if ci >= len(names):
                break
            name = names[ci]
            # Tighten the box: trim fully-gutter lines inside the band.
            def col_dark(x):
                return all(is_gutter(x, y) for y in range(y0, y1, 2))

            def row_dark(y):
                return all(is_gutter(x, y) for x in range(x0, x1, 2))

            bx0, bx1, by0, by1 = x0, x1, y0, y1
            while bx0 < bx1 and col_dark(bx0):
                bx0 += 1
            while bx1 > bx0 and col_dark(bx1 - 1):
                bx1 -= 1
            while by0 < by1 and row_dark(by0):
                by0 += 1
            while by1 > by0 and row_dark(by1 - 1):
                by1 -= 1
            # Small inset cuts the rounded corners / drop shadow so the
            # full tiles butt together without dark seams.
            iw = max(1, int((bx1 - bx0) * 0.04))
            ih = max(1, int((by1 - by0) * 0.04))
            tile = im.crop((bx0 + iw, by0 + ih, bx1 - iw, by1 - ih))
            tile.save(os.path.join(OUT_DIR, name + ".png"))
            tiles[name] = tile
            manifest[name] = {"row": ri, "col": ci,
                              "src_box": [bx0, by0, bx1, by1],
                              "size": list(tile.size)}

    # Pre-rotated shore variants. Straight piece: land on TOP as sliced.
    # rotate(-90) = clockwise -> land faces EAST; rotate(90) -> WEST.
    for mat in SHORE_SETS:
        straight = tiles.get(f"shore_{mat}_n")
        if straight is None:
            continue
        variants = {
            f"shore_{mat}_e": straight.rotate(-90, expand=True),
            f"shore_{mat}_s": straight.rotate(180, expand=True),
            f"shore_{mat}_w": straight.rotate(90, expand=True),
        }
        # Corner pieces (verified by per-quadrant land fraction): cl has
        # land extending down its LEFT side -> NW corner (land N+W);
        # cr mirrors it -> NE. Their 180 rotations give SE / SW.
        cl = tiles.get(f"shore_{mat}_cl")
        cr = tiles.get(f"shore_{mat}_cr")
        if cl is not None:
            variants[f"shore_{mat}_nw"] = cl
            variants[f"shore_{mat}_se"] = cl.rotate(180, expand=True)
        if cr is not None:
            variants[f"shore_{mat}_ne"] = cr
            variants[f"shore_{mat}_sw"] = cr.rotate(180, expand=True)
        for vname, vimg in variants.items():
            vimg.save(os.path.join(OUT_DIR, vname + ".png"))
            tiles[vname] = vimg
            manifest[vname] = {"derived": f"shore_{mat}_n/cl/cr rotation",
                               "size": list(vimg.size)}

    with open(os.path.join(OUT_DIR, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print(f"saved {len(manifest)} tiles to {OUT_DIR}")

    # Labelled contact sheet for eyeball verification.
    names = sorted(tiles.keys())
    cell = 120
    cols = 8
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 14)), (24, 24, 30))
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        x = (i % cols) * cell
        y = (i // cols) * (cell + 14)
        t = tiles[name].copy()
        t.thumbnail((cell - 8, cell - 8))
        sheet.paste(t, (x + 4, y + 4))
        d.text((x + 4, y + cell + 2), name, fill=(230, 230, 230))
    sheet.save("/tmp/tiles_contact.png")
    print("contact sheet: /tmp/tiles_contact.png", sheet.size)


if __name__ == "__main__":
    main()
