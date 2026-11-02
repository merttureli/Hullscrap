"""Demo 2, "Long Haul": warm adaptive chip-synth in D aeolian, 104 BPM, 32 bars (about 74 s), EXPLORE and BATTLE.
The Hullscrap theme (theme.py) mapped into D aeolian is the melody. One chord a bar, voice-led rootless voicings:
  intro (0-3)  Dm7 - Bbmaj9 - C6/9 - A7sus4
  A (4-11)     the theme on a 25% pulse lead: Dm7 - Fadd9 - C9 - Gm7 - Bbmaj9 - C6/9 - Dm9 - A7sus4 (the bVI-bVII-i lift)
  B (12-19)    a bridge on the theme's opening shape, climbing: Gm9 - Bbmaj7 - Fadd9 - C - Gm9 - Bbmaj7 - C - C
  A' (20-27)   the theme an octave up with a 50% pulse a third below: the lift into the second half
  outro (28-31) Bbmaj9 - C6/9 - Dm9 - A7sus4, the lead settles on A and the loop turns back to Dm7.
EXPLORE: an analog saw pad, a 12.5% chip arp in eighths with a dotted echo, a round bass, the chip lead with vibrato.
BATTLE: the same plus a driving kit (kick, backbeat snare, eighth hats, tom fills, crashes), an octave bass in eighths,
a 16th square arp, off-beat pulse stabs and the lead doubled an octave down."""
import numpy as np
import synth as S
import voices as V
import voices2 as V2
import theme as T
from demo import Demo, once

TITLE = "Long Haul"
RMS = {"explore": -18.0, "battle": -15.0}
BARS = 32
CH = {  # pad voicing, bass root, arp tones
    "Dm7": ([57, 60, 62, 65], 38, [62, 65, 69, 72, 74, 77]),
    "Fadd9": ([57, 60, 65, 67], 41, [60, 65, 67, 69, 72, 77]),
    "C9": ([55, 58, 62, 64], 36, [60, 62, 64, 67, 70, 74]),
    "Gm7": ([55, 58, 62, 65], 31, [58, 62, 65, 67, 70, 74]),
    "Bbmaj9": ([57, 60, 62, 65], 34, [58, 62, 65, 69, 70, 72]),
    "C69": ([57, 60, 62, 64], 36, [60, 62, 64, 67, 69, 72]),
    "Dm9": ([53, 57, 60, 64], 38, [62, 64, 65, 69, 72, 76]),
    "A7sus4": ([55, 57, 62, 64], 33, [57, 62, 64, 67, 69, 74]),
    "Gm9": ([55, 58, 62, 65, 69], 31, [58, 62, 65, 69, 70, 74]),
    "Bbmaj7": ([58, 62, 65, 69], 34, [58, 62, 65, 69, 70, 74]),
    "C": ([55, 60, 64, 67], 36, [60, 64, 67, 72, 76, 79]),
}
A_CH = ["Dm7", "Fadd9", "C9", "Gm7", "Bbmaj9", "C69", "Dm9", "A7sus4"]
PLAN = ["Dm7", "Bbmaj9", "C69", "A7sus4"] + A_CH + ["Gm9", "Bbmaj7", "Fadd9", "C", "Gm9", "Bbmaj7", "C", "C"] + A_CH + ["Bbmaj9", "C69", "Dm9", "A7sus4"]
# the bridge: the theme's opening shape (long, leap up, step down, step down) sequenced over the new chords
BRIDGE = [(0, 74, 1.5), (1.5, 79, 0.5), (2, 77, 1), (3, 74, 1), (4, 72, 1.5), (5.5, 74, 0.5), (6, 69, 2),
          (8, 72, 1.5), (9.5, 77, 0.5), (10, 76, 1), (11, 72, 1), (12, 74, 1.5), (13.5, 72, 0.5), (14, 76, 2),
          (16, 77, 1.5), (17.5, 82, 0.5), (18, 81, 1), (19, 77, 1), (20, 74, 1.5), (21.5, 77, 0.5), (22, 81, 2),
          (24, 79, 1.5), (25.5, 76, 0.5), (26, 77, 1), (27, 76, 1), (28, 74, 1), (29, 76, 3)]
OUTRO = [(0, 77, 1.5), (1.5, 74, 0.5), (2, 72, 2), (4, 76, 1.5), (5.5, 74, 0.5), (6, 72, 1), (7, 69, 1), (8, 69, 5)]
ARP = [[0, 2, 4, 5, 3, 4, 2, 1], [0, 1, 3, 5, 4, 2, 3, 1]]
ARP16 = [0, 1, 2, 3, 2, 1, 2, 3, 4, 3, 2, 1, 2, 3, 2, 1]


def render():
    s = Demo(104, BARS, seed=307)
    bar = lambda b: b * 4.0
    sec_of = lambda b: "intro" if b < 4 else "A" if b < 12 else "B" if b < 20 else "A2" if b < 28 else "outro"

    # --- pad, bass, chip arp (shared)
    for b, c in enumerate(PLAN):
        voicing, root, tones = CH[c]
        sec = sec_of(b)
        g = {"intro": 0.7, "A": 0.8, "B": 0.9, "A2": 1.0, "outro": 0.85}[sec]
        for m in voicing:
            s.put("pad", V.pad(m, s.sec(4) - 0.06, 0.5, 1.4, 7.0, seed=b % 4), bar(b), g * s.v(1.0, 0.04), ms=5)
        for p, d, v in ((0, 1.4, 0.85), (1.5, 0.4, 0.55), (2, 1.9, 0.75)):
            s.put("bass", V.bass(root + 12 if root < 33 else root, s.sec(d), 420.0, 1.3, 1.0, 0.3, 0.08, 0.01, 0.8), bar(b) + p, v * s.v(1, 0.05), ms=3)
        for j in range(8):
            if b < 1 or (b < 2 and j < 4):
                continue
            n = ARP[b % 2][j]
            s.put("arp", V2.chip(tones[n] + 12, s.sec(0.4), 0.125, 0.002, 0.12, 0.25, 0.08, bits=7), bar(b) + j / 2,
                  s.v(0.75 if j % 2 == 0 else 0.55, 0.12), pan=(-0.4, 0.4)[j % 2], ms=3)

    # --- the chip lead: the theme in A, the bridge in B, the theme up an octave with a harmony in A', a coda
    def lead(notes, start, shift=0, part="lead", duty=0.25, gain=1.0, pan=0.0, vib=16.0):
        for bt, m, d in notes:
            s.put(part, V2.chip(m + shift, s.sec(d) * 0.94, duty, 0.008, 0.45, 0.7, 0.14, vib, 5.6, 0.18, 0.04, 8), start + bt, gain * s.v(1, 0.05), pan=pan, ms=4)
    lead(T.notes(62, "aeolian", start=0), bar(4))
    lead(BRIDGE, bar(12))
    lead(T.notes(62, "aeolian", start=0), bar(20), 12, gain=0.85)
    lead(T.notes(62, "aeolian", start=0, steps=-2), bar(20), 12, "lead2", 0.5, 0.6, -0.35, 11.0)
    lead(OUTRO, bar(28), 0, gain=0.9)

    # ===== BATTLE layers =====
    lead(T.notes(62, "aeolian", start=0), bar(4), -12, "dbl", 0.5, 0.7, 0.0, 10.0)
    lead(BRIDGE, bar(12), -12, "dbl", 0.5, 0.7, 0.0, 10.0)
    lead(T.notes(62, "aeolian", start=0), bar(20), 0, "dbl", 0.5, 0.7, 0.0, 10.0)
    lead(OUTRO, bar(28), -12, "dbl", 0.5, 0.6, 0.0, 10.0)
    for b, c in enumerate(PLAN):
        voicing, root, tones = CH[c]
        r = root if root >= 33 else root + 12
        for j in range(8):   # octave bass
            s.put("obass", V.bass(r + (12 if j % 2 else 0), s.sec(0.42), 900.0, 1.9, 0.8, 0.6, 0.04, 0.004, 1.4), bar(b) + j / 2,
                  (1.0 if j in (0, 3, 4) else 0.75) * s.v(1, 0.05), ms=2)
        if b >= 4:
            for p in (1.5, 3.5):   # off-beat pulse stabs
                for m in voicing:
                    s.put("stab", V2.chip(m, s.sec(0.22), 0.5, 0.002, 0.1, 0.2, 0.06, bits=8), bar(b) + p, 0.42 * s.v(1, 0.06), pan=0.08 * (m % 3 - 1), ms=2)
            for st in range(16):   # 16th square arp, an octave under the eighths
                s.put("arp16", V2.chip(tones[ARP16[st]] - 12, s.sec(0.2), 0.5, 0.002, 0.08, 0.15, 0.04, bits=6), bar(b) + st / 4,
                      (0.8 if st % 4 == 0 else 0.55) * s.v(1, 0.1), pan=(-0.55, 0.55)[(st // 4) % 2], ms=2)
    # the kit
    for b in range(BARS):
        sec = sec_of(b)
        fill = b in (3, 11, 19, 27, 31)
        kicks = [(0, 1.0), (2, 0.9), (2.5, 0.7)] if b % 2 == 0 else [(0, 1.0), (1.75, 0.6), (2, 0.9)]
        if b < 2:
            kicks = [(j, 0.85) for j in range(4)]
        for p, v in kicks:
            if not (fill and p >= 2):
                s.put("kick", V.kick(int(p * 4) % 3, 150.0, 50.0, 0.03, 0.2, 0.3), bar(b) + p, v * s.v(1, 0.04), ms=2)
        if b >= 2:
            for p in (1, 3):
                if not (fill and p == 3):
                    s.put("snare", V.snare(p % 3, 190.0, 0.11, 1800, 0.3, 0.6), bar(b) + p, s.v(1.0, 0.04), pan=0.04, ms=2)
        for j in range(8):
            if fill and j >= 4:
                continue
            s.put("hat", V.hat(j % 3, False), bar(b) + j / 2, (0.5 if j % 2 else 0.32) * s.v(1, 0.15), pan=0.3, ms=2)
        if b % 2 and not fill:
            s.put("hat", V.hat(1, True), bar(b) + 3.5, 0.4, pan=0.3, ms=2)
        if fill:   # tom fill over beats 3-4, high to low
            for k, f0 in enumerate((196, 196, 165, 165, 131, 131, 110, 98)):
                s.put("tom", V2.tom(f0, 0.25, k % 3), bar(b) + 2 + k / 4, (0.7 + 0.04 * k) * s.v(1, 0.05), pan=0.5 - 0.14 * k, ms=2)
        if b in (0, 4, 12, 20, 28):
            s.put("crash", V.crash(b % 3, 2.0), bar(b), 0.7, pan=0.15)

    # --- mixes
    cut = s.auto([(0, 1000), (bar(4), 1300), (bar(12), 1600), (bar(20), 2000), (bar(28), 1400)], 2.0)
    pad_fc = cut * (1 + 0.22 * S.lfo(s.L, 0.07))
    pad_fx = once(lambda x: (lambda y: y * 0.6 + 0.4 * S.chorus(y, 0.33, 18, 3.0, mix=1.0))(S.lp_sweep(x, pad_fc, 450, 3500)))
    arp_fx = once(lambda x: x + 0.45 * S.pingpong(x, 0.75 * s.spb, 0.45, 7, 4500, 300))
    lead_fx = once(lambda x: x + 0.22 * S.pingpong(x, 0.75 * s.spb, 0.35, 5, 4000, 400))
    common = dict(
        pad=dict(g=-6, hp=150, send=0.45, fx=pad_fx),
        bass=dict(g=-13, hp=32, lp=900, send=0.03),
        arp=dict(g=-4, hp=300, lp=9000, send=0.3, fx=arp_fx),
        lead=dict(g=-6, hp=250, lp=8000, send=0.3, fx=lead_fx),
        lead2=dict(g=-6, hp=250, lp=7000, send=0.35, fx=lead_fx),
    )
    spec_x = dict(common)
    spec_b = dict(common, pad=dict(common["pad"], g=-9), bass=dict(common["bass"], g=-22), arp=dict(common["arp"], g=-7),
                  lead=dict(common["lead"], g=-5),
                  dbl=dict(g=-10, hp=150, lp=5000, send=0.2),
                  obass=dict(g=-16, hp=32, lp=2200, send=0.03),
                  stab=dict(g=-6, hp=300, lp=6000, send=0.25),
                  arp16=dict(g=-14, hp=200, lp=6000, send=0.15),
                  kick=dict(g=-8, hp=30, lp=4000, send=0.03),
                  snare=dict(g=-2, hp=150, send=0.3),
                  hat=dict(g=-2, hp=6000, send=0.1),
                  tom=dict(g=-9, hp=60, send=0.3),
                  crash=dict(g=-12, hp=500, send=0.3))
    ir = S.make_ir(3.2, 22, 1.0, 41)
    env = s.auto([(0, 0.9), (bar(4), 1.0)], 2.0)
    x = s.master(s.mix(spec_x, ir, -3, 4.0, env), RMS["explore"])
    y = s.master(s.mix(spec_b, ir, -4, 4.0, env), RMS["battle"])
    t, at = s.transition(x, y)
    render.bpm, render.song = s.bpm, s
    return {"explore": x, "battle": y, "transition": t, "xfade_s": at,
            "sections": {"intro": 0, "A": round(s.sec(bar(4)), 2), "B": round(s.sec(bar(12)), 2), "A2": round(s.sec(bar(20)), 2),
                         "outro": round(s.sec(bar(28)), 2)}}
