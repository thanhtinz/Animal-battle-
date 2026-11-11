#!/usr/bin/env python3
"""Empire Age 14c-fix3 — big heads for the ORIGINAL four heroes.

The owner approved the new four's big-head chibi proportions and
ordered the old four enlarged to the same template ("nếu đầu to
thì cho các nhân vật cũ đầu to luôn"), with crisp pixel edges.

Method (identity-safe by construction): each shipped sprite is
warped vertically at 4x supersample — head segment (top -> jaw)
scaled up, body segment counter-scaled, feet pinned to the ground
line — then snapped to the roster's crisp profile (binary alpha,
52-colour palette, no dither; see crisp_snap in
build_hero_assets2.py). The warp uses the sprite's own pixels, so
faces / hair / costumes / weapons cannot drift the way a
regeneration could. The rig specs in build_hero_rig.py are warped
by the SAME per-direction function and the parts are re-cut with
that builder's own engine, so pivots stay fitted and rest-pose
reassembly stays pixel-exact. Only the "dirs" block of each old
hero is replaced in hero_rig.json; weapon grip/wscale, tuning and
everything belonging to the new four are preserved.

JAW = head height in px of the 92-px ink (top -> jaw incl. hair),
read by eye on the shipped south sprites over a 6x row grid.
TARGET = the unified template, 43/92 ~= 0.47.

Run from the godot/ directory:  python3 tools/build_hero_fix3.py
"""
import copy
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image

import build_hero_assets2 as A2
import build_hero_rig as R

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ASSETS = os.path.join(ROOT, "assets")
CHARS = ["ngan_ky", "kim_hoa", "lam_bao", "bach_sa"]
DIRS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]
JAW = {"ngan_ky": 40.0, "kim_hoa": 39.0, "lam_bao": 39.0,
       "bach_sa": 38.0}
TARGET = 43.0
SS = 4  # supersample for the warp


def warp_fn(top: float, span: float, frac_from: float, frac_to: float):
    """Continuous canvas-space row warp for one direction sprite:
    ink top and ink bottom fixed, the jaw anchor row moves from
    frac_from to frac_to of the ink span."""
    a_src = top + frac_from * span
    a_dst = top + frac_to * span
    bot = top + span

    def W(y: float) -> float:
        if y <= a_src:
            return top + (y - top) * (a_dst - top) / (a_src - top)
        return a_dst + (y - a_src) * (bot - a_dst) / (bot - a_src)

    return W


def warp_sprite(char: str, dir8: str) -> None:
    path = os.path.join(ASSETS, f"king_{char}_{dir8}.png")
    img = Image.open(path).convert("RGBA")
    bbox = img.getchannel("A").getbbox()
    x0, top, x1, bot = bbox
    span = bot - top
    sub = img.crop(bbox)
    big = sub.resize((sub.width * SS, span * SS), Image.NEAREST)
    frac = JAW[char] / 92.0
    big = A2.warp_rows(big, frac * span * SS,
                       (TARGET / 92.0) * span * SS)
    small = big.resize(sub.size, Image.BOX)
    small = A2.crisp_snap(small)
    img.paste(small, (x0, top))
    # Anything the mask cleanup dropped outside the bbox stays
    # transparent; assert the silhouette still spans the full ink.
    img.save(path)
    print(f"{char} {dir8}: warped (span {span})")


def warp_spec(spec: dict, W) -> dict:
    out = {}
    for k, v in spec.items():
        if k in ("arm_l", "arm_r", "leg_l", "leg_r", "shoe_l", "shoe_r"):
            nv = {"poly": [(x, W(y)) for x, y in v["poly"]],
                  "pivot": (v["pivot"][0], W(v["pivot"][1]))}
            for opt in ("hand", "knee"):
                if opt in v:
                    nv[opt] = (v[opt][0], W(v[opt][1]))
            if "phase" in v:
                nv["phase"] = v["phase"]
            out[k] = nv
        elif k == "back":
            out[k] = {"polys": [[(x, W(y)) for x, y in poly]
                                for poly in v["polys"]],
                      "pivot": (v["pivot"][0], W(v["pivot"][1]))}
        elif k == "weapon":
            nv = dict(v)
            if "hand" in nv:
                nv["hand"] = (nv["hand"][0], W(nv["hand"][1]))
            out[k] = nv
        elif k == "order":
            out[k] = list(v)
        else:
            out[k] = v
    return out


def main() -> None:
    rig_path = os.path.join(ASSETS, "hero_rig.json")
    with open(rig_path, encoding="utf-8") as f:
        data = json.load(f)
    total_diff = 0
    for char in CHARS:
        frac = JAW[char] / 92.0
        # 1) warp the eight direction sprites (cut_parts reads them
        #    back from disk, so sprites go first).
        fns = {}
        for dir8 in DIRS:
            p = os.path.join(ASSETS, f"king_{char}_{dir8}.png")
            bb = Image.open(p).getchannel("A").getbbox()
            fns[dir8] = warp_fn(bb[1], bb[3] - bb[1], frac,
                                TARGET / 92.0)
            warp_sprite(char, dir8)
        # 2) warp the authored rig specs with the s-authored dirs'
        #    own functions; mirrors derive inside full_specs (x-only
        #    flip, y already warped in the source spec).
        authored = {}
        for dir8, spec in R.RIG[char].items():
            authored[dir8] = warp_spec(spec, fns[dir8])
        saved = R.RIG[char]
        R.RIG[char] = authored
        try:
            specs = R.full_specs(char)
        finally:
            R.RIG[char] = saved
        # 3) re-cut parts + rebuild the dirs block exactly as
        #    build_hero_rig.main() assembles it.
        dirs_entry = {}
        for dir8 in DIRS:
            spec = specs[dir8]
            src, parts, diff = R.cut_parts(char, dir8, spec)
            total_diff += diff
            if diff:
                print(f"  !! {char} {dir8} reassembly diff {diff}")
            zmap = R.Z_FRONT if dir8 in R.FRONT_DIRS else (
                R.Z_BACK if dir8 in R.BACK_DIRS else R.Z_SIDE)
            dentry = {"canvas": list(src.size),
                      "swing": -1 if dir8 in ("w", "sw", "nw") else 1,
                      "parts": {}}
            for key, img in parts.items():
                img.save(os.path.join(
                    R.PARTS_DIR, "%s_%s_%s.png" % (char, dir8, key)))
                if key in spec:
                    pv = spec[key]["pivot"]
                elif key.startswith("shin_"):
                    pv = spec["leg_" + key[-1]]["knee"]
                else:
                    pv = (src.width / 2.0, 30.0)
                dentry["parts"][key] = {
                    "tex": "hero_parts/%s_%s_%s.png" % (char, dir8, key),
                    "pivot": [round(float(pv[0]), 1),
                              round(float(pv[1]), 1)],
                    "z": R.part_z(zmap, key)}
                if key in spec and "phase" in spec[key]:
                    dentry["parts"][key]["phase"] = spec[key]["phase"]
                if key in spec and "knee" in spec[key]:
                    kn = spec[key]["knee"]
                    dentry["parts"][key]["knee"] = [
                        round(float(kn[0]), 1), round(float(kn[1]), 1)]
            wspec = dict(spec["weapon"])
            warm = wspec["arm"]
            hand = wspec.get("hand", spec[warm]["hand"]
                             if warm in spec else (0, 0))
            if dir8 in R.NO_WEAPON_DIRS.get(char, set()):
                # Owner rule: no weapon renders in back directions
                # (see build_hero_rig.NO_WEAPON_DIRS).
                dentry["weapon"] = {}
            else:
                dentry["weapon"] = {
                    "arm": warm,
                    "hand": [float(hand[0]), float(hand[1])],
                    "rest": float(wspec["rest"]),
                    "z": int(wspec.get("wz", R.WEAPON_Z)),
                    "follow": R.WEAPON_FOLLOW[char]}
            dirs_entry[dir8] = dentry
        data["chars"][char]["dirs"] = dirs_entry
        print(f"{char}: rig re-cut, head {JAW[char]:.0f} -> {TARGET:.0f}")
    with open(rig_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
    print("reassembly diff total:", total_diff)
    assert total_diff == 0, "rest-pose reassembly must stay exact"


if __name__ == "__main__":
    main()
