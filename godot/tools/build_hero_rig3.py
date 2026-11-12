#!/usr/bin/env python3
"""Empire Age 16a — cutout rigs for the eight Western Medieval heroes.

Same machinery as tools/build_hero_rig2.py (imported and re-specced):
body mask = sprite alpha minus weapon pixels, polygon-band parts
claimed in the shipped order, pixel-exact rest reassembly over the
body mask, weapons DRAWN here in the painted dialect — never photo
cutouts. Merged ADDITIVELY into assets/hero_rig.json; the outgoing
roster's entries are not touched.

Owner rules applied (2026-11-11):
  * shields are body-worn equipment — the knight's lion shield and
    the paladin's cross shield stay INSIDE the body parts (they sit
    contiguous with the body's own silhouette runs); only the HAND
    weapons are stripped from the body and drawn as rig weapons;
  * NO weapon is rendered in the back directions (ne/n/nw emit an
    empty weapon entry) — for every new hero, like the old roster.

Run from the godot/ directory:  python3 tools/build_hero_rig3.py
"""
import importlib.util
import math
import os

import numpy as np
from PIL import Image, ImageDraw

spec = importlib.util.spec_from_file_location(
    "r2", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "build_hero_rig2.py"))
r2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r2)

SS = r2.SS
_blade = r2._blade

HEROES8 = ("knight", "berserker", "archer", "mage",
           "paladin", "dragoon", "assassin", "ranger")


# ======================================================================
# Weapons — drawn at 4x, downscaled. Business end points UP from the
# grip, exactly like the shipped weapon sets.
# ======================================================================
def draw_knight() -> Image.Image:
    # Longsword: silver blade, gold crossguard, dark wrap, gold pommel.
    W, H = 34 * SS, 96 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 17 * SS, 70 * SS
    _blade(dr, [(gx - 3 * SS, gy - 6 * SS), (gx - 3 * SS, gy - 58 * SS),
                (gx, gy - 66 * SS), (gx + 3 * SS, gy - 58 * SS),
                (gx + 3 * SS, gy - 6 * SS)], (168, 180, 205, 255), (96, 106, 138, 255))
    dr.line([(gx, gy - 60 * SS), (gx, gy - 10 * SS)], fill=(120, 132, 165, 255), width=SS)
    dr.rectangle([gx - 9 * SS, gy - 6 * SS, gx + 9 * SS, gy - 2 * SS], fill=(196, 152, 74, 255))
    dr.rectangle([gx - 9 * SS, gy - 6 * SS, gx + 9 * SS, gy - 4 * SS], fill=(226, 186, 100, 255))
    dr.rectangle([gx - 2 * SS, gy - 2 * SS, gx + 2 * SS, gy + 14 * SS], fill=(52, 42, 34, 255))
    dr.ellipse([gx - 3 * SS, gy + 14 * SS, gx + 3 * SS, gy + 20 * SS], fill=(196, 152, 74, 255))
    return im.resize((34, 96), Image.LANCZOS)


def draw_berserker() -> Image.Image:
    # Great axe: long wood haft, one huge silver crescent blade.
    W, H = 64 * SS, 104 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 32 * SS, 72 * SS
    dr.rectangle([gx - 2 * SS, 14 * SS, gx + 2 * SS, 100 * SS], fill=(104, 74, 44, 255))
    dr.rectangle([gx - 2 * SS, 14 * SS, gx, 100 * SS], fill=(140, 104, 62, 255))
    # Blade: crescent sweeping left-down from the haft top.
    _blade(dr, [(gx - 1 * SS, 8 * SS), (gx - 20 * SS, 10 * SS), (gx - 30 * SS, 20 * SS),
                (gx - 31 * SS, 34 * SS), (gx - 22 * SS, 40 * SS), (gx - 8 * SS, 36 * SS),
                (gx - 1 * SS, 30 * SS)], (158, 170, 198, 255), (92, 102, 132, 255))
    dr.line([(gx - 29 * SS, 22 * SS), (gx - 28 * SS, 33 * SS), (gx - 20 * SS, 38 * SS)],
            fill=(205, 218, 240, 255), width=SS)
    # Bronze socket bands + back spike.
    dr.rectangle([gx - 4 * SS, 10 * SS, gx + 4 * SS, 16 * SS], fill=(146, 110, 56, 255))
    dr.rectangle([gx - 4 * SS, 28 * SS, gx + 4 * SS, 33 * SS], fill=(146, 110, 56, 255))
    _blade(dr, [(gx + 2 * SS, 12 * SS), (gx + 12 * SS, 16 * SS), (gx + 2 * SS, 22 * SS)],
           (158, 170, 198, 255), (92, 102, 132, 255))
    dr.ellipse([gx - 3 * SS, 98 * SS, gx + 3 * SS, 103 * SS], fill=(80, 58, 36, 255))
    return im.resize((64, 104), Image.LANCZOS)


def draw_archer() -> Image.Image:
    # Recurve bow: pale wood limbs, gold tips, white string.
    W, H = 36 * SS, 118 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 15 * SS, 59 * SS
    dr.line([(9 * SS, 5 * SS), (9 * SS, 113 * SS)], fill=(230, 232, 226, 255), width=max(2, SS // 2))
    limb = [(9 * SS, 5 * SS), (21 * SS, 15 * SS), (27 * SS, 33 * SS),
            (28 * SS, 59 * SS), (27 * SS, 85 * SS), (21 * SS, 103 * SS),
            (9 * SS, 113 * SS)]
    dr.line(limb, fill=(146, 104, 56, 255), width=3 * SS, joint="curve")
    dr.line(limb, fill=(186, 142, 84, 255), width=SS, joint="curve")
    for tip in ((9, 5), (9, 113)):
        dr.ellipse([(tip[0] * SS - 3 * SS, tip[1] * SS - 3 * SS),
                    (tip[0] * SS + 3 * SS, tip[1] * SS + 3 * SS)], fill=(206, 168, 84, 255))
    dr.rectangle([gx - 2 * SS, gy - 6 * SS, gx + 3 * SS, gy + 6 * SS], fill=(66, 92, 52, 255))
    return im.resize((36, 118), Image.LANCZOS)


def draw_mage() -> Image.Image:
    # Orb staff: gold shaft, pronged crown, glowing violet orb.
    W, H = 30 * SS, 104 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 15 * SS, 66 * SS
    dr.rectangle([gx - 2 * SS, 26 * SS, gx + 2 * SS, 100 * SS], fill=(168, 128, 62, 255))
    dr.rectangle([gx - 2 * SS, 26 * SS, gx, 100 * SS], fill=(206, 168, 92, 255))
    # Prongs cradling the orb.
    for sgn in (-1, 1):
        dr.line([(gx, 30 * SS), (gx + sgn * 7 * SS, 20 * SS), (gx + sgn * 6 * SS, 10 * SS)],
                fill=(206, 168, 92, 255), width=2 * SS)
    # Orb: layered violet -> magenta -> pale core.
    dr.ellipse([gx - 8 * SS, 2 * SS, gx + 8 * SS, 20 * SS], fill=(110, 52, 190, 255))
    dr.ellipse([gx - 6 * SS, 4 * SS, gx + 6 * SS, 18 * SS], fill=(156, 84, 226, 255))
    dr.ellipse([gx - 3 * SS, 6 * SS, gx + 2 * SS, 13 * SS], fill=(216, 168, 255, 255))
    # Sparkles.
    for dx, dy, s in [(-11, 8, 3), (11, 14, 2), (10, 2, 2)]:
        cx, cy = (gx + dx * SS), (dy + 4) * SS
        dr.polygon([(cx, cy - s * SS), (cx + s * SS // 2, cy), (cx, cy + s * SS),
                    (cx - s * SS // 2, cy)], fill=(226, 196, 255, 255))
    dr.ellipse([gx - 3 * SS, 98 * SS, gx + 3 * SS, 103 * SS], fill=(146, 110, 56, 255))
    return im.resize((30, 104), Image.LANCZOS)


def draw_paladin() -> Image.Image:
    # War hammer: gold square head with a cross worked into the
    # face, SHORT handle below the grip — on his sheet the maul
    # head sits right at his hand with only a stub pommel below;
    # a long tail rotated at rest stuck out past his silhouette.
    W, H = 44 * SS, 64 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 22 * SS, 34 * SS
    dr.rectangle([gx - 2 * SS, 26 * SS, gx + 2 * SS, 58 * SS], fill=(104, 78, 48, 255))
    dr.rectangle([gx - 2 * SS, 26 * SS, gx, 58 * SS], fill=(140, 108, 66, 255))
    dr.rectangle([5 * SS, 3 * SS, 39 * SS, 27 * SS], fill=(196, 152, 74, 255))
    dr.rectangle([5 * SS, 3 * SS, 39 * SS, 9 * SS], fill=(232, 192, 106, 255))
    dr.rectangle([5 * SS, 21 * SS, 39 * SS, 27 * SS], fill=(158, 118, 54, 255))
    # Cross engraved on the head face.
    dr.rectangle([20 * SS, 7 * SS, 24 * SS, 23 * SS], fill=(122, 88, 38, 255))
    dr.rectangle([13 * SS, 12 * SS, 31 * SS, 16 * SS], fill=(122, 88, 38, 255))
    dr.rectangle([18 * SS, 3 * SS, 26 * SS, 27 * SS], fill=(172, 130, 62, 255))
    dr.ellipse([gx - 3 * SS, 56 * SS, gx + 3 * SS, 61 * SS], fill=(196, 152, 74, 255))
    return im.resize((44, 64), Image.LANCZOS)


def draw_dragoon() -> Image.Image:
    # Lance: long silver head, gold shaft, blue gem at the collar.
    W, H = 26 * SS, 124 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 13 * SS, 84 * SS
    dr.rectangle([gx - 2 * SS, 30 * SS, gx + 2 * SS, 120 * SS], fill=(158, 118, 56, 255))
    dr.rectangle([gx - 2 * SS, 30 * SS, gx, 120 * SS], fill=(196, 152, 80, 255))
    _blade(dr, [(gx - 3 * SS, 34 * SS), (gx - 2 * SS, 12 * SS), (gx, 2 * SS),
                (gx + 2 * SS, 12 * SS), (gx + 3 * SS, 34 * SS)],
           (170, 182, 208, 255), (98, 110, 140, 255))
    dr.rectangle([gx - 4 * SS, 32 * SS, gx + 4 * SS, 37 * SS], fill=(206, 168, 92, 255))
    dr.ellipse([gx - 3 * SS, 42 * SS, gx + 3 * SS, 48 * SS], fill=(64, 110, 220, 255))
    return im.resize((26, 124), Image.LANCZOS)


def draw_assassin() -> Image.Image:
    # Twin daggers: two short straight blades fanning from one grip.
    W, H = 44 * SS, 84 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 22 * SS, 62 * SS
    _blade(dr, [(gx - 2 * SS, gy - 4 * SS), (gx - 12 * SS, gy - 34 * SS),
                (gx - 15 * SS, gy - 48 * SS), (gx - 6 * SS, gy - 38 * SS),
                (gx + 1 * SS, gy - 16 * SS)], (128, 140, 168, 255), (70, 80, 106, 255))
    _blade(dr, [(gx + 2 * SS, gy - 4 * SS), (gx + 11 * SS, gy - 36 * SS),
                (gx + 14 * SS, gy - 52 * SS), (gx + 6 * SS, gy - 40 * SS),
                (gx - 1 * SS, gy - 16 * SS)], (164, 176, 202, 255), (96, 108, 138, 255))
    dr.rectangle([gx - 8 * SS, gy - 5 * SS, gx + 8 * SS, gy - 1 * SS], fill=(120, 96, 52, 255))
    dr.rectangle([gx - 2 * SS, gy - 1 * SS, gx + 2 * SS, gy + 13 * SS], fill=(30, 28, 36, 255))
    dr.ellipse([gx - 3 * SS, gy + 13 * SS, gx + 3 * SS, gy + 18 * SS], fill=(110, 88, 48, 255))
    return im.resize((44, 84), Image.LANCZOS)


def draw_ranger() -> Image.Image:
    # Longsword (owner-verified: she is a sword skirmisher, not a
    # rapier fencer): straight silver-blue blade, gold crossguard.
    W, H = 26 * SS, 108 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    gx, gy = 13 * SS, 78 * SS
    _blade(dr, [(gx - 3 * SS, gy - 6 * SS), (gx - 3 * SS, gy - 62 * SS),
                (gx, gy - 72 * SS), (gx + 3 * SS, gy - 62 * SS),
                (gx + 3 * SS, gy - 6 * SS)], (178, 198, 224, 255), (110, 132, 168, 255))
    dr.line([(gx, gy - 64 * SS), (gx, gy - 10 * SS)], fill=(128, 150, 186, 255), width=SS)
    dr.rectangle([gx - 8 * SS, gy - 6 * SS, gx + 8 * SS, gy - 2 * SS], fill=(196, 152, 74, 255))
    dr.rectangle([gx - 8 * SS, gy - 6 * SS, gx + 8 * SS, gy - 4 * SS], fill=(226, 186, 100, 255))
    dr.rectangle([gx - 2 * SS, gy - 2 * SS, gx + 2 * SS, gy + 12 * SS], fill=(84, 58, 38, 255))
    dr.ellipse([gx - 3 * SS, gy + 12 * SS, gx + 3 * SS, gy + 17 * SS], fill=(196, 152, 74, 255))
    return im.resize((26, 108), Image.LANCZOS)


# ======================================================================
# Spec tables (patched into rig2's machinery).
# ======================================================================
r2.WEAPON_DRAW = {"knight": draw_knight, "berserker": draw_berserker,
                  "archer": draw_archer, "mage": draw_mage,
                  "paladin": draw_paladin, "dragoon": draw_dragoon,
                  "assassin": draw_assassin, "ranger": draw_ranger}
r2.GRIPS = {"knight": [17, 70], "berserker": [32, 72], "archer": [15, 59],
            "mage": [15, 66], "paladin": [22, 34], "dragoon": [13, 84],
            "assassin": [22, 62], "ranger": [13, 78]}
r2.LAYOUT = {
    "knight": {"kind": "legs", "hair": 0.55},
    "berserker": {"kind": "legs", "hair": 0.42},
    "archer": {"kind": "legs", "hair": 0.52},
    "mage": {"kind": "gown", "hair": 0.46},
    "paladin": {"kind": "legs", "hair": 0.50},
    "dragoon": {"kind": "legs", "hair": 0.55},
    "assassin": {"kind": "legs", "hair": 0.50},
    "ranger": {"kind": "gown", "hair": 0.55},
}
_ARM_R = {"s": "arm_r", "se": "arm_r", "e": "arm_r", "ne": "arm_r", "n": "arm_r"}
# Sword/axe/hammer hand is the figure's hand on the IMAGE-LEFT in
# the front views (the shield rides the other arm) — read off the
# sprites, not assumed.
_ARM_FRONT_L = {"s": "arm_l", "se": "arm_l", "e": "arm_r", "ne": "arm_r", "n": "arm_l"}
_ARM_BOW = {"s": "arm_r", "se": "arm_r", "e": "arm_r", "ne": "arm_r", "n": "arm_l"}
r2.WEAPON_ARM = {"knight": dict(_ARM_FRONT_L), "berserker": dict(_ARM_FRONT_L),
                 "archer": dict(_ARM_BOW), "mage": dict(_ARM_R),
                 "paladin": dict(_ARM_FRONT_L), "dragoon": dict(_ARM_R),
                 "assassin": dict(_ARM_R), "ranger": dict(_ARM_BOW)}

# Hand positions authored from the sprites (the automatic read
# lands on the shield for the knight/paladin and on the quiver for
# the archer, because those ride inside the same arm band). Applied
# over the built rig; mirrored dirs (sw/w) are derived from se/e.
HAND_OVERRIDES = {
    "knight": {"s": ("arm_l", [10.0, 66.0]), "se": ("arm_l", [12.0, 64.0]),
               "e": ("arm_r", [36.0, 63.0])},
    "berserker": {"s": ("arm_l", [8.0, 64.0]), "se": ("arm_l", [10.0, 63.0]),
                  "e": ("arm_r", [40.0, 63.0])},
    "ranger": {"s": ("arm_r", [68.0, 62.0]), "se": ("arm_r", [72.0, 60.0]),
               "e": ("arm_r", [66.0, 62.0])},
}

# Heroes whose hand weapon is FUSED to the silhouette in the sheet
# art and stays body-worn, exactly like the knight's shield: no
# separate rig weapon is drawn.
#  - archer: her bow hugs her body and shares her hair's gold-brown
#    palette, so a colour strip would eat her hair; the bow rides
#    inside her arm/torso parts instead. (Back views: the bow is
#    cleaned out of the n sprite at the source, see assets3.)
#  - paladin: his gold maul head hangs fused at his side in the
#    sheet. The rig-drawn hammer at rest rendered as a detached
#    gold blob by his foot (QA strip v1), worse than the sheet's
#    own hammer riding in his arm part — so the sheet hammer stays
#    and no rig weapon is drawn.
BODY_WORN_WEAPON = ("archer", "paladin")
_SWORD_REST = {"s": 150, "se": 140, "e": 128, "ne": 150, "n": 165}
_HEAVY_REST = {"s": 155, "se": 145, "e": 130, "ne": 155, "n": 170}
r2.RESTS = {"knight": dict(_SWORD_REST), "berserker": dict(_HEAVY_REST),
            "archer": {"s": 10, "se": 12, "e": 16, "ne": 10, "n": 10},
            "mage": {"s": 10, "se": 16, "e": 22, "ne": 12, "n": 12},
            "paladin": dict(_HEAVY_REST),
            "dragoon": {"s": 16, "se": 20, "e": 35, "ne": 18, "n": 18},
            "assassin": dict(_SWORD_REST), "ranger": dict(_SWORD_REST)}
r2.FOLLOWS = {"knight": 0.85, "berserker": 0.8, "archer": 0.5, "mage": 0.6,
              "paladin": 0.8, "dragoon": 0.35, "assassin": 0.85, "ranger": 0.85}
r2.NO_WEAPON_DIRS = {h: {"ne", "n", "nw"} for h in HEROES8}
r2.WCLASS = {"knight": "sword", "berserker": "sword", "archer": "bow",
             "mage": "staff", "paladin": "sword", "dragoon": "spear",
             "assassin": "sword", "ranger": "sword"}
r2.TUNING = {
    "knight": {"leg_amp": 0.50, "arm_amp": 0.28, "cadence": 1.0, "bob": 2.2,
               "knee_fold": 0.7, "hem_lag": 0.0, "shoe_amp": 0.0},
    "berserker": {"leg_amp": 0.58, "arm_amp": 0.32, "cadence": 1.05, "bob": 2.6,
                  "knee_fold": 0.7, "hem_lag": 0.0, "shoe_amp": 0.0},
    "archer": {"leg_amp": 0.55, "arm_amp": 0.26, "cadence": 1.0, "bob": 2.2,
               "knee_fold": 0.7, "hem_lag": 0.0, "shoe_amp": 0.0},
    "mage": {"leg_amp": 0.28, "arm_amp": 0.22, "cadence": 0.9, "bob": 2.0,
             "knee_fold": 0.0, "hem_lag": 0.7, "shoe_amp": 1.3},
    "paladin": {"leg_amp": 0.48, "arm_amp": 0.28, "cadence": 0.95, "bob": 2.2,
                "knee_fold": 0.6, "hem_lag": 0.0, "shoe_amp": 0.0},
    "dragoon": {"leg_amp": 0.52, "arm_amp": 0.28, "cadence": 1.0, "bob": 2.2,
                "knee_fold": 0.7, "hem_lag": 0.0, "shoe_amp": 0.0},
    "assassin": {"leg_amp": 0.60, "arm_amp": 0.30, "cadence": 1.1, "bob": 2.0,
                 "knee_fold": 0.75, "hem_lag": 0.0, "shoe_amp": 0.0},
    "ranger": {"leg_amp": 0.30, "arm_amp": 0.24, "cadence": 0.95, "bob": 2.1,
               "knee_fold": 0.0, "hem_lag": 0.5, "shoe_amp": 1.0},
}
r2.FRONT_LEG = {"knight": 0.75, "berserker": 0.8, "archer": 0.7, "mage": 0.8,
                "paladin": 0.75, "dragoon": 0.75, "assassin": 0.8, "ranger": 0.75}


# ======================================================================
# Body masks: alpha minus weapon pixels. Colour strips keyed per
# hero, then rig2's per-row run cleaning (drops separated runs in
# the weapon zones: bow limbs, axe haft ends, staff sparkles).
# ======================================================================
_STEEL_HEROES = ("knight", "berserker", "dragoon", "assassin", "ranger")


def _strip_outside_main_run(a, colour):
    """Remove `colour` pixels that lie outside their row's main run
    (the run covering the body centre) — the Lôi Chấn rule: costume
    pieces in the same colours sit INSIDE the main run and survive;
    hand weapons ride in their own side runs and are stripped."""
    h, w = a.shape
    torso_rows = a[int(h * 0.30):int(h * 0.55)]
    cols = np.where(torso_rows.any(axis=0))[0]
    cx = float(cols.mean()) if len(cols) else w / 2.0
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
        srow = colour[y]
        if main is not None:
            srow = srow.copy()
            srow[main[0]:main[1] + 1] = False
        strip[y] = srow
    return a & ~strip


def body_mask3(hero: str, spr: Image.Image) -> np.ndarray:
    a = np.asarray(spr.getchannel("A")).astype(np.int32) > 40
    rgb = np.asarray(spr.convert("RGB")).astype(np.int32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    h, w = a.shape
    if hero in _STEEL_HEROES:
        # Pale steel = blades (sword / axe head / lance head /
        # daggers / rapier). Armour, fur and skin in the same value
        # range sit inside the main run and are protected.
        steel = (mx - mn < 64) & (mx > 140) & (b >= r - 6)
        a = _strip_outside_main_run(a, steel)
    elif hero == "paladin":
        # No colour strip: his gold war hammer is body-worn (see
        # BODY_WORN_WEAPON) and his armour's gold trim shares its
        # palette. Only the run cleaning below applies.
        pass
    elif hero == "mage":
        # The glowing orb: violet-pink — but her HOOD is violet
        # too and a pure colour test eats its bright rows (seen as
        # magenta streaks through the hood in the first rig pass).
        # Gate by position instead: the orb rides on the staff
        # BEYOND the head's right edge; strip violet-family pixels
        # only out there. The gold shaft is left to run cleaning.
        violet = (b > 140) & (b > r) & (r > 90)
        rows = a.any(axis=1)
        ys = np.where(rows)[0]
        top_i, bot_i = int(ys.min()), int(ys.max())
        head_rows = a[top_i:top_i + int((bot_i - top_i + 1) * 0.40)]
        hcols = np.where(head_rows.any(axis=0))[0]
        hx = int(hcols.max()) + 3 if len(hcols) else w
        orb = violet.copy()
        orb[:, :hx] = False
        a &= ~orb
    elif hero == "archer":
        # The bow's curve encloses a blob of the sheet's white
        # background that border keying could not reach. Strip
        # near-white components of >= 8 px in the bow zone (right
        # of the body centre, below the face) — eye whites and the
        # quiver's fletching sit outside the gate and survive.
        torso_rows = a[int(h * 0.30):int(h * 0.55)]
        cols = np.where(torso_rows.any(axis=0))[0]
        ccx = float(cols.mean()) if len(cols) else w / 2.0
        near_white = (mn > 232) & ((mx - mn) < 25) & a
        strip = np.zeros_like(a)
        for pts in r2._components(near_white):
            if len(pts) < 8:
                continue
            if all(px > ccx + 8 and py > 20 for py, px in pts):
                for py, px in pts:
                    strip[py, px] = True
        a &= ~strip
    # Per-row run cleaning (rig2's, verbatim logic): drop runs
    # separated from the body run by more than 2 px.
    torso_rows = a[int(h * 0.30):int(h * 0.55)]
    cols = np.where(torso_rows.any(axis=0))[0]
    cx = float(cols.mean()) if len(cols) else w / 2.0
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
            near = any(rn[1] >= br[0] - 2 and rn[0] <= br[1] + 2
                       for br in body_runs)
            if near:
                keep.add(rn)
        for rn in runs:
            if rn not in keep:
                out[y, rn[0]:rn[1] + 1] = False
    return out


r2.body_mask = body_mask3


def apply_hand_overrides() -> None:
    import json
    with open(r2.RIG_JSON, encoding="utf-8") as f:
        data = json.load(f)
    for hero in BODY_WORN_WEAPON:
        for ddat in data["chars"][hero]["dirs"].values():
            ddat["weapon"] = {}
    print("body-worn weapons (no rig weapon):", ", ".join(BODY_WORN_WEAPON))
    swap = {"arm_l": "arm_r", "arm_r": "arm_l"}
    mirror_of = {"se": "sw", "e": "w"}
    for hero, dirs in HAND_OVERRIDES.items():
        entry = data["chars"][hero]
        for d, (arm, hand) in dirs.items():
            wpn = entry["dirs"][d].get("weapon", {})
            if wpn:
                wpn["arm"] = arm
                wpn["hand"] = list(hand)
            md = mirror_of.get(d)
            if md:
                mwpn = entry["dirs"][md].get("weapon", {})
                if mwpn:
                    w = entry["dirs"][md]["canvas"][0]
                    mwpn["arm"] = swap[arm]
                    mwpn["hand"] = [round(w - 1 - hand[0], 1), hand[1]]
    with open(r2.RIG_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
    print("hand overrides applied:", ", ".join(HAND_OVERRIDES))


if __name__ == "__main__":
    r2.main()
    apply_hand_overrides()
