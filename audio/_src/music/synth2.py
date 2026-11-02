"""Round-2 DSP tools on top of synth.py: pulse waves with duty control, a resonant 2-pole low-pass whose cutoff
moves per sample (envelope and LFO), a sidechain ducker keyed by kick hits, glitch edits (stutter, buffer repeat,
tape-stop, crush sweep) and the onset-sync check between two versions of a piece. numpy only."""
import numpy as np
import synth as S
from synth import SR


def pulse_blep(ph, dt, duty=0.5):
    """Band-limited pulse from a phase in cycles: the difference of two PolyBLEP saws; high for `duty` of the cycle,
    zero mean, peak-to-peak 2. duty may be a per-sample array (pulse-width modulation)."""
    return (S.saw_blep((ph + 1.0 - duty) % 1.0, dt) - S.saw_blep(ph, dt)).astype(np.float32)


def phase(f):
    """Phase in cycles (0..1) and per-sample increment for a frequency curve in Hz."""
    dt = np.broadcast_to(np.asarray(f, np.float64), np.shape(f)) / SR
    return (np.cumsum(dt) % 1.0), dt


def svf_lp(x, fc, q, z=(0.0, 0.0)):
    """Resonant 2-pole low-pass (trapezoidal state-variable filter). fc (Hz) and q are scalars or per-sample arrays,
    so the cutoff can ride an envelope and an LFO. Returns (y, end state)."""
    n = len(x)
    g = np.tan(np.pi * np.clip(np.broadcast_to(fc, (n,)), 20.0, SR * 0.45) / SR)
    k = 1.0 / np.broadcast_to(np.asarray(q, np.float64), (n,))
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    y = [0.0] * n
    ic1, ic2 = z
    for i, (v0, b1, b2, b3) in enumerate(zip(x.tolist(), a1.tolist(), a2.tolist(), a3.tolist())):
        v3 = v0 - ic2
        v1 = b1 * ic1 + b2 * v3
        v2 = ic2 + b2 * ic1 + b3 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        y[i] = v2
    return np.asarray(y, np.float32), (ic1, ic2)


def svf_loop(x, fc, q, pre=0.5):
    """svf_lp on a loop: the last `pre` seconds run first so the filter state at sample 0 continues from the end."""
    k = min(len(x), int(pre * SR))
    fc = np.broadcast_to(fc, x.shape)
    q = np.broadcast_to(q, x.shape)
    y, _ = svf_lp(np.concatenate([x[-k:], x]), np.concatenate([fc[-k:], fc]), np.concatenate([q[-k:], q]))
    return y[k:]


def duck(n, hits, depth=0.55, attack_ms=3.0, release=0.2, curve=1.6):
    """Sidechain gain curve for an n-sample loop: at each kick hit (a sample index) the gain falls by `depth` within
    attack_ms and swells back over `release` seconds. Multiply a part by it to make it pump with the kick."""
    a = max(1, int(attack_ms * SR / 1000))
    r = max(1, int(release * SR))
    shape = np.concatenate([np.linspace(0, 1, a, endpoint=False), (1 - np.arange(r) / r) ** curve])
    imp = np.zeros(n)
    np.add.at(imp, np.asarray(hits, np.int64) % n, 1.0)
    dip = np.fft.irfft(np.fft.rfft(imp) * np.fft.rfft(shape, n), n)
    return (1.0 - depth * np.clip(dip, 0, 1)).astype(np.float32)


def gate_curve(n, spb, pattern, start_beat, beats, step=0.25, duty=0.6, smooth_ms=3.0):
    """A trance gate: pattern is a string of 'x' (open) and '.' (shut) per `step` beats, repeated from start_beat for
    `beats` beats; each open step stays open for `duty` of the step. Returns a 0..1 curve; 1 outside the window."""
    g = np.ones(n, np.float32)
    s0, s1 = int(start_beat * spb), int((start_beat + beats) * spb)
    g[s0 % n:min(n, s1)] = 0.0
    for i in range(int(beats / step)):
        if pattern[i % len(pattern)] == "x":
            a = int((start_beat + i * step) * spb)
            g[a:a + int(step * duty * spb)] = 1.0
    k = max(1, int(smooth_ms * SR / 1000))
    return np.convolve(g, np.ones(k) / k, mode="same").astype(np.float32)


# ---------- glitch edits on a stereo (2, n) loop buffer; regions wrap around the loop ----------
def _idx(n, at, m):
    return (int(at) + np.arange(int(m))) % n


def _fades(m, ms=2.0):
    k = max(1, min(m // 4, int(ms * SR / 1000)))
    w = np.ones(m, np.float32)
    w[:k] = np.linspace(0, 1, k)
    w[-k:] = np.linspace(1, 0, k)
    return w


def stutter(x, at, slice_len, span, src=None, decay=1.0, shrink=1.0, min_len=0.0):
    """Buffer repeat: copy the slice starting at `src` (default `at`) over [at, at + span), again and again. Each
    repeat is `decay` times as loud and `shrink` times as long (shrink < 1 makes a roll that speeds up), never
    shorter than min_len samples. Every slice gets 2 ms fades so the edits do not click."""
    y = x.copy()
    n = x.shape[1]
    src = at if src is None else src
    pos, ln, g = 0, float(slice_len), 1.0
    while pos < span:
        m = int(min(max(ln, min_len), span - pos))
        if m < 8:
            break
        y[:, _idx(n, at + pos, m)] = x[:, _idx(n, src, m)] * (_fades(m) * g)[None, :]
        pos += m
        ln *= shrink
        g *= decay
    return y


def tape_stop(x, at, length, power=1.6, tail=0.12):
    """Tape-stop over [at, at + length): playback slows to a halt (the pitch falls with it), then silence to the end of
    the region; the music resumes after it untouched."""
    y = x.copy()
    n = x.shape[1]
    m = int(length)
    t = np.arange(m) / m
    pos = np.cumsum((1 - t) ** power)   # read position in samples, speed falling from 1 to 0
    i0 = np.floor(pos).astype(np.int64)
    fr = (pos - i0).astype(np.float32)
    seg = x[:, _idx(n, at, m + 2)]
    out = seg[:, i0] * (1 - fr) + seg[:, i0 + 1] * fr
    fade = np.clip((1 - t) / tail, 0, 1).astype(np.float32) ** 2
    y[:, _idx(n, at, m)] = out * fade[None, :] * _fades(m, 3.0)[None, :] + x[:, _idx(n, at, m)] * (1 - _fades(m, 3.0))[None, :]
    return y


def crush_sweep(x, at, length, bits=(12, 4), hold=(1, 10), mix=1.0):
    """Bit-crush and sample-rate reduction that deepen across [at, at + length), faded in and out at the edges."""
    y = x.copy()
    n = x.shape[1]
    m = int(length)
    idx = _idx(n, at, m)
    seg = x[:, idx]
    t = np.arange(m) / m
    b = bits[0] + (bits[1] - bits[0]) * t
    h = np.round(hold[0] + (hold[1] - hold[0]) * t).astype(np.int64)
    # sample-and-hold: each sample takes the value at the start of its hold block
    j = np.arange(m)
    j = np.maximum(j - (j % np.maximum(h, 1)), 0)
    q = 2.0 ** (b - 1)
    c = np.round(seg[:, j] * q[None, :]) / q[None, :]
    w = np.minimum(1.0, np.minimum(t, 1 - t) / 0.08) * mix
    y[:, idx] = (seg * (1 - w) + c * w).astype(np.float32)
    return y


# ---------- sync check ----------
def onset_strength(x, hop=64):
    """Spectral-flux-like onset curve: the positive rise of the log energy in three bands, one value per hop."""
    m = x.mean(0)
    out = 0.0
    for lo, hi in ((30, 200), (200, 2000), (2000, 12000)):
        e = S.band(m, lo, hi) ** 2
        f = e[:len(e) // hop * hop].reshape(-1, hop).mean(1)
        lg = np.log10(f + 1e-10)
        out = out + np.clip(np.diff(lg, prepend=lg[0]), 0, None)
    return out


def onset_lag(a, b, hop=64, max_ms=250.0):
    """The lag (ms) that best lines up b's onsets with a's, and the normalised correlation at lag 0."""
    oa, ob = onset_strength(a, hop), onset_strength(b, hop)
    oa, ob = oa - oa.mean(), ob - ob.mean()
    n = len(oa)
    xc = np.fft.irfft(np.fft.rfft(oa, 2 * n) * np.conj(np.fft.rfft(ob, 2 * n)), 2 * n)
    k = int(max_ms / 1000 * SR / hop)
    lags = np.r_[np.arange(0, k + 1), np.arange(-k, 0)]
    vals = np.r_[xc[:k + 1], xc[-k:]]
    best = int(lags[np.argmax(vals)])
    c0 = float(xc[0] / (np.sqrt((oa ** 2).sum() * (ob ** 2).sum()) + 1e-12))
    return round(best * hop / SR * 1000, 2), round(c0, 3)
