#!/usr/bin/env python3
"""Build the WESTERN MEDIEVAL King (Tín redirect 2026-11-09: the
soldiers are western knights — helmet + cross shield — so the Roman
emperor clashed; the King is now a medieval king: pointed gold
crown, short beard, ermine-trimmed cape, tabard + heater shield
with a gold lion).

Pipeline (same crisp lessons as king_build.py / recut_smooth):
  1. Key out the flat magenta page with un-blending.
  2. SOURCE-LEVEL EYE FIX: the raw generations draw the eyes as
     solid black bars (19x85 px, ~90% solid, aspect 1:4.5). The
     game's eye language (measured on the Militia sheet) is a slim
     soft dash: dark region ~5-7x7-8 px at final scale, only ~40%
     solid, warm brown-black core ~2-3 px wide with feathered
     shading. So each bar is painted over with a soft radial oval
     (dark warm-brown centre feathering out to the local skin tone)
     sized to land on those numbers after the downscale.
  3. Premultiplied LANCZOS resize to 90 sheet px (= 44 world px at
     DISPLAY_SCALE 0.49, ~1.3x the Militia), defringe, save sprite.
  4. Preview: hero 6x NN + true-size trio (Villager/King/Militia)
     on the game's grass + a face close-up plaque.

Team palettes come from godot/tools/recolor_teams.py (cape cloth,
tabard field and shield field are crimson = in the red dye band;
crown, fur, steel and blade sit outside it).
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

GEN = "/home/hatch/workspace/empire-age/gen"
GODOT = "/home/hatch/workspace/empire-age/godot"
SRC = GEN + "/media-generation-empire-king-western-v2-0-97bba0b1-4c58-4fd3-a791-5306bfb97b5c.webp"
SOURCE_OUT = GEN + "/king_western_source_v1.png"
TARGET_H = 90  # sheet px -> 44 world px at scale 0.49

# Painted-eye geometry in source px (content 1539x1402, scale .0642).
# Two-ellipse construction copied from the Militia's eye structure:
# a SLIM near-black warm core dash (final ~3x7 px, like the Militia's
# 2-3x7 core) inside a LIGHT warm halo (final extent ~6x9 px, no
# darker than lum ~120 outside the core). A single big radial
# gradient was tried first and read as hollow sockets — too much
# high-contrast area; the core/halo split is what the units use.
CORE_RX, CORE_RY = 24.0, 54.0
HALO_RX, HALO_RY = 47.0, 70.0
CORE_RGB = np.array((28, 15, 8), np.float32)
HALO_RGB = np.array((150, 116, 80), np.float32)


def key_magenta(img: Image.Image) -> Image.Image:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    k = np.minimum(r, b) - g  # 255 on pure magenta, <=0 on reds/skin
    alpha = 1.0 - np.clip((k - 40.0) / 100.0, 0.0, 1.0)
    bg = np.array([255.0, 0.0, 255.0], np.float32)
    out = a.copy()
    m = alpha > 0.02
    out[m] = (a[m] - (1.0 - alpha[m])[..., None] * bg) / alpha[m][..., None]
    out = np.clip(out, 0, 255)
    rgba = np.dstack([out, alpha * 255.0]).astype(np.uint8)
    im = Image.fromarray(rgba, "RGBA")
    bb = im.getchannel("A").getbbox()
    return im.crop(bb)


def resize_premul(img: Image.Image, size) -> Image.Image:
    a = np.asarray(img).astype(np.float32) / 255.0
    pm = a.copy()
    pm[..., :3] *= a[..., 3:4]
    chans = []
    for i in range(4):
        ch = Image.fromarray((pm[..., i] * 255.0).astype(np.uint8))
        chans.append(np.asarray(ch.resize(size, Image.LANCZOS)).astype(np.float32) / 255.0)
    pm = np.dstack(chans)
    al = pm[..., 3]
    rgb = np.zeros_like(pm[..., :3])
    m = al > 1e-4
    rgb[m] = pm[..., :3][m] / al[m][..., None]
    out = np.dstack([np.clip(rgb, 0, 1), al])
    return Image.fromarray((out * 255.0).astype(np.uint8), "RGBA")


def defringe(img: Image.Image) -> Image.Image:
    a = np.asarray(img).copy()
    alpha = a[..., 3].astype(np.int16)
    a[alpha < 89, 3] = 0  # cut the faint graded ring (< 0.35)
    alpha = a[..., 3]
    rgb = a[..., :3].astype(np.float32)
    known = alpha >= 250
    for _ in range(6):
        if known.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros(alpha.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh_k = np.roll(known, (dy, dx), axis=(0, 1))
            sh_c = np.roll(rgb, (dy, dx), axis=(0, 1))
            acc[sh_k] += sh_c[sh_k]
            cnt[sh_k] += 1
        new = (~known) & (cnt > 0) & (alpha > 0)
        rgb[new] = acc[new] / cnt[new][..., None]
        known |= new
    a[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


def dark_blobs(a, lum_max, y0, y1, x0, x1, min_n):
    """Connected components of dark opaque pixels in a band."""
    from collections import deque
    lum = 0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]
    mask = (lum < lum_max) & (a[..., 3] > 200)
    H, W = mask.shape
    mask[:y0, :] = False
    mask[y1:, :] = False
    mask[:, :x0] = False
    mask[:, x1:] = False
    seen = np.zeros_like(mask)
    blobs = []
    ys, xs = np.where(mask)
    for sy, sx in zip(ys, xs):
        if seen[sy, sx]:
            continue
        q = deque([(sy, sx)])
        seen[sy, sx] = True
        pts = []
        while q:
            cy, cx = q.popleft()
            pts.append((cy, cx))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        if len(pts) >= min_n:
            yy = [p[0] for p in pts]
            xx = [p[1] for p in pts]
            blobs.append((len(pts), min(xx), min(yy), max(xx), max(yy)))
    return sorted(blobs, reverse=True)


def fix_eyes(keyed: Image.Image) -> Image.Image:
    """Repaint the generated solid-black eye bars as soft unit eyes."""
    a = np.asarray(keyed).astype(np.float32)
    H, W = a.shape[:2]
    bars = dark_blobs(a.astype(int), 70, int(H * 0.30), int(H * 0.55),
                      int(W * 0.25), int(W * 0.75), 300)
    bars = [b for b in bars if (b[3] - b[1]) < 40 and (b[4] - b[2]) < 140][:2]
    assert len(bars) == 2, f"expected 2 eye bars, got {bars}"
    for n, bx0, by0, bx1, by1 in bars:
        cx, cy = (bx0 + bx1) / 2.0, (by0 + by1) / 2.0
        # local skin tone: cheek patch below the eye (above the beard)
        sx0, sx1 = int(cx - 45), int(cx + 45)
        sy0, sy1 = int(cy + 95), int(cy + 155)
        patch = a[sy0:sy1, sx0:sx1]
        lum = 0.3 * patch[..., 0] + 0.59 * patch[..., 1] + 0.11 * patch[..., 2]
        good = patch[(lum > 150) & (patch[..., 3] > 250)]
        skin = np.median(good[:, :3], axis=0)
        # paint: skin base -> light halo -> slim dark core
        px0, px1 = int(cx - HALO_RX - 16), int(cx + HALO_RX + 16)
        py0, py1 = int(cy - HALO_RY - 16), int(cy + HALO_RY + 16)
        yy, xx = np.mgrid[py0:py1, px0:px1]
        dc = np.sqrt(((xx - cx) / CORE_RX) ** 2 + ((yy - cy) / CORE_RY) ** 2)
        dh = np.sqrt(((xx - cx) / HALO_RX) ** 2 + ((yy - cy) / HALO_RY) ** 2)
        region = a[py0:py1, px0:px1]
        opaque = region[..., 3] > 250
        # 1) erase the old bar back to flat local skin (soft mask)
        w_erase = np.clip((1.12 - dh) / 0.24, 0.0, 1.0) * opaque
        col = region[..., :3] * (1 - w_erase[..., None]) \
            + skin[None, None, :] * w_erase[..., None]
        # 2) halo: gentle warm shading, capped strength
        w_halo = np.clip((1.10 - dh) / 0.35, 0.0, 1.0) * 0.55 * opaque
        col = col * (1 - w_halo[..., None]) + HALO_RGB[None, None, :] * w_halo[..., None]
        # 3) core dash: warm near-black, feathered rim
        w_core = np.clip((1.15 - dc) / 0.30, 0.0, 1.0) * opaque
        col = col * (1 - w_core[..., None]) + CORE_RGB[None, None, :] * w_core[..., None]
        region[..., :3] = col
        a[py0:py1, px0:px1] = region
        print(f"eye repainted at ({cx:.0f},{cy:.0f}), skin={skin.astype(int)}")
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def frame(sheet, cw, ch):
    im = Image.open(sheet).convert("RGBA")
    f = im.crop((0, 0, cw, ch))
    return f.crop(f.getchannel("A").getbbox())


def shadow(canvas: Image.Image, cx, base_y, w):
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    h = max(6, int(w * 0.16))
    d.ellipse([cx - w // 2, base_y - h // 2, cx + w // 2, base_y + h // 2],
              fill=(20, 30, 10, 120))
    sh = sh.filter(ImageFilter.GaussianBlur(max(2, w // 28)))
    canvas.alpha_composite(sh)


def main():
    src = Image.open(SRC)
    keyed = fix_eyes(key_magenta(src))
    keyed.save(SOURCE_OUT)
    print("source fixed:", keyed.size)

    scale = TARGET_H / keyed.height
    tw = max(1, int(round(keyed.width * scale)))
    sprite = defringe(resize_premul(keyed, (tw, TARGET_H)))
    bb = sprite.getchannel("A").getbbox()
    sprite = sprite.crop(bb)
    sprite.save(GODOT + "/assets/king.png")
    print("game sprite:", sprite.size,
          "-> world height at 0.49:", round(sprite.height * 0.49, 1))

    # ---- eye check on the final sprite vs the Militia's language ----
    sa = np.asarray(sprite).astype(int)
    eyes = dark_blobs(sa, 95, int(sa.shape[0] * 0.30), int(sa.shape[0] * 0.62),
                      int(sa.shape[1] * 0.2), int(sa.shape[1] * 0.8), 6)
    eyes = [e for e in eyes if (e[3] - e[1]) <= 12 and (e[4] - e[2]) <= 14][:2]
    for n, x0, y0, x1, y1 in eyes:
        print(f"sprite eye: {x1 - x0 + 1}x{y1 - y0 + 1}px n={n} "
              f"density={n / ((x1 - x0 + 1) * (y1 - y0 + 1)):.2f}")

    # ---- preview on the game's grass ----
    import random as _random
    _random.seed(7)
    variants = [Image.open(f"{GODOT}/assets/tiles_seamless/grass_{i}.png").convert("RGB").resize((114, 120))
                for i in range(3)]
    W, H = 1280, 680
    prev = Image.new("RGBA", (W, H))
    tw0, th0 = variants[0].size
    OV = 16
    ramp = np.clip(np.arange(OV, dtype=np.float32) / OV, 0, 1)
    gy = 0
    row_i = 0
    while gy < H:
        gx = 0
        col_i = 0
        while gx < W:
            t = variants[_random.randrange(3)].convert("RGBA")
            m = np.ones((th0, tw0), np.float32)
            if col_i:
                m[:, :OV] = ramp[None, :]
            if row_i:
                m[:OV, :] = np.minimum(m[:OV, :], ramp[:, None])
            mask = Image.fromarray((m * 255).astype(np.uint8))
            prev.paste(t, (gx, gy), mask)
            gx += tw0 - OV
            col_i += 1
        gy += th0 - OV
        row_i += 1

    # hero: 6x nearest-neighbour of the actual game sprite
    hero = sprite.resize((sprite.width * 6, sprite.height * 6), Image.NEAREST)
    hx, gy = 70, 618
    shadow(prev, hx + hero.width // 2, gy, int(hero.width * 0.62))
    prev.alpha_composite(hero, (hx, gy - hero.height))

    # trio: compose at TRUE world size, then 3x NN (camera zoom)
    mil = frame(f"{GODOT}/assets/militia.png", 184, 82)    # 34.8 world px
    vil = frame(f"{GODOT}/assets/villager.png", 82, 82)     # 32.2 world px
    king_true = sprite.resize((round(sprite.width * 0.49), 44), Image.NEAREST)
    mil_true = mil.resize((round(mil.width * 0.49), 35), Image.NEAREST)
    vil_true = vil.resize((round(vil.width * 0.46), 32), Image.NEAREST)
    trio = Image.new("RGBA", (150, 52), (0, 0, 0, 0))
    trio.alpha_composite(vil_true, (2, 52 - vil_true.height))
    trio.alpha_composite(king_true, (34, 52 - king_true.height))
    trio.alpha_composite(mil_true, (92, 52 - mil_true.height))
    trio3 = trio.resize((trio.width * 3, trio.height * 3), Image.NEAREST)
    tx, tgy = 700, 618
    shadow(prev, tx + 34 * 3 + king_true.width * 3 // 2, tgy, king_true.width * 3)
    shadow(prev, tx + 2 * 3 + vil_true.width * 3 // 2, tgy, vil_true.width * 3)
    shadow(prev, tx + 92 * 3 + mil_true.width * 3 // 2, tgy, mil_true.width * 3)
    prev.alpha_composite(trio3, (tx, tgy - trio3.height))

    # face close-up plaque: crop around the eye line of the sprite
    if len(eyes) == 2:
        ecx = (eyes[0][1] + eyes[0][3] + eyes[1][1] + eyes[1][3]) / 4.0
        ecy = (eyes[0][2] + eyes[0][4]) / 2.0
    else:  # fallback: proportional face centre
        ecx, ecy = sprite.width * 0.5, sprite.height * 0.36
    cw2, ch2 = 46, 40
    fx0 = int(min(max(ecx - cw2 / 2, 0), sprite.width - cw2))
    fy0 = int(min(max(ecy - ch2 / 2 + 2, 0), sprite.height - ch2))
    face = sprite.crop((fx0, fy0, fx0 + cw2, fy0 + ch2))
    face_big = face.resize((cw2 * 9, ch2 * 9), Image.NEAREST)
    plaque = Image.new("RGBA", (face_big.width + 16, face_big.height + 16),
                       (14, 20, 36, 242))
    pd = ImageDraw.Draw(plaque)
    pd.rounded_rectangle([0, 0, plaque.width - 1, plaque.height - 1],
                         radius=10, outline=(120, 140, 180, 255))
    plaque.alpha_composite(face_big, (8, 8))
    prev.alpha_composite(plaque, (W - plaque.width - 24, 22))

    prev.convert("RGB").save(GODOT + "/shots/empire_age_king_western_v1.png")
    print("preview saved")


if __name__ == "__main__":
    main()
