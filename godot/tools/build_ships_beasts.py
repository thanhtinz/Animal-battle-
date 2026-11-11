#!/usr/bin/env python3
"""Empire Age — SHIPS + BEASTS asset build (self-drawn pass 2, 2026-11-08).

Sources (media-generated, style-gated by eye; sources kept in gen/):
  gen/media-generation-empire-ships-row-*.webp     3 hulls in a row
  gen/media-generation-empire-wolf-poses-*.webp    6 poses
  gen/media-generation-empire-bear-poses-v2-*.webp 6 poses (v1 FAILED
      the gate: pixel-art teddy bear; v2 is the accepted redraw)
  gen/media-generation-empire-boar-poses-*.webp    6 poses

Pipeline: white-page detection (extract_buildings.build_alpha) ->
per-figure smooth matte (recut_buildings_smooth.matte_component) ->
ships saved at native size; beasts normalised into a one-row sheet
+ <species>_frames.json {cell_w, cell_h, baseline, walk, idle, attack,
die, scale}. Enemy ship variants via the faction recolor (red band ->
deep blue); wolf biome variants by fur grading (snow white / desert
sand) on the finished sheet.

Outputs:
  assets/ships/{fishing_boat,transport,war_ship}.png
  assets/enemy/ships/{...}.png
  assets/env/{wolf,bear,boar}.png + _frames.json
  assets/env/{wolf_snow,wolf_desert}.png + _frames.json

Re-runnable: python3 tools/build_ships_beasts.py
"""
import colorsys
import glob
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)
GEN = os.path.join(ROOT, "..", "gen")
ASSETS = os.path.join(ROOT, "assets")

from extract_buildings import build_alpha          # noqa: E402
from recut_buildings_smooth import matte_component  # noqa: E402
from recut_smooth import resize_premul              # noqa: E402
import recolor_enemy                                # noqa: E402


def latest(pattern):
    hits = sorted(glob.glob(os.path.join(GEN, pattern)))
    assert hits, pattern
    return hits[-1]


def figures(path):
    """Matte every sizable component of a white-bg row image.
    Returns RGBA figures sorted left-to-right."""
    rgb = np.asarray(Image.open(path).convert("RGB"))
    fg = build_alpha(rgb)
    lab, n = ndimage.label(fg)
    if n == 0:
        return [], rgb, fg
    sizes = ndimage.sum(fg, lab, index=np.arange(1, n + 1))
    keep = [i + 1 for i, s in enumerate(sizes) if s > 0.004 * fg.size]
    keep.sort(key=lambda i: ndimage.center_of_mass(fg, lab, i)[1])
    out = []
    zero = np.zeros(fg.shape, dtype=bool)
    for i in keep:
        out.append(matte_component(rgb, lab == i, fg, zero)[0])
    return out, rgb, fg


def content_wh(img):
    a = np.asarray(img)[..., 3]
    ys, xs = np.where(a > 8)
    return int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)


# ---------------------------------------------------------------- ships
def build_ships():
    figs, _, _ = figures(latest("media-generation-empire-ships-row-*.webp"))
    assert len(figs) >= 3, f"ships: expected >=3 figures, got {len(figs)}"
    figs = figs[:3]
    names = ["fishing_boat", "transport", "war_ship"]
    out_dir = os.path.join(ASSETS, "ships")
    out_e = os.path.join(ASSETS, "enemy", "ships")
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(out_e, exist_ok=True)
    for name, fig in zip(names, figs):
        p = os.path.join(out_dir, name + ".png")
        fig.save(p)
        recolor_enemy.recolor(fig).save(os.path.join(out_e, name + ".png"))
        print("ship:", name, fig.size)


# ---------------------------------------------------------------- beasts
BEASTS = {
    # stand_h: sheet px height of standing poses; world_len: in-game
    # body length in world px (scale = world_len / idle figure width)
    "wolf": dict(src="media-generation-empire-wolf-poses-*.webp",
                 stand_h=118, world_len=30,
                 walk=[0, 1, 2, 3], idle=3, attack=4, die=5),
    "bear": dict(src="media-generation-empire-bear-poses-v2-*.webp",
                 stand_h=170, world_len=44,
                 walk=[0, 1, 2, 3], idle=2, attack=4, die=5),
    "boar": dict(src="media-generation-empire-boar-poses-*.webp",
                 stand_h=128, world_len=34,
                 walk=[0, 1, 3], idle=2, attack=4, die=5),
}


def build_beast(species, cfg):
    figs, _, _ = figures(latest(cfg["src"]))
    assert len(figs) >= 6, f"{species}: expected 6 poses, got {len(figs)}"
    figs = figs[:6]
    # Matte sanity: the dead pose (index 5) must be the flattest figure.
    aspects = []
    for f in figs:
        w, h = content_wh(f)
        aspects.append(h / float(w))
    assert aspects[cfg["die"]] == min(aspects), \
        f"{species}: die pose is not the flattest {aspects}"
    th = cfg["stand_h"]
    dims = [content_wh(f) for f in figs]
    max_h = max(dims[i][1] for i in range(len(figs)) if i != cfg["die"])
    # Upright poses normalise by height; stretched poses (run / lunge /
    # dead) take the median upright scale so they keep their relative
    # size instead of ballooning.
    up = [th / float(dims[i][1]) for i in range(len(figs))
          if i != cfg["die"] and dims[i][1] >= 0.78 * max_h]
    med = float(np.median(up))
    out_figs = []
    for i, f in enumerate(figs):
        w, h = dims[i]
        s = th / float(h) if (i != cfg["die"] and h >= 0.78 * max_h) else med
        nw, nh = max(2, int(round(w * s))), max(2, int(round(h * s)))
        out_figs.append(resize_premul(f, (nw, nh)))
    cw = max(f.size[0] for f in out_figs) + 12
    ch = max(f.size[1] for f in out_figs) + 12
    baseline = ch - 6
    sheet = Image.new("RGBA", (cw * len(out_figs), ch), (0, 0, 0, 0))
    for i, f in enumerate(out_figs):
        sheet.paste(f, (i * cw + (cw - f.size[0]) // 2, baseline - f.size[1]),
                    f)
    idle_w = out_figs[cfg["idle"]].size[0]
    meta = dict(cell_w=cw, cell_h=ch, baseline=baseline,
                walk=cfg["walk"], idle=cfg["idle"], attack=cfg["attack"],
                die=cfg["die"], scale=round(cfg["world_len"] / idle_w, 4))
    print("  world widths:", [round(f.size[0] * meta["scale"], 1)
                              for f in out_figs])
    env = os.path.join(ASSETS, "env")
    sheet.save(os.path.join(env, species + ".png"))
    with open(os.path.join(env, species + "_frames.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
    print("beast:", species, sheet.size, meta)
    return sheet, meta


def wolf_variants(sheet, meta):
    """Biome fur grades of the finished wolf sheet (alpha untouched)."""
    env = os.path.join(ASSETS, "env")
    arr = np.asarray(sheet).astype(np.float32)
    r, g, b, a = arr[..., 0], arr[..., 1], arr[..., 2], arr[..., 3]
    mx = arr[..., :3].max(axis=2)
    mn = arr[..., :3].min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1.0), 0.0)
    fur = (a > 8) & (sat < 0.38)  # grey coat incl. shading + pale belly
    # Snow: lift the coat toward white, keeping the shading ratio.
    v = mx / 255.0
    lift = 0.45 + 0.55 * v
    snow = arr.copy()
    for ch in range(3):
        snow[..., ch] = np.where(fur, arr[..., ch] * 0.25 + 255.0 * lift * 0.75,
                                 arr[..., ch])
    Image.fromarray(np.clip(snow, 0, 255).astype(np.uint8), "RGBA").save(
        os.path.join(env, "wolf_snow.png"))
    # Desert: warm sand multiply + slight desaturation.
    des = arr.copy()
    grey = (0.299 * r + 0.587 * g + 0.114 * b)[..., None]
    mixed = arr[..., :3] * 0.72 + grey * 0.28
    des[..., 0] = np.where(a > 8, mixed[..., 0] * 1.10, r)
    des[..., 1] = np.where(a > 8, mixed[..., 1] * 0.97, g)
    des[..., 2] = np.where(a > 8, mixed[..., 2] * 0.74, b)
    Image.fromarray(np.clip(des, 0, 255).astype(np.uint8), "RGBA").save(
        os.path.join(env, "wolf_desert.png"))
    for name in ("wolf_snow", "wolf_desert"):
        with open(os.path.join(env, name + "_frames.json"), "w") as fh:
            json.dump(meta, fh, indent=1)
        print("wolf variant:", name)


def main():
    build_ships()
    metas = {}
    for species, cfg in BEASTS.items():
        sheet, meta = build_beast(species, cfg)
        metas[species] = (sheet, meta)
    wolf_variants(*metas["wolf"])


if __name__ == "__main__":
    main()
