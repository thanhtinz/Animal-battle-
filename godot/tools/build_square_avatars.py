#!/usr/bin/env python3
"""Build the SQUARE profile avatars (13m follow-up, Tín: "Làm lại
avatar cho khớp khung vuông").

The supplied portraits bake a decorative octagonal frame into the
art, so inside the game's plain square gold frames they read as a
frame-in-a-frame and never fill the square. This script crops a
clean square bust (head + shoulders) from INSIDE each portrait's
aperture — the baked frame, its rim and the top diamond ornament
are all excluded — and exports a 320x320 texture per character.

Sources (Tín's originals, ~/workspace/user/files/):
  * trio strip  E0DC965F-...jpg  (1215x355): ngan_ky | kim_hoa | lam_bao
  * single      C71900FC-...jpg  (422x353):  bach_sa

Aperture geometry (measured on the strip, identical template in
all three cells; frame outer ~x36..368 / y22..332 per cell):
picture area x52..352, y42..315, corner diagonals ~33px. Every
crop box below is a square whose four corners were checked
against all four diagonals plus the straight edges, with margin.

Output: assets/avatars/avatar_sq_<id>.png (320x320, Lanczos +
gentle unsharp so it stays crisp large and clean small).
Characters.avatar_for() points at these; the framed originals
(king_avatar_<id>.png) stay for the collection-screen cards.
"""
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
USER_FILES = ROOT.parent.parent / "user" / "files"
OUT_DIR = ROOT / "assets" / "avatars"
OUT_SIZE = 320

STRIP = USER_FILES / "E0DC965F-1B82-4ABA-BC2C-33A1AAC33EDA-photo-83293D31-156F-4B8C-AEA9-AA08EB75D783.jpg"
SINGLE = USER_FILES / "C71900FC-E861-48DF-8DBA-70BDBA04D0D0-photo-4C86DE8A-A135-4B7F-99CC-E32E3A807C20.jpg"

# (source, crop box x0, y0, x1, y1) — squares inscribed in the
# portrait aperture, centred on each face.
CROPS = {
    "ngan_ky": (STRIP, (128, 70, 338, 280)),
    "kim_hoa": (STRIP, (535, 74, 745, 284)),
    "lam_bao": (STRIP, (946, 74, 1156, 284)),
    "bach_sa": (SINGLE, (142, 65, 357, 280)),
}


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    cache: dict[Path, Image.Image] = {}
    for char_id, (src, box) in CROPS.items():
        if src not in cache:
            cache[src] = Image.open(src).convert("RGB")
        crop = cache[src].crop(box)
        assert crop.width == crop.height, (char_id, crop.size)
        out = crop.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
        out = out.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
        path = OUT_DIR / f"avatar_sq_{char_id}.png"
        out.save(path)
        print(f"{char_id}: {box} -> {path} {out.size}")


if __name__ == "__main__":
    main()
