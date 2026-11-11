#!/usr/bin/env python3
"""Roster sheet v2 (13n): the four main characters WITH their
weapons — portrait + the rig posed at rest holding the weapon
(the front 's' rig composed from assets/hero_parts + the weapon
layer from tools/build_hero_rig.py data), name + weapon label —
plus the three locked skins row. Output:
shots/empire_age_characters_v2.png.
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = json.load(open(os.path.join(ROOT, "assets", "hero_rig.json")))

CHARS = [
    ("ngan_ky", "Ngân Kỵ", "Kiếm dài — bạc, chuôi vàng, ngọc đỏ"),
    ("kim_hoa", "Kim Hoa", "Hoa trượng — vàng, hoa trắng, ngọc hồng"),
    ("lam_bao", "Lam Bào", "Thương băng — cán dài, mũi băng xanh nhạt"),
    ("bach_sa", "Bạch Sa", "Thánh trượng — vàng, đầu mặt trời"),
]
SKINS = [
    ("vo_hiep", "Võ Hiệp"), ("bach_y", "Bạch Y"), ("tu_y", "Tử Y"),
]

FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts"]


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def compose(cid, d8):
    """Rest pose: parts in z order + weapon (same math as the
    game's _rig_build_dir / _rig_pose follow mode, PIL sign
    convention)."""
    ch = DATA["chars"][cid]
    d = ch["dirs"][d8]
    W, H = d["canvas"]
    pad = 90
    canvas = Image.new("RGBA", (W + 2 * pad, H + 2 * pad), (0, 0, 0, 0))
    layers = []
    for key, spec in sorted(d["parts"].items(),
                            key=lambda kv: (kv[1]["z"], kv[0])):
        layers.append((spec["z"], key))
    wspec = d["weapon"]
    layers.append((wspec["z"], "__weapon__"))
    for z, key in sorted(layers):
        if key == "__weapon__":
            spec = ch["weapon"]
            img = Image.open(os.path.join(ROOT, "assets", spec["tex"])).convert("RGBA")
            rest = wspec["rest"]
            scratch = Image.new("RGBA", (180, 180), (0, 0, 0, 0))
            scratch.alpha_composite(img, (0, 0))
            rotated = scratch.rotate(rest, resample=Image.BICUBIC,
                                     center=(spec["grip"][0], spec["grip"][1]))
            hx, hy = wspec["hand"]
            ox = hx - spec["grip"][0]
            oy = hy - spec["grip"][1]
            canvas.alpha_composite(rotated, (pad + int(ox), pad + int(oy)))
        else:
            spec = d["parts"][key]
            img = Image.open(os.path.join(ROOT, "assets", spec["tex"])).convert("RGBA")
            canvas.alpha_composite(img, (pad, pad))
    return canvas.crop(canvas.getbbox())


def main():
    CW, CH = 322, 505
    sheet = Image.new("RGB", (CW * 4 + 26, 990), (16, 19, 31))
    dr = ImageDraw.Draw(sheet)
    dr.text((20, 14), "NHÂN VẬT CHÍNH — VŨ KHÍ & RIG ANIMATION (13n)",
            font=font(22, True), fill=(240, 205, 110))
    for i, (cid, name, wlabel) in enumerate(CHARS):
        x = 6 + i * (CW + 5)
        dr.rounded_rectangle([x, 52, x + CW, 52 + CH], radius=10,
                             outline=(120, 100, 55), width=2)
        port = Image.open(os.path.join(
            ROOT, "assets", "avatars", "king_avatar_%s.png" % cid)).convert("RGBA")
        port = ImageOps.contain(port, (150, 150))
        sheet.paste(port, (x + (CW - port.width) // 2, 66), port)
        pose = compose(cid, "s")
        pose = ImageOps.contain(pose, (200, 240), method=Image.NEAREST)
        px = x + (CW - pose.width) // 2
        sheet.paste(pose, (px, 226), pose)
        t = name
        tw = dr.textlength(t, font=font(24, True))
        dr.text((x + (CW - tw) / 2, 470), t, font=font(24, True),
                fill=(240, 224, 178))
        words = wlabel.split(" — ")
        for j, ln in enumerate(words):
            tw = dr.textlength(ln, font=font(14))
            dr.text((x + (CW - tw) / 2, 502 + j * 20), ln,
                    font=font(14), fill=(196, 204, 224))
    # Skins row (locked, static procedural art — unchanged by 13n).
    dr.text((20, 578), "SKIN CAO CẤP — SẮP MỞ BÁN (chỉ thay ngoại hình; "
            "giữ animation thủ tục 13j)", font=font(17, True),
            fill=(168, 175, 199))
    for i, (sid, name) in enumerate(SKINS):
        x = 6 + i * (CW + 5)
        dr.rounded_rectangle([x, 614, x + CW, 614 + 330], radius=10,
                             outline=(90, 96, 120), width=2)
        pose = Image.open(os.path.join(
            ROOT, "assets", "king_%s_s.png" % sid)).convert("RGBA")
        pose = ImageOps.contain(pose, (190, 220), method=Image.NEAREST)
        px = x + (CW - pose.width) // 2
        sheet.paste(pose, (px, 628), pose)
        tw = dr.textlength(name, font=font(22, True))
        dr.text((x + (CW - tw) / 2, 862), name, font=font(22, True),
                fill=(200, 205, 220))
        t2 = "Chỉ thay ngoại hình"
        tw = dr.textlength(t2, font=font(14))
        dr.text((x + (CW - tw) / 2, 898), t2, font=font(14),
                fill=(150, 156, 175))
    out = os.path.join(ROOT, "shots", "empire_age_characters_v2.png")
    sheet.save(out)
    print("wrote", out, sheet.size)


if __name__ == "__main__":
    main()
