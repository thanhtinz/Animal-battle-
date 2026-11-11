"""Leg-band pixel motion: v2 GIF vs v3 GIF (13n follow-up proof).

For each GIF, average over consecutive frame pairs in the WALK
segment: (a) mean absolute pixel difference in the leg band
(rows 55-85% of frame height), and (b) the fraction of band
pixels changing by > 24 (a zoom-robust "how much of the leg
area actually moves" measure). Cameras are locked in both GIF
sets, so the background is static and band motion is the hero.
v2: 512x320, walk segment frames 9-34. v3: 640x360, east walk
segment frames 1-12.
"""
import numpy as np
from PIL import Image


def measure(path, f0, f1):
    im = Image.open(path)
    prev = None
    tot_diff = 0.0
    tot_frac = 0.0
    cnt = 0
    for i in range(f0, min(f1, im.n_frames)):
        im.seek(i)
        fr = im.convert("RGB")
        w, h = fr.size
        band = np.asarray(
            fr.crop((0, int(h * 0.55), w, int(h * 0.85))), dtype=np.float32)
        if prev is not None:
            d = np.abs(band - prev)
            tot_diff += float(d.mean())
            tot_frac += float((d.max(axis=2) > 24).mean())
            cnt += 1
        prev = band
    return tot_diff / max(cnt, 1), tot_frac / max(cnt, 1), cnt


CHARS = ["ngan_ky", "kim_hoa", "lam_bao", "bach_sa"]
base = "/home/hatch/workspace/empire-age/godot/shots"
print(f"{'char':10} {'v2 diff':>8} {'v3 diff':>8} {'x':>5} "
      f"{'v2 frac':>8} {'v3 frac':>8} {'x':>5}")
for c in CHARS:
    d2, f2, _ = measure(f"{base}/empire_age_char_anim_v2_{c}.gif", 9, 34)
    d3, f3, _ = measure(f"{base}/empire_age_char_walk_v3_{c}.gif", 1, 10)
    print(f"{c:10} {d2:8.2f} {d3:8.2f} {d3 / max(d2, 0.01):5.1f} "
          f"{f2:8.3f} {f3:8.3f} {f3 / max(f2, 0.001):5.1f}")
