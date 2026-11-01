"""One-shot stings (2-10 s): victory, defeat, jump, region_cross, ada_found, unlock, ending.
Each is a tiny Song at 60 BPM (one beat = one second) except `ending`; a reverb tail is rendered after the last event and
the file is trimmed and faded at `total`. Same palette as the tracks."""
import numpy as np
import synth as S
import voices as V
import theme as T
from common import Song
from synth import SR

TAIL = 3.0


def _pads(s, chord, t, dur, g=1.0, att=0.4, rel=1.8, seed=0):
    for m in chord:
        s.put("pad", V.pad(m, dur, att, rel, 8.0, 3.0, seed=seed), t, g * s.v(1.0, 0.04))


def victory(s):
    for k, (t, m, v) in enumerate([(0.0, 62, .8), (0.2, 69, .8), (0.4, 74, .9), (0.6, 78, .9), (0.8, 81, 1.0)]):
        s.put("pluck", V.pluck(m, 1.3, "saw", 1.1, 0.5), t, v, pan=-0.5 + 0.25 * k)
    s.put("bell", V.bell(86, 3.2, 3.5, 2.0, 1.3), 1.0, 0.7, pan=0.3)
    s.put("bell", V.bell(78, 3.2, 3.5, 2.0, 1.3), 1.0, 0.4, pan=-0.3)
    _pads(s, [50, 57, 62, 66, 69, 76], 0.55, 1.5, 1.0, 0.3, 2.0)
    s.put("bass", V.bass(38, 1.8, 330.0, 1.2, 1.0, 0.2, 0.2), 0.55, 0.9)
    return {"pad": dict(g=-3, hp=140, send=0.5), "pluck": dict(g=-3, hp=260, send=0.4), "bell": dict(g=-2, hp=350, send=0.7),
            "bass": dict(g=-6, hp=30, lp=700, send=0.05)}


def defeat(s):
    for t, m, v in ((0.0, 74, .8), (0.85, 72, .7), (1.7, 69, .6), (2.9, 65, .55)):
        s.put("box", V.musicbox(m, 4.0, 14.0 * (1 + t), 8.0, 1.8), t, v, pan=0.1)
    _pads(s, [46, 53, 58, 62, 65], 0.0, 2.0, 1.0, 0.3, 2.5)
    _pads(s, [45, 52, 57, 60], 2.2, 1.0, 0.9, 0.5, 2.5, 1)
    n = int(2.0 * SR)
    t = np.arange(n) / SR
    s.put("sub", (np.sin(2 * np.pi * np.cumsum(34 + 50 * np.exp(-t / 0.5)) / SR) * np.exp(-t / 0.9)).astype(np.float32), 0.25, 0.9)
    s.put("kick", V.kick(2, 90.0, 38.0, 0.08, 0.35, 0.05, 0.8), 0.0, 0.5)
    fc = s.auto([(0, 2600), (1.5, 900), (3.2, 350)], 0.4)
    return {"pad": dict(g=-3, hp=120, send=0.6, fx=lambda x: S.lp_sweep(x, fc, 300, 3000)), "box": dict(g=-2, hp=300, send=0.8),
            "sub": dict(g=-7, hp=28, lp=300, send=0.0), "kick": dict(g=-8, hp=30, lp=2000, send=0.05)}


def jump(s):
    n = int(1.3 * SR)
    up = V.riser(n, 3, 200.0, 11000.0)
    s.put("whoosh", up / (np.abs(up).max() + 1e-9), 0.0, 0.9, pan=0.0)
    n2 = int(1.2 * SR)
    dn = V.riser(n2, 4, 150.0, 6000.0)[::-1]
    s.put("whoosh", dn / (np.abs(dn).max() + 1e-9), 1.3, 0.5, pan=0.0)
    t = np.arange(n) / SR
    f = 110 * 2 ** (3.0 * (t / 1.3) ** 1.6)
    ph = np.cumsum(f) / SR
    g = S.saw_blep(ph % 1.0, f / SR) * (t / 1.3) ** 1.3
    s.put("glide", S.filt(g[None, :], lp=3000)[0], 0.0, 0.6, pan=0.0)
    s.put("kick", V.kick(1, 95.0, 30.0, 0.14, 0.8, 0.1, 1.2), 1.3, 1.0)
    for m, pan in ((62, -0.4), (69, 0.0), (74, 0.4), (81, 0.2)):
        s.put("bell", V.bell(m, 3.0, 3.5, 1.5, 1.0), 1.3, 0.5, pan=pan)
    return {"whoosh": dict(g=-6, hp=200, send=0.35), "glide": dict(g=-8, hp=100, send=0.3), "kick": dict(g=-8, hp=30, lp=2500, send=0.05),
            "bell": dict(g=-4, hp=350, send=0.7)}


def region_cross(s):
    _pads(s, [50, 57, 60, 64, 65], 0.0, 1.5, 1.0, 0.5, 1.5)
    _pads(s, [55, 59, 62, 64, 69], 1.5, 1.4, 1.0, 0.5, 2.2, 1)
    for t, m, v in ((0.4, 81, .6), (0.9, 86, .6), (1.8, 88, .5), (2.3, 81, .5)):
        s.put("bell", V.bell(m, 3.0, 3.5, 1.6, 1.2), t, v, pan=0.35 if m != 86 else -0.3)
    s.put("bass", V.bass(38, 1.6, 300.0, 1.2, 1.0, 0.15, 0.2), 0.0, 0.7)
    s.put("bass", V.bass(43, 1.8, 300.0, 1.2, 1.0, 0.15, 0.3), 1.5, 0.7)
    return {"pad": dict(g=-4, hp=140, send=0.5), "bell": dict(g=-2, hp=350, send=0.7), "bass": dict(g=-8, hp=30, lp=700, send=0.05)}


def ada_found(s):
    for b, m, d in T.BEACON:    # the beacon's four notes, close and clean
        s.put("bell", V.bell(m, 3.0, 2.0, 1.0, 1.1), b * 0.45, 0.85, pan=-0.2)
    _pads(s, [50, 57, 60, 64, 65], 1.4, 2.0, 0.9, 0.9, 2.5)
    spb = 60 / 110.0
    for b, m, d in T.notes(62, "dorian", bars=1):    # the theme's first bar, on the music box
        s.put("box", V.musicbox(m, 3.4, 0.0, 0.0, 1.7), 2.1 + b * spb, 0.8 if b else 0.5, pan=0.15)
    s.put("bass", V.bass(38, 3.0, 300.0, 1.2, 1.0, 0.15, 0.3), 1.9, 0.6)
    return {"bell": dict(g=-2, hp=350, send=0.7), "pad": dict(g=-4, hp=140, send=0.5), "box": dict(g=-2, hp=350, send=0.6),
            "bass": dict(g=-9, hp=30, lp=700, send=0.05)}


def unlock(s):
    for k, (t, m) in enumerate(((0.0, 74), (0.09, 76), (0.18, 79), (0.27, 81), (0.36, 84), (0.45, 86))):
        s.put("pluck", V.pluck(m, 0.9, "square", 1.2, 0.4), t, 0.5 + 0.08 * k, pan=-0.5 + 0.2 * k)
    for m, pan in ((81, -0.3), (86, 0.3), (93, 0.0)):
        s.put("bell", V.bell(m, 2.6, 3.5, 1.8, 1.0), 0.55, 0.5, pan=pan)
    _pads(s, [57, 62, 64, 69], 0.3, 0.6, 0.7, 0.2, 1.2)
    return {"pluck": dict(g=-4, hp=260, send=0.4), "bell": dict(g=-3, hp=350, send=0.7), "pad": dict(g=-6, hp=140, send=0.5)}


def ending(s):
    spb = s.spb / SR
    chords = [([50, 57, 60, 64, 65], 38), ([55, 59, 62, 64, 69], 43), ([58, 62, 65, 69, 72], 46), ([57, 60, 64, 67, 71], 45)]
    for k, (ch, root) in enumerate(chords):
        _pads(s, ch, 2 * k * 4, 7.2 * spb, 1.0, 0.35, 1.2, k)
        s.put("bass", V.bass(root, 7.4 * spb, 330.0, 1.2, 1.0, 0.18, 0.12), 2 * k * 4, 0.8)
    for b, m, d in T.notes(62, "dorian"):
        s.put("lead", V.lead(m, d * spb * 0.97, 9.0, 5.2, 0.25, 0.03, 0.5), b, 0.95, pan=0.05)
        s.put("bell", V.bell(m + 12, 2.5, 3.5, 2.0, 1.0), b, 0.28, pan=0.3)
    tones = [[57, 62, 65, 69, 72, 76], [55, 62, 67, 71, 74, 76], [58, 62, 65, 69, 72, 74], [57, 60, 64, 67, 69, 72]]
    for q in range(64):
        s.put("pluck", V.pluck(tones[q // 16][(q * 3) % 6], 0.8, "square", 0.8, 0.4), q * 0.5, 0.28 * (1.0 if q % 2 == 0 else 0.6), pan=(-0.4, 0.4)[q % 2])
    t_end = 32.0      # the last chord: the theme comes home to D
    _pads(s, [38, 50, 57, 62, 65, 69, 76], t_end, 1.2, 1.2, 0.15, 2.0, 5)
    s.put("bell", V.bell(86, 3.5, 3.5, 2.0, 1.4), t_end, 0.7, pan=0.2)
    s.put("bell", V.bell(74, 3.5, 3.5, 2.0, 1.4), t_end, 0.5, pan=-0.2)
    s.put("bass", V.bass(26, 2.0, 300.0, 1.0, 1.0, 0.1, 0.3), t_end, 1.0)
    return {"pad": dict(g=-4, hp=120, send=0.5), "bass": dict(g=-9, hp=28, lp=700, send=0.05), "lead": dict(g=-3, hp=250, send=0.5),
            "bell": dict(g=-3, hp=350, send=0.7), "pluck": dict(g=-6, hp=260, send=0.35)}


# name: (builder, content seconds, trimmed total seconds, bpm, reverb t60, seed)
CFG = {
    "victory": (victory, 2.0, 5.0, 60, 2.6, 71),
    "defeat": (defeat, 4.0, 6.0, 60, 3.0, 72),
    "jump": (jump, 2.5, 4.5, 60, 2.4, 73),
    "region_cross": (region_cross, 3.0, 5.5, 60, 3.0, 74),
    "ada_found": (ada_found, 4.4, 6.0, 60, 3.2, 75),
    "unlock": (unlock, 1.2, 3.2, 60, 2.2, 76),
    "ending": (ending, 8.3, 10.0, 232, 3.2, 77),
}


def render(name):
    fn, content, total, bpm, t60, seed = CFG[name]
    s = Song(bpm, content * bpm / 60 / 4, seed, tail=TAIL)
    spec = fn(s)
    mix = s.mix(spec, S.make_ir(t60, 18, 1.0, seed), -2, 3.0)
    y = mix[:, :int(total * SR)]
    y = S.filt(y, hp=24)
    k = int(0.7 * SR)
    y[:, -k:] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)).astype(np.float32)[None, :]
    # loudness: RMS of the loudest 1.5 s window at -16 dBFS, but never past -2 dBFS peak or -1.35 dBTP
    w = int(1.5 * SR)
    win = max(S.rms_db(y[:, i:i + w]) for i in range(0, max(1, y.shape[1] - w), SR // 4))
    y = y * np.float32(10 ** ((-16.0 - win) / 20))
    y = y * np.float32(min(1.0, 10 ** (-2.0 / 20) / np.abs(y).max(), 10 ** (-1.4 / 20) / S.true_peak(y)))
    render.bpm = bpm
    return y.astype(np.float32)
