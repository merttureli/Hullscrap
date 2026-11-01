"""Hullscrap soundtrack engine: numpy-only DSP (no scipy). Every song is rendered into circular buffers of
exactly one loop, so FFT filters, delays and the reverb wrap around and the loop point is seamless."""
import functools
import numpy as np

SR = 44100


def hz(m):
    return 440.0 * 2.0 ** ((np.asarray(m, float) - 69.0) / 12.0)


def db(x):
    return 10 ** (x / 20.0)


def smooth_len(n):
    """The 7-smooth integer nearest to n (FFTs of these lengths are fast; the tempo moves under 0.5%)."""
    lo, hi = int(n * 0.99), int(n * 1.01) + 1
    cand = [2 ** a * 3 ** b * 5 ** c * 7 ** d for a in range(25) for b in range(16) for c in range(11) for d in range(9)
            if lo <= 2 ** a * 3 ** b * 5 ** c * 7 ** d <= hi and (2 ** a * 3 ** b * 5 ** c * 7 ** d) % 2 == 0]
    return min(cand, key=lambda v: abs(v - n))


@functools.lru_cache(maxsize=None)
def _freqs(n):
    return np.fft.rfftfreq(n, 1.0 / SR)


def cycles(rate_hz, n):
    """LFO rate rounded so a whole number of cycles fits the n-sample loop."""
    return max(1, round(rate_hz * n / SR))


def lfo(n, rate_hz, phase=0.0):
    return np.sin(2 * np.pi * cycles(rate_hz, n) * np.arange(n) / n + phase).astype(np.float32)


# ---------- circular canvas ----------
class Canvas:
    def __init__(self, n):
        self.n = n
        self.buf = np.zeros((2, n), np.float32)

    def put(self, sig, at, gain=1.0, pan=0.0):
        sig = np.asarray(sig, np.float32)
        if sig.ndim == 1:
            th = (pan + 1) * np.pi / 4
            sig = np.stack([sig * (np.cos(th) * 1.4142 * gain), sig * (np.sin(th) * 1.4142 * gain)])
        else:
            sig = sig * gain
        m = min(sig.shape[1], self.n)
        sig = sig[:, :m]
        at = int(at) % self.n
        if at + m <= self.n:
            self.buf[:, at:at + m] += sig
        else:
            k = self.n - at
            self.buf[:, at:] += sig[:, :k]
            self.buf[:, :m - k] += sig[:, k:]


# ---------- oscillators / envelopes ----------
def saw_blep(ph, dt):
    """Band-limited saw from a phase in cycles (0..1) and the per-sample increment (PolyBLEP)."""
    y = 2.0 * ph - 1.0
    a = ph < dt
    t = np.where(a, ph / dt, 0.0)
    y -= np.where(a, t + t - t * t - 1.0, 0.0)
    b = ph > 1.0 - dt
    t = np.where(b, (ph - 1.0) / dt, 0.0)
    y -= np.where(b, t * t + t + t + 1.0, 0.0)
    return y.astype(np.float32)


def tri_from(ph):
    return (4.0 * np.abs(ph % 1.0 - 0.5) - 1.0).astype(np.float32)


def gate_env(n_on, n_total, att, rel_s):
    """Raised-cosine attack, hold, raised-cosine release that ends at n_total."""
    e = np.ones(n_total, np.float32)
    a = max(1, min(int(att * SR), n_total))
    e[:a] = 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    r = n_total - n_on
    if r > 1:
        e[n_on:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(r) / r)
    return e


# ---------- FFT filters (zero phase) ----------
def resp(n, hp=None, lp=None, order=2, bells=()):
    f = _freqs(n)
    h = np.ones(len(f))
    if hp:
        h /= np.sqrt(1 + (hp / np.maximum(f, 1e-3)) ** (2 * order))
    if lp:
        h /= np.sqrt(1 + (f / lp) ** (2 * order))
    for fc, g, w in bells:   # bell EQ: centre Hz, gain dB, width in octaves
        h *= 10 ** (g / 20 * np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) / w) ** 2))
    return h.astype(np.float32)


def filt(x, hp=None, lp=None, order=2, bells=()):
    n = x.shape[-1]
    if not (hp or lp or bells):
        return x
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * resp(n, hp, lp, order, bells), n, axis=-1).astype(np.float32)


def band(x, lo, hi, order=2):
    return filt(x, hp=lo, lp=hi, order=order)


def lp_sweep(x, fc, lo=300.0, hi=4000.0, nb=7, order=2):
    """Low-pass whose cutoff follows the per-sample curve fc: a bank of fixed filters, crossfaded."""
    n = x.shape[-1]
    X = np.fft.rfft(x, axis=-1)
    pos = np.clip(np.log(np.clip(fc, lo, hi) / lo) / np.log(hi / lo) * (nb - 1), 0, nb - 1)
    out = np.zeros_like(x, dtype=np.float32)
    for i, c in enumerate(np.geomspace(lo, hi, nb)):
        w = np.clip(1 - np.abs(pos - i), 0, 1).astype(np.float32)
        if not w.any():
            continue
        out += np.fft.irfft(X * resp(n, lp=c, order=order), n, axis=-1).astype(np.float32) * w
    return out


# ---------- effects ----------
def chorus(x, rate, base_ms, depth_ms, phase=0.0, mix=0.5):
    n = x.shape[-1]
    t = np.arange(n)
    d = (base_ms + depth_ms * np.sin(2 * np.pi * cycles(rate, n) * t / n + phase)) * SR / 1000.0
    idx = t - d
    i0 = np.floor(idx).astype(np.int64)
    fr = (idx - i0).astype(np.float32)
    y = x[..., i0 % n] * (1 - fr) + x[..., (i0 + 1) % n] * fr
    return x * (1 - mix) + y * mix


def pingpong(x, delay, fb=0.5, taps=9, lp=3600, hp=220):
    """Ping-pong echo of the mono sum; the first repeat lands right, then left, and so on."""
    m = filt(x.mean(0), hp=hp, lp=lp)
    out = np.zeros((2, x.shape[-1]), np.float32)
    for k in range(1, taps + 1):
        out[1 if k % 2 else 0] += np.roll(m, int(round(k * delay))) * (fb ** (k - 1))
    return out


@functools.lru_cache(maxsize=None)
def make_ir(t60=3.5, predelay_ms=22.0, dark=1.0, seed=7):
    """A synthetic stereo reverb impulse: decorrelated noise, four bands that decay at different rates."""
    rng = np.random.default_rng(seed)
    m = int(t60 * 1.25 * SR)
    t = np.arange(m) / SR
    edges = [(None, 250), (250, 1000), (1000, 4000), (4000, None)]
    scale = [1.25, 1.0, 0.7 / dark, 0.42 / dark]
    ir = np.zeros((2, m))
    for c in range(2):
        w = rng.standard_normal(m)
        W = np.fft.rfft(w)
        for (lo, hi), s in zip(edges, scale):
            h = np.ones(len(W))
            f = _freqs(m)
            if lo:
                h = h / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** 4)
            if hi:
                h = h / np.sqrt(1 + (f / hi) ** 4)
            ir[c] += np.fft.irfft(W * h, m) * np.exp(-6.91 * t / (t60 * s))
        for _ in range(7):   # a few early reflections
            k = int(rng.uniform(0.004, 0.07) * SR)
            ir[c, k] += rng.choice([-1, 1]) * rng.uniform(0.5, 1.4) * ir[c].std() * 6
    ir *= np.minimum(1.0, t / 0.02)[None, :] ** 1.5
    ir = np.concatenate([np.zeros((2, int(predelay_ms * SR / 1000))), ir], axis=1)
    ir /= np.sqrt((ir ** 2).sum(axis=1, keepdims=True))
    return ir.astype(np.float32)


def reverb(x, ir):
    n = x.shape[-1]
    ir = ir[:, :n]
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * np.fft.rfft(ir, n, axis=-1), n, axis=-1).astype(np.float32)


def crush(x, bits=12):
    q = 2.0 ** (bits - 1)
    return (np.round(x * q) / q).astype(np.float32)


def _conv_smooth(p, tau, causal):
    n = len(p)
    k = max(2, int(tau * SR * 6))
    kern = np.zeros(n)
    e = np.exp(-np.arange(k) / (tau * SR))
    kern[:k] = e
    if not causal:
        kern[-(k - 1):] = e[1:][::-1]
    kern /= kern.sum()
    return np.fft.irfft(np.fft.rfft(p) * np.fft.rfft(kern), n)


def compress(x, thresh_db=-26.0, ratio=2.2, release=0.25, knee=8.0):
    """Gentle bus compressor: RMS detector, soft knee; deeper-of(look-ahead, slow-release) gain reduction."""
    p = _conv_smooth(np.mean(x.astype(np.float64) ** 2, axis=0), 0.03, False)
    lvl = 10 * np.log10(p + 1e-12)
    over = lvl - thresh_db
    gr = -np.where(over > knee / 2, over, np.clip(over + knee / 2, 0, None) ** 2 / (2 * knee)) * (1 - 1 / ratio)
    gr = np.minimum(_conv_smooth(gr, 0.012, False), _conv_smooth(gr, release, True))
    return (x * (10 ** (gr / 20)).astype(np.float32)[None, :]).astype(np.float32)


def softclip(x, ceil, knee=0.78):
    T = ceil * knee
    a = np.abs(x)
    o = a > T
    y = x.copy()
    y[o] = np.sign(x[o]) * (T + (ceil - T) * np.tanh((a[o] - T) / (ceil - T)))
    return y


def true_peak(x):
    """Inter-sample peak (linear) by 4x FFT upsampling."""
    best = 0.0
    for c in x:
        n = len(c)
        X = np.fft.rfft(c)
        Y = np.zeros(2 * n + 1, np.complex64)
        Y[:len(X)] = X
        best = max(best, float(np.abs(np.fft.irfft(Y, 4 * n) * 4).max()))
    return best


def rms_db(x):
    return 10 * np.log10(float(np.mean(x.astype(np.float64) ** 2)) + 1e-20)


def master(x, target_rms_db, ceil_db=-1.8):
    """High-pass the DC, bus-compress, set the loudness, then soft-limit under the ceiling."""
    x = filt(x, hp=24, order=2)
    x = compress(x)
    g0 = db(target_rms_db) / np.sqrt(np.mean(x.astype(np.float64) ** 2))
    for _ in range(3):   # soft-limit under the ceiling, lower the ceiling if inter-sample peaks still go over -1.35 dBTP
        ceil, g = db(ceil_db), g0
        for _ in range(5):
            y = softclip(x * np.float32(g), ceil)
            g *= db(target_rms_db - rms_db(y))
        over = 20 * np.log10(true_peak(y)) + 1.35
        if over <= 0:
            break
        ceil_db -= over + 0.1
    return y.astype(np.float32)


def bands_share(x):
    """Energy share (percent) in 20-120, 120-500, 500-2k, 2k-6k and 6k+ Hz."""
    edges = [20, 120, 500, 2000, 6000, 30000]
    tot = np.zeros(5)
    for c in x:
        P = np.abs(np.fft.rfft(c.astype(np.float64))) ** 2
        f = _freqs(len(c))
        for i in range(5):
            tot[i] += P[(f >= edges[i]) & (f < edges[i + 1])].sum()
    return [round(float(v), 1) for v in tot / tot.sum() * 100]


def seam_check(x):
    """Step across the loop point against the loudest ordinary step, and the RMS of the first and last 0.5 s."""
    step = float(np.abs(x[:, 0] - x[:, -1]).max())
    d = np.abs(np.diff(x, axis=1))
    k = SR // 2
    return {"seam_step": round(step, 5), "typ_step_p999": round(float(np.percentile(d, 99.9)), 5), "max_step": round(float(d.max()), 5),
            "rms_first_db": round(rms_db(x[:, :k]), 1), "rms_last_db": round(rms_db(x[:, -k:]), 1)}
