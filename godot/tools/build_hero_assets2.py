#!/usr/bin/env python3
"""Empire Age 14c — Stage A assets for the four new heroes
(loi_chan / xich_diem / phong_linh / thach_son).

Inputs (approved art, see NHAN-VAT-MOI-5-8.md):
  * portraits:  art_candidates/char{5..8}_*_portrait_*.png (1600x1600)
  * turnaround sheets generated from the approved full-bodies:
    art_candidates/turnaround/media-generation-<hero>-sheet-*.webp
    (5 views in a row: front, front-3/4, side, back-3/4, back)

Outputs (the game's established asset routes):
  * godot/assets/king_<id>_<dir8>.png  — in-game sprites, 92 px tall,
    palette-quantised to the roster dialect (existing heroes measure
    ~53 unique colours), w-side directions mirrored from e-side.
  * godot/assets/avatars/avatar_sq_<id>.png   — 320x320 bust crop.
  * godot/assets/avatars/king_avatar_<id>.png — 320x320 framed bust;
    the gold frame is lifted pixel-for-pixel from the existing four
    framed avatars (the pixels all four agree on), so the new four
    wear the identical Collection frame.

Run from the godot/ directory:  python3 tools/build_hero_assets2.py
"""
import glob
import os
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
EA = os.path.join(ROOT, "..")
ASSETS = os.path.join(ROOT, "assets")
AVATARS = os.path.join(ASSETS, "avatars")
SHEETS = os.path.join(EA, "art_candidates", "turnaround")

HEROES = {
    "loi_chan": "char5_loi_chan_portrait_v4.png",
    "xich_diem": "char6_xich_diem_portrait_v3.png",
    "phong_linh": "char7_phong_linh_portrait_v1.png",
    "thach_son": "char8_thach_son_portrait_v5.png",
}
DIRS5 = ["s", "se", "e", "ne", "n"]       # authored views, in sheet order
MIRROR = {"se": "sw", "e": "w", "ne": "nw"}
SPRITE_H = 92
PALETTE = 56


# ------------------------------------------------------------------ keying
def key_out_white(img: Image.Image) -> Image.Image:
    """Alpha from a border flood fill over near-white pixels (the
    turnaround sheets sit on pure white), with a soft 1-2 px edge.
    Same recipe family as tools/build_skill_assets.py."""
    rgb = img.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    seen = bytearray(w * h)
    q = deque()

    def is_bg(x, y):
        r, g, b = px[x, y]
        return r >= 242 and g >= 242 and b >= 242

    for x in range(w):
        for y in (0, h - 1):
            if is_bg(x, y) and not seen[y * w + x]:
                seen[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(x, y) and not seen[y * w + x]:
                seen[y * w + x] = 1
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] \
                    and is_bg(nx, ny):
                seen[ny * w + nx] = 1
                q.append((nx, ny))
    out = rgb.convert("RGBA")
    opx = out.load()
    for y in range(h):
        base = y * w
        for x in range(w):
            if seen[base + x]:
                r, g, b, _ = opx[x, y]
                opx[x, y] = (r, g, b, 0)
    return out


def split_sheet(img: Image.Image) -> list:
    """Split a keyed turnaround sheet into its 5 figures. The sheets
    are evenly composed, so: cut the width at the emptiest column of
    each fifth-boundary zone (hair strands can bridge the naive
    column clusters), then keep, per slice, the dominant connected
    component of a downscaled mask (drops stray strands/sparkles
    sliced off a neighbour)."""
    w, h = img.size
    alpha = img.getchannel("A")
    apx = alpha.load()
    # Boundary cuts are chosen on the LOWER half only: hair and
    # ribbons bridge neighbouring figures at head height, but the
    # gaps between feet are truly empty.
    col = [0] * w
    for x in range(w):
        s = 0
        for y in range(h // 2, h, 3):
            if apx[x, y] > 30:
                s += 1
        col[x] = s
    cuts = [0]
    for i in range(1, 5):
        mid = i * w // 5
        zone = range(max(0, mid - w // 16), min(w, mid + w // 16))
        cuts.append(min(zone, key=lambda x: col[x]))
    cuts.append(w)
    # Dominant component per slice, on a 1/6 mask.
    sw, sh = w // 6, h // 6
    small = alpha.resize((sw, sh), Image.BOX).point(lambda v: 255 if v > 30 else 0)
    spx = small.load()
    label = [[0] * sw for _ in range(sh)]
    comps = []  # (mass, x0, x1, y0, y1)
    cur = 0
    for sy in range(sh):
        for sx in range(sw):
            if spx[sx, sy] and not label[sy][sx]:
                cur += 1
                mass = 0
                x0 = x1 = sx
                y0 = y1 = sy
                stack = [(sx, sy)]
                label[sy][sx] = cur
                while stack:
                    cx, cy = stack.pop()
                    mass += 1
                    x0 = min(x0, cx)
                    x1 = max(x1, cx)
                    y0 = min(y0, cy)
                    y1 = max(y1, cy)
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy),
                                   (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < sw and 0 <= ny < sh \
                                and spx[nx, ny] and not label[ny][nx]:
                            label[ny][nx] = cur
                            stack.append((nx, ny))
                comps.append((mass, x0, x1, y0, y1))
    figs = []
    for i in range(5):
        cx_lo, cx_hi = cuts[i] // 6, cuts[i + 1] // 6
        best = None
        for mass, x0, x1, y0, y1 in comps:
            ccx = (x0 + x1) // 2
            # A component far wider than one slice is several
            # figures bridged by hair strands — not a figure; a
            # tiny one is a sliced-off strand or sparkle.
            if x1 - x0 > (cx_hi - cx_lo) * 1.35 or mass < 1200:
                continue
            if cx_lo <= ccx < cx_hi and (best is None or mass > best[0]):
                best = (mass, x0, x1, y0, y1)
        if best is not None:
            _, x0, x1, y0, y1 = best
            box = (max(0, x0 * 6 - 8), max(0, y0 * 6 - 8),
                   min(w, (x1 + 1) * 6 + 8), min(h, (y1 + 1) * 6 + 8))
            sub = img.crop(box)
        else:
            # Hair strands bridged this figure into a neighbour's
            # component: fall back to the alpha bbox of the raw slice.
            sub = img.crop((cuts[i], 0, cuts[i + 1], h))
        bbox = sub.getchannel("A").getbbox()
        figs.append(recenter_body(sub.crop(bbox)))
    return figs


def recenter_body(fig: Image.Image) -> Image.Image:
    """Pad the crop so the BODY's ground anchor (centroid of the leg
    rows) sits at the canvas centre — a weapon overhang (a blade
    swept forward, a hammer at the side) must not shift the point
    the game treats as the unit's feet."""
    a = fig.getchannel("A")
    apx = a.load()
    w, h = fig.size
    y_lo, y_hi = int(h * 0.55), int(h * 0.97)
    sx = n = 0
    for y in range(y_lo, y_hi):
        for x in range(w):
            if apx[x, y] > 40:
                sx += x
                n += 1
    if n == 0:
        return fig
    cx = sx / n
    pad_l = pad_r = 0
    if cx < w / 2:
        pad_r = int(round(2 * (w / 2 - cx)))
    else:
        pad_l = int(round(2 * (cx - w / 2)))
    if pad_l or pad_r:
        out = Image.new("RGBA", (w + pad_l + pad_r, h), (0, 0, 0, 0))
        out.paste(fig, (pad_l, 0))
        return out
    return fig


# ------------------------------------------------------------------ colour
# 14c-fix: the turnaround generations lean pale/watercolour — after
# the 56-colour quantise the four read washed-out in game (Phong
# Linh near-ghostly against the bright grass; measured mean HSV
# saturation 0.17–0.29 vs 0.39–0.43 for Ngân Kỵ/Kim Hoa). Grade each
# hero BEFORE quantising: a saturation multiplier, a value gamma
# that deepens mid-tones (pure whites stay white), and an extra
# saturation push inside the hero's signature hue band, biased to
# the approved portraits. The grade is blended by alpha so the
# keyed edge pixels (whose RGB still carries the white backdrop)
# are not tinted into a halo.
GRADE = {
    # hero: (sat x, value gamma, hue band (lo, hi), band sat x)
    # 14c-fix3: the grade now runs at sheet resolution (before the
    # premultiplied downscale), where colours are purer than at the
    # old 92-px stage — xich_diem / thach_son / phong_linh are
    # trimmed back so the shipped sprites keep the exact saturation
    # the owner approved in 14c-fix (0.44 / 0.55 / 0.38 / 0.40).
    "loi_chan": (1.30, 1.12, (0.66, 0.85), 1.20),    # violet
    "xich_diem": (1.02, 1.10, (0.93, 1.07), 1.05),   # crimson (wraps 0)
    "phong_linh": (1.68, 1.20, (0.33, 0.56), 1.28),  # mint-teal
    "thach_son": (1.18, 1.13, (0.04, 0.17), 1.12),   # bronze / ochre
}


def grade_colours(img: Image.Image, hero: str) -> Image.Image:
    ksat, gamma, (hlo, hhi), kband = GRADE[hero]
    arr = np.asarray(img.convert("RGBA")).astype(np.float32)
    rgb = arr[..., :3] / 255.0
    a = arr[..., 3] / 255.0
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    d = mx - mn
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.zeros_like(mx)
    nz = d > 1e-6
    idx = nz & (mx == r)
    hue[idx] = ((g - b)[idx] / d[idx]) % 6
    idx = nz & (mx == g)
    hue[idx] = ((b - r)[idx] / d[idx]) + 2
    idx = nz & (mx == b)
    hue[idx] = ((r - g)[idx] / d[idx]) + 4
    hue /= 6.0
    sat = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    if hhi > 1.0:
        band = (hue >= hlo) | (hue <= hhi - 1.0)
    else:
        band = (hue >= hlo) & (hue <= hhi)
    sat2 = np.clip(sat * ksat * np.where(band, kband, 1.0), 0, 1)
    val2 = np.power(mx, gamma)
    h6 = hue * 6.0
    ii = np.floor(h6).astype(int) % 6
    f = h6 - np.floor(h6)
    p = val2 * (1 - sat2)
    q = val2 * (1 - sat2 * f)
    t = val2 * (1 - sat2 * (1 - f))
    out = np.zeros_like(rgb)
    for i, (rr, gg, bb) in enumerate([(val2, t, p), (q, val2, p),
                                      (p, val2, t), (p, q, val2),
                                      (t, p, val2), (val2, p, q)]):
        m = ii == i
        out[..., 0] = np.where(m, rr, out[..., 0])
        out[..., 1] = np.where(m, gg, out[..., 1])
        out[..., 2] = np.where(m, bb, out[..., 2])
    grey = sat <= 1e-6
    out[grey] = np.stack([val2] * 3, axis=2)[grey]
    blend = np.clip(a, 0, 1)[..., None]
    final = rgb * (1 - blend) + out * blend
    res = np.concatenate([(final * 255).round(), arr[..., 3:4]], axis=2)
    return Image.fromarray(res.astype(np.uint8), "RGBA")


# ------------------------------------------------------------------ 14c-fix3
# Crisp pixel dialect + one big-head template for the whole roster.
#
# The owner called the new four's sprites "cắt lem" (smeared cut):
# measured against the original four — BINARY alpha (0 semi-
# transparent pixels) and 48–52 colours — the 14c/14c-fix pipeline
# above (plain LANCZOS resize + the soft 90/210 alpha ramp in the
# old quantise_sprite) shipped 191–237 semi-transparent halo pixels
# per sprite and 228–362 colours. The fix adapts the skill-icon
# dialect (fixed grid + palette quantise) to sprites:
#   * colour travels PREMULTIPLIED through every resample, so the
#     white page can never bleed into edge colours (no halo);
#   * alpha snaps BINARY at 0.5 coverage, isolated 1-px specks are
#     dropped and 1-px holes filled — a hard silhouette;
#   * colours snap to a 52-colour median-cut palette, NO dither —
#     flat clusters like the originals, no intermediate shades.
#
# Head template (owner: "nếu đầu to thì cho các nhân vật cũ đầu to
# luôn" — big heads for everyone, ONE template): head (top -> jaw,
# incl. hair) = HEAD_TARGET of ink height for all 8 heroes.
# HEAD_NOW = the jaw fraction measured by eye on the shipped south
# sprites over a 6x row grid (jaw row + 1) / 92. Each sheet figure
# is warped vertically — head segment scaled, body segment counter-
# scaled, feet pinned to the ground line — before pixelising. (The
# original four get the same warp at sprite level in
# tools/build_hero_fix3.py, which also warps their rig specs.)
HEAD_TARGET = 43.0 / 92.0
HEAD_NOW = {"loi_chan": 40.0 / 92.0, "xich_diem": 40.0 / 92.0,
            "phong_linh": 39.0 / 92.0, "thach_son": 45.0 / 92.0}
CRISP_COLOURS = 52


def _premul(arr: np.ndarray) -> np.ndarray:
    a = arr[..., 3:4]
    return np.concatenate([arr[..., :3] * a, a], axis=2)


def _unpremul(arr: np.ndarray) -> np.ndarray:
    a = arr[..., 3:4]
    rgb = np.where(a > 1e-4, arr[..., :3] / np.maximum(a, 1e-4), 0.0)
    return np.concatenate([np.clip(rgb, 0, 1), a], axis=2)


def _to_img(arr: np.ndarray) -> Image.Image:
    return Image.fromarray(
        (np.clip(arr, 0, 1) * 255).round().astype(np.uint8), "RGBA")


def warp_rows(img: Image.Image, a_src: float, a_dst: float) -> Image.Image:
    """Vertical piecewise-linear warp: continuous row a_src lands on
    a_dst; top (0) and bottom (h) stay fixed. Bilinear sampling over
    premultiplied colours, so edges never pick up page colour."""
    arr = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    pm = _premul(arr)
    h = pm.shape[0]
    dst = np.arange(h, dtype=np.float32) + 0.5
    src = np.where(dst <= a_dst, dst * (a_src / a_dst),
                   a_src + (dst - a_dst) * ((h - a_src) / (h - a_dst)))
    src = np.clip(src - 0.5, 0, h - 1)
    i0 = np.floor(src).astype(int)
    i1 = np.minimum(i0 + 1, h - 1)
    f = (src - i0).astype(np.float32)[:, None, None]
    return _to_img(_unpremul(pm[i0] * (1 - f) + pm[i1] * f))


def premul_resize(img: Image.Image, size: tuple) -> Image.Image:
    """LANCZOS resize with premultiplied colour: edge pixels keep
    their true colour instead of a blend with the transparent
    backdrop's RGB."""
    arr = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    pim = _to_img(_premul(arr)).resize(size, Image.LANCZOS)
    return _to_img(_unpremul(
        np.asarray(pim).astype(np.float32) / 255.0))


def crisp_snap(img: Image.Image, colours: int = CRISP_COLOURS) -> Image.Image:
    """Snap a soft-alpha RGBA (already at final size) to the shipped
    roster's measured profile: binary alpha (0 semi-transparent
    pixels) + a flat median-cut palette, no dither."""
    from scipy import ndimage
    arr = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    mask = arr[..., 3] >= 0.5
    # Drop isolated single pixels (resize dust); a 1-comp component
    # has no opaque neighbour by definition.
    lab, n = ndimage.label(mask)
    if n:
        sizes = ndimage.sum(mask, lab, range(1, n + 1))
        dust = np.isin(lab, np.flatnonzero(sizes <= 1) + 1)
        mask = mask & ~dust
    # Fill 1-px holes: transparent pixels walled in on all 4 sides.
    up = np.zeros_like(mask); up[1:] = mask[:-1]
    dn = np.zeros_like(mask); dn[:-1] = mask[1:]
    lf = np.zeros_like(mask); lf[:, 1:] = mask[:, :-1]
    rt = np.zeros_like(mask); rt[:, :-1] = mask[:, 1:]
    mask = mask | (~mask & up & dn & lf & rt)
    # Palette from the surviving pixels only, then a hard map.
    rgb = Image.fromarray(
        (np.clip(arr[..., :3], 0, 1) * 255).round().astype(np.uint8), "RGB")
    px = np.asarray(rgb)[mask]
    strip = Image.fromarray(px.reshape(1, -1, 3), "RGB")
    pal = strip.quantize(colors=colours, method=Image.MEDIANCUT)
    q = rgb.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")
    out = q.convert("RGBA")
    out.putalpha(Image.fromarray((mask * 255).astype(np.uint8), "L"))
    # Transparent pixels carry NO colour: un-premultiplying the
    # resample leaves amplified quantisation noise under alpha 0,
    # while the shipped originals are exactly (0,0,0,0) there (the
    # rig builder's rest-pose diff counts full RGBA tuples).
    arr = np.asarray(out).copy()
    arr[~mask] = 0
    return Image.fromarray(arr, "RGBA")


def make_sprites(hero: str) -> None:
    path = glob.glob(os.path.join(SHEETS, f"media-generation-{hero.replace('_', '-')}-sheet-*.webp"))[0]
    sheet = key_out_white(Image.open(path))
    figs = split_sheet(sheet)
    authored = {}
    for d, fig in zip(DIRS5, figs):
        fig = grade_colours(fig, hero)
        fig = warp_rows(fig, HEAD_NOW[hero] * fig.height,
                        HEAD_TARGET * fig.height)
        scale = SPRITE_H / fig.height
        spr = premul_resize(fig, (max(1, round(fig.width * scale)),
                                  SPRITE_H))
        spr = crisp_snap(spr)
        authored[d] = spr
        spr.save(os.path.join(ASSETS, f"king_{hero}_{d}.png"))
    for src, dst in MIRROR.items():
        authored[src].transpose(Image.FLIP_LEFT_RIGHT).save(
            os.path.join(ASSETS, f"king_{hero}_{dst}.png"))
    print(f"{hero}: sprites " +
          ", ".join(f"{d} {authored[d].width}x{authored[d].height}" for d in DIRS5))


# ------------------------------------------------------------------ avatars
def _octagon(size: int, inset: int, cut: int) -> Image.Image:
    from PIL import ImageDraw
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    s = size - inset
    d.polygon([(inset + cut, inset), (s - cut, inset), (s, inset + cut),
               (s, s - cut), (s - cut, s), (inset + cut, s),
               (inset, s - cut), (inset, inset + cut)], fill=255)
    return m


def frame_template() -> tuple:
    """The Collection frame (octagonal silver-gold band + top
    diamond) is geometrically identical across the existing four,
    though each was rendered as its own artwork. Lift it from the
    ngan_ky donor: every pixel outside the inner octagon opening
    (inset 13, corner cut 76 at 320 px) is frame; the bust of a new
    hero is clipped INTO that opening."""
    donor = Image.open(os.path.join(AVATARS, "king_avatar_ngan_ky.png")) \
        .convert("RGBA")
    inner = _octagon(320, 13, 76)
    tpl = donor.copy()
    tp = tpl.load()
    ip = inner.load()
    for y in range(320):
        for x in range(320):
            if ip[x, y]:
                tp[x, y] = (0, 0, 0, 0)
    return tpl, inner


# Bust crops (fractions of the 1600x1600 portraits): face + shoulders.
SQ_CROP = (0.07, 0.00, 0.95, 0.88)
FR_CROP = (0.03, 0.00, 0.99, 0.96)


def make_avatars(hero: str, tpl: Image.Image, inner: Image.Image) -> None:
    src = Image.open(os.path.join(EA, "art_candidates", HEROES[hero])).convert("RGB")
    w, h = src.size
    x0, y0, x1, y1 = SQ_CROP
    bust = src.crop((int(w * x0), int(h * y0), int(w * x1), int(h * y1)))
    bust = bust.resize((320, 320), Image.LANCZOS)
    bust.save(os.path.join(AVATARS, f"avatar_sq_{hero}.png"))
    x0, y0, x1, y1 = FR_CROP
    fbust = src.crop((int(w * x0), int(h * y0), int(w * x1), int(h * y1)))
    fbust = fbust.resize((320, 320), Image.LANCZOS).convert("RGBA")
    fbust.putalpha(inner) # bust lives only inside the octagon opening
    fbust.alpha_composite(tpl)
    fbust.save(os.path.join(AVATARS, f"king_avatar_{hero}.png"))
    print(f"{hero}: avatars done")


def main() -> None:
    tpl, inner = frame_template()
    tpl.save("/tmp/ea_frame_template.png")
    for hero in HEROES:
        make_sprites(hero)
        make_avatars(hero, tpl, inner)


if __name__ == "__main__":
    main()
