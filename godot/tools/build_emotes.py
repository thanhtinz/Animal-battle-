#!/usr/bin/env python3
"""Empire Age 17e — the drawn emoticon set for the chat hub.

Builds 24 transparent PNGs (128x128, drawn at 4x and
downscaled) in ONE painted family: round yellow faces with a
warm radial gradient, dark-brown line work, and per-id
expression features — plus a few glyph badges (heart, thumbs,
YES/NO) drawn in the same hand. The ids here MUST match
EmoteIDs in server/chathub.go and Emotes.IDS in
scripts/emotes.gd (the server strips unknown tokens).

Usage: python3 tools/build_emotes.py
Output: assets/emotes/<id>.png + tools/emotes_contact.png
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

SS = 4                      # supersample
S = 128 * SS                # canvas
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "emotes")
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

INK = (91, 58, 18, 255)         # dark warm brown line work
INK_SOFT = (122, 82, 26, 255)
WHITE = (255, 255, 255, 255)
BLUSH = (244, 130, 90, 110)
TEAR = (110, 190, 245, 235)
HEART = (232, 62, 92, 255)
HEART_D = (178, 34, 62, 255)

CX, CY, R = S // 2, S // 2 + 6 * SS, 46 * SS


def face_base():
    """Round yellow face: radial gradient + rim + soft top light."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    steps = 46
    for i in range(steps, 0, -1):
        t = i / steps
        r = R * t
        # centre #ffe066 -> mid #ffd23e -> rim #f2a71b
        if t > 0.55:
            k = (t - 0.55) / 0.45
            col = (int(255 - 13 * k), int(224 - 14 * k), int(102 - 64 * k), 255)
        else:
            k = t / 0.55
            col = (int(255 - 0 * k), int(210 + 14 * k), int(62 + 40 * k), 255)
        gd.ellipse([CX - r, CY - r, CX + r, CY + r], fill=col)
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([CX - R, CY - R, CX + R, CY + R], fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.ellipse([CX - R, CY - R, CX + R, CY + R], outline=(214, 132, 20, 255),
              width=3 * SS)
    # soft top-left light, composited (ImageDraw.Draw would
    # REPLACE the pixels and leave a grey smudge instead)
    light = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(light)
    ld.ellipse([CX - 31 * SS, CY - 39 * SS, CX - 5 * SS, CY - 17 * SS],
               fill=(255, 255, 255, 40))
    img.alpha_composite(light)
    return img, ImageDraw.Draw(img)


def eye_open(d, x, y, w=6.5, h=9.5):
    d.ellipse([x - w * SS, y - h * SS, x + w * SS, y + h * SS], fill=INK)
    d.ellipse([x - 2.2 * SS, y - 6 * SS, x + 1.6 * SS, y - 2.2 * SS], fill=WHITE)


def eye_dot(d, x, y, r=3.2):
    d.ellipse([x - r * SS, y - r * SS, x + r * SS, y + r * SS], fill=INK)


def eye_happy(d, x, y, flip=False):
    """Closed happy eye: an arc (∩ normally, ∪ when flip)."""
    box = [x - 8 * SS, y - 6 * SS, x + 8 * SS, y + 8 * SS]
    if flip:
        d.arc(box, start=0, end=180, fill=INK, width=3 * SS)
    else:
        d.arc(box, start=180, end=360, fill=INK, width=3 * SS)


def eye_x(d, x, y, s=6):
    for dx, dy in ((-1, -1), (1, 1), (-1, 1), (1, -1)):
        pass
    d.line([x - s * SS, y - s * SS, x + s * SS, y + s * SS], fill=INK, width=3 * SS)
    d.line([x - s * SS, y + s * SS, x + s * SS, y - s * SS], fill=INK, width=3 * SS)


def eye_spiral(d, x, y):
    pts = []
    for i in range(60):
        t = i / 59.0
        ang = t * math.pi * 5
        r = 1.5 + t * 6.5
        pts.append((x + math.cos(ang) * r * SS, y + math.sin(ang) * r * SS))
    d.line(pts, fill=INK, width=2 * SS)


def eye_heart(d, x, y, s=8):
    heart(d, x, y, s, HEART, HEART_D)


def brow(d, x, y, ang_deg, ln=11):
    a = math.radians(ang_deg)
    dx, dy = math.cos(a) * ln * SS, math.sin(a) * ln * SS
    d.line([x - dx, y - dy, x + dx, y + dy], fill=INK, width=3 * SS)


def mouth_smile(d, cx=CX, cy=None, w=15, h=10, open_fill=False):
    cy = CY + 16 * SS if cy is None else cy
    box = [cx - w * SS, cy - h * SS, cx + w * SS, cy + h * SS]
    if open_fill:
        d.pieslice(box, start=0, end=180, fill=(146, 74, 32, 255))
        d.arc(box, start=0, end=180, fill=INK, width=3 * SS)
    else:
        d.arc(box, start=15, end=165, fill=INK, width=3 * SS)


def mouth_frown(d, cx=CX, cy=None, w=13, h=9):
    cy = CY + 26 * SS if cy is None else cy
    d.arc([cx - w * SS, cy - h * SS, cx + w * SS, cy + h * SS],
          start=195, end=345, fill=INK, width=3 * SS)


def mouth_o(d, cx, cy, r=6, fill=(146, 74, 32, 255)):
    d.ellipse([cx - r * SS, cy - r * SS, cx + r * SS, cy + r * SS], fill=fill)
    d.ellipse([cx - r * SS, cy - r * SS, cx + r * SS, cy + r * SS],
              outline=INK, width=2 * SS)


def mouth_flat(d, cx, cy, w=10):
    d.line([cx - w * SS, cy, cx + w * SS, cy], fill=INK, width=3 * SS)


def mouth_grin(d, cx, cy, w=16, h=9):
    box = [cx - w * SS, cy - h * SS, cx + w * SS, cy + h * SS]
    d.pieslice(box, start=0, end=180, fill=WHITE)
    d.arc(box, start=0, end=180, fill=INK, width=3 * SS)
    d.line([cx - w * SS, cy, cx + w * SS, cy], fill=INK, width=2 * SS)


def mouth_wavy(d, cx, cy, w=14):
    pts = []
    for i in range(33):
        t = i / 32.0
        pts.append((cx + (t - 0.5) * 2 * w * SS,
                    cy + math.sin(t * math.pi * 3) * 3.2 * SS))
    d.line(pts, fill=INK, width=3 * SS)


def blush(d):
    for sx in (-1, 1):
        d.ellipse([CX + sx * 34 * SS - 8 * SS, CY + 10 * SS - 5 * SS,
                   CX + sx * 34 * SS + 8 * SS, CY + 10 * SS + 5 * SS], fill=BLUSH)


def tear(d, x, y, s=7):
    d.polygon([(x, y - s * SS), (x - s * 0.62 * SS, y + s * 0.5 * SS),
               (x + s * 0.62 * SS, y + s * 0.5 * SS)], fill=TEAR)
    d.ellipse([x - s * 0.62 * SS, y - s * 0.1 * SS, x + s * 0.62 * SS,
               y + s * 0.85 * SS], fill=TEAR)


def heart(d, cx, cy, s, col, edge):
    """s = half-width in units."""
    pts = []
    for i in range(41):
        t = i / 40.0 * 2 * math.pi
        hx = 16 * math.sin(t) ** 3
        hy = (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t)
              - math.cos(4 * t))
        pts.append((cx + hx * s * SS / 16.0, cy - hy * s * SS / 16.0))
    d.polygon(pts, fill=col)
    d.line(pts + [pts[0]], fill=edge, width=2 * SS)


def badge_base(col, edge):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([14 * SS, 30 * SS, S - 14 * SS, S - 30 * SS],
                        radius=16 * SS, fill=col, outline=edge, width=3 * SS)
    return img, d


def finish(img, name):
    img = img.resize((128, 128), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"))


EX, EY = 19 * SS, 10 * SS       # eye offsets from centre
LX, RX = CX - EX, CX + EX
EYY = CY - 8 * SS


def b_vui():
    img, d = face_base()
    eye_open(d, LX, EYY); eye_open(d, RX, EYY)
    mouth_smile(d, open_fill=True)
    return img


def b_cuoi():
    img, d = face_base()
    eye_happy(d, LX, EYY); eye_happy(d, RX, EYY)
    mouth_grin(d, CX, CY + 14 * SS)
    return img


def b_cuoi_khoc():
    img, d = face_base()
    eye_happy(d, LX, EYY); eye_happy(d, RX, EYY)
    mouth_grin(d, CX, CY + 14 * SS)
    tear(d, LX - 12 * SS, CY + 6 * SS, 8)
    tear(d, RX + 12 * SS, CY + 6 * SS, 8)
    return img


def b_khoc():
    img, d = face_base()
    brow(d, LX, CY - 22 * SS, -18); brow(d, RX, CY - 22 * SS, 198 - 180 + 18)
    eye_open(d, LX, EYY, 5.5, 8)
    eye_open(d, RX, EYY, 5.5, 8)
    mouth_frown(d)
    # tear streams: short rivulets just under the eyes,
    # ending in a round drop on the cheek
    for sx, x in ((-1, LX), (1, RX)):
        d.rounded_rectangle([x - 2.6 * SS, CY + 0 * SS, x + 2.6 * SS, CY + 17 * SS],
                            radius=3 * SS, fill=TEAR)
        d.ellipse([x - 4.4 * SS, CY + 14 * SS, x + 4.4 * SS, CY + 23 * SS], fill=TEAR)
    return img


def b_buon():
    img, d = face_base()
    brow(d, LX, CY - 22 * SS, -14); brow(d, RX, CY - 22 * SS, 14 + 180)
    eye_dot(d, LX, EYY); eye_dot(d, RX, EYY)
    mouth_frown(d, w=11, h=7)
    return img


def b_gian():
    img, d = face_base()
    # angry brows slanting down toward the centre
    d.line([LX - 10 * SS, CY - 24 * SS, LX + 9 * SS, CY - 15 * SS], fill=INK, width=4 * SS)
    d.line([RX + 10 * SS, CY - 24 * SS, RX - 9 * SS, CY - 15 * SS], fill=INK, width=4 * SS)
    eye_dot(d, LX, EYY, 3.6); eye_dot(d, RX, EYY, 3.6)
    mouth_frown(d, w=12, h=8)
    # anger vein, top right
    vx, vy = CX + 30 * SS, CY - 28 * SS
    for a in (0, 90, 45, 135):
        r = math.radians(a)
        d.line([vx, vy, vx + math.cos(r) * 7 * SS, vy + math.sin(r) * 7 * SS],
               fill=(216, 84, 60, 255), width=3 * SS)
    return img


def b_ngac_nhien():
    img, d = face_base()
    brow(d, LX, CY - 24 * SS, 0, 9); brow(d, RX, CY - 24 * SS, 0, 9)
    eye_open(d, LX, EYY, 7, 11); eye_open(d, RX, EYY, 7, 11)
    mouth_o(d, CX, CY + 20 * SS, 6)
    return img


def b_so():
    img, d = face_base()
    brow(d, LX, CY - 22 * SS, -16); brow(d, RX, CY - 22 * SS, 196)
    eye_open(d, LX, EYY, 7, 11); eye_open(d, RX, EYY, 7, 11)
    mouth_wavy(d, CX, CY + 22 * SS)
    # sweat drop
    tear(d, CX + 38 * SS, CY - 18 * SS, 7)
    return img


def b_choang():
    img, d = face_base()
    eye_spiral(d, LX, EYY); eye_spiral(d, RX, EYY)
    mouth_o(d, CX, CY + 20 * SS, 5)
    # stars around
    for (sx, sy) in ((-38, -30), (36, -34), (0, -44)):
        star(d, CX + sx * SS, CY + sy * SS, 5)
    return img


def star(d, cx, cy, s):
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        r = s * SS if i % 2 == 0 else s * 0.45 * SS
        pts.append((cx + math.cos(ang) * r, cy + math.sin(ang) * r))
    d.polygon(pts, fill=(255, 214, 64, 255), outline=(214, 132, 20, 255))


def b_ngu():
    img, d = face_base()
    eye_happy(d, LX, EYY, flip=True); eye_happy(d, RX, EYY, flip=True)
    mouth_o(d, CX, CY + 18 * SS, 4)
    f = ImageFont.truetype(FONT_BOLD, 20 * SS)
    d.text((CX + 26 * SS, CY - 46 * SS), "Z", font=f, fill=(90, 120, 190, 255))
    f2 = ImageFont.truetype(FONT_BOLD, 14 * SS)
    d.text((CX + 38 * SS, CY - 34 * SS), "Z", font=f2, fill=(90, 120, 190, 255))
    return img


def b_yeu():
    img, d = face_base()
    eye_heart(d, LX, EYY, 8); eye_heart(d, RX, EYY, 8)
    mouth_smile(d, open_fill=True)
    blush(d)
    return img


def b_tim():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    heart(d, CX, CY, 30, HEART, HEART_D)
    d.ellipse([CX - 16 * SS, CY - 16 * SS, CX - 4 * SS, CY - 6 * SS],
              fill=(255, 255, 255, 90))
    return img


def thumb(d, cx, cy, up=True):
    """One chunky painted thumb: a SINGLE filled silhouette
    (fist + thumb digit in one path) so the shape reads at
    chat size; the down variant flips the finished badge."""
    raw = [(-15, 24), (17, 24), (19, 12), (19, -3), (10, -7),
           (4, -9), (3, -18), (0, -28), (-7, -31), (-13, -27),
           (-14, -16), (-13, -6), (-16, 2), (-17, 12)]
    pts = [(cx + x * SS, cy + y * SS) for x, y in raw]
    d.polygon(pts, fill=WHITE)
    d.line(pts + [pts[0]], fill=INK, width=3 * SS, joint="curve")
    # knuckle creases
    d.line([cx + 6 * SS, cy + 2 * SS, cx + 15 * SS, cy + 2 * SS],
           fill=INK_SOFT, width=2 * SS)
    d.line([cx + 6 * SS, cy + 9 * SS, cx + 15 * SS, cy + 9 * SS],
           fill=INK_SOFT, width=2 * SS)
    # cuff
    d.rounded_rectangle([cx - 18 * SS, cy + 20 * SS, cx + 20 * SS, cy + 33 * SS],
                        radius=4 * SS, fill=(66, 120, 200, 255), outline=INK, width=3 * SS)


def b_like():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    thumb(d, CX - 2 * SS, CY + 2 * SS, up=True)
    return img


def b_dislike():
    img = b_like()
    return img.transpose(Image.FLIP_TOP_BOTTOM)


def b_yes():
    img, d = badge_base((64, 160, 84, 255), (30, 96, 46, 255))
    f = ImageFont.truetype(FONT_BOLD, 34 * SS)
    d.text((S // 2, S // 2), "YES", font=f, fill=WHITE, anchor="mm",
           stroke_width=2 * SS, stroke_fill=(30, 96, 46, 255))
    return img


def b_no():
    img, d = badge_base((206, 74, 64, 255), (130, 40, 34, 255))
    f = ImageFont.truetype(FONT_BOLD, 38 * SS)
    d.text((S // 2, S // 2), "NO", font=f, fill=WHITE, anchor="mm",
           stroke_width=2 * SS, stroke_fill=(130, 40, 34, 255))
    return img


def b_le_luoi():
    img, d = face_base()
    eye_happy(d, LX, EYY); eye_happy(d, RX, EYY)
    mouth_flat(d, CX, CY + 16 * SS, 12)
    # tongue sticking out below the mouth line
    d.rounded_rectangle([CX - 5 * SS, CY + 16 * SS, CX + 5 * SS, CY + 29 * SS],
                        radius=5 * SS, fill=(240, 110, 120, 255), outline=INK, width=2 * SS)
    d.line([CX, CY + 19 * SS, CX, CY + 27 * SS], fill=(200, 70, 84, 255), width=2 * SS)
    return img


def b_xau_ho():
    img, d = face_base()
    eye_happy(d, LX, EYY, flip=True); eye_happy(d, RX, EYY, flip=True)
    mouth_smile(d, cy=CY + 20 * SS, w=9, h=6)
    blush(d)
    return img


def b_nghi():
    img, d = face_base()
    eye_dot(d, LX, EYY); eye_open(d, RX, EYY, 6, 9)
    brow(d, RX, CY - 24 * SS, 0, 9)
    mouth_flat(d, CX + 3 * SS, CY + 20 * SS, 9)
    f = ImageFont.truetype(FONT_BOLD, 26 * SS)
    d.text((CX + 34 * SS, CY - 44 * SS), "?", font=f, fill=(90, 120, 190, 255))
    return img


def b_om():
    img, d = face_base()
    brow(d, LX, CY - 22 * SS, -14); brow(d, RX, CY - 22 * SS, 194)
    eye_happy(d, LX, EYY, flip=True); eye_happy(d, RX, EYY, flip=True)
    mouth_wavy(d, CX, CY + 22 * SS, 11)
    # thermometer
    tx = CX + 30 * SS
    d.rounded_rectangle([tx - 3 * SS, CY + 2 * SS, tx + 3 * SS, CY + 20 * SS],
                        radius=3 * SS, fill=WHITE, outline=INK, width=2 * SS)
    d.rounded_rectangle([tx - 2 * SS, CY + 8 * SS, tx + 2 * SS, CY + 19 * SS],
                        radius=2 * SS, fill=(216, 84, 60, 255))
    d.ellipse([tx - 6 * SS, CY + 16 * SS, tx + 6 * SS, CY + 28 * SS],
              fill=(216, 84, 60, 255), outline=INK, width=2 * SS)
    return img


def b_cuoi_deu():
    img, d = face_base()
    # sly look: calm dot eyes + one raised brow + a one-sided
    # smirk (no lid bars — they read as blindfolds)
    eye_dot(d, LX, EYY, 3.4); eye_dot(d, RX, EYY, 3.4)
    brow(d, LX, CY - 22 * SS, 4, 9)
    brow(d, RX, CY - 27 * SS, -8, 9)
    d.arc([CX - 6 * SS, CY + 8 * SS, CX + 18 * SS, CY + 25 * SS],
          start=25, end=165, fill=INK, width=3 * SS)
    return img


def b_hun():
    img, d = face_base()
    eye_happy(d, LX, EYY, flip=True); eye_happy(d, RX, EYY, flip=True)
    # puckered lips: small heart at the mouth spot
    heart(d, CX, CY + 18 * SS, 7, HEART, HEART_D)
    heart(d, CX + 30 * SS, CY - 22 * SS, 5.5, HEART, HEART_D)
    blush(d)
    return img


def b_kho_hieu():
    img, d = face_base()
    eye_x(d, LX, EYY); eye_x(d, RX, EYY)
    mouth_wavy(d, CX, CY + 22 * SS, 12)
    return img


def b_met():
    img, d = face_base()
    # droopy lids
    eye_dot(d, LX, EYY + 2 * SS); eye_dot(d, RX, EYY + 2 * SS)
    d.arc([LX - 8 * SS, EYY - 8 * SS, LX + 8 * SS, EYY + 8 * SS],
          start=200, end=340, fill=INK, width=3 * SS)
    d.arc([RX - 8 * SS, EYY - 8 * SS, RX + 8 * SS, EYY + 8 * SS],
          start=200, end=340, fill=INK, width=3 * SS)
    # open yawning mouth, low
    mouth_o(d, CX, CY + 22 * SS, 7)
    f = ImageFont.truetype(FONT_BOLD, 16 * SS)
    d.text((CX + 24 * SS, CY - 42 * SS), "Z", font=f, fill=(90, 120, 190, 255))
    return img


BUILDERS = {
    "vui": b_vui, "cuoi": b_cuoi, "cuoi_khoc": b_cuoi_khoc,
    "khoc": b_khoc, "buon": b_buon, "gian": b_gian,
    "ngac_nhien": b_ngac_nhien, "so": b_so, "choang": b_choang,
    "ngu": b_ngu, "yeu": b_yeu, "tim": b_tim,
    "like": b_like, "dislike": b_dislike, "yes": b_yes, "no": b_no,
    "le_luoi": b_le_luoi, "xau_ho": b_xau_ho, "nghi": b_nghi,
    "om": b_om, "cuoi_deu": b_cuoi_deu, "hun": b_hun,
    "kho_hieu": b_kho_hieu, "met": b_met,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in BUILDERS.items():
        finish(fn(), name)
        print("emote:", name)
    # contact sheet for eyeballing the family
    ids = list(BUILDERS)
    cols = 6
    rows = (len(ids) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * 96, rows * 96), (38, 46, 66, 255))
    for i, name in enumerate(ids):
        tile = Image.open(os.path.join(OUT, name + ".png")).resize((88, 88), Image.LANCZOS)
        sheet.paste(tile, ((i % cols) * 96 + 4, (i // cols) * 96 + 4), tile)
    sheet.save(os.path.join(os.path.dirname(__file__), "emotes_contact.png"))
    print("contact sheet written")


if __name__ == "__main__":
    main()
