"""Demo 4, "Ma's Ledger II": the round-1 menu theme re-orchestrated for space. D dorian (the menu's key), 96 BPM,
28 bars (70 s), EXPLORE and BATTLE. The menu's harmony, two bars a chord: Dm9 - G6/9 - Bbmaj7 - Am7 (intro: Dm9 held).
  intro (0-3) | A (4-11) the theme on the soft lead | B (12-19) an octave up with a harmony a third below and a glass
  double | C (20-27) the first half on music box and glass, the second half on the lead up an octave.
EXPLORE: big shimmer pads (the chords plus an octave-and-fifth halo that lives in a 6 s reverb), a slow 12.5% chip
arp (quarters, eighths from B) with a dotted echo, a round bass, bells on the chord changes. No static.
BATTLE: an FTL-style driving layer on the same harmony: kick and backbeat snare with 16th hats, tom fills, a 16th
pulsing bass, short brassy stabs on the off-beats and a 25% pulse doubling the theme."""
import numpy as np
import synth as S
import voices as V
import voices2 as V2
import theme as T
from demo import Demo, once

TITLE = "Ma's Ledger II"
RMS = {"explore": -18.0, "battle": -15.0}
BARS = 28
CHORDS = [  # (pad voicing, bass root, arp tones) as in t_menu.py
    ([50, 57, 60, 64, 65], 38, [57, 62, 65, 69, 72, 76]),     # Dm9
    ([55, 59, 62, 64, 69], 43, [55, 62, 67, 71, 74, 76]),     # G6/9
    ([58, 62, 65, 69, 72], 34, [58, 62, 65, 69, 72, 74]),     # Bb maj7
    ([57, 60, 64, 67, 71], 33, [57, 60, 64, 67, 69, 72]),     # Am7
]
ARP_Q = [0, 2, 3, 5, 4, 3, 2, 1]
ARP_E = [0, 2, 4, 5, 4, 3, 2, 3, 1, 2, 4, 5, 3, 2, 4, 2]


def render():
    s = Demo(96, BARS, seed=613)
    bar = lambda b: b * 4.0
    sec_of = lambda b: "intro" if b < 4 else "A" if b < 12 else "B" if b < 20 else "C"
    ci_of = lambda b: 0 if b < 4 else ((b - 4) // 2) % 4

    # --- pads and the shimmer halo, bass
    plan = [(0, 4, 0)] + [(4 + 2 * k, 2, k % 4) for k in range(12)]
    for k, (b0, nb, ci) in enumerate(plan):
        voicing, root, _ = CHORDS[ci]
        g = {"intro": 0.6, "A": 0.75, "B": 0.9, "C": 0.85}[sec_of(b0)]
        for m in voicing:
            s.put("pad", V.pad(m, s.sec(bar(nb)) - 0.1, 2.0, 3.0, 8.0, 4.0, seed=k % 4), bar(b0), g * s.v(1.0, 0.04), ms=6)
        for m in (voicing[1] + 12, voicing[2] + 19, voicing[3] + 12):
            s.put("shim", V.pad(m, s.sec(bar(nb)) - 0.1, 3.0, 4.0, 5.0, 6.0, seed=k % 3 + 5), bar(b0), g * 0.5, ms=0)
        if b0 >= 2:
            s.put("bass", V.bass(root, s.sec(bar(nb)) - 0.2, 330.0, 1.2, 1.0, 0.18, 0.15, 0.05, 0.5), bar(b0), 0.8 if b0 >= 4 else 0.5)

    # --- the slow chip arp (quarters in A, eighths in B and C), waking in the intro's last bar
    for b in range(3, BARS):
        tones = CHORDS[ci_of(b)][2]
        if sec_of(b) in ("intro", "A"):
            for j in range(4):
                if b == 3 and j == 0:
                    continue
                n = ARP_Q[((b - 4) * 4 + j) % 8]
                s.put("arp", V2.chip(tones[n] + 12, s.sec(0.9), 0.125, 0.006, 0.35, 0.2, 0.2, 6.0, 5.0, 0.15, bits=8), bar(b) + j,
                      s.v(0.6, 0.12), pan=(-0.45, 0.45)[j % 2], ms=4)
        else:
            for j in range(8):
                n = ARP_E[((b - 4) * 8 + j) % 16]
                s.put("arp", V2.chip(tones[n] + 12, s.sec(0.45), 0.125, 0.004, 0.25, 0.15, 0.15, bits=8), bar(b) + j / 2,
                      s.v(0.55 if j % 2 == 0 else 0.42, 0.12), pan=(-0.55, 0.55)[j % 2], ms=4)

    # --- the theme
    def lead(start_bar, shift=0, steps=0, part="lead", gain=1.0, pan=0.0, bars=8, skip=0):
        for bt, m, d in T.notes(62, "dorian", start=bar(start_bar), steps=steps, shift=shift, bars=bars, skip_bars=skip):
            s.put(part, V.lead(m, s.sec(d) * 0.96, 12.0, 5.0, 0.3, 0.04, 0.5, 0.2), bt, gain * s.v(1, 0.05), pan=pan, ms=5)
    lead(4)
    lead(12, 12, 0, gain=0.85, pan=0.1)
    lead(12, 12, -2, "lead2", 0.55, -0.3)
    for bt, m, d in T.notes(62, "dorian", start=bar(12), shift=12):
        s.put("glass", V2.glass(m, 2.2), bt, s.v(0.35, 0.1), pan=0.35, ms=4)
    for bt, m, d in T.notes(62, "dorian", start=bar(20), shift=12, bars=4):
        s.put("box", V.musicbox(m, 3.2, 0.0, 0.0, 1.5), bt, s.v(0.55, 0.1), pan=0.15, ms=5)
        s.put("glass", V2.glass(m, 2.6), bt, s.v(0.3, 0.1), pan=-0.35, ms=5)
    lead(24, 12, 0, gain=0.8, bars=4, skip=4)
    lead(24, 12, -2, "lead2", 0.5, -0.3, bars=4, skip=4)
    # bells on the chord changes
    for k, (b0, nb, ci) in enumerate(plan):
        if b0 >= 4:
            tones = CHORDS[ci][2]
            s.put("bell", V.bell(tones[(k * 3) % 6] + 12, 3.4, 3.5, 1.6, 1.4), bar(b0) + 0.5, 0.4, pan=(-0.5, 0.5)[k % 2], ms=4)
    for beat, m in ((2.0, 76), (6.0, 72), (9.5, 69)):
        s.put("bell", V.bell(m, 3.5, 3.5, 1.6, 1.3), beat, 0.3, pan=0.35, ms=3)

    # ===== BATTLE layers =====
    for b in range(BARS):
        voicing, root, tones = CHORDS[ci_of(b)]
        r = root if root < 40 else root - 12
        light = b < 2
        for st in range(16):   # 16th pulsing bass, octave on the off-beat 16ths
            if light and st % 4:
                continue
            s.put("obass", V.bass(r + (12 if st % 4 == 2 else 0), s.sec(0.22), 850.0, 1.8, 0.85, 0.55, 0.03, 0.003, 1.5), bar(b) + st / 4,
                  (1.0 if st % 4 == 0 else 0.7) * s.v(1, 0.05), ms=2)
        fill = b in (3, 11, 19, 27)
        kicks = [(0, 1.0), (2, 0.9), (2.75, 0.6)] if b % 2 == 0 else [(0, 1.0), (1.5, 0.65), (2, 0.9)]
        for p, v in kicks:
            if not (fill and p > 2):
                s.put("kick", V.kick(int(p * 4) % 3, 150.0, 48.0, 0.03, 0.22, 0.3), bar(b) + p, v * s.v(1, 0.04), ms=2)
        if b >= 2:
            for p in (1, 3):
                if not (fill and p == 3):
                    s.put("snare", V.snare(p % 3, 185.0, 0.12, 1700, 0.32, 0.65), bar(b) + p, s.v(1.0, 0.04), pan=0.04, ms=2)
                    s.put("snare", V.rim(p % 3), bar(b) + p, 0.35, pan=-0.1, ms=2)
        for st in range(16):
            if fill and st >= 8:
                continue
            v = 0.45 if st % 4 == 2 else 0.32 if st % 2 == 0 else 0.2
            s.put("hat", V.hat(st % 3, False), bar(b) + st / 4, v * s.v(1, 0.15) * (0.6 if light else 1), pan=0.3, ms=2)
        if fill:   # 16th toms over beats 3-4
            for k, f0 in enumerate((220, 220, 185, 185, 147, 147, 123, 110)):
                s.put("tom", V2.tom(f0, 0.24, k % 3), bar(b) + 2 + k / 4, (0.65 + 0.05 * k) * s.v(1, 0.05), pan=0.45 - 0.13 * k, ms=2)
        if b in (4, 12, 20):
            s.put("crash", V.crash(b % 3, 2.0), bar(b), 0.75, pan=0.12)
        if b >= 4:
            for p in (1.5, 3.5) if b % 2 == 0 else (1.5, 2.75, 3.5):   # brassy off-beat stabs
                for m in voicing[1:]:
                    s.put("stab", V.pad(m, s.sec(0.3), 0.004, 0.14, 12.0, 0.0, seed=2), bar(b) + p, 0.8 * s.v(1, 0.06), ms=2)
    # the theme doubled on a 25% pulse (an octave down where the lead is high)
    for start, sh in ((4, 0), (12, 0), (20, 0)):
        for bt, m, d in T.notes(62, "dorian", start=bar(start), shift=sh):
            s.put("dbl", V2.chip(m, s.sec(d) * 0.94, 0.25, 0.006, 0.4, 0.7, 0.12, 14.0, 5.6, 0.2, 0.03, 8), bt, s.v(0.8, 0.05), ms=3)

    # --- mixes
    cut = s.auto([(0, 1000), (bar(4), 1300), (bar(12), 1800), (bar(20), 1500)], 3.0)
    pad_fc = cut * (1 + 0.25 * S.lfo(s.L, 0.05))
    pad_fx = once(lambda x: (lambda y: y * 0.55 + 0.45 * S.chorus(y, 0.2, 22, 4.0, mix=1.0))(S.lp_sweep(x, pad_fc, 450, 3500)))
    trem = (0.75 + 0.25 * S.lfo(s.L, 0.25)).astype(np.float32)
    shim_fx = once(lambda x: S.chorus(x, 0.13, 25, 6.0, 1.2, 1.0) * trem[None, :])
    echo = once(lambda x: x + 0.55 * S.pingpong(x, 0.75 * s.spb, 0.55, 9, 5000, 400))
    lead_fx = once(lambda x: x + 0.35 * S.pingpong(x, 1.5 * s.spb, 0.4, 5, 4000, 300))
    common = dict(
        pad=dict(g=-4, hp=140, send=0.6, fx=pad_fx),
        shim=dict(g=-14, hp=900, lp=9000, send=6.0, fx=shim_fx),
        bass=dict(g=-12, hp=30, lp=600, send=0.05),
        arp=dict(g=-3, hp=400, lp=9000, send=0.4, fx=echo),
        lead=dict(g=-3, hp=250, send=0.6, fx=lead_fx),
        lead2=dict(g=-7, hp=250, send=0.6, fx=lead_fx),
        glass=dict(g=-6, hp=500, send=0.7, fx=echo),
        box=dict(g=-1, hp=350, send=0.7),
        bell=dict(g=-4, hp=350, send=0.8),
    )
    spec_x = dict(common)
    spec_b = dict(common, pad=dict(common["pad"], g=-8), shim=dict(common["shim"], g=-19), bass=dict(common["bass"], g=-20),
                  arp=dict(common["arp"], g=-6), lead=dict(common["lead"], g=-3, send=0.4), bell=dict(common["bell"], g=-8),
                  obass=dict(g=-16, hp=35, lp=2000, send=0.03),
                  kick=dict(g=-9, hp=30, lp=4000, send=0.03),
                  snare=dict(g=0, hp=150, send=0.3),
                  hat=dict(g=1, hp=6000, send=0.1),
                  tom=dict(g=-8, hp=60, send=0.3),
                  crash=dict(g=-12, hp=500, send=0.3),
                  stab=dict(g=-12, hp=250, lp=6000, send=0.3),
                  dbl=dict(g=-9, hp=200, lp=6000, send=0.25))
    ir = S.make_ir(6.0, 40, 0.9, 61)
    env = s.auto([(0, 0.85), (bar(4), 1.0)], 2.0)
    x = s.master(s.mix(spec_x, ir, -3, 4.5, env), RMS["explore"])
    y = s.master(s.mix(spec_b, ir, -5, 4.0, env), RMS["battle"])
    t, at = s.transition(x, y)
    render.bpm, render.song = s.bpm, s
    return {"explore": x, "battle": y, "transition": t, "xfade_s": at,
            "sections": {k: round(s.sec(bar(v)), 2) for k, v in (("intro", 0), ("A", 4), ("B", 12), ("C", 20))}}
