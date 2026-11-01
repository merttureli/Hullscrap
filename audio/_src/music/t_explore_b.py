"""explore_b.ogg  "Salvage Lanes"  E dorian, 88 BPM, 56 bars (2:33).
Eight-bar cycle: Em9 Em9 A7 A7 Bm7 Gmaj7 Dmaj7 A7sus, seven times. A walking bass, shuffled hats and a brush backbeat, scrap-metal
clanks as texture, an 8th-note pluck arp, and the theme (in E dorian) on the FM keys in cycles 4 and 6.
Cycle 1 intro, 5 breakdown (clanks, no drums), 7 outro."""
import numpy as np
import synth as S
import voices as V
import theme as T
from common import Song

TITLE = "Salvage Lanes"
RMS = -18.0
BARS = 56
SW = 0.64      # the shuffle: where the offbeat 8th falls inside the beat
CH = [  # pad voicing, keys voicing, bass tones (root, 3rd, 5th, 7th, octave), arp tones
    dict(pad=[52, 55, 59, 62, 66], keys=[59, 62, 66, 67], bass=[40, 43, 47, 50, 52], arp=[64, 67, 71, 74, 78, 76]),   # Em9
    dict(pad=[57, 61, 64, 67], keys=[61, 64, 67, 69], bass=[45, 49, 52, 55, 57], arp=[64, 67, 69, 73, 76, 79]),       # A7
    dict(pad=[59, 62, 66, 69], keys=[62, 66, 69, 71], bass=[47, 50, 54, 57, 59], arp=[62, 66, 69, 71, 74, 78]),       # Bm7
    dict(pad=[55, 59, 62, 66], keys=[59, 62, 66, 67], bass=[43, 47, 50, 54, 55], arp=[62, 67, 71, 74, 78, 79]),       # Gmaj7
    dict(pad=[57, 62, 66, 69, 73], keys=[62, 66, 69, 73], bass=[38, 42, 45, 49, 50], arp=[62, 66, 69, 73, 74, 78]),   # Dmaj7
    dict(pad=[57, 62, 64, 67], keys=[62, 64, 67, 69], bass=[45, 50, 52, 55, 57], arp=[62, 64, 67, 69, 74, 76]),       # A7sus
]
BAR_CH = [0, 0, 1, 1, 2, 3, 4, 5]   # chord of each bar in the cycle


def render():
    s = Song(88, BARS, seed=303)
    bar = lambda b: b * 4.0
    cyc = lambda b: b // 8
    chord = lambda b: CH[BAR_CH[b % 8]]

    # --- pad, one note per chord change
    for b in range(BARS):
        if b % 8 in (1, 3):
            continue
        n = 2 if b % 8 in (0, 2) else 1
        c = chord(b)
        g = [0.6, 0.75, 0.8, 0.85, 1.0, 0.85, 0.7][cyc(b)]
        for m in c["pad"]:
            s.put("pad", V.pad(m, s.sec(bar(n)) - 0.1, 1.2, 2.2, seed=b % 8), bar(b), g * s.v(1.0, 0.05), ms=8)

    # --- bass: sparse in the intro, walking from cycle 2, held roots in the breakdown
    for b in range(BARS):
        c, nxt = chord(b), CH[BAR_CH[(b + 1) % 8]]
        tn = c["bass"]
        if cyc(b) == 0 or cyc(b) == 4:
            if b % 2 == 0 or cyc(b) == 0:
                s.put("bass", V.bass(tn[0], s.sec(3.8), 330.0, 1.2, 1.0, 0.2, 0.15, 0.03, 0.6), bar(b), 0.7 if cyc(b) == 0 else 0.8, ms=3)
            continue
        app = nxt["bass"][0] + (-1 if b % 2 == 0 else 1)
        seq = [tn[0], tn[2] if b % 2 == 0 else tn[1], tn[1] if b % 2 == 0 else tn[3], app]
        for j, m in enumerate(seq):
            s.put("bass", V.bass(m, s.sec(0.92), 420.0, 1.5, 1.0, 0.3, 0.06, 0.01, 1.0), bar(b) + j, (0.95 if j == 0 else 0.78) * s.v(1.0, 0.08), ms=4)

    # --- keys: rolled comping stabs (cycles 2-3, 6-7), theme on keys in cycles 4 and 6
    for b in range(8, BARS):
        c = cyc(b)
        if c in (0, 4):
            continue
        if c == 1 and b < 12:
            continue
        v = chord(b)["keys"]
        stabs = ((0.0, 1.6, 0.8), (2.5, 1.0, 0.6)) if c != 6 else ((0.0, 1.6, 0.6),)
        for beat, d, vel in stabs:
            for i, m in enumerate(v):
                s.put("keys", V.keys(m, s.sec(d), 3 if beat == 0 else 2, 1.8, 0.5, 1.0), bar(b) + beat + i * 0.04, vel * s.v(1.0, 0.1), pan=-0.25 + 0.1 * i, ms=4)
    for start, shift, vel in ((24, 0, 1.0), (40, 0, 0.9)):
        for b, m, d in T.notes(64, "dorian", start=bar(start), bars=4, shift=shift):
            s.put("keys", V.keys(m, s.sec(d) * 0.95, 4, 2.4, 0.7, 1.6), b, vel * s.v(1.0, 0.06), pan=0.15, ms=5)
    for b, m, d in T.notes(64, "dorian", start=bar(40), bars=2, shift=12):
        s.put("bell", V.bell(m, 3.0, 3.5, 2.0, 1.0), b, 0.3, pan=0.35, ms=4)

    # --- shuffled 8th pluck arp in cycles 3, 4, 6 (and a thin one in 7)
    for b in range(16, BARS):
        c = cyc(b)
        if c not in (2, 3, 5, 6):
            continue
        tones = chord(b)["arp"]
        for st in range(8):
            if c == 6 and st % 2:
                continue
            if c == 3 and b < 28 and st % 2 and b % 2:
                continue
            n = (3 * st + b) % 6
            beat = bar(b) + st // 2 + (SW if st % 2 else 0.0)
            s.put("pluck", V.pluck(tones[n], 1.1, "saw", 0.9, 0.4), beat, (0.8 if st % 2 == 0 else 0.55) * (1.0 if c != 6 else 0.7) * s.v(1.0, 0.15),
                  pan=(-0.55, 0.55)[st % 2], ms=4)

    # --- drums: hats from bar 4, kick + brush from bar 8; none in the breakdown
    for b in range(4, BARS):
        c = cyc(b)
        if c == 4:
            continue
        for j in range(4):
            s.put("hat", V.hat(j % 3, False), bar(b) + j, (0.35 if j % 2 == 0 else 0.25) * s.v(1, 0.2), pan=0.3, ms=3)
            s.put("hat", V.hat((j + 1) % 3, False), bar(b) + j + SW, (0.5 if j % 2 else 0.4) * s.v(1, 0.2), pan=0.3, ms=3)
        if b % 4 == 3 and c in (2, 3, 5):
            s.put("hat", V.hat(0, True), bar(b) + 3 + SW, 0.4, pan=0.3, ms=3)
        if b < 8 or c == 6 and b >= 52:
            continue
        s.put("kick", V.kick(b % 3), bar(b), 0.8 * s.v(1, 0.1), ms=3)
        s.put("kick", V.kick((b + 1) % 3), bar(b) + 2.0, 0.55 * s.v(1, 0.1), ms=3)
        if b % 2:
            s.put("kick", V.kick(2), bar(b) + 2 + SW, 0.35, ms=3)
        for j in (1, 3):
            s.put("brush", V.brush(j + b % 2), bar(b) + j, 0.85 * s.v(1, 0.1), pan=-0.2, ms=3)

    # --- scrap-metal clanks as texture (random but seeded)
    prob = [0.15, 0.28, 0.32, 0.35, 0.9, 0.32, 0.22]
    for b in range(BARS):
        if s.rng.random() < prob[cyc(b)]:
            for _ in range(1 + int(s.rng.random() < (0.7 if cyc(b) == 4 else 0.2))):
                pos = float(s.rng.choice([0.5, 1.25, 1.5, 2.5, 2.75, 3.25, 3.5]))
                base = float(s.rng.choice([310.0, 410.0, 560.0, 720.0, 880.0]))
                s.put("clank", V.clank(int(s.rng.integers(0, 6)), base, 0.5 + 0.4 * float(s.rng.random())), bar(b) + pos,
                      float(s.rng.uniform(0.3, 0.6)), pan=float(s.rng.uniform(-0.8, 0.8)), ms=0)
    s.put("riser", V.riser(int(s.sec(bar(7)) * S.SR), 9), bar(33), 0.5)

    # --- texture
    s.part("tex").put(V.hiss(s.L, 5) * (0.6 + 0.4 * S.lfo(s.L, 0.05)), 0, 1.0, 0.0)
    s.part("tex").put(V.crackle(s.L, 6, 4.0) * 0.5, 0, 1.0, 0.0)

    # --- mix
    cut = s.auto([(0, 1100), (bar(8), 1400), (bar(16), 1700), (bar(32), 2000), (bar(40), 1700), (bar(48), 1500)], 3.0)
    pad_fc = cut * (1 + 0.3 * S.lfo(s.L, 0.05))

    def pad_fx(x):
        y = S.lp_sweep(x, pad_fc, 450, 3200)
        return y * 0.6 + 0.4 * S.chorus(y, 0.25, 19, 3.0, mix=1.0)

    echo = lambda x: x + 0.5 * S.pingpong(x, 0.75 * s.spb, 0.5)
    spec = {
        "pad": dict(g=-7, hp=140, send=0.5, fx=pad_fx),
        "bass": dict(g=-12, hp=30, lp=800, send=0.05),
        "keys": dict(g=-2, hp=160, lp=8000, send=0.4),
        "pluck": dict(g=-3, hp=260, lp=8000, send=0.35, fx=echo),
        "bell": dict(g=3, hp=350, send=0.7),
        "kick": dict(g=-5, hp=30, lp=2500, send=0.05),
        "brush": dict(g=-6, hp=500, send=0.2),
        "hat": dict(g=-5, hp=5000, send=0.15),
        "clank": dict(g=-7, hp=250, send=0.6),
        "riser": dict(g=-13, hp=300, send=0.3),
        "tex": dict(g=-23, hp=1200, send=0.0),
    }
    env = s.auto([(0, 0.8), (bar(8), 0.9), (bar(16), 1.0), (bar(32), 0.85), (bar(40), 1.0), (bar(52), 0.85)], 2.5)
    mix = s.mix(spec, S.make_ir(3.8, 24, 1.0, 13), -3, 5.0, env)
    render.levels = s.levels(spec)
    render.bpm = s.bpm
    return S.master(mix, RMS)
