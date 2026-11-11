#!/usr/bin/env python3
"""Extract villager animation frames from the design presentation sheet.

Source : ~/workspace/empire-age/ref/villager-sheet.jpg  (cream/near-white bg, JPG)
Output : ../assets/villager.png            (grid sheet, transparent)
         ../assets/villager_frames.json    (manifest: cell size + anim rects)
         ../assets/villager_portrait.png   (big top-left portrait, bg removed)
         /tmp/villager_contact.png         (verification contact sheet)

Method: background = pixels close to near-white that are connected to the
image border (flood fill), so cream-coloured sprite interiors survive.
Frames are found per animation row band via connected components, merged
with nearby held props (wheat / stones), with Work-row tree stumps removed.
Every frame is normalised: same scale (median Idle height), feet baseline
aligned, centred on a fixed canvas.
"""
import json
import os
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.expanduser("~/workspace/empire-age/ref/villager-sheet.jpg")
ASSETS = os.path.join(HERE, "..", "assets")
DIST_TH = 30           # colour distance from white that counts as "not bg"
RIM_DIST = 60          # boundary pixels closer than this to bg are shaved off
LABEL_X = 140          # animation rows start right of the row labels

# Row bands (y slices) measured from the sheet; labels sit at x < LABEL_X.
BANDS = {
    "idle":    (228, 302),
    "walk":    (318, 392),
    "run":     (413, 487),
    "work":    (492, 570),
    "harvest": (573, 648),
    "pickup":  (650, 725),
}


def build_alpha(rgb: np.ndarray) -> np.ndarray:
    """Boolean foreground mask via flood fill of bg-coloured pixels."""
    dist = np.sqrt(((rgb.astype(np.int32) - 255) ** 2).sum(axis=2))
    bgcand = dist <= DIST_TH
    lab, _ = ndimage.label(bgcand)
    border = set(np.unique(np.concatenate(
        [lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))) - {0}
    bgmask = np.isin(lab, list(border))
    fg = ~bgmask
    # Shave the cream/JPG fringe: foreground boundary pixels whose colour is
    # still close to the background are blends, not real sprite pixels.
    bgish = dist < RIM_DIST
    near_bg = ndimage.binary_dilation(~fg)
    fg = fg & ~(bgish & near_bg)
    return fg


def comps_in(mask: np.ndarray):
    lab, n = ndimage.label(mask)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        area = int((lab[sl] == i).sum())
        out.append({
            "x0": sl[1].start, "x1": sl[1].stop,
            "y0": sl[0].start, "y1": sl[0].stop,
            "w": sl[1].stop - sl[1].start, "h": sl[0].stop - sl[0].start,
            "area": area, "mask": lab[sl] == i,
        })
    return out


def extract_band(fg: np.ndarray, band: tuple, drop_stumps: bool = False):
    """Return sorted list of frame component dicts for one animation row."""
    y0, y1 = band
    sub = fg[y0:y1, LABEL_X:].copy()
    # Erase horizontal divider lines: rows that are >85% foreground across
    # the whole band width are printed rules, not sprites.
    cover = sub.mean(axis=1)
    sub[cover > 0.85, :] = False
    comps = comps_in(sub)
    for c in comps:
        c["x0"] += LABEL_X
        c["x1"] += LABEL_X
        c["y0"] += y0
        c["y1"] += y0
    # Drop label-bar remnants: short blobs touching the left cut are pieces
    # of the row's brown label bar, never characters (chars start x>=148).
    comps = [c for c in comps if not (c["x0"] <= LABEL_X + 1 and c["h"] < 50)]
    # Characters are the tall components.
    chars = [c for c in comps if c["h"] >= 40 and c["area"] >= 1200]
    others = [c for c in comps if c not in chars]
    # Merge nearby props (wheat, held stones, tools) into their character:
    # bbox within 10 px horizontally and vertical overlap >= 30% of the prop.
    # Props may not reach left of the first character (label-bar territory).
    first_char_x = min((c["x0"] for c in chars), default=10 ** 9)
    others = [p for p in others if p["x0"] >= first_char_x - 6]
    for p in others:
        best = None
        for ch in chars:
            dx = max(ch["x0"] - p["x1"], p["x0"] - ch["x1"], 0)
            ov = min(ch["y1"], p["y1"]) - max(ch["y0"], p["y0"])
            if dx <= 10 and ov >= 0.3 * p["h"]:
                if best is None or dx < best[0]:
                    best = (dx, ch)
        if best is not None:
            best[1].setdefault("props", []).append(p)
    if drop_stumps:
        # Work row: stumps are short blobs at ground level right of a char.
        for ch in chars:
            keep = []
            for p in ch.get("props", []):
                is_stump = (p["h"] <= 28 and p["x0"] > ch["x0"] + ch["w"] // 3
                            and p["y1"] >= ch["y1"] - 10)
                if not is_stump:
                    keep.append(p)
            ch["props"] = keep
        # Also drop standalone (unmerged) stump candidates near chars.
    chars.sort(key=lambda c: c["x0"])
    return chars


def clean_work_stump(rgb_crop: np.ndarray, m: np.ndarray) -> np.ndarray:
    """Remove a tree stump fused into a Work frame's silhouette.

    The stump sits right of the body, low in the frame, in woody browns.
    Cut zone: right of the body core (columns that have pixels in the top
    half) and below 55% of the frame height; only wood-brown pixels go
    (dark pants/shoes and grey tool heads are kept). If the cut would
    strand a small floating component (e.g. a pickaxe head whose handle
    was cut), the whole frame is reverted — accept the stump there.
    """
    h, w = m.shape
    top = m[: int(h * 0.5), :]
    cols = np.nonzero(top.any(axis=0))[0]
    if len(cols) == 0:
        return m
    core_right = int(cols.max())
    cut = m.copy()
    zone = np.zeros_like(m)
    zone[int(h * 0.55):, core_right + 3:] = True
    px = rgb_crop.astype(np.int32)
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    wood = (r > b + 30) & ((np.maximum(np.maximum(r, g), b)
                            - np.minimum(np.minimum(r, g), b)) > 45) & (r > 120)
    cut[zone & wood & m] = False
    if not cut.any():
        return m
    olab, _ = ndimage.label(m)
    osizes = ndimage.sum_labels(m, olab, np.arange(1, olab.max() + 1))
    main_label = int(np.argmax(osizes)) + 1
    # 1) Drop ground-touching leftovers fully inside the zone (the stump's
    #    dark outline survives the colour cut but sits on the ground).
    lab, n = ndimage.label(cut)
    for i in range(1, n + 1):
        comp = lab == i
        ys, xs = np.nonzero(comp)
        if (ys.max() >= h - 2 and xs.min() > core_right + 2
                and ys.min() >= int(h * 0.55)):
            cut[comp] = False
    # 2) Revert only if the cut strands a non-wood piece of the original
    #    body mid-air (e.g. a pickaxe head severed from its handle). Marks
    #    that already float in the source art do not trigger a revert.
    lab, n = ndimage.label(cut)
    for i in range(1, n + 1):
        comp = lab == i
        ys, _xs = np.nonzero(comp)
        if ys.max() >= h - 2 or comp.sum() < 40:
            continue
        if not (olab[comp] == main_label).any():
            continue
        px2 = rgb_crop[comp].astype(np.int32)
        r2, g2, b2 = px2[:, 0].mean(), px2[:, 1].mean(), px2[:, 2].mean()
        is_wood = r2 > b2 + 30 and (max(r2, g2, b2) - min(r2, g2, b2)) > 45 and r2 > 120
        if not is_wood:
            return m
    # 3) Erode-and-restore: the stump's outline shell is only ~3 px thick,
    #    so a 2 px erosion kills it while the body and tool heads survive;
    #    dilating the survivors back and intersecting with the cut mask
    #    restores the kept shapes pixel-exactly.
    er = ndimage.binary_erosion(cut, iterations=2)
    lab, n = ndimage.label(er)
    keep = np.zeros_like(cut)
    for i in range(1, n + 1):
        comp = lab == i
        if comp.sum() >= 50:
            keep |= ndimage.binary_dilation(comp, iterations=2)
    restored = cut & keep
    return restored if restored.sum() > 400 else cut


def frame_image(rgb: np.ndarray, alpha: np.ndarray, comp,
                clean_stump: bool = False) -> Image.Image:
    """Crop a component (+merged props) to an RGBA image."""
    x0, y0, x1, y1 = comp["x0"], comp["y0"], comp["x1"], comp["y1"]
    for p in comp.get("props", []):
        x0 = min(x0, p["x0"]); x1 = max(x1, p["x1"])
        y0 = min(y0, p["y0"]); y1 = max(y1, p["y1"])
    m = np.zeros((y1 - y0, x1 - x0), dtype=bool)
    m[comp["y0"] - y0:comp["y1"] - y0, comp["x0"] - x0:comp["x1"] - x0] |= comp["mask"]
    for p in comp.get("props", []):
        m[p["y0"] - y0:p["y1"] - y0, p["x0"] - x0:p["x1"] - x0] |= p["mask"]
    crop = rgb[y0:y1, x0:x1].copy()
    if clean_stump:
        m = clean_work_stump(crop, m)
        # Re-trim to the cleaned mask so the frame bbox hugs the character.
        ys, xs = np.nonzero(m)
        if len(xs):
            sub = Image.fromarray(np.dstack([crop, (m * 255).astype(np.uint8)]), "RGBA")
            return sub.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    out = np.zeros((y1 - y0, x1 - x0, 4), dtype=np.uint8)
    out[..., :3] = crop
    out[..., 3] = (m * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def main() -> None:
    img = Image.open(SRC).convert("RGB")
    rgb = np.asarray(img)
    fg = build_alpha(rgb)
    alpha = fg

    rows = {}
    for name, band in BANDS.items():
        rows[name] = extract_band(fg, band, drop_stumps=(name == "work"))
        print(f"{name:8s}: {len(rows[name])} frames")

    # ---- normalisation -------------------------------------------------
    idle_h = float(np.median([c["y1"] - c["y0"] for c in rows["idle"]]))
    target_h = 72.0
    scale = target_h / idle_h
    # Canvas must fit the widest scaled frame (work frames carry an axe).
    max_w = 0
    for comps in rows.values():
        for c in comps:
            w = c["x1"] - c["x0"]
            for p in c.get("props", []):
                w = max(w, p["x1"] - c["x0"], c["x1"] - p["x0"])
            max_w = max(max_w, w)
    cell_w = int(np.ceil(max_w * scale)) + 8
    cell_w += cell_w % 2
    cell_h = int(target_h) + 10          # feet baseline at cell_h - 4
    baseline = cell_h - 4
    print(f"idle median h={idle_h:.1f} scale={scale:.3f} cell={cell_w}x{cell_h}")

    order = ["idle", "walk", "work", "harvest", "pickup"]
    cols = 16
    sheet = Image.new("RGBA", (cell_w * cols, cell_h * len(order)), (0, 0, 0, 0))
    manifest = {"cell_w": cell_w, "cell_h": cell_h, "baseline": baseline,
                "source_height_px": idle_h, "animations": {},
                # Work frames 2 (stump-edge sliver) and 6 (stump fused into
                # the impact pose) keep stump remnants; the in-game Work
                # loop uses the clean frames only. All 12 stay in the sheet.
                "work_loop": [0, 1, 3, 4, 5, 7, 8, 9, 10, 11]}
    contact = Image.new("RGBA", (cell_w * cols, cell_h * len(order)), (40, 44, 60, 255))
    draw = ImageDraw.Draw(contact)
    for r, name in enumerate(order):
        frames = rows[name]
        anim = {"row": r, "count": len(frames), "frames": []}
        for i, c in enumerate(frames):
            fi = frame_image(rgb, alpha, c, clean_stump=(name == "work"))
            nw = max(1, int(round(fi.width * scale)))
            nh = max(1, int(round(fi.height * scale)))
            fi = fi.resize((nw, nh), Image.LANCZOS)
            px = i * cell_w + (cell_w - nw) // 2
            py = r * cell_h + (baseline - nh)
            sheet.alpha_composite(fi, (px, py))
            contact.alpha_composite(fi, (px, py))
            anim["frames"].append({"col": i, "row": r})
            draw.rectangle([i * cell_w, r * cell_h, (i + 1) * cell_w - 1,
                            (r + 1) * cell_h - 1], outline=(120, 130, 160, 255))
            draw.text((i * cell_w + 3, r * cell_h + 2), f"{name[:2]}{i}",
                      fill=(255, 220, 120, 255))
        manifest["animations"][name] = anim

    os.makedirs(ASSETS, exist_ok=True)
    sheet.save(os.path.join(ASSETS, "villager.png"))
    with open(os.path.join(ASSETS, "villager_frames.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    contact.save("/tmp/villager_contact.png")
    print("sheet:", sheet.size, "-> assets/villager.png; contact -> /tmp/villager_contact.png")

    # ---- portrait -------------------------------------------------------
    region = fg[0:235, 0:180]
    pcomps = [c for c in comps_in(region) if c["h"] >= 120 and c["area"] > 8000]
    if pcomps:
        p = max(pcomps, key=lambda c: c["area"])
        port = frame_image(rgb, alpha, p)
        # The "Dan (Villager)" label bar is fused to the top of this blob
        # with no fully empty row between: cut at the narrowest alpha row
        # (the neck where the label ends and the hat brim begins).
        pa = np.asarray(port)[..., 3] > 0
        counts = pa.sum(axis=1)
        lo, hi = 15, min(60, port.height // 3)
        neck = lo + int(np.argmin(counts[lo:hi]))
        if counts[neck] < 40:
            port = port.crop((0, neck + 1, port.width, port.height))
            ys, xs = np.nonzero(np.asarray(port)[..., 3] > 0)
            port = port.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        port.save(os.path.join(ASSETS, "villager_portrait.png"))
        print("portrait:", port.size)
    else:
        print("portrait: NOT FOUND", [(c["x0"], c["y0"], c["w"], c["h"], c["area"]) for c in comps_in(region)][:8])


if __name__ == "__main__":
    main()
