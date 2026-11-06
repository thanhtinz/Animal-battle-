#!/usr/bin/env python3
"""Sinh texture phụ cho bản Java J1.5 (chibi): mặt nhân vật, hiên sọc, gạch, vương miện, cờ.
Chạy: python3 tools/make_textures.py -> assets/*.png"""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets')
os.makedirs(OUT, exist_ok=True)

# --- Mặt chibi: mắt to, mày giận-cute, miệng la, má hồng (nền trong suốt) ---
img = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
# má hồng
d.ellipse([30, 138, 78, 168], fill=(255, 140, 130, 110))
d.ellipse([178, 138, 226, 168], fill=(255, 140, 130, 110))
# lông mày (gạch dày chéo xuống giữa = quyết tâm)
d.line([52, 62, 100, 84], fill=(35, 28, 25, 255), width=13)
d.line([204, 62, 156, 84], fill=(35, 28, 25, 255), width=13)
# mắt đen to + đốm sáng
for cx in (76, 180):
    d.ellipse([cx - 17, 92, cx + 17, 140], fill=(30, 24, 22, 255))
    d.ellipse([cx - 6, 100, cx + 6, 114], fill=(255, 255, 255, 255))
# miệng la (oval mở + lưỡi)
d.ellipse([104, 152, 152, 196], fill=(122, 45, 32, 255))
d.pieslice([108, 168, 148, 198], 0, 180, fill=(240, 120, 120, 255))
img.save(f'{OUT}/face.png'); print('face.png')

# --- Mặt vui (cho nhân vật phụ): mắt cười cong, miệng cười ---
img = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.ellipse([30, 138, 78, 168], fill=(255, 140, 130, 110))
d.ellipse([178, 138, 226, 168], fill=(255, 140, 130, 110))
for cx in (76, 180):  # mắt cười: cung úp
    d.arc([cx - 20, 92, cx + 20, 132], 180, 360, fill=(30, 24, 22, 255), width=9)
d.arc([100, 140, 156, 196], 15, 165, fill=(122, 45, 32, 255), width=9)
img.save(f'{OUT}/face2.png'); print('face2.png')

# --- Mái hiên sọc ---
def awning(name, color):
    img = Image.new('RGB', (256, 64), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for x in range(0, 256, 64):
        d.rectangle([x, 0, x + 31, 63], fill=color)
    img.save(f'{OUT}/{name}'); print(name)
awning('awning_green.png', (38, 128, 105))
awning('awning_red.png', (200, 70, 45))

# --- Tường gạch ---
img = Image.new('RGB', (256, 128), (196, 178, 160))
d = ImageDraw.Draw(img)
bh, bw = 30, 62
for row, y in enumerate(range(0, 128, bh)):
    off = (bw // 2) if row % 2 else 0
    for x in range(-bw, 256 + bw, bw):
        d.rectangle([x + off + 3, y + 3, x + off + bw - 3, y + bh - 3], fill=(166, 84, 58))
img.save(f'{OUT}/brick.png'); print('brick.png')

# --- Vương miện (vẽ nét trắng-vàng trên trong suốt) ---
def crown(draw, ox, oy, s, fill):
    pts = [(ox, oy + 90 * s), (ox, oy + 20 * s), (ox + 42 * s, oy + 52 * s),
           (ox + 80 * s, oy), (ox + 118 * s, oy + 52 * s), (ox + 160 * s, oy + 20 * s),
           (ox + 160 * s, oy + 90 * s)]
    draw.polygon(pts, fill=fill)
    draw.rectangle([ox, oy + 90 * s, ox + 160 * s, oy + 104 * s], fill=fill)
img = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
crown(d, 48, 70, 1.0, (255, 255, 255, 235))
img.save(f'{OUT}/crown.png'); print('crown.png')

# --- Cờ xanh có vương miện trắng ---
img = Image.new('RGB', (256, 160), (23, 128, 118))
d = ImageDraw.Draw(img)
crown(d, 58, 26, 0.85, (255, 255, 255, 255))
img.save(f'{OUT}/flag.png'); print('flag.png')
print('done')
