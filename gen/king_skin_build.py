#!/usr/bin/env python3
"""King skin builds — generic, DATA-DRIVEN (Tín, 2026-11-09:
"Thêm skin nữa"). Every King skin is one registry entry: a
turnaround sheet + a DYE BAND (the hue family that takes the
team colour). Adding a skin = adding an entry here + the sheet.

Registry (mirrored in godot/scripts/king_skins.gd SKINS):
  goc      Mặc định  Western king — built by king_western_build.py
                     + king_crisp_build.py, standard red band.
  vo_hiep  Võ Hiệp   built by king_wuxia_build.py — crimson band
                     (h<=0.03 / h>=0.955, s>=0.50; the plum-brown
                     hair forced the saturation floor).
  bach_y   Bạch Y    THIS script — pale blue-grey/periwinkle
                     cloth + silver ribbon: hues [0.635, 0.795],
                     s >= 0.06 (the robe's shading is pale; its
                     plum hair sits at h >= 0.87, safely outside;
                     the teal jade pendant at h ~0.47 outside).
  tu_y     Tử Y      THIS script — lavender dress: hues
                     [0.715, 0.855], s >= 0.16 (deep dress dyes
                     fully, pale petals at the band edge only
                     tint; plum hair h >= 0.87 outside).

Both new sheets: Tín-supplied 8-direction turnarounds (1290x430,
white JPEG bg), direction order S, SE, E, NE, N, NW, W, SW —
verified by the faces. Slice/key/scale/crisp reuse the wuxia
pipeline (king_wuxia_build.py helpers): border flood-fill keying
(preserves pale cloth that a global white key would eat), one
GLOBAL scale to 92 px figure height, shared k-means palette per
skin, consensus cleanup, cloth-band flatten.

FACE PROTECTION (both skins): after recolouring, tiny flat
clusters on the eye line are restored from the slot-0 sprite —
in-band ones (Tử Y's PURPLE eyes sit inside her own dye band;
Bạch Y's ribbon must NOT be restored: it is one long cluster, so
the size/flatness test excludes it) plus near-white ones (eye
whites, which JPEG tint can push into a pale band).

Recolour: in-band pixels take the slot hue (tools/recolor_teams
SLOTS factors); saturation is depth-ramped so band edges blend.
Everything outside the band stays pixel-identical — proven per
skin by the ac-survey tests in the Godot suite.

Run: python3 gen/king_skin_build.py [skin_id ...]
"""
import colorsys
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

GEN = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.join(GEN, "..", "godot")
sys.path.insert(0, os.path.join(GODOT, "tools"))
sys.path.insert(0, GEN)
from recolor_teams import SLOTS  # noqa: E402
from king_wuxia_build import (  # noqa: E402
    DIRS, TARGET_H, bbox_trim, consensus, figure_centres, hsv_maps,
    key_crop)

FILES = os.path.expanduser("~/workspace/user/files")
SKINS = {
    "bach_y": {
        "sheet": os.path.join(
            FILES, "8A200B1E-2064-49E9-A642-23D9845C1290"
                   "-photo-A2DFC3DD-0E24-4876-847E-04FDF3E9111E.jpg"),
        "hues": [(0.635, 0.795)],
        "sat_min": 0.06,
        "palette_k": 48,
    },
    "tu_y": {
        "sheet": os.path.join(
            FILES, "6B811D72-EAC3-4C38-8004-B37C69E02884"
                   "-photo-D7ECABFB-964E-4735-853E-5849EC0065DA.jpg"),
        "hues": [(0.715, 0.855)],
        "sat_min": 0.16,
        "palette_k": 56,
    },
    # ---- Expansion 2 (Tín, 2026-11-09 "Nhân vật kèm avatar") ----
    "ngan_ky": {
        # Silver hair, red eyes, silver-gold armour, RED cape.
        "sheet": os.path.join(
            FILES, "7900E68A-1036-459B-839C-33337D04191D"
                   "-photo-A41A294D-DD12-4CAA-B1B2-F2523423E7FA.jpg"),
        "hues": [(0.94, 1.0), (0.0, 0.035)],
        "sat_min": 0.45,
        "palette_k": 52,
    },
    "kim_hoa": {
        # Blonde, white flower, red skirt panels + hair ribbons.
        "sheet": os.path.join(
            FILES, "E0511CD8-836B-4524-BD9E-DD33E8222E41"
                   "-photo-8A927302-56A9-4E07-A963-94A1E86FD5AD.jpg"),
        "hues": [(0.955, 1.0), (0.0, 0.03)],
        "sat_min": 0.40,
        "palette_k": 52,
    },
    "lam_bao": {
        # Blonde prince, BLUE cape, white fur collar. The band
        # needs the value floor: his armour is blue-steel too, but
        # DARK (v < 0.30) or pale (s < 0.42); the cape body is the
        # mid-value saturated blue (verified: the rule selects
        # 7.9k px in the back pose's cape zone, ~0.5k on the front).
        # dark_hair: the sheet's blonde hair is recoloured to the
        # portrait's near-black dark brown BEFORE the crisp pass
        # (Tín's fix for the sheet/avatar mismatch) — hair is not
        # the dye band and stays identical across team colours.
        "sheet": os.path.join(
            FILES, "471FDE0C-DDED-4F9A-BC47-0DB9B7B9A8DD"
                   "-photo-4E9E1912-C43C-4201-8D00-77A5170FC22C.jpg"),
        "hues": [(0.56, 0.72)],
        "sat_min": 0.42,
        "val_min": 0.30,
        "palette_k": 52,
        "dark_hair": True,
    },
    "bach_sa": {
        # Silver hair, white veil dress, GOLD embroidery — almost
        # no coloured cloth, so the dye band is the cream/gold
        # trim (skin sits below the saturation floor; the blue
        # gems stay blue in every slot). Team distinction is
        # inherently subtle for this skin (flagged in the report).
        "sheet": os.path.join(
            FILES, "1519063C-34A0-448F-A48C-7F18DC9CDB39"
                   "-photo-8D3F1E10-AAF2-4AC1-9D1D-15B257C7FF5B.jpg"),
        "hues": [(0.06, 0.15)],
        "sat_min": 0.50,
        "palette_k": 48,
        "survey_min": 40,
    },
}

# Framed portrait avatars (Expansion 2): the trio strip carries
# ngan_ky / kim_hoa / lam_bao left-to-right; bach_sa is the
# single framed image. Frames are KEPT (they are part of the
# supplied art); only the white outside the frame is keyed out.
AVATAR_STRIP = os.path.join(
    FILES, "E0DC965F-1B82-4ABA-BC2C-33A1AAC33EDA"
           "-photo-83293D31-156F-4B8C-AEA9-AA08EB75D783.jpg")
AVATARS = {
    "ngan_ky": (AVATAR_STRIP, 0),
    "kim_hoa": (AVATAR_STRIP, 1),
    "lam_bao": (AVATAR_STRIP, 2),
    "bach_sa": (os.path.join(
        FILES, "C71900FC-E861-48DF-8DBA-70BDBA04D0D0"
               "-photo-4C86DE8A-A135-4B7F-99CC-E32E3A807C20.jpg"), -1),
}


def in_band(h: float, s: float, cfg: dict, v: float = 1.0) -> bool:
    if s < cfg["sat_min"] or v < cfg.get("val_min", 0.0):
        return False
    return any(lo <= h <= hi for lo, hi in cfg["hues"])


def band_mask(a: np.ndarray, cfg: dict) -> np.ndarray:
    h, s, v = hsv_maps(a)
    m = (a[..., 3] > 0) & (s >= cfg["sat_min"]) & (v >= cfg.get("val_min", 0.0))
    hue_ok = np.zeros_like(m)
    for lo, hi in cfg["hues"]:
        hue_ok |= (h >= lo) & (h <= hi)
    return m & hue_ok


def recolor_band(img: Image.Image, cfg: dict, target_hue: float,
                 sat_base: float, val_mult: float) -> Image.Image:
    """Rotate in-band pixels to the slot hue. Saturation is
    depth-ramped (band centre keeps full saturation, edges are
    pulled toward sat_base) — the same discipline as
    recolor_teams.recolor, generalised to arbitrary hue windows."""
    img = img.convert("RGBA")
    px = img.load()
    w, hgt = img.size
    half = min((hi - lo) / 2.0 for lo, hi in cfg["hues"])
    for y in range(hgt):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, ss, vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if not in_band(hh, ss, cfg, vv):
                continue
            depth = 0.0
            for lo, hi in cfg["hues"]:
                if lo <= hh <= hi:
                    depth = max(depth, min(hh - lo, hi - hh) / half)
            t_hue = min(1.0, depth)
            t_sat = min(1.0, max(0.0, (ss - cfg["sat_min"]) / 0.25))
            t = t_hue * (0.45 + 0.55 * t_sat)
            ns = ss * (sat_base + (1.0 - sat_base) * t)
            nv = vv * val_mult
            nr, ng, nb = colorsys.hsv_to_rgb(target_hue, ns, nv)
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return img


def face_protect(a: np.ndarray, cfg: dict) -> np.ndarray:
    """Eye-line identity pixels to restore after recolouring:
    tiny FLAT clusters (<= 6 px, bbox height <= 2, centroid at
    20-42% of figure height) that are either in the dye band
    (coloured eyes) or near-white (eye whites)."""
    H, W = a.shape[:2]
    h, s, v = hsv_maps(a)
    op = a[..., 3] > 0
    band = band_mask(a, cfg)
    near_white = op & (s < 0.20) & (v > 0.80)
    keep = np.zeros((H, W), bool)
    for cand in (band, near_white):
        seen = np.zeros_like(cand)
        for sy in range(H):
            for sx in range(W):
                if not cand[sy, sx] or seen[sy, sx]:
                    continue
                dq = deque([(sy, sx)])
                seen[sy, sx] = True
                comp = []
                while dq:
                    y, x = dq.popleft()
                    comp.append((y, x))
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = y + dy, x + dx
                            if 0 <= ny < H and 0 <= nx < W \
                                    and cand[ny, nx] and not seen[ny, nx]:
                                seen[ny, nx] = True
                                dq.append((ny, nx))
                if len(comp) <= 6:
                    ys = [p[0] for p in comp]
                    cy = sum(ys) / len(ys)
                    if max(ys) - min(ys) <= 2 and 0.20 * H <= cy <= 0.42 * H:
                        for y, x in comp:
                            keep[y, x] = True
    return keep


def band_flatten(a: np.ndarray, mask: np.ndarray, passes: int = 1) -> np.ndarray:
    H, W = a.shape[:2]
    for _ in range(passes):
        cur = a[..., :3].astype(np.int32)
        key = (cur[..., 0] << 16) | (cur[..., 1] << 8) | cur[..., 2]
        pad = np.pad(mask, 2)
        padk = np.pad(key, 2)
        changed = 0
        for y in range(H):
            for x in range(W):
                if not mask[y, x]:
                    continue
                win = pad[y:y + 5, x:x + 5]
                if win.mean() < 0.85:
                    continue
                ks = padk[y:y + 5, x:x + 5][win]
                vals, cnts = np.unique(ks, return_counts=True)
                best = vals[np.argmax(cnts)]
                if best != key[y, x]:
                    a[y, x, :3] = [(best >> 16) & 255, (best >> 8) & 255,
                                   best & 255]
                    changed += 1
        if changed == 0:
            break
    return a


def darken_hair(a: np.ndarray, frontish: bool) -> np.ndarray:
    """Lam Bào hair fix (Tín): the sheet's blonde hair becomes the
    portrait's near-black dark brown. The blonde palette RAMP is
    remapped to a dark ramp (value compressed into 0.05..0.35,
    hue set warm, saturation damped) so every highlight and
    shadow of the original shading survives — no flat fill.
    Hair pixels are found as connected blonde-range components
    that touch the figure's top rows or sit high (the hair mass
    and its long side locks); the face is spared twice over — it
    is its own component, and on front-ish poses an ellipse over
    the face zone is excluded explicitly. Skin ears caught at the
    hairline read as hair-covered at game size; the gold circlet
    inside the hair darkens to antique bronze (it sits inside the
    blonde range) — noted in the delivery report."""
    H, W = a.shape[:2]
    h, s, v = hsv_maps(a)
    cand = (a[..., 3] > 0) & (h >= 0.05) & (h <= 0.14) \
        & (s >= 0.22) & (s <= 0.75) & (v >= 0.42)
    keep = np.zeros((H, W), bool)
    seen = np.zeros((H, W), bool)
    for sy in range(H):
        for sx in range(W):
            if not cand[sy, sx] or seen[sy, sx]:
                continue
            dq = deque([(sy, sx)])
            seen[sy, sx] = True
            comp = []
            while dq:
                y, x = dq.popleft()
                comp.append((y, x))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < H and 0 <= nx < W \
                                and cand[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            dq.append((ny, nx))
            ys = [p[0] for p in comp]
            if min(ys) < 0.08 * H or sum(ys) / len(ys) < 0.30 * H:
                for y, x in comp:
                    keep[y, x] = True
    if frontish and keep.any():
        top = keep.copy()
        top[int(0.5 * H):, :] = False
        xs = np.where(top.any(0))[0]
        cx = float(xs.mean()) if len(xs) else W / 2.0
        yy, xx = np.mgrid[0:H, 0:W]
        ellipse = ((xx - cx) / (0.17 * W)) ** 2 \
            + ((yy - 0.35 * H) / (0.105 * H)) ** 2 <= 1.0
        keep &= ~ellipse
    ys, xs = np.where(keep)
    for y, x in zip(ys, xs):
        t = min(1.0, max(0.0, (v[y, x] - 0.42) / 0.58))
        nr, ng, nb = colorsys.hsv_to_rgb(
            0.075, min(0.5, s[y, x] * 0.6), 0.05 + t * 0.30)
        a[y, x, :3] = [int(nr * 255), int(ng * 255), int(nb * 255)]
    print("  dark_hair: remapped", int(keep.sum()), "px")
    return a


def build(skin_id: str, cfg: dict) -> None:
    sheet = np.asarray(Image.open(cfg["sheet"]).convert("RGB")).astype(np.int32)
    H, W = sheet.shape[:2]
    centres = figure_centres(sheet)
    cuts = [0] + [(centres[i] + centres[i + 1]) // 2 for i in range(7)] + [W]
    raw = {}
    for i, d in enumerate(DIRS):
        raw[d] = bbox_trim(key_crop(sheet[:, cuts[i]:cuts[i + 1]]))
        if cfg.get("dark_hair"):
            raw[d] = darken_hair(raw[d], d in ("s", "se", "sw"))
    factor = TARGET_H / raw["s"].shape[0]
    small = {}
    for d in DIRS:
        im = Image.fromarray(raw[d].astype(np.uint8), "RGBA")
        nw = max(2, int(round(im.width * factor)))
        nh = max(2, int(round(im.height * factor)))
        im = im.resize((nw, nh), Image.LANCZOS)
        a = np.asarray(im).astype(np.int32)
        a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
        small[d] = bbox_trim(a)
    K = cfg["palette_k"]
    rng = np.random.default_rng(7)
    pts = np.concatenate([small[d][small[d][..., 3] > 0][:, :3]
                          for d in DIRS]).astype(np.float64)
    sample = pts[rng.choice(len(pts), size=min(40000, len(pts)),
                            replace=False)]
    centers = [sample[rng.integers(len(sample))]]
    for _ in range(K - 1):
        C = np.stack(centers)
        d2 = ((sample[:, None, :] - C[None]) ** 2).sum(-1).min(1)
        centers.append(sample[rng.choice(len(sample), p=d2 / d2.sum())])
    C = np.stack(centers)
    for _ in range(60):
        d2 = ((sample[:, None, :] - C[None]) ** 2).sum(-1)
        lab = d2.argmin(1)
        newC = C.copy()
        for k in range(K):
            m = lab == k
            if m.any():
                newC[k] = sample[m].mean(0)
        if np.abs(newC - C).max() < 0.05:
            C = newC
            break
        C = newC
    sprites = {}
    protect = {}
    for d in DIRS:
        a = small[d].copy()
        op = a[..., 3] > 0
        P = a[op][:, :3].astype(np.float64)
        lab = ((P[:, None, :] - C[None]) ** 2).sum(-1).argmin(1)
        rgb = np.zeros_like(a[..., :3])
        rgb[op] = C[lab]
        a[..., :3] = rgb
        a = consensus(a)
        a = band_flatten(a, band_mask(a, cfg))
        sprites[d] = Image.fromarray(a.astype(np.uint8), "RGBA")
        if d in ("s", "se", "e", "w", "sw"):
            protect[d] = face_protect(a, cfg)
            print(skin_id, "protect", d, int(protect[d].sum()), "px")
        sprites[d].save(os.path.join(
            GODOT, "assets", "king_%s_%s.png" % (skin_id, d)))
        print(skin_id, "crisp", d, sprites[d].size,
              "colours", len(np.unique(a[a[..., 3] > 0][:, :3], axis=0)))
    # REDESIGN (Tín, 2026-11-09): characters are NOT recoloured
    # per team — one canonical colour set serves every slot, and
    # the player's NAME over the hero's head (tinted by slot)
    # carries allegiance instead. The recolor machinery above
    # (recolor_band / face_protect) stays in the file as the
    # documented history of the skin-era pipeline; build() no
    # longer emits slot variants. ( protect[] is still computed
    # and logged — it is free diagnostics of the face zones. )


def build_avatars() -> None:
    """Slice the framed portraits into avatar textures. The trio
    strip's frames are found as non-white column clusters; the
    single portrait is one cluster. White OUTSIDE the painted
    frame is keyed away by border flood fill (the frame is a
    closed border); each portrait is normalised onto a 320x320
    transparent canvas, frame kept whole."""
    outdir = os.path.join(GODOT, "assets", "avatars")
    os.makedirs(outdir, exist_ok=True)
    cache = {}
    for skin_id, (path, idx) in AVATARS.items():
        if path not in cache:
            cache[path] = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
        img = cache[path]
        nonwhite = (img.min(-1) < 200).any(0)
        runs = []
        inr = False
        for x, val in enumerate(nonwhite):
            if val and not inr:
                st = x
                inr = True
            if not val and inr:
                runs.append((st, x))
                inr = False
        if inr:
            runs.append((st, len(nonwhite)))
        x0, x1 = runs[0] if idx < 0 else runs[idx]
        sub = img[:, x0:x1]
        rows = np.where((sub.min(-1) < 200).any(1))[0]
        crop = sub[rows.min():rows.max() + 1]
        # key_crop takes RGB and returns RGBA (border flood:
        # outside-frame white -> alpha 0). Feeding it an RGBA
        # array makes it stack a 5th channel — the scramble bug
        # of the first avatar build.
        rgba = key_crop(np.ascontiguousarray(crop))
        im = Image.fromarray(rgba.astype(np.uint8), "RGBA")
        canvas = Image.new("RGBA", (320, 320), (0, 0, 0, 0))
        sc = min(320 / im.width, 320 / im.height)
        im2 = im.resize((max(2, int(im.width * sc)), max(2, int(im.height * sc))),
                        Image.LANCZOS)
        canvas.alpha_composite(im2, ((320 - im2.width) // 2, (320 - im2.height) // 2))
        canvas.save(os.path.join(outdir, "king_avatar_%s.png" % skin_id))
        print("avatar", skin_id, im.size, "-> 320x320")


def main() -> None:
    ids = sys.argv[1:] or list(SKINS.keys())
    if ids == ["avatars"]:
        build_avatars()
        return
    for skin_id in ids:
        build(skin_id, SKINS[skin_id])
    build_avatars()


if __name__ == "__main__":
    main()
