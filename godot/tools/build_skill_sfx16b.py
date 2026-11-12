#!/usr/bin/env python3
"""Empire Age 16b — synthesised SFX for the 8 new western heroes'
skill 1, built on build_skill_sfx.py's primitives (same 22050 Hz
mono WAV format, same presentation-only role: Main's SFX pool
loads assets/sfx/<hero>_1.wav when present).

Signatures:
  knight    shield clang + deep horn swell
  berserker heavy spinning whoosh + chop
  archer    multiple arrow whistles raining
  mage      rising rumble into a boom
  paladin   warm bell chime + soft choir pad
  dragoon   fast dash whoosh + piercing stab
  assassin  quick shadow swish + sharp stab
  ranger    5 rapid sword slashes

Run from the godot/ directory:  python3 tools/build_skill_sfx16b.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_skill_sfx import (SR, bandpass, env, fm_bell, lowpass, mix,  # noqa: E402
                             noise, save, sweep, t_axis, whoosh)

rng = np.random.default_rng(20261112)


def delayed(x, delay_s):
    return np.concatenate([np.zeros(int(SR * delay_s)), x])


def main():
    # ---- Knight: shield clang + deep horn swell (0.95 s)
    clang, _ = fm_bell(1568, 1.51, 2.4, 0.4, decay=10.0)
    clang2, _ = fm_bell(2217, 1.34, 1.6, 0.3, decay=12.0)
    burst = bandpass(noise(0.12, 161), 2800, q=0.9) \
        * np.exp(-22 * t_axis(0.12))
    ht = t_axis(0.95)
    horn = (np.sin(2 * np.pi * 98 * ht) * 0.45
            + np.sin(2 * np.pi * 147 * ht) * 0.30
            + np.sin(2 * np.pi * 196 * ht) * 0.20
            + np.sin(2 * np.pi * 294 * ht) * 0.10) \
        * env(ht, 0.16, 0.3, 0.55, 0.35)
    save("knight_1.wav", mix(clang * 0.8, clang2 * 0.5, burst * 0.7,
                             delayed(horn, 0.06)))

    # ---- Berserker: heavy spinning whoosh + chop (0.85 s)
    spin = mix(whoosh(0.42, 240, 1100, 171), whoosh(0.34, 900, 300, 172) * 0.8)
    ct = t_axis(0.3)
    chop = lowpass(noise(0.3, 173), 900) * np.exp(-10 * ct) * 0.9
    chop += np.sin(2 * np.pi * (74 + 30 * np.exp(-9 * ct)) * ct) \
        * np.exp(-7 * ct)
    save("berserker_1.wav", np.concatenate([spin, chop]))

    # ---- Archer: rain of arrow whistles (1.1 s)
    rain = np.zeros(int(SR * 1.1))
    for i in range(8):
        at = int(rng.uniform(0.0, 0.82) * SR)
        wst, wt = sweep(rng.uniform(2600, 3300), rng.uniform(1000, 1400), 0.17)
        wst *= np.exp(-6 * wt) * rng.uniform(0.16, 0.34)
        rain[at:at + len(wst)] += wst
        tick = bandpass(noise(0.03, 180 + i), 1300, q=1.6) \
            * np.exp(-48 * t_axis(0.03))
        at2 = min(at + int(0.17 * SR), len(rain) - len(tick))
        rain[at2:at2 + len(tick)] += tick * 0.45
    save("archer_1.wav", rain * env(t_axis(1.1), 0.04, 0.3, 0.7, 0.35))

    # ---- Mage: rising rumble into a boom (1.15 s)
    rt = t_axis(0.62)
    rumble = lowpass(noise(0.62, 191), 300) * (rt / 0.62) ** 1.6
    riser, _ = sweep(58, 190, 0.62)
    riser *= (rt / 0.62) ** 2 * 0.4
    bt = t_axis(0.53)
    boom = np.sin(2 * np.pi * (96 - 52 * (1 - np.exp(-6 * bt))) * bt) \
        * np.exp(-6.5 * bt)
    boom += lowpass(noise(0.53, 192), 650) * np.exp(-8 * bt) * 0.8
    spark, _ = fm_bell(2637, 2.4, 1.0, 0.3, decay=11.0)
    save("mage_1.wav", np.concatenate(
        [mix(rumble, riser), mix(boom, spark * 0.35)]))

    # ---- Paladin: warm bell chime + soft choir pad (1.15 s)
    b1, _ = fm_bell(1046.5, 2.0, 1.1, 0.9, decay=2.8)
    b2, _ = fm_bell(1318.5, 2.0, 0.9, 0.9, decay=2.6)
    pt = t_axis(1.15)
    pad = np.zeros_like(pt)
    for f, g in ((523.25, 0.20), (659.25, 0.16), (783.99, 0.14)):
        s, _ = sweep(f, f, 1.15)
        pad += s * g
    pad *= env(pt, 0.18, 0.35, 0.55, 0.45)
    save("paladin_1.wav", mix(b1 * 0.75, delayed(b2 * 0.6, 0.13), pad))

    # ---- Dragoon: fast dash whoosh + piercing stab (0.62 s)
    dash = whoosh(0.3, 700, 3600, 201)
    st_t = t_axis(0.32)
    stab = bandpass(noise(0.32, 202), 2400, q=1.0) * np.exp(-13 * st_t)
    ping, _ = fm_bell(2959, 1.5, 1.4, 0.28, decay=13.0)
    stab = mix(stab * 0.8, ping * 0.55,
               np.sin(2 * np.pi * 150 * st_t) * np.exp(-16 * st_t) * 0.4)
    save("dragoon_1.wav", np.concatenate([dash, stab]))

    # ---- Assassin: quick shadow swish + sharp stab (0.5 s)
    swish = whoosh(0.22, 2600, 500, 211)
    kt = t_axis(0.28)
    stab2 = bandpass(noise(0.28, 212), 3400, q=0.9) * np.exp(-16 * kt)
    ring2, _ = fm_bell(3520, 1.51, 1.2, 0.2, decay=16.0)
    save("assassin_1.wav", np.concatenate(
        [swish, mix(stab2 * 0.85, ring2 * 0.5)]))

    # ---- Ranger: 5 rapid sword slashes (0.95 s)
    parts = []
    for i in range(5):
        seg = whoosh(0.2, 500 if i % 2 == 0 else 2400,
                     2600 if i % 2 == 0 else 600, 220 + i)
        r, _ = fm_bell(2350 - i * 120, 1.51, 1.2, 0.16, decay=14.0)
        parts.append(delayed(mix(seg, r * 0.35), i * 0.15))
    save("ranger_1.wav", mix(*parts))


if __name__ == "__main__":
    main()
