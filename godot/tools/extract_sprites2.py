#!/usr/bin/env python3
"""Extract the NEW character sprites (sent by Tin 2026-11-07) into game sheets.

Sources (originals in ~/workspace/user/files/ — the copies in ref/ are 0-byte
victims of the write outage and must NOT be used):
  villager anim : 9CE8E960...jpg  rows Idle/Walk/Work/Carry/Build/Harvest 8f, Die 7f (label says 6f)
  villager 8-dir: 9BA03421...jpg  4x2 big poses: front, front-right, right, back-right /
                                  back, back-left, left, front-left
  militia sheet : 64B625BF...jpg  4 direction rows: down / left / right / up
  archer  sheet : ED846FF7...jpg  4 direction rows: down / right / up / left
                                  (loose arrow frames sit inside the shoot segment)

Outputs (in ../assets/):
  villager.png + villager_frames.json + villager_portrait.png  (REPLACES straw-hat villager)
  militia.png  + militia_frames.json
  archer.png   + archer_frames.json
  arrow.png    (projectile sprite for P3, cut from the archer sheet)

Method: white background removal by flood fill from the border (same as
extract_villager.py), connected components per row band, nearby props merged
into their character, wide merged components split at the alpha valley.
Every frame is normalised to a shared scale (median idle height -> 72 px),
feet baseline aligned, centred in a fixed cell.

Composed layout (all sheets): animation rows, direction frames grouped as
[down xN, left xN, right xN, up xN] for directional anims (idle/walk/attack).
The new villager only has front-facing animation cycles; side/up frames in
idle/walk are the matching static poses from the 8-dir sheet (with a 2 px
step bob on walk), Carry frames are used while returning with a load.
"""
import json
import os
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
    """Split a merged component (two figures touching) at its alpha valley."""
    if comp["w"] <= max_w:
        return [comp]
    sub = fg[comp["y0"]:comp["y1"], comp["x0"]:comp["x1"]]
    colsum = sub.sum(axis=0)
    lo, hi = comp["w"] // 3, 2 * comp["w"] // 3
    if hi <= lo:
        return [comp]
    cut = lo + int(np.argmin(colsum[lo:hi]))
    if colsum[cut] > 0.6 * colsum.max():
        return [comp]  # no real valley; keep as one wide frame (e.g. lying body)
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
    """Character frames of one row band, props merged, sorted by x."""
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
    # Merge small props that touch the ground zone of a character
    # (build posts, held tools); floating marks (sound/effect curls in the
    # upper area) are dropped.
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


def frame_image(rgb, comp):
    x0, y0, x1, y1 = comp["x0"], comp["y0"], comp["x1"], comp["y1"]
    for p in comp.get("props", []):
        x0 = min(x0, p["x0"]); x1 = max(x1, p["x1"]); y0 = min(y0, p["y0"]); y1 = max(y1, p["y1"])
    m = np.zeros((y1 - y0, x1 - x0), dtype=bool)
    m[comp["y0"] - y0:comp["y1"] - y0, comp["x0"] - x0:comp["x1"] - x0] |= comp["mask"]
    for p in comp.get("props", []):
        m[p["y0"] - y0:p["y1"] - y0, p["x0"] - x0:p["x1"] - x0] |= p["mask"]
    crop = rgb[y0:y1, x0:x1]
    out = np.zeros((y1 - y0, x1 - x0, 4), dtype=np.uint8)
    out[..., :3] = crop
    out[..., 3] = (m * 255).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    ys, xs = np.nonzero(m)
    if len(xs):
        img = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    return img


def compose(rows_spec, scale, out_png, out_json, extra=None):
    """rows_spec: list of (anim_name, frames[list of PIL images], per_dir or None).
    Returns manifest dict. Frames are pasted baseline-aligned, centred."""
    max_w = 0
    for _name, frames, _pd in rows_spec:
        for f in frames:
            max_w = max(max_w, f.width)
    cell_w = int(np.ceil(max_w * scale)) + 8
    cell_w += cell_w % 2
    cell_h = int(TARGET_H) + 10
    baseline = cell_h - 4
    cols = max(len(frames) for _n, frames, _p in rows_spec)
    sheet = Image.new("RGBA", (cell_w * cols, cell_h * len(rows_spec)), (0, 0, 0, 0))
    manifest = {"cell_w": cell_w, "cell_h": cell_h, "baseline": baseline, "animations": {}}
    if extra:
        manifest.update(extra)
    for r, (name, frames, per_dir) in enumerate(rows_spec):
        for i, fi in enumerate(frames):
            nw = max(1, int(round(fi.width * scale)))
            nh = max(1, int(round(fi.height * scale)))
            rs = fi.resize((nw, nh), Image.LANCZOS)
            px = i * cell_w + (cell_w - nw) // 2
            py = r * cell_h + (baseline - nh)
            sheet.alpha_composite(rs, (px, py))
        manifest["animations"][name] = {
            "row": r, "count": len(frames),
            "per_dir": per_dir if per_dir else len(frames),
        }
    os.makedirs(ASSETS, exist_ok=True)
    sheet.save(os.path.join(ASSETS, out_png))
    with open(os.path.join(ASSETS, out_json), "w") as f:
        json.dump(manifest, f, indent=1)
    print(f"{out_png}: sheet {sheet.size} cell {cell_w}x{cell_h} scale {scale:.3f} anims "
          + ", ".join(f"{n}={len(fr)}" for n, fr, _ in rows_spec))
    return manifest


def load(path):
    img = Image.open(path).convert("RGB")
    rgb = np.asarray(img)
    return rgb, build_alpha(rgb)


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
    frames = {n: [frame_image(rgb, c) for c in bands[n]] for n in names}

    rgb2, fg2 = load(SRC_VILL_DIR)
    H2, W2 = rgb2.shape[0], rgb2.shape[1]
    poses = []
    for r in range(2):
        for cidx in range(4):
            comps = band_frames(rgb2, fg2, int(r * H2 / 2), int((r + 1) * H2 / 2),
                                cidx * W2 // 4, max_w=400, min_h=150)
            # keep only comps whose centre sits in this quadrant
            quad = [c for c in comps if cidx * W2 // 4 <= (c["x0"] + c["x1"]) // 2 < (cidx + 1) * W2 // 4]
            poses.append(frame_image(rgb2, quad[0]))
    print("villager poses:", [p.size for p in poses])
    # pose order: 0 front, 1 front-right, 2 right, 3 back-right, 4 back, 5 back-left, 6 left, 7 front-left
    idle_h = float(np.median([c["h"] for c in bands["idle"]]))
    scale = TARGET_H / idle_h
    # The 8-dir poses are drawn ~2.8x larger than the anim frames: shrink
    # them to the anim frames' height so the shared compose scale fits.
    portrait_img = poses[0]
    poses = [p.resize((max(1, int(round(p.width * idle_h / p.height))), int(idle_h)),
                      Image.LANCZOS) for p in poses]
    front, right_p, back, left_p = poses[0], poses[2], poses[4], poses[6]

    def directional(anim_frames, bob=False):
        out = list(anim_frames[:4])                       # down: real front cycle
        for pose in (left_p, right_p, back):              # left, right, up: static poses
            for k in range(4):
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
    compose(rows, scale, "villager.png", "villager_frames.json",
            extra={"work_loop": list(range(len(frames["work"]))),
                   "note": "idle/walk side+up frames are static poses from the 8-dir sheet; down uses the real front cycle"})
    portrait_img.save(os.path.join(ASSETS, "villager_portrait.png"))
    print("villager portrait:", portrait_img.size)


# ------------------------------------------------------------------ military
def cluster_segments(chars):
    """Split a row's frames into segments at wide x gaps."""
    segs = [[chars[0]]]
    for prev, cur in zip(chars, chars[1:]):
        if cur["x0"] - prev["x1"] > 16:
            segs.append([cur])
        else:
            segs[-1].append(cur)
    return segs


def do_military(src, dir_rows, out_png, out_json, arrow_src=False, bounds=None):
    """dir_rows: source row index per direction in [down, left, right, up] order.
    bounds: x boundaries between the row's segments [idle|walk|attack|filler|die],
    measured from the sheets (the AI sheets are not on an exact uniform grid,
    so segment assignment is by frame centre x within these bands)."""
    rgb, fg = load(src)
    H = rgb.shape[0]
    per_dir_anims = {"idle": {}, "walk": {}, "attack": {}, "die": {}, "hurt": {}}
    arrow_img = None
    for src_row in range(4):
        y0 = int(src_row * H / 4); y1 = int((src_row + 1) * H / 4)
        chars = band_frames(rgb, fg, y0, y1, 0, max_w=78, min_h=30)
        # Die frames: lying bodies are naturally wide and the splitter would
        # shred them into helmet fragments — keep the raw merged components
        # (a frame may hold a body pair, intact) for the die segment instead.
        chars_raw = band_frames(rgb, fg, y0, y1, 0, max_w=100000, min_h=30)
        # small loose components in the band: the archer's separate arrow
        sub = fg[y0:y1, :]
        for c in comps_in(sub):
            if 14 <= c["w"] <= 34 and 6 <= c["h"] <= 18 and c["area"] >= 60:
                cc = dict(c); cc["y0"] += y0; cc["y1"] += y0
                if arrow_img is None:
                    arrow_img = frame_image(rgb, cc)
        kinds = ["idle", "walk", "attack", "hurt", "die"]
        assign = {}
        for c in chars:
            cx = (c["x0"] + c["x1"]) // 2
            seg = 0
            for b in bounds:
                if cx >= b:
                    seg += 1
            if kinds[seg] == "die":
                continue  # die comes from chars_raw below
            assign.setdefault(kinds[seg], []).append(c)
        for c in chars_raw:
            cx = (c["x0"] + c["x1"]) // 2
            if cx >= bounds[-1]:
                assign.setdefault("die", []).append(c)
        for v in assign.values():
            v.sort(key=lambda c: c["x0"])
        direction = ["down", "left", "right", "up"][dir_rows.index(src_row)]
        print(os.path.basename(src), "row", src_row, "->", direction,
              {k: len(v) for k, v in assign.items()})
        for kind, comps in assign.items():
            per_dir_anims[kind][direction] = [frame_image(rgb, c) for c in comps]

    all_frames = []
    for kind in ("idle", "walk", "attack", "die", "hurt"):
        for d in ("down", "left", "right", "up"):
            all_frames.extend(per_dir_anims[kind].get(d, []))
    idle_h = float(np.median([f.height for f in per_dir_anims["idle"].get("down", [])] or [60]))
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
    compose(rows, scale, out_png, out_json)
    if arrow_src and arrow_img is not None:
        arrow_img.save(os.path.join(ASSETS, "arrow.png"))
        print("arrow.png:", arrow_img.size)


if __name__ == "__main__":
    do_villager()
    # militia source rows: 0 down, 1 left, 2 right, 3 up
    do_military(SRC_MILITIA, [0, 1, 2, 3], "militia.png", "militia_frames.json",
                bounds=[232, 492, 760, 978])
    # archer source rows: 0 down, 1 right, 2 up, 3 left -> per direction [down0, left3, right1, up2]
    do_military(SRC_ARCHER, [0, 3, 1, 2], "archer.png", "archer_frames.json", arrow_src=True,
                bounds=[280, 555, 878, 1010])
