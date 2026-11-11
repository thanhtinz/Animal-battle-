#!/usr/bin/env python3
"""Assemble game-ready sprite sheets for the SELF-DRAWN units
(Spearman, Cavalry, Battering Ram) from the generated white-bg sheets
in ~/workspace/empire-age/gen/.

Method: build_alpha foreground -> per-figure components -> the figures
are classified per direction band (idle / walk / attack / die) using
the layout the generator produced (diagnosed comp-by-comp; see the
per-unit rules below) -> each figure is smooth-matted with the same
matte_component the buildings use -> figures are normalised into
uniform cells (standing figures scaled by height, lying figures by
width, feet on a shared baseline) and pasted into the standard sheet
layout the game expects:

  rows: idle / walk / attack / die / hurt   (hurt reuses idle frames)
  within a row: [down, left, right, up] blocks of per_dir frames

Cavalry's left row is baked as mirrored copies of its right row (the
generated left band is tangled with the band below it); the Ram is a
single side view reused for every direction (unit.gd flips it when
facing left).

Outputs: assets/spearman.png + spearman_frames.json,
         assets/cavalry.png + cavalry_frames.json,
         assets/ram.png + ram_frames.json
Re-runnable: python3 tools/build_unit_sheets.py
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import recut_buildings_smooth as rbs
from extract_buildings import build_alpha

GEN = os.path.expanduser("~/workspace/empire-age/gen")
ASSETS = os.path.join(HERE, "..", "assets")

SPEARMAN_SRC = "media-generation-empire-spearman-sheet-0-2780cc1f-ce26-450e-a696-53863df4f30e.webp"
CAVALRY_SRC = "media-generation-empire-cavalry-sheet-0-3f5c953b-4449-463c-b38f-ee23d72ea6c0.webp"
RAM_SRC = "media-generation-empire-ram-0-758092df-91d5-4a75-ae80-b5fcdca6b455.webp"


def load_comps(filename, min_area=800):
    im = Image.open(os.path.join(GEN, filename)).convert("RGB")
    rgb = np.asarray(im)
    fg = build_alpha(rgb)
    lab, _ = ndimage.label(fg)
    comps = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        area = int((lab[sl] == i).sum())
        if area <= min_area:
            continue
        comps.append({"mask": lab == i, "sl": sl, "area": area,
                      "x0": sl[1].start, "x1": sl[1].stop,
                      "y0": sl[0].start, "y1": sl[0].stop,
                      "w": sl[1].stop - sl[1].start,
                      "h": sl[0].stop - sl[0].start,
                      "cx": (sl[1].start + sl[1].stop) / 2.0,
                      "cy": (sl[0].start + sl[0].stop) / 2.0})
    return rgb, fg, comps


def matte_figure(rgb, fg, mask):
    forbidden = ndimage.binary_dilation(~fg, iterations=2)
    img, lost, _ = rbs.matte_component(rgb, mask, fg, forbidden)
    return img


def fit_figure(img, cell_w, cell_h, baseline, stand_h=None, lie_w=None):
    """Scale a matted figure into a transparent cell image."""
    cell = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    if img.width == 0 or img.height == 0:
        return cell
    if lie_w is not None:
        scale = lie_w / float(img.width)
    else:
        scale = stand_h / float(img.height)
    nw = max(1, round(img.width * scale))
    nh = max(1, round(img.height * scale))
    fig = img.resize((nw, nh), Image.LANCZOS)
    x = (cell_w - nw) // 2
    y = baseline - nh
    cell.alpha_composite(fig, (x, y))
    return cell


def assemble(figs, cell_w, cell_h, baseline, stand_h, lie_w, out_name):
    """figs: {dir: {"idle": img, "walk": [imgs], "attack": [imgs],
    "die": img}} with dir in [down, left, right, up]."""
    dirs = ["down", "left", "right", "up"]
    anims = {"idle": (0, 1), "walk": (1, 4), "attack": (2, 2),
             "die": (3, 1), "hurt": (4, 1)}
    cols = 16
    sheet = Image.new("RGBA", (cols * cell_w, 5 * cell_h), (0, 0, 0, 0))
    for d_i, d in enumerate(dirs):
        f = figs[d]
        for anim, (row, per_dir) in anims.items():
            if anim == "hurt":
                frames = [f["idle"]]
            elif anim == "idle" or anim == "die":
                frames = [f[anim]]
            else:
                frames = f[anim]
            for k in range(per_dir):
                fig = frames[k % len(frames)]
                lie = lie_w if anim == "die" else None
                cell = fit_figure(fig, cell_w, cell_h, baseline,
                                  stand_h=stand_h, lie_w=lie)
                sheet.alpha_composite(
                    cell, ((d_i * per_dir + k) * cell_w, row * cell_h))
    sheet.save(os.path.join(ASSETS, out_name + ".png"))
    manifest = {"cell_w": cell_w, "cell_h": cell_h, "baseline": baseline,
                "animations": {
                    a: {"row": r, "count": p * 4, "per_dir": p}
                    for a, (r, p) in anims.items()}}
    with open(os.path.join(ASSETS, out_name + "_frames.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    print("saved %s.png size=%s" % (out_name, sheet.size))


def pick_attack(standing, exclude=()):
    """Attack frames: the widest figure (thrust) + the last by x."""
    rest = [c for c in standing[1:]
            if all(c is not e for e in exclude)]
    widest = max(rest, key=lambda c: c["w"])
    last = rest[-1]
    out = [widest]
    if last is not widest:
        out.append(last)
    return out


def walk_frames(standing, attack):
    pool = [c for c in standing[1:]
            if all(c is not a for a in attack)]
    if not pool:
        pool = standing[1:]
    out = []
    i = 0
    while len(out) < 4:
        out.append(pool[i % len(pool)])
        i += 1
    return out


# ----------------------------------------------------------------------
# Spearman
# ----------------------------------------------------------------------
def build_spearman():
    rgb, fg, comps = load_comps(SPEARMAN_SRC)
    corpses = sorted([c for c in comps if c["h"] <= 130 and c["w"] >= 250],
                     key=lambda c: c["cy"])
    merged = [c for c in comps if c["h"] > 320][0]
    standing = [c for c in comps if c["h"] >= 200]
    rows = {0: [], 1: [], 2: [], 3: []}
    for c in standing:
        if c["y0"] < 290:
            rows[0].append(c)
        elif c["y0"] < 520:
            rows[1].append(c)
        elif c["y0"] < 810:
            rows[2].append(c)
        else:
            rows[3].append(c)
    # Split the merged row-1 comp: standing figure + corpse at its feet.
    m = merged
    zone = np.zeros_like(m["mask"])
    ys, xs = np.where(m["mask"])
    zone[ys, xs] = ((xs > m["x0"] + 0.47 * m["w"])
                    & (ys > m["y0"] + 0.66 * m["h"]))
    corpse_mask = m["mask"] & zone
    lab, n = ndimage.label(corpse_mask)
    if n:
        sizes = ndimage.sum(corpse_mask, lab, index=np.arange(1, n + 1))
        corpse_mask = lab == (int(np.argmax(sizes)) + 1)
    stand_mask = m["mask"] & ~ndimage.binary_dilation(corpse_mask,
                                                      iterations=3)
    corpse_fig = matte_figure(rgb, fg, corpse_mask)
    merged_fig = matte_figure(rgb, fg, stand_mask)
    row_corpse = {0: corpse_fig,
                  1: matte_figure(rgb, fg, corpses[0]["mask"]),
                  2: matte_figure(rgb, fg, corpses[1]["mask"]),
                  3: matte_figure(rgb, fg, corpses[2]["mask"])}
    figs = {}
    dir_names = ["down", "left", "right", "up"]
    for r in range(4):
        st = sorted(rows[r], key=lambda c: c["x0"])
        attack = pick_attack(st, exclude=(merged,))
        walk = walk_frames(st, attack)
        d = {}
        d["idle"] = merged_fig if st[0] is merged else matte_figure(
            rgb, fg, st[0]["mask"])
        d["walk"] = [merged_fig if c is merged else matte_figure(
            rgb, fg, c["mask"]) for c in walk]
        d["attack"] = [matte_figure(rgb, fg, c["mask"]) for c in attack]
        d["die"] = row_corpse[r]
        figs[dir_names[r]] = d
        print("spearman row %d: standing=%d attack_x=%s"
              % (r, len(st), [c["x0"] for c in attack]))
    assemble(figs, 184, 96, 90, 84, 170, "spearman")


# ----------------------------------------------------------------------
# Cavalry
# ----------------------------------------------------------------------
def build_cavalry():
    rgb, fg, comps = load_comps(CAVALRY_SRC)
    standing = [c for c in comps if c["h"] >= 150]
    fallen = [c for c in comps if c["h"] <= 110 and c["w"] >= 150]

    def by_x(cs):
        return sorted(cs, key=lambda c: c["x0"])

    def merged_mask(cs):
        m = np.zeros_like(fg)
        for c in cs:
            m |= c["mask"]
        return m

    down_st = by_x([c for c in standing if c["y0"] < 60 and c["w"] <= 130])
    down_atk = [c for c in standing if 100 <= c["y0"] <= 115
                or (c["y0"] < 10 and c["h"] > 300)]
    down_die = [c for c in fallen if 240 <= c["cy"] <= 360]
    right_st = by_x([c for c in standing if 560 <= c["y0"] <= 640])
    right_die = [c for c in fallen if 700 <= c["cy"] <= 880]
    up_st = by_x([c for c in standing if c["y0"] >= 850])
    up_die = [c for c in fallen if c["cy"] > 990]
    print("cavalry: down=%d down_atk=%d right=%d up=%d die=%d/%d/%d"
          % (len(down_st), len(down_atk), len(right_st), len(up_st),
             len(down_die), len(right_die), len(up_die)))

    def fig(mask):
        return matte_figure(rgb, fg, mask)

    right = {"idle": fig(right_st[0]["mask"]),
             "walk": [fig(right_st[1]["mask"]), fig(right_st[2]["mask"]),
                      fig(right_st[0]["mask"]), fig(right_st[1]["mask"])],
             "attack": [fig(right_st[3]["mask"]), fig(right_st[2]["mask"])],
             "die": fig(merged_mask(right_die))}
    left = {"idle": right["idle"].transpose(Image.FLIP_LEFT_RIGHT),
            "walk": [f.transpose(Image.FLIP_LEFT_RIGHT)
                     for f in right["walk"]],
            "attack": [f.transpose(Image.FLIP_LEFT_RIGHT)
                       for f in right["attack"]],
            "die": right["die"].transpose(Image.FLIP_LEFT_RIGHT)}
    down = {"idle": fig(down_st[0]["mask"]),
            "walk": [fig(down_st[1]["mask"]), fig(down_st[0]["mask"]),
                     fig(down_st[1]["mask"]), fig(down_st[0]["mask"])],
            "attack": [fig(down_atk[0]["mask"]), fig(down_atk[1]["mask"])],
            "die": fig(down_die[0]["mask"])}
    up = {"idle": fig(up_st[0]["mask"]),
          "walk": [fig(c["mask"]) for c in up_st[1:5]],
          "attack": [fig(up_st[6]["mask"]), fig(up_st[5]["mask"])],
          "die": fig(merged_mask(up_die))}
    assemble({"down": down, "left": left, "right": right, "up": up},
             240, 140, 132, 124, 215, "cavalry")


# ----------------------------------------------------------------------
# Battering Ram — one side view for every direction
# ----------------------------------------------------------------------
def build_ram():
    rgb, fg, comps = load_comps(RAM_SRC)
    big = max(comps, key=lambda c: c["area"])
    fig = matte_figure(rgb, fg, big["mask"])
    one = {"idle": fig, "walk": [fig], "attack": [fig], "die": fig}
    figs = {d: dict(one) for d in ["down", "left", "right", "up"]}
    assemble(figs, 240, 140, 132, 124, None, "ram")


if __name__ == "__main__":
    build_spearman()
    build_cavalry()
    build_ram()
