#!/usr/bin/env python3
"""Crisp rebuild of the King sprite (Tín, 2026-11-09: "Vô game mờ
quá" — in-game the King read soft/blurry next to the soldiers).

ROOT CAUSE: the soldiers are chunky low-res pixel art, so their
detail survives the game's 0.49 LINEAR_WITH_MIPMAPS draw. The King
was a smooth 1539x1402 painting downscaled ~15x (king_western_build
.py) — 3504 unique colours of continuous gradient, which averages
into mush at display size. No downscale filter fixes that; the
sprite itself must be true low-res pixel art.

PIPELINE (run AFTER king_western_build.py; input = the smooth
assets/king.png it produces):
  1. Binarise alpha (>=128) — pixel-art silhouette, no AA fringe.
  2. K-means palette quantise (K=44, deterministic seed) — flat
     colour clusters, soldier-like colour discipline.
  3. Consensus cleanup: a pixel recolours only when >=7 of 8
     neighbours agree, or it disagrees with all of them — kills
     leftover dither speckle without eroding 2px lines (sword).
  4. Cape flatten: 5x5 mode filter restricted to the strict red
     hue band (h<0.055 or h>0.945, s>0.30) — the HSV definition
     matters: a channel-difference test eats the GOLD lion (it is
     red-dominant by channels); the hue band does not.
  5. Warm speck removal: isolated warm clusters of <=4 px fully
     surrounded by red-family pixels repaint to the local red.
  6. Regenerate the 3 team palettes from the crisp sprite
     (tools/recolor_teams.py recolor(): cape/tabard/shield dye;
     crown, ermine, blade constant).

Result metrics (measured): unique colours 3504 -> 44; share of
pixels identical to >=6 of 8 neighbours 2.2% -> 18.2%; soft
micro-gradient ("mush band") interior share 9.3% -> 4.6%.
Simplifications forced by 99x90 and accepted: the heraldic lions
are bold gold silhouettes (no internal detail), crown gems are
1-2 px, ermine speckles are chunky dots.
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
from recolor_teams import SLOTS, recolor  # noqa: E402

K = 44
SEED = 7


def hsv_maps(a):
    rgb = a[..., :3].astype(np.float32) / 255.0
    mx = rgb.max(-1); mn = rgb.min(-1); d = mx - mn
    h = np.zeros_like(mx)
    r_, g_, b_ = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    m = d > 1e-6
    h[m & (mx == r_)] = ((g_ - b_) / np.maximum(d, 1e-9))[m & (mx == r_)] % 6
    h[m & (mx == g_)] = ((b_ - r_) / np.maximum(d, 1e-9) + 2)[m & (mx == g_)]
    h[m & (mx == b_)] = ((r_ - g_) / np.maximum(d, 1e-9) + 4)[m & (mx == b_)]
    h /= 6.0
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def main():
    src = Image.open(os.path.join(GODOT, "assets", "king.png")).convert("RGBA")
    a = np.asarray(src).astype(np.float32)
    H, W = a.shape[:2]
    opaque = a[..., 3] >= 128
    rgb = a[..., :3].copy()

    # 1+2: k-means palette on opaque pixels
    rng = np.random.default_rng(SEED)
    pts = rgb[opaque].astype(np.float64)
    centers = [pts[rng.integers(len(pts))]]
    for _ in range(K - 1):
        C = np.stack(centers)
        d2 = ((pts[:, None, :] - C[None]) ** 2).sum(-1).min(1)
        centers.append(pts[rng.choice(len(pts), p=d2 / d2.sum())])
    C = np.stack(centers)
    lab = None
    for _ in range(60):
        d2 = ((pts[:, None, :] - C[None]) ** 2).sum(-1)
        lab = d2.argmin(1)
        newC = C.copy()
        for k in range(K):
            m = lab == k
            if m.any():
                newC[k] = pts[m].mean(0)
        if np.abs(newC - C).max() < 0.05:
            C = newC
            break
        C = newC
    out = np.zeros((H, W, 4), np.uint8)
    img_rgb = np.zeros((H, W, 3), np.float64)
    img_rgb[opaque] = C[lab]
    out[..., :3] = img_rgb.astype(np.uint8)
    out[..., 3] = np.where(opaque, 255, 0).astype(np.uint8)
    a = out.copy()

    # 3: consensus cleanup (<=4 passes)
    op = a[..., 3] > 0
    def neigh(arr, dy, dx):
        o = np.zeros_like(arr)
        ys = slice(max(0, dy), H + min(0, dy)); xs = slice(max(0, dx), W + min(0, dx))
        yt = slice(max(0, -dy), H + min(0, -dy)); xt = slice(max(0, -dx), W + min(0, -dx))
        o[yt, xt] = arr[ys, xs]
        return o
    for _ in range(4):
        keys = (a[..., 0].astype(np.int32) << 16) | (a[..., 1].astype(np.int32) << 8) | a[..., 2].astype(np.int32)
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
                if best != keys[y, x] and (cnts.max() >= 7 or (cnts.max() >= 5 and keys[y, x] not in ks)):
                    a[y, x, :3] = [(best >> 16) & 255, (best >> 8) & 255, best & 255]
                    changed += 1
        if changed == 0:
            break

    # 4: cape flatten inside the strict red hue band
    h, s, mx = hsv_maps(a)
    red_fam = op & ((h < 0.055) | (h > 0.945)) & (s > 0.30) & (mx > 0.18)
    for _ in range(3):
        cur = a[..., :3].astype(np.int32)
        key = (cur[..., 0] << 16) | (cur[..., 1] << 8) | cur[..., 2]
        pad = np.pad(red_fam, 2); padk = np.pad(key, 2)
        changed = 0
        for y in range(H):
            for x in range(W):
                if not red_fam[y, x]:
                    continue
                win = pad[y:y + 5, x:x + 5]
                if win.mean() < 0.8:
                    continue
                ks = padk[y:y + 5, x:x + 5][win]
                vals, cnts = np.unique(ks, return_counts=True)
                best = vals[np.argmax(cnts)]
                if best != key[y, x]:
                    a[y, x, :3] = [(best >> 16) & 255, (best >> 8) & 255, best & 255]
                    changed += 1
        if changed == 0:
            break

    # 5: isolated warm specks inside red territory -> local red
    lum = 0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]
    def ncount(mask):
        p = np.pad(mask, 1)
        return sum(p[1 + dy:1 + dy + H, 1 + dx:1 + dx + W]
                   for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
    warm = op & ~red_fam & (lum > 56) & (s > 0.18) & (((h >= 0.0) & (h < 0.22)) | (h > 0.93))
    cand = warm & (ncount(red_fam) >= 6)
    seen = np.zeros_like(cand)
    for sy, sx in zip(*np.where(cand)):
        if seen[sy, sx]:
            continue
        q = deque([(sy, sx)]); seen[sy, sx] = True; comp = []
        while q:
            y, x = q.popleft(); comp.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < H and 0 <= nx < W and cand[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True; q.append((ny, nx))
        if len(comp) <= 4:
            around = []
            for y, x in comp:
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < H and 0 <= nx < W and red_fam[ny, nx]:
                            around.append(tuple(a[ny, nx, :3]))
            if around:
                vals, cnts = np.unique(np.array(around), axis=0, return_counts=True)
                col = vals[np.argmax(cnts)]
                for y, x in comp:
                    a[y, x, :3] = col

    sprite = Image.fromarray(a, "RGBA")
    sprite.save(os.path.join(GODOT, "assets", "king.png"))
    print("crisp king:", sprite.size)
    for slot, (dirname, hue, sat_base, val_mult) in sorted(SLOTS.items()):
        dst = os.path.join(GODOT, "assets", dirname, "king.png")
        recolor(sprite.copy(), hue, sat_base, val_mult).save(dst)
        print("palette slot", slot, "->", dst)


if __name__ == "__main__":
    main()
