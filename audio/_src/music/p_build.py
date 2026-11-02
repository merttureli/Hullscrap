"""build.ogg  "Ma's Ledger II (build)": the round-2 Ledger II EXPLORE version polished into the build-mode loop.
D dorian (the menu's key), 96 BPM, 42 bars (1:45), one version. The menu's harmony, two bars a chord:
Dm9 - G6/9 - Bbmaj7 - Am7. Calm enough to build a ship to for an hour:
  intro (0-1)  Dm9, bells, the chip arp waking
  A (2-9)      the theme on the soft lead, the slow chip arp in quarters
  B (10-17)    the theme an octave up with a harmony a third below and a glass double, arp in eighths
  C (18-25)    the first half on music box and glass, the second half on the lead up an octave
  D (26-33)    a rest for the ear: no lead, the arp, bells on the changes, the beacon far away on glass
  A2 (34-41)   the theme low and soft with bells doubling it, the arp back to quarters, into the loop.
Big shimmer pads (the chords plus an octave-and-fifth halo in a 6 s reverb), a round bass, no static."""
import numpy as np
import synth as S
import voices as V
import voices2 as V2
import theme as T
from demo import Demo, once

TITLE = "Ma's Ledger II (build)"
RMS = -18.0
BARS = 42
CHORDS = [  # (pad voicing, bass root, arp tones) as in t_menu.py
    ([50, 57, 60, 64, 65], 38, [57, 62, 65, 69, 72, 76]),     # Dm9
    ([55, 59, 62, 64, 69], 43, [55, 62, 67, 71, 74, 76]),     # G6/9
    ([58, 62, 65, 69, 72], 34, [58, 62, 65, 69, 72, 74]),     # Bb maj7
    ([57, 60, 64, 67, 71], 33, [57, 60, 64, 67, 69, 72]),     # Am7
]
ARP_Q = [0, 2, 3, 5, 4, 3, 2, 1]
ARP_E = [0, 2, 4, 5, 4, 3, 2, 3, 1, 2, 4, 5, 3, 2, 4, 2]
BEACON = [(0.0, 76, 0.9), (1.0, 71, 0.9), (2.0, 74, 0.9), (4.0, 69, 2.5)]


def render():
    s = Demo(96, BARS, seed=613)
    bar = lambda b: b * 4.0
    sec_of = lambda b: "intro" if b < 2 else "A" if b < 10 else "B" if b < 18 else "C" if b < 26 else "D" if b < 34 else "A2"
    ci_of = lambda b: 0 if b < 2 else ((b - 2) // 2) % 4

    # --- pads and the shimmer halo, bass: the intro holds Dm9 for two bars, then the 8-bar cycle five times
    plan = [(0, 2, 0)] + [(2 + 2 * k, 2, k % 4) for k in range(20)]
    for k, (b0, nb, ci) in enumerate(plan):
        voicing, root, _ = CHORDS[ci]
        g = {"intro": 0.6, "A": 0.75, "B": 0.9, "C": 0.85, "D": 0.8, "A2": 0.7}[sec_of(b0)]
        for m in voicing:
            s.put("pad", V.pad(m, s.sec(bar(nb)) - 0.1, 2.0, 3.0, 8.0, 4.0, seed=k % 4), bar(b0), g * s.v(1.0, 0.04), ms=6)
        for m in (voicing[1] + 12, voicing[2] + 19, voicing[3] + 12):
            s.put("shim", V.pad(m, s.sec(bar(nb)) - 0.1, 3.0, 4.0, 5.0, 6.0, seed=k % 3 + 5), bar(b0), g * 0.5, ms=0)
        if b0 >= 2:
            s.put("bass", V.bass(root, s.sec(bar(nb)) - 0.2, 330.0, 1.2, 1.0, 0.18, 0.15, 0.05, 0.5), bar(b0), 0.75 if sec_of(b0) != "D" else 0.6)

    # --- the slow chip arp: quarters in A and A2, eighths in B, C and D; it wakes in the intro's second bar
    for b in range(1, BARS):
        tones = CHORDS[ci_of(b)][2]
        if sec_of(b) in ("intro", "A", "A2"):
            for j in range(4):
                if b == 1 and j < 2:
                    continue
                n = ARP_Q[((b - 2) * 4 + j) % 8]
                s.put("arp", V2.chip(tones[n] + 12, s.sec(0.9), 0.125, 0.006, 0.35, 0.2, 0.2, 6.0, 5.0, 0.15, bits=8), bar(b) + j,
                      s.v(0.6, 0.12), pan=(-0.45, 0.45)[j % 2], ms=4)
        else:
            for j in range(8):
                n = ARP_E[((b - 2) * 8 + j) % 16]
                s.put("arp", V2.chip(tones[n] + 12, s.sec(0.45), 0.125, 0.004, 0.25, 0.15, 0.15, bits=8), bar(b) + j / 2,
                      s.v(0.55 if j % 2 == 0 else 0.42, 0.12), pan=(-0.55, 0.55)[j % 2], ms=4)

    # --- the theme
    def lead(start_bar, shift=0, steps=0, part="lead", gain=1.0, pan=0.0, bars=8, skip=0):
        for bt, m, d in T.notes(62, "dorian", start=bar(start_bar), steps=steps, shift=shift, bars=bars, skip_bars=skip):
            s.put(part, V.lead(m, s.sec(d) * 0.96, 12.0, 5.0, 0.3, 0.04, 0.5, 0.2), bt, gain * s.v(1, 0.05), pan=pan, ms=5)
    lead(2)
    lead(10, 12, 0, gain=0.85, pan=0.1)
    lead(10, 12, -2, "lead2", 0.55, -0.3)
    for bt, m, d in T.notes(62, "dorian", start=bar(10), shift=12):
        s.put("glass", V2.glass(m, 2.2), bt, s.v(0.35, 0.1), pan=0.35, ms=4)
    for bt, m, d in T.notes(62, "dorian", start=bar(18), shift=12, bars=4):
        s.put("box", V.musicbox(m, 3.2, 0.0, 0.0, 1.5), bt, s.v(0.55, 0.1), pan=0.15, ms=5)
        s.put("glass", V2.glass(m, 2.6), bt, s.v(0.3, 0.1), pan=-0.35, ms=5)
    lead(22, 12, 0, gain=0.8, bars=4, skip=4)
    lead(22, 12, -2, "lead2", 0.5, -0.3, bars=4, skip=4)
    lead(34, 0, 0, gain=0.75)
    for bt, m, d in T.notes(62, "dorian", start=bar(34), shift=12):
        s.put("bell", V.bell(m, 3.0, 3.5, 2.0, 1.0), bt, s.v(0.2, 0.1), pan=0.3, ms=4)
    # the rest section: the beacon far away on glass, twice
    for b0, lvl in ((27, 0.5), (31, 0.4)):
        for bt, m, d in BEACON:
            s.put("glass", V2.glass(m + 12, 3.5, 2.0, 1.0, 1.2, 0.1), bar(b0) + bt, lvl, pan=-0.5, ms=0)
    # bells on the chord changes
    for k, (b0, nb, ci) in enumerate(plan):
        if b0 >= 2 and (sec_of(b0) != "A2" or k % 2):
            tones = CHORDS[ci][2]
            s.put("bell", V.bell(tones[(k * 3) % 6] + 12, 3.4, 3.5, 1.6, 1.4), bar(b0) + 0.5, 0.4, pan=(-0.5, 0.5)[k % 2], ms=4)
    for beat, m in ((1.0, 76), (4.5, 72)):
        s.put("bell", V.bell(m, 3.5, 3.5, 1.6, 1.3), beat, 0.3, pan=0.35, ms=3)

    # --- mix (Ledger II's EXPLORE mix)
    cut = s.auto([(0, 1000), (bar(2), 1300), (bar(10), 1800), (bar(18), 1500), (bar(26), 1300), (bar(34), 1200)], 3.0)
    pad_fc = cut * (1 + 0.25 * S.lfo(s.L, 0.05))
    pad_fx = once(lambda x: (lambda y: y * 0.55 + 0.45 * S.chorus(y, 0.2, 22, 4.0, mix=1.0))(S.lp_sweep(x, pad_fc, 450, 3500)))
    trem = (0.75 + 0.25 * S.lfo(s.L, 0.25)).astype(np.float32)
    shim_fx = once(lambda x: S.chorus(x, 0.13, 25, 6.0, 1.2, 1.0) * trem[None, :])
    echo = once(lambda x: x + 0.55 * S.pingpong(x, 0.75 * s.spb, 0.55, 9, 5000, 400))
    lead_fx = once(lambda x: x + 0.35 * S.pingpong(x, 1.5 * s.spb, 0.4, 5, 4000, 300))
    spec = dict(
        pad=dict(g=-4, hp=140, send=0.6, fx=pad_fx),
        shim=dict(g=-14, hp=900, lp=9000, send=6.0, fx=shim_fx),
        bass=dict(g=-12, hp=30, lp=600, send=0.05),
        arp=dict(g=-3, hp=400, lp=9000, send=0.4, fx=echo),
        lead=dict(g=-4, hp=250, send=0.6, fx=lead_fx),
        lead2=dict(g=-7, hp=250, send=0.6, fx=lead_fx),
        glass=dict(g=-6, hp=500, send=0.7, fx=echo),
        box=dict(g=-1, hp=350, send=0.7),
        bell=dict(g=-4, hp=350, send=0.8),
    )
    env = s.auto([(0, 0.85), (bar(2), 1.0), (bar(26), 0.92), (bar(34), 0.95)], 2.0)
    mix = s.mix(spec, S.make_ir(6.0, 40, 0.9, 61), -3, 4.5, env)
    render.bpm = s.bpm
    return s.master(S.filt(mix, lp=16000, order=4), RMS)
