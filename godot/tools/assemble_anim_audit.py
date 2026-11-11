#!/usr/bin/env python3
"""Assemble the 13o animation-audit GIFs from the frames recorded by
tests/capture_anim_audit.tscn, plus two "before" GIFs built straight
from the sprite sheets (the Ram's walk row and the Spearman's idle
row are pixel-identical repeats — a GIF of them IS the statue the
13o pass replaced).

Run: python3 tools/assemble_anim_audit.py
Output: shots/empire_age_anim_audit_v1/*.gif
"""
import glob
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "shots",
                    "empire_age_anim_audit_v1")
FRAMES = os.path.join(ROOT, "frames")
ASSETS = os.path.join(os.path.dirname(__file__), "..", "assets")


def load_seg(seg):
    paths = sorted(glob.glob(os.path.join(FRAMES, seg, "f_*.png")))
    return [Image.open(p).convert("RGB") for p in paths]


def center_crop(img, w, h):
    cw, ch = img.size
    x = max(0, (cw - w) // 2)
    y = max(0, (ch - h) // 2)
    return img.crop((x, y, x + w, y + h))


def save_gif(frames, name, duration=120, resize=None):
    if not frames:
        print("SKIP (no frames):", name)
        return
    if resize:
        frames = [f.resize(resize, Image.LANCZOS) for f in frames]
    out = os.path.join(ROOT, name)
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=duration, loop=0, optimize=True)
    print("WROTE", out, len(frames), "frames",
          os.path.getsize(out) // 1024, "KB")


def main():
    # Flags: before (materials stripped, baked flag frozen) then
    # after (wave shader live) — tight crop on the Town Center.
    before = [center_crop(f, 560, 420) for f in load_seg("base_before")]
    after = [center_crop(f, 560, 420) for f in load_seg("base")]
    save_gif(before + after, "flags_before_after.gif")
    # Wide living base: flags, hearth smoke, tree + crop sway,
    # breathing troops — full frame, downscaled.
    save_gif(load_seg("base"), "base_wide.gif", resize=(768, 432))
    # Idle lineup (spearman/cavalry breathing on 1-frame idle rows).
    save_gif([center_crop(f, 640, 430) for f in load_seg("lineup")],
             "units_idle.gif")
    # Hurt row + flash on the militia.
    save_gif([center_crop(f, 640, 430) for f in load_seg("hurt")],
             "units_hurt.gif")
    # Villager work loop (pre-existing rows, audit evidence).
    save_gif([center_crop(f, 560, 400) for f in load_seg("gather")],
             "villager_work.gif")
    # Cavalry gait.
    save_gif([center_crop(f, 640, 400) for f in load_seg("cavalry")],
             "cavalry_walk.gif")
    # Ram approach rock + battering thrust.
    save_gif([center_crop(f, 660, 420) for f in load_seg("ram")],
             "ram_attack.gif")
    # Beasts breathing / wandering.
    save_gif([center_crop(f, 600, 420) for f in load_seg("beasts")],
             "beasts_idle.gif")
    # Ships bob + roll.
    save_gif([center_crop(f, 680, 440) for f in load_seg("ships")],
             "ships_sail.gif")

    # ---- "before" GIFs from the sheets themselves ----------------
    # Ram walk row: 4 frames of the first direction group, looped.
    # Pixel audit: every frame in this sheet is IDENTICAL, so this
    # GIF is a statue sliding — exactly the pre-13o behaviour.
    ram = Image.open(os.path.join(ASSETS, "ram.png")).convert("RGBA")
    cw, ch = 240, 140
    row = 1  # walk
    bg = Image.new("RGBA", (cw, ch), (70, 110, 60, 255))
    frames = []
    for rep in range(3):
        for i in range(4):
            f = ram.crop((i * cw, row * ch, (i + 1) * cw, (row + 1) * ch))
            canvas = bg.copy()
            canvas.alpha_composite(f)
            frames.append(canvas.convert("RGB").resize((360, 210), Image.LANCZOS))
    save_gif(frames, "before_ram_sheet.gif", duration=150)
    # Spearman idle: per_dir = 1 — the down-facing "cycle" is this
    # single frame forever.
    sp = Image.open(os.path.join(ASSETS, "spearman.png")).convert("RGBA")
    cw, ch = 184, 96
    f0 = sp.crop((0, 0, cw, ch))
    canvas = Image.new("RGBA", (cw, ch), (70, 110, 60, 255))
    canvas.alpha_composite(f0)
    still = canvas.convert("RGB").resize((368, 192), Image.LANCZOS)
    save_gif([still] * 10, "before_spearman_idle.gif", duration=150)


if __name__ == "__main__":
    main()
