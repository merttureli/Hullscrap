"""explore_a.ogg  "Drift"  A aeolian, 80 BPM, 48 bars (2:24).
Am(add9) - Fmaj7 - C - Gsus4, two bars each, six cycles. Cycles 1-2: pad and a sparse 16th pluck arp with the
dotted-eighth echo, no drums. Cycles 3-4: a soft kick and rim; the theme's opening phrase on the lead in cycle 4.
Cycle 5: breakdown with a riser. Cycle 6: drums with light hats, the phrase again on the music box, then thin out."""
import numpy as np
import synth as S
import voices as V
import theme as T
from common import Song

TITLE = "Drift"
RMS = -18.0
BARS = 48
CHORDS = [  # (pad voicing, bass root, arp tones)
    ([52, 57, 60, 64, 71], 33, [57, 60, 64, 69, 71, 72, 76]),     # Am(add9)
    ([53, 57, 60, 64], 29, [57, 60, 64, 65, 69, 72, 76]),         # Fmaj7
    ([52, 55, 60, 64, 67], 36, [60, 64, 67, 72, 74, 76, 79]),     # C
    ([55, 60, 62, 67], 31, [55, 60, 62, 67, 72, 74, 79]),         # Gsus4
]
ARP = [0, 2, 4, 3, 5, 2, 6, 4, 1, 3, 5, 4, 6, 3, 2, 4]
DENS = {"sparse": "x..x..x...x.x...", "mid": "x.xx..x.x.xx..x.", "full": "xxxxxxxxxxxxxxxx"}
ACC = [1.0, 0.45, 0.65, 0.45]


def render():
    s = Song(80, BARS, seed=202)
    bar = lambda b: b * 4.0
    cyc = lambda b: b // 8

    # --- pad and bass
    for k in range(24):
        b0 = 2 * k
        voicing, root, _ = CHORDS[k % 4]
        g = [0.65, 0.75, 0.85, 0.85, 1.0, 0.85][cyc(b0)]
        for m in voicing:
            s.put("pad", V.pad(m, s.sec(8) - 0.15, 1.6, 2.6, seed=k % 4), bar(b0), g * s.v(1.0, 0.05), ms=8)
        if cyc(b0) >= 1 and cyc(b0) != 4:
            s.put("bass", V.bass(root, s.sec(8) - 0.25, 300.0, 1.2, 1.0, 0.18, 0.12, 0.04, 0.6), bar(b0), 0.8)
            if cyc(b0) in (2, 3, 5):   # a pickup pulse a beat before the next chord
                nxt = CHORDS[(k + 1) % 4][1]
                s.put("bass", V.bass(nxt, s.sec(0.9), 300.0, 1.2, 1.0, 0.18, 0.05, 0.02, 0.6), bar(b0 + 2) - 1.0, 0.55)

    # --- the 16th pluck arp
    for b in range(BARS):
        c = cyc(b)
        tones = CHORDS[(b // 2) % 4][2]
        dens = "sparse" if c == 0 else "mid" if c == 1 else "full" if c in (2, 3, 5) else "sparse"
        if c == 4 and b >= 36:
            dens = "mid"
        pat = DENS[dens]
        for st in range(16):
            if pat[st] != "x":
                continue
            if b >= 46:   # thin out into the loop
                if st % 4:
                    continue
            n = ARP[(b * 16 + st) % 16]
            lvl = [0.5, 0.65, 0.8, 0.9, 0.6, 0.85][c]
            s.put("pluck", V.pluck(tones[n], 1.4, "saw" if c >= 2 else "square", 0.7 + 0.15 * c, 0.5),
                  bar(b) + st / 4.0, lvl * ACC[st % 4] * s.v(1.0, 0.15), pan=(-0.5, 0.5)[(st // 2) % 2] * 0.8, ms=5)

    # --- bell pings on chord changes (cycles 2-6)
    for k in range(8, 24):
        if k // 4 == 4 and k % 2:
            continue
        tones = CHORDS[k % 4][2]
        s.put("bell", V.bell(tones[(k * 3) % 7] + 12, 3.4, 3.5, 1.8, 1.4), bar(2 * k) + 0.5, 0.45, pan=(-0.5, 0.5)[k % 2], ms=4)

    # --- drums: soft kick and rim from bar 16, light hats in cycle 6, breakdown without
    for b in range(16, 46):
        if cyc(b) == 4:
            continue
        for beat, vel in ((0, 0.55), (2, 0.42), (2.75, 0.2) if b % 4 == 3 else (3.5, 0.0)):
            if vel:
                s.put("kick", V.kick(b % 3), bar(b) + beat, vel * s.v(1, 0.1), ms=3)
        for beat, vel in ((1, 0.5), (3, 0.6), (3.75 if b % 4 == 1 else 1.75, 0.15)):
            s.put("rim", V.rim(b % 3), bar(b) + beat, vel * s.v(1, 0.15), pan=0.2, ms=3)
        if cyc(b) == 5:
            for j in range(8):
                s.put("hat", V.hat(j % 3, False), bar(b) + j / 2, (0.4 if j % 2 else 0.22) * s.v(1, 0.2), pan=0.3, ms=3)
    # a riser through the end of the breakdown into the last cycle
    s.put("riser", V.riser(int(s.sec(bar(7)) * S.SR), 5), bar(33), 0.0 + 0.5, 0.0)

    # --- the theme's opening phrase, A aeolian: lead in cycle 4, music box in cycle 6
    for b, m, d in T.notes(57, "aeolian", start=bar(26), bars=2, shift=12):
        s.put("lead", V.lead(m, s.sec(d) * 0.95), b, s.v(0.9, 0.06), pan=0.1, ms=6)
    for b, m, d in T.notes(57, "aeolian", start=bar(42), bars=2, shift=24):
        s.put("box", V.musicbox(m, 3.4, 0.0, 0.0, 1.6), b, s.v(0.55, 0.08), pan=-0.1, ms=5)

    # --- texture
    s.part("tex").put(V.hiss(s.L, 5) * (0.6 + 0.4 * S.lfo(s.L, 0.05)), 0, 1.0, 0.0)
    s.part("tex").put(V.crackle(s.L, 6, 4.0) * 0.5, 0, 1.0, 0.0)

    # --- mix
    cut = s.auto([(0, 1000), (bar(8), 1250), (bar(16), 1500), (bar(32), 1900), (bar(40), 1500), (bar(46), 1100)], 3.0)
    pad_fc = cut * (1 + 0.3 * S.lfo(s.L, 0.045))

    def pad_fx(x):
        y = S.lp_sweep(x, pad_fc, 450, 3000)
        return y * 0.6 + 0.4 * S.chorus(y, 0.23, 20, 3.2, mix=1.0)

    echo = lambda x: x + 0.6 * S.pingpong(x, 0.75 * s.spb, 0.55)
    spec = {
        "pad": dict(g=-5, hp=140, send=0.5, fx=pad_fx),
        "bass": dict(g=-9, hp=30, lp=700, send=0.05),
        "pluck": dict(g=-4, hp=260, lp=8000, send=0.35, fx=echo),
        "bell": dict(g=0, hp=350, send=0.7),
        "lead": dict(g=-2, hp=250, send=0.5),
        "box": dict(g=-2, hp=350, send=0.6),
        "kick": dict(g=-3, hp=30, lp=2500, send=0.05),
        "rim": dict(g=-6, hp=300, send=0.25),
        "hat": dict(g=-8, hp=5000, send=0.15),
        "riser": dict(g=-13, hp=300, send=0.3),
        "tex": dict(g=-23, hp=1200, send=0.0),
    }
    env = s.auto([(0, 0.8), (bar(8), 0.9), (bar(16), 1.0), (bar(32), 0.85), (bar(40), 1.0), (bar(46), 0.8)], 2.5)
    mix = s.mix(spec, S.make_ir(4.5, 28, 1.0, 12), -3, 5.0, env)
    render.levels = s.levels(spec)
    render.bpm = s.bpm
    return S.master(mix, RMS)
