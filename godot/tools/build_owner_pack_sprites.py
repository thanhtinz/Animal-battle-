#!/usr/bin/env python3
"""Empire Age 16b-A: build hero sprites from the owner-supplied packs.

For each of the 8 medieval heroes, takes the Idle rotation PNGs from the
owner pack zip (48x48 RGBA, 8 directions), converts them to the game
format used by res://assets/king_<id>_<dir8>.png:

  * binarise alpha at 0.5 (output alpha is only 0 / 255)
  * RGB of fully-transparent pixels set to 0
  * trim the fully-transparent border
  * scale with NEAREST so the sprite HEIGHT is exactly 92 px
    (width proportional, rounded)

WEAPON ERASURE (standing owner rule): in the three BACK rotations
(ne, n, nw) the hero must hold NO hand weapon. The erase masks below are
defined per hero / per direction in source 48x48 coordinates and were
derived by visually inspecting every back pose at 10x zoom. Shields
(knight / paladin) are body equipment and are deliberately NOT masked.
Poses where the weapon is already fully hidden behind the body carry an
empty mask (verified by inspection):

  * knight   nw - sword fully behind cape; only the shield shows (kept)
  * ranger   nw - sword fully behind the coat; only the fist shows
  * dragoon  nw - lance fully behind cape/hair; the gold/blue object on
                  the left is the forearm armour (body), not the lance

Run from the godot/ directory:  python3 tools/build_owner_pack_sprites.py
Repeatable: outputs are fully regenerated from the zips on every run.
The existing .png.import sidecars are left untouched.
"""

import io
import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw

GODOT_DIR = Path(__file__).resolve().parent.parent
PACKS_DIR = GODOT_DIR.parent / "art_candidates" / "owner_packs"
ASSETS_DIR = GODOT_DIR / "assets"

TARGET_H = 92

HEROES = ["knight", "berserker", "archer", "mage",
          "dragoon", "assassin", "ranger", "paladin"]

# paladin must use the fixed pack; everyone else uses <id>_pack.zip
PACK_FILE = {h: f"{h}_pack.zip" for h in HEROES}
PACK_FILE["paladin"] = "paladin_pack_fixed.zip"

# owner-pack rotation name -> game dir8 suffix
DIR_MAP = {
    "south": "s", "south-east": "se", "east": "e", "north-east": "ne",
    "north": "n", "north-west": "nw", "west": "w", "south-west": "sw",
}
BACK_DIRS = {"ne", "n", "nw"}

# ---------------------------------------------------------------------------
# Erase masks, in SOURCE 48x48 coordinates.
# Shape forms:
#   ("rect", x0, y0, x1, y1)   inclusive rectangle
#   ("poly", [(x, y), ...])    filled polygon
# Only the weapon is covered; hands/fists that gripped it are kept where
# they do not overlap the weapon itself.
# ---------------------------------------------------------------------------
ERASE_MASKS = {
    # --- knight: sword in the right hand, shield on the left (kept) ---
    ("knight", "ne"): [  # diagonal blade + gold crossguard, bottom-right
        ("poly", [(31, 29), (48, 37), (48, 43), (37, 43), (30, 36)]),
        ("rect", 34, 29, 38, 33),   # crossguard remnant beside the gauntlet
        ("rect", 43, 41, 47, 45),   # blade tip below the polygon
    ],
    ("knight", "n"): [  # short diagonal blade tip, right of the cape
        ("poly", [(32, 28), (48, 39), (48, 44), (39, 44), (32, 35)]),
        ("rect", 35, 29, 40, 33),   # crossguard remnant
    ],
    ("knight", "nw"): [],  # no weapon visible (shield kept)

    # --- berserker: double axe ---
    ("berserker", "ne"): [  # axe head right of the fist + handle stub
        ("rect", 36, 21, 47, 40),
        ("rect", 34, 30, 36, 33),
    ],
    ("berserker", "n"): [  # blade edge hanging in the left hand
        ("rect", 4, 20, 9, 37),
    ],
    ("berserker", "nw"): [  # axe head bottom-right
        ("rect", 36, 31, 45, 38),
    ],

    # --- archer: bow held low in both hands ---
    ("archer", "ne"): [
        # right limb + nocked arrow shaft (white horizontal)
        ("rect", 29, 25, 43, 32),
        # silver left limb sweeping down in front of the left boot
        ("poly", [(20, 31), (23, 34), (13, 44), (6, 44), (6, 39),
                  (14, 34), (17, 31)]),
        # arrow shaft printed on the skirt front (white WW at y35-36)
        ("rect", 21, 35, 24, 36),
        # bow section protruding right of the skirt silhouette
        ("rect", 29, 33, 38, 39),
        # silver arrow tip between the legs (x19-20, y37-38)
        ("rect", 19, 37, 20, 38),
    ],
    ("archer", "n"): [
        ("rect", 2, 22, 12, 38),    # left limb
        ("rect", 35, 23, 45, 37),   # right limb
        ("rect", 9, 39, 14, 46),    # arrow tip hanging below left hand
    ],
    ("archer", "nw"): [
        ("rect", 4, 23, 13, 40),    # bow limb on the left
        ("rect", 13, 27, 20, 31),   # bowstring
        ("rect", 7, 33, 20, 38),    # arrow shaft sliver left of the skirt
        ("rect", 3, 32, 8, 38),     # bow limb tip at the far left
    ],

    # --- mage: staff with purple orb ---
    ("mage", "ne"): [  # orb + full shaft on the right
        ("rect", 31, 2, 43, 47),
    ],
    ("mage", "n"): [
        ("rect", 33, 2, 45, 17),    # orb
        ("rect", 36, 17, 40, 44),   # shaft right of the robe
    ],
    ("mage", "nw"): [  # only the orb peeks out behind the hood
        ("rect", 33, 2, 44, 17),
    ],

    # --- dragoon: lance carried across the back + spearhead in hand ---
    ("dragoon", "ne"): [
        # back-carried shaft + silver butt tip, top-left behind the hair
        ("poly", [(2, 6), (10, 5), (20, 13), (18, 17), (5, 13), (2, 12)]),
        # spearhead + lower shaft, bottom-right
        ("rect", 30, 29, 47, 43),
    ],
    ("dragoon", "n"): [
        # short visible shaft segment + tip, top-left of the hair
        ("poly", [(4, 9), (10, 8), (19, 15), (17, 19), (5, 14)]),
        # spearhead, bottom-right
        ("rect", 35, 27, 47, 41),
    ],
    ("dragoon", "nw"): [],  # no weapon visible

    # --- assassin: twin daggers ---
    ("assassin", "ne"): [  # right dagger, diagonal blade
        ("poly", [(28, 31), (48, 38), (48, 44), (35, 44), (27, 37)]),
    ],
    ("assassin", "n"): [  # both daggers
        ("poly", [(0, 35), (16, 32), (19, 35), (5, 43), (0, 43)]),
        ("poly", [(29, 33), (48, 37), (48, 43), (42, 43), (30, 38)]),
    ],
    ("assassin", "nw"): [  # left dagger
        ("poly", [(0, 36), (18, 31), (21, 35), (5, 44), (0, 44)]),
    ],

    # --- ranger: short sword ---
    ("ranger", "ne"): [  # diagonal white blade, bottom-right
        ("poly", [(26, 29), (45, 36), (45, 42), (33, 42), (25, 34)]),
    ],
    ("ranger", "n"): [
        ("poly", [(29, 29), (47, 36), (47, 42), (35, 42), (28, 34)]),
        ("rect", 35, 28, 41, 32),   # grip stub above the blade band
    ],
    ("ranger", "nw"): [],  # no weapon visible

    # --- paladin: upright sword in the right hand, shield kept ---
    ("paladin", "ne"): [
        ("rect", 34, 2, 40, 24),    # blade
        ("rect", 39, 23, 44, 29),   # crossguard tip right of the fist
        ("rect", 35, 29, 40, 36),   # pommel below the fist
    ],
    ("paladin", "n"): [
        ("rect", 36, 2, 43, 25),    # blade (incl. right outline column)
        ("rect", 40, 23, 47, 30),   # crossguard tip right of the fist
        ("rect", 35, 30, 41, 36),   # pommel below the fist
    ],
    ("paladin", "nw"): [  # blade sliver above the right shoulder (x33-35)
        ("rect", 33, 2, 36, 16),
    ],
}


def binarise(im: Image.Image) -> Image.Image:
    """Alpha -> 0/255 at the 0.5 threshold; transparent RGB zeroed."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a >= 128:
                px[x, y] = (r, g, b, 255)
            else:
                px[x, y] = (0, 0, 0, 0)
    return im


def apply_masks(im: Image.Image, masks) -> int:
    """Erase masked pixels (set transparent). Returns erased opaque count."""
    if not masks:
        return 0
    overlay = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(overlay)
    for shape in masks:
        if shape[0] == "rect":
            _, x0, y0, x1, y1 = shape
            d.rectangle([x0, y0, x1, y1], fill=255)
        elif shape[0] == "poly":
            d.polygon(shape[1], fill=255)
        else:
            raise ValueError(f"unknown mask shape {shape[0]!r}")
    src = im.load()
    m = overlay.load()
    erased = 0
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if m[x, y] and src[x, y][3] == 255:
                src[x, y] = (0, 0, 0, 0)
                erased += 1
    return erased


def convert(im: Image.Image) -> Image.Image:
    """Trim transparent border, then scale to height 92 with NEAREST."""
    bbox = im.getbbox()  # bbox of non-zero (alpha) region
    if bbox is None:
        raise ValueError("pose is fully transparent")
    im = im.crop(bbox)
    w, h = im.size
    new_w = max(1, round(w * TARGET_H / h))
    return im.resize((new_w, TARGET_H), Image.NEAREST)


def main() -> int:
    print(f"packs:  {PACKS_DIR}")
    print(f"assets: {ASSETS_DIR}")
    failures = []
    print()
    print(f"{'hero':<11} {'dir':<4} {'out':>9} {'opaque':>7} "
          f"{'erased':>7} {'erase%':>7}  audit")
    total_erased = {}
    for hero in HEROES:
        zpath = PACKS_DIR / PACK_FILE[hero]
        if not zpath.exists():
            failures.append(f"{hero}: pack missing: {zpath}")
            continue
        with zipfile.ZipFile(zpath) as z:
            names = set(z.namelist())
            for rot, dir8 in DIR_MAP.items():
                member = f"Idle/rotations/{rot}.png"
                if member not in names:
                    failures.append(f"{hero}/{dir8}: {member} not in pack")
                    continue
                raw = Image.open(io.BytesIO(z.read(member)))
                im = binarise(raw)
                opaque_before = sum(
                    1 for p in im.getdata() if p[3] == 255)
                erased = 0
                if dir8 in BACK_DIRS:
                    erased = apply_masks(im, ERASE_MASKS.get((hero, dir8), []))
                    pct = 100.0 * erased / opaque_before if opaque_before else 0
                    if pct > 25.0:
                        print(f"  WARNING {hero}/{dir8}: erased {pct:.1f}% "
                              f"of opaque pixels (>25%) - mask too big?",
                              file=sys.stderr)
                    total_erased[(hero, dir8)] = (erased, pct)
                out = convert(im)
                out_path = ASSETS_DIR / f"king_{hero}_{dir8}.png"
                out.save(out_path)
                # audit the written file
                chk = Image.open(out_path).convert("RGBA")
                alphas = {p[3] for p in chk.getdata()}
                semi = sum(1 for p in chk.getdata() if p[3] not in (0, 255))
                ok = chk.height == TARGET_H and semi == 0
                if not ok:
                    failures.append(
                        f"{hero}/{dir8}: audit FAIL h={chk.height} semi={semi}")
                opaque_out = sum(1 for p in chk.getdata() if p[3] == 255)
                pct_s = (f"{100.0 * erased / opaque_before:.1f}%"
                         if dir8 in BACK_DIRS else "-")
                print(f"{hero:<11} {dir8:<4} "
                      f"{f'{chk.width}x{chk.height}':>9} {opaque_out:>7} "
                      f"{erased if dir8 in BACK_DIRS else '-':>7} "
                      f"{pct_s:>7}  "
                      f"{'OK' if ok else 'FAIL'} (alphas {sorted(alphas)})")
    print()
    print("erased-pixel summary (back poses):")
    for hero in HEROES:
        row = []
        for dir8 in ("ne", "n", "nw"):
            if (hero, dir8) in total_erased:
                n, pct = total_erased[(hero, dir8)]
                row.append(f"{dir8}={n} ({pct:.1f}%)")
        print(f"  {hero:<11} " + "  ".join(row))
    if failures:
        print("\nFAILURES:", file=sys.stderr)
        for f in failures:
            print(f"  {f}", file=sys.stderr)
        return 1
    print("\nAll 64 sprites written and audited OK.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
