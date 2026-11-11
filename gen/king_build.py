#!/usr/bin/env python3
"""Build the King design-gate assets from the AI generation (attempt 2).

Pipeline (mirrors the project's recut_smooth lessons):
  1. Key out the flat magenta page with un-blending (no magenta fringe).
  2. Save the full-res keyed source.
  3. Premultiplied-space LANCZOS resize to the unit pipeline size
     (content height 90 sheet px -> 44 world px at DISPLAY_SCALE 0.49,
     i.e. ~1.3x the Militia's 34.8 world px).
  4. Defringe: semi-transparent edge pixels take the colour of the
     nearest opaque pixel; alpha < 0.35 is cut.
  5. Preview on the game's own seamless grass: hero at 6x NN + the
     true relative-size trio (King / Militia / Villager) at 3x camera
     zoom, plus a literal 1x inset.
No game code is touched; this is a design gate only.
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

GEN = "/home/hatch/workspace/empire-age/gen"
GODOT = "/home/hatch/workspace/empire-age/godot"
SRC = GEN + "/media-generation-media-generation-empire-king-v-0-16ce7001-bdbc-4e12-8cbc-5f5aafe7399c.webp"
TARGET_H = 90  # sheet px of content -> 44 world px at scale 0.49


def key_magenta(img: Image.Image) -> Image.Image:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    k = np.minimum(r, b) - g  # 255 on pure magenta, <=0 on reds/skin
    alpha = 1.0 - np.clip((k - 40.0) / 100.0, 0.0, 1.0)
    bg = np.array([255.0, 0.0, 255.0], np.float32)
    out = a.copy()
    m = alpha > 0.02
    # un-blend: fg = (c - (1-a)*bg) / a
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
    # semi pixels borrow colour from the nearest opaque pixel (dilate)
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
    keyed = key_magenta(src)
    keyed.save(GEN + "/king_source_v2.png")
    print("source keyed:", keyed.size)

    scale = TARGET_H / keyed.height
    tw = max(1, int(round(keyed.width * scale)))
    sprite = defringe(resize_premul(keyed, (tw, TARGET_H)))
    bb = sprite.getchannel("A").getbbox()
    sprite = sprite.crop(bb)
    sprite.save(GODOT + "/assets/king.png")
    print("game sprite:", sprite.size,
          "-> world height at 0.49:", round(sprite.height * 0.49, 1))

    # ---- preview on the game's grass ----
    # The three seamless variants tiled with a 16 px crossfade overlap —
    # the same trick the game's ground bake uses (tone-matched pair
    # blends), so no DC seams and no kaleidoscope repetition.
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
    # literal 1x inset of the same trio on a dark plaque (reads as an
    # inset chip, not as figures floating in the field)
    plaque = Image.new("RGBA", (216, 88), (14, 20, 36, 242))
    pd = ImageDraw.Draw(plaque)
    pd.rounded_rectangle([0, 0, 215, 87], radius=10, outline=(120, 140, 180, 255))
    plaque.alpha_composite(trio, ((216 - trio.width) // 2, 88 - 10 - trio.height))
    prev.alpha_composite(plaque, (W - 216 - 24, 22))

    prev.convert("RGB").save(GODOT + "/shots/empire_age_king_preview_v1.png")
    print("preview saved")


if __name__ == "__main__":
    main()
