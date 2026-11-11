#!/usr/bin/env python3
"""Empire Age — per-SLOT team-color palette generation (Tín's rule,
2026-11-09: "Trận 4 đội thì phải 4 màu nha nhân vật giống nhau hết
nhưng phải chia màu" — every faction uses the SAME base sprites;
identity is a team colour dyed onto the faction-bearing parts only).

This generalises tools/recolor_enemy.py (which produced the slot-1
blue set) into one canonical palette map applied uniformly:

  * Source of truth = the slot-0 (Roman red) art.
  * Only the red-dominant hue band rotates (cloth/tunic, shield
    faces, capes, plumes, flags/banners, red roofs):
    hue in [0.955, 1.0] U [0.0, 0.045] and saturation >= 0.28.
  * Skin (orange), wood (brown), stone (grey) and gold trim
    (yellow) sit outside the band and stay identical for every
    colour — same faces, same armour, same weapons.

Slot table (colour is keyed by player SLOT, not team — a 4-player
match shows 4 colours even in 2v2):

  slot 0  ĐỎ          canonical art, nothing generated
  slot 1  XANH DƯƠNG  hue 0.615 — assets/enemy/ (the P3 enemy set;
                      regenerated here with the original constants,
                      byte-identical to recolor_enemy.py's output)
  slot 2  XANH LÁ     hue 0.345 forest green, slightly muted
                      saturation — assets/team2/
  slot 3  VÀNG        hue 0.150 amber-yellow, pulled a touch
                      toward lemon so the cloth reads brighter
                      than the (unrotated) deep-gold trim —
                      assets/team3/

Each set mirrors the asset layout: <unit>.png + <unit>_frames.json,
buildings/<stem>_tN.png (only the 4 stems whose art carries faction
colour: towncenter/barracks/house/tower), ships/<kind>.png and
king.png (cape + shield; asset only — the King is not in gameplay).

Run: python3 tools/recolor_teams.py
"""
import colorsys
import json
import os
import shutil

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")

RED_HI = 0.045              # red band: h <= RED_HI or h >= RED_LO
RED_LO = 0.955
MIN_SAT = 0.28

UNITS = ["villager", "militia", "archer", "spearman", "cavalry", "ram", "cart", "wagon"]
BUILDING_STEMS = ["towncenter", "barracks", "house", "tower"]
SHIPS = ["fishing_boat", "transport", "war_ship"]

# slot -> (output dir, target hue, saturation base, value multiplier)
# The saturation factor ramps sat_base -> 1.0 across the band edge,
# exactly as the original enemy pass (0.92 base, value x0.94).
SLOTS = {
    1: ("enemy", 0.615, 0.92, 0.94),
    2: ("team2", 0.345, 0.82, 0.96),
    3: ("team3", 0.150, 0.86, 0.99),
    # 13z slots 4-7 (Tín approved 2026-11-11): Tím · Cam ·
    # Xanh ngọc · Hồng.
    4: ("team4", 0.760, 0.85, 0.97),  # TÍM (purple)
    5: ("team5", 0.075, 0.95, 1.00),  # CAM (orange)
    6: ("team6", 0.500, 0.85, 0.97),  # XANH NGỌC (teal)
    7: ("team7", 0.930, 0.72, 1.03),  # HỒNG (pink: softer + brighter)
}


def clamp01(v: float) -> float:
    return max(0.0, min(1.0, v))


def recolor(img: Image.Image, target_hue: float, sat_base: float,
            val_mult: float) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, ss, vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if ss >= MIN_SAT and (hh <= RED_HI or hh >= RED_LO):
                # Distance into the band: pure red (h~0/1) rotates
                # fully; edge hues (orange-red) rotate less so
                # gradients survive.
                d = min(hh, 1.0 - hh)
                t = 1.0 - clamp01(d / RED_HI if hh <= RED_HI
                                  else d / (1.0 - RED_LO))
                ns = ss * (sat_base + (1.0 - sat_base) * t)
                nv = vv * val_mult
                nr, ng, nb = colorsys.hsv_to_rgb(target_hue, ns, nv)
                px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return img


def main() -> None:
    for slot, (dirname, hue, sat_base, val_mult) in sorted(SLOTS.items()):
        out = os.path.join(ASSETS, dirname)
        out_b = os.path.join(out, "buildings")
        out_s = os.path.join(out, "ships")
        for d in (out, out_b, out_s):
            os.makedirs(d, exist_ok=True)
        for unit in UNITS:
            src = os.path.join(ASSETS, unit + ".png")
            dst = os.path.join(out, unit + ".png")
            recolor(Image.open(src), hue, sat_base, val_mult).save(dst)
            shutil.copyfile(os.path.join(ASSETS, unit + "_frames.json"),
                            os.path.join(out, unit + "_frames.json"))
            print("slot %d unit: %s" % (slot, dst))
        for stem in BUILDING_STEMS:
            for tier in range(1, 5):
                src = os.path.join(ASSETS, "buildings",
                                   "%s_t%d.png" % (stem, tier))
                dst = os.path.join(out_b, "%s_t%d.png" % (stem, tier))
                recolor(Image.open(src), hue, sat_base, val_mult).save(dst)
                print("slot %d building: %s" % (slot, dst))
        for ship in SHIPS:
            src = os.path.join(ASSETS, "ships", ship + ".png")
            dst = os.path.join(out_s, ship + ".png")
            recolor(Image.open(src), hue, sat_base, val_mult).save(dst)
            print("slot %d ship: %s" % (slot, dst))
        # King: cape + shield carry the faction colour (asset only).
        src = os.path.join(ASSETS, "king.png")
        dst = os.path.join(out, "king.png")
        recolor(Image.open(src), hue, sat_base, val_mult).save(dst)
        print("slot %d king: %s" % (slot, dst))


if __name__ == "__main__":
    main()
