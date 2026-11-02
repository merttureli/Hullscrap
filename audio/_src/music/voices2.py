"""Round-2 instruments: chip pulse voices, the acid line (also the darksynth pulse bass), a detuned supersaw,
glass plucks, a gated snare, toms. Mono float32 unless noted. Renders are cached by their arguments; never modify
a returned array in place."""
import functools
import numpy as np
import synth as S
import synth2 as S2
import voices as V
from synth import SR, hz

cache = functools.lru_cache(maxsize=None)


def _t(n):
    return np.arange(n, dtype=np.float32) / SR


def adsr(n_on, n, att, dec, sus, rel):
    """Linear attack, exponential decay to `sus`, held, raised-cosine release that ends at n."""
    t = np.arange(n) / SR
    e = sus + (1 - sus) * np.exp(-np.maximum(t - att, 0) / max(dec, 1e-3))
    e = np.where(t < att, t / max(att, 1e-4), e)
    r = n - n_on
    if r > 1:
        e[n_on:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(r) / r)
    return e.astype(np.float32)


# ---------- chip voices: pulse waves with duty control ----------
@cache
def chip(midi, dur, duty=0.25, att=0.004, dec=0.3, sus=0.65, rel=0.1, vib=0.0, vrate=5.6, vdelay=0.22, pwm=0.0, bits=8,
         slide_from=None, slide_ms=40.0):
    """Pulse-wave voice (duty 0.125 / 0.25 / 0.5) with an ADSR, delayed vibrato (cents), slow pulse-width wobble and a
    light bit-crush on the decaying signal. slide_from bends up or down from that MIDI note into this one."""
    n_on = int(dur * SR)
    n = n_on + int(rel * SR)
    t = np.arange(n) / SR
    m = np.full(n, float(midi))
    if slide_from is not None:
        m += (slide_from - midi) * np.exp(-t / (slide_ms / 1000))
    cents = vib * np.clip((t - vdelay) / 0.3, 0, 1) * np.sin(2 * np.pi * vrate * t)
    ph, dt = S2.phase(hz(m + cents / 100))
    d = duty + pwm * np.sin(2 * np.pi * 0.6 * t) if pwm else duty
    y = S2.pulse_blep(ph, dt, d) * 0.45 * adsr(n_on, n, att, dec, sus, rel)
    return S.crush(y, bits) if bits else y


# ---------- acid: a 303-like line through the resonant low-pass, rendered whole onto the loop ----------
def acid(L, spb, steps, base_fc, q=7.0, env_oct=2.6, decay=0.16, acc_oct=1.0, wave="saw", gate=0.55, slide_ms=60.0,
         drive=2.2, sub=0.0):
    """steps: (beat, beats, midi, accent 0..1, slide). A slid note glides in from the previous one without retriggering
    the envelopes, and the note before it holds legato. base_fc is the cutoff curve in Hz (scalar or per sample: the
    LFO and the section automation); every retriggered note adds a filter envelope of env_oct octaves, more on accents.
    q is the resonance (scalar or per sample). Returns a mono loop of L samples."""
    st = sorted(steps)
    pitch = np.zeros(L)
    amp = np.zeros(L)
    fenv = np.zeros(L)
    accs = np.zeros(L)
    for i, (b, d, m, a, sl) in enumerate(st):
        b0 = int(round(b * spb)) % L
        nb, _, nm, _, nsl = st[(i + 1) % len(st)]
        b1 = int(round(nb * spb)) if i + 1 < len(st) else int(round(st[0][0] * spb)) + L
        span = (b1 - b0) % L or L
        idx = (b0 + np.arange(span)) % L
        t = np.arange(span) / SR
        p = np.full(span, float(m))
        if sl:
            pm = st[i - 1][2]
            p += (pm - m) * np.exp(-t / (slide_ms / 1000))
        pitch[idx] = p
        g_end = span if nsl else min(span, int(d * gate * spb))
        e = np.zeros(span)
        e[:g_end] = 1.0
        k = min(int(0.006 * SR), max(1, span - g_end))
        if g_end < span:
            e[g_end:g_end + k] = np.linspace(1, 0, len(e[g_end:g_end + k]))
        if not sl:
            e[:int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))
            fenv[idx] = np.exp(-t / (decay * (0.7 if a > 0.5 else 1.0)))
            accs[idx] = a
        else:
            prev = fenv[(b0 - 1) % L]
            fenv[idx] = prev * np.exp(-t / (decay * 2.5))
            accs[idx] = accs[(b0 - 1) % L]
        amp[idx] = e * (0.7 + 0.3 * a)
    f = hz(pitch)
    ph, dt = S2.phase(f)
    osc = S.saw_blep(ph, dt) if wave == "saw" else S2.pulse_blep(ph, dt, 0.5) * 0.9
    fc = np.asarray(base_fc, np.float64) * 2.0 ** (env_oct * fenv * (1 + acc_oct * accs))
    amp = np.convolve(amp, np.ones(32) / 32, mode="same")   # no zipper clicks at the gate edges
    y = S2.svf_loop((osc * amp).astype(np.float32), fc, q)
    if sub:
        y = y + sub * np.sin(2 * np.pi * np.cumsum(f / 2) / SR).astype(np.float32) * amp
    y = np.tanh(drive * y) / np.tanh(drive)
    return y.astype(np.float32)


# ---------- supersaw lead: seven detuned saws spread across the stereo field ----------
@cache
def supersaw(midi, dur, voices=7, detune=20.0, att=0.012, rel=0.35, spread=0.9, seed=0, slide_from=None, slide_ms=50.0):
    """Returns a stereo note. detune is the outermost voice's offset in cents."""
    rng = np.random.default_rng(seed * 997 + int(midi))
    n_on = int(dur * SR)
    n = n_on + int(rel * SR)
    t = np.arange(n) / SR
    base = np.full(n, float(midi))
    if slide_from is not None:
        base += (slide_from - midi) * np.exp(-t / (slide_ms / 1000))
    out = np.zeros((2, n), np.float32)
    for k in range(voices):
        x = (k / (voices - 1)) * 2 - 1
        c = detune * np.sign(x) * abs(x) ** 1.4
        ph, dt = S2.phase(hz(base + c / 100))
        ph = (ph + rng.random()) % 1.0
        y = S.saw_blep(ph, dt) * (1.0 if k == voices // 2 else 0.8)
        th = (spread * x + 1) * np.pi / 4
        out[0] += y * np.float32(np.cos(th))
        out[1] += y * np.float32(np.sin(th))
    return out * S.gate_env(n_on, n, att, rel)[None, :] * np.float32(0.6 / np.sqrt(voices))


# ---------- glass pluck: FM with a bright transient that settles to an almost pure tone ----------
@cache
def glass(midi, ring=2.6, ratio=3.0, index=1.8, tau=0.85, sparkle=0.3):
    f = float(hz(midi))
    n = int(ring * SR)
    t = _t(n)
    I = index * np.exp(-t / 0.11) + 0.25
    y = np.sin(2 * np.pi * f * t + I * np.sin(2 * np.pi * ratio * f * t)) * np.exp(-t / tau)
    if f * 4.07 < 15000:
        y += sparkle * np.sin(2 * np.pi * f * 4.07 * t) * np.exp(-t / 0.22)
    y *= np.minimum(1.0, t / 0.0015) * np.minimum(1.0, (ring - t) / 0.2)
    return V._norm(y, 0.8)


# ---------- drums ----------
@cache
def gated_snare(seed=0, hold=0.2, size=1.4, tone=180.0, wet=0.9):
    """An 80s gated snare: a full snare into a dense room that is cut hard after `hold` seconds. Stereo."""
    dry = V.snare(seed, tone, 0.13, 1300, 0.5, 0.8)
    n = int(1.2 * SR)
    c = np.zeros((2, n), np.float32)
    c[:, :len(dry)] += dry
    room = S.reverb(S.filt(c, hp=250), S.make_ir(size, 3, 0.8, 40 + seed))
    m = int(0.5 * SR)
    g = np.ones(m, np.float32)
    h, k = int(hold * SR), int(0.022 * SR)
    g[h:h + k] = 0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)
    g[h + k:] = 0
    y = c[:, :m] + wet * room[:, :m] * g[None, :] * 4.0
    return S.crush((y / max(1e-9, float(np.abs(y).max())) * 0.9).astype(np.float32))


@cache
def tom(f0=110.0, decay=0.3, seed=0):
    n = int((decay * 4 + 0.05) * SR)
    t = _t(n)
    fi = f0 * (1 + 0.6 * np.exp(-t / 0.045))
    y = np.sin(2 * np.pi * np.cumsum(fi) / SR) * np.exp(-t / decay)
    y += 0.15 * np.sin(4 * np.pi * np.cumsum(fi) / SR) * np.exp(-t / (decay * 0.4))
    y += 0.3 * S.band(V._noise(n, seed), 800, 6000) * np.exp(-t / 0.006)
    return S.crush(V._tail(V._norm(np.tanh(1.4 * y), 0.9)))
