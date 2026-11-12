#!/usr/bin/env python3
"""Empire Age 15g — land-transport sprite sheets (trade Cart +
troop Wagon) sliced from the OWNER'S OWN covered-wagon sheet.

History: the first two cuts were drawn in this file with PIL
primitives (functional art, then a scale pass after the owner's
"Xe gì còn nhỏ hơn người"). On 2026-11-11 the owner replaced the
art direction entirely by sending his own sprite sheet (brown
draught horse + wooden covered wagon, cream canvas canopy with a
fleur-de-lis, barrels, lantern, big spoked wheels: front / back /
both side views + 8-frame walk rows for all four directions).
This builder now SLICES that sheet — the vehicle is never redrawn.

Source: assets-src/owner_wagon_sheet.jpg (owner's upload; the
JPG's checkerboard "transparency" is BAKED INTO the pixels).

Pipeline:
  1. Keying — the two checkerboard tones sit at ~223 and ~252 and
     JPG smears them together, so colour-distance keying alone
     fails. Instead: flood-fill from the image border through
     near-neutral pixels (sat <= 20, min channel >= 165). That
     swallows both checker tones AND the baked contact shadow
     (the engine draws its own soft shadow — see
     Unit.get_shadow_tex; baked shadows are cut by house rule),
     while the wagon's saturated browns/creams stop the flood.
  2. Canopy tint — per SLOT. The cream canvas (plus the darker
     fleur-de-lis woven into it) is re-hued to the slot colour at
     moderate saturation, value preserved, so ownership reads at
     a glance while the owner's shading survives. Everything
     else stays byte-faithful. All 8 slots are generated HERE;
     tools/recolor_teams.py no longer owns cart/wagon (its red-
     band rotation cannot tint a cream canopy).
  1b. Residue cleanup (per cropped frame) — the flood cannot
     reach page pockets walled off by 1-3px of JPG smear (seen
     through the wheel spokes, between the horse's legs, under
     the bed), and the baked contact shadow survives the old
     trim (its tone ~(126,134,148) classified as "material").
     clean_residue deletes bright-neutral components per frame
     except the horse's protected head markings (front blaze /
     chin, profile muzzle — measured positions + warm-ringed),
     and trim_ground_shadow now classes the shadow by its cool
     tone. The cream canopy never enters the candidate set
     (measured: its highlights stay sat>34 or mn<180).
  3. Defringe — same philosophy as tools/defringe_characters.py:
     rim pixels are mostly page colour pre-blended over the true
     colour; estimate coverage against the nearest deep-interior
     colour, restore RGB and scale alpha by coverage. Then bleed
     opaque colours a few px into the transparent margin so the
     LINEAR_WITH_MIPMAPS sampling never pulls bare black/white.
     Frame scaling is PREMULTIPLIED (resize RGB*A and A, then
     un-premultiply) so the bright checker RGB still sitting in
     transparent pixels cannot bleed into silhouette edges.
  4. Sheet assembly — the roster layout, unchanged contract:
     rows idle / walk / die / hurt, frames grouped by direction
     [down, left, right, up]; idle/die/hurt take 1 frame per dir,
     walk takes 2 (the two most opposed phases of the owner's
     8-frame rows). die = idle frames + the engine's death fade;
     hurt = idle frames + the engine's white hurt flash (13o) —
     the owner's sheet has no hurt/death poses. One uniform scale
     per vehicle, chosen so the SIDE length matches the shipped
     ruler (Unit.CONTENT_SIZE, display scale 0.40): cart side =
     225 sheet px -> 90 world px, wagon side = 277 -> 111 px.

Writes assets/{cart,wagon}.png + *_frames.json (same geometry as
before: cart cell 240x150 baseline 146, wagon 300x180 baseline
166) for slot 0, and the tinted variants into assets/enemy/
(slot 1) and assets/team2..7/ (slots 2-7). Prints the measured
CONTENT_SIZE values Unit must carry.

Run: python3 tools/build_transport_assets.py
"""
import colorsys
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.join(HERE, "..")
ASSETS = os.path.join(GODOT, "assets")
SRC_CANDIDATES = [
    os.path.join(GODOT, "..", "assets-src", "owner_wagon_sheet.jpg"),
    os.path.expanduser("~/workspace/user/files/"
                       "64A737B1-2945-411F-82B4-7ABE47DDBBE3-photo-"
                       "85CFE0FB-5399-4360-ADB9-41090B747D52.jpg"),
]

# Slot -> (output dir under assets/, UI colour from TeamColors)
SLOTS = {
    0: ("", (0.90, 0.26, 0.20)),        # Đỏ
    1: ("enemy", (0.35, 0.58, 1.00)),   # Xanh dương
    2: ("team2", (0.32, 0.82, 0.36)),   # Xanh lá
    3: ("team3", (1.00, 0.76, 0.20)),   # Vàng
    4: ("team4", (0.66, 0.40, 0.95)),   # Tím
    5: ("team5", (1.00, 0.55, 0.15)),   # Cam
    6: ("team6", (0.15, 0.85, 0.75)),   # Xanh ngọc
    7: ("team7", (1.00, 0.45, 0.75)),   # Hồng
}

# Source-sheet grid, measured from the baked image (1290x860).
BIG_ROW = (11, 235)
BIG_COLS = [(46, 213), (255, 433), (474, 857), (905, 1289)]
# big pose order on the sheet: front(down), back(up),
# side horse-left (left), side horse-right (right)
WALK_ROWS = {
    "right": (278, 361),
    "left": (414, 493),
    "down": (530, 664),
    "up": (707, 835),
}
DIRS = ["down", "left", "right", "up"]

# vehicle -> (cell_w, cell_h, baseline, target side length sheet px)
VEHICLES = {
    "cart": (240, 150, 146, 225),
    "wagon": (300, 180, 166, 277),
}
ANIMATIONS = {
    "idle": {"row": 0, "count": 4, "per_dir": 1},
    "walk": {"row": 1, "count": 8, "per_dir": 2},
    "die": {"row": 2, "count": 4, "per_dir": 1},
    "hurt": {"row": 3, "count": 4, "per_dir": 1},
}


def load_source() -> Image.Image:
    for p in SRC_CANDIDATES:
        if os.path.exists(p):
            print("source:", p)
            return Image.open(p).convert("RGB")
    raise SystemExit("owner wagon sheet not found in: %s" % SRC_CANDIDATES)


def frame_cells(alpha: np.ndarray):
    """All sheet cells (big poses + walk rows) by opaque projection."""
    h, w = alpha.shape
    rows = alpha.sum(1) > 3
    bands, inb = [], False
    for y in range(h):
        if rows[y] and not inb:
            y0, inb = y, True
        elif not rows[y] and inb:
            bands.append((y0, y - 1))
            inb = False
    if inb:
        bands.append((y0, h - 1))
    cells = []
    for (y0, y1) in bands:
        if y1 - y0 < 5:
            continue
        cols = alpha[y0:y1 + 1].sum(0) > 3
        inb = False
        for x in range(w):
            if cols[x] and not inb:
                x0, inb = x, True
            elif not cols[x] and inb:
                cells.append((x0, x - 1, y0, y1))
                inb = False
        if inb:
            cells.append((x0, w - 1, y0, y1))
    return cells


def key_out(rgb: np.ndarray) -> np.ndarray:
    """Alpha (0/255): border flood-fill + enclosed-pocket removal.

    The flood swallows the checkerboard and the reachable shadow.
    Enclosed pockets of page colour (under the bed, between the
    wheels, the gap between horse and lamp post) are walled off by
    saturated paint, so they are removed as components instead —
    measured on this sheet, real near-neutral details (the horse's
    face blaze ~200px, its white socks ~130px) are far smaller
    than the pockets (>=600px) and never touch their frame's
    ground line, which gives two safe rules:
      (a) a bright-neutral component of >=600px at >=88% very
          light pixels is page/shadow;
      (b) a bright-neutral component touching its own frame's
          lowest opaque row is ground shadow / see-through floor.
    """
    mx = rgb.max(2)
    mn = rgb.min(2)
    passable = (mx - mn) <= 20
    passable &= mn >= 165
    lab, _ = ndimage.label(passable)
    border = set(np.unique(np.concatenate(
        [lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    alpha = np.where(bg, 0, 255).astype(np.uint8)
    print("flood keyed out %.1f%% of the sheet" % (100.0 * bg.mean()))

    cand = (alpha > 0) & ((mx - mn) <= 24) & (mn >= 150)
    lab, n = ndimage.label(cand)
    cells = frame_cells(alpha)
    ground_rows = []
    for (x0, x1, y0, y1) in cells:
        sub = alpha[y0:y1 + 1, x0:x1 + 1] > 0
        ys = np.where(sub.any(1))[0]
        if len(ys):
            ground_rows.append((x0, x1, y0 + ys.max()))
    removed = 0
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        ys, xs = sl
        comp = lab[sl] == i
        area = int(comp.sum())
        if area < 60:
            continue
        vals = mn[sl][comp]
        frac_hi = float((vals >= 195).mean())
        kill = area >= 600 and frac_hi >= 0.88
        if not kill and frac_hi >= 0.80:
            for (cx0, cx1, grow) in ground_rows:
                if xs.start >= cx0 - 2 and xs.stop - 1 <= cx1 + 2 \
                        and ys.stop - 1 == grow:
                    kill = True
                    break
        if kill:
            region = alpha[sl]
            region[comp] = 0
            alpha[sl] = region
            removed += area
    print("enclosed pockets removed: %d px" % removed)
    return alpha


def trim_ground_shadow(rgba: np.ndarray) -> np.ndarray:
    """Column-wise sweep removing the baked contact shadow.

    From each column's bottom, walk up at most 30px: skip
    transparent pixels, delete shadow-like ones, stop at the
    first real-material pixel. The baked shadow over the
    checkerboard is COOL grey-blue (median ~(126,134,148)) —
    the previous classes (delete sat<=26 & mn>=160; material =
    sat>40 | mn<150) classified that tone as material and the
    sweep stopped on it, shipping the whole band. Shadow-like
    is now: sat<=55, mn>=95, blue >= red-10. Real contacts stop
    the sweep: hooves/iron are dark (mn<90), wood/horse/cream
    are warm (red-blue>=14) or saturated. The canopy is >100px
    above the ground line in every frame, so the sweep can
    never reach it.
    """
    rgb = rgba[..., :3].astype(int)
    a = rgba[..., 3]
    r, b = rgb[..., 0], rgb[..., 2]
    mx = rgb.max(2)
    mn = rgb.min(2)
    sat = mx - mn
    cand = (sat <= 55) & (mn >= 95) & (b >= r - 10)
    real = ((r - b) >= 14) | (mn < 90) | (sat > 70)
    h = rgba.shape[0]
    for x in range(rgba.shape[1]):
        deleted = 0
        for y in range(h - 1, -1, -1):
            if deleted >= 30:
                break
            if a[y, x] == 0:
                continue
            if real[y, x]:
                break
            if cand[y, x]:
                a[y, x] = 0
                deleted += 1
    rgba[..., 3] = a
    return rgba


def clean_residue(rgba: np.ndarray, protect: str) -> np.ndarray:
    """Delete bright-neutral page pockets inside a cropped frame.

    The border flood cannot reach background seen through gaps
    in the vehicle (wheel spokes, between the horse's legs,
    under the bed, between canopy and lamp post): 1-3px of JPG
    smear walls it off. Those pockets are bright-neutral
    components (mn>=180, sat<=34); in the walk rows they
    fragment into 6-27px islands (verified by highlight
    renders: every island sits in a gap, never on the horse)
    and the walk upscale grows sub-10px specks back over the
    sheet-audit floor, so there is NO area floor: every
    unprotected candidate component is deleted. The ONLY
    legitimate pixels in
    that class are the horse's head markings — front blaze +
    chin (pose down / walk down, dead centre, warm-ringed) and
    the profile muzzle (side poses, small, at the horse's end).
    Everything else in the class is page and is deleted; the
    protected zones below are the measured positions of those
    markings (fractions of the frame, warm-ring = share of the
    component's opaque ring that is warm, red-blue>12). The
    cream canopy never enters the class (measured on every
    frame: its highlights stay sat>34 or mn<180), and neither
    do the horse's cream socks (warmer) or the lantern (mn<180).
    """
    arr = rgba.astype(int)
    r, b, a = arr[..., 0], arr[..., 2], arr[..., 3]
    mx = arr[..., :3].max(2)
    mn = arr[..., :3].min(2)
    sat = mx - mn
    cand = (a > 0) & (mn >= 180) & (sat <= 34)
    lab, _ = ndimage.label(cand)
    h, w = a.shape
    removed = 0
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        m = lab[sl] == i
        area = int(m.sum())
        ys, xs = sl
        fx0, fx1 = xs.start / float(w), (xs.stop - 1) / float(w)
        fy0, fy1 = ys.start / float(h), (ys.stop - 1) / float(h)
        dil = ndimage.binary_dilation(m)
        ring = dil & ~m
        ring_op = ring & (a[sl] > 0)
        warm = float(((r[sl] - b[sl]) > 12)[ring_op].mean()) \
            if ring_op.any() else 0.0
        keep = False
        if protect == "front":
            keep = fx0 >= 0.40 and fx1 <= 0.60 and fy0 >= 0.32 \
                and fy1 <= 0.60 and warm >= 0.55
        elif protect == "left":
            keep = area <= 85 and warm >= 0.50 and fx1 <= 0.17 \
                and fy0 >= 0.42 and fy1 <= 0.68
        elif protect == "right":
            keep = area <= 85 and warm >= 0.50 and fx0 >= 0.83 \
                and fy0 >= 0.42 and fy1 <= 0.68
        if not keep:
            region = rgba[sl]
            region[m] = 0
            rgba[sl] = region
            removed += area
    if removed:
        print("    residue pockets removed (%s): %d px"
              % (protect, removed))
    return rgba


def crop_frame(rgb, alpha, x0, x1, y0, y1, protect="none"):
    """Tight RGBA crop of the opaque content inside a sheet cell."""
    sub_a = alpha[y0:y1 + 1, x0:x1 + 1]
    ys, xs = np.where(sub_a > 0)
    if len(xs) == 0:
        raise SystemExit("empty frame at %s" % ((x0, x1, y0, y1),))
    bx0, bx1, by0, by1 = xs.min(), xs.max(), ys.min(), ys.max()
    rgba = np.dstack([rgb[y0:y1 + 1, x0:x1 + 1],
                      alpha[y0:y1 + 1, x0:x1 + 1]])
    rgba = trim_ground_shadow(rgba[by0:by1 + 1, bx0:bx1 + 1])
    ys, xs = np.where(rgba[..., 3] > 0)
    rgba = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    rgba = clean_residue(rgba, protect)
    ys, xs = np.where(rgba[..., 3] > 0)
    rgba = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return Image.fromarray(rgba, "RGBA")


def split_walk_row(rgb, alpha, y0, y1, protect="none"):
    """Split one walk row into its 8 frames by opaque column groups."""
    cols = alpha[y0:y1 + 1].sum(0) > 0
    groups, inb, x = [], False, 0
    for i, v in enumerate(cols):
        if v and not inb:
            x, inb = i, True
        elif not v and inb:
            groups.append((x, i - 1))
            inb = False
    if inb:
        groups.append((x, len(cols) - 1))
    if len(groups) != 8:
        raise SystemExit("walk row %d-%d: got %d groups"
                         % (y0, y1, len(groups)))
    return [crop_frame(rgb, alpha, gx0, gx1, y0, y1, protect)
            for gx0, gx1 in groups]


def opposed_pair(frames):
    """The two most different frames of an 8-frame cycle (phases)."""
    small = [np.asarray(f.resize((40, 40)), dtype=float) for f in frames]
    best, pair = -1.0, (0, 4)
    for i in range(8):
        j = (i + 4) % 8
        d = float(np.abs(small[i] - small[j]).mean())
        if d > best:
            best, pair = d, (i, j)
    print("  walk phases %s (diff %.1f)" % (pair, best))
    return [frames[pair[0]], frames[pair[1]]]


def canopy_mask(rgba: Image.Image) -> np.ndarray:
    """Boolean mask of the cream canvas + its fleur-de-lis motif."""
    arr = np.asarray(rgba).astype(float) / 255.0
    r, g, b, a = arr[..., 0], arr[..., 1], arr[..., 2], arr[..., 3]
    mx = arr[..., :3].max(2)
    mn = arr[..., :3].min(2)
    rng = mx - mn
    sat = np.where(mx > 0, rng / np.maximum(mx, 1e-6), 0)
    hue = np.zeros_like(mx)
    nz = rng > 1e-6
    idx = (mx == r) & nz
    hue[idx] = ((g - b)[idx] / rng[idx]) % 6 / 6.0
    idx = (mx == g) & nz
    hue[idx] = ((b - r)[idx] / rng[idx] + 2) / 6.0
    idx = (mx == b) & nz
    hue[idx] = ((r - g)[idx] / rng[idx] + 4) / 6.0
    cream = (a > 0.5) & (hue >= 0.03) & (hue <= 0.16) & \
        (sat >= 0.04) & (sat <= 0.52) & (mx >= 0.55)
    lab, n = ndimage.label(cream)
    if n == 0:
        return np.zeros(cream.shape, bool)
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    big = sizes.max()
    h_img = cream.shape[0]
    keep = np.zeros(cream.shape, bool)
    for i, s in enumerate(sizes, start=1):
        if s < max(100.0, 0.10 * big):
            continue
        ys, _ = np.where(lab == i)
        if ys.mean() > 0.55 * h_img:  # canopy lives in the upper half
            continue
        keep |= lab == i
    # fleur-de-lis: darker warm motif pixels hugged by cream
    motif = (a > 0.5) & (hue >= 0.03) & (hue <= 0.13) & \
        (sat >= 0.22) & (sat <= 0.70) & (mx >= 0.28) & (mx <= 0.70)
    near = ndimage.distance_transform_edt(~keep) <= 5
    keep |= motif & near
    # shaded canvas folds can split into their own components (the
    # component filter drops them); regrow the mask 2px into any
    # warm cloth-like pixel touching it — the dark seam painted
    # between canvas and barrels keeps this from leaking into wood.
    cloth = (a > 0.5) & (hue >= 0.03) & (hue <= 0.16) & \
        (sat >= 0.04) & (sat <= 0.60) & (mx >= 0.45)
    near2 = ndimage.distance_transform_edt(~keep) <= 2
    keep |= cloth & near2
    return keep


def rgb_to_hsv_vec(px: np.ndarray) -> np.ndarray:
    """Vectorised colorsys.rgb_to_hsv for an (N,3) float array."""
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    mx = px.max(1)
    mn = px.min(1)
    rng = mx - mn
    v = mx
    s = np.where(mx > 0, rng / np.maximum(mx, 1e-12), 0.0)
    h = np.zeros_like(mx)
    nz = rng > 1e-12
    idx = nz & (mx == r)
    h[idx] = ((g - b)[idx] / rng[idx]) % 6 / 6.0
    idx = nz & (mx == g)
    h[idx] = ((b - r)[idx] / rng[idx] + 2) / 6.0
    idx = nz & (mx == b)
    h[idx] = ((r - g)[idx] / rng[idx] + 4) / 6.0
    return np.stack([h, s, v], 1)


def hsv_to_rgb_vec(hsv: np.ndarray) -> np.ndarray:
    """Vectorised colorsys.hsv_to_rgb for an (N,3) float array."""
    h, s, v = hsv[:, 0], hsv[:, 1], hsv[:, 2]
    i = np.floor(h * 6).astype(int)
    f = h * 6 - i
    p = v * (1 - s)
    q = v * (1 - s * f)
    t = v * (1 - s * (1 - f))
    i = i % 6
    out = np.empty_like(hsv)
    sel = [i == k for k in range(6)]
    comps = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v),
             (v, p, q)]
    for k in range(6):
        for ch in range(3):
            out[sel[k], ch] = comps[k][ch][sel[k]]
    return out


def tint_canopy(rgba: Image.Image, slot_rgb) -> Image.Image:
    mask = canopy_mask(rgba)
    if not mask.any():
        return rgba
    th, ts, _ = colorsys.rgb_to_hsv(*slot_rgb)
    cap = 0.62 * ts
    arr = np.asarray(rgba).copy()
    px = arr[mask].astype(float) / 255.0
    hsv = rgb_to_hsv_vec(px[:, :3])
    s = hsv[:, 1]
    hsv[:, 1] = np.where(s <= cap, np.minimum(s, cap),
                         np.minimum(s, cap + 0.15))
    hsv[:, 0] = th
    rgb_out = hsv_to_rgb_vec(hsv)
    out = np.concatenate([rgb_out, px[:, 3:4]], 1)
    arr[mask] = (out * 255).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def defringe(rgba: Image.Image) -> Image.Image:
    """Restore rim colours and scale their alpha by coverage."""
    arr = np.asarray(rgba).astype(float)
    rgb, alpha = arr[..., :3], arr[..., 3]
    opaque = alpha > 0
    if not opaque.any():
        return rgba
    dist = ndimage.distance_transform_edt(opaque)
    interior = dist >= 3
    if not interior.any():
        interior = opaque
    _, nearest = ndimage.distance_transform_edt(
        ~interior, return_indices=True)
    F = rgb[nearest[0], nearest[1]]  # nearest interior colour per px
    rim = opaque & (dist < 2)
    B = 240.0  # checkerboard page tone the rim was blended over
    denom = B - F
    with np.errstate(divide="ignore", invalid="ignore"):
        t_all = (B - rgb) / np.where(np.abs(denom) > 8, denom, np.nan)
    t = np.nanmedian(t_all, axis=2)
    fix = rim & (t < 0.90) & (F.min(2) <= 235) & np.isfinite(t)
    rgb[fix] = F[fix]
    alpha[fix] = np.clip(t[fix], 0.15, 1.0) * 255.0
    arr[..., :3], arr[..., 3] = rgb, alpha
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def bleed_margin(sheet: Image.Image) -> Image.Image:
    """Bleed opaque colours 3px into transparency (alpha stays 0)."""
    arr = np.asarray(sheet).astype(float)
    for _ in range(3):
        has_colour = (arr[..., :3].sum(2) > 0) | (arr[..., 3] > 0)
        if has_colour.all():
            break
        pad = np.pad(arr, ((1, 1), (1, 1), (0, 0)), mode="edge")
        acc = np.zeros_like(arr)
        cnt = np.zeros(arr.shape[:2])
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                nb = pad[1 + dy:1 + dy + arr.shape[0],
                         1 + dx:1 + dx + arr.shape[1]]
                wgt = (nb[..., 3] > 0) | (nb[..., :3].sum(2) > 0)
                acc += nb * wgt[..., None]
                cnt += wgt
        todo = ~has_colour & (cnt > 0)
        if not todo.any():
            break
        new = arr.copy()
        filled = np.zeros_like(arr)
        filled[..., 0] = acc[..., 0] / np.maximum(cnt, 1)
        filled[..., 1] = acc[..., 1] / np.maximum(cnt, 1)
        filled[..., 2] = acc[..., 2] / np.maximum(cnt, 1)
        new[todo] = filled[todo]
        new[..., 3] = arr[..., 3]
        arr = new
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def place(sheet, frame, cx, baseline):
    """Paste a frame centred at cx with its bottom on the baseline."""
    x = int(round(cx - frame.width / 2.0))
    y = int(round(baseline - frame.height))
    sheet.alpha_composite(frame, (x, y))


def build_sheet(poses, walks, walk_scales, cell_w, cell_h, baseline,
                scale):
    def sc(f, s):
        """Premultiplied LANCZOS scale: resize RGB*A and A, then
        un-premultiply, so bright page RGB sitting in transparent
        pixels cannot bleed into the silhouette's edge colours."""
        w2 = max(1, round(f.width * s))
        h2 = max(1, round(f.height * s))
        arr = np.asarray(f).astype(np.float32)
        a = arr[..., 3:4]
        pm = np.concatenate([arr[..., :3] * (a / 255.0), a], axis=2)
        chans = []
        for c in range(4):
            ch = Image.fromarray(pm[..., c], mode="F").resize(
                (w2, h2), Image.LANCZOS)
            chans.append(np.asarray(ch))
        out = np.stack(chans, axis=2)
        ao = np.clip(out[..., 3], 0.0, 255.0)
        rgb_o = np.zeros_like(out[..., :3])
        m = ao > 0.5
        rgb_o[m] = out[..., :3][m] * 255.0 / ao[m][..., None]
        res = np.dstack([np.clip(rgb_o, 0, 255), ao])
        # Hard alpha, the roster sprite standard (crisp_snap):
        # binarise at 50% coverage so LANCZOS ringing cannot leave
        # semi-transparent page-coloured pixels hanging below the
        # silhouette's true bottom edge. bleed_margin afterwards
        # repaints the transparent margin's RGB for mip safety.
        hard = res[..., 3] >= 128.0
        res[..., 3] = np.where(hard, 255.0, 0.0)
        res[~hard] = 0
        return Image.fromarray(res.astype(np.uint8), "RGBA")
    sheet = Image.new("RGBA", (cell_w * 8, cell_h * 4), (0, 0, 0, 0))
    for row in (0, 2, 3):  # idle / die / hurt share the idle poses
        for i, d in enumerate(DIRS):
            place(sheet, sc(poses[d], scale), cell_w * i + cell_w / 2.0,
                  baseline + row * cell_h)
    col = 0
    for d in DIRS:  # walk row: [down x2, left x2, right x2, up x2]
        for f in walks[d]:
            place(sheet, sc(f, walk_scales[d]),
                  cell_w * col + cell_w / 2.0, baseline + cell_h)
            col += 1
    return bleed_margin(sheet)


def main() -> None:
    src = load_source()
    rgb = np.asarray(src)
    alpha = key_out(rgb)

    y0, y1 = BIG_ROW
    big = [crop_frame(rgb, alpha, cx0, cx1, y0, y1, protect=p)
           for (cx0, cx1), p in zip(BIG_COLS,
                                    ["front", "none", "left", "right"])]
    poses = {"down": big[0], "up": big[1], "left": big[2], "right": big[3]}
    for name in DIRS:
        f = poses[name]
        print("pose %-5s %dx%d opaque=%d"
              % (name, f.width, f.height,
                 int((np.asarray(f)[..., 3] > 0).sum())))
    walks = {}
    walk_ref = {}
    protect_of = {"down": "front", "up": "none",
                  "left": "left", "right": "right"}
    for d, (wy0, wy1) in WALK_ROWS.items():
        frames = split_walk_row(rgb, alpha, wy0, wy1, protect_of[d])
        print("walk %-5s first frames: %s"
              % (d, ["%dx%d" % (f.width, f.height) for f in frames[:2]]))
        walk_ref[d] = frames[0]
        walks[d] = opposed_pair(frames)
    # The owner's walk rows are drawn at a SMALLER (and per-row
    # inconsistent) scale than the hero poses, so each walk
    # direction gets its own scale normalised onto its pose:
    # length for the side views, height for front/back.
    def walk_scale_for(veh_scale, d):
        if d in ("left", "right"):
            return veh_scale * poses[d].width / float(walk_ref[d].width)
        return veh_scale * poses[d].height / float(walk_ref[d].height)

    side_len = poses["right"].width
    measured = {}
    for slot, (dirname, ui_rgb) in sorted(SLOTS.items()):
        out_dir = os.path.join(ASSETS, dirname) if dirname else ASSETS
        os.makedirs(out_dir, exist_ok=True)
        s_poses = {d: defringe(tint_canopy(f, ui_rgb))
                   for d, f in poses.items()}
        s_walks = {d: [defringe(tint_canopy(f, ui_rgb)) for f in fs]
                   for d, fs in walks.items()}
        for veh, (cw, ch, base, target) in VEHICLES.items():
            scale = target / float(side_len)
            ws = {d: walk_scale_for(scale, d) for d in DIRS}
            sheet = build_sheet(s_poses, s_walks, ws, cw, ch, base, scale)
            png = os.path.join(out_dir, veh + ".png")
            sheet.save(png)
            manifest = {"cell_w": cw, "cell_h": ch, "baseline": base,
                        "animations": ANIMATIONS}
            with open(os.path.join(out_dir, veh + "_frames.json"), "w") as fh:
                json.dump(manifest, fh, indent=1)
            if slot == 0:
                fw = round(poses["down"].width * scale)
                fh_ = round(poses["down"].height * scale)
                measured[veh] = [fw, fh_, fh_, target]
            print("slot %d %-5s -> %s (scale %.3f)" % (slot, veh, png, scale))
    print("CONTENT_SIZE measured:", measured)


if __name__ == "__main__":
    main()
