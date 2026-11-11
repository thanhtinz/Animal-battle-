#!/usr/bin/env python3
"""
build_walk_strips.py — Empire Age 13n follow-up QA: 8-frame walk
cycle strips per character (side view 'e' row + front view 's'
row), rendered with the same pose curves the engine runs
(build_hero_rig.walk_pose). Tín reported the v2 walk read as
static; these strips are the eyeball proof that the stride
extremes are unmistakable: legs apart, one foot lifted with the
knee folded (knights) / shoes alternating under the hem (gowns).

Outputs: shots/empire_age_walk_strip_v3_<char>.png
Re-run: python3 tools/build_walk_strips.py   (from the godot/ folder)
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_hero_rig as B
from PIL import Image, ImageDraw

ROOT = B.ROOT
SHOTS = os.path.join(ROOT, "shots")
S = 3


def pivots_of(spec, parts):
    out = {}
    for k in parts:
        if k in spec:
            out[k] = spec[k]["pivot"]
        elif k.startswith("shin_"):
            out[k] = spec["leg_" + k[-1]]["knee"]
        else:
            out[k] = (0, 0)
    return out


def main():
    os.makedirs(SHOTS, exist_ok=True)
    for char in B.CHARS:
        wimg, grip = B.WEAPON_DRAW[char]()
        specs = B.full_specs(char)
        rows = []
        for dir8 in ("e", "s"):
            spec = specs[dir8]
            _src, parts, diff = B.cut_parts(char, dir8, spec)
            assert diff == 0, (char, dir8, diff)
            zmap = B.Z_SIDE if dir8 == "e" else B.Z_FRONT
            pivots = pivots_of(spec, parts)
            cells = []
            for i in range(8):
                phase = i * math.pi / 4.0
                ang, offs = B.walk_pose(char, dir8, spec, phase)
                wt = B.weapon_at(spec, ang, wimg, grip)
                img = B.render_composite(parts, pivots, zmap, ang, wt, offs)
                cells.append(img)
            rows.append((dir8, cells))
        cw = max(c.width for _d, cells in rows for c in cells)
        chh = max(c.height for _d, cells in rows for c in cells)
        sheet = Image.new("RGBA", (cw * 8 * S // 3 * 3, 0), (0, 0, 0, 0))
        # compose at native size first, then upscale once
        native = Image.new("RGBA", (cw * 8, chh * 2 + 28), (24, 24, 34, 255))
        dr = ImageDraw.Draw(native)
        for ri, (dir8, cells) in enumerate(rows):
            y0 = ri * (chh + 14)
            dr.text((4, y0 + 1), "%s %s walk cycle" % (char, dir8), fill=(255, 255, 160, 255))
            for ci, img in enumerate(cells):
                native.alpha_composite(img, (ci * cw, y0 + 14))
        big = native.resize((native.width * S, native.height * S), Image.NEAREST)
        out = os.path.join(SHOTS, "empire_age_walk_strip_v3_%s.png" % char)
        big.save(out)
        print("saved", out, big.size)


if __name__ == "__main__":
    main()
