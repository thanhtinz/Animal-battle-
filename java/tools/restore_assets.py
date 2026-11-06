#!/usr/bin/env python3
"""Giải mã assets-src/*.b64 -> assets/ (font + biển hiệu). Chạy 1 lần sau khi clone.
Biển hiệu cũng sinh lại được bằng tools/make_signs.py; font thì chỉ có ở dạng .b64 này."""
import base64, os

ROOT = os.path.join(os.path.dirname(__file__), '..')

def dec(src, dst):
    raw = ''.join(open(src).read().split())
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, 'wb').write(base64.b64decode(raw))
    print('restored', dst)

dec(f'{ROOT}/assets-src/font.ttf.b64', f'{ROOT}/assets/font.ttf')
signs = f'{ROOT}/assets-src/signs'
for name in sorted(os.listdir(signs)):
    if name.endswith('.png.b64'):
        dec(os.path.join(signs, name), f'{ROOT}/assets/signs/{name[:-4]}')
for name in sorted(os.listdir(f'{ROOT}/assets-src')):
    if name.endswith('.png.b64'):
        dec(f'{ROOT}/assets-src/{name}', f'{ROOT}/assets/{name[:-4]}')
print('done')
