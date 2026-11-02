"""menu.ogg  "Ma's Ledger"  D dorian, 72 BPM, 36 bars (2:00).
Intro on a Dm9 pad; then the 8-bar cycle Dm9 - G6/9 - Bb maj7 - Am7 (two bars each) four times:
A: the theme on the soft lead.  B: the theme an octave up with a harmony line a third below.
C: breakdown, the theme's first half on the music box over a busier arp.  D: the theme again, low, bells doubling."""
import numpy as np
import synth as S
import voices as V
import theme as T
from common import Song

TITLE = "Ma's Ledger"
RMS = -18.0
BARS = 36
CHORDS = [  # (pad voicing, bass root, arp tones)
    ([50, 57, 60, 64, 65], 38, [57, 62, 65, 69, 72, 76]),     # Dm9
    ([55, 59, 62, 64, 69], 43, [55, 62, 67, 71, 74, 76]),     # G6/9
    ([58, 62, 65, 69, 72], 34, [58, 62, 65, 69, 72, 74]),     # Bb maj7
    ([57, 60, 64, 67, 71], 33, [57, 60, 64, 67, 69, 72]),     # Am7
]
ARP_Q = [0, 2, 3, 5, 4, 3, 2, 1]          # a slow arp: one note a beat
ARP_E = [0, 2, 4, 5, 4, 3, 2, 3, 1, 2, 4, 5, 3, 2, 4, 2]   # eighths for B and C


def render():
    s = Song(72, BARS, seed=101)
    bar = lambda b: b * 4.0
    sec_of = lambda b: "intro" if b < 4 else "A" if b < 12 else "B" if b < 20 else "C" if b < 28 else "D"

    # --- pad and bass: one chord per two bars (the intro holds Dm9 for four)
    plan = [(0, 4, 0)] + [(4 + 2 * k, 2, k % 4) for k in range(16)]
    for k, (b0, nb, ci) in enumerate(plan):
        voicing, root, _ = CHORDS[ci]
        sec = sec_of(b0)
        g = {"intro": 0.5, "A": 0.72, "B": 0.88, "C": 0.95, "D": 0.72}[sec]
        for m in voicing:
            s.put("pad", V.pad(m, s.sec(bar(nb)) - 0.15, 1.8, 2.6, seed=k), bar(b0), g * s.v(1.0, 0.05), ms=8)
        if b0 >= 2 and not (sec == "C" and k % 2):
            s.put("bass", V.bass(root, s.sec(bar(nb)) - 0.2, 330.0, 1.2, 1.0, 0.18, 0.12, 0.04, 0.6), bar(b0), 0.8 if sec != "intro" else 0.5)

    # --- the slow arp (A and D quarters, B and C eighths), with the dotted-eighth echo
    for b in range(4, BARS):
        sec = sec_of(b)
        ci = ((b - 4) // 2) % 4
        tones = CHORDS[ci][2]
        if sec in ("A", "D"):
            for j in range(4):
                n = ARP_Q[((b - 4) * 4 + j) % 8]
                s.put("pluck", V.pluck(tones[n], 1.5, "square", 0.8, 0.55), bar(b) + j, s.v(0.30 if sec == "A" else 0.24, 0.15), pan=(-0.35, 0.35)[j % 2], ms=5)
        else:
            for j in range(8):
                n = ARP_E[((b - 4) * 8 + j) % 16]
                s.put("pluck", V.pluck(tones[n], 1.4, "square", 0.9, 0.5), bar(b) + j / 2, s.v(0.30 if sec == "B" else 0.36, 0.2), pan=(-0.5, 0.5)[j % 2], ms=5)
    # intro: the arp wakes up in its last bar
    for j, n in enumerate((0, 2, 3)):
        s.put("pluck", V.pluck(CHORDS[0][2][n], 1.5, "square", 0.8, 0.55), bar(3) + 1 + j, 0.2 + 0.05 * j, pan=0.3 * (1 - 2 * (j % 2)), ms=4)

    # --- the lead: A low, B an octave up with a harmony, D low and softer with bells doubling
    def stmt(start_bar, shift, steps, part, gain, dur_scale=0.96, pan=0.0):
        for b, m, d in T.notes(62, "dorian", start=bar(start_bar), steps=steps, shift=shift):
            s.put(part, V.lead(m, s.sec(d) * dur_scale), b, s.v(gain, 0.06), pan=pan, ms=6)
    stmt(4, 0, 0, "lead", 0.95)
    stmt(12, 12, 0, "lead", 0.8, pan=0.12)
    stmt(12, 12, -2, "lead2", 0.55, pan=-0.3)
    stmt(28, 0, 0, "lead", 0.8)
    for b, m, d in T.notes(62, "dorian", start=bar(28), shift=12):
        s.put("bell", V.bell(m, 3.0, 3.5, 2.0, 1.0), b, s.v(0.22, 0.1), pan=0.3, ms=4)
    # the breakdown: the theme's first half on the music box, then a bell answer
    for b, m, d in T.notes(62, "dorian", start=bar(20), shift=12, bars=4):
        s.put("box", V.musicbox(m, 3.2, 0.0, 0.0, 1.5), b, s.v(0.5, 0.1), pan=0.15, ms=5)
    for b, m, d in T.notes(62, "dorian", start=bar(24), shift=12, bars=4, skip_bars=4):
        s.put("box", V.musicbox(m, 3.2, 0.0, 0.0, 1.5), b, s.v(0.42, 0.1), pan=-0.15, ms=5)
    # a few bell notes in the intro
    for beat, m in ((6.0, 76), (10.0, 72), (13.5, 69)):
        s.put("bell", V.bell(m, 3.5, 3.5, 1.6, 1.3), beat, 0.25, pan=0.35, ms=3)

    # --- texture: 12 dB under round 1 and silent for the first 8 s (fades in over 8-12 s, out over the last 3 s)
    t = np.arange(s.L) / S.SR
    ramp = np.clip((t - 8.0) / 4.0, 0, 1) * np.clip((s.L / S.SR - t) / 3.0, 0, 1)
    ramp = (0.5 - 0.5 * np.cos(np.pi * ramp)).astype(np.float32)
    s.part("tex").put(V.hiss(s.L, 5) * 0.5 * (0.6 + 0.4 * S.lfo(s.L, 0.04)) * ramp, 0, 1.0, 0.0)
    s.part("tex").put(V.crackle(s.L, 6, 5.0) * 0.5 * ramp, 0, 1.0, 0.0)

    # --- mix
    pad_cut = s.auto([(0, 1100), (bar(4), 1350), (bar(12), 1700), (bar(20), 1900), (bar(28), 1450)], 2.5)
    pad_fc = pad_cut * (1 + 0.28 * S.lfo(s.L, 0.06))

    def pad_fx(x):
        y = S.lp_sweep(x, pad_fc, 500, 3000)
        return y * 0.6 + 0.4 * S.chorus(y, 0.27, 19, 3.0, mix=1.0)

    echo = lambda x: x + 0.5 * S.pingpong(x, 0.75 * s.spb, 0.5)
    spec = {
        "pad": dict(g=-3, hp=140, send=0.5, fx=pad_fx),
        "bass": dict(g=-9, hp=30, lp=700, send=0.05),
        "pluck": dict(g=-1, hp=260, lp=7500, send=0.35, fx=echo),
        "lead": dict(g=-2, hp=250, send=0.5),
        "lead2": dict(g=-5, hp=250, send=0.5),
        "bell": dict(g=0, hp=350, send=0.7),
        "box": dict(g=-2, hp=350, send=0.6),
        "tex": dict(g=-32, hp=1200, send=0.0),
    }
    env = s.auto([(0, 0.8), (bar(4), 1.0), (bar(32), 1.0), (bar(34), 0.8)], 2.0)
    mix = s.mix(spec, S.make_ir(4.2, 24, 1.0, 11), -3, 5.0, env)
    render.levels = s.levels(spec)
    render.bpm = s.bpm
    return S.master(mix, RMS)
