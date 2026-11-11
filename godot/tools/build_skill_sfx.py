#!/usr/bin/env python3
"""build_skill_sfx.py — Empire Age 13v: procedurally synthesised
hero-skill sound effects (numpy -> 16-bit mono WAV, 22050 Hz).

No audio assets exist in the project and none may be downloaded,
so every skill sound is synthesised from primitives: swept sines
(whooshes via filtered noise), metallic partial stacks (sword
ring, chimes), noise bursts through resonant filters (ice crack,
slam), and slow amplitude swells (blizzard wind, holy hum).

Output: assets/sfx/<skill>.wav for all 12 active skills:
  ngan_ky_1/2/3, kim_hoa_1/2/3, lam_bao_1/2/3, bach_sa_1/2/3
Played by Main's presentation SFX pool on the "SFX" AudioServer
bus (13u settings) — never sim state.
"""
import os

import numpy as np

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "sfx")
rng = np.random.default_rng(20261110)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env(t, a=0.01, d=0.2, sustain=0.0, r=0.1):
    """Simple ADSR-ish envelope over time array t (seconds)."""
    total = t[-1] if len(t) else 0.0
    e = np.zeros_like(t)
    atk = t < a
    e[atk] = t[atk] / max(a, 1e-4)
    dec = (t >= a) & (t < a + d)
    e[dec] = 1.0 - (1.0 - sustain) * (t[dec] - a) / max(d, 1e-4)
    rel_start = max(total - r, a + d)
    sus = (t >= a + d) & (t < rel_start)
    e[sus] = sustain
    rel = t >= rel_start
    e[rel] = sustain * np.clip(1.0 - (t[rel] - rel_start) / max(r, 1e-4), 0, 1) \
        if sustain > 0 else np.clip(1.0 - (t[rel] - rel_start) / max(r, 1e-4), 0, 1) * \
        (e[int(np.argmax(t >= rel_start)) - 1] if np.any(t >= rel_start) else 0.0)
    return np.clip(e, 0.0, 1.0)


def sweep(f0, f1, dur, shape="exp"):
    t = t_axis(dur)
    if shape == "exp":
        f = f0 * (f1 / f0) ** (t / dur)
    else:
        f = f0 + (f1 - f0) * (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph), t


def noise(dur, seed=None):
    r = np.random.default_rng(seed if seed is not None else rng.integers(1 << 30))
    return r.standard_normal(int(SR * dur))


def bandpass(x, f0, f1=None, q=1.0):
    """Crude resonant bandpass via FFT masking (offline synth)."""
    n = len(x)
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    if f1 is None:
        g = np.exp(-0.5 * ((np.log2(np.maximum(freqs, 1.0) / max(f0, 1.0))) ** 2) * (q ** 2))
    else:
        g = ((freqs >= f0) & (freqs <= f1)).astype(float)
        # soften edges
        g = np.convolve(g, np.ones(9) / 9.0, mode="same")
    return np.fft.irfft(spec * g, n)


def lowpass(x, fc):
    n = len(x)
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    g = 1.0 / (1.0 + (freqs / fc) ** 4)
    return np.fft.irfft(spec * g, n)


def fm_bell(fc, fm_ratio, index, dur, decay=4.0):
    t = t_axis(dur)
    mod = np.sin(2 * np.pi * fc * fm_ratio * t) * index * np.exp(-decay * t)
    return np.sin(2 * np.pi * fc * t + mod) * np.exp(-decay * 0.7 * t), t


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def norm(x, peak=0.85):
    m = np.max(np.abs(x)) if len(x) else 0.0
    return x * (peak / m) if m > 1e-6 else x


def save(name, x):
    x = norm(x)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    import wave
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("sfx", name, "%.2fs" % (len(data) / SR))


def whoosh(dur=0.35, f0=500, f1=2400, seed=1):
    n = noise(dur, seed)
    t = t_axis(dur)
    # moving bandpass: chop into windows with rising centre freq
    out = np.zeros_like(n)
    step = 512
    for i in range(0, len(n), step):
        seg = n[i:i + step]
        fr = f0 * (f1 / f0) ** (i / len(n))
        out[i:i + step] = bandpass(seg, fr, q=1.4)
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    return out * e


def main():
    os.makedirs(OUT, exist_ok=True)
    # ---- Ngân Kỵ
    # 1 Xung Phong: fast rising whoosh + short sword ring.
    ring, _ = fm_bell(2350, 1.51, 2.0, 0.35, decay=9.0)
    save("ngan_ky_1.wav", mix(whoosh(0.32, 600, 2600, 11), ring * 0.5))
    # 2 Kiếm Khí: bigger whoosh with a metallic singing edge.
    sing, _ = sweep(900, 340, 0.5)
    t = t_axis(0.5)
    sing *= np.exp(-3.0 * t) * 0.4
    save("ngan_ky_2.wav", mix(whoosh(0.5, 400, 3200, 12), sing,
                              whoosh(0.28, 1800, 500, 13) * 0.6))
    # 3 Vương Kiếm: riser then a deep slam (low sine thud + noise crush).
    riser, _ = sweep(180, 1400, 0.55)
    riser *= (t_axis(0.55) / 0.55) ** 2 * 0.5
    thud_t = t_axis(0.7)
    thud = np.sin(2 * np.pi * (52 + 26 * np.exp(-9 * thud_t)) * thud_t) \
        * np.exp(-5.5 * thud_t)
    crush = lowpass(noise(0.5, 14), 700) * np.exp(-7 * t_axis(0.5))
    slam = mix(thud, crush * 0.8)
    save("ngan_ky_3.wav", np.concatenate([riser, slam]))
    # ---- Kim Hoa
    # 1 Vương Mệnh: soft two-note heal chime.
    c1, _ = fm_bell(880, 2.0, 1.2, 0.7, decay=3.5)
    c2, _ = fm_bell(1318, 2.0, 1.0, 0.8, decay=3.0)
    save("kim_hoa_1.wav", mix(c1, np.concatenate([np.zeros(int(SR * 0.09)), c2])))
    # 2 Hoa Vũ: gentle shimmering rain of tiny bells.
    rain = np.zeros(int(SR * 1.1))
    r = np.random.default_rng(7)
    for i in range(46):
        f = r.uniform(1800, 4200)
        b, _ = fm_bell(f, 2.76, 0.8, 0.22, decay=14.0)
        at = int(r.uniform(0, 0.85) * SR)
        rain[at:at + len(b)] += b * r.uniform(0.15, 0.5)
    save("kim_hoa_2.wav", rain * env(t_axis(1.1), 0.08, 0.3, 0.7, 0.35))
    # 3 Vạn Hoa: blooming chord swell (major arpeggio of bells + airy pad).
    bloom = np.zeros(int(SR * 1.6))
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        b, _ = fm_bell(f, 2.0, 1.4, 1.1, decay=2.2)
        at = int(i * 0.09 * SR)
        n = min(len(b), len(bloom) - at)
        bloom[at:at + n] += b[:n] * 0.55
    bloom = bloom[:int(SR * 1.3)]
    pad, _ = sweep(262, 262, 1.3)
    bloom += pad * 0.08 * env(t_axis(1.3), 0.3, 0.5, 0.6, 0.5)
    save("kim_hoa_3.wav", bloom)
    # ---- Lam Bào
    # 1 Băng Phong: frost burst — crackling noise + cold shimmer.
    crack = bandpass(noise(0.45, 21), 2600, q=0.8) * np.exp(-6 * t_axis(0.45))
    shimmer, _ = sweep(2400, 900, 0.5)
    shimmer *= np.exp(-4 * t_axis(0.5)) * 0.35
    save("lam_bao_1.wav", mix(crack, shimmer))
    # 2 Thương Băng: throw whoosh into a hard ice crack.
    cr_t = t_axis(0.3)
    hard = bandpass(noise(0.3, 22), 1500, 5200) * np.exp(-11 * cr_t)
    hard += np.sin(2 * np.pi * 190 * cr_t) * np.exp(-14 * cr_t) * 0.7
    save("lam_bao_2.wav", np.concatenate([whoosh(0.28, 700, 2600, 23), hard]))
    # 3 Băng Hà: blizzard wind — slow-swell banded noise, 2.2 s.
    w = bandpass(noise(2.2, 24), 800, q=0.6)
    w2 = bandpass(noise(2.2, 25), 1600, q=0.9)
    tw = t_axis(2.2)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * 0.45 * tw + 0.7) \
        * np.sin(2 * np.pi * 0.13 * tw)
    save("lam_bao_3.wav", (w * 0.8 + w2 * 0.5) * gust
         * env(tw, 0.35, 0.4, 0.75, 0.6))
    # ---- Bạch Sa
    # 1 Kết Giới: warm holy tone rising and settling.
    h1, _ = sweep(392, 392, 0.9)
    h2, _ = sweep(587, 587, 0.9)
    th = t_axis(0.9)
    save("bach_sa_1.wav", (h1 * 0.4 + h2 * 0.28 + np.sin(2 * np.pi * 784 * th) * 0.15)
         * env(th, 0.12, 0.3, 0.55, 0.4))
    # 2 Phán Xét: descending light strike — bright zap + choir-ish stack.
    zap, _ = sweep(2600, 300, 0.3)
    zap *= np.exp(-6 * t_axis(0.3)) * 0.6
    choir = np.zeros(int(SR * 0.65))
    for f in (440, 554, 659):
        s, _ = sweep(f, f, 0.65)
        choir += s * 0.16 * env(t_axis(0.65), 0.03, 0.2, 0.5, 0.3)
    save("bach_sa_2.wav", mix(zap, choir))
    # 3 Thiên Màn: dome rise — deep hum swelling with a high halo shimmer.
    hum_t = t_axis(1.4)
    hum = (np.sin(2 * np.pi * 98 * hum_t) * 0.5
           + np.sin(2 * np.pi * 196 * hum_t) * 0.3
           + np.sin(2 * np.pi * 294 * hum_t) * 0.18) \
        * env(hum_t, 0.4, 0.4, 0.7, 0.5)
    halo, _ = fm_bell(1568, 2.0, 0.7, 1.2, decay=2.4)
    save("bach_sa_3.wav", mix(hum, halo * 0.4))


if __name__ == "__main__":
    main()
