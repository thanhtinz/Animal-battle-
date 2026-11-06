#!/usr/bin/env python3
"""Ghép tên quán lên bảng hiệu trống của 4 mặt tiền AI (gen/) -> 10 texture assets/facades/f0..f9.png.
Chạy: python3 tools/make_facades.py (cần gen/*.png từ media.generate_image + assets/font.ttf)"""
from PIL import Image, ImageDraw, ImageFont
import glob, os

ROOT = os.path.join(os.path.dirname(__file__), '..')
GEN = os.path.join(ROOT, 'gen')
OUT = os.path.join(ROOT, 'assets', 'facades')
os.makedirs(OUT, exist_ok=True)

# bảng hiệu (x0,y0,x1,y1 theo tỉ lệ ảnh gốc) của từng mẫu
BASES = {
    'yellow': ('media-generation-facade-yellow-*.png', (0.315, 0.125, 0.690, 0.295)),
    'mint':   ('media-generation-facade-mint-*.png',   (0.175, 0.125, 0.825, 0.360)),
    'cream':  ('media-generation-facade-cream-*.png',  (0.350, 0.155, 0.665, 0.300)),
    'pink':   ('media-generation-facade-pink-*.png',   (0.235, 0.165, 0.765, 0.345)),
}
# 10 nhà theo thứ tự World.OBSTACLES: (tên, mẫu)
HOUSES = [
    ('TẠP HÓA', 'yellow'), ('CHỢ MỚI', 'mint'), ('TRÀ ĐÁ', 'cream'), ('TIỆM CƠM', 'pink'),
    ('CÀ PHÊ', 'cream'), ('HỦ TIẾU', 'yellow'), ('SỬA XE', 'mint'), ('TẠP HÓA 2', 'pink'),
    ('BÁNH MÌ', 'yellow'), ('NET XÓM', 'mint'),
]
CROP_X, CROP_Y = 0.045, 0.01  # cắt viền trắng 2 bên của ảnh AI

def load_base(key):
    pat, board = BASES[key]
    path = glob.glob(os.path.join(GEN, pat))[0]
    im = Image.open(path).convert('RGB')
    w, h = im.size
    im = im.crop((int(w * CROP_X), int(h * CROP_Y), int(w * (1 - CROP_X)), int(h * (1 - CROP_Y))))
    im = im.resize((768, round(768 * im.size[1] / im.size[0])), Image.LANCZOS)
    # quy đổi tọa độ bảng sang ảnh đã cắt
    bx0 = (board[0] - CROP_X) / (1 - 2 * CROP_X)
    bx1 = (board[2] - CROP_X) / (1 - 2 * CROP_X)
    by0 = (board[1] - CROP_Y) / (1 - 2 * CROP_Y)
    by1 = (board[3] - CROP_Y) / (1 - 2 * CROP_Y)
    W, H = im.size
    return im, (bx0 * W, by0 * H, bx1 * W, by1 * H)

def draw_name(im, box, text):
    d = ImageDraw.Draw(im)
    bw, bh = box[2] - box[0], box[3] - box[1]
    size = int(bh * 0.62)
    while size > 10:
        f = ImageFont.truetype(os.path.join(ROOT, 'assets', 'font.ttf'), size)
        tb = d.textbbox((0, 0), text, font=f)
        if tb[2] - tb[0] <= bw * 0.92:
            break
        size -= 4
    tb = d.textbbox((0, 0), text, font=f)
    x = box[0] + (bw - (tb[2] - tb[0])) / 2 - tb[0]
    y = box[1] + (bh - (tb[3] - tb[1])) / 2 - tb[1]
    d.text((x, y), text, font=f, fill=(122, 47, 22), stroke_width=max(1, size // 28), stroke_fill=(90, 32, 14))
    return im

cache = {}
for i, (name, key) in enumerate(HOUSES):
    if key not in cache:
        cache[key] = load_base(key)
    base, box = cache[key]
    im = draw_name(base.copy(), box, name)
    out = os.path.join(OUT, f'f{i}.png')
    im.save(out)
    print('facade', out, name)
print('done')
