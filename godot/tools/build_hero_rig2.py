#!/usr/bin/env python3
"""Empire Age 14c — cutout rigs for the four new heroes.

tools/build_hero_rig.py hand-authored the first four heroes' part
polygons from their shipped sprites. The new four arrive as
turnaround sheets (see build_hero_assets2.py), so this builder
derives the equivalent rig automatically from the final sprites:

  * body mask = sprite alpha, minus the WEAPON pixels (colour masks
    for Lôi Chấn's steel blades and Xích Diệm's black fan, plus a
    per-row run cleaning that drops separated thin runs in the
    weapon zones — Phong Linh's bow, Thạch Sơn's hammer — so the
    rig's own weapon sprite is the only weapon drawn);
  * parts (back / leg / shin / shoe / torso / arm) are polygon bands
    fitted to the measured silhouette, claimed in the same order
    and with the same pivot/z conventions as build_hero_rig.py, so
    Unit._rig_pose animates them identically (rest-pose reassembly
    is exact over the body mask by construction);
  * weapons are DRAWN here in the painted dialect (twin curved
    blades / black iron fan / longbow / stone hammer) — never photo
    cutouts — one texture per hero, grip + wscale like the 13v set;
  * the four entries are merged into assets/hero_rig.json.

Run from the godot/ directory:  python3 tools/build_hero_rig2.py
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ASSETS = os.path.join(ROOT, "assets")
PARTS_DIR = os.path.join(ASSETS, "hero_parts")
WEAPONS_DIR = os.path.join(ASSETS, "hero_weapons")
RIG_JSON = os.path.join(ASSETS, "hero_rig.json")
DIRS5 = ["s", "se", "e", "ne", "n"]
MIRROR = {"se": ("sw", True), "e": ("w", True), "ne": ("nw", True),
          "s": ("s", False), "n": ("n", False)}

SS = 4  # weapon draw supersample


# ======================================================================
# Weapons — drawn at 4x, downscaled. Business end points UP from the
# grip, exactly like the 13v weapon set (rest angles hang them).
# ======================================================================
def _blade(dr, pts, fill, edge):
    dr.polygon(pts, fill=fill)
    dr.line(pts + [pts[0]], fill=edge, width=3)


def draw_loi_chan() -> Image.Image:
    W, H = 46 * SS, 100 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 23 * SS, 74 * SS
    # Far blade (darker), sweeping up-right. 14c-fix: steel fills
    # deepened — at game scale the original near-white fills read
    # as plain white sticks against the grass.
    _blade(dr, [(gx, gy), (gx + 9 * SS, gy - 26 * SS), (gx + 15 * SS, gy - 52 * SS),
                (gx + 12 * SS, gy - 66 * SS), (gx + 3 * SS, gy - 44 * SS),
                (gx - 3 * SS, gy - 20 * SS)], (112, 122, 152, 255), (66, 76, 104, 255))
    # Near blade, sweeping up-left, brighter steel + lightning edge.
    _blade(dr, [(gx, gy), (gx - 10 * SS, gy - 28 * SS), (gx - 16 * SS, gy - 54 * SS),
                (gx - 13 * SS, gy - 68 * SS), (gx - 3 * SS, gy - 46 * SS),
                (gx + 3 * SS, gy - 20 * SS)], (156, 170, 204, 255), (122, 178, 255, 255))
    dr.line([(gx - 13 * SS, gy - 68 * SS), (gx - 16 * SS, gy - 54 * SS),
             (gx - 10 * SS, gy - 28 * SS)], fill=(170, 216, 255, 255), width=2 * SS)
    # Hilts + twin pommels below the grip.
    dr.rectangle([gx - 3 * SS, gy - 6 * SS, gx + 3 * SS, gy + 12 * SS], fill=(52, 40, 74, 255))
    dr.rectangle([gx - 8 * SS, gy - 8 * SS, gx + 8 * SS, gy - 4 * SS], fill=(120, 110, 150, 255))
    dr.ellipse([gx - 3 * SS, gy + 12 * SS, gx + 3 * SS, gy + 18 * SS], fill=(140, 130, 170, 255))
    return im.resize((46, 100), Image.LANCZOS)


def draw_xich_diem() -> Image.Image:
    W, H = 84 * SS, 72 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 42 * SS, 60 * SS
    R = 52 * SS
    a0, a1 = math.radians(-168), math.radians(-12)
    # Cloth: fan of triangles from the pivot.
    steps = 26
    rim = [(gx + R * math.cos(a0 + (a1 - a0) * i / steps),
            gy + R * math.sin(a0 + (a1 - a0) * i / steps)) for i in range(steps + 1)]
    dr.polygon([(gx, gy)] + rim, fill=(24, 20, 26, 255))
    # Flame motif: layered teardrops over the cloth.
    for fx, fs, col in [(0.30, 15, (214, 84, 30, 255)), (0.52, 19, (226, 106, 34, 255)),
                        (0.72, 14, (206, 74, 28, 255)), (0.41, 10, (244, 164, 60, 255)),
                        (0.62, 11, (246, 176, 66, 255)), (0.52, 7, (252, 208, 106, 255))]:
        cx = gx + R * 0.62 * math.cos(a0 + (a1 - a0) * fx)
        cy = gy + R * 0.62 * math.sin(a0 + (a1 - a0) * fx)
        s = fs * SS
        dr.polygon([(cx - s * 0.42, cy + s * 0.4), (cx, cy - s * 0.75),
                    (cx + s * 0.42, cy + s * 0.4), (cx, cy + s * 0.12)], fill=col)
    # Ribs + rim + pivot.
    for i in range(steps + 1):
        if i % 2 == 0:
            dr.line([(gx, gy), rim[i]], fill=(96, 78, 52, 255), width=max(2, SS // 2))
    dr.line(rim, fill=(168, 132, 62, 255), width=2 * SS)
    dr.rectangle([gx - 2 * SS, gy, gx + 2 * SS, gy + 9 * SS], fill=(40, 32, 30, 255))
    dr.ellipse([gx - 3 * SS, gy - 3 * SS, gx + 3 * SS, gy + 3 * SS], fill=(196, 152, 74, 255))
    return im.resize((84, 72), Image.LANCZOS)


def draw_phong_linh() -> Image.Image:
    W, H = 36 * SS, 118 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 15 * SS, 59 * SS
    # String (straight chord on the left), limbs curving right.
    dr.line([(9 * SS, 5 * SS), (9 * SS, 113 * SS)], fill=(226, 230, 224, 255), width=max(2, SS // 2))
    limb = [(9 * SS, 5 * SS), (20 * SS, 16 * SS), (26 * SS, 34 * SS),
            (27 * SS, 59 * SS), (26 * SS, 84 * SS), (20 * SS, 102 * SS),
            (9 * SS, 113 * SS)]
    dr.line(limb, fill=(122, 84, 50, 255), width=3 * SS, joint="curve")
    dr.line(limb, fill=(168, 124, 78, 255), width=SS, joint="curve")
    # Silver wraps + feather cluster at the grip's top.
    for wy in (30, 59, 88):
        dr.line([(24 * SS, (wy - 5) * SS), (28 * SS, (wy + 5) * SS)],
                fill=(206, 212, 218, 255), width=2 * SS)
    for dx, dy, ln in [(-4, -16, 15), (1, -19, 18), (6, -15, 13)]:
        dr.polygon([(gx + dx * SS, gy + dy * SS), (gx + (dx + 3) * SS, gy + (dy + ln) * SS),
                    (gx + (dx - 3) * SS, gy + (dy + ln) * SS)], fill=(232, 236, 238, 255))
    dr.rectangle([gx - 2 * SS, gy - 6 * SS, gx + 3 * SS, gy + 6 * SS], fill=(84, 58, 34, 255))
    return im.resize((36, 118), Image.LANCZOS)


def draw_thach_son() -> Image.Image:
    W, H = 44 * SS, 108 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 22 * SS, 34 * SS
    # Handle (through the grip, down to the pommel).
    dr.rectangle([gx - 2 * SS, 16 * SS, gx + 2 * SS, 104 * SS], fill=(104, 78, 48, 255))
    dr.rectangle([gx - 2 * SS, 16 * SS, gx, 104 * SS], fill=(140, 108, 66, 255))
    # Stone head: blocky grey mass with bronze bands + crack lines.
    dr.rectangle([6 * SS, 3 * SS, 38 * SS, 27 * SS], fill=(128, 126, 120, 255))
    dr.rectangle([6 * SS, 3 * SS, 38 * SS, 9 * SS], fill=(158, 155, 146, 255))
    dr.rectangle([6 * SS, 21 * SS, 38 * SS, 27 * SS], fill=(104, 102, 96, 255))
    dr.rectangle([6 * SS, 12 * SS, 38 * SS, 15 * SS], fill=(146, 110, 56, 255))
    dr.rectangle([19 * SS, 3 * SS, 25 * SS, 27 * SS], fill=(146, 110, 56, 255))
    dr.line([(10 * SS, 18 * SS), (16 * SS, 24 * SS), (22 * SS, 20 * SS)],
            fill=(84, 82, 78, 255), width=max(2, SS // 2))
    dr.line([(28 * SS, 6 * SS), (33 * SS, 11 * SS)], fill=(84, 82, 78, 255),
            width=max(2, SS // 2))
    dr.ellipse([gx - 3 * SS, 102 * SS, gx + 3 * SS, 107 * SS], fill=(146, 110, 56, 255))
    return im.resize((44, 108), Image.LANCZOS)


WEAPON_DRAW = {"loi_chan": draw_loi_chan, "xich_diem": draw_xich_diem,
               "phong_linh": draw_phong_linh, "thach_son": draw_thach_son}
GRIPS = {"loi_chan": [23, 74], "xich_diem": [42, 60],
         "phong_linh": [15, 59], "thach_son": [22, 34]}


# ======================================================================
# Body masks: alpha minus weapon pixels.
# ======================================================================
def _components(mask: np.ndarray) -> list:
    """4-connected components of a boolean mask: list of (y, x)
    pixel lists."""
    from collections import deque
    ys, xs = np.where(mask)
    seen = set(zip(ys.tolist(), xs.tolist()))  # (y, x)
    comps = []
    while seen:
        seed = seen.pop()
        q = deque([seed])
        pts = [seed]
        while q:
            cy, cx = q.popleft()
            for ny, nx in ((cy, cx + 1), (cy, cx - 1), (cy + 1, cx), (cy - 1, cx)):
                if (ny, nx) in seen:
                    seen.discard((ny, nx))
                    q.append((ny, nx))
                    pts.append((ny, nx))
        comps.append(pts)
    return comps


def _xich_diem_fan(spr: Image.Image):
    """Xích Diệm's war fan in a sprite: (strip mask, grip point).

    Black + flame-orange pixels form the fan, but her robe's gold
    flame embroidery and belt match the same colour tests. Measured
    on the chibi sprites, the fan is a component of >= 45 px riding
    at torso height in every view (299 px in front view, 60–76 in
    side/back views where it is partly occluded), while embroidery
    patches are <= ~35 px and the belt bits sit lower (y >= 59) away
    from the fan. Strip fan components plus any small component
    whose bbox touches a fan bbox (fan rim fragments); the grip is
    the stripped pixel closest to the body's grip point (centre,
    60% height) — her fingers wrap the fan's inner lower rim."""
    rgb = np.asarray(spr.convert("RGB")).astype(np.int32)
    a = np.asarray(spr.getchannel("A")) > 40
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mx = rgb.max(axis=2)
    fan = ((mx < 80) | ((r > 185) & (g > 55) & (g < 155) & (b < 70))) & a
    h, w = a.shape
    torso_rows = a[int(h * 0.30):int(h * 0.55)]
    cols = np.where(torso_rows.any(axis=0))[0]
    bcx = float(cols.mean()) if len(cols) else w / 2.0
    comps = []
    for pts in _components(fan):
        if len(pts) < 15:
            continue
        ys = [p[0] for p in pts]
        xs = [p[1] for p in pts]
        comps.append((pts, min(xs), max(xs), min(ys), max(ys)))
    prim = [c for c in comps if len(c[0]) >= 45]
    strip = np.zeros_like(a)
    grip = None
    if prim:
        boxes = [(x0 - 2, x1 + 2, y0 - 2, y1 + 2)
                 for _p, x0, x1, y0, y1 in prim]
        target = np.array([bcx, h * 0.60])
        best_d = None
        for pts, x0, x1, y0, y1 in comps:
            take = len(pts) >= 45 or any(
                x0 <= bx1 and x1 >= bx0 and y0 <= by1 and y1 >= by0
                for bx0, bx1, by0, by1 in boxes)
            if not take:
                continue
            for py, px in pts:
                strip[py, px] = True
                dist = (px - target[0]) ** 2 + (py - target[1]) ** 2
                if best_d is None or dist < best_d:
                    best_d = dist
                    grip = [round(float(px), 1), round(float(py), 1)]
    return strip, grip


def body_mask(hero: str, spr: Image.Image) -> np.ndarray:
    a = np.asarray(spr.getchannel("A")).astype(np.int32) > 40
    rgb = np.asarray(spr.convert("RGB")).astype(np.int32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    h, w = a.shape
    # Body centre column from the torso rows (of the ORIGINAL alpha).
    torso_rows = a[int(h * 0.30):int(h * 0.55)]
    cols = np.where(torso_rows.any(axis=0))[0]
    cx = float(cols.mean()) if len(cols) else w / 2.0
    if hero == "loi_chan":
        # Pale steel = the twin blades. 14c-fix2: in the chibi art
        # his silver lamellar VEST and white under-skirt are just as
        # pale, and they sit INSIDE the body's main alpha run — so
        # only strip steel pixels that lie OUTSIDE their row's main
        # run (the run covering the body centre). The blades ride in
        # their own side runs; the few grip-row pixels fused into
        # the main run stay hidden under the rig's drawn blades.
        steel = (mx - mn < 64) & (mx > 140) & (b >= r - 6)
        strip = np.zeros_like(a)
        for y in range(h):
            row = a[y]
            if not row.any():
                continue
            x = 0
            main = None
            while x < w:
                if row[x]:
                    x0 = x
                    while x < w and row[x]:
                        x += 1
                    if x0 - 4 <= cx <= x - 1 + 4:
                        main = (x0, x - 1)
                else:
                    x += 1
            srow = steel[y]
            if main is not None:
                srow = srow.copy()
                srow[main[0]:main[1] + 1] = False
            strip[y] = srow
        a &= ~strip
    elif hero == "xich_diem":
        # Black + flame-orange = her war fan (see _xich_diem_fan).
        strip, _grip = _xich_diem_fan(spr)
        a &= ~strip
    # Per-row run cleaning in the weapon zones (outer silhouette):
    # drop runs separated from the body run by more than 2 px (bow
    # limbs, hammer head, floating ribbons/arcs). 14c-fix2: the old
    # thin-low exception also ate Phong Linh's braid and Xích
    # Diệm's hair tips — thin runs NEAR the body are costume, keep
    # them; weapons are handled by distance + the colour rules.
    torso_rows = a[int(h * 0.30):int(h * 0.55)]
    cols = np.where(torso_rows.any(axis=0))[0]
    if len(cols):
        cx = float(cols.mean())
    out = a.copy()
    for y in range(h):
        row = a[y]
        if not row.any():
            continue
        runs = []
        x = 0
        while x < w:
            if row[x]:
                x0 = x
                while x < w and row[x]:
                    x += 1
                runs.append((x0, x - 1))
            else:
                x += 1
        body_runs = [rn for rn in runs if rn[0] - 4 <= cx <= rn[1] + 4]
        keep = set()
        for rn in runs:
            if rn in body_runs:
                keep.add(rn)
                continue
            near = any(rn[1] >= br[0] - 2 and rn[0] <= br[1] + 2 for br in body_runs)
            if near:
                keep.add(rn)
        for rn in runs:
            if rn not in keep:
                out[y, rn[0]:rn[1] + 1] = False
    return out


# ======================================================================
# Segmentation: polygon bands fitted to the silhouette, claimed in
# build_hero_rig.py's order (back, under, legs, shins, shoes, torso,
# arms) so the pose code treats them identically.
# ======================================================================
def poly_mask(w: int, h: int, poly: list) -> np.ndarray:
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).polygon([(float(x), float(y)) for x, y in poly], fill=1)
    return np.asarray(m) > 0


def measure(mask: np.ndarray) -> dict:
    h, w = mask.shape
    rows = mask.any(axis=1)
    ys = np.where(rows)[0]
    top, bot = int(ys.min()), int(ys.max())
    widths = mask.sum(axis=1)
    xs = [np.where(mask[y])[0] for y in range(h)]
    xmins = np.array([x.min() if len(x) else 0 for x in xs], dtype=float)
    xmaxs = np.array([x.max() if len(x) else w - 1 for x in xs], dtype=float)
    head = mask[top:top + 16]
    head_cx = float(np.where(head.any(axis=0))[0].mean())
    # Neck: narrowest row under the head mass. 14c-fix2: the
    # turnarounds are now CHIBI (head ~44% of height, matching the
    # original four), so the pinch under the chin sits far lower
    # than the tall figures' — search the band under the head mass
    # instead of the old fixed top rows.
    ink_h = bot - top + 1
    neck_y = top + int(ink_h * 0.44)
    best = None
    for y in range(top + int(ink_h * 0.34),
                   min(top + int(ink_h * 0.58), h - 1)):
        if best is None or widths[y] < best:
            best = widths[y]
            neck_y = y
    # 14c-fix2: waist/hip follow the chibi template measured from
    # the original four (hip/leg split at ~0.82 of height — their
    # rig leg pivots sit at y 72–78 of 92), not the tall figures'
    # 0.565/0.63.
    waist_y = int(h * 0.68)
    hip_y = int(h * 0.815)
    waist_w = float(widths[waist_y])
    cx = float((xmins[waist_y] + xmaxs[waist_y]) / 2.0)
    return {"top": top, "bot": bot, "neck": neck_y, "waist": waist_y,
            "hip": hip_y, "cx": cx, "head_cx": head_cx, "waist_w": waist_w,
            "xmins": xmins, "xmaxs": xmaxs, "widths": widths}


# Per-hero layout: gown (robe panels + shoe tips) vs legs (thigh/shin).
# 14c-fix2: hair fractions re-based on the chibi sheets (the head
# alone is ~0.42–0.50 of height now; Xích Diệm's hair mass runs
# nearly to the hem in the back views).
LAYOUT = {
    "loi_chan": {"kind": "gown", "hair": 0.42},
    "xich_diem": {"kind": "gown", "hair": 0.72},
    "phong_linh": {"kind": "legs", "hair": 0.40},
    "thach_son": {"kind": "gown", "hair": 0.32},
}
# Weapon arm per authored dir + rest angles (authored for arm_r;
# the mirror step flips them), following the 13v set's conventions.
WEAPON_ARM = {
    "loi_chan": {"s": "arm_r", "se": "arm_r", "e": "arm_r", "ne": "arm_r", "n": "arm_r"},
    "xich_diem": {"s": "arm_l", "se": "arm_l", "e": "arm_r", "ne": "arm_r", "n": "arm_r"},
    "phong_linh": {"s": "arm_l", "se": "arm_l", "e": "arm_r", "ne": "arm_r", "n": "arm_l"},
    "thach_son": {"s": "arm_r", "se": "arm_r", "e": "arm_r", "ne": "arm_r", "n": "arm_r"},
}
RESTS = {
    "loi_chan": {"s": 150, "se": 140, "e": 128, "ne": 150, "n": 165},
    "xich_diem": {"s": 18, "se": 22, "e": 30, "ne": 30, "n": 30},
    "phong_linh": {"s": 10, "se": 12, "e": 16, "ne": 10, "n": 10},
    "thach_son": {"s": 155, "se": 145, "e": 130, "ne": 155, "n": 170},
}
FOLLOWS = {"loi_chan": 0.85, "xich_diem": 0.6, "phong_linh": 0.5, "thach_son": 0.8}
# 14c-fix4: Xích Diệm's BACK views. The source art tucks her fan
# behind the hair mass, so the fan-derived grip lands inside the
# hair at shoulder height (y 43-47) and with the front-view rests
# (14-16 deg) the fan rendered floating over her back hair — the
# owner's "cầm quạt sau lưng vậy". Author her grip at her hand
# beside her hip instead (hip-height grips are what every other
# hero's back views already use). nw inherits hand + rest
# through the mirror step.
# 14c-fix4-bis (owner, same day): the first fix4 rests (108/118)
# tipped the fan DOWN beside her skirt and read as drooping —
# "Kiểu cầm quạt phía trước và bên hông thôi". Back rests now
# equal the side rests (ne/n = 30, nw = -30 via mirror): the fan
# presents OPEN at her side by the hip, top edge up/outward,
# exactly the read of the e/w views. Grips unchanged from fix4.
BACK_FAN_HAND = {"ne": [45.0, 55.0], "n": [47.0, 57.0]}
# 14c-fix4-ter (owner, same day): "Quay sau lưng bỏ quạt luôn" —
# in the back directions Xích Diệm's fan is not rendered AT ALL.
# The rig compose code (unit.gd _rig_build_dir / _rig_pose) draws
# no weapon when a direction's "weapon" entry is an empty dict,
# so the builder emits {} for her back dirs; nw inherits through
# the mirror step and is suppressed by the same set. (Her fan
# pixels are already stripped from the body parts by body_mask,
# so hiding the weapon sprite removes the fan completely.)
# Owner generalised the rule the same evening ("Mấy nhân vật khác
# nữa"): NO hero renders a weapon in the back directions. Front/
# side weapons stay exactly as authored.
NO_WEAPON_DIRS = {h: {"ne", "n", "nw"} for h in
                  ("loi_chan", "xich_diem", "phong_linh", "thach_son")}
WCLASS = {"loi_chan": "sword", "xich_diem": "sword",
          "phong_linh": "bow", "thach_son": "sword"}
TUNING = {
    "loi_chan": {"leg_amp": 0.34, "arm_amp": 0.30, "cadence": 1.05, "bob": 2.4,
                 "knee_fold": 0.0, "hem_lag": 0.55, "shoe_amp": 1.1},
    "xich_diem": {"leg_amp": 0.28, "arm_amp": 0.22, "cadence": 0.9, "bob": 2.0,
                  "knee_fold": 0.0, "hem_lag": 0.7, "shoe_amp": 1.3},
    "phong_linh": {"leg_amp": 0.55, "arm_amp": 0.26, "cadence": 1.0, "bob": 2.2,
                   "knee_fold": 0.7, "hem_lag": 0.0, "shoe_amp": 0.0},
    "thach_son": {"leg_amp": 0.42, "arm_amp": 0.27, "cadence": 0.95, "bob": 2.2,
                  "knee_fold": 0.2, "hem_lag": 0.3, "shoe_amp": 0.8},
}
FRONT_LEG = {"loi_chan": 0.8, "xich_diem": 0.8, "phong_linh": 0.7, "thach_son": 0.75}


def segment(hero: str, d: str, spr: Image.Image, mask: np.ndarray) -> dict:
    """Returns (parts dict for the rig json, uncovered body px)."""
    h, w = mask.shape
    M = measure(mask)
    cx, top, neck = M["cx"], M["top"], M["neck"]
    waist, hip, bot = M["waist"], M["hip"], M["bot"]
    lay = LAYOUT[hero]
    side = d in ("e", "w")
    diag = d in ("se", "ne", "sw", "nw")
    # Torso core: narrower than the silhouette (arms take the sides).
    core_hw = max(6.0, M["waist_w"] * (0.30 if side else 0.36 if diag else 0.40))
    tx0, tx1 = cx - core_hw, cx + core_hw
    sh_y = neck + 2.0
    hand_y = hip + 4.0
    # Lower-body silhouette bounds: leg panels must not swallow the
    # arm bands' lower halves (the original specs keep the robe
    # panels inside the body's own width for the same reason).
    low_rows = range(int(hip) - 2, h)
    bx0 = max(0.0, min(float(M["xmins"][y]) for y in low_rows) - 1.0)
    bx1 = min(float(w - 1), max(float(M["xmaxs"][y]) for y in low_rows) + 1.0)
    specs = []  # (key, poly, pivot, z, extra)
    # back: hair / cape mass behind the torso. For the back view it
    # claims LAST (leftover hair mass between torso and arms); for
    # front/diag views it is capped near the shoulders so the wide
    # sleeves stay with the arms; side views get a centre strip.
    hair_bot = min(top + (bot - top) * lay["hair"], sh_y + 18.0)
    back_spec = None
    if d == "n":
        back_spec = ("back", [(0, top), (w, top), (w, hip + 6), (0, hip + 6)],
                     (cx, (top + hip) / 2.0), 0, {})
    elif side:
        specs.append(("back", [(tx0 - 6, top), (tx1 + 2, top), (tx1 + 2, hip + 4),
                               (tx0 - 6, hip + 4)], (cx, neck + 8.0), 0, {}))
    else:
        specs.append(("back", [(0, top), (w, top), (w, hair_bot),
                               (tx1 + 3, hair_bot), (tx1 + 3, top + 6),
                               (tx0 - 3, top + 6), (tx0 - 3, hair_bot),
                               (0, hair_bot)], (cx, top + 10.0), 0, {}))
    if lay["kind"] == "gown":
        hem_y = bot - 8.0
        # Slanted hems (outer edge higher) leave the shoe tips to
        # the shoe parts, like the original gown specs.
        specs.append(("leg_l", [(bx0, hip - 6), (cx + 3, hip - 6), (cx + 3, bot - 1),
                                (bx0, bot - 6)], ((bx0 + cx) / 2.0, hip - 2.0), 2,
                      {"phase": 0}))
        specs.append(("leg_r", [(cx - 3, hip - 6), (bx1, hip - 6), (bx1, bot - 6),
                                (cx - 3, bot - 1)], ((cx + bx1) / 2.0, hip - 2.0), 2,
                      {"phase": 1}))
        for key, xa, xb in (("shoe_l", bx0, cx + 2), ("shoe_r", cx - 2, bx1)):
            specs.append((key, [(xa, hem_y), (xb, hem_y), (xb, bot), (xa, bot)],
                          ((xa + xb) / 2.0, hem_y + 1.0), 3, {}))
    else:
        # 14c-fix2: chibi legs are only ~18% of height (hip ~0.815),
        # so the knee sits at ~0.90, not the tall figures' 0.80.
        knee_y = int(h * 0.90)
        spans = (("leg_l", bx0, cx + 3, 0), ("leg_r", cx - 3, bx1, 1))
        for key, xa, xb, ph in spans:
            specs.append((key, [(xa, hip - 6), (xb, hip - 6), (xb, knee_y + 3),
                                (xa, knee_y + 3)], ((xa + xb) / 2.0, hip - 2.0), 2,
                          {"phase": ph, "knee": [(xa + xb) / 2.0, float(knee_y)]}))
            skey = "shin_" + key[-1]
            specs.append((skey, [(xa, knee_y - 2), (xb, knee_y - 2), (xb, bot),
                                 (xa, bot)], ((xa + xb) / 2.0, float(knee_y)), 2,
                          {"phase": ph}))
    # Torso (head included, as the original specs do).
    specs.append(("torso", [(tx0 - 2, top), (tx1 + 2, top), (tx1 + 3, hip + 4),
                            (tx0 - 3, hip + 4)], (cx, neck + 4.0), 3, {}))
    # Arms: silhouette side bands, shoulder to hand.
    if side:
        specs.append(("arm_l", [(0, sh_y), (tx0 + 3, sh_y), (tx0 + 3, hand_y),
                                (0, hand_y)], (tx0, sh_y + 2.0), 4, {}))
        specs.append(("arm_r", [(tx1 - 3, sh_y), (w, sh_y), (w, hand_y),
                                (tx1 - 3, hand_y)], (tx1, sh_y + 2.0), 5, {}))
    else:
        specs.append(("arm_l", [(0, sh_y), (tx0 + 3, sh_y), (tx0 + 2, hand_y),
                                (0, hand_y)], (tx0, sh_y + 2.0), 4, {}))
        specs.append(("arm_r", [(tx1 - 2, sh_y), (w, sh_y), (w, hand_y),
                                (tx1 - 3, hand_y)], (tx1, sh_y + 2.0), 5, {}))
    if back_spec is not None:
        specs.append(back_spec)
    # Claim pixels in order.
    used = np.zeros((h, w), dtype=bool)
    claimed = []  # (key, part mask, part dict)
    for key, poly, pivot, z, extra in specs:
        pm = poly_mask(w, h, poly) & mask & ~used
        if pm.sum() < 4:
            # A dropped micro-part must NOT mark its pixels used —
            # they stay claimable (the mop-up below hands them to a
            # neighbouring part instead of leaving holes).
            continue
        used |= pm
        pd = {"pivot": [round(pivot[0], 1), round(pivot[1], 1)], "z": z}
        pd.update(extra)
        if "knee" in pd:
            pd["knee"] = [round(pd["knee"][0], 1), round(pd["knee"][1], 1)]
        claimed.append((key, pm, pd))
    # Mop-up: a few body pixels can fall outside every polygon band
    # (hair tips past the back strip, a bow limb above the arm
    # band). Grow the neighbouring parts into them, nearest first,
    # so rest-pose reassembly stays pixel-exact over the body mask.
    leftover = mask & ~used
    while leftover.any():
        grown = False
        for key, pm, pd in claimed:
            dil = pm.copy()
            dil[1:, :] |= pm[:-1, :]
            dil[:-1, :] |= pm[1:, :]
            dil[:, 1:] |= pm[:, :-1]
            dil[:, :-1] |= pm[:, 1:]
            dil[1:, 1:] |= pm[:-1, :-1]
            dil[1:, :-1] |= pm[:-1, 1:]
            dil[:-1, 1:] |= pm[1:, :-1]
            dil[:-1, :-1] |= pm[1:, 1:]
            take = dil & leftover
            if take.any():
                pm |= take
                leftover &= ~take
                grown = True
        if not grown:
            break
    if leftover.any():
        # Fully detached specks (a ribbon tip a pixel clear of the
        # body): hand each to its nearest claimed part outright.
        ys, xs = np.where(leftover)
        for y, x in zip(ys.tolist(), xs.tolist()):
            best, best_d = None, None
            for key, pm, pd in claimed:
                pys, pxs = np.where(pm)
                dist = (pxs - x) ** 2 + (pys - y) ** 2
                dmin = int(dist.min()) if len(dist) else 1 << 30
                if best_d is None or dmin < best_d:
                    best, best_d = pm, dmin
            if best is not None:
                best[y, x] = True
                leftover[y, x] = False
    # Save part textures.
    parts = {}
    pdir = os.path.join(PARTS_DIR, hero)
    os.makedirs(pdir, exist_ok=True)
    arr = np.asarray(spr).copy()
    part_masks = {}
    for key, pm, pd in claimed:
        out = np.zeros_like(arr)
        out[pm] = arr[pm]
        name = f"{hero}_{d}_{key}.png"
        Image.fromarray(out, "RGBA").save(os.path.join(pdir, name))
        pd["tex"] = f"hero_parts/{hero}/{name}"
        parts[key] = pd
        part_masks[key] = pm
    if claimed:
        all_pm = np.logical_or.reduce([pm for _, pm, _ in claimed])
        uncovered = int((mask & ~all_pm).sum())
    else:
        uncovered = int(mask.sum())
    # 14c-fix2: the weapon hand comes from the weapon ARM PART's own
    # pixels — the lowest row of its main mass (rows carrying at
    # least a quarter of the part's widest row, so stray specks and
    # hem pixels in the old whole-silhouette zone can't drag the
    # grip down to the skirt). hand_of()'s silhouette zone picked
    # y=84 (hem) for every chibi hero; the real grips sit at 56–67.
    hand = None
    warm = WEAPON_ARM[hero][d]
    if hero == "xich_diem":
        # Her arm parts are nearly empty in the chibi art (the hair
        # mass claims her sleeves first), so her grip is read off
        # the FAN itself (see _xich_diem_fan).
        _strip, hand = _xich_diem_fan(spr)
    if hand is None and warm in part_masks \
            and int(part_masks[warm].sum()) >= 6:
        pm = part_masks[warm]
        rows = pm.sum(axis=1)
        thr = max(2.0, 0.25 * float(rows.max()))
        ys = [y for y in range(pm.shape[0]) if rows[y] >= thr]
        if ys:
            hy = max(ys)
            band = pm[max(0, hy - 3):hy + 1]
            xs = np.where(band.any(axis=0))[0]
            hx = float(xs.mean()) if len(xs) else M["cx"]
            hand = [round(hx, 1), round(float(hy), 1)]
    return parts, uncovered, M, hand


def hand_of(mask: np.ndarray, parts: dict, arm: str, M: dict) -> list:
    """The weapon hand: centroid of the weapon arm's lowest rows."""
    # Recompute from the arm part texture would need a reload; use
    # the silhouette: lowest mask pixels inside the arm's x-band.
    h, w = mask.shape
    cx = M["cx"]
    if arm == "arm_r":
        zone = mask[:, int(cx):]
        off = int(cx)
    else:
        zone = mask[:, :int(cx) + 1]
        off = 0
    ys = np.where(zone.any(axis=1))[0]
    low = [y for y in ys if y <= M["hip"] + 10]
    y = float(max(low)) if low else float(M["hip"])
    xs = np.where(zone[int(y) - 2:int(y) + 1].any(axis=0))[0]
    x = float(xs.mean()) + off if len(xs) else cx
    return [round(x, 1), round(y, 1)]


def mirror_parts(hero: str, d: str, parts: dict, w: int) -> dict:
    out = {}
    swap = {"arm_l": "arm_r", "arm_r": "arm_l", "leg_l": "leg_r",
            "leg_r": "leg_l", "shin_l": "shin_r", "shin_r": "shin_l",
            "shoe_l": "shoe_r", "shoe_r": "shoe_l"}
    md = MIRROR[d][0]
    for key, pd in parts.items():
        nk = swap.get(key, key)
        src = Image.open(os.path.join(ASSETS, pd["tex"]))
        name = f"{hero}_{md}_{nk}.png"
        src.transpose(Image.FLIP_LEFT_RIGHT).save(
            os.path.join(PARTS_DIR, hero, name))
        np_ = dict(pd)
        np_["tex"] = f"hero_parts/{hero}/{name}"
        np_["pivot"] = [round(w - 1 - pd["pivot"][0], 1), pd["pivot"][1]]
        if "knee" in pd:
            np_["knee"] = [round(w - 1 - pd["knee"][0], 1), pd["knee"][1]]
        if "phase" in pd:
            np_["phase"] = 1 - pd["phase"]
        out[nk] = np_
    return out


def main() -> None:
    with open(RIG_JSON, encoding="utf-8") as f:
        data = json.load(f)
    os.makedirs(WEAPONS_DIR, exist_ok=True)
    for hero in WEAPON_DRAW:
        WEAPON_DRAW[hero]().save(os.path.join(WEAPONS_DIR, f"{hero}.png"))
        chars = data.setdefault("chars", {})
        entry = {"tuning": TUNING[hero], "wclass": WCLASS[hero],
                 "front_leg_factor": FRONT_LEG[hero],
                 "weapon": {"tex": f"hero_weapons/{hero}.png",
                            "grip": GRIPS[hero], "wscale": 0.5},
                 "dirs": {}}
        for d in DIRS5:
            spr = Image.open(os.path.join(ASSETS, f"king_{hero}_{d}.png")) \
                .convert("RGBA")
            mask = body_mask(hero, spr)
            parts, uncovered, M, part_hand = segment(hero, d, spr, mask)
            total = int(mask.sum())
            warm = WEAPON_ARM[hero][d]
            hand = part_hand if part_hand is not None \
                else hand_of(mask, parts, warm, M)
            if hero == "xich_diem" and d in BACK_FAN_HAND:
                hand = list(BACK_FAN_HAND[d])
            wpn = {"arm": warm, "hand": hand,
                   "rest": RESTS[hero][d], "z": 6,
                   "follow": FOLLOWS[hero]}
            if d in NO_WEAPON_DIRS.get(hero, set()):
                wpn = {}
            entry["dirs"][d] = {
                "canvas": [spr.width, spr.height], "swing": 1, "parts": parts,
                "weapon": wpn}
            print(f"{hero} {d}: parts={len(parts)} uncovered "
                  f"{uncovered}/{total} ({100.0 * uncovered / max(total, 1):.1f}%) "
                  f"hand={hand}")
            if d in MIRROR and MIRROR[d][1]:
                md = MIRROR[d][0]
                mparts = mirror_parts(hero, d, parts, spr.width)
                mrest = -RESTS[hero][d]
                marm = "arm_l" if warm == "arm_r" else "arm_r"
                mhand = [round(spr.width - 1 - hand[0], 1), hand[1]]
                mwpn = {"arm": marm, "hand": mhand, "rest": mrest,
                        "z": 6, "follow": FOLLOWS[hero]}
                if md in NO_WEAPON_DIRS.get(hero, set()):
                    mwpn = {}
                entry["dirs"][md] = {
                    "canvas": [spr.width, spr.height], "swing": 1,
                    "parts": mparts,
                    "weapon": mwpn}
        chars[hero] = entry
    with open(RIG_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
    print("hero_rig.json updated:", ", ".join(WEAPON_DRAW))


if __name__ == "__main__":
    main()
