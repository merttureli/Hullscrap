"""Round-3 instruments for the faction dialects: a clean sine lead, a gritty bending lead, a clap, digital blips.
Mono float32; cached by their arguments, never modify a returned array in place."""
import functools
import numpy as np
import synth as S
import synth2 as S2
import voices as V
import voices2 as V2
from synth import SR, hz

cache = functools.lru_cache(maxsize=None)


def _t(n):
    return np.arange(n, dtype=np.float32) / SR


@cache
def sine(midi, dur, att=0.01, rel=0.25, vib=6.0, vrate=5.2, vdelay=0.3, h2=0.12):
    """A clean sine with a touch of second harmonic and delayed vibrato."""
    n_on = int(dur * SR)
    n = n_on + int(rel * SR)
    t = np.arange(n) / SR
    cents = vib * np.clip((t - vdelay) / 0.4, 0, 1) * np.sin(2 * np.pi * vrate * t)
    ph = np.cumsum(hz(midi + cents / 100) / SR)
    y = np.sin(2 * np.pi * ph) + h2 * np.sin(4 * np.pi * ph)
    return (y * S.gate_env(n_on, n, att, rel) * 0.5).astype(np.float32)


@cache
def grit(midi, dur, bend=-2.0, bend_ms=110.0, vib=22.0, vrate=5.8, drive=3.0, lp=3800.0, rel=0.18):
    """A distorted saw-and-square lead that bends into each note from `bend` semitones away, then shakes wide."""
    n_on = int(dur * SR)
    n = n_on + int(rel * SR)
    t = np.arange(n) / SR
    m = midi + bend * np.exp(-t / (bend_ms / 1000)) if bend else np.full(n, float(midi))
    cents = vib * np.clip((t - 0.2) / 0.3, 0, 1) * np.sin(2 * np.pi * vrate * t)
    ph, dt = S2.phase(hz(m + cents / 100))
    y = S.saw_blep(ph, dt) + 0.5 * S2.pulse_blep(ph, dt, 0.5)
    y = np.tanh(drive * y * 0.5) / np.tanh(drive * 0.5)
    y = S.filt(y.astype(np.float32), hp=120, lp=lp)
    return (y * S.gate_env(n_on, n, 0.006, rel) * 0.45).astype(np.float32)


@cache
def clap(seed=0, tail=0.16, tone=1100.0):
    """Three quick noise bursts and a short tail, band-passed: a drum-machine clap."""
    n = int((0.04 + tail * 3) * SR)
    t = _t(n)
    nz = S.band(V._noise(n, seed), tone * 0.7, tone * 6)
    e = np.zeros(n, np.float32)
    for k in range(3):
        a = int(k * 0.011 * SR)
        e[a:] += np.exp(-(t[:n - a]) / 0.006) * (0.8 + 0.1 * k)
    e += np.exp(-np.maximum(t - 0.024, 0) / tail) * (t >= 0.024) * 0.7
    return S.crush(V._tail(V._norm(nz * e, 0.9)))


@cache
def blip(f=1600.0, decay=0.05, bits=8):
    """A digital sine blip with a falling pitch flick: the Concord's ticks and pings."""
    n = int((decay * 6 + 0.01) * SR)
    t = _t(n)
    y = np.sin(2 * np.pi * np.cumsum(f * (1 + 0.3 * np.exp(-t / 0.004))) / SR) * np.exp(-t / decay)
    return S.crush(V._tail(V._norm(y * np.minimum(1, t / 0.0005), 0.85)), bits)
