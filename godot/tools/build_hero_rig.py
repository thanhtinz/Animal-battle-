#!/usr/bin/env python3
"""
build_hero_rig.py — Empire Age 13n: cutout limb rigs + weapons for the
four main characters.

Tín's orders (2026-11-09): "vẽ thêm animation cho chân tay đồ hoạt
động đi" + "Vẽ thêm vũ khí cho nó". The characters ship ONE static
pose per direction, so real limb motion needs a cutout rig: each
direction sprite is partitioned into parts (back / leg_l / leg_r /
torso / arm_l / arm_r) that the game rotates around joint pivots
(scripts/hero_rig.gd + the king block in scripts/unit.gd). All of it
is PRESENTATION ONLY — nothing here touches sim state.

Outputs:
  assets/hero_parts/<char>_<dir>_<part>.png   full-canvas part sprites
  assets/hero_weapons/<char>.png              the character's weapon
  assets/hero_rig.json                        pivots / hands / z / tuning
  /tmp/rig_exploded.png                       QA: parts side by side
  /tmp/rig_poses.png                          QA: canned walk/attack/cast poses

Segmentation discipline:
  * Every opaque pixel of the source belongs to exactly ONE part
    (claim order per direction), so rest-pose reassembly is exact.
  * Arms get a shoulder CAP and legs a THIGH BAND: pixels copied
    from the source into the part (the owner part keeps its own
    copy). Drawn under/over correctly they are invisible at rest
    and cover the joint when the part rotates — no torn holes.
  * Gown characters (Kim Hoa, Bạch Sa) have no visible legs in the
    source art: their "leg" parts are the two hem panels + shoes,
    which swing alternately — documented per direction in RIG_NOTES.
  * w-side directions are authored by mirroring the e-side spec
    (arm_l<->arm_r, leg_l<->leg_r swapped); QA sheets cover all 32.

Re-run: python3 tools/build_hero_rig.py   (from the godot/ folder)
"""
import json
import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ASSETS = os.path.join(ROOT, "assets")
PARTS_DIR = os.path.join(ASSETS, "hero_parts")
WEAPONS_DIR = os.path.join(ASSETS, "hero_weapons")
DIRS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]
CHARS = ["ngan_ky", "kim_hoa", "lam_bao", "bach_sa"]

# ---------------------------------------------------------------- weapons
# Drawn at 4x then downscaled (the character art is smooth-matted,
# linear-filtered in game). Grip point in FINAL pixels, weapon
# pointing UP at rotation 0.

def _canvas(w, h):
    return Image.new("RGBA", (w * 4, h * 4), (0, 0, 0, 0))


def _finish(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def draw_sword():
    """Ngân Kỵ's longsword: silver blade, gold guard, red-gem pommel.
    Canvas 16x42, grip at (8, 35): blade above, pommel below."""
    W, H, S = 16, 42, 4
    im = _canvas(W, H)
    d = ImageDraw.Draw(im)
    OUT = (38, 42, 54, 255)
    SILVER = (216, 226, 238, 255)
    SILVER_HI = (248, 251, 255, 255)
    SILVER_LO = (150, 166, 184, 255)
    GOLD = (232, 182, 76, 255)
    GOLD_DK = (168, 118, 40, 255)
    GRIP = (96, 62, 38, 255)
    GEM = (210, 59, 59, 255)
    cx = 8 * S
    # blade: from tip (y=1) to guard (y=28), half-width 2.2 -> 1.6
    d.polygon([(cx, 1 * S), (cx + 2.2 * S, 7 * S), (cx + 1.7 * S, 28 * S),
               (cx - 1.7 * S, 28 * S), (cx - 2.2 * S, 7 * S)], fill=SILVER, outline=OUT, width=S)
    d.polygon([(cx, 2 * S), (cx + 1.0 * S, 8 * S), (cx + 0.8 * S, 27 * S),
               (cx - 0.2 * S, 27 * S), (cx - 0.4 * S, 8 * S)], fill=SILVER_HI)
    d.line([(cx + 1.2 * S, 9 * S), (cx + 1.2 * S, 27 * S)], fill=SILVER_LO, width=S)
    # crossguard y 28..31.5, width 13
    d.rounded_rectangle([cx - 6.5 * S, 28 * S, cx + 6.5 * S, 31.5 * S], radius=1.5 * S,
                        fill=GOLD, outline=GOLD_DK, width=S)
    d.ellipse([cx - 1.6 * S, 28.4 * S, cx + 1.6 * S, 31.1 * S], fill=GEM, outline=GOLD_DK, width=max(1, S // 2))
    # grip y 31.5..37
    d.rectangle([cx - 1.5 * S, 31.5 * S, cx + 1.5 * S, 37 * S], fill=GRIP, outline=OUT, width=S)
    for gy in (33.2, 35.2):
        d.line([(cx - 1.5 * S, gy * S), (cx + 1.5 * S, gy * S)], fill=(60, 38, 22, 255), width=S)
    # pommel y 37..41
    d.ellipse([cx - 2.4 * S, 37 * S, cx + 2.4 * S, 41.4 * S], fill=GOLD, outline=GOLD_DK, width=S)
    d.ellipse([cx - 1.1 * S, 38.2 * S, cx + 1.1 * S, 40.4 * S], fill=GEM)
    return _finish(im, W, H), (8, 35)


def draw_sceptre():
    """Kim Hoa's flower sceptre: slender gold staff, white flower
    with a pink heart. Canvas 14x40, grip at (7, 31)."""
    W, H, S = 14, 40, 4
    im = _canvas(W, H)
    d = ImageDraw.Draw(im)
    GOLD = (236, 196, 96, 255)
    GOLD_DK = (172, 128, 46, 255)
    WHITE = (252, 250, 246, 255)
    WHITE_SH = (226, 218, 205, 255)
    PINK = (242, 150, 190, 255)
    PINK_DK = (214, 96, 150, 255)
    cx = 7 * S
    # staff y 12..38 (grip zone 27..34), slight taper
    d.polygon([(cx - 1.1 * S, 12 * S), (cx + 1.1 * S, 12 * S),
               (cx + 0.8 * S, 38 * S), (cx - 0.8 * S, 38 * S)], fill=GOLD, outline=GOLD_DK, width=S)
    d.ellipse([cx - 1.9 * S, 36.4 * S, cx + 1.9 * S, 39.6 * S], fill=GOLD, outline=GOLD_DK, width=S)
    # leaves under the flower
    d.polygon([(cx, 11 * S), (cx - 3.4 * S, 14.5 * S), (cx - 0.6 * S, 15 * S)], fill=(120, 178, 110, 255))
    d.polygon([(cx, 11 * S), (cx + 3.4 * S, 14.5 * S), (cx + 0.6 * S, 15 * S)], fill=(104, 164, 96, 255))
    # flower: 5 petals around (cx, 7)
    for ang in (-90, -18, 54, 126, 198):
        px = cx + 3.4 * S * math.cos(math.radians(ang))
        py = 7 * S + 3.4 * S * math.sin(math.radians(ang))
        d.ellipse([px - 2.5 * S, py - 2.5 * S, px + 2.5 * S, py + 2.5 * S],
                  fill=WHITE, outline=WHITE_SH, width=S)
    d.ellipse([cx - 2.2 * S, 7 * S - 2.2 * S, cx + 2.2 * S, 7 * S + 2.2 * S],
              fill=PINK, outline=PINK_DK, width=S)
    d.ellipse([cx - 0.9 * S, 7 * S - 0.9 * S, cx + 0.9 * S, 7 * S + 0.9 * S], fill=(255, 214, 232, 255))
    return _finish(im, W, H), (7, 31)


def draw_spear():
    """Lam Bào's ice spear: long shaft, pale ice blade. Canvas
    12x56, grip at (6, 40)."""
    W, H, S = 12, 56, 4
    im = _canvas(W, H)
    d = ImageDraw.Draw(im)
    OUT = (44, 54, 74, 255)
    ICE = (178, 226, 250, 255)
    ICE_HI = (240, 251, 255, 255)
    ICE_LO = (120, 178, 220, 255)
    SHAFT = (104, 84, 66, 255)
    SHAFT_DK = (70, 56, 44, 255)
    GOLD = (232, 182, 76, 255)
    GOLD_DK = (168, 118, 40, 255)
    cx = 6 * S
    # shaft y 13..54
    d.polygon([(cx - 1.0 * S, 13 * S), (cx + 1.0 * S, 13 * S),
               (cx + 0.8 * S, 54 * S), (cx - 0.8 * S, 54 * S)], fill=SHAFT, outline=SHAFT_DK, width=S)
    # butt spike
    d.polygon([(cx - 1.2 * S, 54 * S), (cx + 1.2 * S, 54 * S), (cx, 55.8 * S)], fill=GOLD, outline=GOLD_DK, width=max(1, S // 2))
    # gold collar y 13..16
    d.rectangle([cx - 1.7 * S, 12.6 * S, cx + 1.7 * S, 16 * S], fill=GOLD, outline=GOLD_DK, width=S)
    # ice blade y 1..13 leaf shape
    d.polygon([(cx, 0.6 * S), (cx + 2.3 * S, 5 * S), (cx + 1.5 * S, 12.8 * S),
               (cx - 1.5 * S, 12.8 * S), (cx - 2.3 * S, 5 * S)], fill=ICE, outline=OUT, width=S)
    d.polygon([(cx, 1.6 * S), (cx + 0.9 * S, 5.4 * S), (cx + 0.5 * S, 12.2 * S),
               (cx - 0.5 * S, 12.2 * S), (cx - 0.8 * S, 5.4 * S)], fill=ICE_HI)
    d.line([(cx + 1.5 * S, 6 * S), (cx + 1.1 * S, 12.4 * S)], fill=ICE_LO, width=S)
    return _finish(im, W, H), (6, 40)


def draw_holy_staff():
    """Bạch Sa's holy staff: gold staff crowned with a sun orb.
    Canvas 16x46, grip at (8, 36)."""
    W, H, S = 16, 46, 4
    im = _canvas(W, H)
    d = ImageDraw.Draw(im)
    GOLD = (238, 200, 100, 255)
    GOLD_DK = (176, 132, 48, 255)
    ORB = (255, 244, 205, 255)
    ORB_HI = (255, 253, 240, 255)
    cx = 8 * S
    # staff y 14..44
    d.polygon([(cx - 1.1 * S, 14 * S), (cx + 1.1 * S, 14 * S),
               (cx + 0.8 * S, 44 * S), (cx - 0.8 * S, 44 * S)], fill=GOLD, outline=GOLD_DK, width=S)
    d.ellipse([cx - 1.8 * S, 42.4 * S, cx + 1.8 * S, 45.6 * S], fill=GOLD, outline=GOLD_DK, width=S)
    # sun rays around orb centre (cx, 8), r 5.5..7.6
    for ang in range(0, 360, 45):
        a = math.radians(ang)
        x0 = cx + 5.2 * S * math.cos(a)
        y0 = 8 * S + 5.2 * S * math.sin(a)
        x1 = cx + 7.4 * S * math.cos(a)
        y1 = 8 * S + 7.4 * S * math.sin(a)
        d.line([(x0, y0), (x1, y1)], fill=GOLD, width=int(1.4 * S))
    # orb ring + core
    d.ellipse([cx - 5.4 * S, 8 * S - 5.4 * S, cx + 5.4 * S, 8 * S + 5.4 * S],
              fill=(250, 222, 140, 255), outline=GOLD_DK, width=S)
    d.ellipse([cx - 3.6 * S, 8 * S - 3.6 * S, cx + 3.6 * S, 8 * S + 3.6 * S], fill=ORB)
    d.ellipse([cx - 1.8 * S, 8 * S - 2.2 * S, cx + 0.6 * S, 8 * S + 0.4 * S], fill=ORB_HI)
    return _finish(im, W, H), (8, 36)


WEAPON_DRAW = {
    "ngan_ky": draw_sword,
    "kim_hoa": draw_sceptre,
    "lam_bao": draw_spear,
    "bach_sa": draw_holy_staff,
}

# How much of the weapon arm's swing the weapon inherits at rest /
# walk / idle (1.0 = rigidly fixed to the hand). The spear is held
# near-vertical like a standard, so it follows least.
WEAPON_FOLLOW = {"ngan_ky": 0.85, "kim_hoa": 0.6, "lam_bao": 0.35, "bach_sa": 0.6}

# Owner rule (2026-11-11, generalised from Xích Diệm's fan in
# 14c-fix4-ter — "Mấy nhân vật khác nữa"): NO hero renders a weapon
# in the back directions. The rig compose code (unit.gd
# _rig_build_dir / _rig_pose) draws no weapon when a direction's
# "weapon" entry is an empty dict, so the dirs block emits {} for
# these dirs; nw is mirrored from ne and suppressed by the same
# set. The flat back sprites carry no weapon pixels, so hiding the
# weapon sprite removes the weapon completely. Front/side weapons
# stay exactly as authored.
NO_WEAPON_DIRS = {h: {"ne", "n", "nw"} for h in
                  ("ngan_ky", "kim_hoa", "lam_bao", "bach_sa")}

# Pose-curve family per weapon (hero_rig.gd / unit.gd switch on it).
WEAPON_CLASS = {"ngan_ky": "sword", "lam_bao": "spear",
                "kim_hoa": "staff", "bach_sa": "staff"}

# ---------------------------------------------------------------- rig specs
# Coordinates are SOURCE pixels of each direction sprite, read off
# 7x grid renders of the shipped art. poly = the part's silhouette;
# pivot = the joint it rotates around; hand = where the weapon grip
# sits at rest; phase = walk phase (legs 0/1 alternate).
#
# Only s/se/e/ne/n are authored; sw/w/nw are mirrored from se/e/ne
# (arm_l<->arm_r, leg_l<->leg_r swapped). Z-order defaults by facing
# class live in Z_DEFAULTS; per-dir overrides sit in the spec.

def arm(poly, pivot, hand):
    return {"poly": poly, "pivot": pivot, "hand": hand}


def leg(poly, pivot, phase, knee=None):
    d = {"poly": poly, "pivot": pivot, "phase": phase}
    if knee is not None:
        d["knee"] = knee
    return d


def shoe(poly, pivot, phase):
    return {"poly": poly, "pivot": pivot, "phase": phase}


def back(polys, pivot):
    return {"polys": polys, "pivot": pivot}


RIG = {
    # ------------------------------------------------ Ngân Kỵ (knight)
    "ngan_ky": {
        "s": {
            "order": ["leg_l", "leg_r", "back", "arm_l", "arm_r"],
            "back": back([[(0, 54), (6, 54), (7, 86), (0, 86)],
                          [(39, 54), (46, 54), (46, 86), (39, 86)]], (23, 40)),
            "arm_l": arm([(3, 43), (13, 42), (14, 58), (12, 69), (5, 69), (3, 60)], (8, 46), (8, 66)),
            "arm_r": arm([(33, 42), (43, 43), (43, 60), (41, 69), (34, 69), (32, 58)], (38, 46), (38, 66)),
            "leg_l": leg([(11, 68), (22, 68), (22, 92), (10, 92)], (15, 72), 0, knee=(16, 80)),
            "leg_r": leg([(23, 68), (36, 68), (36, 92), (23, 92)], (30, 72), 1, knee=(29, 80)),
            "weapon": {"arm": "arm_r", "rest": 150.0},
        },
        "se": {
            "back": back([[(1, 56), (10, 56), (10, 84), (2, 84)]], (21, 40)),
            "arm_l": arm([(5, 44), (13, 44), (13, 64), (6, 64), (4, 54)], (9, 47), (9, 61)),
            "arm_r": arm([(29, 43), (41, 44), (41, 64), (38, 71), (30, 70), (29, 57)], (35, 46), (35, 67)),
            "leg_l": leg([(12, 68), (22, 68), (22, 92), (11, 92)], (16, 72), 1, knee=(17, 80)),
            "leg_r": leg([(22, 68), (35, 68), (36, 92), (22, 92)], (28, 72), 0, knee=(28, 80)),
            "weapon": {"arm": "arm_r", "rest": 140.0},
        },
        "e": {
            # Near leg claims first: in side view the two boots
            # overlap in x, and the near boot must stay whole on
            # ONE leg or opposite-phase swings tear it in half.
            "order": ["arm_r", "leg_r", "leg_l", "back"],
            "back": back([[(2, 42), (22, 40), (20, 74), (16, 88), (4, 88), (0, 70)]], (20, 38)),
            "arm_r": arm([(24, 42), (35, 44), (35, 66), (32, 74), (25, 72), (23, 58)], (29, 46), (30, 70)),
            "leg_l": leg([(16, 69), (26, 69), (26, 92), (16, 92)], (21, 72), 1, knee=(21, 80)),
            "leg_r": leg([(24, 69), (36, 69), (36, 92), (24, 92)], (29, 72), 0, knee=(29, 80)),
            "weapon": {"arm": "arm_r", "rest": 128.0},
        },
        "ne": {
            "back": back([[(3, 40), (30, 40), (30, 86), (4, 86)]], (21, 38)),
            "arm_r": arm([(29, 42), (41, 44), (41, 66), (38, 74), (30, 72), (29, 56)], (35, 46), (36, 70)),
            "leg_l": leg([(14, 82), (26, 82), (26, 92), (14, 92)], (20, 84), 0),
            "leg_r": leg([(27, 82), (40, 82), (40, 92), (27, 92)], (33, 84), 1),
            "weapon": {"arm": "arm_r", "rest": 150.0},
        },
        "n": {
            "back": back([[(4, 40), (41, 40), (42, 84), (3, 84)]], (22, 38)),
            "arm_l": arm([(2, 42), (11, 42), (11, 72), (4, 72), (2, 60)], (7, 46), (7, 69)),
            "arm_r": arm([(34, 42), (43, 42), (43, 60), (41, 72), (34, 72), (34, 58)], (38, 46), (38, 69)),
            "leg_l": leg([(10, 80), (22, 80), (22, 92), (10, 92)], (16, 82), 0),
            "leg_r": leg([(23, 80), (35, 80), (35, 92), (23, 92)], (29, 82), 1),
            "weapon": {"arm": "arm_r", "rest": 165.0},
        },
    },
    # ------------------------------------------------ Lam Bào (knight)
    "lam_bao": {
        "s": {
            "back": back([[(0, 52), (8, 52), (8, 86), (1, 86)],
                          [(35, 52), (43, 52), (42, 86), (35, 86)]], (21, 40)),
            "arm_l": arm([(5, 38), (14, 38), (14, 66), (11, 73), (6, 72), (5, 56)], (10, 42), (9, 69)),
            "arm_r": arm([(29, 38), (38, 38), (38, 56), (37, 72), (32, 73), (29, 66)], (33, 42), (34, 69)),
            "leg_l": leg([(9, 70), (19, 70), (19, 92), (9, 92)], (14, 74), 0, knee=(14, 82)),
            "leg_r": leg([(24, 70), (34, 70), (34, 92), (24, 92)], (29, 74), 1, knee=(29, 82)),
            "weapon": {"arm": "arm_r", "rest": 16.0},
        },
        "se": {
            "back": back([[(1, 52), (10, 52), (10, 86), (2, 86)]], (19, 40)),
            "arm_l": arm([(6, 42), (13, 42), (13, 62), (7, 62), (5, 52)], (10, 45), (10, 59)),
            "arm_r": arm([(25, 41), (36, 42), (36, 64), (33, 72), (26, 70), (25, 55)], (30, 44), (31, 68)),
            "leg_l": leg([(11, 70), (20, 70), (20, 92), (11, 92)], (15, 74), 1, knee=(15, 82)),
            "leg_r": leg([(20, 70), (31, 70), (31, 92), (20, 92)], (25, 74), 0, knee=(25, 82)),
            "weapon": {"arm": "arm_r", "rest": 20.0},
        },
        "e": {
            "order": ["arm_r", "leg_r", "leg_l", "back"],
            "back": back([[(1, 42), (22, 40), (20, 74), (15, 88), (3, 88), (0, 66)]], (19, 38)),
            "arm_r": arm([(23, 40), (34, 42), (34, 66), (31, 75), (24, 73), (23, 56)], (28, 44), (29, 71)),
            "leg_l": leg([(19, 70), (27, 70), (27, 92), (19, 92)], (23, 74), 1, knee=(23, 82)),
            "leg_r": leg([(25, 70), (35, 70), (35, 92), (25, 92)], (30, 74), 0, knee=(30, 82)),
            "weapon": {"arm": "arm_r", "rest": 35.0},
        },
        "ne": {
            "back": back([[(5, 40), (33, 40), (34, 84), (6, 84)]], (20, 38)),
            "arm_r": arm([(31, 42), (40, 44), (40, 68), (37, 75), (31, 72), (30, 56)], (35, 46), (36, 71)),
            "leg_l": leg([(12, 82), (24, 82), (24, 92), (12, 92)], (18, 84), 0),
            "leg_r": leg([(25, 82), (37, 82), (37, 92), (25, 92)], (31, 84), 1),
            "weapon": {"arm": "arm_r", "rest": 10.0},
        },
        "n": {
            "back": back([[(5, 40), (39, 40), (40, 84), (4, 84)]], (22, 38)),
            "arm_l": arm([(2, 42), (10, 42), (10, 74), (3, 74), (2, 58)], (6, 46), (6, 70)),
            "arm_r": arm([(34, 42), (42, 42), (42, 58), (41, 74), (34, 74), (34, 58)], (38, 46), (38, 70)),
            "leg_l": leg([(10, 80), (22, 80), (22, 92), (10, 92)], (16, 82), 0),
            "leg_r": leg([(23, 80), (35, 80), (35, 92), (23, 92)], (29, 82), 1),
            "weapon": {"arm": "arm_r", "rest": 12.0},
        },
    },
    # ------------------------------------------------ Kim Hoa (gown)
    # No visible legs: leg_l/leg_r are the two HEM panels (+ shoes).
    "kim_hoa": {
        "s": {
            "order": ["shoe_l", "shoe_r", "arm_l", "arm_r", "leg_l", "leg_r"],
            "shoe_l": shoe([(14, 85), (22, 85), (22, 92), (14, 92)], (18, 86), 0),
            "shoe_r": shoe([(22, 85), (30, 85), (30, 92), (22, 92)], (26, 86), 1),
            "arm_l": arm([(11, 44), (19, 44), (18, 60), (15, 66), (11, 60), (10, 52)], (14, 46), (15, 62)),
            "arm_r": arm([(25, 44), (33, 44), (33, 60), (29, 66), (26, 60), (25, 52)], (29, 46), (29, 62)),
            "leg_l": leg([(2, 76), (22, 76), (22, 92), (2, 92)], (13, 78), 0),
            "leg_r": leg([(22, 76), (42, 76), (42, 92), (22, 92)], (31, 78), 1),
            "weapon": {"arm": "arm_r", "rest": 10.0},
        },
        "se": {
            "order": ["shoe_l", "shoe_r", "arm_r", "leg_l", "leg_r"],
            "shoe_l": shoe([(16, 84), (23, 84), (23, 91), (16, 91)], (19, 85), 1),
            "shoe_r": shoe([(23, 84), (31, 84), (31, 91), (23, 91)], (27, 85), 0),
            "arm_r": arm([(25, 46), (34, 46), (34, 62), (29, 67), (25, 60), (24, 53)], (29, 48), (29, 63)),
            "leg_l": leg([(4, 74), (22, 74), (22, 91), (4, 91)], (13, 76), 1),
            "leg_r": leg([(22, 74), (40, 74), (40, 91), (22, 91)], (31, 76), 0),
            "weapon": {"arm": "arm_r", "rest": 16.0},
        },
        "e": {
            "order": ["shoe_r", "arm_r", "leg_l", "leg_r", "back"],
            "shoe_r": shoe([(23, 83), (34, 83), (34, 90), (23, 90)], (28, 84), 0),
            "back": back([[(0, 4), (24, 2), (22, 44), (18, 68), (6, 68), (0, 44)]], (12, 10)),
            "arm_r": arm([(23, 46), (32, 46), (32, 62), (28, 67), (23, 60), (22, 53)], (27, 48), (28, 63)),
            "leg_l": leg([(2, 72), (20, 72), (20, 90), (2, 90)], (11, 74), 1),
            "leg_r": leg([(20, 72), (38, 72), (38, 90), (20, 90)], (28, 74), 0),
            "weapon": {"arm": "arm_r", "rest": 22.0},
        },
        "ne": {
            "leg_l": leg([(3, 68), (21, 68), (21, 90), (3, 90)], (12, 70), 0),
            "leg_r": leg([(21, 68), (39, 68), (39, 90), (21, 90)], (30, 70), 1),
            "weapon": {"arm": "arm_r", "rest": 6.0, "hand": (37, 64), "wz": -1},
        },
        "n": {
            "leg_l": leg([(3, 68), (21, 68), (21, 90), (3, 90)], (12, 70), 0),
            "leg_r": leg([(21, 68), (38, 68), (38, 90), (21, 90)], (29, 70), 1),
            # 14c-fix4: hand x 36 -> 40. At x=36 the flower head of
            # her staff (z=-1 behind the back view) landed inside
            # the hair silhouette and the staff vanished in the
            # straight back view; at the silhouette edge it reads
            # held at her side, like Bạch Sa's sun staff (ne keeps
            # its authored 37 — it already clears the edge there).
            "weapon": {"arm": "arm_r", "rest": 6.0, "hand": (40, 64), "wz": -1},
        },
    },
    # ------------------------------------------------ Bạch Sa (veil gown)
    # Arms are sleeve patches merged into the veil; legs are hem
    # panels. The smallest amplitudes of the cast (see TUNING).
    "bach_sa": {
        "s": {
            "order": ["shoe_l", "shoe_r", "arm_l", "arm_r", "leg_l", "leg_r"],
            "shoe_l": shoe([(15, 86), (23, 86), (23, 92), (15, 92)], (19, 87), 0),
            "shoe_r": shoe([(23, 86), (31, 86), (31, 92), (23, 92)], (27, 87), 1),
            "arm_l": arm([(10, 42), (20, 42), (21, 52), (19, 62), (13, 66), (9, 58)], (15, 45), (14, 60)),
            "arm_r": arm([(26, 42), (36, 42), (37, 58), (33, 66), (27, 62), (25, 52)], (31, 45), (32, 60)),
            "leg_l": leg([(3, 74), (23, 74), (23, 92), (3, 92)], (13, 76), 0),
            "leg_r": leg([(23, 74), (43, 74), (43, 92), (23, 92)], (33, 76), 1),
            "weapon": {"arm": "arm_r", "rest": 8.0},
        },
        "se": {
            "order": ["shoe_l", "shoe_r", "arm_r", "leg_l", "leg_r"],
            "shoe_l": shoe([(14, 85), (22, 85), (22, 91), (14, 91)], (18, 86), 1),
            "shoe_r": shoe([(22, 85), (30, 85), (30, 91), (22, 91)], (26, 86), 0),
            "arm_r": arm([(24, 44), (34, 44), (35, 58), (30, 64), (25, 58), (24, 51)], (29, 46), (30, 59)),
            "leg_l": leg([(4, 74), (21, 74), (21, 91), (4, 91)], (12, 76), 1),
            "leg_r": leg([(21, 74), (40, 74), (40, 91), (21, 91)], (30, 76), 0),
            "weapon": {"arm": "arm_r", "rest": 14.0},
        },
        "e": {
            "order": ["shoe_r", "arm_r", "leg_l", "leg_r"],
            "shoe_r": shoe([(26, 85), (37, 85), (37, 91), (26, 91)], (31, 86), 0),
            "arm_r": arm([(25, 46), (35, 46), (36, 60), (31, 66), (26, 60), (24, 53)], (30, 48), (31, 61)),
            "leg_l": leg([(4, 72), (22, 72), (22, 91), (4, 91)], (13, 74), 1),
            "leg_r": leg([(22, 72), (41, 72), (41, 91), (22, 91)], (31, 74), 0),
            "weapon": {"arm": "arm_r", "rest": 18.0},
        },
        "ne": {
            "leg_l": leg([(4, 70), (20, 70), (20, 91), (4, 91)], (12, 72), 0),
            "leg_r": leg([(20, 70), (38, 70), (38, 91), (20, 91)], (29, 72), 1),
            "weapon": {"arm": "arm_r", "rest": 6.0, "hand": (35, 62), "wz": -1},
        },
        "n": {
            "leg_l": leg([(4, 70), (22, 70), (22, 91), (4, 91)], (13, 72), 0),
            "leg_r": leg([(22, 70), (40, 70), (40, 91), (22, 91)], (31, 72), 1),
            "weapon": {"arm": "arm_r", "rest": 6.0, "hand": (38, 62), "wz": -1},
        },
    },
}

# Per-character animation personality (radians / multipliers).
# leg_amp: full THIGH swing in side views (13n follow-up: Tín
# reported the v2 walk read as static — the old 0.42 rad on a
# 17 px shin-only segment moved the foot ~4 screen px; the thigh
# now runs from the hip (~25 px reach) at ±0.55-0.58 rad with a
# knee fold on top). Front/back views use FRONT_LEG_FACTOR of it
# plus a foot lift. knee_fold: peak shin fold (rad) mid-swing for
# the two-segment knight legs. hem_lag: gown hem panels trail the
# stride phase by this many radians; shoe_amp scales the gowns'
# shoe slide/lift (their only real "feet").
TUNING = {
    "ngan_ky": {"leg_amp": 0.58, "arm_amp": 0.30, "cadence": 1.00, "bob": 2.4,
                "knee_fold": 0.78, "hem_lag": 0.0, "shoe_amp": 0.0},
    "lam_bao": {"leg_amp": 0.55, "arm_amp": 0.27, "cadence": 0.95, "bob": 2.2,
                "knee_fold": 0.72, "hem_lag": 0.0, "shoe_amp": 0.0},
    "kim_hoa": {"leg_amp": 0.30, "arm_amp": 0.18, "cadence": 0.85, "bob": 1.8,
                "knee_fold": 0.0, "hem_lag": 0.7, "shoe_amp": 1.35},
    "bach_sa": {"leg_amp": 0.26, "arm_amp": 0.12, "cadence": 0.80, "bob": 1.5,
                "knee_fold": 0.0, "hem_lag": 0.7, "shoe_amp": 1.25},
}
FRONT_LEG_FACTOR = 0.8

# Default intra-hero draw order by facing class. "under" is the
# synthesised body-core layer (see cut_parts): it sits above the
# cape/back layer and below everything else, invisible at rest.
Z_FRONT = {"back": 0, "under": 1, "leg_l": 2, "leg_r": 2, "torso": 3, "arm_l": 4, "arm_r": 4}
Z_SIDE = {"back": 0, "under": 1, "leg_l": 2, "leg_r": 3, "torso": 4, "arm_l": 5, "arm_r": 5}
Z_BACK = {"back": 0, "under": 1, "leg_l": 2, "leg_r": 2, "torso": 3, "arm_l": 4, "arm_r": 4}
WEAPON_Z = 6

MIRROR_OF = {"sw": "se", "w": "e", "nw": "ne"}
FRONT_DIRS = ("s", "se", "sw")
BACK_DIRS = ("n", "ne", "nw")

# ---------------------------------------------------------------- engine

def poly_mask(size, poly):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon([(float(x), float(y)) for x, y in poly], fill=255)
    return m


def mask_and(a, b):
    return Image.composite(a, Image.new("L", a.size, 0), b)


def mask_sub(a, b):
    inv = b.point(lambda v: 255 - v)
    return mask_and(a, inv)


def mask_or(a, b):
    return Image.max(a, b) if hasattr(Image, "max") else \
        Image.composite(Image.new("L", a.size, 255), a, b)


def mirror_spec(spec, w_src, w_dst):
    """Mirror an authored spec for the opposite-side direction."""
    dx = (w_dst - w_src) / 2.0

    def mx(x):
        return (w_src - 1 - x) + dx

    def mpt(p):
        return (mx(p[0]), p[1])

    out = {}
    swap = {"arm_l": "arm_r", "arm_r": "arm_l", "leg_l": "leg_r", "leg_r": "leg_l",
            "shoe_l": "shoe_r", "shoe_r": "shoe_l"}
    for key, val in spec.items():
        if key in ("arm_l", "arm_r", "leg_l", "leg_r", "shoe_l", "shoe_r"):
            nv = {"poly": [mpt(p) for p in val["poly"]],
                  "pivot": mpt(val["pivot"])}
            if "hand" in val:
                nv["hand"] = mpt(val["hand"])
            if "phase" in val:
                nv["phase"] = val["phase"]
            if "knee" in val:
                nv["knee"] = mpt(val["knee"])
            out[swap[key]] = nv
        elif key == "back":
            out["back"] = {"polys": [[mpt(p) for p in poly] for poly in val["polys"]],
                           "pivot": mpt(val["pivot"])}
        elif key == "weapon":
            nv = dict(val)
            nv["arm"] = swap.get(val["arm"], val["arm"])
            nv["rest"] = -val["rest"]
            if "hand" in val:
                nv["hand"] = mpt(val["hand"])
            out["weapon"] = nv
        elif key == "order":
            out["order"] = [swap.get(k, k) for k in val]
    return out


def full_specs(char):
    """Authored 5 dirs + mirrored 3, keyed by dir."""
    authored = RIG[char]
    specs = dict(authored)
    for dst, src in MIRROR_OF.items():
        w_src = Image.open(os.path.join(ASSETS, "king_%s_%s.png" % (char, src))).width
        w_dst = Image.open(os.path.join(ASSETS, "king_%s_%s.png" % (char, dst))).width
        specs[dst] = mirror_spec(authored[src], w_src, w_dst)
    return specs


PART_KEYS = ["back", "leg_l", "leg_r", "arm_l", "arm_r"]


def part_z(zmap, key):
    """Draw order for a part key; shins and shoes ride at their
    leg's z (they are that leg's lower segment / foot)."""
    if key.startswith("shin_") or key.startswith("shoe_"):
        return zmap.get("leg_" + key[-1], 2)
    return zmap.get(key, 2)


def cut_parts(char, dir8, spec):
    """Partition the source sprite. Returns {part: full-canvas RGBA}
    plus a reassembly-diff count (pixels differing from source)."""
    src = Image.open(os.path.join(ASSETS, "king_%s_%s.png" % (char, dir8))).convert("RGBA")
    W, H = src.size
    opaque = src.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    claimed = Image.new("L", (W, H), 0)
    masks = {}

    def claim(key, mask):
        m = mask_sub(mask, claimed)
        masks[key] = m
        return m

    order = spec.get("order", ["arm_l", "arm_r", "leg_l", "leg_r", "back"])
    for key in order:
        if key not in spec:
            continue
        if key == "back":
            m = Image.new("L", (W, H), 0)
            for poly in spec["back"]["polys"]:
                m = mask_or(m, poly_mask((W, H), poly))
            claim("back", m)
        else:
            claim(key, poly_mask((W, H), spec[key]["poly"]))
        claimed = mask_or(claimed, masks[key])
    # Torso = everything opaque that nobody claimed.
    masks["torso"] = mask_sub(opaque, claimed)

    # --- Two-segment legs (13n follow-up): a leg spec with a
    # "knee" splits at the knee line into the thigh (leg_x) and a
    # shin part (shin_x). The shin keeps a 3 px cap copy of the
    # rows just above the line so folding the knee never opens a
    # gap at its front; the thigh keeps its own copy of those
    # rows too, so the rest composite stays pixel-exact.
    for key in ("leg_l", "leg_r"):
        if key in spec and "knee" in spec[key] and key in masks:
            ky = int(round(spec[key]["knee"][1]))
            above = poly_mask((W, H), [(0, 0), (W, 0), (W, ky), (0, ky)])
            full = Image.new("L", (W, H), 255)
            shin = mask_and(masks[key], mask_sub(full, above))
            cap = mask_and(masks[key], poly_mask((W, H),
                           [(0, ky - 3), (W, ky - 3), (W, ky), (0, ky)]))
            masks["shin_" + key[-1]] = mask_or(shin, cap)
            masks[key] = mask_and(masks[key], above)

    # Joint insurance: shoulder caps into arms, thigh bands into legs
    # (copies — the owner part keeps its own pixels; see header).
    # Knee'd legs skip the top band: their polys already reach the
    # fauld, and a band would drag belt pixels into the thigh.
    for key in ("arm_l", "arm_r"):
        if key in spec:
            px, py = spec[key]["pivot"]
            cap = Image.new("L", (W, H), 0)
            ImageDraw.Draw(cap).ellipse([px - 7, py - 7, px + 7, py + 7], fill=255)
            masks[key] = mask_or(masks[key], mask_and(cap, opaque))
    for key in ("leg_l", "leg_r"):
        if key in spec and "knee" not in spec[key]:
            shifted = [(x, y - 6) for x, y in spec[key]["poly"]]
            band = mask_and(poly_mask((W, H), shifted), opaque)
            band = mask_and(band, poly_mask((W, H), [(0, 0), (W, 0),
                                    (W, spec[key]["pivot"][1] + 1), (0, spec[key]["pivot"][1] + 1)]))
            masks[key] = mask_or(masks[key], band)

    parts = {}
    for key, m in masks.items():
        if m.getbbox() is None:
            continue
        part = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        part.paste(src, (0, 0), m)
        parts[key] = part

    # --- "under": a body-core filler behind arms/legs/torso.
    # Rotating an arm away vacates the pixels it owned; with only
    # the partition there, the body would show a see-through hole.
    # under = the body silhouette (torso+arms+legs, NOT the cape)
    # eroded 1px, filled with the nearest torso colour (slightly
    # darkened, like an under-layer in shadow). At rest it is fully
    # covered by the real parts, so reassembly stays pixel-exact.
    from PIL import ImageFilter
    body = Image.new("L", (W, H), 0)
    for key in ("torso", "arm_l", "arm_r", "leg_l", "leg_r", "shin_l", "shin_r"):
        if key in masks:
            # Intersect with the real silhouette: the claim masks
            # are raw polygons whose corners can stick out past
            # the art (e.g. hem rectangles at a flared skirt).
            body = mask_or(body, mask_and(masks[key], opaque))
    # Erode by 2: the sprites' defringed silhouette edges are
    # semi-transparent for ~2px, and under must hide beneath FULLY
    # opaque part pixels or the rest composite would differ.
    under_m = body.filter(ImageFilter.MinFilter(5))
    # Fill = the source art itself, blurred and slightly darkened:
    # where a part rotates away, what shows is a soft smear of the
    # local body colours (armour under an arm, dress under a
    # sleeve) instead of a hole — or of a directional fill, which
    # streaked (see 13n notes). Alpha comes from under_m alone.
    from PIL import ImageEnhance
    blurred = src.filter(ImageFilter.GaussianBlur(1.5))
    blurred.putalpha(under_m)
    under = ImageEnhance.Brightness(blurred).enhance(0.92)
    under.putalpha(under_m)
    parts["under"] = under

    # Verify: z-order composite at rest == source (report diffs).
    zmap = Z_FRONT if dir8 in FRONT_DIRS else (Z_BACK if dir8 in BACK_DIRS else Z_SIDE)
    comp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for key in sorted(parts, key=lambda k: part_z(zmap, k)):
        comp.alpha_composite(parts[key])
    diff = 0
    sp, cp = src.load(), comp.load()
    for y in range(H):
        for x in range(W):
            if sp[x, y] != cp[x, y]:
                diff += 1
    return src, parts, diff


def rotate_about(img, pivot, godot_deg):
    """Rotate a full-canvas image around a pivot, Godot semantics
    (positive = clockwise on screen). PIL rotates CCW-positive, so
    the angle is negated."""
    return img.rotate(-godot_deg, resample=Image.BICUBIC,
                      center=(float(pivot[0]), float(pivot[1])))


RENDER_MARGIN = (18, 12)  # QA canvas slack for raised limbs/weapons


def render_composite(parts, pivots, zmap, angles=None, weapon=None, offsets=None):
    """angles: {part: godot degrees}. offsets: {part: (dx, dy)}.
    weapon: (img, grip, pos, deg, z). Returns the composited RGBA
    on a canvas padded by RENDER_MARGIN (Godot draws parts as
    separate nodes and never clips; the pad keeps QA honest)."""
    size = next(iter(parts.values())).size
    mx, my = RENDER_MARGIN
    full = (size[0] + mx * 2, size[1] + my * 2)
    comp = Image.new("RGBA", full, (0, 0, 0, 0))
    angles = angles or {}
    offsets = offsets or {}
    items = []
    for key, img in parts.items():
        items.append((zmap.get(key, 2), key, img))
    if weapon is not None:
        items.append((weapon[4], "weapon", None))
    items.sort(key=lambda t: t[0])
    for _z, key, img in items:
        if key == "weapon":
            wimg, grip, pos, deg, _wz = weapon
            # Rotate on a big scratch canvas with the grip pinned
            # at its centre: rotating the small weapon canvas in
            # place would clip the blade at any large angle.
            big = Image.new("RGBA", (180, 180), (0, 0, 0, 0))
            big.alpha_composite(wimg, (90 - grip[0], 90 - grip[1]))
            rot = big.rotate(-deg, resample=Image.BICUBIC, center=(90.0, 90.0))
            comp.alpha_composite(rot, (int(round(pos[0])) + mx - 90,
                                       int(round(pos[1])) + my - 90))
        else:
            a = angles.get(key, 0.0)
            # Pad BEFORE rotating so limb tips that swing past the
            # sprite's own canvas survive (Godot nodes never clip;
            # a PIL rotate inside the small canvas would).
            padded = Image.new("RGBA", full, (0, 0, 0, 0))
            padded.alpha_composite(img, (mx, my))
            pv = (pivots[key][0] + mx, pivots[key][1] + my)
            out = rotate_about(padded, pv, a) if a else padded
            off = offsets.get(key, (0, 0))
            comp.alpha_composite(out, (int(round(off[0])), int(round(off[1]))))
    return comp


def compose_shins(spec, ang, offs, knee_rot):
    """Fold knee rotations into absolute shin transforms: the
    shin rotates about the knee by thigh+knee, and its offset
    carries the knee point to where the thigh's rotation put it
    (Godot rotation convention, same as weapon_at's hand math)."""
    for suf in ("l", "r"):
        lk, sk = "leg_" + suf, "shin_" + suf
        if lk in spec and "knee" in spec[lk]:
            hip = spec[lk]["pivot"]
            knee = spec[lk]["knee"]
            ta = math.radians(ang.get(lk, 0.0))
            dx, dy = knee[0] - hip[0], knee[1] - hip[1]
            kx = hip[0] + dx * math.cos(ta) - dy * math.sin(ta)
            ky = hip[1] + dx * math.sin(ta) + dy * math.cos(ta)
            ang[sk] = ang.get(lk, 0.0) + knee_rot.get(lk, 0.0)
            lo = offs.get(lk, (0.0, 0.0))
            offs[sk] = (kx - knee[0] + lo[0], ky - knee[1] + lo[1])


def walk_pose(char, dir8, spec, phase):
    """The walk cycle (13n follow-up curves — mirrors the walk
    branch of Unit._rig_pose; keep the two in sync). Returns
    (angles_deg, offsets) including composed shin entries and
    gown shoe slides. phase = the stride phase in radians."""
    tun = TUNING[char]
    side = dir8 in ("e", "w")
    swing = -1.0 if dir8 in ("w", "sw", "nw") else 1.0
    leg_amp = tun["leg_amp"] * (1.0 if side else FRONT_LEG_FACTOR)
    ang, offs, knee_rot = {}, {}, {}
    for key in ("leg_l", "leg_r"):
        if key not in spec:
            continue
        th = phase + spec[key]["phase"] * math.pi
        w = math.sin(th)
        lift = max(0.0, math.cos(th))  # peaks mid swing-through
        ang[key] = math.degrees(leg_amp) * w * (swing if side else 1.0)
        if side:
            offs[key] = (0.0, -1.2 * lift)
        else:
            out = -1.0 if key == "leg_l" else 1.0
            offs[key] = (out * 1.2 * lift, -4.0 * lift)
        fold = tun["knee_fold"] * (lift ** 1.5) * (1.0 if side else 0.35)
        knee_rot[key] = math.degrees(fold) * swing
    warm = spec.get("weapon", {}).get("arm", "")
    for key in ("arm_l", "arm_r"):
        if key in spec:
            f = 0.45 if key == warm else 1.0
            leg_key = "leg_l" if key == "arm_l" else "leg_r"
            lph = spec.get(leg_key, spec.get("leg_l", {"phase": 0}))["phase"]
            w = math.sin(phase + lph * math.pi)
            ang[key] = -math.degrees(tun["arm_amp"]) * f * w * (swing if side else 1.0)
    if tun["hem_lag"]:
        # Gown hem panels trail the stride; side views also drag
        # the hem tips backwards along the ground line.
        for key in ("leg_l", "leg_r"):
            if key in spec:
                th = phase - tun["hem_lag"] + spec[key]["phase"] * math.pi
                ang[key] = math.degrees(leg_amp) * math.sin(th) * (swing if side else 1.0)
                if side:
                    offs[key] = (-math.sin(th) * 1.8 * swing, offs[key][1])
    for key in ("shoe_l", "shoe_r"):
        if key in spec:
            th = phase + spec[key]["phase"] * math.pi
            dx = math.sin(th) * 3.6 * tun["shoe_amp"] * (swing if side else 0.6)
            dy = -max(0.0, math.cos(th)) * 3.0 * tun["shoe_amp"]
            offs[key] = (dx, dy)
            ang[key] = math.sin(th) * 5.2
    compose_shins(spec, ang, offs, knee_rot)
    return ang, offs


def qa_pose_angles(char, dir8, spec, pose):
    """Canned poses mirroring hero_rig.gd's pose curves (QA only —
    the in-engine captures are the ground truth). "attack" is the
    STRIKE frame, "cast" the APEX frame. Returns (angles, offsets,
    weapon_abs_deg or None). Angles in Godot degrees."""
    tun = TUNING[char]
    side = dir8 in ("e", "w")
    swing = -1.0 if dir8 in ("w", "sw", "nw") else 1.0
    leg_amp = tun["leg_amp"] * (1.0 if side else FRONT_LEG_FACTOR)
    ang = {}
    offs = {}
    wabs = None
    warm = spec.get("weapon", {}).get("arm", "")
    rest = spec.get("weapon", {}).get("rest", 0.0)
    if pose in ("walk_a", "walk_b"):
        ang, offs = walk_pose(char, dir8, spec,
                              math.pi / 2 if pose == "walk_a" else 3 * math.pi / 2)
        return ang, offs, None
    elif pose == "attack":
        other = "arm_l" if warm == "arm_r" else "arm_r"
        if other in spec:
            ang[other] = -14.0 * swing
        for key in ("leg_l", "leg_r"):
            if key in spec and spec[key]["phase"] == 0:
                ang[key] = 13.0 * swing
        if char == "ngan_ky":      # sword mid-slash
            if warm in spec:
                ang[warm] = -8.0 if side else -18.0
            wabs = (168.0 if side else 190.0) * swing
        elif char == "lam_bao":    # spear thrust, levelled
            if warm in spec:
                ang[warm] = 12.0 * swing
            wabs = (92.0 if side else 55.0) * swing
        else:                      # staff tap forward
            if warm in spec:
                ang[warm] = 16.0 * swing
            wabs = rest + (40.0 if side else 34.0) * swing
    elif pose == "cast":
        other = "arm_l" if warm == "arm_r" else "arm_r"
        if other in spec:
            ang[other] = 30.0 * swing
        if warm in spec:
            ang[warm] = -108.0 * swing if side else -112.0
        wabs = {"ngan_ky": -18.0, "lam_bao": -24.0,
                "kim_hoa": -8.0, "bach_sa": -6.0}[char] * (swing if side else 1.0)
    compose_shins(spec, ang, offs, {})  # attack/cast: knees straight, shins follow
    return ang, offs, wabs

# ---------------------------------------------------------------- main

def weapon_at(spec, angles, wimg, grip):
    """Weapon render tuple for render_composite at the given arm
    angles: the grip follows the weapon arm's hand rotated around
    the shoulder pivot; the weapon's own angle = rest + arm angle
    (+ any pose extra handled by the caller via 'rest' override)."""
    wspec = spec["weapon"]
    arm_key = wspec["arm"]
    hand = wspec.get("hand")
    if hand is None and arm_key in spec:
        hand = spec[arm_key]["hand"]
    pivot = spec[arm_key]["pivot"] if arm_key in spec else hand
    a = math.radians(angles.get(arm_key, 0.0))
    dx, dy = hand[0] - pivot[0], hand[1] - pivot[1]
    hx = pivot[0] + dx * math.cos(a) - dy * math.sin(a)
    hy = pivot[1] + dx * math.sin(a) + dy * math.cos(a)
    if "_abs" in wspec:
        deg = wspec["_abs"]
    else:
        deg = wspec["rest"] + angles.get(arm_key, 0.0) * wspec.get("_follow", 1.0) \
            + wspec.get("_extra", 0.0)
    return (wimg, grip, (hx, hy), deg, wspec.get("wz", WEAPON_Z))


def main():
    os.makedirs(PARTS_DIR, exist_ok=True)
    os.makedirs(WEAPONS_DIR, exist_ok=True)
    rig = {"chars": {}}
    total_diff = 0
    worst = []
    exploded_rows = []   # (char, dir, [part imgs], reassembled)
    pose_cells = []      # (label, img)
    weapons = {}
    for char in CHARS:
        wimg, grip = WEAPON_DRAW[char]()
        wpath = os.path.join(WEAPONS_DIR, char + ".png")
        wimg.save(wpath)
        weapons[char] = (wimg, grip)
        rig["chars"][char] = {"tuning": TUNING[char],
                              "wclass": WEAPON_CLASS[char],
                              "front_leg_factor": FRONT_LEG_FACTOR,
                              "weapon": {"tex": "hero_weapons/%s.png" % char,
                                         "grip": list(grip)},
                              "dirs": {}}
        specs = full_specs(char)
        for dir8 in DIRS:
            spec = specs[dir8]
            src, parts, diff = cut_parts(char, dir8, spec)
            total_diff += diff
            worst.append((diff, char, dir8))
            zmap = Z_FRONT if dir8 in FRONT_DIRS else (Z_BACK if dir8 in BACK_DIRS else Z_SIDE)
            pivots = {}
            dentry = {"canvas": list(src.size),
                      "swing": -1 if dir8 in ("w", "sw", "nw") else 1,
                      "parts": {}}
            for key, img in parts.items():
                img.save(os.path.join(PARTS_DIR, "%s_%s_%s.png" % (char, dir8, key)))
                if key in spec:
                    pv = spec[key]["pivot"]
                elif key.startswith("shin_"):
                    pv = spec["leg_" + key[-1]]["knee"]  # shin pivots on the knee
                else:
                    pv = (src.width / 2.0, 30.0)
                pivots[key] = pv
                dentry["parts"][key] = {"tex": "hero_parts/%s_%s_%s.png" % (char, dir8, key),
                                        "pivot": [round(float(pv[0]), 1), round(float(pv[1]), 1)],
                                        "z": part_z(zmap, key)}
                if key in spec and "phase" in spec[key]:
                    dentry["parts"][key]["phase"] = spec[key]["phase"]
                if key in spec and "knee" in spec[key]:
                    kn = spec[key]["knee"]
                    dentry["parts"][key]["knee"] = [round(float(kn[0]), 1),
                                                    round(float(kn[1]), 1)]
            wspec = dict(spec["weapon"])
            warm = wspec["arm"]
            hand = wspec.get("hand", spec[warm]["hand"] if warm in spec else (0, 0))
            if dir8 in NO_WEAPON_DIRS.get(char, set()):
                dentry["weapon"] = {}
            else:
                dentry["weapon"] = {"arm": warm, "hand": [float(hand[0]), float(hand[1])],
                                    "rest": float(wspec["rest"]), "z": int(wspec.get("wz", WEAPON_Z)),
                                    "follow": WEAPON_FOLLOW[char]}
            rig["chars"][char]["dirs"][dir8] = dentry
            # QA captures
            exploded_rows.append((char, dir8, parts, zmap))
            if dir8 in ("s", "e"):
                for pose in ("walk_a", "walk_b", "attack", "cast"):
                    ang, offs, wabs = qa_pose_angles(char, dir8, spec, pose)
                    spec2 = dict(spec)
                    spec2["weapon"] = dict(spec["weapon"])
                    if wabs is not None:
                        spec2["weapon"]["_abs"] = wabs
                    wt = weapon_at(spec2, ang, wimg, grip)
                    pose_cells.append(("%s %s %s" % (char, dir8, pose),
                                       render_composite(parts, pivots, zmap, ang, wt, offs)))
    with open(os.path.join(ASSETS, "hero_rig.json"), "w") as f:
        json.dump(rig, f, indent=1, ensure_ascii=False)
    worst.sort(reverse=True)
    print("reassembly diff total:", total_diff, "worst:", worst[:6])

    # ---- exploded contact sheet: per char, 8 dirs x parts + assembly
    S = 3
    cols = ["back", "under", "leg_l", "leg_r", "torso", "arm_l", "arm_r", "rest"]
    cellw, cellh = 52 * S, 96 * S + 14
    sheet = Image.new("RGBA", (cellw * len(cols), cellh * 8 * len(CHARS)), (26, 26, 36, 255))
    dr = ImageDraw.Draw(sheet)
    row = 0
    by_key = {}
    for char, dir8, parts, zmap in exploded_rows:
        by_key[(char, dir8)] = (parts, zmap)
    for char in CHARS:
        specs = full_specs(char)
        for dir8 in DIRS:
            parts, zmap = by_key[(char, dir8)]
            spec = specs[dir8]
            pivots = {k: (spec[k]["pivot"] if k in spec else
                          (spec["leg_" + k[-1]]["knee"] if k.startswith("shin_")
                           else (0, 0))) for k in parts}
            y0 = row * cellh
            for ci, key in enumerate(cols):
                x0 = ci * cellw
                if key == "rest":
                    wt = weapon_at(spec, {}, *weapons[char])
                    img = render_composite(parts, pivots, zmap, {}, wt)
                    mx, my = RENDER_MARGIN
                    sw, sh = next(iter(parts.values())).size
                    img = img.crop((mx, my, mx + sw, my + sh))
                elif key in parts:
                    img = parts[key]
                else:
                    continue
                big = img.resize((img.width * S, img.height * S), Image.NEAREST)
                sheet.paste(big, (x0 + (cellw - big.width) // 2, y0 + 12), big)
                if key in pivots and key != "rest":
                    px, py = pivots[key]
                    cxp = x0 + (cellw - big.width) // 2 + int(px * S)
                    cyp = y0 + 12 + int(py * S)
                    dr.ellipse([cxp - 4, cyp - 4, cxp + 4, cyp + 4], outline=(255, 80, 80, 255), width=2)
            dr.text((4, y0 + 1), "%s %s" % (char, dir8), fill=(255, 255, 160, 255))
            row += 1
    sheet.save("/tmp/rig_exploded.png")

    # ---- pose sheet (render_composite already pads its canvas)
    pw = 88 * S
    ph = 122 * S + 14
    cols_n = 4
    rows_n = (len(pose_cells) + cols_n - 1) // cols_n
    psheet = Image.new("RGBA", (pw * cols_n, ph * rows_n), (26, 26, 36, 255))
    pdr = ImageDraw.Draw(psheet)
    for i, (label, img) in enumerate(pose_cells):
        r, c = divmod(i, cols_n)
        big = img.resize((img.width * S, img.height * S), Image.NEAREST)
        psheet.paste(big, (c * pw + (pw - big.width) // 2, r * ph + 12), big)
        pdr.text((c * pw + 4, r * ph + 1), label, fill=(255, 255, 160, 255))
    psheet.save("/tmp/rig_poses.png")
    print("QA sheets: /tmp/rig_exploded.png /tmp/rig_poses.png")


if __name__ == "__main__":
    main()
