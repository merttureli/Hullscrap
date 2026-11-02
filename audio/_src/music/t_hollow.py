"""hollow.ogg  "Manners"  no key centre (whole-tone sets and semitone clusters), 60 BPM free, 30 bars (2:00).
Detuned pads with a seasick chorus, a beating sub drone, reverse swells, the theme at half speed on a music box that drifts
further out of tune, the beacon's four notes far away every 15 s, radio static with tuning whistles and a murmur.
Polite and wrong."""
import numpy as np
import synth as S
import voices as V
import theme as T
from common import Song
from synth import SR

TITLE = "Manners"
RMS = -18.0
BARS = 30
PADS = [(0, 22, [48, 52, 56, 62], 0.7), (18, 22, [49, 50, 56, 57], 0.8), (40, 24, [50, 54, 58, 60], 0.9),
        (62, 24, [47, 48, 54, 55], 1.0), (84, 22, [48, 52, 56, 62, 66], 0.9), (104, 22, [49, 50, 56, 57], 0.8)]


def render():
    s = Song(60, BARS, seed=505)          # one beat = one second
    rng = np.random.default_rng(9)
    for k, (t0, d, ch, g) in enumerate(PADS):
        for m in ch:
            s.put("pad", V.pad(m, d - 6.0, 5.0, 6.0, 25.0, 9.0, seed=k), t0, g * s.v(1.0, 0.06), ms=0)

    # sub drone: two sines a hair apart (beats once every ~1.4 s); whole cycles so the loop is seamless
    t = np.arange(s.L)
    c1, c2 = S.cycles(41.2, s.L), S.cycles(42.6, s.L)
    drone = (0.6 * np.sin(2 * np.pi * c1 * t / s.L) + 0.5 * np.sin(2 * np.pi * c2 * t / s.L)) * (0.55 + 0.45 * S.lfo(s.L, 0.03))
    s.part("drone").put(drone.astype(np.float32), 0, 1.0, 0.0)

    # the theme, half speed, on a music box that drifts out of tune; later it sticks on its first two bars
    notes = T.notes(62, "dorian", speed=0.5, start=24.0, shift=12)
    for i, (b, m, d) in enumerate(notes):
        prog = (b - 24.0) / 64.0                     # 0..1 through the statement
        cents = float(rng.uniform(-1, 1)) * (10 + 55 * prog)
        wrong = 1 if rng.random() < 0.18 * prog else 0     # now and then a note a semitone off
        s.put("box", V.musicbox(m + wrong, 4.0, round(cents / 5) * 5.0, 14.0, 1.8), b, (0.85 - 0.2 * prog) * s.v(1.0, 0.1), pan=float(rng.uniform(-0.3, 0.3)), ms=45)
    for rep in range(3):
        for b, m, d in T.notes(62, "dorian", speed=0.5, start=92.0 + rep * 8.5, bars=2, shift=12):
            c = float(rng.uniform(-60, 40))
            s.put("box", V.musicbox(m, 4.0, round(c / 5) * 5.0, 18.0, 2.0), b, (0.55 - 0.14 * rep) * s.v(1.0, 0.1), pan=(-0.4, 0.4, -0.2)[rep], ms=50)
    # "wrong chords": a semitone cluster struck together
    for t0, ch in ((52.0, [61, 62, 68, 69]), (76.0, [66, 67, 73, 74]), (100.5, [60, 61, 67, 68])):
        for m in ch:
            s.put("box", V.musicbox(m + 12, 5.0, float(rng.uniform(-30, 30)), 25.0, 2.4), t0 + float(rng.uniform(0, 0.12)), 0.5, pan=float(rng.uniform(-0.5, 0.5)))

    # reverse swells that land on the next event (the last one wraps into the loop start)
    def swell(m, end_t, gain, pan):
        ring = 4.5
        n = S.smooth_len(int(ring * 1.5 * SR))
        z = np.zeros((2, n), np.float32)
        note = V.musicbox(m, ring, 20.0, 12.0, 2.5)
        z[:, :len(note)] = note
        rev = S.reverb(z, S.make_ir(3.2, 20, 0.9, 21))[:, ::-1]
        s.part("swell").put(rev * np.float32(gain) * np.array([[1 - 0.5 * pan], [1 + 0.5 * pan]], np.float32), s.at(end_t) - n, 1.0)
    for end_t, m, g, p in ((23.9, 74, 0.8, -0.3), (51.9, 61, 0.9, 0.3), (75.9, 66, 0.9, -0.4), (99.9, 60, 1.0, 0.4), (119.9, 69, 1.0, 0.0)):
        swell(m, end_t, g, p)

    # the beacon far away: E5 B4 D5 ... A4, every 15 s, quietest first and last
    for k, t0 in enumerate(range(6, 120, 15)):
        lvl = (0.45, 0.6, 0.8, 0.95, 1.0, 0.95, 0.8, 0.6)[k]
        for b, m, d in T.BEACON:
            s.put("beacon", V.bell(m, 4.0, 2.0, 1.0, 1.0), t0 + b * 1.7 / 1.0, lvl * s.v(1.0, 0.04), pan=-0.65, ms=0)

    # radio static, tuning whistles, a murmur
    ramp = s.auto([(0, 0.4), (30, 0.8), (84, 1.1), (110, 1.4)], 6.0)
    for c, seed in ((0, 3), (1, 4)):
        s.part("static").buf[c] += V.static(s.L, seed, 900.0, 6000.0, 0.9, 0.2) * ramp
    s.part("static").buf += V.crackle(s.L, 8, 6.0, 5000)[None, :] * 0.6
    for t0 in (13.0, 44.0, 67.0, 90.0, 109.0):
        n = int(1.6 * SR)
        f = 1400 + 900 * (np.arange(n) / n) ** 1.5 * rng.choice([-1, 1]) + 200 * rng.random()
        w = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * np.arange(n) / n) ** 2
        s.put("whistle", w.astype(np.float32), t0, 0.5, pan=float(rng.uniform(-0.6, 0.6)))
    mur = np.zeros(s.L, np.float32)
    nz = np.random.default_rng(31).standard_normal(s.L).astype(np.float32)
    syll = np.clip(S.band(np.random.default_rng(32).standard_normal(s.L).astype(np.float32)[None, :], 0.4, 5.0)[0], 0, None)
    syll = (syll / (syll.max() + 1e-9)) ** 1.5
    voice = S.band(nz[None, :], 350, 900)[0] + 0.7 * S.band(nz[None, :], 1300, 2300)[0]
    gate = s.auto([(0, 0), (38, 1), (48, 0), (60, 0.8), (66, 0), (93, 1), (104, 0)], 1.5)
    s.part("murmur").put((voice * syll * gate)[None, :].repeat(2, 0) * 0.5, 0, 1.0)

    # --- mix
    pad_fc = (650 + 330 * S.lfo(s.L, 0.04)) * (1 + 0.25 * S.lfo(s.L, 0.11, 1.0))

    def pad_fx(x):
        y = S.lp_sweep(x, pad_fc, 300, 1800)
        return y * 0.55 + 0.45 * S.chorus(y, 0.17, 24, 7.0, 0.7, 1.0)

    spec = {
        "pad": dict(g=-4, hp=120, send=0.6, fx=pad_fx),
        "drone": dict(g=-12, hp=28, lp=160, send=0.0),
        "box": dict(g=-1, hp=300, send=0.9),
        "swell": dict(g=-5, hp=250, send=0.3),
        "beacon": dict(g=-8, hp=500, lp=3800, send=2.2, fx=lambda x: x * 0.3),
        "static": dict(g=-21, hp=800, lp=7000, send=0.1),   # 6 dB under round 1
        "whistle": dict(g=-13, hp=600, send=0.4),
        "murmur": dict(g=-2, hp=300, lp=3500, send=0.7),
    }
    mix = s.mix(spec, S.make_ir(7.0, 40, 0.8, 23), -2, 3.0)
    render.levels = s.levels(spec)
    render.bpm = s.bpm
    return S.master(mix, RMS)
