"""DSP building blocks for the Hullscrap SFX pipeline. numpy only, deterministic (every random source takes a seeded Generator).
Signals are float64 arrays in -1..1 at 44.1 kHz: mono (n,) or stereo (n, 2)."""
import os
import zlib
import wave
import numpy as np

SR = 44100
TAU = 2.0 * np.pi


def n_of(sec):
    return int(round(sec * SR))


def tt(sec):
    return np.arange(n_of(sec)) / SR


def rng_for(name, k=0):
    """A Generator seeded from the sound's name (and a variant number), so every sound is fixed forever."""
    return np.random.default_rng(zlib.crc32(name.encode()) * 31 + k * 7919 + 17)


def db(x):
    return 10.0 ** (x / 20.0)


# --- envelopes -----------------------------------------------------------------------------------------------

def env(sec, pts, power=1.0):
    """Piecewise-linear curve through pts [(t, value), ...] (t in seconds); power > 1 bends the segments toward a slow start."""
    t = tt(sec)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    y = np.interp(t, xs, ys)
    if power != 1.0:
        lo, hi = min(ys), max(ys)
        if hi > lo:
            y = lo + (hi - lo) * ((y - lo) / (hi - lo)) ** power
    return y


def ad(sec, a=0.003, tau=0.1):
    """Linear attack of a seconds, then an exponential decay with time constant tau."""
    t = tt(sec)
    up = np.minimum(t / max(a, 1e-4), 1.0)
    return up * np.exp(-np.maximum(t - a, 0.0) / tau)


def decay(sec, tau):
    return np.exp(-tt(sec) / tau)


def swell(sec, rise=0.5, fall=0.5):
    """Smooth rise and fall (raised cosine), for whooshes."""
    t = tt(sec)
    up = np.clip(t / rise, 0, 1)
    dn = np.clip((sec - t) / fall, 0, 1)
    return np.sin(up * np.pi / 2) * np.sin(dn * np.pi / 2)


def sweep(f0, f1, sec, curve="exp"):
    """A frequency curve from f0 to f1 over sec seconds (exp = equal musical steps per second)."""
    t = np.linspace(0.0, 1.0, n_of(sec))
    if curve == "exp":
        return f0 * (f1 / f0) ** t
    return f0 + (f1 - f0) * t


def fa(v, n):
    """A scalar or an array as an array of length n."""
    a = np.asarray(v, dtype=float)
    return np.full(n, float(a)) if a.ndim == 0 else a[:n] if len(a) >= n else np.pad(a, (0, n - len(a)), mode="edge")


# --- oscillators ----------------------------------------------------------------------------------------------

def cycles(freq, n=None):
    """Running phase in cycles for a frequency (scalar or per-sample array)."""
    f = fa(freq, n) if n is not None else np.asarray(freq, dtype=float)
    return np.cumsum(f) / SR


def sine(freq, n=None, ph=0.0):
    return np.sin(TAU * (cycles(freq, n) + ph))


def saw(freq, n=None, ph=0.0):
    return 2.0 * ((cycles(freq, n) + ph) % 1.0) - 1.0


def square(freq, n=None, pw=0.5, ph=0.0):
    return np.where(((cycles(freq, n) + ph) % 1.0) < pw, 1.0, -1.0)


def tri(freq, n=None, ph=0.0):
    return 2.0 * np.abs(2.0 * ((cycles(freq, n) + ph) % 1.0) - 1.0) - 1.0


def fm(fc, ratio, index, n=None, fb=0.0):
    """Two-operator FM: a carrier at fc modulated by a sine at fc*ratio; index is a scalar or per-sample array (radians)."""
    f = fa(fc, n) if n is not None else np.asarray(fc, dtype=float)
    idx = fa(index, len(f))
    mod = np.sin(TAU * cycles(f * ratio))
    return np.sin(TAU * cycles(f) + idx * mod)


def white(rng, n):
    return rng.standard_normal(n)


def coloured(rng, n, power=1.0):
    """Noise with a 1/f^(power/2) amplitude slope (power 1 = pink, 2 = brown), unit RMS."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.maximum(np.arange(len(spec)), 1.0)
    spec = spec / f ** (power / 2.0)
    spec[0] = 0.0
    y = np.fft.irfft(spec, n)
    return y / (np.sqrt(np.mean(y ** 2)) + 1e-12)


def band_noise(rng, n, lo, hi, power=0.0):
    """Noise made in the frequency domain between lo and hi Hz (soft edges, an extra 1/f^(power/2) slope), unit RMS. It is exactly
    periodic over n samples, so tile_to() makes a seamless loop of it."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.maximum(np.arange(len(spec)) * SR / n, 1.0)
    spec = spec / np.sqrt(1.0 + (lo / f) ** 4) / np.sqrt(1.0 + (f / hi) ** 4) / f ** (power / 2.0)
    spec[0] = 0.0
    y = np.fft.irfft(spec, n)
    return y / (np.sqrt(np.mean(y ** 2)) + 1e-12)


def tile_to(x, n):
    """Repeat x to n samples."""
    return np.tile(x, int(np.ceil(n / len(x))))[:n]


def crackle(rng, n, rate, tau=0.002, amp=1.0, pitch=0.45):
    """Sparse random clicks (rate per second), each a short decaying burst: fire and welding texture."""
    out = np.zeros(n)
    k = int(rate * n / SR)
    pos = rng.integers(0, max(n - 1, 1), k)
    mag = rng.random(k) ** 2 * amp
    sign = rng.choice([-1.0, 1.0], k)
    out[pos] = mag * sign
    m = max(int(tau * SR * 6), 2)
    kern = np.exp(-np.arange(m) / (tau * SR)) * np.cos(np.arange(m) * pitch)
    return np.convolve(out, kern)[:n]


# --- filters --------------------------------------------------------------------------------------------------

def lp1(x, fc):
    """One-pole low-pass; fc may vary per sample."""
    x = np.asarray(x, dtype=float)
    a = 1.0 - np.exp(-TAU * fa(fc, len(x)) / SR)
    out = np.empty(len(x))
    y = 0.0
    xs, al = x.tolist(), a.tolist()
    for i in range(len(xs)):
        y += al[i] * (xs[i] - y)
        out[i] = y
    return out


def hp1(x, fc):
    return np.asarray(x, dtype=float) - lp1(x, fc)


def biquad(x, kind, f, q=0.707):
    """RBJ biquad (lp, hp, bp = constant 0 dB peak, notch, peak-less): f and q may vary per sample."""
    x = np.asarray(x, dtype=float)
    n = len(x)
    f = np.clip(fa(f, n), 20.0, SR * 0.45)
    q = fa(q, n)
    w = TAU * f / SR
    cw, sw = np.cos(w), np.sin(w)
    al = sw / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    elif kind == "bp":
        b0, b1, b2 = al, np.zeros(n), -al
    else:  # notch
        b0, b1, b2 = np.ones(n), -2 * cw, np.ones(n)
    a0 = 1 + al
    B0, B1, B2 = (b0 / a0).tolist(), (b1 / a0).tolist(), (b2 / a0).tolist()
    A1, A2 = (-2 * cw / a0).tolist(), ((1 - al) / a0).tolist()
    xs = x.tolist()
    out = np.empty(n)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(n):
        xi = xs[i]
        y = B0[i] * xi + B1[i] * x1 + B2[i] * x2 - A1[i] * y1 - A2[i] * y2
        x2, x1, y2, y1 = x1, xi, y1, y
        out[i] = y
    return out


def lp(x, f, q=0.707):
    return biquad(x, "lp", f, q)


def hp(x, f, q=0.707):
    return biquad(x, "hp", f, q)


def bp(x, f, q=2.0):
    return biquad(x, "bp", f, q)


# --- instruments -----------------------------------------------------------------------------------------------

def modal(freqs, taus, amps, sec, rng=None, jitter=0.0):
    """Struck scrap metal: a sum of decaying sines at inharmonic partials. taus are decay time constants (s)."""
    t = tt(sec)[:, None]
    f = np.asarray(freqs, dtype=float)[None, :]
    if rng is not None and jitter > 0:
        f = f * (1.0 + jitter * (rng.random(f.shape) - 0.5))
    ph = rng.random(f.shape) * TAU if rng is not None else np.zeros(f.shape)
    y = np.sin(TAU * f * t + ph) * np.exp(-t / np.asarray(taus, dtype=float)[None, :]) * np.asarray(amps, dtype=float)[None, :]
    return y.sum(axis=1)


# metal-bar partial ratios (a free bar: 1, 2.76, 5.40, 8.93, 13.34, 18.64), the "scrap clank" the hull sounds are built on
BAR = np.array([1.0, 2.76, 5.40, 8.93, 13.34, 18.64])
PLATE = np.array([1.0, 1.59, 2.14, 2.30, 2.65, 2.92, 3.50])


def karplus(freq, sec, rng, damp=0.5, bright=0.5):
    """Karplus-Strong plucked string / struck wire."""
    n = n_of(sec)
    period = max(int(round(SR / freq)), 2)
    buf = (rng.random(period) * 2 - 1) * bright + (1 - bright) * np.sign(rng.random(period) - 0.5) * 0.5
    out = np.empty(n)
    b = buf.tolist()
    k = 0
    prev = 0.0
    for i in range(n):
        cur = b[k]
        out[i] = cur
        b[k] = (cur + prev) * 0.5 * (1.0 - damp * 0.01)
        prev = cur
        k += 1
        if k == period:
            k = 0
    return out


def crush(x, bits=10, hold=1):
    """Bit-crush and sample-hold: the lo-fi grit."""
    x = np.asarray(x, dtype=float)
    step = 2.0 / (2 ** bits)
    y = np.round(x / step) * step
    if hold > 1:
        y = np.repeat(y[::hold], hold)[:len(x)]
    return y


def reverb(x, rt60=0.5, wet=0.25, seed=1, damp=4000.0, tail=None, pre=0.0):
    """Convolution reverb with a synthetic exponential-noise impulse (low-passed so the tail is dark). Returns x extended by the tail."""
    x = np.asarray(x, dtype=float)
    rng = np.random.default_rng(seed)
    m = n_of(rt60 * 1.1)
    t = np.arange(m) / SR
    imp = rng.standard_normal(m) * np.exp(-6.91 * t / rt60)
    imp = lp1(imp, np.linspace(damp, damp * 0.35, m))
    imp[:n_of(pre)] = 0.0
    imp /= np.sqrt(np.sum(imp ** 2)) + 1e-12
    extra = m if tail is None else n_of(tail)
    size = 1 << int(np.ceil(np.log2(len(x) + m)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(imp, size), size)[:len(x) + extra]
    out = np.zeros(len(x) + extra)
    out[:len(x)] = x
    return out * (1.0 - wet * 0.5) + y * wet * 2.0


def chorus(x, depth=0.003, rate=0.7, mix=0.5):
    x = np.asarray(x, dtype=float)
    n = len(x)
    idx = np.arange(n) - (depth * SR) * (1.0 + np.sin(TAU * rate * np.arange(n) / SR)) - 1
    idx = np.clip(idx, 0, n - 1)
    lo = idx.astype(int)
    fr = idx - lo
    hi = np.minimum(lo + 1, n - 1)
    d = x[lo] * (1 - fr) + x[hi] * fr
    return x * (1 - mix * 0.5) + d * mix * 0.5


# --- assembling ---------------------------------------------------------------------------------------------------

def place(*layers, length=None):
    """Sum layers [(signal, start_seconds, gain), ...] into one buffer."""
    end = max(n_of(s) + len(x) for x, s, _ in layers)
    n = end if length is None else n_of(length)
    out = np.zeros((n,) + layers[0][0].shape[1:])
    for x, s, g in layers:
        i = n_of(s)
        if i >= n:
            continue
        m = min(len(x), n - i)
        out[i:i + m] += x[:m] * g
    return out


def fade(x, a=0.002, r=0.004):
    """Short linear fades at both ends so nothing clicks."""
    x = np.array(x, dtype=float)
    na, nr = max(n_of(a), 1), max(n_of(r), 1)
    ramp_in = np.linspace(0.0, 1.0, na)
    ramp_out = np.linspace(1.0, 0.0, nr)
    if x.ndim == 2:
        x[:na] *= ramp_in[:, None]
        x[-nr:] *= ramp_out[:, None]
    else:
        x[:na] *= ramp_in
        x[-nr:] *= ramp_out
    return x


def trim(x, floor_db=-60.0, keep=0.01):
    """Cut the silent tail (below floor_db of the peak), keeping `keep` seconds after the last loud sample."""
    m = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    loud = np.nonzero(m > np.max(m) * db(floor_db))[0]
    end = min(len(x), (loud[-1] if len(loud) else len(x) - 1) + n_of(keep))
    return x[:end]


def dc_block(x):
    return hp1(x, 18.0) if x.ndim == 1 else np.stack([hp1(x[:, 0], 18.0), hp1(x[:, 1], 18.0)], axis=1)


def stereo(left, right):
    return np.stack([left, right], axis=1)


def loop_fix(x, length, tail):
    """Make a seamless loop of `length` seconds from a signal of length+tail seconds: the continuation past the end
    is cross-faded (equal power) onto the start, so the last sample runs straight into the first."""
    n, m = n_of(length), n_of(tail)
    out = np.array(x[:n], dtype=float)
    w = np.linspace(0.0, 1.0, m)
    fin, fout = np.sin(w * np.pi / 2), np.cos(w * np.pi / 2)
    if out.ndim == 2:
        fin, fout = fin[:, None], fout[:, None]
    out[:m] = x[:m] * fin + x[n:n + m] * fout
    return out


def peak_db(x):
    return 20.0 * np.log10(np.max(np.abs(x)) + 1e-12)


def active_rms_db(x):
    """RMS over the loud part of the sound (samples within 30 dB of the peak), in dBFS: the loudness the families are matched on."""
    a = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
    sel = a > np.max(a) * db(-30.0)
    y = x[sel]
    return 10.0 * np.log10(np.mean(y ** 2) + 1e-12)


def finish(x, target_rms_db, ceiling_db=-1.0):
    """Match the active RMS to target_rms_db, then keep the peaks under ceiling_db: a soft saturation takes the top 3 dB, a hard scale guarantees the rest."""
    x = np.asarray(x, dtype=float)
    x = x * db(target_rms_db - active_rms_db(x))
    ceil = db(ceiling_db)
    knee = ceil * db(-3.0)
    a = np.abs(x)
    over = a > knee
    if np.any(over):
        room = ceil - knee
        x = np.where(over, np.sign(x) * (knee + room * np.tanh((a - knee) / room)), x)
    p = np.max(np.abs(x))
    if p > ceil:
        x = x * (ceil / p)
    return x


def to_pcm16(x):
    return np.round(np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")


def write_wav(path, x):
    pcm = to_pcm16(x)
    with wave.open(path, "wb") as w:
        w.setnchannels(1 if x.ndim == 1 else 2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# --- helpers for the sound library of round 2 (ambience beds, line variants) --------------------------------------------

def resample(x, ratio):
    """Play x back `ratio` times as fast (pitch and speed together; linear interpolation): the cheap pitch shift."""
    x = np.asarray(x, dtype=float)
    idx = np.arange(0.0, len(x) - 1.0, ratio)
    lo = idx.astype(int)
    fr = idx - lo
    return x[lo] * (1.0 - fr) + x[lo + 1] * fr


def per(n, k, ph=0.0):
    """A sine with k whole cycles over n samples: a modulator that fits a seamless loop."""
    return np.sin(TAU * (k * np.arange(n) / n + ph))


def snap(f, sec):
    """The frequency nearest f that fits a whole number of cycles in sec seconds (a tone that loops without a seam)."""
    return max(round(f * sec), 1) / sec


def wrap_add(out, x, start):
    """Add x into the loop buffer `out` at sample `start`; what runs past the end comes in again at the beginning, so events never leave a seam."""
    idx = (int(start) + np.arange(len(x))) % len(out)
    np.add.at(out, idx, x)


def fft_filter(x, lo=None, hi=None, order=2):
    """A circular band-pass in the frequency domain (soft edges): shapes a whole loop with no start-up transient, so it stays seamless.
    lo: high-pass corner, hi: low-pass corner (Hz, either may be None); order 2 is a gentle slope."""
    x = np.asarray(x, dtype=float)
    out = np.empty_like(x)
    for c in range(1 if x.ndim == 1 else x.shape[1]):
        col = x if x.ndim == 1 else x[:, c]
        spec = np.fft.rfft(col)
        f = np.maximum(np.arange(len(spec)) * SR / len(col), 1e-3)
        if lo:
            spec = spec / np.sqrt(1.0 + (lo / f) ** (2 * order))
        if hi:
            spec = spec / np.sqrt(1.0 + (f / hi) ** (2 * order))
        y = np.fft.irfft(spec, len(col))
        if x.ndim == 1:
            out = y
        else:
            out[:, c] = y
    return out


def smooth_noise(rng, n, rate, floor=0.0):
    """A slow random curve 0..1 that repeats over n samples (noise limited to ~rate Hz, squared): breathing, syllables, gusts."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.arange(len(spec)) * SR / n
    spec = spec / np.sqrt(1.0 + (f / rate) ** 4)
    spec[0] = 0.0
    y = np.fft.irfft(spec, n)
    y = y / (np.max(np.abs(y)) + 1e-12)
    return floor + (1.0 - floor) * (0.5 + 0.5 * y) ** 2


def wcrackle(rng, n, rate, tau=0.002, amp=1.0, pitch=0.45, power=2.0):
    """Sparse random clicks like crackle(), but wrapped round the end of the buffer (for loops). Every click is a decaying burst."""
    out = np.zeros(n)
    k = max(int(rate * n / SR), 1)
    pos = rng.integers(0, n, k)
    mag = rng.random(k) ** power * amp
    sign = rng.choice([-1.0, 1.0], k)
    m = max(int(tau * SR * 6), 2)
    kern = np.exp(-np.arange(m) / (tau * SR)) * np.cos(np.arange(m) * pitch)
    for p, g, s in zip(pos, mag, sign):
        wrap_add(out, kern * g * s, p)
    return out


def sample(name, ratio=1.0, gain=1.0):
    """A committed sample (audio/_src/sfx/samples/<name>.wav, mono 44.1 kHz 16-bit) as floats, played back `ratio` times as fast."""
    with wave.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples", name + ".wav")) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768.0
    return (resample(x, ratio) if ratio != 1.0 else x) * gain
