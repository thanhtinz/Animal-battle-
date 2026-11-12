#!/usr/bin/env python3
"""Empire Age 17d — avatar-frame asset pipeline (spec §7.2A).

Godot cannot play the owner's animated GIFs natively, so each
frame GIF in art_candidates/avatar_frames/raw/ is extracted into
a sprite sheet under assets/avatar_frames/:

    frame_XX_sheet.png   grid sheet, 256px cells, frames in
                         reading order (left-to-right, top-down)
    manifest.json        per frame id: {frames, cols, rows,
                         cell, fps, aperture:[x0,y0,x1,y1]}

fps is the GIF's average frame rate (total duration / frames);
the aperture (the frame's inner window, normalised 0..1) comes
from art_candidates/avatar_frames/aperture_calibration.json —
the measured centre-cross alpha scan. The client helper
(scripts/avatar_frame.gd) fits the avatar as a centred square
inscribed in that window.

Repeatable: re-running rebuilds every sheet + the manifest.
"""
import json
import math
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # godot/
SRC_DIR = os.path.join(ROOT, "..", "art_candidates", "avatar_frames", "raw")
CAL_PATH = os.path.join(ROOT, "..", "art_candidates", "avatar_frames",
                        "aperture_calibration.json")
DST_DIR = os.path.join(ROOT, "assets", "avatar_frames")
CELL = 256
FRAME_IDS = ["frame_01", "frame_03", "frame_04", "frame_05", "frame_06",
             "frame_07", "frame_08", "frame_09", "frame_10", "frame_11",
             "frame_12"]


def extract_frames(path):
    """Composite a GIF into full-canvas RGBA frames (disposal-aware
    enough for full-frame exports: every source frame here is a
    full 1064x1064 tile, verified below)."""
    im = Image.open(path)
    frames = []
    durations = []
    base = Image.new("RGBA", im.size, (0, 0, 0, 0))
    for i in range(getattr(im, "n_frames", 1)):
        im.seek(i)
        tile = im.convert("RGBA")
        if tile.size != im.size:
            raise ValueError("%s frame %d is a partial tile %s — "
                             "this pipeline expects full-frame GIFs"
                             % (path, i, tile.size))
        composed = base.copy()
        composed.alpha_composite(tile)
        frames.append(composed)
        durations.append(int(im.info.get("duration", 100)) or 100)
        if im.disposal_method == 2:
            base = Image.new("RGBA", im.size, (0, 0, 0, 0))
        elif im.disposal_method == 3:
            pass  # restore to previous: keep the old base
        else:
            base = composed
    return frames, durations


def main() -> int:
    with open(CAL_PATH, "r", encoding="utf-8") as f:
        calibration = json.load(f)
    os.makedirs(DST_DIR, exist_ok=True)
    manifest = {}
    for fid in FRAME_IDS:
        src = os.path.join(SRC_DIR, fid + ".gif")
        if not os.path.exists(src):
            print("MISSING source:", src)
            return 1
        frames, durations = extract_frames(src)
        n = len(frames)
        cols = int(math.ceil(math.sqrt(n)))
        rows = int(math.ceil(n / float(cols)))
        sheet = Image.new("RGBA", (cols * CELL, rows * CELL), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            small = fr.resize((CELL, CELL), Image.LANCZOS)
            sheet.paste(small, ((i % cols) * CELL, (i // cols) * CELL))
        out = os.path.join(DST_DIR, fid + "_sheet.png")
        sheet.save(out)
        total_ms = float(sum(durations))
        fps = round(n * 1000.0 / total_ms, 2) if total_ms > 0 else 10.0
        manifest[fid] = {
            "frames": n, "cols": cols, "rows": rows, "cell": CELL,
            "fps": fps,
            "aperture": calibration[fid],
            "sheet": "res://assets/avatar_frames/" + fid + "_sheet.png",
        }
        print("%s: %d frames -> %dx%d sheet @ %.2f fps" %
              (fid, n, cols, rows, fps))
    with open(os.path.join(DST_DIR, "manifest.json"), "w",
              encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print("manifest.json written with", len(manifest), "frames")
    return 0


if __name__ == "__main__":
    sys.exit(main())
