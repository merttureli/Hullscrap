"""build.ogg  "Workbench"  G mixolydian, 76 BPM, 32 bars (1:41).
Eight-bar cycle G6/9 Fmaj7 Cmaj9 Dm7-G7 | G6/9 Fmaj7 Em7 Dm7-G7, four times. FM electric piano (arpeggiated in the intro, comping
after), a warm bass, brush drums, vinyl crackle and small tool clinks. Cycle 2 melody on the keys, cycle 3 on the soft lead with the
theme's opening on the keys; cycle 4 winds down."""
import numpy as np
import synth as S
import voices as V
import theme as T
from common import Song

TITLE = "Workbench"
RMS = -18.0
BARS = 32
SW = 0.6
# per bar of the cycle: [(beat, keys voicing, bass root)]
BARS8 = [
    [(0, [59, 62, 64, 69], 43)],
    [(0, [57, 60, 64, 65], 41)],
    [(0, [59, 62, 64, 67], 36)],
    [(0, [57, 60, 62, 65], 38), (2, [59, 62, 65, 67], 43)],
    [(0, [59, 62, 64, 69], 43)],
    [(0, [57, 60, 64, 65], 41)],
    [(0, [55, 59, 62, 64], 40)],
    [(0, [57, 60, 62, 65], 38), (2, [59, 62, 65, 67], 43)],
]
MEL = [   # (beat in the cycle, midi, beats): G mixolydian melody over the eight bars
    (0, 74, 1.5), (1.5, 71, .5), (2, 69, 1), (3, 67, 1),
    (4, 72, 2), (6, 69, 1), (7, 67, 1),
    (8, 71, 1.5), (9.5, 74, .5), (10, 76, 1.5), (11.5, 74, .5),
    (12, 72, 1), (13, 69, 1), (14, 71, 1), (15, 74, 1),
    (16, 76, 1.5), (17.5, 74, .5), (18, 71, 1), (19, 69, 1),
    (20, 72, 1.5), (21.5, 69, .5), (22, 67, 1), (23, 65, 1),
    (24, 71, 1.5), (25.5, 67, .5), (26, 71, 1), (27, 74, 1),
    (28, 69, 2), (30, 71, 1), (31, 69, 1),
]


def render():
    s = Song(76, BARS, seed=606)
    bar = lambda b: b * 4.0
    cyc = lambda b: b // 8

    for b in range(BARS):
        c, bi = cyc(b), b % 8
        for beat, vo, root in BARS8[bi]:
            nxt = 2.0 if len(BARS8[bi]) > 1 and beat == 0 else 2.0 if beat == 2 else 4.0
            # soft pad under the keys from cycle 2
            if c >= 1:
                for m in vo:
                    s.put("pad", V.pad(m - 12, s.sec(nxt) - 0.1, 0.5, 1.2, 7.0, 3.0, seed=bi), bar(b) + beat, (0.6 if c != 3 else 0.45) * s.v(1.0, 0.05), ms=6)
            # keys: rolled arpeggio in the intro cycle, comping after
            if c == 0:
                for j, m in enumerate(vo + vo[::-1][1:3]):
                    pos = beat + (j // 2) + (SW if j % 2 else 0.0)
                    if pos < beat + nxt:
                        s.put("keys", V.keys(m, s.sec(0.9), 2, 1.6, 0.5, 1.0), bar(b) + pos, 0.7 * s.v(1.0, 0.12), pan=-0.3 + 0.15 * j, ms=6)
            else:
                stabs = [(beat, 1.7 if nxt > 2 else 1.4, 3, 0.85)]
                if c in (1, 2) and nxt > 2:
                    stabs.append((beat + 2 + SW - 0.1, 1.0, 2, 0.6))
                for pos, d, vel, g in stabs:
                    for i, m in enumerate(vo):
                        s.put("keys", V.keys(m, s.sec(d), vel, 1.7, 0.5, 1.0), bar(b) + pos + i * 0.035, g * s.v(1.0, 0.1), pan=-0.3 + 0.2 * i, ms=8)
            # bass
            if c >= 0 and not (c == 0 and b < 4):
                s.put("bass", V.bass(root, s.sec(1.4), 380.0, 1.4, 1.0, 0.35, 0.1, 0.01, 0.8), bar(b) + beat, 0.9 * s.v(1.0, 0.06), ms=5)
                if nxt > 2:
                    s.put("bass", V.bass(root + (7 if b % 2 == 0 else 12), s.sec(0.8), 380.0, 1.4, 1.0, 0.3, 0.08, 0.01, 0.8), bar(b) + beat + 2, 0.6, ms=5)
                    if b % 4 == 3 or bi == 6:
                        s.put("bass", V.bass(root, s.sec(0.4), 380.0, 1.4, 1.0, 0.3, 0.05, 0.01, 0.8), bar(b) + beat + 3 + SW - 0.1, 0.45, ms=5)

    # --- melody: keys in cycle 2, soft lead in cycle 3; the theme's opening on the keys in cycle 3
    for b0, part in ((8, "keys"), (16, "lead")):
        for beat, m, d in MEL:
            if part == "keys":
                s.put("keys", V.keys(m, s.sec(d) * 0.9, 3, 2.2, 0.8, 1.4), bar(b0) + beat + (SW - 0.5 if beat % 1 == 0.5 else 0), 0.9 * s.v(1.0, 0.1), pan=0.2, ms=8)
            else:
                s.put("lead", V.lead(m, s.sec(d) * 0.92), bar(b0) + beat + (SW - 0.5 if beat % 1 == 0.5 else 0), 0.8 * s.v(1.0, 0.08), pan=0.15, ms=8)
    for b, m, d in T.notes(55, "mixolydian", start=bar(28), bars=2):
        s.put("keys", V.keys(m, s.sec(d) * 0.9, 2, 2.0, 0.8, 1.4), b, 0.8 * s.v(1.0, 0.06), pan=0.25, ms=8)

    # --- drums: brush backbeat from bar 4; a soft kick; shaker hat
    for b in range(4, BARS):
        c = cyc(b)
        for j in (1, 3):
            s.put("brush", V.brush(j + b % 2, 0.34, 1400, 7500, 0.09), bar(b) + j, (0.9 if c != 3 else 0.6) * s.v(1.0, 0.1), pan=-0.2, ms=6)
        if c in (1, 2) or b >= 8:
            s.put("kick", V.kick(b % 3, 120.0, 50.0, 0.04, 0.2, 0.1), bar(b), 0.55 * s.v(1.0, 0.1), ms=5)
            if c != 3:
                s.put("kick", V.kick((b + 1) % 3, 120.0, 50.0, 0.04, 0.2, 0.1), bar(b) + 2.0 + SW - 0.1, 0.4 * s.v(1.0, 0.1), ms=5)
        if c in (1, 2):
            for j in range(4):
                s.put("hat", V.hat(j % 3, False, 8000), bar(b) + j + SW, 0.35 * s.v(1.0, 0.2), pan=0.3, ms=5)
        if b % 8 == 7:
            s.put("rim", V.rim(1), bar(b) + 3.5 + 0.1, 0.4, pan=0.2, ms=4)

    # --- small tool clinks and vinyl
    for b in range(BARS):
        if s.rng.random() < (0.5 if cyc(b) in (1, 2) else 0.3):
            pos = float(s.rng.choice([0.5, 1.5, 2.25, 3.25, 3.75]))
            s.put("clink", V.clank(int(s.rng.integers(0, 6)), float(s.rng.choice([1500.0, 1900.0, 2300.0])), 0.1, 0.5), bar(b) + pos,
                  float(s.rng.uniform(0.3, 0.7)), pan=float(s.rng.uniform(-0.8, 0.8)))
    s.part("tex").put(V.hiss(s.L, 5) * 0.6, 0, 1.0, 0.0)
    s.part("tex").put(V.crackle(s.L, 6, 9.0) * 0.8, 0, 1.0, 0.0)

    # --- mix
    pad_fc = 1000 * (1 + 0.3 * S.lfo(s.L, 0.07))

    def pad_fx(x):
        y = S.lp_sweep(x, pad_fc, 400, 2200)
        return y * 0.6 + 0.4 * S.chorus(y, 0.2, 18, 3.0, mix=1.0)

    keys_fx = lambda x: S.chorus(x, 0.6, 6, 1.2, 0.0, 0.3)    # a hint of vibrato-chorus on the e-piano
    spec = {
        "pad": dict(g=-8, hp=140, send=0.5, fx=pad_fx),
        "keys": dict(g=-2, hp=150, lp=7500, send=0.3, fx=keys_fx),
        "lead": dict(g=-3, hp=250, send=0.4),
        "bass": dict(g=-9, hp=30, lp=900, send=0.04),
        "kick": dict(g=-2, hp=30, lp=2000, send=0.03),
        "brush": dict(g=-6, hp=500, send=0.2),
        "hat": dict(g=-2, hp=5000, send=0.1),
        "rim": dict(g=0, hp=300, send=0.2),
        "clink": dict(g=-5, hp=800, send=0.45),
        "tex": dict(g=-23, hp=1000, send=0.0),
    }
    env = s.auto([(0, 0.85), (bar(4), 1.0), (bar(28), 0.9)], 2.0)
    mix = s.mix(spec, S.make_ir(2.8, 16, 1.0, 27), -4, 4.0, env)
    render.levels = s.levels(spec)
    render.bpm = s.bpm
    return S.master(mix, RMS)
