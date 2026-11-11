#!/usr/bin/env python3
"""build_skill_assets.py — Empire Age 13v: procedural VFX textures
+ official hero weapons.

Part A: effect textures for the skill VFX layer (GPUParticles2D
emitters + shader sprites in scripts/skill_fx.gd). All textures are
generated — soft radial glow disc, glow ring, petal, ice shard,
spark streak, snowflake — white shapes whose colour comes from the
emitter's modulate / colour ramp at runtime.

  assets/vfx/fx_glow.png    128x128 soft radial disc
  assets/vfx/fx_ring.png    128x128 thin glowing ring
  assets/vfx/fx_petal.png    32x32  falling petal
  assets/vfx/fx_shard.png    32x32  ice shard / crystal sliver
  assets/vfx/fx_streak.png   64x16  elongated spark streak
  assets/vfx/fx_flake.png    32x32  snowflake

Part B: the four OFFICIAL weapons, cut from Tín's supplied sheet
(~/workspace/user/files/63B65487-...jpg, left→right: sword,
flower staff, ice spear, sun staff). White background is keyed out
by flood-fill from the borders (so enclosed whites — the sun orb,
the flower heart — survive), edges are defringed, and each weapon
is fitted onto a 2x-resolution canvas versus the 13n drawn weapons
(hero_rig.json grip updated to the new pixels + "wscale": 0.5 so
the on-screen size is unchanged but twice as sharp):

  assets/hero_weapons/<char>.png   (overwritten)
  assets/hero_rig.json             (weapon grip + wscale per char)

Grip points: the hand holds the weapon at the same height fraction
as the drawn weapons used (sword .833, sceptre .775, spear .714,
staff .783 of the canvas height) — measured on the official art:
sword = wrapped grip below the crossguard, sceptre = bare shaft,
spear = shaft below the ribbons, staff = bare shaft.
"""
import json
import math
import os
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ASSETS = os.path.join(ROOT, "assets")
VFX_DIR = os.path.join(ASSETS, "vfx")
WEAPONS_DIR = os.path.join(ASSETS, "hero_weapons")
SHEET = os.path.expanduser(
    "~/workspace/user/files/63B65487-8D21-427D-92F9-5288B7A0A0EC-"
    "photo-7C5B7675-D0A3-4323-9C8A-3C42DC109056.jpg")


# ---------------------------------------------------------------- textures
def _radial(size, inner=0.0, outer=1.0, power=2.0):
    y, x = np.mgrid[0:size, 0:size]
    c = (size - 1) / 2.0
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2) / c
    t = np.clip((r - inner) / max(outer - inner, 1e-6), 0.0, 1.0)
    return (1.0 - t) ** power


def _save_rgba(name, alpha, rgb=(255, 255, 255)):
    img = np.zeros((alpha.shape[0], alpha.shape[1], 4), dtype=np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = rgb
    img[..., 3] = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(VFX_DIR, name))
    print("vfx tex", name)


def make_textures():
    os.makedirs(VFX_DIR, exist_ok=True)
    _save_rgba("fx_glow.png", _radial(128, power=1.6))
    _save_rgba("fx_ring.png", _radial(128, inner=0.78, outer=0.97, power=1.0)
               * _radial(128, inner=0.0, outer=1.0, power=0.4))
    # petal: an ellipse leaf with a centre vein, slightly rotated
    p = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(p)
    d.ellipse([18, 6, 46, 58], fill=(255, 255, 255, 235))
    d.line([(32, 10), (32, 54)], fill=(255, 255, 255, 90), width=3)
    p = p.rotate(24, resample=Image.BICUBIC).resize((32, 32), Image.LANCZOS)
    p.save(os.path.join(VFX_DIR, "fx_petal.png"))
    print("vfx tex fx_petal.png")
    # ice shard: faceted sliver
    s = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(s)
    d.polygon([(32, 2), (44, 26), (38, 62), (27, 62), (21, 24)],
              fill=(235, 248, 255, 245))
    d.polygon([(32, 2), (44, 26), (36, 60), (31, 60)], fill=(170, 215, 245, 200))
    d.line([(32, 4), (32, 60)], fill=(255, 255, 255, 160), width=2)
    s = s.resize((32, 32), Image.LANCZOS)
    s.save(os.path.join(VFX_DIR, "fx_shard.png"))
    print("vfx tex fx_shard.png")
    # spark streak: horizontal capsule with hot core
    st = Image.new("RGBA", (64, 16), (0, 0, 0, 0))
    px = st.load()
    for yy in range(16):
        for xx in range(64):
            dx = abs(xx - 31.5) / 31.5
            dy = abs(yy - 7.5) / 7.5
            a = max(0.0, (1.0 - dx * dx) * (1.0 - dy * dy))
            px[xx, yy] = (255, 255, 255, int(255 * a ** 0.7))
    st.save(os.path.join(VFX_DIR, "fx_streak.png"))
    print("vfx tex fx_streak.png")
    # snowflake: six-arm asterisk with side ticks
    f = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(f)
    cx = cy = 32
    for k in range(6):
        a = math.radians(60 * k)
        x1, y1 = cx + 26 * math.cos(a), cy + 26 * math.sin(a)
        d.line([(cx, cy), (x1, y1)], fill=(255, 255, 255, 230), width=3)
        for sgn in (-1, 1):
            b = a + sgn * math.radians(38)
            mx, my = cx + 16 * math.cos(a), cy + 16 * math.sin(a)
            d.line([(mx, my), (mx + 9 * math.cos(b), my + 9 * math.sin(b))],
                   fill=(255, 255, 255, 200), width=2)
    f = f.resize((32, 32), Image.LANCZOS)
    f.save(os.path.join(VFX_DIR, "fx_flake.png"))
    print("vfx tex fx_flake.png")


# ---------------------------------------------------------------- weapons
# Column bands of the 4 weapons in the source sheet (measured:
# content runs [84,269) [338,587) [684,872) [938,1250) at 1290 wide).
BANDS = {"ngan_ky": (60, 300), "kim_hoa": (315, 610),
         "lam_bao": (660, 895), "bach_sa": (915, 1275)}
# Grip height fraction of the FINAL canvas, measured on the
# official art: the hand sits mid-handle / on the bare shaft
# (sword: below the crossguard; sceptre: below the tassel;
# spear: on the shaft under the ribbons; staff: mid-shaft).
GRIP_FRAC = {"ngan_ky": 0.78, "kim_hoa": 0.67,
             "lam_bao": 0.68, "bach_sa": 0.75}
# Final canvas (w, h) at 2x the drawn weapons' resolution.
CANVAS = {"ngan_ky": (34, 88), "kim_hoa": (30, 84),
          "lam_bao": (26, 116), "bach_sa": (34, 96)}


def _key_out_white(im):
    """Flood-fill the white background from the borders to alpha 0,
    then defringe: semi-key pixels whose colour is near-white."""
    a = np.asarray(im.convert("RGB")).astype(np.int32)
    h, w = a.shape[:2]
    lum = a.mean(axis=2)
    bg_like = lum > 238
    seen = np.zeros((h, w), dtype=bool)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg_like[y, x] and not seen[y, x]:
                seen[y, x] = True
                dq.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if bg_like[y, x] and not seen[y, x]:
                seen[y, x] = True
                dq.append((x, y))
    while dq:
        x, y = dq.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny, nx] \
                    and bg_like[ny, nx]:
                seen[ny, nx] = True
                dq.append((nx, ny))
    alpha = np.where(seen, 0, 255).astype(np.uint8)
    out = np.dstack([np.asarray(im.convert("RGB")), alpha])
    # defringe: pixels touching transparency and still near-white
    # get their halo pulled toward the nearest solid colour by
    # simply darkening them toward the local average (cheap + fine
    # at final size).
    img = Image.fromarray(out, "RGBA")
    return img


def cut_weapons():
    sheet = Image.open(SHEET).convert("RGB")
    rig_path = os.path.join(ASSETS, "hero_rig.json")
    rig = json.load(open(rig_path))
    for char, (x0, x1) in BANDS.items():
        crop = sheet.crop((x0, 0, x1, sheet.height))
        keyed = _key_out_white(crop)
        bbox = keyed.getchannel("A").getbbox()
        keyed = keyed.crop(bbox)
        cw, ch = CANVAS[char]
        keyed.thumbnail((cw - 2, ch - 2), Image.LANCZOS)
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        ox = (cw - keyed.width) // 2
        oy = (ch - keyed.height) // 2
        canvas.alpha_composite(keyed, (ox, oy))
        out_path = os.path.join(WEAPONS_DIR, char + ".png")
        canvas.save(out_path)
        # grip x: the shaft column near the grip row — the column
        # with the most opaque pixels in a small window around the
        # grip row, searched near the canvas centre (ribbons and
        # tassels hang off-centre and must not pull the grip).
        gy = int(round(GRIP_FRAC[char] * (ch - 1)))
        alpha = np.asarray(canvas.getchannel("A"))
        win = alpha[max(0, gy - 5):gy + 6, :]
        colsum = (win > 30).sum(axis=0).astype(float)
        lo = int(cw * 0.3)
        hi = int(cw * 0.7)
        gx = lo + int(np.argmax(colsum[lo:hi])) if hi > lo else cw // 2
        rig["chars"][char]["weapon"] = {
            "tex": "hero_weapons/%s.png" % char,
            "grip": [gx, gy], "wscale": 0.5}
        print("weapon", char, "canvas", (cw, ch), "grip", (gx, gy))
    with open(rig_path, "w") as f:
        json.dump(rig, f)
    print("hero_rig.json weapon entries updated")


if __name__ == "__main__":
    make_textures()
    cut_weapons()
