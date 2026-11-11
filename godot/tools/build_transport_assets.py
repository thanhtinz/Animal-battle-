#!/usr/bin/env python3
"""Empire Age 15g — land-transport sprite sheets (trade Cart +
troop Wagon), drawn in the game's family with PIL primitives:
warm woods, an iron-banded wheel pair, and a RED cloth canopy /
cover (the red hue band is what tools/recolor_teams.py rotates
into every other slot's colour — skin, hair, wood and metal stay
pixel-identical across slots, the standing rule).

Sheet layout follows the roster convention: rows are animations
(idle / walk / die / hurt), frames are grouped by direction
[down, left, right, up] with `per_dir` frames each. Vehicles get
real front / side / rear views (the Ram's single-view repeat is
the fallback this roster no longer needs).

Run: python3 tools/build_transport_assets.py
Writes assets/{cart,wagon}.png + *_frames.json, recolours them
into the 7 other slot sets, and prints the measured content
sizes that Unit.CONTENT_SIZE must carry.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
SS = 3  # supersample

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from recolor_teams import SLOTS, recolor  # noqa: E402

# palette (final-px space)
WOOD = (138, 90, 43, 255)
WOOD_D = (110, 68, 30, 255)
WOOD_L = (168, 118, 62, 255)
IRON = (88, 88, 96, 255)
IRON_D = (58, 58, 64, 255)
HORSE = (122, 74, 33, 255)
HORSE_D = (74, 44, 18, 255)
HORSE_L = (150, 100, 52, 255)
RED = (200, 55, 45, 255)      # faction cloth — the recolor band
RED_D = (158, 38, 32, 255)
RED_L = (226, 92, 74, 255)
SACK = (196, 164, 110, 255)
SACK_D = (164, 132, 82, 255)
SKIN = (232, 184, 138, 255)
SHIRT = (84, 96, 130, 255)    # driver clothes (not faction red)
PANTS = (70, 58, 44, 255)


def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


class P:
    """Primitive painter in final-px coordinates."""

    def __init__(self, img):
        self.d = ImageDraw.Draw(img)

    def rect(self, x, y, x2, y2, fill):
        self.d.rectangle([x * SS, y * SS, x2 * SS, y2 * SS], fill=fill)

    def rrect(self, x, y, x2, y2, r, fill):
        self.d.rounded_rectangle([x * SS, y * SS, x2 * SS, y2 * SS],
                                 radius=r * SS, fill=fill)

    def ell(self, x, y, x2, y2, fill):
        self.d.ellipse([x * SS, y * SS, x2 * SS, y2 * SS], fill=fill)

    def poly(self, pts, fill):
        self.d.polygon([(x * SS, y * SS) for x, y in pts], fill=fill)

    def line(self, pts, fill, w=2):
        self.d.line([(x * SS, y * SS) for x, y in pts], fill=fill,
                    width=max(1, int(w * SS)), joint="curve")

    def arc(self, x, y, x2, y2, a0, a1, fill, w=2):
        self.d.arc([x * SS, y * SS, x2 * SS, y2 * SS], a0, a1,
                   fill=fill, width=max(1, int(w * SS)))


def wheel(p, cx, cy, r, rot=0.0):
    p.ell(cx - r, cy - r, cx + r, cy + r, IRON_D)
    p.ell(cx - r + 2, cy - r + 2, cx + r - 2, cy + r - 2, WOOD_D)
    import math
    for i in range(4):
        a = rot + i * math.pi / 4.0
        dx, dy = math.cos(a) * (r - 3), math.sin(a) * (r - 3)
        p.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], WOOD_L, 2)
    p.ell(cx - 3, cy - 3, cx + 3, cy + 3, IRON)


def horse_side(p, x, y, s=1.0, flip=False):
    """A horse facing +x, feet at y (final px, scaled by s)."""
    def X(v):
        return x - v * s if flip else x + v * s
    # legs
    for lx, wob in [(6, 0), (14, 0), (40, 0), (48, 0)]:
        p.rect(min(X(lx), X(lx + 5)), y - 26 * s, max(X(lx), X(lx + 5)),
               y, HORSE_D)
        p.rect(min(X(lx), X(lx + 5)), y - 4 * s, max(X(lx), X(lx + 5)),
               y, IRON_D)
    # body
    p.ell(min(X(0), X(56)), y - 44 * s, max(X(0), X(56)), y - 20 * s, HORSE)
    p.ell(min(X(2), X(54)), y - 42 * s, max(X(2), X(54)), y - 30 * s, HORSE_L)
    # neck + head
    p.poly([(X(46), y - 40 * s), (X(64), y - 52 * s), (X(68), y - 44 * s),
            (X(54), y - 30 * s)], HORSE)
    p.poly([(X(62), y - 54 * s), (X(76), y - 48 * s), (X(74), y - 40 * s),
            (X(62), y - 40 * s)], HORSE)
    p.ell(X(71) - (2 if flip else 0), y - 49 * s, X(71) + (2 if flip else 0) + 2,
          y - 45 * s, HORSE_D)  # eye
    # mane + tail
    p.poly([(X(44), y - 44 * s), (X(58), y - 54 * s), (X(52), y - 34 * s)],
           HORSE_D)
    p.poly([(X(0), y - 42 * s), (X(-8), y - 26 * s), (X(2), y - 20 * s)],
           HORSE_D)
    # saddle blanket in faction red
    p.rrect(min(X(20), X(38)), y - 45 * s, max(X(20), X(38)), y - 32 * s,
            2, RED)


def driver(p, x, y, flip=False):
    """A seated driver silhouette: head, torso, legs to the bench."""
    p.ell(x - 5, y - 26, x + 5, y - 16, SKIN)          # head
    p.poly([(x - 6, y - 27), (x + 6, y - 27), (x + 3, y - 31),
            (x - 3, y - 31)], HORSE_D)                  # hat
    p.rrect(x - 6, y - 16, x + 6, y - 2, 2, SHIRT)     # torso
    p.line([(x + (4 if not flip else -4), y - 10), (x + (13 if not flip else -13), y - 4)], SKIN, 3)  # arm to reins
    p.line([(x - 2, y - 2), (x + 8, y + 4)], PANTS, 4)  # leg


def cart_side(flip=False, walk=0, dead=False):
    img = canvas(200, 120)
    p = P(img)
    bob = -2 if walk == 1 else 0
    # horse at left, facing right (drawn facing +x; flipped by mirror)
    horse_side(p, 30, 106 + bob, 1.0, flip=False)
    # shafts from horse to cart
    p.line([(78, 74 + bob), (102, 78)], WOOD_D, 3)
    p.line([(78, 84 + bob), (102, 84)], WOOD_D, 3)
    # cart bed
    p.rrect(96, 66 + bob, 178, 84 + bob, 2, WOOD)
    p.rect(96, 80 + bob, 178, 84 + bob, WOOD_D)
    # sacks under the canopy lip
    p.ell(104, 56 + bob, 128, 70 + bob, SACK)
    p.ell(140, 54 + bob, 166, 70 + bob, SACK_D)
    # red canopy (rounded hood)
    p.rrect(98, 30 + bob, 176, 62 + bob, 10, RED)
    p.rrect(98, 30 + bob, 176, 44 + bob, 10, RED_L)
    p.rect(98, 58 + bob, 176, 62 + bob, RED_D)
    # wheels
    wheel(p, 158, 92 + bob, 15, 0.4 if walk == 1 else 0.0)
    wheel(p, 110, 94 + bob, 12, 0.4 if walk == 1 else 0.0)
    if flip:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    return img


def cart_front():
    img = canvas(200, 120)
    p = P(img)
    cx = 100
    # horse head-on (head + ears + chest between the shafts)
    p.ell(cx - 13, 30, cx + 13, 62, HORSE)
    p.poly([(cx - 12, 34), (cx - 18, 16), (cx - 5, 26)], HORSE_D)
    p.poly([(cx + 12, 34), (cx + 18, 16), (cx + 5, 26)], HORSE_D)
    p.ell(cx - 8, 44, cx - 3, 49, HORSE_D)
    p.ell(cx + 3, 44, cx + 8, 49, HORSE_D)
    p.ell(cx - 16, 58, cx + 16, 96, HORSE)
    p.rect(cx - 16, 88, cx - 10, 106, HORSE_D)
    p.rect(cx + 10, 88, cx + 16, 106, HORSE_D)
    # cart behind: canopy front + bed front
    p.rrect(cx - 34, 22, cx + 34, 58, 9, RED)
    p.rrect(cx - 34, 22, cx + 34, 34, 9, RED_L)
    p.rrect(cx - 36, 58, cx + 36, 82, 2, WOOD)
    wheel(p, cx - 33, 92, 13)
    wheel(p, cx + 33, 92, 13)
    return img


def cart_rear():
    img = canvas(200, 120)
    p = P(img)
    cx = 100
    # horse from behind (rump + tail), cart back in front of viewer
    p.rrect(cx - 36, 26, cx + 36, 60, 9, RED_D)  # canopy back
    p.rrect(cx - 38, 58, cx + 38, 84, 2, WOOD_D)  # bed back
    p.rect(cx - 38, 62, cx + 38, 66, WOOD_L)
    p.ell(cx - 12, 66, cx + 12, 96, HORSE)        # rump beyond the bed
    p.line([(cx, 70), (cx, 98)], HORSE_D, 4)     # tail
    p.rect(cx - 15, 90, cx - 9, 106, HORSE_D)
    p.rect(cx + 9, 90, cx + 15, 106, HORSE_D)
    wheel(p, cx - 34, 92, 13)
    wheel(p, cx + 34, 92, 13)
    return img


def wagon_side(flip=False, walk=0, dead=False):
    img = canvas(240, 140)
    p = P(img)
    bob = -2 if walk == 1 else 0
    horse_side(p, 26, 124 + bob, 1.05, flip=False)
    p.line([(80, 88 + bob), (104, 92)], WOOD_D, 3)
    # long bed
    p.rrect(100, 84 + bob, 224, 104 + bob, 2, WOOD)
    p.rect(100, 99 + bob, 224, 104 + bob, WOOD_D)
    # big covered top in faction red
    p.rrect(108, 38 + bob, 220, 88 + bob, 12, RED)
    p.rrect(108, 38 + bob, 220, 54 + bob, 12, RED_L)
    p.rect(108, 82 + bob, 220, 88 + bob, RED_D)
    # bench + driver at the front of the bed
    p.rect(96, 78 + bob, 112, 84 + bob, WOOD_D)
    driver(p, 104, 78 + bob)
    # wheels: big rear, smaller front
    wheel(p, 196, 110 + bob, 17, 0.4 if walk == 1 else 0.0)
    wheel(p, 122, 113 + bob, 13, 0.4 if walk == 1 else 0.0)
    if flip:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    return img


def wagon_front():
    img = canvas(240, 140)
    p = P(img)
    cx = 120
    p.ell(cx - 14, 44, cx + 14, 78, HORSE)
    p.poly([(cx - 13, 48), (cx - 20, 28), (cx - 5, 38)], HORSE_D)
    p.poly([(cx + 13, 48), (cx + 20, 28), (cx + 5, 38)], HORSE_D)
    p.ell(cx - 9, 59, cx - 3, 65, HORSE_D)
    p.ell(cx + 3, 59, cx + 9, 65, HORSE_D)
    p.ell(cx - 18, 74, cx + 18, 112, HORSE)
    p.rect(cx - 18, 104, cx - 11, 124, HORSE_D)
    p.rect(cx + 11, 104, cx + 18, 124, HORSE_D)
    # cover front, higher and wider than the cart's
    p.rrect(cx - 44, 30, cx + 44, 76, 11, RED)
    p.rrect(cx - 44, 30, cx + 44, 46, 11, RED_L)
    p.rrect(cx - 46, 76, cx + 46, 102, 2, WOOD)
    driver(p, cx - 34, 74)
    wheel(p, cx - 42, 110, 15)
    wheel(p, cx + 42, 110, 15)
    return img


def wagon_rear():
    img = canvas(240, 140)
    p = P(img)
    cx = 120
    p.rrect(cx - 46, 34, cx + 46, 78, 11, RED_D)   # cover back
    p.rrect(cx - 48, 78, cx + 48, 104, 2, WOOD_D)  # bed back
    p.rect(cx - 48, 82, cx + 48, 87, WOOD_L)
    p.ell(cx - 13, 84, cx + 13, 112, HORSE)
    p.line([(cx, 88), (cx, 114)], HORSE_D, 4)
    p.rect(cx - 16, 106, cx - 10, 124, HORSE_D)
    p.rect(cx + 10, 106, cx + 16, 124, HORSE_D)
    wheel(p, cx - 43, 110, 15)
    wheel(p, cx + 43, 110, 15)
    return img


def darken(img, f=0.55):
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (int(r * f), int(g * f), int(b * f), a)
    return img


def tint_red(img, f=0.35):
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (min(255, int(r * (1 + f))), int(g * (1 - f * 0.4)),
                            int(b * (1 - f * 0.4)), a)
    return img


def build_sheet(kind, cell_w, cell_h, baseline, side_fn, front_fn, rear_fn):
    dirs = [front_fn, None, None, rear_fn]  # down, left, right, up

    def frame(direction, walk):
        if direction == 0:
            return front_fn()
        if direction == 3:
            return rear_fn()
        return side_fn(flip=(direction == 1), walk=walk)

    def paste_row(sheet, row, frames):
        for i, fr in enumerate(frames):
            fr = fr.resize((cell_w * SS, cell_h * SS), Image.LANCZOS)
            sheet.alpha_composite(fr, (i * cell_w * SS, row * cell_h * SS))

    rows = {"idle": [], "walk": [], "die": [], "hurt": []}
    for d in range(4):
        rows["idle"].append(frame(d, 0))
    for d in range(4):
        rows["walk"].append(frame(d, 0))
        rows["walk"].append(frame(d, 1))
    for d in range(4):
        f = frame(d, 0)
        rows["die"].append(darken(f.copy()))
        rows["hurt"].append(tint_red(f.copy()))
    cols = max(len(v) for v in rows.values())
    sheet = Image.new("RGBA", (cols * cell_w * SS, 4 * cell_h * SS),
                      (0, 0, 0, 0))
    for r, name in enumerate(["idle", "walk", "die", "hurt"]):
        paste_row(sheet, r, rows[name])
    sheet = sheet.resize((cols * cell_w, 4 * cell_h), Image.LANCZOS)
    out = os.path.join(ASSETS, kind + ".png")
    sheet.save(out)
    manifest = {
        "cell_w": cell_w, "cell_h": cell_h, "baseline": baseline,
        "animations": {
            "idle": {"row": 0, "count": 4, "per_dir": 1},
            "walk": {"row": 1, "count": 8, "per_dir": 2},
            "die": {"row": 2, "count": 4, "per_dir": 1},
            "hurt": {"row": 3, "count": 4, "per_dir": 1},
        },
    }
    with open(os.path.join(ASSETS, kind + "_frames.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    # measured content: front (down idle) width + full height, side length
    cell0 = sheet.crop((0, 0, cell_w, cell_h))
    side = sheet.crop((2 * cell_w, 0, 3 * cell_w, cell_h))
    fb = cell0.getbbox()
    sb = side.getbbox()
    print("%s: front bbox=%s side bbox=%s -> CONTENT [%d, %d, %d, %d]"
          % (kind, fb, sb, fb[2] - fb[0], fb[3] - fb[1],
             fb[3] - fb[1], sb[2] - sb[0]))
    return out, manifest


def main():
    jobs = [
        ("cart", 200, 120, 110, cart_side, cart_front, cart_rear),
        ("wagon", 240, 140, 130, wagon_side, wagon_front, wagon_rear),
    ]
    for kind, cw, ch, base, sfn, ffn, rfn in jobs:
        src, _ = build_sheet(kind, cw, ch, base, sfn, ffn, rfn)
        img = Image.open(src)
        for slot, (dirname, hue, sat_base, val_mult) in sorted(SLOTS.items()):
            out_dir = os.path.join(ASSETS, dirname)
            os.makedirs(out_dir, exist_ok=True)
            recolor(img.copy(), hue, sat_base, val_mult).save(
                os.path.join(out_dir, kind + ".png"))
            with open(os.path.join(ASSETS, kind + "_frames.json")) as fh:
                data = fh.read()
            with open(os.path.join(out_dir, kind + "_frames.json"), "w") as fh:
                fh.write(data)
            print("slot %d: %s/%s.png" % (slot, dirname, kind))
    print("done")


if __name__ == "__main__":
    main()
