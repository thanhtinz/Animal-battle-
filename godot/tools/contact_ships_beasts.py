#!/usr/bin/env python3
"""Contact sheet of the ships + beasts pass sprites, on the game's
dark navy, each at roughly its in-game display size x3 so the family
resemblance can be judged. Output:
  shots/empire_age_ships_beasts_contact_v1.png
"""
import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "assets")
OUT = os.path.join(ROOT, "shots", "empire_age_ships_beasts_contact_v1.png")

BG = (16, 24, 38, 255)
INK = (235, 240, 248, 255)


def beast_frame(species, pose_key):
    sheet = Image.open(os.path.join(A, "env", species + ".png")).convert("RGBA")
    meta = json.load(open(os.path.join(A, "env", species + "_frames.json")))
    idx = meta[pose_key]
    if isinstance(idx, list):
        idx = idx[0]
    cw, ch = meta["cell_w"], meta["cell_h"]
    frame = sheet.crop((idx * cw, 0, (idx + 1) * cw, ch))
    # Display at in-game scale x3.
    sc = meta["scale"] * 3.0
    return frame.resize((max(2, int(frame.width * sc)), max(2, int(frame.height * sc))),
                        Image.LANCZOS)


def ship(name, enemy=False):
    p = os.path.join(A, "enemy" if enemy else "", "ships", name + ".png")
    img = Image.open(p).convert("RGBA")
    target = {"fishing_boat": 74, "transport": 106, "war_ship": 110}[name] * 3
    sc = min(target / img.width, 196.0 / img.height)
    return img.resize((max(2, int(img.width * sc)), max(2, int(img.height * sc))),
                      Image.LANCZOS)


items = [
    ("Fishing Boat", ship("fishing_boat")),
    ("Transport", ship("transport")),
    ("War Ship", ship("war_ship")),
    ("War Ship (enemy)", ship("war_ship", enemy=True)),
    ("Wolf walk", beast_frame("wolf", "walk")),
    ("Wolf attack", beast_frame("wolf", "attack")),
    ("Wolf snow", beast_frame("wolf_snow", "idle")),
    ("Wolf desert", beast_frame("wolf_desert", "idle")),
    ("Bear", beast_frame("bear", "idle")),
    ("Bear attack", beast_frame("bear", "attack")),
    ("Boar", beast_frame("boar", "idle")),
    ("Boar attack", beast_frame("boar", "attack")),
]

COLS = 4
CELL_W, CELL_H, LABEL_H = 360, 240, 26
rows = (len(items) + COLS - 1) // COLS
canvas = Image.new("RGBA", (COLS * CELL_W, rows * CELL_H), BG)
d = ImageDraw.Draw(canvas)
for i, (label, img) in enumerate(items):
    cx = (i % COLS) * CELL_W
    cy = (i // COLS) * CELL_H
    x = cx + (CELL_W - img.width) // 2
    y = cy + (CELL_H - LABEL_H - img.height) // 2
    canvas.alpha_composite(img, (x, y))
    d.text((cx + 10, cy + CELL_H - LABEL_H + 4), label, fill=INK)
canvas.convert("RGB").save(OUT)
print("saved", OUT, canvas.size)
