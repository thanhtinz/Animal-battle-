#!/usr/bin/env python3
"""Empire Age 14c — synthesised SFX for the 12 new hero skills,
built on build_skill_sfx.py's primitives (same 22050 Hz mono WAV
format, same presentation-only role: Main's SFX pool loads
assets/sfx/<char>_<idx>.wav when present).

Run from the godot/ directory:  python3 tools/build_skill_sfx2.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_skill_sfx import (SR, bandpass, env, fm_bell, lowpass, mix,  # noqa: E402
                             noise, save, sweep, t_axis, whoosh)

rng = np.random.default_rng(20261111)


def zap(dur=0.16, f0=2800, f1=300, seed=3):
    """Electric arc: descending buzz-saw sweep + crackle."""
    s, t = sweep(f0, f1, dur)
    sq = np.sign(np.sin(2 * np.pi * np.cumsum(
        np.linspace(f0, f1, len(t))) / SR)) * 0.3
    cr = bandpass(noise(dur, seed), 3400, q=0.7) * np.exp(-9 * t)
    return (s * 0.5 + sq * 0.4) * np.exp(-5 * t) + cr * 0.7


def fire_bed(dur, seed, fc=500):
    n = lowpass(noise(dur, seed), fc)
    t = t_axis(dur)
    lick = 0.7 + 0.3 * np.sin(2 * np.pi * 7 * t + rng.uniform(0, 6))
    return n * lick


def main():
    # ---- Lôi Chấn (lightning)
    # 1 Lôi Độn: a zip-dash — rising zap into a crackle tail.
    z, _ = sweep(300, 3400, 0.16)
    z *= np.exp(-2.5 * t_axis(0.16)) * 0.5
    save("loi_chan_1.wav", np.concatenate(
        [z, zap(0.22, 2400, 500, 31) * 0.8]))
    # 2 Song Lôi Liên Kích: three chained zaps, each lower.
    parts = []
    for i, f in enumerate((3000, 2400, 1900)):
        seg = zap(0.15, f, 400, 40 + i)
        parts.append(np.concatenate([np.zeros(int(SR * 0.09 * i)), seg]))
    save("loi_chan_2.wav", mix(*parts))
    # 3 Thiên Lôi Phạt Trận: thunder — sub rumble + a hard crack.
    rt = t_axis(1.7)
    rum = lowpass(noise(1.7, 51), 220) * env(rt, 0.02, 0.5, 0.55, 0.7)
    rum += np.sin(2 * np.pi * 44 * rt) * 0.4 * np.exp(-1.8 * rt)
    crack = bandpass(noise(0.4, 52), 2000, q=0.6) * np.exp(-8 * t_axis(0.4))
    save("loi_chan_3.wav", mix(rum, np.concatenate(
        [np.zeros(int(SR * 0.12)), crack])) * 1.0)
    # ---- Xích Diệm (fire)
    # 1 Hỏa Ấn: a branding pulse — low fire swell + ember pops.
    ht = t_axis(0.8)
    bed = fire_bed(0.8, 61) * env(ht, 0.08, 0.3, 0.5, 0.4)
    pops = np.zeros(int(SR * 0.8))
    for i in range(7):
        at = int(rng.uniform(0.05, 0.7) * SR)
        p = bandpass(noise(0.05, 70 + i), 1800, q=2.0) \
            * np.exp(-40 * t_axis(0.05))
        pops[at:at + len(p)] += p * 0.5
    tone, _ = sweep(196, 147, 0.8)
    save("xich_diem_1.wav", mix(bed, pops, tone * 0.2
                                * env(ht, 0.05, 0.3, 0.4, 0.4)))
    # 2 Diệm Phiến Toàn: a broad fan whoosh through fire.
    save("xich_diem_2.wav", mix(whoosh(0.5, 300, 900, 81) * 0.7,
                                fire_bed(0.55, 82) * 0.8))
    # 3 Phượng Hỏa Giáng: phoenix screech dive + roar + boom.
    scr, st = sweep(1900, 620, 0.6)
    scr *= (st / 0.6) ** 1.5 * 0.45
    bt = t_axis(0.8)
    boom = np.sin(2 * np.pi * (58 + 30 * np.exp(-8 * bt)) * bt) \
        * np.exp(-5 * bt)
    roar = fire_bed(0.9, 83, 800) * env(t_axis(0.9), 0.05, 0.3, 0.6, 0.4)
    save("xich_diem_3.wav", np.concatenate(
        [scr, mix(boom, roar[:len(boom)])]))
    # ---- Phong Linh (wind / bow)
    # 1 Truy Phong Tiễn: bowstring twang + a piercing arrow zip.
    tw, tt = sweep(220, 90, 0.12)
    tw *= np.exp(-16 * tt)
    zip_ = whoosh(0.38, 900, 3400, 91)
    save("phong_linh_1.wav", mix(tw * 0.7, np.concatenate(
        [np.zeros(int(SR * 0.05)), zip_])))
    # 2 Tiễn Vũ: a rain of whistling arrows + soft ground ticks.
    rain = np.zeros(int(SR * 1.3))
    for i in range(26):
        at = int(rng.uniform(0, 1.05) * SR)
        wst, wt = sweep(rng.uniform(2400, 3200), rng.uniform(900, 1300), 0.16)
        wst *= np.exp(-7 * wt) * rng.uniform(0.1, 0.3)
        rain[at:at + len(wst)] += wst
        tick = bandpass(noise(0.03, 100 + i), 1200, q=1.5) \
            * np.exp(-50 * t_axis(0.03))
        at2 = min(at + int(0.16 * SR), len(rain) - len(tick))
        rain[at2:at2 + len(tick)] += tick * 0.4
    save("phong_linh_2.wav", rain * env(t_axis(1.3), 0.05, 0.3, 0.7, 0.4))
    # 3 Cuồng Phong Nộ: a vortex — banded wind with a rotating LFO.
    wt2 = t_axis(2.1)
    wind = bandpass(noise(2.1, 111), 700, q=0.8) * 0.8 \
        + bandpass(noise(2.1, 112), 1500, q=1.1) * 0.5
    rot = 0.6 + 0.4 * np.sin(2 * np.pi * 1.4 * wt2)
    save("phong_linh_3.wav", wind * rot * env(wt2, 0.3, 0.5, 0.7, 0.6))
    # ---- Thạch Sơn (earth)
    # 1 Sơn Băng Đạp: leap whoosh into a stone slam.
    slam_t = t_axis(0.6)
    slam = np.sin(2 * np.pi * (48 + 24 * np.exp(-9 * slam_t)) * slam_t) \
        * np.exp(-6 * slam_t)
    slam = mix(slam, lowpass(noise(0.45, 121), 500)
               * np.exp(-8 * t_axis(0.45)) * 0.9)
    save("thach_son_1.wav", np.concatenate(
        [whoosh(0.3, 400, 1500, 122), slam]))
    # 2 Nham Tường: stone grinding up — deep rumble + rock clatter.
    gt = t_axis(1.0)
    grind = lowpass(noise(1.0, 131), 300) * env(gt, 0.25, 0.4, 0.5, 0.3)
    clat = np.zeros(int(SR * 1.0))
    for i in range(12):
        at = int(rng.uniform(0.05, 0.85) * SR)
        c = bandpass(noise(0.06, 140 + i), rng.uniform(500, 1100), q=2.5) \
            * np.exp(-35 * t_axis(0.06))
        clat[at:at + len(c)] += c * rng.uniform(0.3, 0.7)
    save("thach_son_2.wav", mix(grind, clat))
    # 3 Địa Long Lật Đất: sub-earthquake — long sub rumble + cracks.
    qt = t_axis(1.6)
    quake = np.sin(2 * np.pi * 36 * qt) * 0.55 * env(qt, 0.03, 0.5, 0.6, 0.7)
    quake += lowpass(noise(1.6, 151), 180) * env(qt, 0.02, 0.4, 0.6, 0.6)
    cracks = np.zeros(int(SR * 1.6))
    for i in range(9):
        at = int(rng.uniform(0.05, 1.3) * SR)
        c = bandpass(noise(0.12, 160 + i), rng.uniform(700, 1600), q=1.2) \
            * np.exp(-22 * t_axis(0.12))
        cracks[at:at + len(c)] += c * rng.uniform(0.3, 0.6)
    save("thach_son_3.wav", mix(quake, cracks))


if __name__ == "__main__":
    main()
