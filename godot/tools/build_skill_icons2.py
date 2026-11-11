#!/usr/bin/env python3
"""Empire Age 14c — the 12 new skill icons in the approved v6
dialect (see the 13v set in assets/skill_icons/): 512x512, art on a
128 grid, ONE 48-colour palette per icon with Floyd-Steinberg
dithering, and the unified gold frame. The v6 frames are per-icon
renderings of one design, so the frame is drawn here from its
measured geometry (outer near-black edge, bronze lines, pale-gold
band with a bright ridge) over each generated motif, and the whole
icon is quantised together — exactly how the v6 set's palettes
measure (48 unique colours, frame included).

Sources: art_candidates/icons_src/media-generation-icon-<hero>-<n>-*.webp
Run from the godot/ directory:  python3 tools/build_skill_icons2.py
"""
import glob
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
EA = os.path.join(ROOT, "..")
SRC = os.path.join(EA, "art_candidates", "icons_src")
OUT = os.path.join(ROOT, "assets", "skill_icons")

HEROES = ["loi_chan", "xich_diem", "phong_linh", "thach_son"]
SIZE = 512
GRID = 128
COLORS = 48

BLACK = (10, 6, 4)
BRONZE_D = (100, 61, 25)
BRONZE = (165, 119, 52)
GOLD_MID = (198, 167, 101)
GOLD_HI = (245, 211, 128)
GOLD_LO = (214, 143, 74)


def draw_frame(im: Image.Image, seed: int) -> None:
    """The v6 gold frame, painted over the art's outer 26 px."""
    dr = ImageDraw.Draw(im)
    rng = random.Random(seed)
    S = SIZE
    # Outer near-black edge.
    dr.rectangle([0, 0, S - 1, S - 1], outline=BLACK, width=5)
    # Bronze seat.
    dr.rectangle([5, 5, S - 6, S - 6], outline=BRONZE_D, width=4)
    # Gold band with a bright ridge near its outer third.
    for i in range(9, 21):
        t = (i - 9) / 11.0
        col = tuple(int(GOLD_LO[k] + (GOLD_MID[k] - GOLD_LO[k]) * t)
                    for k in range(3))
        dr.rectangle([i, i, S - 1 - i, S - 1 - i], outline=col, width=1)
    dr.rectangle([12, 12, S - 13, S - 13], outline=GOLD_HI, width=2)
    # Inner bronze line + a whisper of inner shadow.
    dr.rectangle([21, 21, S - 22, S - 22], outline=BRONZE, width=2)
    dr.rectangle([23, 23, S - 24, S - 24], outline=BRONZE_D, width=1)
    # Painted feel: sparse darker flecks along the gold band.
    for _ in range(260):
        side = rng.randrange(4)
        t = rng.uniform(0, 1)
        off = rng.randint(9, 20)
        if side == 0:
            x, y = int(t * S), off
        elif side == 1:
            x, y = int(t * S), S - 1 - off
        elif side == 2:
            x, y = off, int(t * S)
        else:
            x, y = S - 1 - off, int(t * S)
        dr.point((x, y), fill=BRONZE)


def pixelise(im: Image.Image) -> Image.Image:
    small = im.resize((GRID, GRID), Image.LANCZOS)
    q = small.quantize(colors=COLORS, method=Image.MEDIANCUT,
                       dither=Image.FLOYDSTEINBERG)
    return q.convert("RGB").resize((SIZE, SIZE), Image.NEAREST)


def main() -> None:
    for hi, hero in enumerate(HEROES):
        for n in (1, 2, 3):
            src = glob.glob(os.path.join(
                SRC, f"media-generation-icon-{hero.replace('_', '-')}-{n}-*.webp"))[0]
            art = Image.open(src).convert("RGB")
            # Centre-crop to square, then to the icon canvas.
            w, h = art.size
            s = min(w, h)
            art = art.crop(((w - s) // 2, (h - s) // 2,
                            (w + s) // 2, (h + s) // 2)).resize((SIZE, SIZE),
                                                                Image.LANCZOS)
            draw_frame(art, seed=1400 + hi * 10 + n)
            out = pixelise(art)
            path = os.path.join(OUT, f"{hero}_{n}.png")
            out.save(path)
            cols = len(out.getcolors(SIZE * SIZE) or [])
            print(f"{hero}_{n}: {cols} colours -> {path}")


if __name__ == "__main__":
    main()
