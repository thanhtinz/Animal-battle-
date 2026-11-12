#!/usr/bin/env python3
"""Empire Age 16a — Stage A assets for the 8 Western Medieval heroes
(knight / berserker / archer / mage / paladin / dragoon / assassin /
ranger), replacing the roster in a later stage (see
NHAN-VAT-TAY-TRUNG-CO.md). This stage is ADDITIVE: it only writes
the new heroes' sprites + avatars.

Pipeline identical to 14c (tools/build_hero_assets2.py — its
helpers are imported, not forked): turnaround sheet on white ->
border keying -> 5 figures -> colour grade -> big-head warp ->
premultiplied downscale to 92 px -> crisp_snap (binary alpha,
52 colours). Portraits are SLICED from the owner's sheet (his art
is the approval — never redrawn): assets/avatars/avatar_sq_<id>.png
+ the Collection framed king_avatar_<id>.png using 14c's frame
template lifted from the shipped avatars.

Run from the godot/ directory:  python3 tools/build_hero_assets3.py
"""
import glob
import importlib.util
import os
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
EA = os.path.join(ROOT, "..")
ASSETS = os.path.join(ROOT, "assets")
AVATARS = os.path.join(ASSETS, "avatars")
SHEETS = os.path.join(EA, "art_candidates", "turnaround")
CAND = os.path.join(EA, "art_candidates")

_spec = importlib.util.spec_from_file_location(
    "a2", os.path.join(ROOT, "tools", "build_hero_assets2.py"))
a2 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(a2)

HEROES = ["knight", "berserker", "archer", "mage",
          "paladin", "dragoon", "assassin", "ranger"]
DIRS5 = a2.DIRS5
MIRROR = a2.MIRROR
SPRITE_H = a2.SPRITE_H

# Colour grade (same recipe as 14c-fix3): turnaround generations
# lean pale; push saturation back into the roster band (originals
# measure 0.39–0.43 mean HSV saturation), extra push in each hero's
# signature hue band.
a2.GRADE = {
    # hero: (sat x, value gamma, hue band (lo, hi), band sat x)
    "knight":    (1.18, 1.10, (0.55, 0.68), 1.15),   # blue cape
    "berserker": (1.15, 1.10, (0.93, 1.07), 1.10),   # red hair (wraps)
    "archer":    (1.30, 1.15, (0.24, 0.45), 1.20),   # green
    "mage":      (1.22, 1.12, (0.70, 0.88), 1.18),   # purple
    "paladin":   (1.08, 1.08, (0.06, 0.16), 1.10),   # gold
    "dragoon":   (1.22, 1.12, (0.56, 0.70), 1.20),   # deep blue
    "assassin":  (1.12, 1.06, (0.93, 1.07), 1.05),   # scarf red accent
    "ranger":    (1.18, 1.12, (0.00, 0.09), 1.12),   # red hair
}
# Jaw fraction of ink height measured on the generated sheets
# (narrowest row in the 0.34–0.58 band, same rule as the rig's
# neck measure); the warp normalises everyone to HEAD_TARGET.
a2.HEAD_NOW = {
    # Jaw (chin bottom) fraction of figure height, read by eye on a
    # 10%-grid overlay of each sheet's front figure (16a session).
    "knight": 0.36, "berserker": 0.42, "archer": 0.335,
    "mage": 0.36, "paladin": 0.36, "dragoon": 0.335,
    "assassin": 0.355, "ranger": 0.40,
}


# ======================================================================
# Source-art cleaners (16a fix pass, defects spotted on the QA
# strip). All run per figure at full resolution, before grade/warp.
# ======================================================================
def _components(mask: np.ndarray) -> list:
    ys, xs = np.where(mask)
    seen = set(zip(ys.tolist(), xs.tolist()))
    comps = []
    while seen:
        seed = seen.pop()
        q = deque([seed])
        pts = [seed]
        while q:
            cy, cx = q.popleft()
            for ny, nx in ((cy, cx + 1), (cy, cx - 1), (cy + 1, cx), (cy - 1, cx)):
                if (ny, nx) in seen:
                    seen.discard((ny, nx))
                    q.append((ny, nx))
                    pts.append((ny, nx))
        comps.append(pts)
    return comps


def _runs(row: np.ndarray) -> list:
    runs = []
    x = 0
    while x < len(row):
        if row[x]:
            x0 = x
            while x < len(row) and row[x]:
                x += 1
            runs.append((x0, x - 1))
        else:
            x += 1
    return runs


def _cleared(fig: Image.Image, clear: np.ndarray) -> Image.Image:
    if not clear.any():
        return fig
    arr = np.asarray(fig).copy()
    arr[clear, 3] = 0
    return Image.fromarray(arr, "RGBA")


def clean_foot_shadow(fig: Image.Image) -> Image.Image:
    """Remove the generated ground-shadow ellipse hanging below the
    feet (the assassin's white blob). Per column, pale pixels BELOW
    the lowest non-pale opaque pixel are shadow; costume/skin/weapon
    pixels sit above that floor and are untouchable by construction.
    Pale = near-neutral light grey; steel blades are bluer and set
    the floor themselves."""
    a = np.asarray(fig)
    alpha = a[:, :, 3] > 40
    rgb = a[:, :, :3].astype(np.int32)
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    pale = alpha & (mn >= 150) & ((mx - mn) <= 25) \
        & ((rgb[:, :, 2] - rgb[:, :, 0]) <= 8)
    nonpale = alpha & ~pale
    h, w = alpha.shape
    clear = np.zeros_like(alpha)
    rows = np.arange(h)
    for x in range(w):
        col_np = np.where(nonpale[:, x])[0]
        col_p = pale[:, x]
        if len(col_np):
            clear[:, x] = col_p & (rows > col_np.max())
        else:
            clear[:, x] = col_p & (rows >= int(h * 0.90))
    return _cleared(fig, clear)


def clean_enclosed_white(fig: Image.Image) -> Image.Image:
    """Remove pockets of the sheet's flat white background that are
    fully enclosed by the figure (inside the archer's bow curve) —
    border keying cannot reach them. Enclosed = the component's
    dilation touches no transparent pixel; flat white = the RAW
    sheet white (min channel >= 250, spread <= 6). Shaded costume
    whites stay below that: the first pass at >= 242 ate the flat
    highlight plateaus inside the mage's silver hair, so the gate
    sits at the sheet's own purity, not at "bright"."""
    a = np.asarray(fig)
    alpha = a[:, :, 3] > 40
    rgb = a[:, :, :3].astype(np.int32)
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    white = alpha & (mn >= 250) & ((mx - mn) <= 6)
    h, w = alpha.shape
    clear = np.zeros_like(alpha)
    for pts in _components(white):
        if len(pts) < 250:
            continue
        if sum(p[0] for p in pts) / len(pts) < h * 0.30:
            continue
        comp = np.zeros_like(alpha)
        for py, px in pts:
            comp[py, px] = True
        dil = comp.copy()
        dil[1:, :] |= comp[:-1, :]
        dil[:-1, :] |= comp[1:, :]
        dil[:, 1:] |= comp[:, :-1]
        dil[:, :-1] |= comp[:, 1:]
        if (dil & ~comp & ~alpha).any():
            continue  # touches the silhouette edge: costume, keep
        clear |= comp
    return _cleared(fig, clear)


def clean_mage_back_staff(fig: Image.Image) -> Image.Image:
    """RETIRED — the per-row robe-contour version cut bands through
    the figure whenever the robe's violet run fragmented. Back-view
    staff removal now happens at sprite level (clean_staff_sprite).
    Kept unused for reference."""
    a = np.asarray(fig)
    alpha = a[:, :, 3] > 40
    rgb = a[:, :, :3].astype(np.int32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    violet = alpha & (b > r + 20) & (g < 110)
    h, w = alpha.shape
    clear = np.zeros_like(alpha)
    pad = max(2, int(w * 0.012))
    for y in range(int(h * 0.85)):
        row = alpha[y]
        if not row.any():
            continue
        main = max(_runs(row), key=lambda rn: rn[1] - rn[0])
        # The robe's violet run inside the main run — the LONGEST
        # violet run, not the rightmost violet pixel: at full res
        # the orb fuses into the same alpha run as the hood, and
        # its own short violet run must not extend the contour.
        vrow = violet[y].copy()
        vrow[:main[0]] = False
        vrow[main[1] + 1:] = False
        vruns = _runs(vrow)
        robe_right = max(vruns, key=lambda rn: rn[1] - rn[0])[1] \
            if vruns else main[1]
        clear[y, robe_right + pad:] = alpha[y, robe_right + pad:]
    return _cleared(fig, clear)


def clean_archer_back_bow(fig: Image.Image) -> Image.Image:
    """Archer back view (n): her bow rides at her left, outside the
    body — drop its separated runs, plus the fused segment by
    colour (bow wood / flat string white) in the far-left zone.
    The quiver (right side, body equipment) is untouched."""
    a = np.asarray(fig)
    alpha = a[:, :, 3] > 40
    rgb = a[:, :, :3].astype(np.int32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    h, w = alpha.shape
    clear = np.zeros_like(alpha)
    gap = max(2, int(w * 0.01))
    for y in range(int(h * 0.20), int(h * 0.78)):
        row = alpha[y]
        if not row.any():
            continue
        main = max(_runs(row), key=lambda rn: rn[1] - rn[0])
        for x0, x1 in _runs(row):
            if x1 < main[0] - gap:
                clear[y, x0:x1 + 1] = True
    brown = (r >= 110) & (r <= 180) & (g >= 75) & (g <= 130) & (b <= 90)
    fwhite = (mn >= 242) & ((mx - mn) <= 14)  # shaded rim of the pocket
    zone = np.zeros_like(alpha)
    zone[int(h * 0.40):int(h * 0.76), :int(w * 0.34)] = True
    clear |= zone & alpha & (brown | fwhite)
    return _cleared(fig, clear)


def clean_figure(hero: str, d: str, fig: Image.Image) -> Image.Image:
    fig = clean_foot_shadow(fig)
    fig = clean_enclosed_white(fig)
    if hero == "archer" and d == "n":
        fig = clean_archer_back_bow(fig)
    return fig


def _staff_palette(a: np.ndarray) -> np.ndarray:
    alpha = a[:, :, 3] > 40
    rgb = a[:, :, :3].astype(np.int32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    gold = (r > 140) & (g > 90) & (b < 100)
    violet = (b > 130) & (b > r + 10) & (r > 90)
    return alpha & (gold | violet)


def clean_staff_sprite(spr: Image.Image) -> Image.Image:
    """Mage back views (ne/n), sprite level: grow the staff region
    from the orb's core — the orb's bright magenta-violet (r > 150,
    b > 170) exists nowhere on her robe/hood (deep violet, r ~103),
    so it is a safe seed. Growth spreads over the staff's own
    palette (gold shaft/prongs, bright orb violet, pale sparkles)
    with 8-connectivity; robe violet is not in the growth palette,
    so growth stops at the robe even where the shaft fuses to it.
    (Component tests failed here: a gold+violet union mask merges
    the staff into the robe mass wherever they touch.) Front views
    keep the staff — it is her rig weapon there."""
    a = np.asarray(spr)
    alpha = a[:, :, 3] > 40
    rgb = a[:, :, :3].astype(np.int32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mn = rgb.min(axis=2)
    ys, xs = np.where(alpha)
    cx = float(xs.mean()) if len(xs) else spr.width / 2.0
    seed = alpha & (r > 150) & (b > 170) & (g >= 80) & (g <= 200)
    seeds = [pts for pts in _components(seed)
             if sum(p[1] for p in pts) / len(pts) > cx
             and sum(p[0] for p in pts) / len(pts) < spr.height * 0.38]
    if not seeds:
        return spr
    grow = alpha & (((r > 140) & (g > 90) & (b < 100))
                    | ((r > 150) & (b > 150))
                    | ((mn > 195) & (b > r)))
    seen = np.zeros(alpha.shape, dtype=bool)
    q = deque()
    for pts in seeds:
        for py, px in pts:
            if grow[py, px] and not seen[py, px]:
                seen[py, px] = True
                q.append((py, px))
    while q:
        cy, cx2 = q.popleft()
        for ny in (cy - 1, cy, cy + 1):
            for nx in (cx2 - 1, cx2, cx2 + 1):
                if 0 <= ny < spr.height and 0 <= nx < spr.width \
                        and grow[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
    return _cleared(spr, seen)


def clean_back_side_weapon(spr: Image.Image, min_size: int,
                           y_frac: float) -> Image.Image:
    """Knight/Paladin back views (ne/n), sprite level: clear gold
    pixels inside a fixed zone at the lower weapon-side hip, where
    the sword pommel / maul head hangs. (Component gates failed:
    the maul's gold is continuous with the armour's trim network.)
    The zone starts right of centre + 8 and below y_frac of the
    height: shields (left), pauldrons (high) and the belt (centre)
    are outside it; a few trim pixels of the right tasset inside
    the zone are the accepted cost."""
    a = np.asarray(spr)
    alpha = a[:, :, 3] > 40
    rgb = a[:, :, :3].astype(np.int32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    gold = alpha & (r > 140) & (g > 90) & (b < 100)
    ys, xs = np.where(alpha)
    cx = float(xs.mean()) if len(xs) else spr.width / 2.0
    clear = np.zeros(alpha.shape, dtype=bool)
    clear[int(spr.height * y_frac):, int(cx) + 8:] = \
        gold[int(spr.height * y_frac):, int(cx) + 8:]
    return _cleared(spr, clear)


def clean_sprite(hero: str, d: str, spr: Image.Image) -> Image.Image:
    """Sprite-level (post-crisp) back-view weapon removal — the
    roster rule: no hand weapon renders in ne/n/nw."""
    if hero == "mage" and d in ("ne", "n"):
        spr = clean_staff_sprite(spr)
    if hero == "paladin" and d in ("ne", "n"):
        spr = clean_back_side_weapon(spr, 0, 0.64)
    if hero == "knight" and d in ("ne", "n"):
        spr = clean_back_side_weapon(spr, 0, 0.60)
    return spr


def make_sprites(hero: str) -> None:
    path = glob.glob(os.path.join(
        SHEETS, f"media-generation-medieval-{hero}-sheet-*.webp"))[0]
    sheet = a2.key_out_white(Image.open(path))
    figs = a2.split_sheet(sheet)
    authored = {}
    for d, fig in zip(DIRS5, figs):
        fig = clean_figure(hero, d, fig)
        fig = a2.grade_colours(fig, hero)
        fig = a2.warp_rows(fig, a2.HEAD_NOW[hero] * fig.height,
                           a2.HEAD_TARGET * fig.height)
        scale = SPRITE_H / fig.height
        spr = a2.premul_resize(fig, (max(1, round(fig.width * scale)),
                                     SPRITE_H))
        spr = a2.crisp_snap(spr)
        spr = clean_sprite(hero, d, spr)
        authored[d] = spr
        spr.save(os.path.join(ASSETS, f"king_{hero}_{d}.png"))
    for src, dst in MIRROR.items():
        authored[src].transpose(Image.FLIP_LEFT_RIGHT).save(
            os.path.join(ASSETS, f"king_{hero}_{dst}.png"))
    print(f"{hero}: sprites " +
          ", ".join(f"{d} {authored[d].width}x{authored[d].height}"
                    for d in DIRS5))


# Avatar crops (fractions of the sheet-portrait source): the source
# already frames head + shoulders inside its gold border; crop just
# inside the border so the face fills the tile.
SQ_CROP = (0.05, 0.03, 0.95, 0.97)


def make_avatars(hero: str, tpl: Image.Image, inner: Image.Image) -> None:
    src = Image.open(os.path.join(
        CAND, f"medieval_{hero}_portrait_src.png")).convert("RGB")
    w, h = src.size
    x0, y0, x1, y1 = SQ_CROP
    bust = src.crop((int(w * x0), int(h * y0), int(w * x1), int(h * y1)))
    bust = bust.resize((320, 320), Image.LANCZOS)
    bust.save(os.path.join(AVATARS, f"avatar_sq_{hero}.png"))
    fbust = bust.convert("RGBA")
    fbust.putalpha(inner)
    fbust.alpha_composite(tpl)
    fbust.save(os.path.join(AVATARS, f"king_avatar_{hero}.png"))
    print(f"{hero}: avatars done")


def main() -> None:
    tpl, inner = a2.frame_template()
    for hero in HEROES:
        make_sprites(hero)
        make_avatars(hero, tpl, inner)


if __name__ == "__main__":
    main()
