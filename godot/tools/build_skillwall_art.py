#!/usr/bin/env python3
"""Empire Age 14c — art for Thạch Sơn's Nham Tường (btype
"skillwall"): rune-stone segments in the wall family's format
(~416x456, ART_SCALE 1.5 over a 1-tile footprint, bottom-anchored).
Drawn procedurally: dark basalt blocks, bronze veins, one carved
chevron rune per block — the Earth Temple motif, in the painted
dialect of the other wall sets. Two variants: straight + corner
(Main.refresh_wall_variants picks by adjacency, as for wallstone).

Run from the godot/ directory:  python3 tools/build_skillwall_art.py
"""
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "buildings")
SS = 2
W, H = 416 * SS, 456 * SS

STONE = [(96, 94, 88), (110, 106, 96), (84, 82, 78), (118, 112, 100),
         (90, 88, 92), (104, 98, 86)]
STONE_D = (58, 56, 54)
BRONZE = (150, 112, 58)
RUNE = (64, 196, 168)


def blocks(dr, rng, x0, x1, y_base, rows):
    """Stack rough stone blocks from y_base upward."""
    y = y_base
    for r in range(rows):
        bh = (H // 7) + rng.randint(-8, 8) * SS
        x = x0 + (r % 2) * (W // 9)
        while x < x1 - W // 8:
            bw = rng.randint(W // 5, W // 3)
            col = rng.choice(STONE)
            dr.rounded_rectangle([x + 3 * SS, y - bh + 3 * SS,
                                  min(x + bw, x1) - 3 * SS, y - 3 * SS],
                                 radius=7 * SS, fill=col, outline=STONE_D,
                                 width=3 * SS)
            # Top light edge + a bronze vein fleck.
            dr.line([x + 8 * SS, y - bh + 7 * SS, min(x + bw, x1) - 8 * SS,
                     y - bh + 7 * SS], fill=(168, 162, 148), width=2 * SS)
            if rng.random() < 0.4:
                vx = x + rng.randint(10, max(11, bw // SS - 12)) * SS
                dr.line([vx, y - bh + 10 * SS, vx + 6 * SS, y - 12 * SS],
                        fill=BRONZE, width=2 * SS)
            x += bw
        y -= bh
    return y


def rune(dr, cx, cy, s):
    """Carved chevron rune (Earth Temple mark), faintly glowing."""
    pts = [(cx - s, cy + s // 2), (cx, cy - s // 2), (cx + s, cy + s // 2)]
    dr.line(pts, fill=RUNE, width=5 * SS)
    dr.line([(cx - s, cy + s), (cx, cy), (cx + s, cy + s)], fill=RUNE,
            width=4 * SS)


def make(name, corner):
    rng = random.Random(1408 if not corner else 1415)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    base = H - 26 * SS
    if not corner:
        top = blocks(dr, rng, 6 * SS, W - 6 * SS, base, 3)
        # Cap slab + runes on the middle row.
        dr.rounded_rectangle([2 * SS, top - 16 * SS, W - 2 * SS, top + 8 * SS],
                             radius=6 * SS, fill=(122, 116, 104),
                             outline=STONE_D, width=3 * SS)
        rune(dr, W // 4, base - H // 5, 16 * SS)
        rune(dr, (3 * W) // 4, base - H // 5, 16 * SS)
    else:
        # Corner: a taller post at the left + a lower run to the right.
        top = blocks(dr, rng, W // 3, W - 6 * SS, base, 2)
        dr.rounded_rectangle([4 * SS, base - H // 2 - 30 * SS, W // 3 + 8 * SS,
                              base], radius=8 * SS, fill=(108, 103, 94),
                             outline=STONE_D, width=3 * SS)
        dr.rounded_rectangle([2 * SS, base - H // 2 - 46 * SS, W // 3 + 12 * SS,
                              base - H // 2 - 26 * SS], radius=6 * SS,
                             fill=(124, 118, 106), outline=STONE_D, width=3 * SS)
        rune(dr, W // 6, base - H // 4, 18 * SS)
        rune(dr, (3 * W) // 4, base - H // 6, 15 * SS)
    im = im.resize((W // SS, H // SS), Image.LANCZOS)
    im.save(os.path.join(OUT, name))
    print("wrote", name, im.size)


if __name__ == "__main__":
    make("skillwall.png", False)
    make("skillwall_corner.png", True)
