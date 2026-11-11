#!/usr/bin/env python3
"""13r entry-flow assets, cut from Tín's three reference images.

Outputs into godot/assets/:
  login_bg.png    — clean painted scene (generated, art_candidates/)
  loading_bg.png  — ref 2 as-is (its baked band is covered live)
  login_logo.png  — EMPIRE AGE plaque cut out of ref 1 (alpha)
  name_panel.png  — ref 3's ornate panel, white exterior -> alpha
  plaque_red.png  — ref 3's "Xác Nhận" button with the text erased
                    (per-row red interpolation), for nine-patch use

Flood fills are gradient-step BFS from the borders: smooth sky /
white / shadow gradients are eaten, hard gold & red edges stop them.
"""
import os
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

H = os.path.expanduser("~")
FILES = H + "/workspace/user/files/"
REF1 = FILES + "A24E7EAF-DFDE-4700-99AA-F24BF9917421-photo-95D2ABEC-8631-4754-8903-B6554865F894.jpg"
REF2 = FILES + "EED51351-ED1E-482B-8A1A-D2F9E8AF8C48-photo-D3EB13AA-63F9-4FEC-B0EE-AD4100D377DA.jpg"
REF3 = FILES + "A3176166-B815-4785-9C05-36CFB1D92B4B-photo-C6971580-A9E2-4D7E-B170-1A3570A57B73.jpg"
GEN_BG = H + "/workspace/empire-age/art_candidates/media-generation-empire-age-login-bg-0-6c5db3a3-a211-424e-a185-3c2192a24444.png"
OUT = H + "/workspace/empire-age/godot/assets/"


def gradient_flood_alpha(img: Image.Image, step: float = 26.0) -> Image.Image:
    """Alpha=0 where a border-connected smooth-gradient region lies."""
    a = np.asarray(img.convert("RGB")).astype(np.int16)
    h, w, _ = a.shape
    seen = np.zeros((h, w), dtype=bool)
    dq: deque = deque()
    for x in range(w):
        dq.append((0, x)); dq.append((h - 1, x))
    for y in range(h):
        dq.append((y, 0)); dq.append((y, w - 1))
    while dq:
        y, x = dq.popleft()
        if seen[y, x]:
            continue
        seen[y, x] = True
        c = a[y, x]
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx]:
                d = np.abs(a[ny, nx] - c).sum()
                if d < step:
                    dq.append((ny, nx))
    out = img.convert("RGBA")
    alpha = np.where(seen, 0, 255).astype(np.uint8)
    arr = np.asarray(out).copy()
    arr[:, :, 3] = alpha
    res = Image.fromarray(arr)
    # 1px alpha feather so the cut edge is not crunchy.
    al = res.split()[3].filter(ImageFilter.GaussianBlur(0.7))
    res.putalpha(al)
    return res


def keep_largest_component(img: Image.Image) -> Image.Image:
    """Drop stray sky wisps: keep only the biggest opaque component."""
    a = np.asarray(img.split()[3])
    small = (a[::4, ::4] > 40)
    h, w = small.shape
    label = np.zeros((h, w), dtype=np.int32)
    cur = 0
    sizes: dict[int, int] = {}
    for sy in range(h):
        for sx in range(w):
            if not small[sy, sx] or label[sy, sx]:
                continue
            cur += 1
            n = 0
            dq: deque = deque([(sy, sx)])
            label[sy, sx] = cur
            while dq:
                y, x = dq.popleft()
                n += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and small[ny, nx] and not label[ny, nx]:
                        label[ny, nx] = cur
                        dq.append((ny, nx))
            sizes[cur] = n
    if not sizes:
        return img
    big = max(sizes, key=sizes.get)
    mask_small = (label == big).astype(np.uint8) * 255
    mask = np.asarray(Image.fromarray(mask_small).resize(img.size, Image.NEAREST))
    arr = np.asarray(img).copy()
    arr[:, :, 3] = np.minimum(arr[:, :, 3], mask)
    return Image.fromarray(arr)


def trim(img: Image.Image) -> tuple[Image.Image, tuple[int, int]]:
    bbox = img.split()[3].getbbox()
    return img.crop(bbox), (bbox[0], bbox[1])


def main() -> None:
    # --- login + loading backgrounds -------------------------------------
    Image.open(GEN_BG).convert("RGB").save(OUT + "login_bg.png")
    Image.open(REF2).convert("RGB").save(OUT + "loading_bg.png")
    print("login_bg / loading_bg written")

    # --- logo plaque from ref 1 ------------------------------------------
    ref1 = Image.open(REF1).convert("RGB")
    crop = ref1.crop((600, 0, 1290, 190))
    logo = gradient_flood_alpha(crop, step=30.0)
    logo = keep_largest_component(logo)
    logo, off = trim(logo)
    logo.save(OUT + "login_logo.png")
    print("login_logo", logo.size, "trim offset", off)

    # --- name panel from ref 3 -------------------------------------------
    ref3 = Image.open(REF3).convert("RGB")
    panel = gradient_flood_alpha(ref3, step=22.0)
    panel, off = trim(panel)
    panel.save(OUT + "name_panel.png")
    print("name_panel", panel.size, "trim offset", off)
    ox, oy = off
    fw, fh = panel.size
    def frac(x0, y0, x1, y1):
        return tuple(round(v, 4) for v in (
            (x0 - ox) / fw, (y0 - oy) / fh, (x1 - ox) / fw, (y1 - oy) / fh))
    # Key overlay rects in ORIGINAL ref-3 coordinates, for the client.
    print("FIELD  frac", frac(300, 385, 980, 508))   # text area (after glyph)
    print("DICE   frac", frac(985, 392, 1108, 512))  # dice button hit area
    print("BUTTON frac", frac(318, 606, 970, 740))   # Xác Nhận hit area
    print("ERROR  frac", frac(190, 520, 1100, 550))  # error line under field

    # --- red plaque: the Xác Nhận button, text erased ---------------------
    # The clean red is BRIGHT and saturated; glyph faces are pale gold
    # and their drop shadows are dark maroon — both fail the strict
    # test. Per-row clean colour = median of strict-red pixels in the
    # glyph-free side columns; glyph rows inherit it (the red shading
    # is a horizontal gloss pattern, so a per-row colour rebuilds it).
    btn = np.asarray(ref3.crop((312, 600, 976, 746)).convert("RGB")).astype(np.float32)
    bh, bw, _ = btn.shape
    R, G, B = btn[:, :, 0], btn[:, :, 1], btn[:, :, 2]
    strict = (R >= 105) & (G <= 100) & (B <= 90) & ((R - G) >= 50)
    side = np.zeros(bw, dtype=bool)
    side[8:170] = True
    side[520:656] = True
    rowcol = np.zeros((bh, 3), dtype=np.float32)
    have = np.zeros(bh, dtype=bool)
    for y in range(bh):
        m = strict[y] & side
        if m.sum() >= 6:
            rowcol[y] = [np.median(btn[y, m, c]) for c in range(3)]
            have[y] = True
    ys = np.where(have)[0]
    for y in range(bh):
        if have[y]:
            continue
        lo = ys[ys < y]
        hi = ys[ys > y]
        if len(lo) and len(hi):
            a, b = lo[-1], hi[0]
            rowcol[y] = rowcol[a] + (rowcol[b] - rowcol[a]) * (y - a) / (b - a)
        elif len(lo):
            rowcol[y] = rowcol[lo[-1]]
        elif len(hi):
            rowcol[y] = rowcol[hi[0]]
    # Interior: replace wholesale with the per-row clean colour
    # (the red is a vertical gradient + horizontal gloss bands, so
    # the row colour IS the surface), feathered at the rect edges so
    # the baked inner bevel survives. Mid-red glyph-shadow pixels
    # pass any per-pixel "is red" test — only a full rebuild of the
    # glyph band erases the embossed ghost completely.
    y0, y1, x0, x1, fe = 28, 128, 58, 606, 12
    for y in range(y0, y1):
        for x in range(x0, x1):
            fx = min(1.0, min(x - x0, x1 - 1 - x) / fe)
            fy = min(1.0, min(y - y0, y1 - 1 - y) / fe)
            t = min(fx, fy)
            if t < 1.0:
                btn[y, x] = btn[y, x] * (1 - t) + rowcol[y] * t
            else:
                btn[y, x] = rowcol[y]
    plaque = Image.fromarray(np.clip(btn, 0, 255).astype(np.uint8))
    plaque.save(OUT + "plaque_red.png")
    print("plaque_red", plaque.size)
    # The crop's corners still hold the panel navy outside the
    # pointed silhouette — flood them to transparency, then bake
    # a 0.45x variant whose nine-patch caps land at ~58 px (the
    # size the form buttons actually render at).
    plaque = plaque.convert("RGBA")
    pw, ph = plaque.size
    pp = plaque.load()
    barre = bytearray(pw * ph)
    stack = []
    for x in range(pw):
        stack += [x, x + (ph - 1) * pw]
    for y in range(ph):
        stack += [y * pw, pw - 1 + y * pw]
    while stack:
        i = stack.pop()
        if barre[i]:
            continue
        barre[i] = 1
        x, y = i % pw, i // pw
        r, g, b = pp[x, y][0], pp[x, y][1], pp[x, y][2]
        if (r >= 105 and r - g >= 45 and g <= 120) or \
                (r >= 150 and g >= 100 and b <= 130):
            continue  # red body or gold frame: the button itself
        pp[x, y] = (r, g, b, 0)
        if x > 0:
            stack.append(i - 1)
        if x < pw - 1:
            stack.append(i + 1)
        if y > 0:
            stack.append(i - pw)
        if y < ph - 1:
            stack.append(i + pw)
    plaque.save(OUT + "plaque_red.png")
    small = plaque.resize((round(pw * 0.45), round(ph * 0.45)), Image.LANCZOS)
    small.save(OUT + "plaque_red_btn.png")
    print("plaque_red_btn", small.size, "(corners flooded to alpha)")


if __name__ == "__main__":
    main()
