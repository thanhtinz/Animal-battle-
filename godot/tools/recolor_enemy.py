#!/usr/bin/env python3
"""Empire Age P3 — enemy faction recolor (deep blue + silver).

Tín's standing order (2026-11-08): the enemy faction is designed
in-house — deep BLUE + SILVER against the player's red/gold. This
tool derives the enemy sprite set from the player's accepted art by
rotating ONLY the red-dominant hue band to deep blue:

  * hue in [0.955, 1.0] U [0.0, 0.045] and saturation >= 0.28
    (pure reds: roofs, tunics, plumes, flags, banners, shields)
  * skin (orange, hue ~0.07), wood (brown, hue ~0.06-0.10 at low
    value), stone (near-grey) and gold trim (yellow, hue ~0.12)
    are outside the band and stay natural.

The rotated hue lands at 0.615 (deep blue); saturation is kept and
value slightly compressed so big red surfaces read as steel-blue
rather than neon. Alpha is never touched.

Outputs:
  assets/enemy/<unit>.png + <unit>_frames.json   (villager/militia/archer)
  assets/enemy/buildings/<stem>_tN.png           (towncenter/barracks/house/tower)

Run: python3 tools/recolor_enemy.py
"""
import colorsys
import json
import os
import shutil

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
OUT = os.path.join(ASSETS, "enemy")
OUT_B = os.path.join(OUT, "buildings")

TARGET_HUE = 0.615          # deep blue
RED_HI = 0.045              # red band: h <= RED_HI or h >= RED_LO
RED_LO = 0.955
MIN_SAT = 0.28


def recolor(img: Image.Image) -> Image.Image:
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
                # Distance into the band: pure red (h~0/1) rotates fully;
                # edge hues (orange-red) rotate less so gradients survive.
                d = min(hh, 1.0 - hh) if hh <= RED_HI or hh >= RED_LO else 9.9
                t = 1.0 - clamp01(d / RED_HI if hh <= RED_HI else d / (1.0 - RED_LO))
                nh = TARGET_HUE
                ns = ss * (0.92 + 0.08 * t)
                nv = vv * 0.94
                nr, ng, nb = colorsys.hsv_to_rgb(nh, ns, nv)
                px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return img


def clamp01(v: float) -> float:
    return max(0.0, min(1.0, v))


def main() -> None:
    os.makedirs(OUT_B, exist_ok=True)
    for unit in ["villager", "militia", "archer", "spearman", "cavalry", "ram"]:
        src = os.path.join(ASSETS, unit + ".png")
        dst = os.path.join(OUT, unit + ".png")
        recolor(Image.open(src)).save(dst)
        shutil.copyfile(os.path.join(ASSETS, unit + "_frames.json"),
                        os.path.join(OUT, unit + "_frames.json"))
        print("enemy unit:", dst)
    for stem in ["towncenter", "barracks", "house", "tower"]:
        for tier in range(1, 5):
            src = os.path.join(ASSETS, "buildings", "%s_t%d.png" % (stem, tier))
            dst = os.path.join(OUT_B, "%s_t%d.png" % (stem, tier))
            recolor(Image.open(src)).save(dst)
            print("enemy building:", dst)


if __name__ == "__main__":
    main()
