#!/usr/bin/env python3
"""Empire Age 16b — skill icons (skill 1) for the 8 new western
heroes: knight, berserker, archer, mage, paladin, dragoon,
assassin, ranger.

Same house style as the approved sets (see build_skill_icons2.py,
whose draw_frame + pixelise are imported and reused verbatim):
512x512 PNG, motif painted on a dark navy ground, the unified
gold frame drawn over the outer ~26 px, then the whole icon
pixelised to a 128 grid and quantised to 48 colours with
Floyd-Steinberg dithering.

There are no source paintings for these heroes, so each motif is
PAINTED programmatically with PIL: bold, simple silhouettes with
2-3 tone shading, drawn large at 512 before pixelisation so they
stay readable at HUD size.

Run from the godot/ directory:  python3 tools/build_skill_icons16b.py
Output: assets/skill_icons/<hero>_1.png
"""
import math
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_skill_icons2 import draw_frame, pixelise  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "skill_icons")
SIZE = 512
CX = CY = 256

NAVY = (15, 19, 44)
NAVY_L = (32, 40, 82)


def lerp(a, b, t):
    return tuple(int(a[k] + (b[k] - a[k]) * t) for k in range(3))


def canvas(glow):
    """Dark navy ground with a soft radial glow behind the motif."""
    im = Image.new("RGB", (SIZE, SIZE), NAVY)
    dr = ImageDraw.Draw(im)
    steps = 12
    for i in range(steps, 0, -1):
        r = int(238 * i / steps)
        col = lerp(glow, NAVY_L, i / steps)
        dr.ellipse([CX - r, CY - r, CX + r, CY + r], fill=col)
    return im, dr


def thick_line(dr, p0, p1, width, fill):
    dr.line([p0, p1], fill=fill, width=width)
    r = width // 2
    for p in (p0, p1):
        dr.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


def star_points(cx, cy, r_out, r_in, n, rot=-math.pi / 2):
    pts = []
    for i in range(2 * n):
        r = r_out if i % 2 == 0 else r_in
        a = rot + i * math.pi / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def glow_disc(dr, cx, cy, r, col_dark, col_mid):
    for i in range(6, 0, -1):
        rr = int(r * i / 6)
        dr.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                   fill=lerp(col_mid, col_dark, i / 6))


# ---------------------------------------------------------------- knight
def paint_knight():
    """Khien Su Tu: heater shield, gold lion face on deep blue."""
    im, dr = canvas((24, 44, 96))
    shield = [(150, 102), (362, 102), (362, 252), (256, 418), (150, 252)]
    dr.polygon(shield, fill=(198, 152, 52))
    dr.polygon([(162, 114), (350, 114), (350, 248), (256, 398),
                (162, 248)], fill=(146, 104, 30))
    inner = [(176, 126), (336, 126), (336, 242), (256, 378), (176, 242)]
    dr.polygon(inner, fill=(26, 52, 138))
    dr.polygon([(256, 126), (336, 126), (336, 242), (256, 378)],
               fill=(18, 38, 102))  # right-half shade
    dr.ellipse([238, 104, 274, 140], fill=(245, 208, 110),
               outline=(120, 82, 22), width=4)  # top boss
    # Lion mane: two spiky stars, then the face.
    dr.polygon(star_points(256, 238, 94, 70, 12), fill=(168, 96, 22))
    dr.polygon(star_points(256, 238, 80, 60, 12, -math.pi / 2 + 0.26),
               fill=(216, 138, 36))
    dr.ellipse([202, 158, 232, 196], fill=(216, 138, 36))  # ears
    dr.ellipse([280, 158, 310, 196], fill=(216, 138, 36))
    dr.ellipse([192, 168, 320, 306], fill=(242, 192, 84))  # face
    dr.ellipse([214, 256, 298, 304], fill=(250, 218, 138))  # muzzle
    dr.polygon([(256, 258), (240, 276), (272, 276)], fill=(120, 52, 30))
    dr.line([(256, 276), (256, 290)], fill=(120, 52, 30), width=5)
    dr.line([(256, 290), (238, 296)], fill=(120, 52, 30), width=4)
    dr.line([(256, 290), (274, 296)], fill=(120, 52, 30), width=4)
    for ex in (222, 266):  # eyes + fierce brows
        dr.ellipse([ex, 226, ex + 24, 240], fill=(46, 24, 8))
    dr.line([(216, 216), (250, 224)], fill=(120, 62, 14), width=7)
    dr.line([(296, 216), (262, 224)], fill=(120, 62, 14), width=7)
    return im


# ------------------------------------------------------------ berserker
def paint_berserker():
    """Riu Xoay Cuong No: diagonal great axe + spin arcs, red/orange."""
    im, dr = canvas((70, 26, 22))
    cx, cy = 322, 148
    for r, a0, a1, col, w in ((128, 150, 330, (214, 62, 34), 13),
                              (152, 190, 380, (240, 116, 40), 10),
                              (108, 120, 290, (250, 168, 66), 9)):
        dr.arc([cx - r, cy - r, cx + r, cy + r], a0, a1, fill=col, width=w)
    thick_line(dr, (128, 392), (322, 168), 27, (110, 64, 30))  # haft
    thick_line(dr, (128, 392), (322, 168), 10, (158, 102, 52))
    dr.ellipse([108, 372, 148, 412], fill=(198, 152, 52))  # pommel
    # Crescent blade: outer arc minus inner arc, as a polygon.
    pts = []
    for i in range(13):
        a = math.radians(-96 + i * 16)
        pts.append((cx + 108 * math.cos(a), cy + 108 * math.sin(a)))
    for i in range(12, -1, -1):
        a = math.radians(-96 + i * 16)
        pts.append((cx + 34 + 58 * math.cos(a), cy + 58 * math.sin(a)))
    dr.polygon(pts, fill=(196, 204, 216))
    pts_hi = [p for p in pts[:13]]
    dr.line(pts_hi, fill=(248, 250, 255), width=9)  # bright edge
    dr.polygon([(cx - 20, cy - 26), (cx + 44, cy), (cx - 20, cy + 26)],
               fill=(150, 158, 172))  # socket shade
    dr.rectangle([cx - 34, cy - 18, cx + 6, cy + 18], fill=(198, 152, 52))
    dr.ellipse([cx - 30, cy - 10, cx - 6, cy + 10], fill=(214, 62, 34))
    return im


# ---------------------------------------------------------------- archer
def paint_archer():
    """Mua Ten: three arrows raining diagonally, green/gold."""
    im, dr = canvas((22, 54, 40))
    dx, dy = 0.52, -0.86  # shaft direction, tail up-right of the tip
    px, py = -dy, dx      # perpendicular

    def arrow(tx, ty, ln, shaft_col):
        ex, ey = tx + dx * ln, ty + dy * ln
        for off, col, w in ((-26, (168, 226, 190), 5), (26, (168, 226, 190), 5)):
            dr.line([(tx + px * off + dx * 30, ty + py * off + dy * 30),
                     (ex + px * off + dx * 66, ey + py * off + dy * 66)],
                    fill=col, width=w)  # motion streaks
        thick_line(dr, (tx, ty), (ex, ey), 11, shaft_col)
        head = [(tx, ty),
                (tx + dx * 34 + px * 17, ty + dy * 34 + py * 17),
                (tx + dx * 22, ty + dy * 22),
                (tx + dx * 34 - px * 17, ty + dy * 34 - py * 17)]
        dr.polygon(head, fill=(232, 238, 244))
        dr.polygon([(tx, ty), (tx + dx * 34 + px * 17, ty + dy * 34 + py * 17),
                    (tx + dx * 22, ty + dy * 22)], fill=(168, 182, 198))
        for sgn in (1, -1):  # fletching
            dr.polygon([(ex, ey),
                        (ex - dx * 36 + px * 26 * sgn, ey - dy * 36 + py * 26 * sgn),
                        (ex - dx * 44, ey - dy * 44)],
                       fill=(62, 178, 92) if sgn > 0 else (232, 186, 66))

    arrow(120, 356, 196, (196, 148, 62))
    arrow(226, 386, 210, (214, 164, 72))
    arrow(330, 356, 196, (196, 148, 62))
    return im


# ------------------------------------------------------------------ mage
def paint_mage():
    """Thien Thach Ma Thuat: violet meteor with trail and sparks."""
    im, dr = canvas((44, 24, 78))
    # Trail: three nested tapered bands from the rock to the
    # top-right corner, widest/darkest first.
    rcx, rcy = 205, 315
    dxu, dyu = 0.707, -0.707   # trail direction (up-right)
    pux, puy = 0.707, 0.707    # perpendicular
    tip = (rcx + dxu * 252, rcy + dyu * 252)
    for half_w, tip_w, col in ((62, 10, (96, 46, 172)),
                               (46, 7, (142, 80, 224)),
                               (29, 4, (186, 116, 255))):
        bx, by = rcx + dxu * 30, rcy + dyu * 30
        dr.polygon([(bx + pux * half_w, by + puy * half_w),
                    (tip[0] + pux * tip_w, tip[1] + puy * tip_w),
                    (tip[0] - pux * tip_w, tip[1] - puy * tip_w),
                    (bx - pux * half_w, by - puy * half_w)], fill=col)
    glow_disc(dr, rcx, rcy, 128, (44, 24, 78), (122, 70, 210))
    rock = []
    for i in range(10):
        a = i * math.tau / 10 + 0.2
        r = 96 if i % 2 == 0 else 80
        rock.append((rcx + r * math.cos(a), rcy + r * math.sin(a)))
    dr.polygon(rock, fill=(104, 84, 130))
    dr.polygon([(rcx, rcy - 88), (rcx + 82, rcy - 40), (rcx + 78, rcy + 46),
                (rcx, rcy + 86)], fill=(78, 62, 104))  # shaded facet
    for (x, y, r) in ((rcx - 28, rcy - 28, 19), (rcx + 34, rcy + 24, 14),
                      (rcx - 4, rcy + 38, 10)):
        dr.ellipse([x - r, y - r, x + r, y + r], fill=(58, 44, 82),
                   outline=(186, 128, 255), width=5)  # craters
    for p0, p1 in (((rcx, rcy), (rcx - 30, rcy - 42)),
                   ((rcx, rcy), (rcx + 46, rcy - 14)),
                   ((rcx, rcy), (rcx - 8, rcy + 46))):
        thick_line(dr, p0, p1, 9, (196, 128, 255))  # glowing cracks
        thick_line(dr, p0, p1, 3, (246, 236, 255))
    dr.ellipse([rcx - 12, rcy - 12, rcx + 12, rcy + 12],
               fill=(214, 156, 255))
    rng_pts = [(120, 150), (168, 108), (420, 218), (398, 330), (128, 396),
               (330, 128), (96, 262)]
    for i, (x, y) in enumerate(rng_pts):
        col = (255, 182, 84) if i % 2 == 0 else (206, 138, 255)
        dr.polygon(star_points(x, y, 15, 5, 4), fill=col)  # sparks
    return im


# --------------------------------------------------------------- paladin
def paint_paladin():
    """Thanh Quang Hoi Phuc: radiant golden cross + halo ring."""
    im, dr = canvas((64, 54, 26))
    cx, cy = 256, 252
    for i in range(12):  # light rays
        a = i * math.tau / 12
        ln = 178 if i % 2 == 0 else 138
        wdt = 0.10
        dr.polygon([(cx + 30 * math.cos(a - wdt), cy + 30 * math.sin(a - wdt)),
                    (cx + ln * math.cos(a), cy + ln * math.sin(a)),
                    (cx + 30 * math.cos(a + wdt), cy + 30 * math.sin(a + wdt))],
                   fill=(250, 216, 130) if i % 2 == 0 else (226, 182, 92))
    dr.ellipse([cx - 152, cy - 152, cx + 152, cy + 152],
               outline=(252, 228, 156), width=11)  # halo ring
    dr.ellipse([cx - 132, cy - 132, cx + 132, cy + 132],
               outline=(214, 164, 74), width=4)
    cross_big = [(226, 104), (286, 104), (286, 196), (372, 196), (372, 258),
                 (286, 258), (286, 402), (226, 402), (226, 258), (140, 258),
                 (140, 196), (226, 196)]
    dr.polygon([(x + (6 if x > cx else -6 if x < cx else 0),
                 y + (6 if y > cy else -6 if y < cy else 0))
                for x, y in cross_big], fill=(150, 106, 32))
    dr.polygon(cross_big, fill=(238, 190, 74))
    cross_in = [(240, 120), (272, 120), (272, 210), (356, 210), (356, 244),
                (272, 244), (272, 386), (240, 386), (240, 244), (156, 244),
                (156, 210), (240, 210)]
    dr.polygon(cross_in, fill=(255, 244, 196))
    dr.ellipse([cx - 21, 206, cx + 21, 248], fill=(255, 255, 246),
               outline=(214, 164, 74), width=4)
    return im


# --------------------------------------------------------------- dragoon
def paint_dragoon():
    """Long Thuong Xuyen Tam: long lance, dragon-head spearhead."""
    im, dr = canvas((22, 44, 84))
    thick_line(dr, (100, 92), (368, 360), 17, (150, 104, 44))  # shaft
    thick_line(dr, (100, 92), (368, 360), 6, (206, 158, 84))
    dr.polygon([(100, 92), (58, 118), (76, 66)], fill=(52, 110, 220))
    dr.polygon([(100, 92), (128, 48), (140, 96)], fill=(36, 84, 180))
    # Gold fins at the head base.
    dr.polygon([(352, 322), (316, 268), (382, 292)], fill=(232, 186, 66))
    dr.polygon([(322, 352), (268, 316), (292, 382)], fill=(198, 152, 52))
    # Spearhead blade, tip down-forward (bottom-right).
    tip = (438, 438)
    base = (362, 362)
    px_, py_ = -0.707, 0.707
    dr.polygon([tip,
                (base[0] + px_ * 34, base[1] + py_ * 34),
                (base[0] - px_ * 34, base[1] - py_ * 34)],
               fill=(186, 208, 234))
    dr.polygon([tip, (base[0] + px_ * 34, base[1] + py_ * 34), base],
               fill=(128, 158, 200))
    thick_line(dr, base, tip, 4, (240, 248, 255))
    # Dragon head gripping the shaft just behind the blade.
    dr.polygon([(318, 300), (356, 282), (348, 312), (372, 322),
                (342, 336), (348, 356), (322, 344), (306, 326)],
               fill=(42, 96, 196))  # head silhouette
    dr.polygon([(322, 302), (306, 262), (338, 284)], fill=(232, 186, 66))
    dr.polygon([(344, 344), (330, 372), (316, 340)], fill=(232, 186, 66))
    dr.ellipse([330, 306, 344, 320], fill=(255, 84, 60))  # eye
    dr.ellipse([352, 322, 362, 332], fill=(240, 248, 255))  # fang glint
    return im


# -------------------------------------------------------------- assassin
def _curved_blade(dr, base, tip, bend, w0, fill, edge):
    """A curved dagger blade as a tapered bezier polygon."""
    def bez(t, off):
        x = (1 - t) ** 2 * base[0] + 2 * (1 - t) * t * bend[0] \
            + t ** 2 * tip[0]
        y = (1 - t) ** 2 * base[1] + 2 * (1 - t) * t * bend[1] \
            + t ** 2 * tip[1]
        # tangent -> normal
        tx = 2 * (1 - t) * (bend[0] - base[0]) + 2 * t * (tip[0] - bend[0])
        ty = 2 * (1 - t) * (bend[1] - base[1]) + 2 * t * (tip[1] - bend[1])
        tl = max(math.hypot(tx, ty), 1e-6)
        wdt = w0 * (1 - t * 0.92) * off
        return (x - ty / tl * wdt, y + tx / tl * wdt)
    left = [bez(t / 10.0, 1) for t in range(11)]
    right = [bez(t / 10.0, -1) for t in range(10, -1, -1)]
    dr.polygon(left + right, fill=fill)
    dr.line([bez(t / 10.0, 1) for t in range(11)], fill=edge, width=5)


def paint_assassin():
    """Am Sat: crossed curved daggers over a hooded shadow."""
    im, dr = canvas((30, 24, 52))
    dr.ellipse([132, 82, 380, 330], fill=(30, 26, 50))  # hood
    dr.polygon([(116, 424), (396, 424), (336, 292), (176, 292)],
               fill=(30, 26, 50))  # shoulders
    # Red sash across the shoulders (also gives the red accents
    # enough painted area to survive the 48-colour quantise).
    dr.polygon([(146, 424), (366, 424), (348, 390), (164, 390)],
               fill=(204, 34, 38))
    dr.polygon([(256, 390), (348, 390), (366, 424), (256, 424)],
               fill=(168, 26, 32))
    dr.ellipse([132, 82, 380, 330], outline=(86, 72, 130), width=6)
    dr.ellipse([184, 158, 328, 306], fill=(6, 5, 10))  # face shadow
    dr.polygon([(200, 222), (244, 212), (246, 232), (202, 238)],
               fill=(255, 40, 40))  # eyes
    dr.polygon([(312, 222), (268, 212), (266, 232), (310, 238)],
               fill=(255, 40, 40))
    # Crossed daggers in front.
    _curved_blade(dr, (238, 344), (368, 168), (330, 280), 17,
                  (198, 206, 220), (246, 250, 255))
    _curved_blade(dr, (274, 344), (144, 168), (182, 280), 17,
                  (168, 178, 196), (232, 238, 246))
    thick_line(dr, (238, 344), (188, 402), 19, (36, 28, 34))
    thick_line(dr, (274, 344), (324, 402), 19, (36, 28, 34))
    for p0, p1 in (((202, 382), (224, 360)), ((310, 360), (288, 382))):
        thick_line(dr, p0, p1, 9, (232, 36, 36))  # red wraps
    dr.ellipse([172, 388, 202, 418], fill=(198, 152, 52))
    dr.ellipse([310, 388, 340, 418], fill=(198, 152, 52))
    dr.ellipse([243, 325, 269, 351], fill=(232, 36, 36))  # centre gem
    return im


# ---------------------------------------------------------------- ranger
def paint_ranger():
    """Kiem Vu Lu Hanh: slim sword ringed by swirling slash arcs."""
    im, dr = canvas((18, 56, 58))
    cx, cy = 268, 218
    for r, a0, a1, col, w in ((150, 300, 430, (52, 214, 190), 13),
                              (124, 120, 265, (140, 240, 224), 10),
                              (172, 160, 235, (52, 178, 168), 9),
                              (104, 315, 425, (250, 252, 255), 13)):
        dr.arc([cx - r, cy - r, cx + r, cy + r], a0, a1, fill=col, width=w)
    # Slim diagonal blade, tip up-right.
    tip = (388, 86)
    base = (252, 268)
    px_, py_ = 0.577, 0.577
    dr.polygon([tip, (base[0] + px_ * 29, base[1] + py_ * 29),
                (base[0] - px_ * 29, base[1] - py_ * 29)],
               fill=(250, 252, 255))
    dr.polygon([tip, (base[0] + px_ * 29, base[1] + py_ * 29), base],
               fill=(168, 196, 214))
    thick_line(dr, base, (372, 102), 5, (255, 255, 255))
    thick_line(dr, (218, 252), (282, 316), 13, (232, 186, 66))  # guard
    thick_line(dr, (252, 282), (206, 344), 17, (24, 110, 108))  # grip
    thick_line(dr, (238, 296), (222, 318), 5, (140, 240, 224))
    dr.ellipse([188, 330, 218, 360], fill=(198, 152, 52))  # pommel
    for (x, y) in ((150, 130), (404, 300), (140, 330)):
        dr.polygon(star_points(x, y, 14, 5, 4), fill=(240, 252, 250))
    return im


PAINTERS = {
    "knight": paint_knight,
    "berserker": paint_berserker,
    "archer": paint_archer,
    "mage": paint_mage,
    "paladin": paint_paladin,
    "dragoon": paint_dragoon,
    "assassin": paint_assassin,
    "ranger": paint_ranger,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for i, (hero, paint) in enumerate(PAINTERS.items()):
        art = paint()
        draw_frame(art, seed=1600 + i * 10 + 1)
        out = pixelise(art)
        path = os.path.join(OUT, f"{hero}_1.png")
        out.save(path)
        cols = len(out.getcolors(SIZE * SIZE) or [])
        print(f"{hero}_1: {cols} colours -> {path}")


if __name__ == "__main__":
    main()
