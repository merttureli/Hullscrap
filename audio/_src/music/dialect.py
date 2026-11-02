"""Round-3 piece engine: one darksynth language spoken in faction dialects.
A piece module gives a DIALECT dict (tempo, sections, chord language, scale, swing, bass, arp, lead patches and lines,
percussion kit and patterns, glitch plan, mix) and calls render(D). Every part is composed once on one Demo song;
EXPLORE and BATTLE are two mixes of the same parts, so the files are the same length and every shared note lands on
the same sample. Each is mastered to its loudness and kept under -1 dBTP once encoded. Optional `extras(s, ctx)` adds
a dialect's own parts (chimes, clanks, shimmer...). Chords are {name: (pad voicing, bass root, "m" or "M")}. Pattern strings run 16 steps a bar, counted from the start of
their section (a longer string spans several bars):
  drums  X 1.0  x 0.75  o 0.45  - 0.25  . rest
  bass   X/x root  O/o octave  F/f fifth  B/b flat seventh (upper case = accent)  y = octave slid  . rest"""
import numpy as np
import synth as S
import synth2 as S2
import voices as V
import voices2 as V2
import voices3 as V3
import theme as T
from synth import SR
from demo import Demo, once

SCALES = {"dorian": [0, 2, 3, 5, 7, 9, 10], "aeolian": [0, 2, 3, 5, 7, 8, 10], "mixolydian": [0, 2, 4, 5, 7, 9, 10],
          "phrygian": [0, 1, 3, 5, 7, 8, 10], "lydian": [0, 2, 4, 6, 7, 9, 11], "ionian": [0, 2, 4, 5, 7, 9, 11],
          "harmonic": [0, 2, 3, 5, 7, 8, 11]}
VEL = {"X": 1.0, "x": 0.75, "o": 0.45, "-": 0.25}
BASS_IV = {"x": 0, "o": 12, "f": 7, "b": 10, "y": 12, "z": 0}


def theme_notes(root, scale, start=0.0, steps=0, shift=0, bars=8, skip=0, speed=1.0):
    """The Hullscrap theme (theme.py) mapped degree by degree into `scale` on `root`."""
    sc = SCALES[scale]
    out = []
    for b, m, d in T.THEME:
        if skip * 4 <= b < (skip + bars) * 4:
            o, i = divmod(T.degree(m) + steps, 7)
            out.append(((b - skip * 4) / speed + start, root + 12 * o + sc[i] + shift, d / speed))
    return out


def chord_tones(voicing, root, lo, n):
    """n chord tones ascending from `lo`: the pitch classes of the voicing and the root."""
    pcs = sorted({m % 12 for m in voicing + [root]})
    out, m = [], lo
    while len(out) < n:
        if m % 12 in pcs:
            out.append(m)
        m += 1
    return out


def default_patches():
    """Lead patches: f(midi, seconds, previous midi or None) -> a mono or stereo note."""
    return {
        "supersaw": lambda m, d, p: V2.supersaw(m, d, 7, 22.0, 0.01, 0.3, 0.9, 1, p, 35.0),
        "square": lambda m, d, p: V2.chip(m, d, 0.5, 0.004, 0.35, 0.75, 0.1, 7.0, 5.4, 0.25, 0.0, 0),
        "sine": lambda m, d, p: V3.sine(m, d, 0.01, 0.3, 7.0, 5.2, 0.3),
        "grit": lambda m, d, p: V3.grit(m, d, -2.0 if d > 0.3 else 0.0),
        "glass": lambda m, d, p: V2.glass(m, max(2.0, d + 1.2), 3.0, 1.6, 0.9),
        "bell": lambda m, d, p: V.bell(m, max(2.5, d + 1.5), 3.5, 1.6, 1.3),
        "chip": lambda m, d, p: V2.chip(m, d, 0.25, 0.006, 0.4, 0.7, 0.12, 14.0, 5.6, 0.2, 0.03, 8),
    }


def render(D, extras=None):
    bpm, sections = D["bpm"], D["sections"]
    total = sum(n for _, n in sections)
    s = Demo(bpm, total, D["seed"])
    bar = lambda b: b * 4.0
    secs, starts, b0 = [], {}, 0
    for name, n in sections:
        starts.setdefault(name, b0)
        secs += [(name, k) for k in range(n)]
        b0 += n
    sec_of = lambda b: secs[b % total][0]
    swing = D.get("swing", 0.0)
    sw = lambda st: (swing * 0.25 if st % 2 else 0.0)   # 16th swing: the off 16ths come late
    hum = D.get("humanize_ms", 2.0)

    def chord_at(b):
        name, k = secs[b]
        plan = D["plan"][name]
        return plan[k % len(plan)].split("|")
    CH = D["chords"]

    # --- pad
    P = D["pad"]
    for b in range(total):
        cs = chord_at(b)
        g = P["gain"].get(sec_of(b), 0.8)
        for i, c in enumerate(cs):
            half = len(cs) == 2
            start, d = (2.0 * i, 2.0) if half else (0.0, 4.0)
            for m in CH[c][0]:
                s.put("pad", V.pad(m + P.get("shift", 0), s.sec(d) - 0.04, P["att"] if not i else 0.25, P["rel"], P["detune"], P.get("drift", 3.0),
                      seed=b % 4), bar(b) + start, g * s.v(1.0, 0.04), ms=hum * 2)

    # --- bass: one acid render (the dialect's patch), a sine under it
    B = D["bass"]
    steps = []
    for b in range(total):
        sec = sec_of(b)
        pat = B["pattern"].get(sec, B["pattern"]["default"])
        cs = chord_at(b)
        k = secs[b][1]
        for st in range(16):
            ch = pat[(st + 16 * k) % len(pat)]
            if ch == ".":
                continue
            r = CH[cs[min(len(cs) - 1, st // 8)]][1]
            steps.append((bar(b) + st / 4 + sw(st), 0.25, r + BASS_IV[ch.lower()], 1.0 if ch.isupper() else 0.0, ch in "yz"))
    if B.get("hold"):   # each note lasts until the next one (gate scales it), for slow bass lines
        steps = [(bt, ((steps[(i + 1) % len(steps)][0] - bt) % (4.0 * total)) or 4.0, m, a, sl) for i, (bt, d, m, a, sl) in enumerate(steps)]
    cut = s.auto([(bar(starts[k]), v) for k, v in B["cut"].items()], 0.6)
    if "brk" in starts and B.get("build", True):   # the cutoff climbs through the second half of the breakdown
        nb = dict(sections)["brk"]
        k0, k1 = int(s.at(bar(starts["brk"] + nb // 2))), int(s.at(bar(starts["brk"] + nb)))
        cut[k0:k1] *= np.linspace(1.0, B.get("build_x", 2.2), k1 - k0, dtype=np.float32)
    cut = cut * 2.0 ** (B.get("lfo", 0.0) * S.lfo(s.L, 0.03))
    s.part("bass").buf += V2.acid(s.L, s.spb, steps, cut, B["q"], B["env_oct"], B["decay"], 0.5, B.get("wave", "saw"), B["gate"],
                                  40.0, B["drive"])[None, :] * B.get("level", 0.55)
    if B.get("sub", True):
        for b in range(total):
            cs = chord_at(b)
            for i, c in enumerate(cs):
                s.put("sub", V.bass(CH[c][1], s.sec(4.0 / len(cs)) - 0.05, 150.0, 1.1, 1.0, 0.0, 0.05, 0.01, 0.0), bar(b) + 4.0 * i / len(cs), 0.8)

    # --- arp
    A = D.get("arp")
    if A:
        for b in range(total):
            if not A["where"](sec_of(b), secs[b][1]):
                continue
            cs = chord_at(b)
            n = int(4 / A["step"])
            for j in range(n):
                c = cs[min(len(cs) - 1, (j * len(cs)) // n)]
                st16 = int(j * A["step"] * 4)
                p = A["pattern"][(j + n * b) % len(A["pattern"])]
                if A.get("intervals"):   # semitones over the bass root; a minor third turns major on major chords
                    m = CH[c][1] + A["base"] + p + (1 if p % 12 == 3 and CH[c][2] == "M" else 0)
                else:                    # indices into the chord tones from a fixed base note
                    m = chord_tones(CH[c][0], CH[c][1], A["base"], max(A["pattern"]) + 1)[p]
                s.put("arp", A["patch"](m), bar(b) + j * A["step"] + sw(st16), s.v(A["vel"][j % len(A["vel"])], 0.08),
                      pan=A.get("pan", 0.5) * (-1, 1)[j % 2], ms=hum)

    # --- lead lines
    patches = {**default_patches(), **D.get("patches", {})}
    for L in D["lines"]:
        at = bar(starts[L["sec"]] + L.get("bar", 0))
        notes = L["notes"]() if callable(L["notes"]) else L["notes"]
        if L.get("bars"):
            notes = [n for n in notes if n[0] < bar(L["bars"])]
        prev = None
        for bt, m, d in notes:
            m = m + L.get("shift", 0)
            bt += sw(int(round(bt * 4))) if abs(bt * 4 - round(bt * 4)) < 1e-6 else 0.0
            sig = patches[L["patch"]](m, s.sec(d) * L.get("legato", 0.95), prev)
            s.put(L.get("part", "lead"), sig, at + bt, L.get("gain", 1.0) * s.v(1, 0.04), pan=L.get("pan", 0.0), ms=hum)
            prev = m

    # --- kit: patterns per section; the kick hits key the sidechain
    K = D["kit"]
    for b in range(total):
        sec = sec_of(b)
        for voice, pats in K["patterns"].items():
            pat = pats.get(sec, pats.get("default"))
            if not pat:
                continue
            for st in range(16):
                ch = pat[(st + 16 * secs[b][1]) % len(pat)]
                if ch == ".":
                    continue
                sig = K["sounds"][voice](st + 16 * (b % 2))
                v = VEL[ch] * s.v(1, 0.05)
                beat = bar(b) + st / 4 + sw(st)
                if voice == "kick":
                    s.hit("kick", sig, beat, v, ms=min(hum, 1.0))
                else:
                    s.put(voice, sig, beat, v, pan=K.get("pan", {}).get(voice, 0.0), ms=hum)
    if "brk" in starts:   # the build: a snare roll through the breakdown's last two bars, a riser over four
        e = starts["brk"] + dict(sections)["brk"]
        for k in range(8):
            s.put("roll", K["roll"](k), bar(e - 2) + k * 0.5, 0.3 + 0.04 * k, ms=1)
        for k in range(16):
            s.put("roll", K["roll"](k), bar(e - 1) + k * 0.25, 0.5 + 0.03 * k, ms=1)
        s.put("riser", V.riser(int(s.sec(bar(4)) * SR), D["seed"] % 50, 300.0, 12000.0), bar(e - 4), 0.9)
    for name in D.get("crash_at", ()):
        s.put("crash", V.crash(starts[name] % 3, 2.0), bar(starts[name]), 0.75, pan=0.1)

    ctx = dict(bar=bar, starts=starts, secs=secs, sec_of=sec_of, chord_at=chord_at, total=total, sw=sw)
    if extras:
        extras(s, ctx)

    # --- glitch edits on the BATTLE bus
    G = D.get("glitch", {})

    def glitch(x):
        for b in G.get("stutter", ()):
            x = S2.stutter(x, s.at(bar(b) + 3.5), s.spb / 8, s.spb / 2)
        for b in G.get("roll", ()):
            x = S2.stutter(x, s.at(bar(b) + 3), s.spb / 4, s.spb, shrink=0.7, min_len=s.spb / 16)
        for b, nb in G.get("crush", ()):
            x = S2.crush_sweep(x, s.at(bar(b)), bar(nb) * s.spb, (11, 5), (1, 8), 0.7)
        for b in G.get("tapestop", ()):
            x = S2.tape_stop(x, s.at(bar(b) + 3), s.spb, 1.3)
        for b in G.get("repeat", ()):
            x = S2.stutter(x, s.at(bar(b) + 2), s.spb / 2, 2 * s.spb, src=s.at(bar(b)), shrink=0.5, min_len=s.spb / 8)
        return x

    # --- mixes
    pump = S2.duck(s.L, s.hits.get("kick", []), D.get("pump", 0.6), 3.0, D.get("pump_release", 0.3), 1.8)
    soft = S2.duck(s.L, s.hits.get("kick", []), D.get("pump", 0.6) * 0.5, 4.0, D.get("pump_release", 0.3) * 0.85, 1.5)
    pcut = s.auto([(bar(starts[k]), v) for k, v in P["cut"].items()], 1.5)
    dot = 0.75 * s.spb
    FX = {
        "pad": once(lambda x: (lambda y: y * 0.6 + 0.4 * S.chorus(y, 0.25, 17, 3.0, mix=1.0))(
            S.lp_sweep(x, pcut * (1 + 0.2 * S.lfo(s.L, 0.06)), 350, 3500))),
        "echo": once(lambda x: x + 0.4 * S.pingpong(x, dot, 0.45, 7, 4500, 300)),
        "echo_long": once(lambda x: x + 0.55 * S.pingpong(x, 1.5 * s.spb, 0.6, 9, 4500, 300)),
        "pump": lambda x: x * pump[None, :],
        "soft_pump": lambda x: x * soft[None, :],
    }
    FX.update(D.get("fx", {})(s, ctx) if D.get("fx") else {})

    def spec(version):
        out = {}
        for part, (ex, ba) in D["mix"].items():
            p = ex if version == "explore" else ba
            if p is None:
                continue
            p = dict(p)
            fxs = p.pop("fx", ())
            if fxs:
                fns = [FX[f] for f in fxs]
                p["fx"] = (lambda fns: lambda x: _chain(fns, x))(fns)
            out[part] = p
        return out
    ir = S.make_ir(*D.get("ir", (2.8, 18, 1.0, 51)))
    env = s.auto([(bar(starts[k]), v) for k, v in D.get("env", {"intro": 0.85, "A": 1.0}).items()], 1.5)
    # a 16 kHz low-pass before the master: noise hits near Nyquist otherwise make inter-sample peaks that pull the limiter down
    top = lambda m: S.filt(m, lp=16000, order=4)
    x = s.master(top(s.mix(spec("explore"), ir, D.get("rv_db", (-2, -4))[0], D.get("air", (3.0, 4.0))[0], env)), D["rms"]["explore"])
    y = s.master(top(s.mix(spec("battle"), ir, D.get("rv_db", (-2, -4))[1], D.get("air", (3.0, 4.0))[1], env, glitch)), D["rms"]["battle"])
    render.song = s
    return {"explore": x, "battle": y, "bpm": s.bpm, "song": s,
            "sections": {k: round(s.sec(bar(v)), 2) for k, v in starts.items()},
            "transition": transition(s, x, y, starts.get("A", 0))}


def _chain(fns, x):
    for f in fns:
        x = f(x)
    return x


def transition(s, x, b, start_bar, explore_s=26.0, battle_s=30.0, fade_s=4.0, after_s=10.0, out_s=3.0):
    """A listening demo: EXPLORE from start_bar, crossfade to BATTLE mid-bar, BATTLE, crossfade back mid-bar, EXPLORE,
    fade out (about 75 s). Reads past the loop end by wrapping."""
    o = int(start_bar * 4 * s.spb)
    bar_s = s.sec(4)
    a = int((int(explore_s / bar_s) * 4 + 2.5) * s.spb)
    c = int((int((a / SR + fade_s + battle_s) / bar_s) * 4 + 1.5) * s.spb)
    f = int(fade_s * SR)
    n = c + f + int(after_s * SR)
    i = np.arange(n)
    r = lambda k: 0.5 - 0.5 * np.cos(np.pi * np.clip(k / f, 0, 1))
    w = (r(i - a) - r(i - c)).astype(np.float32)
    y = x[:, (o + i) % s.L] * (1 - w)[None, :] + b[:, (o + i) % s.L] * w[None, :]
    k = int(out_s * SR)
    y[:, -k:] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)).astype(np.float32)[None, :]
    k = int(0.3 * SR)
    y[:, :k] *= np.linspace(0, 1, k, dtype=np.float32)[None, :]
    return y.astype(np.float32)
