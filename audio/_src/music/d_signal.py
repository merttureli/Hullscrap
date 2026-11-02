"""Demo 1, "Signal": psybient in F# dorian, 92 BPM, 28 bars (about 73 s), EXPLORE and BATTLE.
Harmony, one chord per two bars: F#m9 - B6/9 (the dorian IV) - Dmaj9 (bVI) - Eadd9 (bVII), rootless voicings that move
by step around a held E/F#. The intro is F#m9 - F#m9 - Dmaj9 - Eadd9, then A (4-11), B (12-19), C (20-27).
EXPLORE: a slow-filtered analog pad, a deep clean sub, a squelchy acid line on an F# pedal (16ths, accents, slides;
its cutoff rides an envelope per note, a slow LFO and the sections), glassy plucks in a dotted-eighth pattern,
sparse ticks, and the beacon's four notes (moved up a tone to F# C# E . B) on glass at bars 1, 12 and 20.
BATTLE: the same parts plus a half-time breakbeat with ghost notes, a distorted mid bass, trance-gated chord stabs,
reversed cymbals into each section, and glitch fills (a 32nd stutter ending every 4 bars, a roll and a crush sweep
ending every 8, a tape-stop into the loop)."""
import numpy as np
import synth as S
import synth2 as S2
import voices as V
import voices2 as V2
from demo import Demo, once

TITLE = "Signal"
RMS = {"explore": -18.0, "battle": -15.0}
BARS = 28
# name: (pad voicing, sub root, acid colours (A, B), glass tones)
CH = {
    "i": ([57, 61, 64, 68], 30, (45, 52), [69, 73, 76, 80, 81, 85]),      # F#m9: A C# E G#
    "IV": ([56, 61, 63, 66], 35, (51, 44), [68, 71, 73, 75, 78, 80]),     # B6/9: G# C# D# F#
    "bVI": ([57, 61, 64, 66], 38, (45, 50), [69, 73, 74, 76, 78, 81]),    # Dmaj9: A C# E F#
    "bVII": ([56, 59, 64, 66], 40, (44, 47), [68, 71, 76, 78, 80, 83]),   # Eadd9: G# B E F#
}
PLAN = ["i", "i", "bVI", "bVII"] + ["i", "i", "IV", "IV", "bVI", "bVI", "bVII", "bVII"] * 3
# the acid riff over two bars: (16th step, tone, accent, slide); tones 0 F#2, 1 F#3, 2 C#3, 3 and 4 the chord's colours
RIFF = [(0, 0, 1, 0), (1, 0, 0, 0), (2, 1, 0, 1), (4, 0, 0, 0), (5, 2, 1, 0), (7, 0, 0, 0), (8, 3, 1, 0), (9, 0, 0, 0),
        (10, 1, 0, 1), (11, 0, 0, 0), (13, 2, 0, 0), (14, 4, 1, 0), (15, 2, 0, 1),
        (16, 0, 1, 0), (18, 0, 0, 0), (19, 1, 1, 0), (20, 2, 0, 1), (21, 0, 0, 0), (23, 3, 0, 0), (24, 0, 1, 0),
        (25, 0, 0, 0), (26, 4, 0, 1), (27, 3, 0, 0), (28, 1, 1, 0), (30, 2, 0, 0), (31, 0, 0, 1)]
GLASS = [[0, 2, 4, 3, 1], [2, 4, 5, 3, 2]]   # tone indices on 16th steps 0, 3, 6, 9, 12
BEACON = [(0.0, 78, 0.9), (1.0, 73, 0.9), (2.0, 76, 0.9), (4.0, 71, 2.5)]   # the beacon, up a tone: F# C# E . B
# the half-time break over two bars: 16th step -> velocity
KICK = {0: 1.0, 3: 0.55, 10: 0.8, 16: 1.0, 22: 0.7, 27: 0.6}
SNARE = {8: 1.0, 24: 1.0}
GHOST = {6: 0.28, 14: 0.22, 15: 0.32, 19: 0.25, 29: 0.3, 31: 0.22}
STAB_GATE = "x..x..x.x..x.xx."


def render():
    s = Demo(92, BARS, seed=211)
    bar = lambda b: b * 4.0
    sec_of = lambda b: "intro" if b < 4 else "A" if b < 12 else "B" if b < 20 else "C"
    spans = []   # merge repeated chords into (first bar, bars, chord)
    for b, c in enumerate(PLAN):
        if spans and spans[-1][2] == c and spans[-1][0] + spans[-1][1] == b and spans[-1][1] < 2:
            spans[-1][1] += 1
        else:
            spans.append([b, 1, c])

    # --- pad and sub
    for k, (b0, nb, c) in enumerate(spans):
        voicing, root = CH[c][0], CH[c][1]
        g = {"intro": 0.6, "A": 0.8, "B": 0.95, "C": 0.85}[sec_of(b0)]
        for m in voicing:
            s.put("pad", V.pad(m, s.sec(bar(nb)) - 0.1, 1.6, 2.8, 8.0, seed=k % 4), bar(b0), g * s.v(1.0, 0.04), ms=6)
        for j in range(nb):
            if b0 + j < 1:
                continue
            s.put("sub", V.bass(root, s.sec(2.4), 180.0, 1.15, 1.0, 0.0, 0.18, 0.03, 0.0), bar(b0 + j), 0.9)
            s.put("sub", V.bass(root, s.sec(1.1), 180.0, 1.15, 1.0, 0.0, 0.14, 0.02, 0.0), bar(b0 + j) + 2.75, 0.65)

    # --- the acid line: 16ths from bar 2, its cutoff opening through A, widest in B, closing in C
    steps = []
    for b in range(2, BARS):
        cA, cB = CH[PLAN[b]][2]
        tones = [42, 54, 49, cA, cB]
        for st, ti, acc, sl in RIFF:
            if st // 16 == b % 2:
                steps.append((bar(b) + (st % 16) / 4.0, 0.25, tones[ti], acc * (0.6 if b < 4 else 1.0), sl))
    base = s.auto([(0, 170), (bar(4), 260), (bar(8), 330), (bar(12), 420), (bar(16), 480), (bar(20), 330), (bar(24), 250)], 2.0)
    base = base * 2.0 ** (0.6 * S.lfo(s.L, 0.05, -1.5))
    q = s.auto([(0, 5.0), (bar(12), 8.0), (bar(20), 6.0)], 3.0)
    s.part("acid").buf += V2.acid(s.L, s.spb, steps, base, q, 2.8, 0.19, 0.5, "saw", 0.55, 60.0, 2.4)[None, :] * 0.5

    # --- glassy plucks: a dotted-eighth figure on the chord tones, from bar 4
    for b in range(4, BARS):
        if sec_of(b) == "C" and b >= 26:
            continue
        tones = CH[PLAN[b]][3]
        for j, st in enumerate((0, 3, 6, 9, 12)):
            n = GLASS[b % 2][j]
            s.put("glass", V2.glass(tones[n], 2.4), bar(b) + st / 4.0, s.v(0.55 if j else 0.7, 0.15), pan=(-0.45, 0.45)[j % 2], ms=3)

    # --- the beacon on glass (and a sine an octave down)
    for b0, lvl in ((1, 0.8), (12, 1.0), (20, 0.9)):
        for bt, m, d in BEACON:
            s.put("beacon", V2.glass(m, 4.0, 2.0, 1.2, 1.4, 0.1), bar(b0) + bt, lvl, pan=0.2)
            s.put("beacon", V.sine_ping(m - 12, 3.0, 1.0), bar(b0) + bt, 0.5 * lvl, pan=-0.2)

    # --- sparse crisp ticks (both versions): a rim on beat 3, a closed hat on the last 16th of each beat
    for b in range(4, BARS):
        s.put("tick", V.rim(b % 3), bar(b) + 2, s.v(0.5, 0.1), pan=0.25, ms=2)
        for j in range(4):
            s.put("tick", V.hat(j % 3, False, 8000), bar(b) + j + 0.75, s.v(0.28, 0.2), pan=-0.3, ms=2)

    # ===== BATTLE layers =====
    for b in range(BARS):
        light = b < 2
        for st in range(16):
            k = st + 16 * (b % 2)
            beat = bar(b) + st / 4.0
            if k in KICK and not (light and st):
                s.hit("kick", V.kick(st % 3, 135.0, 46.0, 0.03, 0.24, 0.22), beat, KICK[k] * s.v(1, 0.04), ms=2)
            if b >= 2 and k in SNARE:
                s.put("snare", V.snare(b % 3, 195.0, 0.12, 1500, 0.35, 0.65), beat, s.v(1.0, 0.04), pan=0.04, ms=2)
            if b >= 4 and k in GHOST:
                s.put("snare", V.snare(3 + st % 3, 215.0, 0.05, 2600, 0.15, 0.3), beat, GHOST[k] * s.v(1, 0.15), pan=0.1, ms=4)
            swing = 0.035 if st % 2 else 0.0
            v = 0.55 if st % 4 == 2 else 0.4 if st % 2 == 0 else 0.26
            s.put("hat", V.hat(st % 3, False, 7500), beat + swing, v * s.v(1, 0.2) * (0.6 if light else 1.0), pan=0.35, ms=2)
        if b % 2 == 1 and b >= 2:
            s.put("hat", V.hat(1, True, 6500), bar(b) + 3.5, 0.4, pan=0.3, ms=2)
    # distorted mid bass: syncopated roots and octaves from bar 4
    dsteps = []
    for b in range(4, BARS):
        r = CH[PLAN[b]][1]
        for st, o, acc in ((0, 0, 1), (3, 0, 0), (6, 12, 0), (8, 0, 1), (10, 0, 0), (11, 12, 0), (14, 0, 0)):
            dsteps.append((bar(b) + st / 4.0, 0.25, r + o, acc, 0))
    dfc = s.auto([(0, 260), (bar(12), 380), (bar(20), 300)], 2.0) * 2.0 ** (0.4 * S.lfo(s.L, 0.05, -1.5))
    s.part("dbass").buf += V2.acid(s.L, s.spb, dsteps, dfc, 2.2, 2.0, 0.09, 0.6, "saw", 0.8, 40.0, 4.5)[None, :] * 0.5
    # gated stabs: the chord an octave up, held, cut by a 16th gate
    for k, (b0, nb, c) in enumerate(spans):
        if b0 < 4:
            continue
        for m in CH[c][0]:
            s.put("stab", V.pad(m + 12, s.sec(bar(nb)) - 0.02, 0.005, 0.15, 11.0, 0.0, seed=7), bar(b0), 0.8)
    stab_gate = S2.gate_curve(s.L, s.spb, STAB_GATE, 0, bar(BARS), 0.25, 0.55)
    # reversed cymbals into A, B and C
    rev = V.crash(2, 2.0)[::-1].copy()
    for b in (4, 12, 20):
        s.put("rev", rev, bar(b) - 2.0 / s.sec(1), 0.8, pan=-0.1)

    def glitch(x):
        for b in (3, 7, 15, 23):   # 4-bar ends: the last eighth stutters in 32nds
            x = S2.stutter(x, s.at(bar(b) + 3.5), s.spb / 8, s.spb / 2)
        for b in (11, 19):   # 8-bar ends: beat 4 rolls, 16th to 64th, under a crush sweep
            x = S2.crush_sweep(x, s.at(bar(b) + 2), 2 * s.spb, (10, 4), (1, 10))
            x = S2.stutter(x, s.at(bar(b) + 3), s.spb / 4, s.spb, shrink=0.72, min_len=s.spb / 16)
        return S2.tape_stop(x, s.at(bar(27) + 3), s.spb, 1.4)

    # --- mixes
    cut = s.auto([(0, 900), (bar(4), 1200), (bar(12), 1700), (bar(20), 1300), (bar(26), 1000)], 3.0)
    pad_fc = cut * (1 + 0.3 * S.lfo(s.L, 0.05))
    pad_fx = once(lambda x: (lambda y: y * 0.55 + 0.45 * S.chorus(y, 0.21, 21, 3.5, mix=1.0))(S.lp_sweep(x, pad_fc, 400, 3200)))
    dot = 0.75 * s.spb
    acid_fx = once(lambda x: x + 0.35 * S.pingpong(x, dot, 0.45, 7, 2800, 300))
    glass_fx = once(lambda x: x + 0.55 * S.pingpong(x, dot, 0.55, 9, 5000, 400))
    beacon_fx = once(lambda x: x + 0.6 * S.pingpong(x, 1.5 * s.spb, 0.6, 9, 4500, 300))
    stab_fx = lambda x: x * stab_gate[None, :]
    common = dict(
        pad=dict(g=-4, hp=130, send=0.55, fx=pad_fx),
        sub=dict(g=-11, hp=22, lp=160, send=0.0),
        acid=dict(g=-5, hp=105, lp=7000, send=0.15, fx=acid_fx),
        glass=dict(g=-5, hp=450, lp=11000, send=0.6, fx=glass_fx),
        beacon=dict(g=-6, hp=250, send=0.9, fx=beacon_fx),
        tick=dict(g=4, hp=600, send=0.3),
    )
    spec_x = dict(common)
    spec_b = dict(common, pad=dict(common["pad"], g=-7), sub=dict(common["sub"], g=-15), acid=dict(common["acid"], g=-6), glass=dict(common["glass"], g=-8),
                  beacon=dict(common["beacon"], g=-6), tick=dict(common["tick"], g=0),
                  kick=dict(g=-9, hp=28, lp=4000, send=0.03, bus=True),
                  snare=dict(g=0, hp=140, send=0.3, bus=True),
                  hat=dict(g=-1, hp=6000, send=0.1, bus=True),
                  dbass=dict(g=-12, hp=38, lp=2400, send=0.05, bus=True),
                  stab=dict(g=-10, hp=250, lp=5000, send=0.35, fx=stab_fx, bus=True),
                  rev=dict(g=-14, hp=600, send=0.4))
    ir = S.make_ir(5.0, 30, 1.0, 31)
    env = s.auto([(0, 0.85), (bar(4), 1.0)], 2.0)
    x = s.master(s.mix(spec_x, ir, -2, 4.0, env), RMS["explore"])
    y = s.master(s.mix(spec_b, ir, -3, 4.0, env, glitch), RMS["battle"])
    t, at = s.transition(x, y)
    render.bpm, render.song = s.bpm, s
    return {"explore": x, "battle": y, "transition": t, "xfade_s": at,
            "sections": {"intro": 0, "A": round(s.sec(bar(4)), 2), "B": round(s.sec(bar(12)), 2), "C": round(s.sec(bar(20)), 2)}}
