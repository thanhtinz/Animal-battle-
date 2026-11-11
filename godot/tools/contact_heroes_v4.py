#!/usr/bin/env python3
"""Empire Age 14c-fix3 — proof contact sheet.

Top: all 8 heroes' south sprites interleaved (old, new, old, new)
at native size on one ground line over meadow grass — the unified
big-head template judged as a batch, per the calibration skill.
Bottom: a 4x NEAREST zoom strip (2 enlarged-head originals + 2 new)
so edge crispness (binary alpha, flat clusters, no halo) can be
judged directly.

Output: shots/empire_age_heroes8_sprites_v4.png
Run from the godot/ directory:  python3 tools/contact_heroes_v4.py
"""
import os
import random

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ASSETS = os.path.join(ROOT, "assets")
OUT = os.path.join(ROOT, "shots", "empire_age_heroes8_sprites_v4.png")

ORDER = ["ngan_ky", "loi_chan", "kim_hoa", "xich_diem",
         "lam_bao", "phong_linh", "bach_sa", "thach_son"]
ZOOM = ["ngan_ky", "bach_sa", "phong_linh", "thach_son"]
NAMES = {"ngan_ky": "Ngan Ky", "kim_hoa": "Kim Hoa",
         "lam_bao": "Lam Bao", "bach_sa": "Bach Sa",
         "loi_chan": "Loi Chan", "xich_diem": "Xich Diem",
         "phong_linh": "Phong Linh", "thach_son": "Thach Son"}


def grass(w: int, h: int, seed: int = 7) -> Image.Image:
    """Meadow backdrop in the game's grass family: base green with
    blade speckles and sparse flower dots."""
    rng = random.Random(seed)
    img = Image.new("RGBA", (w, h), (106, 176, 44, 255))
    px = img.load()
    greens = [(96, 164, 38), (116, 188, 50), (88, 152, 34),
              (124, 198, 58)]
    for _ in range(w * h // 6):
        x, y = rng.randrange(w), rng.randrange(h)
        px[x, y] = greens[rng.randrange(len(greens))] + (255,)
    for _ in range(w * h // 900):
        x, y = rng.randrange(w), rng.randrange(h)
        c = (240, 220, 90) if rng.random() < 0.6 else (250, 240, 200)
        px[x, y] = c + (255,)
    return img


def font(sz: int):
    p = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    return ImageFont.truetype(p, sz) if os.path.exists(p) \
        else ImageFont.load_default()


def main() -> None:
    spr = {h: Image.open(os.path.join(
        ASSETS, f"king_{h}_s.png")).convert("RGBA") for h in ORDER}
    gap, top_h = 10, 92
    row_w = sum(spr[h].width for h in ORDER) + gap * (len(ORDER) + 1)
    Z = 4
    zoom_w = sum(spr[h].width * Z for h in ZOOM) + gap * (len(ZOOM) + 1)
    W = max(row_w, zoom_w)
    H = 26 + top_h + 30 + 92 * Z + 8
    img = grass(W, H)
    dr = ImageDraw.Draw(img)
    # ground line
    gy = 26 + top_h
    dr.line([(0, gy), (W, gy)], fill=(60, 110, 24, 255), width=1)
    # Spread the row across the full sheet width; labels centred
    # under their sprite (fixed gaps collided on the narrow ones).
    total = sum(spr[h].width for h in ORDER)
    step = (W - total) / (len(ORDER) + 1)
    x = step
    for h in ORDER:
        s = spr[h]
        img.paste(s, (int(x), gy - s.height), s)
        dr.text((int(x + s.width / 2), gy + 6), NAMES[h],
                fill=(20, 40, 10, 255), font=font(11), anchor="ma")
        x += s.width + step
    zy = gy + 30
    x = gap
    for h in ZOOM:
        s = spr[h]
        big = s.resize((s.width * Z, s.height * Z), Image.NEAREST)
        img.paste(big, (x, zy), big)
        x += s.width * Z + gap
    img.save(OUT)
    print("saved", OUT, img.size)


if __name__ == "__main__":
    main()
