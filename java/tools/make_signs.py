#!/usr/bin/env python3
"""Sinh texture biển hiệu cho bản Java (chữ nướng vào ảnh, đúng luật asset).
Chạy: python3 tools/make_signs.py  -> assets/signs/sign<i>.png theo thứ tự World.OBSTACLES
"""
from PIL import Image, ImageDraw, ImageFont
import os

SIGNS = ['TẠP HÓA', 'CHỢ MỚI', 'TRÀ ĐÁ', 'TIỆM CƠM', 'CÀ PHÊ',
         'HỦ TIẾU', 'SỬA XE', 'TẠP HÓA 2', 'BÁNH MÌ', 'NET XÓM']
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'signs')
os.makedirs(OUT, exist_ok=True)

for i, text in enumerate(SIGNS):
    img = Image.new('RGB', (512, 128), (32, 36, 44))
    d = ImageDraw.Draw(img)
    d.rectangle([8, 8, 503, 119], outline=(255, 217, 138), width=6)
    size = 58
    while size > 20:
        f = ImageFont.truetype(FONT, size)
        w = d.textlength(text, font=f)
        if w <= 470:
            break
        size -= 4
    d.text(((512 - w) / 2, 64), text, font=f, fill=(255, 217, 138), anchor='lm')
    img.save(os.path.join(OUT, f'sign{i}.png'))
    print('sign%d.png' % i, text)
print('done', len(SIGNS))
