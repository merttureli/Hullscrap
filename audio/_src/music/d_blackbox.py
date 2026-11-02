"""Demo 3, "Black Box": darksynth in C minor, 118 BPM, 36 bars (about 73 s), EXPLORE and BATTLE.
The 8-bar phrase: Cm (2) - Abmaj7 (2) - Fm (2) - Dbmaj7#11 (bII, 1) - G7sus4 > G7 (1); tension and release every 8 bars.
  intro (0-3) Cm pedal | A (4-11) the groove | B (12-19) the lead | C (20-27) breakdown and build | D (28-35) the drop.
One groove underneath both versions: a 16th saw pulse bass through the resonant low-pass (a short filter envelope per
note, the cutoff opening through the build), four-on-the-floor kick, 16th hats, a dark analog pad, an eighth-note
saw pluck arp and a seven-saw detuned lead with glides (B and D; doubled an octave up in D).
EXPLORE hears it through a wall: the bass low-passed to a pulse, the kick a thump, the hats far away, the lead muffled.
BATTLE opens it all: the bass and pad pump against the kick (sidechain), a gated 80s snare on 2 and 4, a snare roll
and riser through the build, stutters at phrase ends, a crush sweep, and a tape-stop into the drop."""
import numpy as np
import synth as S
import synth2 as S2
import voices as V
import voices2 as V2
from demo import Demo, once

TITLE = "Black Box"
RMS = {"explore": -18.0, "battle": -15.0}
BARS = 36
CH = {  # pad voicing, bass root
    "Cm": ([55, 60, 63, 67], 36), "Ab": ([55, 60, 63, 68], 32), "Fm": ([56, 60, 65, 68], 29),
    "Db": ([56, 60, 65, 67], 37), "Gsus": ([55, 60, 62, 65], 31), "G": ([55, 59, 62, 65], 31)}
PHRASE = ["Cm", "Cm", "Ab", "Ab", "Fm", "Fm", "Db", "G"]
PLAN = ["Cm"] * 4 + PHRASE * 4
LEAD = [(0, 72, 1.5), (1.5, 79, 0.5), (2, 75, 1), (3, 74, 1), (4, 72, 3), (7, 70, 1),
        (8, 75, 1.5), (9.5, 72, 0.5), (10, 68, 2), (12, 67, 1), (13, 68, 1), (14, 72, 2),
        (16, 77, 1.5), (17.5, 75, 0.5), (18, 72, 1), (19, 68, 1), (20, 72, 2), (22, 75, 1), (23, 77, 1),
        (24, 80, 1.5), (25.5, 79, 0.5), (26, 77, 2), (28, 79, 2), (30, 77, 0.5), (30.5, 75, 0.5), (31, 74, 1)]
ARP = [0, 7, 12, 7, 15, 12, 7, 12]   # semitones over the bass root two octaves up, eighths (15 = the minor third)
OCT = (6, 14)                        # 16th steps where the pulse bass jumps an octave


def render():
    s = Demo(118, BARS, seed=509)
    bar = lambda b: b * 4.0
    sec_of = lambda b: "intro" if b < 4 else "A" if b < 12 else "B" if b < 20 else "C" if b < 28 else "D"

    # --- pad
    for b, c in enumerate(PLAN):
        if c == "G":
            chords = (("Gsus", 0, 2), ("G", 2, 2))
        else:
            chords = ((c, 0, 4),)
        g = {"intro": 0.7, "A": 0.8, "B": 0.85, "C": 1.0, "D": 0.9}[sec_of(b)]
        for name, p, d in chords:
            for m in CH[name][0]:
                s.put("pad", V.pad(m, s.sec(d) - 0.04, 0.3 if p else 0.6, 0.9, 9.0, seed=b % 4), bar(b) + p, g * s.v(1.0, 0.04), ms=4)

    # --- the 16th pulse bass (one render shared by both versions; the cutoff opens through the build)
    steps = []
    for b, c in enumerate(PLAN):
        r = CH["G" if c == "G" else c][1]
        thin = sec_of(b) == "C" and b < 24
        for st in range(16):
            if thin and st % 4 == 3:
                continue
            steps.append((bar(b) + st / 4, 0.25, r + (12 if st in OCT else 0), 1.0 if st % 4 == 0 else 0.0, 0))
    base = s.auto([(0, 160), (bar(4), 230), (bar(12), 260), (bar(20), 150), (bar(24), 200), (bar(26), 420), (bar(28), 300)], 0.6)
    s.part("bass").buf += V2.acid(s.L, s.spb, steps, base, 2.4, 2.2, 0.075, 0.5, "saw", 0.72, 30.0, 2.0)[None, :] * 0.55
    for b, c in enumerate(PLAN):   # a sine under it for weight
        s.put("sub", V.bass(CH["G" if c == "G" else c][1], s.sec(3.9), 150.0, 1.1, 1.0, 0.0, 0.05, 0.01, 0.0), bar(b), 0.8)

    # --- arp: eighth-note saw plucks from bar 4 (not in the first half of the breakdown)
    for b in range(4, BARS):
        if 20 <= b < 24:
            continue
        r = CH[PLAN[b]][1] + 24
        for j, iv in enumerate(ARP):
            m = r + iv + (1 if iv == 15 and PLAN[b] in ("Ab", "Db", "G") else 0)   # major chords take the major third
            s.put("arp", V.pluck(m, 0.5, "saw", 1.1, 0.25), bar(b) + j / 2, s.v(0.8 if j % 2 == 0 else 0.6, 0.1), pan=(-0.5, 0.5)[j % 2], ms=2)

    # --- the lead: B, and D doubled an octave up, gliding between notes
    for b0, layers in ((12, ((0, 1.0),)), (28, ((0, 1.0), (12, 0.45)))):
        prev = None
        for bt, m, d in LEAD:
            for sh, g in layers:
                s.put("lead" if sh == 0 else "lead_hi", V2.supersaw(m + sh, s.sec(d) * 0.96, 7, 22.0, 0.01, 0.3, 0.9, 1,
                      None if prev is None else prev + sh, 35.0), bar(b0) + bt, g * s.v(1, 0.04), ms=2)
            prev = m

    # --- kit (both versions: EXPLORE hears it filtered)
    for b in range(BARS):
        sec = sec_of(b)
        if not (sec == "C" and b < 24):
            for j in range(4):
                s.hit("kick", V.kick(j % 3, 170.0, 44.0, 0.028, 0.26, 0.35), bar(b) + j, (1.0 if j % 2 == 0 else 0.92) * s.v(1, 0.03), ms=1)
        if sec != "intro" and not (sec == "C" and b < 26):
            for j in (1, 3):
                s.put("gsnare", V2.gated_snare(j % 2, 0.2, 1.4, 180.0), bar(b) + j, s.v(1.0, 0.03), ms=1)
        for st in range(16):
            if sec == "intro" and st % 2:
                continue
            v = 0.5 if st % 4 == 2 else 0.3 if st % 2 == 0 else 0.2
            s.put("hat", V.hat(st % 3, False, 7500), bar(b) + st / 4, v * s.v(1, 0.15), pan=0.3, ms=1)
        if sec == "D":
            for j in range(4):
                s.put("hat", V.hat(2, True, 6000), bar(b) + j + 0.5, 0.35, pan=-0.25, ms=1)
    # the build: a snare roll over bars 26-27 (eighths, then sixteenths) and a riser
    for k in range(8):
        s.put("roll", V.snare(k % 3, 200.0, 0.08, 2000, 0.25, 0.5), bar(26) + k * 0.5, 0.35 + 0.04 * k, ms=1)
    for k in range(16):
        s.put("roll", V.snare(k % 3, 200.0, 0.06, 2200, 0.2, 0.45), bar(27) + k * 0.25, 0.55 + 0.03 * k, ms=1)
    s.put("riser", V.riser(int(s.sec(bar(4)) * S.SR), 13, 300.0, 12000.0), bar(24), 0.9)
    s.put("crash", V.crash(1, 2.0), bar(28), 0.8, pan=0.1)
    s.put("crash", V.crash(2, 2.0), bar(12), 0.6, pan=-0.1)

    def glitch(x):
        x = S2.stutter(x, s.at(bar(11) + 3.5), s.spb / 8, s.spb / 2)
        x = S2.stutter(x, s.at(bar(15) + 3.5), s.spb / 8, s.spb / 2)
        x = S2.stutter(x, s.at(bar(19) + 3), s.spb / 4, s.spb, shrink=0.7, min_len=s.spb / 16)
        x = S2.crush_sweep(x, s.at(bar(22)), bar(2) * s.spb, (11, 5), (1, 8), 0.7)
        x = S2.tape_stop(x, s.at(bar(27) + 3), s.spb, 1.3)
        x = S2.stutter(x, s.at(bar(31) + 3.5), s.spb / 8, s.spb / 2)
        return S2.stutter(x, s.at(bar(35) + 2), s.spb / 2, 2 * s.spb, src=s.at(bar(35)), shrink=0.5, min_len=s.spb / 8)

    # --- mixes
    pump = S2.duck(s.L, s.hits["kick"], 0.6, 3.0, 0.3, 1.8)
    soft = S2.duck(s.L, s.hits["kick"], 0.3, 4.0, 0.25, 1.5)
    cut = s.auto([(0, 700), (bar(4), 900), (bar(12), 1100), (bar(20), 800), (bar(24), 1600), (bar(28), 1500)], 1.5)
    pad_fx = once(lambda x: (lambda y: y * 0.6 + 0.4 * S.chorus(y, 0.25, 17, 3.0, mix=1.0))(S.lp_sweep(x, cut * (1 + 0.2 * S.lfo(s.L, 0.06)), 350, 3000)))
    arp_fx = once(lambda x: x + 0.4 * S.pingpong(x, 0.75 * s.spb, 0.45, 7, 4000, 300))
    lead_fx = once(lambda x: x + 0.25 * S.pingpong(x, 0.75 * s.spb, 0.4, 5, 5000, 400))
    spec_x = dict(
        pad=dict(g=-8, hp=130, send=0.5, fx=pad_fx),
        bass=dict(g=-8, hp=30, lp=320, order=4, send=0.05),
        sub=dict(g=-17, hp=25, lp=140, send=0.0),
        arp=dict(g=-8, hp=300, lp=3600, send=0.45, fx=arp_fx),
        lead=dict(g=-8, hp=200, lp=2200, order=4, send=0.6, fx=lead_fx),
        lead_hi=dict(g=-14, hp=300, lp=2600, order=4, send=0.6, fx=lead_fx),
        kick=dict(g=-15, hp=28, lp=180, order=4, send=0.05),
        hat=dict(g=-2, hp=3000, lp=6000, send=0.4),
        riser=dict(g=-20, hp=300, lp=2500, send=0.4),
    )
    spec_b = dict(
        pad=dict(g=-9, hp=150, send=0.35, fx=lambda x: pad_fx(x) * soft[None, :], bus=False),
        bass=dict(g=-9, hp=30, lp=5000, send=0.03, fx=lambda x: x * pump[None, :], bus=True),
        sub=dict(g=-16, hp=25, lp=140, send=0.0, fx=lambda x: x * pump[None, :], bus=True),
        arp=dict(g=-11, hp=300, lp=7000, send=0.3, fx=lambda x: arp_fx(x) * soft[None, :]),
        lead=dict(g=-3, hp=200, lp=9000, send=0.3, fx=lead_fx),
        lead_hi=dict(g=-7, hp=300, lp=10000, send=0.3, fx=lead_fx),
        kick=dict(g=-13, hp=28, lp=6000, send=0.02, bus=True),
        gsnare=dict(g=-1, hp=120, send=0.1, bus=True),
        hat=dict(g=-4, hp=6500, send=0.1, bus=True),
        roll=dict(g=-6, hp=150, send=0.3, bus=True),
        riser=dict(g=-12, hp=300, send=0.3),
        crash=dict(g=-12, hp=500, send=0.3, bus=True),
    )
    ir = S.make_ir(2.8, 18, 1.0, 51)
    env = s.auto([(0, 0.85), (bar(4), 1.0), (bar(20), 0.9), (bar(28), 1.0)], 1.5)
    x = s.master(s.mix(spec_x, ir, -2, 3.0, env), RMS["explore"])
    y = s.master(s.mix(spec_b, ir, -4, 4.0, env, glitch), RMS["battle"])
    t, at = s.transition(x, y)
    render.bpm, render.song = s.bpm, s
    return {"explore": x, "battle": y, "transition": t, "xfade_s": at,
            "sections": {k: round(s.sec(bar(v)), 2) for k, v in (("intro", 0), ("A", 4), ("B", 12), ("C", 20), ("D", 28))}}
