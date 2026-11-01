"""The Hullscrap palette: pad, pluck, bass, lead, keys, bells, music box, drums and textures.
Instruments return mono (or stereo for the pad) float32 arrays. Renders are cached by their arguments, so a
repeated note is built once; never modify a returned array in place."""
import functools
import numpy as np
import synth as S
from synth import SR, hz

cache = functools.lru_cache(maxsize=None)


def _t(n):
    return np.arange(n, dtype=np.float32) / SR


def _tail(y, ms=30):
    """Cosine fade over the last ms so a hit that is cut at its buffer end never clicks."""
    k = min(len(y) // 2, int(ms * SR / 1000))
    y = y.copy()
    y[-k:] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)).astype(np.float32)
    return y


def _norm(y, peak=1.0):
    return (y * (peak / max(1e-9, float(np.abs(y).max())))).astype(np.float32)


# ---------- pad: three detuned saws (+-7 cents) ----------
@cache
def pad(midi, dur, att=1.4, rel=2.4, detune=7.0, drift=3.0, seed=0):
    """Returns a stereo note. The low-pass sweep and the chorus are applied to the whole part by the song."""
    rng = np.random.default_rng(seed * 1000 + int(midi))
    n_on = int(dur * SR)
    n = n_on + int(rel * SR)
    t = np.arange(n) / SR
    out = np.zeros((2, n), np.float32)
    for dc, pan in ((-detune, -0.75), (0.0, 0.0), (detune, 0.75)):
        f = hz(midi + dc / 100.0) * 2.0 ** (drift * np.sin(2 * np.pi * rng.uniform(0.07, 0.23) * t + rng.uniform(0, 6.28)) / 1200)
        dt = f / SR
        ph = (rng.random() + np.cumsum(dt)) % 1.0
        y = S.saw_blep(ph, dt)
        th = (pan + 1) * np.pi / 4
        out[0] += y * np.float32(np.cos(th))
        out[1] += y * np.float32(np.sin(th))
    return out * S.gate_env(n_on, n, att, rel)[None, :] * np.float32(0.33)


# ---------- pluck: a decaying saw/square whose brightness (filter envelope) decays faster than its level ----------
@cache
def pluck(midi, ring=1.3, wave="saw", bright=1.0, decay=0.55, seed=0):
    f = float(hz(midi))
    n = int(ring * SR)
    t = _t(n)
    K = int(max(2, min(22, 9000 // f)))
    k = np.arange(1, K + 1, dtype=np.float32)[:, None]
    amp = (1.0 / k) * (((k % 2) == 1) if wave == "square" else 1.0)
    tau0 = float(np.clip(decay * (1.5 - 0.009 * (midi - 40)), 0.18, 2.0))
    rate = (1 + (k - 1) * 0.5 / bright) / tau0
    y = (amp * np.sin(2 * np.pi * f * k * t[None, :]) * np.exp(-rate * t[None, :])).sum(0)
    rng = np.random.default_rng(seed + int(midi))
    click = S.filt(rng.standard_normal(int(0.012 * SR)).astype(np.float32), hp=2500) * np.exp(-_t(int(0.012 * SR)) / 0.002)
    y[:len(click)] += click * 0.35 * float(np.abs(y).max())
    y *= np.minimum(1.0, t / 0.0015) * np.minimum(1.0, (ring - t) / 0.08)
    return _norm(y, 0.9)


# ---------- bass: sine sub plus a filtered saw ----------
@cache
def bass(midi, dur, cutoff=520.0, drive=1.6, sub=1.0, saw=0.55, rel=0.09, att=0.008, snap=1.4):
    f = float(hz(midi))
    n_on = int(dur * SR)
    n = n_on + int(rel * SR * 2)
    t = _t(n)
    K = int(max(2, min(48, 3500 // f)))
    k = np.arange(1, K + 1, dtype=np.float32)[:, None]
    fc = cutoff * (1 + snap * np.exp(-t / 0.1))[None, :]
    s = (np.sin(2 * np.pi * f * k * t[None, :]) / k / np.sqrt(1 + (k * f / fc) ** 4)).sum(0)
    y = np.tanh(drive * (sub * np.sin(2 * np.pi * f * t) * 0.8 + saw * s)) / np.tanh(drive)
    return (y * S.gate_env(n_on, n, att, rel * 2)).astype(np.float32)


# ---------- lead: a soft triangle with gentle vibrato ----------
@cache
def lead(midi, dur, vib=11.0, vrate=5.1, vdelay=0.35, att=0.05, rel=0.4, tone=0.22, grit=0.0):
    f = float(hz(midi))
    n_on = int(dur * SR)
    n = n_on + int(rel * SR)
    t = np.arange(n) / SR
    cents = vib * np.clip((t - vdelay) / 0.5, 0, 1) * np.sin(2 * np.pi * vrate * t)
    ph = np.cumsum(f * 2.0 ** (cents / 1200) / SR)
    y = S.tri_from(ph) + tone * np.sin(2 * np.pi * ph * 2).astype(np.float32)
    if grit:   # combat variant: saw and square edge
        y = y + grit * (S.saw_blep(ph % 1.0, f / SR) + 0.6 * np.sign(np.sin(2 * np.pi * ph)).astype(np.float32))
        y = S.filt(y, lp=3200)
    return (y * S.gate_env(n_on, n, att, rel) * 0.5).astype(np.float32)


# ---------- keys: a 2-operator FM electric piano ----------
@cache
def keys(midi, dur, vel=3, idx=2.0, rel=0.5, tau=1.1):
    f = float(hz(midi))
    n_on = int(dur * SR)
    n = n_on + int(rel * SR)
    t = _t(n)
    v = vel / 4.0
    I = 0.2 + idx * v * np.exp(-t / 0.4) + 1.6 * v * np.exp(-t / 0.018)
    y = np.sin(2 * np.pi * f * t + I * np.sin(2 * np.pi * f * t))
    amp = np.exp(-t / (tau * (1.6 - 0.008 * (midi - 40)))) * np.minimum(1.0, t / 0.002)
    rl = np.ones(n, np.float32)
    rl[n_on:] = np.exp(-(t[n_on:] - t[n_on]) / (rel / 4.5))
    return _tail((y * amp * rl * 0.5 * (0.35 + 0.65 * v)).astype(np.float32), 40)


# ---------- bells: FM bell and music box ----------
@cache
def bell(midi, ring=3.2, ratio=3.5, index=3.0, tau=1.1, att=0.003):
    f = float(hz(midi))
    n = int(ring * SR)
    t = _t(n)
    I = index * np.exp(-t / (0.45 * tau))
    y = np.sin(2 * np.pi * f * t + I * np.sin(2 * np.pi * ratio * f * t)) * np.exp(-t / tau)
    y += 0.22 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / (0.5 * tau))
    y *= np.minimum(1.0, t / att) * np.minimum(1.0, (ring - t) / 0.2)
    return _norm(y, 0.8)


@cache
def musicbox(midi, ring=3.4, cents=0.0, beat=0.0, tau=1.5, seed=0):
    """Comb-tine partials (1, 2.76, 5.40, 8.93). cents detunes the whole note; beat adds a slightly sharp twin."""
    f = float(hz(midi + cents / 100.0))
    n = int(ring * SR)
    t = _t(n)
    y = np.zeros(n, np.float32)
    for r, a, d in ((1.0, 1.0, 1.0), (2.756, 0.33, 0.55), (5.404, 0.16, 0.3), (8.933, 0.07, 0.18)):
        if f * r > 14000:
            continue
        e = np.exp(-t / (tau * d))
        y += a * np.sin(2 * np.pi * f * r * t) * e
        if beat:
            y += 0.6 * a * np.sin(2 * np.pi * f * r * 2 ** (beat / 1200) * t + 1.3) * e
    rng = np.random.default_rng(seed + int(midi))
    nz = rng.standard_normal(int(0.01 * SR)).astype(np.float32)
    y[:len(nz)] += S.filt(nz, hp=3000) * np.exp(-_t(len(nz)) / 0.002) * 0.25
    y *= np.minimum(1.0, t / 0.001) * np.minimum(1.0, (ring - t) / 0.2)
    return _norm(y, 0.8)


@cache
def sine_ping(midi, ring=2.0, tau=0.7):
    t = _t(int(ring * SR))
    y = np.sin(2 * np.pi * float(hz(midi)) * t) * np.exp(-t / tau) * np.minimum(1.0, t / 0.004)
    return (y * np.minimum(1.0, (ring - t) / 0.2) * 0.8).astype(np.float32)


# ---------- drums (all lightly bit-crushed to 12 bits at full scale, then mixed down) ----------
def _noise(n, seed):
    return np.random.default_rng(seed).standard_normal(n).astype(np.float32)


@cache
def kick(seed=0, f0=150.0, f1=46.0, tau_f=0.032, decay=0.17, click=0.25, dur=0.5):
    n = int(dur * SR)
    t = _t(n)
    fi = f1 + (f0 - f1) * np.exp(-t / tau_f)
    y = np.sin(2 * np.pi * np.cumsum(fi) / SR) * np.exp(-t / decay)
    y += click * S.filt(_noise(n, seed), hp=1500) * np.exp(-t / 0.004)
    return S.crush(_tail(_norm(np.tanh(1.6 * y), 0.95)))


@cache
def snare(seed=0, tone=185.0, decay=0.1, noise_hp=1800, dur=0.35, body=0.6):
    n = int(dur * SR)
    t = _t(n)
    nz = S.filt(_noise(n, seed), hp=noise_hp, lp=9000) * np.exp(-t / decay)
    tn = np.sin(2 * np.pi * (tone + 60 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.07) * body
    return S.crush(_tail(_norm(nz + tn, 0.9)))


@cache
def hat(seed=0, open_=False, hp=7000):
    n = int((0.38 if open_ else 0.09) * SR)
    t = _t(n)
    y = S.filt(_noise(n, seed), hp=hp, order=2) * np.exp(-t / (0.12 if open_ else 0.018))
    return S.crush(_tail(_norm(y, 0.8)))


@cache
def rim(seed=0):
    n = int(0.08 * SR)
    t = _t(n)
    y = (np.sin(2 * np.pi * 1750 * t) * 0.6 + np.sin(2 * np.pi * 455 * t)) * np.exp(-t / 0.012)
    y += 0.5 * S.filt(_noise(n, seed), hp=2500) * np.exp(-t / 0.003)
    return S.crush(_tail(_norm(y, 0.85)))


@cache
def brush(seed=0, dur=0.32, lo=1200, hi=7000, swell=0.07):
    """A swished brush: band noise that swells in and falls away."""
    n = int(dur * SR)
    t = _t(n)
    e = np.minimum(1.0, t / swell) * np.exp(-np.maximum(t - swell, 0) / (dur * 0.35))
    return S.crush(_tail(_norm(S.band(_noise(n, seed), lo, hi) * e, 0.8)))


@cache
def clank(seed=0, base=480.0, decay=0.6, dur=1.4):
    """Scrap-metal clank: inharmonic partials that ring, over a noise strike."""
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = _t(n)
    y = np.zeros(n, np.float32)
    for r, a, d in ((1.0, 1.0, 1.0), (2.32, 0.8, 0.7), (3.87, 0.6, 0.5), (5.43, 0.45, 0.35), (7.11, 0.3, 0.25), (9.6, 0.15, 0.18)):
        r2 = r * rng.uniform(0.97, 1.04)
        y += a * np.sin(2 * np.pi * base * r2 * t + rng.uniform(0, 6.28)) * np.exp(-t / (decay * d))
    y += 1.2 * S.band(_noise(n, seed + 1), 1500, 8000) * np.exp(-t / 0.012)
    return S.crush(_tail(_norm(y * np.minimum(1.0, t / 0.001), 0.85)))


@cache
def crash(seed=0, dur=2.0):
    n = int(dur * SR)
    t = _t(n)
    y = S.filt(_noise(n, seed), hp=2800) * np.exp(-t / 0.7)
    y += 0.5 * clank(seed, 330.0, 0.9, 2.0)[:n] if n <= 2 * SR else 0
    return S.crush(_tail(_norm(y, 0.8)))


def riser(n, seed=0, lo=250.0, hi=9000.0):
    """Noise whose low-pass opens across the length, with a rising swell (not cached: used a few times)."""
    t = np.arange(n) / n
    fc = lo * (hi / lo) ** t
    y = S.lp_sweep(_noise(n, seed)[None, :], fc.astype(np.float32), lo, hi, nb=6)[0]
    return _tail((S.filt(y, hp=200) * t ** 2.2).astype(np.float32), 20)


# ---------- textures (full-loop length) ----------
def hiss(n, seed=1, lo=1500.0, hi=9500.0):
    return S.band(_noise(n, seed)[None, :], lo, hi)[0]


def crackle(n, seed=2, rate=7.0, lp=7000):
    rng = np.random.default_rng(seed)
    y = np.zeros(n, np.float32)
    k = int(n / SR * rate)
    y[rng.integers(0, n, k)] = rng.standard_normal(k) * rng.choice([0.2, 0.2, 1.0], k)
    return S.filt(y, hp=900, lp=lp)


def static(n, seed=3, lo=900.0, hi=6000.0, depth=0.8, rate=0.21):
    """Radio static with a slowly wandering level."""
    z = S.band(_noise(n, seed + 9)[None, :], 0.5, 3.0)[0]
    env = np.clip(0.5 + depth * z / (np.abs(z).max() + 1e-9), 0.02, 1.0) ** 2
    return (S.band(_noise(n, seed)[None, :], lo, hi)[0] * env).astype(np.float32)
