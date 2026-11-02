"""lumen: the Lumen's regions. The darksynth language in F lydian with whole-tone colour, 96 BPM felt in half time,
56 bars (2:20). The mystic glass-tech faction: light, faith, crystal. Shimmer pads (the chords plus an octave-and-fifth
halo in a long reverb), FM bells and glass, long ping-pong delays, a slow held bass, sparse kicks and one big clap on
beat 3. The hook is a hymn on the beacon's four notes (E B D . A, which sit in F lydian as they are), stepped down
the chords and ending on G# over C augmented, the whole-tone turn back to F.
  intro (0-7)  Fmaj9#11, G/F, Cmaj7, C+ | A (8-23) Fmaj9 - G/F - Dm9 - Em7 - Cmaj7 - C+, the hymn, then on bells too
  B (24-31)    the Hullscrap theme in F lydian on FM bells over the same lydian chords
  brk (32-39)  Dm9 - Em7 - Cmaj7 - C+, the build | A2 (40-55) the hymn again, then the theme's second half up high.
BATTLE adds a driving pulse under the shimmer (a 16th square bass that pumps with the kick, 16th hats, the kick and
clap louder), beautiful and cold."""
import numpy as np
import voices as V
import voices2 as V2
import voices3 as V3
import synth as S
import dialect

TITLE = "Lumen"
MODE = "F lydian, with whole-tone colour (C augmented)"
RMS = {"explore": -18.0, "battle": -15.0}
CH = {
    "Fmaj9": ([57, 60, 64, 67, 71], 41, "M"), "G/F": ([55, 59, 62, 67], 41, "M"), "Dm9": ([53, 57, 60, 64], 38, "m"),
    "Em7": ([55, 59, 62, 64], 40, "m"), "Cmaj7": ([55, 59, 64, 67], 36, "M"), "Caug": ([56, 60, 64, 68], 36, "M"),
}
PHRASE = ["Fmaj9", "Fmaj9", "G/F", "G/F", "Dm9", "Em7", "Cmaj7", "Caug"]
HYMN = [(0, 76, 0.9), (1, 71, 0.9), (2, 74, 0.9), (4, 69, 2.5), (8, 74, 0.9), (9, 69, 0.9), (10, 72, 0.9), (12, 67, 2.5),
        (16, 77, 0.9), (17, 72, 0.9), (18, 76, 0.9), (20, 71, 2.5), (24, 79, 0.9), (25, 74, 0.9), (26, 76, 0.9), (28, 80, 2.5)]
NONE = "." * 16


def extras(s, ctx):
    """The shimmer halo (both versions) and the driving 16th pulse (BATTLE only)."""
    bar = ctx["bar"]
    steps = []
    for b in range(ctx["total"]):
        c = ctx["chord_at"](b)[0]
        voicing, root, _ = CH[c]
        for m in (voicing[1] + 12, voicing[2] + 19, voicing[-1] + 12):
            s.put("shim", V.pad(m, s.sec(4) - 0.05, 2.5, 3.5, 5.0, 6.0, seed=b % 3 + 5), bar(b), 0.5, ms=0)
        if ctx["sec_of"](b) != "intro" or ctx["secs"][b][1] >= 4:
            for st in range(16):
                steps.append((bar(b) + st / 4, 0.25, root + (12 if st % 4 == 2 else 0), 1.0 if st % 4 == 0 else 0.0, 0))
    cut = s.auto([(0, 380), (bar(ctx["starts"]["A"]), 520), (bar(ctx["starts"]["brk"]), 300), (bar(ctx["starts"]["A2"]), 600)], 0.8)
    s.part("pulse").buf += V2.acid(s.L, s.spb, steps, cut, 1.6, 1.8, 0.06, 0.4, "pulse", 0.6, 30.0, 1.3)[None, :] * 0.5


def fx(s, ctx):
    trem = (0.75 + 0.25 * S.lfo(s.L, 0.2)).astype(np.float32)
    return {"shim": dialect.once(lambda x: S.chorus(x, 0.11, 25, 6.0, 1.2, 1.0) * trem[None, :])}


DIALECT = dict(
    title=TITLE, bpm=96, seed=809, rms=RMS, swing=0.0, humanize_ms=3.0,
    sections=[("intro", 8), ("A", 16), ("B", 8), ("brk", 8), ("A2", 16)],
    chords=CH,
    plan={"intro": ["Fmaj9"] * 4 + ["G/F", "G/F", "Cmaj7", "Caug"], "A": PHRASE, "A2": PHRASE,
          "B": ["Fmaj9", "Fmaj9", "G/F", "G/F", "Dm9", "Dm9", "Cmaj7", "Caug"],
          "brk": ["Dm9", "Dm9", "Em7", "Em7", "Cmaj7", "Cmaj7", "Caug", "Caug"]},
    pad=dict(att=1.2, rel=2.2, detune=6.0, drift=3.0, gain={"intro": 0.6, "A": 0.75, "B": 0.85, "brk": 0.9, "A2": 0.8},
             cut={"intro": 1300, "A": 1800, "B": 2200, "brk": 1600, "A2": 2400}),
    bass=dict(pattern={"default": "X.......x.....x.", "intro": "X...............", "brk": "X.......x......."}, wave="saw",
              q=1.3, env_oct=1.2, decay=0.35, gate=0.92, drive=1.3, level=0.6, hold=True,
              cut={"intro": 150, "A": 200, "B": 230, "brk": 150, "A2": 240}, build_x=2.0),
    arp=dict(base=72, pattern=[0, 2, 4, 3, 1, 3, 5, 2], step=0.5, vel=(0.7, 0.5), pan=0.55,
             patch=lambda m: V2.glass(m, 1.4, 3.0, 1.2, 0.5, 0.25), where=lambda sec, k: (sec in ("A", "A2") and k >= 8) or sec in ("B", "brk")),
    lines=[
        dict(sec="A", bar=0, notes=HYMN, patch="glass", gain=1.1),
        dict(sec="A", bar=8, notes=HYMN, patch="bell", part="lead2", gain=0.9),
        dict(sec="A", bar=8, notes=HYMN, patch="glass", shift=12, gain=0.5),
        dict(sec="B", bar=0, notes=lambda: dialect.theme_notes(65, "lydian"), patch="bell", part="lead2", gain=1.0),
        dict(sec="B", bar=0, notes=lambda: dialect.theme_notes(65, "lydian"), patch="sine", part="lead3", gain=0.5),
        dict(sec="A2", bar=0, notes=HYMN, patch="glass", gain=1.1),
        dict(sec="A2", bar=0, notes=HYMN, patch="bell", part="lead2", shift=12, gain=0.55),
        dict(sec="A2", bar=8, notes=lambda: dialect.theme_notes(65, "lydian", skip=4, bars=4), patch="glass", shift=12, gain=0.9),
        dict(sec="A2", bar=8, notes=lambda: dialect.theme_notes(65, "lydian", skip=4, bars=4), patch="sine", part="lead3", gain=0.45),
    ],
    kit=dict(
        sounds={"kick": lambda i: V.kick(0, 115.0, 40.0, 0.04, 0.33, 0.08),
                "clap": lambda i: V3.clap(1, 0.26, 1000.0),
                "shaker": lambda i: V.brush(i % 3, 0.12, 5000, 11000, 0.02),
                "hat": lambda i: V.hat(i % 3, False, 8000)},
        patterns={"kick": {"default": "X.........x.....X...............", "intro": NONE * 4 + "X..............." * 4,
                           "brk": NONE * 4 + "X.......X......." * 4},
                  "clap": {"default": "........X.......", "intro": NONE * 4 + "........X......." * 4, "brk": NONE * 6 + "........X......." * 2},
                  "shaker": {"default": "o.-.o.-.o.-.o.-.", "intro": "o...o...o...o..."},
                  "hat": {"default": "x-o-x-o-x-o-x-o-", "intro": NONE, "brk": NONE * 4 + "x-o-x-o-x-o-x-o-" * 4}},
        pan={"shaker": -0.35, "hat": 0.3},
        roll=lambda k: V.snare(k % 3, 220.0, 0.05, 2500, 0.16, 0.3)),
    crash_at=("A", "A2"),
    glitch=dict(stutter=(15, 47), roll=(23, 31), repeat=(55,)),
    pump=0.55, pump_release=0.4,
    fx=fx,
    mix={
        "pad": (dict(g=-7, hp=150, send=0.6, fx=("pad",)), dict(g=-9, hp=170, send=0.5, fx=("pad", "soft_pump"))),
        "shim": (dict(g=-14, hp=900, lp=9000, send=6.0, fx=("shim",)), dict(g=-17, hp=900, lp=9000, send=5.0, fx=("shim",))),
        "bass": (dict(g=-9, hp=30, lp=300, order=4, send=0.05), dict(g=-13, hp=30, lp=400, send=0.03, fx=("soft_pump",))),
        "sub": (dict(g=-19, hp=25, lp=140, send=0.0), dict(g=-18, hp=25, lp=140, send=0.0, fx=("pump",), bus=True)),
        "pulse": (None, dict(g=-9, hp=40, lp=3000, send=0.05, fx=("pump",), bus=True)),
        "arp": (dict(g=-12, hp=500, lp=10000, send=0.5, fx=("echo_long",)), dict(g=-13, hp=500, lp=10000, send=0.4, fx=("echo_long",))),
        "lead": (dict(g=-6, hp=400, send=0.7, fx=("echo_long",)), dict(g=-5, hp=400, send=0.5, fx=("echo_long",))),
        "lead2": (dict(g=-6, hp=300, send=0.7, fx=("echo_long",)), dict(g=-5, hp=300, send=0.5, fx=("echo_long",))),
        "lead3": (dict(g=-12, hp=250, send=0.6), dict(g=-12, hp=250, send=0.5)),
        "kick": (dict(g=-16, hp=30, lp=180, order=4, send=0.05), dict(g=-10, hp=30, lp=5000, send=0.05, bus=True)),
        "clap": (dict(g=-8, hp=400, lp=6000, send=1.2), dict(g=0, hp=300, lp=11000, send=0.9, bus=True)),
        "shaker": (dict(g=-8, hp=4000, lp=10000, send=0.4), dict(g=-6, hp=4000, lp=11000, send=0.3, bus=True)),
        "hat": (None, dict(g=-4, hp=7000, lp=12000, send=0.15, bus=True)),
        "roll": (None, dict(g=-9, hp=200, send=0.4, bus=True)),
        "riser": (dict(g=-20, hp=300, lp=4000, send=0.5), dict(g=-13, hp=300, send=0.4)),
        "crash": (dict(g=-20, hp=600, lp=9000, send=0.6), dict(g=-12, hp=500, lp=12000, send=0.4, bus=True)),
    },
    ir=(5.0, 36, 0.9, 81), rv_db=(-2, -4), air=(4.0, 4.0),
    env={"intro": 0.85, "A": 1.0, "brk": 0.92, "A2": 1.0},
)


def render():
    r = dialect.render(DIALECT, extras)
    render.bpm = r["bpm"]
    return r
