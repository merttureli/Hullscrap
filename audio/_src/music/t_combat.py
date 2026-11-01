"""combat.ogg  "Broadside"  C minor, 126 BPM, 64 bars (2:02).
One chord a bar. A: Cm - Ab - Eb - Bb. B: Fm - Ab - Gsus4 - G. Each 8-bar unit is A then B; the theme, mapped into C minor,
fits one unit exactly (one theme bar per chord) and is the lead in units 2, 5 (octave up, right after the breakdown) and 7 (doubled).
Intro 4 bars; units 1-3; a 4-bar breakdown; units 4-7. Eighth-note bass, full drums with scrap-metal accents,
a 16th arp and stabs; a snare roll and riser into every B and into the loop."""
import numpy as np
import synth as S
import voices as V
import theme as T
from common import Song

TITLE = "Broadside"
RMS = -15.0
BARS = 64
# chord data: stab voicing, bass root, arp tones
A_CH = [([60, 63, 67, 72], 36, [60, 63, 67, 72, 75, 79]), ([60, 63, 68, 72], 32, [56, 60, 63, 68, 72, 75]),
        ([58, 63, 67, 70], 39, [63, 67, 70, 75, 79, 82]), ([58, 62, 65, 70], 34, [58, 62, 65, 70, 74, 77])]
B_CH = [([60, 65, 68, 72], 41, [53, 56, 60, 65, 68, 72]), ([60, 63, 68, 72], 32, [56, 60, 63, 68, 72, 75]),
        ([60, 62, 67, 72], 43, [55, 60, 62, 67, 72, 74]), ([59, 62, 67, 71], 43, [55, 59, 62, 67, 71, 74])]
ARP = [0, 2, 3, 2, 4, 3, 2, 1, 0, 2, 3, 5, 4, 3, 2, 3]


def render():
    s = Song(126, BARS, seed=404)
    bar = lambda b: b * 4.0
    def chord(b):
        i = b % 8 if b < 4 else (b - 4) % 8 if b < 28 else (b - 32) % 8 if b >= 32 else (b - 28) % 4
        return (A_CH + B_CH)[i] if b >= 4 else A_CH[b % 4]
    brk = lambda b: 28 <= b < 32
    u_of = lambda b: -1 if b < 4 else (b - 4) // 8 if b < 28 else 3 if b < 32 else 4 + (b - 32) // 8   # unit index
    is_b = lambda b: b >= 4 and not brk(b) and ((b - 4) % 8 >= 4 if b < 28 else (b - 32) % 8 >= 4)

    # --- pad, bass, stabs
    for b in range(BARS):
        stab, root, tones = chord(b)
        u = u_of(b)
        for m in stab:
            s.put("pad", V.pad(m - 12, s.sec(4) - 0.05, 0.25, 0.6, seed=b % 8), bar(b), (1.3 if brk(b) else 0.8) * s.v(1.0, 0.05), ms=5)
        if brk(b):
            s.put("bass", V.bass(root, s.sec(3.9), 300.0, 1.3, 1.0, 0.25, 0.1, 0.02, 0.5), bar(b), 0.8)
            continue
        if True:
            for j in range(8):
                o = 12 if j in (2, 6) and u >= 1 else 0
                accent = 1.0 if j in (0, 5) else 0.72
                s.put("bass", V.bass(root + o, s.sec(0.46), 700.0, 1.8, 0.9, 0.5, 0.04, 0.004, 1.2), bar(b) + j / 2, accent * s.v(1.0, 0.06), ms=3)
        if b >= 4 and u in (1, 2, 5, 6, 4, 7):   # stabs: one on the and-of-2, two in the heavy units
            pos = (1.5, 2.75) if u in (2, 5, 7) else (1.5,)
            for p in pos:
                for m in stab:
                    s.put("stab", V.pad(m, s.sec(0.28), 0.004, 0.14, 9.0, 0.0, seed=1), bar(b) + p, 0.9 * s.v(1.0, 0.08), pan=0.05, ms=3)

    # --- arp: 16ths, from the second half of unit 1, not in the break; thinner in unit 7's end
    for b in range(8, BARS):
        if brk(b) or (b >= 60 and b % 2):
            continue
        tones = chord(b)[2]
        for st in range(16):
            n = ARP[st]
            s.put("arp", V.pluck(tones[n], 0.6, "saw", 1.2, 0.3), bar(b) + st / 4.0, (1.0 if st % 4 == 0 else 0.62 if st % 2 == 0 else 0.45) * s.v(1.0, 0.1),
                  pan=(-0.6, 0.6)[(st // 2) % 2], ms=2)

    # --- the theme as lead (C minor, one theme bar per chord, unit starts at bars 12, 36 and 52)
    for start, shifts in ((12, (0,)), (32, (12,)), (48, (0, 12))):
        for sh in shifts:
            for b, m, d in T.notes(60, "minor", start=bar(start), shift=sh):
                s.put("lead", V.lead(m, s.sec(d) * 0.97, 14.0, 5.5, 0.25, 0.015, 0.2, 0.15, 0.5), b, (0.95 if sh == 0 else 0.7) * s.v(1.0, 0.04), pan=0.0, ms=3)

    # --- drums
    def roll(b, beat0, n, v0, v1):
        for i in range(n):
            s.put("snare", V.snare(i % 3, 190.0, 0.07, 2200, 0.2, 0.4), bar(b) + beat0 + i * (4 - beat0) / n, (v0 + (v1 - v0) * i / n) * s.v(1, 0.05), ms=2)
    for b in range(BARS):
        u = u_of(b)
        bb = is_b(b)
        if brk(b):
            if b == 31:
                roll(b, 0.0, 16, 0.25, 0.95)
                s.put("riser", V.riser(int(s.sec(4) * S.SR), 21, 300.0, 11000.0), bar(b), 0.9)
            else:
                s.put("clank", V.clank(b % 6, 330.0 + 90 * (b % 3), 0.9, 1.4), bar(b) + 0.0, 0.6, pan=-0.4)
                s.put("clank", V.clank((b + 2) % 6, 620.0, 0.5, 1.4), bar(b) + 2.5, 0.45, pan=0.5)
            continue
        light = b < 4
        # kick
        ks = [(0, 1.0), (1.5, 0.7), (2, 0.95)] + ([(3.5, 0.6)] if b % 2 else [])
        for p, v in ks:
            s.put("kick", V.kick(int(p * 2) % 3, 160.0, 48.0, 0.03, 0.2, 0.3), bar(b) + p, v * s.v(1, 0.05), ms=2)
        if True:
            for j in (1, 3):
                s.put("snare", V.snare(j % 3), bar(b) + j, 1.0 * s.v(1, 0.05), pan=0.05, ms=2)
            s.put("snare", V.snare(2, 190.0, 0.05, 2500, 0.15, 0.3), bar(b) + 3.75, 0.3 * s.v(1, 0.2), ms=2)
        # hats: 8ths, 16ths in B sections
        step = 0.25 if bb else 0.5
        for i in range(int(4 / step)):
            v = (0.5 if (i * step) % 1 == 0.5 else 0.3 if (i * step) % 1 == 0 else 0.22)
            s.put("hat", V.hat(i % 3, False), bar(b) + i * step, v * s.v(1, 0.15), pan=0.35, ms=2)
        if b % 2 == 1:
            s.put("hat", V.hat(1, True), bar(b) + 3.5, 0.45, pan=0.3, ms=2)
        # scrap-metal percussion
        if b >= 4:
            s.put("clank", V.clank(b % 3, 880.0 if bb else 760.0, 0.22, 0.7), bar(b) + 2.5, 0.45 * s.v(1, 0.15), pan=-0.35, ms=2)
            if bb:
                s.put("clank", V.clank(3 + b % 3, 1180.0, 0.18, 0.7), bar(b) + 3.75, 0.35 * s.v(1, 0.15), pan=0.4, ms=2)
        # fills and impacts: a roll and riser into each B (last A bar) and into the loop (last bar)
        if b >= 4 and ((b - 4) % 8 == 3 and b < 28 or (b - 32) % 8 == 3 and b >= 32 or b == 63):
            roll(b, 3.0, 8, 0.35, 0.95)
            s.put("riser", V.riser(int(s.sec(4) * S.SR), 11 + b), bar(b), 0.8)
        if (b >= 4 and ((b - 4) % 8 in (0, 4) and b < 28 or (b - 32) % 8 in (0, 4) and b >= 32 or b == 32)) or b == 0:
            s.put("crash", V.crash(b % 4, 2.0), bar(b), 0.7 if (b - 4) % 8 == 4 else 0.55, pan=0.1)

    # --- mix
    cut = s.auto([(0, 700), (bar(4), 1200), (bar(12), 1800), (bar(28), 2800), (bar(32), 1500), (bar(56), 2000)], 1.0)
    pad_fc = cut * (1 + 0.25 * S.lfo(s.L, 0.12))

    def pad_fx(x):
        y = S.lp_sweep(x, pad_fc, 400, 3500)
        return y * 0.7 + 0.3 * S.chorus(y, 0.3, 18, 3.0, mix=1.0)

    echo = lambda x: x + 0.45 * S.pingpong(x, 0.75 * s.spb, 0.45)
    spec = {
        "pad": dict(g=-6, hp=140, send=0.3, fx=pad_fx),
        "bass": dict(g=-11, hp=30, lp=1500, send=0.03),
        "stab": dict(g=-3, hp=200, lp=6500, send=0.35),
        "arp": dict(g=-4, hp=260, lp=8500, send=0.3, fx=echo),
        "lead": dict(g=-1, hp=250, lp=9000, send=0.35),
        "kick": dict(g=-9, hp=30, lp=3000, send=0.03),
        "snare": dict(g=-4, hp=150, send=0.25),
        "hat": dict(g=-3, hp=5000, send=0.1),
        "clank": dict(g=-4, hp=300, send=0.4),
        "crash": dict(g=-10, hp=500, send=0.4),
        "riser": dict(g=-10, hp=300, send=0.25),
    }
    env = s.auto([(0, 0.92), (bar(4), 1.0), (bar(28), 0.9), (bar(32), 1.0)], 1.5)
    mix = s.mix(spec, S.make_ir(2.4, 14, 1.0, 17), -4, 4.0, env)
    render.levels = s.levels(spec)
    render.bpm = s.bpm
    return S.master(mix, RMS)
