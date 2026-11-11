#!/usr/bin/env python3
"""King skin "Võ Hiệp" (vo_hiep) — build pipeline (Tín's own skin
art, delivered 2026-11-09: "Cái bạn là gốc còn này là skin" — Bé's
Western crisp King stays the DEFAULT skin "goc"; this wuxia warlord
is an optional alternate appearance of the same King unit).

Sources (Tín-supplied, in ~/workspace/user/files/):
  * C1B8DC87-...jpg — the 8-direction turnaround sheet (1290x430,
    white JPEG background).
  * 4351E3B1-...jpg — the detailed portrait (reference only; the
    turnaround carries every direction the game needs).

PIPELINE:
  1. SLICE: the figures' ponytails touch across columns, so plain
     gap detection merges them. The boots/bodies separate cleanly
     in the lower band (y >= 300): 8 clusters there give the 8
     figure centres; slices are cut at the midpoints between
     neighbouring centres (Voronoi columns).
     Order on the sheet, verified by the faces:
     S, SE, E, NE, N, NW, W, SW (clockwise from the front).
  2. KEY: the background is flat white JPEG, but the character
     Wears white fur — a global white key would eat the cape.
     Instead: flood-fill from the crop borders through
     background-like pixels (min channel >= 240) only; the art's
     darker outline stops the flood, interior whites survive.
     Then keep the largest opaque component and trim a 2-pass
     near-white halo ring left by JPEG bleed.
  3. SCALE: one global factor for all 8 poses (relative proportions
     stay true): the S pose lands at TARGET_H px tall — the same
     figure height class as the Western king (90 px), so both skins
     share the game's king display scale (0.49 -> ~45 world px,
     ~1.3x infantry).
  4. CRISP (the "Vô game mờ quá" lesson — never ship a smooth
     downscale): binarised alpha, ONE shared k-means palette
     (K=52, seed 7) across all 8 poses so colours cannot drift
     between directions, neighbour-consensus cleanup, a mode-filter
     flatten inside the strict red band (scarf/tassels — the dye
     surface) and a gentle one inside the near-white fur band.
  5. TEAM COLOURS: the red band rotates per slot via
     tools/recolor_teams.py's recolor() (scarf + tassels + sash
     accents), EXCEPT the eyes: tiny high-saturation red clusters
     in the face zone of the five faced poses are restored from
     the slot-0 sprite after recolouring — the King's red eyes are
     identity, not faction cloth. Skin/hair/fur/gold stay
     pixel-identical across slots (proven by the ac-survey tests).

Outputs: godot/assets/king_vo_hiep_<dir>.png (slot 0) and the same
names under assets/enemy|team2|team3/ (slots 1-3).
Run: python3 gen/king_wuxia_build.py
"""
import colorsys
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

GEN = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(GEN, "..")
GODOT = os.path.join(ROOT, "godot")
sys.path.insert(0, os.path.join(GODOT, "tools"))
import recolor_teams as _rt  # noqa: E402
from recolor_teams import SLOTS  # noqa: E402

# BAND NARROWING (measured on the first builds): hue alone cannot
# separate this King's dye surface from his hair. The hair's dark
# tones are a desaturated PLUM-brown — RGB like (101, 68, 70),
# where G ~ B puts the hue at 0.97-1.00 (inside any crimson band)
# but saturation is only ~0.33. The scarf/tassels are TRUE crimson:
# saturation 0.65-0.80. So this build recolours with a high
# saturation floor before calling the shared recolor():
# h <= 0.03 or h >= 0.955 AND s >= 0.50. Dark maroon robe trim
# (s ~0.43) stays undyed in every slot — it reads as black trim.
# The standard band stays untouched for every other asset.
_rt.RED_HI = 0.03
_rt.RED_LO = 0.955
_rt.MIN_SAT = 0.50
recolor = _rt.recolor

SHEET = os.path.expanduser(
    "~/workspace/user/files/C1B8DC87-8FB7-409C-91CB-AD04A927433D"
    "-photo-A76F84AB-3D52-4927-BE0C-E4F137529419.jpg")
DIRS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]
FACED = {"s", "se", "e", "w", "sw"}  # poses with a visible face/eyes
TARGET_H = 92
K = 52
SEED = 7


# ---------------------------------------------------------------- slice

def figure_centres(a: np.ndarray) -> list:
    """8 figure centres from the clean lower band (boots/bodies)."""
    bg = a.min(-1) > 238
    band = ~bg[300:, :]
    colhas = band.any(0)
    clusters = []
    start = None
    for x in range(a.shape[1]):
        if colhas[x] and start is None:
            start = x
        elif not colhas[x] and start is not None:
            clusters.append((start, x - 1))
            start = None
    if start is not None:
        clusters.append((start, a.shape[1] - 1))
    assert len(clusters) == 8, "expected 8 figures, got %d" % len(clusters)
    return [(c[0] + c[1]) // 2 for c in clusters]


def key_crop(rgb: np.ndarray) -> np.ndarray:
    """White-background keying by border flood fill. Returns RGBA."""
    H, W = rgb.shape[:2]
    bg_like = rgb.min(-1) >= 240
    seen = np.zeros((H, W), bool)
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            if bg_like[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(H):
        for x in (0, W - 1):
            if bg_like[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < H and 0 <= nx < W and bg_like[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    alpha = np.where(seen, 0, 255).astype(np.uint8)
    # Keep the largest opaque component (drops stray JPEG islands).
    op = alpha > 0
    lab = np.zeros((H, W), np.int32)
    cur = 0
    best, best_n = 0, -1
    for sy in range(H):
        for sx in range(W):
            if not op[sy, sx] or lab[sy, sx]:
                continue
            cur += 1
            n = 0
            dq = deque([(sy, sx)])
            lab[sy, sx] = cur
            while dq:
                y, x = dq.popleft()
                n += 1
                for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < H and 0 <= nx < W and op[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = cur
                        dq.append((ny, nx))
            if n > best_n:
                best, best_n = cur, n
    alpha = np.where(lab == best, alpha, 0).astype(np.uint8)
    # Halo trim: near-white opaque pixels touching transparency are
    # JPEG bleed, not art — peel up to 2 rings.
    for _ in range(2):
        op = alpha > 0
        near = rgb.min(-1) >= 236
        touch = np.zeros_like(op)
        touch[1:, :] |= ~op[:-1, :]
        touch[:-1, :] |= ~op[1:, :]
        touch[:, 1:] |= ~op[:, :-1]
        touch[:, :-1] |= ~op[:, 1:]
        alpha = np.where(op & near & touch, 0, alpha).astype(np.uint8)
    out = np.dstack([rgb, alpha])
    return out


def bbox_trim(a: np.ndarray) -> np.ndarray:
    ys, xs = np.where(a[..., 3] > 0)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


# ---------------------------------------------------------------- crisp

def hsv_maps(a):
    rgb = a[..., :3].astype(np.float32) / 255.0
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    r_, g_, b_ = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    m = d > 1e-6
    h[m & (mx == r_)] = ((g_ - b_) / np.maximum(d, 1e-9))[m & (mx == r_)] % 6
    h[m & (mx == g_)] = ((b_ - r_) / np.maximum(d, 1e-9) + 2)[m & (mx == g_)]
    h[m & (mx == b_)] = ((r_ - g_) / np.maximum(d, 1e-9) + 4)[m & (mx == b_)]
    h /= 6.0
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def consensus(a: np.ndarray, passes: int = 3) -> np.ndarray:
    H, W = a.shape[:2]
    op = a[..., 3] > 0

    def neigh(arr, dy, dx):
        o = np.zeros_like(arr)
        ys = slice(max(0, dy), H + min(0, dy))
        xs = slice(max(0, dx), W + min(0, dx))
        yt = slice(max(0, -dy), H + min(0, -dy))
        xt = slice(max(0, -dx), W + min(0, -dx))
        o[yt, xt] = arr[ys, xs]
        return o

    for _ in range(passes):
        keys = (a[..., 0].astype(np.int32) << 16) | \
               (a[..., 1].astype(np.int32) << 8) | a[..., 2].astype(np.int32)
        offs = [(dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]
        nbs = np.stack([neigh(keys, dy, dx) for dy, dx in offs])
        nbop = np.stack([neigh(op.view(np.uint8), dy, dx) > 0 for dy, dx in offs])
        changed = 0
        for y in range(H):
            for x in range(W):
                if not op[y, x]:
                    continue
                ks = nbs[:, y, x][nbop[:, y, x]]
                if len(ks) == 0:
                    continue
                vals, cnts = np.unique(ks, return_counts=True)
                best = vals[np.argmax(cnts)]
                if best != keys[y, x] and (cnts.max() >= 7
                        or (cnts.max() >= 5 and keys[y, x] not in ks)):
                    a[y, x, :3] = [(best >> 16) & 255, (best >> 8) & 255,
                                   best & 255]
                    changed += 1
        if changed == 0:
            break
    return a


def band_flatten(a: np.ndarray, mask: np.ndarray, win_min: float,
                 passes: int = 2) -> np.ndarray:
    """Mode-filter inside `mask` (5x5 window, mostly-mask pixels)."""
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
                if win.mean() < win_min:
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


# ---------------------------------------------------------------- eyes

def eye_pixels(a: np.ndarray) -> np.ndarray:
    """Mask of the King's red eyes (identity — never dyed): tiny
    high-saturation red clusters ON THE EYE LINE. Flat clusters
    only (bbox height <= 3) with centroid at 22-42% of the figure
    height — the hair-tie bead strand hangs higher and longer,
    and it is a tassel accent that MUST take the team colour."""
    H, W = a.shape[:2]
    h, s, v = hsv_maps(a)
    op = a[..., 3] > 0
    cand = op & ((h < 0.05) | (h > 0.95)) & (s > 0.55) & (v > 0.35)
    cand[int(H * 0.42):, :] = False
    seen = np.zeros_like(cand)
    keep = np.zeros_like(cand)
    for sy in range(cand.shape[0]):
        for sx in range(cand.shape[1]):
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
                        if 0 <= ny < cand.shape[0] and 0 <= nx < cand.shape[1] \
                                and cand[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            dq.append((ny, nx))
            if len(comp) <= 6:
                ys = [p[0] for p in comp]
                cy = sum(ys) / len(ys)
                if max(ys) - min(ys) <= 2 and 0.22 * H <= cy <= 0.42 * H:
                    for y, x in comp:
                        keep[y, x] = True
    return keep


# ---------------------------------------------------------------- main

def main() -> None:
    sheet = np.asarray(Image.open(SHEET).convert("RGB")).astype(np.int32)
    H, W = sheet.shape[:2]
    centres = figure_centres(sheet)
    cuts = [0] + [(centres[i] + centres[i + 1]) // 2 for i in range(7)] + [W]
    raw = {}
    for i, d in enumerate(DIRS):
        crop = sheet[:, cuts[i]:cuts[i + 1]]
        raw[d] = bbox_trim(key_crop(crop))
        print("slice", d, "cols", cuts[i], cuts[i + 1], "bbox", raw[d].shape)
    # One global scale from the S pose.
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
        print("scaled", d, small[d].shape)
    # Shared palette across all poses.
    rng = np.random.default_rng(SEED)
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
    for d in DIRS:
        a = small[d].copy()
        op = a[..., 3] > 0
        P = a[op][:, :3].astype(np.float64)
        lab = ((P[:, None, :] - C[None]) ** 2).sum(-1).argmin(1)
        rgb = np.zeros_like(a[..., :3])
        rgb[op] = C[lab]
        a[..., :3] = rgb
        a = consensus(a)
        h, s, v = hsv_maps(a)
        op = a[..., 3] > 0
        red_fam = op & ((h < 0.055) | (h > 0.945)) & (s > 0.30) & (v > 0.18)
        a = band_flatten(a, red_fam, 0.8)
        h, s, v = hsv_maps(a)
        fur = (a[..., 3] > 0) & (s < 0.12) & (v > 0.78)
        a = band_flatten(a, fur, 0.85, passes=1)
        sprites[d] = Image.fromarray(a.astype(np.uint8), "RGBA")
        print("crisp", d, sprites[d].size,
              "colours", len(np.unique(a[a[..., 3] > 0][:, :3], axis=0)))
    # Save slot 0 + recoloured slots (eyes protected on faced poses).
    eyes = {}
    for d in DIRS:
        if d in FACED:
            eyes[d] = eye_pixels(np.asarray(sprites[d]).astype(np.int32))
            print("eyes", d, int(eyes[d].sum()), "px protected")
        sprites[d].save(os.path.join(GODOT, "assets",
                                     "king_vo_hiep_%s.png" % d))
    for slot, (dirname, hue, sat_base, val_mult) in sorted(SLOTS.items()):
        outdir = os.path.join(GODOT, "assets", dirname)
        for d in DIRS:
            rc = recolor(sprites[d].copy(), hue, sat_base, val_mult)
            if d in eyes and eyes[d].any():
                ra = np.asarray(rc).copy()
                sa = np.asarray(sprites[d])
                ra[eyes[d]] = sa[eyes[d]]
                rc = Image.fromarray(ra, "RGBA")
            rc.save(os.path.join(outdir, "king_vo_hiep_%s.png" % d))
        print("slot", slot, "->", outdir)


if __name__ == "__main__":
    main()
