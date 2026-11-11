#!/usr/bin/env python3
"""13r polish — REAL brand icons for the login social row.

Tín rejected the hand-drawn glyphs ("Dùng icon css cho gg, fb,
apple"), so these textures are baked from the OFFICIAL shapes:

  icon_google.png    — Google's own multicolour "G" asset
                       (gstatic googleg_standard_color_128dp.png,
                       downloaded verbatim — no redraw).
  icon_facebook.png  — Font Awesome Brands "facebook-f" (U+F39E)
                       in white on a #1877F2 disc, exactly the
                       mark the reference button shows.
  icon_apple.png     — Font Awesome Brands "apple" (U+F179),
                       near-black.
  icon_eye.png       — Font Awesome Solid "eye" (U+F06E), white.
  icon_eye_off.png   — Font Awesome Solid "eye-slash" (U+F070).

Fonts: fa-brands-400.ttf / fa-solid-900.ttf from the user's own
AvatarDK project (assets/fonts/) — the genuine FA6 free files,
verified to contain all three brand codepoints. Glyphs are
rendered at 4-8x and trimmed to their ink box so the client can
centre them optically.
"""
import io
import os
import subprocess

from PIL import Image, ImageDraw, ImageFont

H = os.path.expanduser("~")
FA_BRANDS = H + "/workspace/avatardk-java/assets/fonts/fa-brands-400.ttf"
FA_SOLID = H + "/workspace/avatardk-java/assets/fonts/fa-solid-900.ttf"
OUT = H + "/workspace/empire-age/godot/assets/"
G_URL = "https://www.gstatic.com/images/branding/googleg/1x/googleg_standard_color_128dp.png"
FB_BLUE = (24, 119, 242, 255)  # #1877F2
APPLE_INK = (12, 12, 14, 255)
WHITE = (255, 255, 255, 255)


def glyph(font_path: str, codepoint: int, size: int, colour) -> Image.Image:
    """Render one FA glyph, trimmed to its ink bounding box."""
    font = ImageFont.truetype(font_path, size)
    ch = chr(codepoint)
    canvas = Image.new("RGBA", (size * 2, size * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    d.text((size, size), ch, font=font, fill=colour, anchor="mm")
    bbox = canvas.split()[3].getbbox()
    return canvas.crop(bbox)


def main() -> None:
    # --- Google: the official asset, untouched -------------------
    raw = subprocess.run(["curl", "-sL", "--max-time", "30", G_URL],
                         capture_output=True, check=True).stdout
    g = Image.open(io.BytesIO(raw)).convert("RGBA")
    assert g.size == (128, 128) and g.split()[3].getbbox(), "bad G asset"
    g.save(OUT + "icon_google.png")
    print("icon_google.png", g.size, "(official gstatic asset)")

    # --- Facebook: FA f in white on the #1877F2 disc -------------
    S = 512
    fb = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(fb)
    d.ellipse([0, 0, S - 1, S - 1], fill=FB_BLUE)
    f = glyph(FA_BRANDS, 0xF39E, 430, WHITE)
    f = f.resize((round(f.width * 300 / f.height), 300), Image.LANCZOS)
    fb.alpha_composite(f, (round((S - f.width) / 2), round((S - f.height) / 2) + 6))
    fb.save(OUT + "icon_facebook.png")
    print("icon_facebook.png", fb.size, "(disc + FA facebook-f)")

    # --- Apple: FA glyph, near-black ------------------------------
    ap = glyph(FA_BRANDS, 0xF179, 480, APPLE_INK)
    pad = round(ap.width * 0.03)
    apc = Image.new("RGBA", (ap.width + 2 * pad, ap.height + 2 * pad), (0, 0, 0, 0))
    apc.alpha_composite(ap, (pad, pad))
    apc.save(OUT + "icon_apple.png")
    print("icon_apple.png", apc.size)

    # --- Eyes: FA Solid, white ------------------------------------
    for cp, name in ((0xF06E, "icon_eye.png"), (0xF070, "icon_eye_off.png")):
        e = glyph(FA_SOLID, cp, 400, WHITE)
        e.save(OUT + name)
        print(name, e.size)

    # --- Entry utility column: FA Solid, white --------------------
    # Same glyphs as AvatarDK's EntryUi column (Ui.FA_BELL /
    # FA_TRASH / FA_HEADSET) + the info panel's FA_XMARK close.
    for cp, name in ((0xF0F3, "icon_bell.png"), (0xF2ED, "icon_trash.png"),
                     (0xF590, "icon_headset.png"), (0xF00D, "icon_xmark.png")):
        g2 = glyph(FA_SOLID, cp, 400, WHITE)
        g2.save(OUT + name)
        print(name, g2.size)


if __name__ == "__main__":
    main()
