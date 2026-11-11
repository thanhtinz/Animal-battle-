#!/usr/bin/env python3
"""Re-cut the character sprites from the ORIGINAL source JPGs with smooth
alpha matting (v3 — the root-cause fix for the "lem" / ragged-edge look).

Why the old sheets looked ragged: extract_sprites2.py built a near-BINARY
alpha (flood fill + rim shave), so every silhouette edge was a hard 1 px
step whose RGB was the character colour pre-blended over the white page;
the follow-up defringe pass could only patch the worst of it, and the
sheets were then rendered with TEXTURE_FILTER_NEAREST at fractional
scales, turning the steps into chunky blocks with white/grey speckle
along hair and under feet.

This tool keeps the EXACT frame geometry of extract_sprites2.py — same
detection (build_alpha / band_frames / split_wide copied verbatim), same
component bboxes, same cell size / baseline from the shipped
*_frames.json (which it never rewrites) — and replaces only the pixel
treatment inside each frame:

  * smooth alpha: coverage estimated per pixel as whiteness-distance /
    nearest-deep-interior whiteness-distance (accurate for dark outlines
    AND pale skin/cream cloth), gaussian-smoothed, support limited to a
    3 px dilation of the core silhouette. No threshold steps. Enclosed
    white holes (arm/torso gaps) correctly fall to alpha 0.
  * RGB unblended from white with that alpha, then bled toward the
    nearest interior colour; interior colours also bled a few px under
    the transparent margin so filtered sampling never sees bare white.
  * the baked grey contact-shadow blob under the feet is REMOVED from
    the silhouette (flat low-saturation blob grown from the frame's
    bottom rows); units get a soft code-drawn ellipse shadow instead
    (scripts/unit.gd).
  * every resize runs in PREMULTIPLIED space (the old pipeline resized
    straight RGBA, which itself smears edge colours).

Outputs: ../assets/villager.png, militia.png, archer.png (same sizes as
the shipped sheets) and villager_portrait.png. arrow.png is untouched.
Contacts + halo scores are printed for verification.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "assets")
USER = os.path.expanduser("~/workspace/user/files")
SRC_VILL_ANIM = os.path.join(USER, "9CE8E960-96E1-4765-A47D-5B67B35F8FF8-photo-E73FA6D2-2DE9-45AB-812C-2A873EAE132D.jpg")
SRC_VILL_DIR = os.path.join(USER, "9BA03421-0D8D-49E4-BD0D-BAA0914A98E9-photo-3F2A63CE-A835-46A1-B75E-11099BA6E049.jpg")
SRC_MILITIA = os.path.join(USER, "64B625BF-4D18-4FB3-81A3-A5C5A4AED697-photo-0BC56B7C-9D28-43EC-A95B-30C362189A86.jpg")
SRC_ARCHER = os.path.join(USER, "ED846FF7-810F-4896-BC3D-55E16C90759F-photo-6991F663-7C23-4A66-B1A3-CB404E7A90C6.jpg")

DIST_TH = 30
RIM_DIST = 60
TARGET_H = 72.0
PAD = 5  # source px of matting margin kept around each frame's core bbox


# --------------------------------------------------------------------------
# Detection — copied verbatim from extract_sprites2.py so the frame
# geometry (components, bboxes, counts) is bit-identical to the shipped
# sheets.
# --------------------------------------------------------------------------
def build_alpha(rgb):
    dist = np.sqrt(((rgb.astype(np.int32) - 255) ** 2).sum(axis=2))
    bgcand = dist <= DIST_TH
    lab, _ = ndimage.label(bgcand)
    border = set(np.unique(np.concatenate([lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))) - {0}
    bgmask = np.isin(lab, list(border))
    fg = ~bgmask
    bgish = dist < RIM_DIST
    near_bg = ndimage.binary_dilation(~fg)
    fg = fg & ~(bgish & near_bg)
    return fg


def comps_in(mask):
    lab, n = ndimage.label(mask)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        out.append({
            "x0": sl[1].start, "x1": sl[1].stop, "y0": sl[0].start, "y1": sl[0].stop,
            "w": sl[1].stop - sl[1].start, "h": sl[0].stop - sl[0].start,
            "area": int((lab[sl] == i).sum()), "mask": lab[sl] == i,
        })
    return out


def split_wide(rgb, fg, comp, max_w):
    if comp["w"] <= max_w:
        return [comp]
    sub = fg[comp["y0"]:comp["y1"], comp["x0"]:comp["x1"]]
    colsum = sub.sum(axis=0)
    lo, hi = comp["w"] // 3, 2 * comp["w"] // 3
    if hi <= lo:
        return [comp]
    cut = lo + int(np.argmin(colsum[lo:hi]))
    if colsum[cut] > 0.6 * colsum.max():
        return [comp]
    left = dict(comp); right = dict(comp)
    m = comp["mask"]
    left["mask"] = m[:, :cut]; right["mask"] = m[:, cut:]
    left["x1"] = comp["x0"] + cut; right["x0"] = comp["x0"] + cut
    left["w"] = cut; right["w"] = comp["w"] - cut
    out = []
    for c in (left, right):
        c["area"] = int(c["mask"].sum())
        if c["area"] >= 150:
            out.extend(split_wide(rgb, fg, c, max_w))
    return out if out else [comp]


def band_frames(rgb, fg, y0, y1, x_min, max_w=95, min_h=38):
    sub = fg[y0:y1, x_min:].copy()
    comps = comps_in(sub)
    for c in comps:
        c["x0"] += x_min; c["x1"] += x_min; c["y0"] += y0; c["y1"] += y0
    chars = [c for c in comps if c["h"] >= min_h and c["area"] >= 700 and c["w"] >= 38]
    others = [c for c in comps if c not in chars]
    expanded = []
    for ch in chars:
        expanded.extend(split_wide(rgb, fg, ch, max_w))
    chars = expanded
    chars.sort(key=lambda c: c["x0"])
    for p in others:
        if p["area"] < 40:
            continue
        for ch in chars:
            dx = max(ch["x0"] - p["x1"], p["x0"] - ch["x1"], 0)
            ground_prop = p["y1"] >= ch["y1"] - 25
            if dx <= 10 and ground_prop:
                ch.setdefault("props", []).append(p)
                break
    return chars


# --------------------------------------------------------------------------
# Smooth matting
# --------------------------------------------------------------------------
def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def remove_shadow(crop, prior, pad_t, core_h):
    """Cut the baked grey contact-shadow blob out of the silhouette.

    Candidates: flat light-grey pixels (sat < 0.10, 150 < lum < 248)
    inside the prior mask, in the bottom 45% of the core frame, grown
    from seeds in the bottom 12%. A grown blob is only removed when it
    is flat like a ground shadow (height <= 45% of its width) — a tall
    blob is body/armour, not shadow.
    """
    lum = crop.mean(axis=2)
    sat = (crop.max(axis=2) - crop.min(axis=2)) / np.maximum(crop.max(axis=2), 1.0)
    cand = prior & (sat < 0.10) & (lum > 150) & (lum < 248)
    h = crop.shape[0]
    zone = np.zeros_like(prior)
    zone[pad_t + int(0.55 * core_h):, :] = True
    seeds = np.zeros_like(prior)
    seeds[pad_t + int(0.88 * core_h):, :] = True
    grow = cand & zone
    if not (grow & seeds).any():
        return prior
    lab, n = ndimage.label(grow, structure=np.ones((3, 3)))
    hit = set(np.unique(lab[seeds & grow])) - {0}
    if not hit:
        return prior
    blob = np.isin(lab, list(hit))
    ys, xs = np.where(blob)
    bh = ys.max() - ys.min() + 1
    bw = xs.max() - xs.min() + 1
    if bh > 0.45 * max(bw, 1):
        return prior  # too tall to be a ground shadow — leave it alone
    return prior & ~blob


def remove_white_effects(crop, prior):
    """Cut baked EFFECT paint (axe-swing swooshes, dust puffs) out of
    the silhouette. Effect paint is light and desaturated (sat < 0.26,
    lum > 175 — white, beige and grey washes; skin, wheat, wood and
    hair are all far more saturated). Large regions of it (area >= 150
    source px — swooshes and dust; small details like arrow fletching
    are exempt) are PEELED layer by layer from the silhouette boundary
    inward: only eligible pixels within 1.5 px of open background are
    removed, repeatedly. Peeling stops dead at any saturated/dark
    barrier — the outline around the cream sleeves, skin, the axe
    head, armour plate outlines — so real costume whites behind an
    outline are never reached, and enclosed whites (eye glints) are
    untouched."""
    lum = crop.mean(axis=2)
    sat = (crop.max(axis=2) - crop.min(axis=2)) / np.maximum(crop.max(axis=2), 1.0)
    nw = prior & (sat < 0.26) & (lum > 175)
    if not nw.any():
        return prior
    lab, n = ndimage.label(nw, structure=np.ones((3, 3)))
    if n == 0:
        return prior
    areas = ndimage.sum_labels(nw, lab, np.arange(1, n + 1))
    eligible = np.isin(lab, [i + 1 for i, a in enumerate(areas) if a >= 60])
    peel = nw & eligible
    if not peel.any():
        return prior
    cur = prior.copy()
    for _ in range(64):
        dist_out = ndimage.distance_transform_edt(cur)
        exposed = peel & cur & (dist_out <= 1.5)
        if not exposed.any():
            break
        cur = cur & ~exposed
    # The swoosh's own darker edge stroke survives the peel as DETACHED
    # arc fragments (its colour fails the wash test). Drop detached
    # components that are entirely pale/desaturated — real detached
    # props (wheat, wood posts, a loose arrow) are saturated or dark.
    lab2, n2 = ndimage.label(cur, structure=np.ones((3, 3)))
    if n2 > 1:
        areas2 = ndimage.sum_labels(cur, lab2, np.arange(1, n2 + 1))
        main_id = int(np.argmax(areas2)) + 1
        drop = []
        for i in range(1, n2 + 1):
            if i == main_id or areas2[i - 1] > 0.4 * areas2[main_id - 1]:
                continue
            comp = lab2 == i
            if sat[comp].mean() < 0.35 and lum[comp].mean() > 160:
                drop.append(i)
        if drop:
            cur = cur & ~np.isin(lab2, drop)
    return cur


def matte_crop(crop, prior, fg_crop):
    """Smooth-matte one padded frame crop.

    crop: float RGB (source px). prior: bool core silhouette (shadow
    already removed). fg_crop: the detection foreground in the same
    crop, used to keep neighbouring frames' silhouettes out of the
    support band.
    Returns a uint8 RGBA PIL image of the padded crop.
    """
    d = np.sqrt(((255.0 - crop) ** 2).sum(axis=2)) / (255.0 * np.sqrt(3.0))
    dist_in = ndimage.distance_transform_edt(prior)
    interior = dist_in >= 2
    _, inds = ndimage.distance_transform_edt(~interior, return_indices=True)
    near_rgb = crop[inds[0], inds[1]]
    d_near = d[inds[0], inds[1]]
    # Coverage: whiteness ratio against the nearest interior colour.
    alpha = np.clip(d / np.maximum(d_near, 0.08), 0.0, 1.0)
    nearwhite = d_near < 0.08
    alpha = np.where(nearwhite, smoothstep(0.03, 0.20, d), alpha)
    alpha = np.where(d < 0.025, 0.0, alpha)
    support = ndimage.binary_dilation(prior, iterations=3) & (prior | ~fg_crop)
    alpha = np.where(support, alpha, 0.0)
    alpha = ndimage.gaussian_filter(alpha, 0.7)
    alpha = np.where(support, alpha, 0.0)
    # Gentle alpha contrast: pulls the faint outer skirt (alpha < ~0.1,
    # mostly JPEG haze) to zero and firms up the near-solid band, so the
    # visible transition stays smooth but carries no wide pale halo.
    alpha = smoothstep(0.06, 0.94, alpha)
    alpha = np.where(dist_in >= 3, 1.0, alpha)
    alpha = np.clip(alpha, 0.0, 1.0)
    # Unblend RGB from white, then bleed toward the interior colour so
    # the semi band carries true colours instead of JPEG grey.
    F = crop.copy()
    semi = (alpha > 0.02) & (alpha < 0.98)
    av = alpha[semi]
    F[semi] = np.clip((crop[semi] - (1.0 - av)[:, None] * 255.0) / av[:, None], 0, 255)
    lean = (alpha > 0.0) & (alpha < 0.9)
    wgt = np.where(lean, 0.35 * (1.0 - alpha), 0.0)
    F = F * (1.0 - wgt[..., None]) + near_rgb * wgt[..., None]
    # Colour margin under full transparency for filtered sampling.
    dout = ndimage.distance_transform_edt(alpha <= 0.0)
    margin = (alpha <= 0.0) & (dout <= 3)
    F[margin] = near_rgb[margin]
    out = np.dstack([F, alpha * 255.0])
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def matted_frame(rgb, fg, comp):
    """Frame record for one detected component: a matted RGBA image of
    the core bbox padded by PAD, plus the core geometry so compose can
    anchor it exactly where the old binary frame sat."""
    x0, y0, x1, y1 = comp["x0"], comp["y0"], comp["x1"], comp["y1"]
    for p in comp.get("props", []):
        x0 = min(x0, p["x0"]); x1 = max(x1, p["x1"])
        y0 = min(y0, p["y0"]); y1 = max(y1, p["y1"])
    m = np.zeros((y1 - y0, x1 - x0), dtype=bool)
    m[comp["y0"] - y0:comp["y1"] - y0, comp["x0"] - x0:comp["x1"] - x0] |= comp["mask"]
    for p in comp.get("props", []):
        m[p["y0"] - y0:p["y1"] - y0, p["x0"] - x0:p["x1"] - x0] |= p["mask"]
    ys, xs = np.nonzero(m)
    ty0, ty1, tx0, tx1 = ys.min(), ys.max(), xs.min(), xs.max()
    cx0, cy0 = x0 + tx0, y0 + ty0
    cx1, cy1 = x0 + tx1 + 1, y0 + ty1 + 1
    core = m[ty0:ty1 + 1, tx0:tx1 + 1]
    core_h, core_w = core.shape
    H, W = rgb.shape[:2]
    px0, py0 = max(0, cx0 - PAD), max(0, cy0 - PAD)
    px1, py1 = min(W, cx1 + PAD), min(H, cy1 + PAD)
    pad_l, pad_t = cx0 - px0, cy0 - py0
    crop = rgb[py0:py1, px0:px1].astype(np.float64)
    prior = np.zeros(crop.shape[:2], dtype=bool)
    prior[pad_t:pad_t + core_h, pad_l:pad_l + core_w] = core
    prior = remove_shadow(crop, prior, pad_t, core_h)
    prior = remove_white_effects(crop, prior)
    img = matte_crop(crop, prior, fg[py0:py1, px0:px1])
    return {"img": img, "core_w": int(core_w), "core_h": int(core_h),
            "pad_l": int(pad_l), "pad_t": int(pad_t)}


def resize_premul(img, size):
    """Resize an RGBA image in premultiplied space (no edge smearing)."""
    if img.size == tuple(size):
        return img
    a = np.asarray(img).astype(np.float32)
    alpha = a[..., 3]
    prem = a[..., :3] * (alpha[..., None] / 255.0)
    chans = []
    for ch in (prem[..., 0], prem[..., 1], prem[..., 2], alpha):
        chans.append(np.asarray(
            Image.fromarray(ch, mode="F").resize(size, Image.LANCZOS)))
    P = np.stack(chans[:3], axis=-1)
    A = chans[3]
    rgb = np.where(A[..., None] > 2.0,
                   P * 255.0 / np.maximum(A[..., None], 1.0), 0.0)
    out = np.dstack([np.clip(rgb, 0, 255), np.clip(A, 0, 255)])
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def compose_smooth(rows_spec, scale, out_png, cell_w, cell_h, baseline):
    """Anchored compose: cell size + baseline come from the shipped
    manifest (never recomputed), each frame's CORE lands on the same
    centre/baseline the binary frame had; the matting pad may feather
    into the cell margin but is clipped at the cell border."""
    cols = max(len(frames) for _n, frames, _p in rows_spec)
    sheet = Image.new("RGBA", (cell_w * cols, cell_h * len(rows_spec)), (0, 0, 0, 0))
    for r, (name, frames, per_dir) in enumerate(rows_spec):
        for i, rec in enumerate(frames):
            nw = max(1, int(round(rec["core_w"] * scale)))
            nh = max(1, int(round(rec["core_h"] * scale)))
            full = resize_premul(rec["img"], (max(1, int(round(rec["img"].width * scale))),
                                              max(1, int(round(rec["img"].height * scale)))))
            px = i * cell_w + (cell_w - nw) // 2 - int(round(rec["pad_l"] * scale))
            py = r * cell_h + (baseline - nh) - int(round(rec["pad_t"] * scale))
            # Clip into this frame's cell, then composite.
            ox, oy = px - i * cell_w, py - r * cell_h
            fx0, fy0 = max(0, -ox), max(0, -oy)
            fx1 = min(full.width, cell_w - ox)
            fy1 = min(full.height, cell_h - oy)
            if fx1 <= fx0 or fy1 <= fy0:
                continue
            piece = full.crop((fx0, fy0, fx1, fy1))
            sheet.alpha_composite(piece, (i * cell_w + ox + fx0, r * cell_h + oy + fy0))
    sheet.save(os.path.join(ASSETS, out_png))
    print(f"{out_png}: sheet {sheet.size} cell {cell_w}x{cell_h} (anchored, manifest untouched)")
    return sheet


def load(path):
    img = Image.open(path).convert("RGB")
    rgb = np.asarray(img)
    return rgb, build_alpha(rgb)


def cells_of(name):
    man = json.load(open(os.path.join(ASSETS, name + "_frames.json")))
    return man["cell_w"], man["cell_h"], man["baseline"]


# ------------------------------------------------------------------ villager
def do_villager():
    rgb, fg = load(SRC_VILL_ANIM)
    H = rgb.shape[0]
    names = ["idle", "walk", "work", "carry", "build", "harvest", "die"]
    bands = {}
    for i, name in enumerate(names):
        y0 = int(i * H / 7); y1 = int((i + 1) * H / 7)
        bands[name] = band_frames(rgb, fg, y0, y1, 180, max_w=130)
        print("villager", name, len(bands[name]), "frames")
    frames = {n: [matted_frame(rgb, fg, c) for c in bands[n]] for n in names}

    rgb2, fg2 = load(SRC_VILL_DIR)
    H2, W2 = rgb2.shape[0], rgb2.shape[1]
    pose_comps = []
    for r in range(2):
        for cidx in range(4):
            comps = band_frames(rgb2, fg2, int(r * H2 / 2), int((r + 1) * H2 / 2),
                                cidx * W2 // 4, max_w=400, min_h=150)
            quad = [c for c in comps if cidx * W2 // 4 <= (c["x0"] + c["x1"]) // 2 < (cidx + 1) * W2 // 4]
            pose_comps.append(quad[0])
    poses = [matted_frame(rgb2, fg2, c) for c in pose_comps]
    portrait = poses[0]["img"]
    idle_h = float(np.median([c["h"] for c in bands["idle"]]))
    scale = TARGET_H / idle_h
    # 8-dir poses are drawn ~2.8x larger: shrink to the anim frames'
    # height first (premultiplied), mirroring the old pipeline's math.
    shrunk = []
    for rec in poses:
        s = idle_h / rec["core_h"]
        img = resize_premul(rec["img"], (max(1, int(round(rec["img"].width * s))),
                                         max(1, int(round(rec["img"].height * s)))))
        shrunk.append({"img": img,
                       "core_w": int(round(rec["core_w"] * s)),
                       "core_h": int(idle_h),
                       "pad_l": int(round(rec["pad_l"] * s)),
                       "pad_t": int(round(rec["pad_t"] * s))})
    poses = shrunk
    front, right_p, back, left_p = poses[0], poses[2], poses[4], poses[6]

    def directional(anim_frames):
        out = list(anim_frames[:4])
        for pose in (left_p, right_p, back):
            for _k in range(4):
                out.append(pose)
        return out

    rows = [
        ("idle", directional(frames["idle"]), 4),
        ("walk", directional(frames["walk"]), 4),
        ("work", frames["work"], None),
        ("harvest", frames["harvest"], None),
        ("build", frames["build"], None),
        ("carry", frames["carry"], None),
        ("die", frames["die"], None),
    ]
    cw, ch, bl = cells_of("villager")
    compose_smooth(rows, scale, "villager.png", cw, ch, bl)
    portrait.save(os.path.join(ASSETS, "villager_portrait.png"))
    print("villager portrait:", portrait.size)


# ------------------------------------------------------------------ military
def do_military(src, dir_rows, out_name, bounds):
    rgb, fg = load(src)
    H = rgb.shape[0]
    per_dir_anims = {"idle": {}, "walk": {}, "attack": {}, "die": {}, "hurt": {}}
    for src_row in range(4):
        y0 = int(src_row * H / 4); y1 = int((src_row + 1) * H / 4)
        chars = band_frames(rgb, fg, y0, y1, 0, max_w=78, min_h=30)
        chars_raw = band_frames(rgb, fg, y0, y1, 0, max_w=100000, min_h=30)
        kinds = ["idle", "walk", "attack", "hurt", "die"]
        assign = {}
        for c in chars:
            cx = (c["x0"] + c["x1"]) // 2
            seg = 0
            for b in bounds:
                if cx >= b:
                    seg += 1
            if kinds[seg] == "die":
                continue
            assign.setdefault(kinds[seg], []).append(c)
        for c in chars_raw:
            cx = (c["x0"] + c["x1"]) // 2
            if cx >= bounds[-1]:
                assign.setdefault("die", []).append(c)
        for v in assign.values():
            v.sort(key=lambda c: c["x0"])
        direction = ["down", "left", "right", "up"][dir_rows.index(src_row)]
        print(os.path.basename(src)[:8], "row", src_row, "->", direction,
              {k: len(v) for k, v in assign.items()})
        for kind, comps in assign.items():
            per_dir_anims[kind][direction] = [matted_frame(rgb, fg, c) for c in comps]

    idle_h = float(np.median([f["core_h"] for f in per_dir_anims["idle"].get("down", [])] or [60]))
    scale = TARGET_H / idle_h
    rows = []
    for kind in ("idle", "walk", "attack", "die", "hurt"):
        per = max((len(per_dir_anims[kind].get(d, [])) for d in ("down", "left", "right", "up")), default=0)
        if per == 0:
            continue
        frames = []
        for d in ("down", "left", "right", "up"):
            fs = per_dir_anims[kind].get(d, [])
            frames.extend(fs)
            frames.extend([fs[-1]] * (per - len(fs)) if fs else [])
        rows.append((kind, frames, per))
    cw, ch, bl = cells_of(out_name)
    compose_smooth(rows, scale, out_name + ".png", cw, ch, bl)


# ------------------------------------------------------------------ verify
def halo_score(rgba, bg=(16.0, 24.0, 48.0)):
    """Mean luminance of the composited edge ring on navy — the same
    diagnostic the defringe pass used (lower = cleaner edge)."""
    rgb = rgba[..., :3].astype(np.float64)
    a = rgba[..., 3:].astype(np.float64) / 255.0
    comp = rgb * a + np.array(bg) * (1.0 - a)
    ring = (a[..., 0] > 0.02) & (a[..., 0] < 0.98)
    if ring.sum() == 0:
        return 0.0
    lum = comp[..., 0] * 0.299 + comp[..., 1] * 0.587 + comp[..., 2] * 0.114
    return float(lum[ring].mean())


def verify(name, backup_dir):
    old = np.asarray(Image.open(os.path.join(backup_dir, name + ".png")).convert("RGBA"))
    new = np.asarray(Image.open(os.path.join(ASSETS, name + ".png")).convert("RGBA"))
    print("%s halo: %.1f -> %.1f" % (name, halo_score(old), halo_score(new)))
    man = json.load(open(os.path.join(ASSETS, name + "_frames.json")))
    cw, ch = man["cell_w"], man["cell_h"]
    assert old.shape == new.shape, (name, old.shape, new.shape)
    worst = 0
    for y0 in range(0, new.shape[0], ch):
        for x0 in range(0, new.shape[1], cw):
            for arr, tag in ((old, "o"), (new, "n")):
                pass
            ob = np.argwhere(old[y0:y0 + ch, x0:x0 + cw, 3] > 10)
            nb = np.argwhere(new[y0:y0 + ch, x0:x0 + cw, 3] > 10)
            if len(ob) == 0 or len(nb) == 0:
                continue
            dev = max(abs(ob.min(axis=0) - nb.min(axis=0)).max(),
                      abs(ob.max(axis=0) - nb.max(axis=0)).max())
            worst = max(worst, int(dev))
    print("%s geometry: sheet size identical, worst per-cell alpha-bbox edge deviation %d px"
          % (name, worst))


def contact(name):
    """Idle row of the new sheet on navy + grass green, 4x — eyeball aid."""
    man = json.load(open(os.path.join(ASSETS, name + "_frames.json")))
    cw, ch = man["cell_w"], man["cell_h"]
    sheet = Image.open(os.path.join(ASSETS, name + ".png"))
    strip = sheet.crop((0, 0, cw * 4, ch))
    for bgname, col in (("navy", (16, 24, 48, 255)), ("grass", (106, 170, 44, 255))):
        bg = Image.new("RGBA", strip.size, col)
        bg.alpha_composite(strip)
        bg.convert("RGB").resize((strip.width * 4, strip.height * 4),
                                 Image.NEAREST).save(f"/tmp/v3work/contact_{name}_{bgname}.png")
    print("contacts -> /tmp/v3work/contact_%s_{navy,grass}.png" % name)


if __name__ == "__main__":
    backup = sys.argv[1] if len(sys.argv) > 1 else "/tmp/v3work/backup"
    do_villager()
    do_military(SRC_MILITIA, [0, 1, 2, 3], "militia", bounds=[232, 492, 760, 978])
    do_military(SRC_ARCHER, [0, 3, 1, 2], "archer", bounds=[280, 555, 878, 1010])
    for n in ("villager", "militia", "archer"):
        verify(n, backup)
        contact(n)
