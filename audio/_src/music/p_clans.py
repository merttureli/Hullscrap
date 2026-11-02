"""clans: the Scrapper Clans' regions. The darksynth language in A minor (pentatonic lead), 116 BPM, 64 bars (2:12).
Rowdy scrapper families, honour and debt, welded scrap tech. The 16ths swing (the off 16ths come late), the bass is
a gritty overdriven saw riff with fifths and octaves, the percussion is scrap metal (clank partials) over a punchy kick
and a roomy snare, and the lead is a distorted saw-and-square that bends up into its long notes (minor pentatonic,
the hook ends on a #9 over E7). Brassy chord stabs answer like a shout.
  intro (0-7)  Am, then F - E7 | A (8-23) Am - Am - C - G - Am - Am - F - E7, the hook from bar 16
  B (24-39)    the Hullscrap theme in A aeolian on the bending lead, then again with a second lead a third below
  brk (40-47)  F - G - Am - E7, the build | A2 (48-63) the hook doubled an octave down, then its first half.
BATTLE is a brawl: stabs on the off-beats, crush sweeps, stutters and a tape-stop into the drop."""
import voices as V
import voices3 as V3
import dialect

TITLE = "Clans"
MODE = "A minor: aeolian harmony with the major V (E7#9), a minor-pentatonic lead"
RMS = {"explore": -18.0, "battle": -15.0}
CH = {
    "Am": ([57, 60, 64, 69], 33, "m"), "C": ([55, 60, 64, 67], 36, "M"), "G": ([55, 59, 62, 67], 31, "M"),
    "F": ([57, 60, 65, 69], 29, "M"), "E7": ([56, 59, 62, 64], 28, "M"),
    "Am7": ([52, 55, 60, 64], 33, "m"), "Fmaj7": ([52, 57, 60, 65], 29, "M"), "Gb": ([50, 55, 59, 62], 31, "M"),
    "Dm9": ([53, 57, 60, 64], 38, "m"), "Fadd9": ([55, 57, 60, 65], 29, "M"), "G69": ([52, 57, 59, 62], 31, "M"),
    "Am9": ([55, 60, 64, 71], 33, "m"), "Esus": ([52, 57, 59, 62], 28, "M"), "E": ([52, 56, 59, 62], 28, "M"),
}
PHRASE = ["Am", "Am", "C", "G", "Am", "Am", "F", "E7"]
# minor pentatonic; the theme's opening shape (long, quick leap up, steps down) in every other bar
HOOK = [(0, 76, 1.5), (1.5, 79, 0.5), (2, 76, 0.5), (2.5, 74, 0.5), (3, 72, 1), (4, 69, 1.5), (5.5, 72, 0.5), (6, 69, 2),
        (8, 72, 0.75), (8.75, 74, 0.75), (9.5, 76, 1.5), (11, 79, 1), (12, 79, 1), (13, 76, 0.5), (13.5, 74, 0.5), (14, 74, 2),
        (16, 81, 1.5), (17.5, 79, 0.5), (18, 76, 1), (19, 74, 1), (20, 76, 0.5), (20.5, 74, 0.5), (21, 72, 1), (22, 69, 2),
        (24, 72, 1.5), (25.5, 74, 0.5), (26, 76, 1), (27, 72, 1), (28, 76, 1.5), (29.5, 79, 0.5), (30, 74, 1), (31, 71, 1)]
NONE = "." * 16
KICK = "X..x..x.X..x...."
METAL = (520.0, 760.0, 980.0, 640.0)


def extras(s, ctx):
    """Shout stabs: the chord and its octave, short and brassy, on the off-beats (both versions; EXPLORE hears them dark)."""
    bar, sw = ctx["bar"], ctx["sw"]
    for b in range(ctx["total"]):
        sec = ctx["sec_of"](b)
        k = ctx["secs"][b][1]
        if sec not in ("A", "A2") and not (sec == "brk" and k >= 4):
            continue
        cs = ctx["chord_at"](b)
        hits = (0.0, 0.75, 1.5) if cs[0] in ("E7", "E") else (1.5, 3.5) if sec != "brk" else (0.0,)
        for p in hits:
            for m in CH[cs[0]][0]:
                for o in (0, 12):
                    s.put("stab", V.pad(m + o, s.sec(0.32), 0.003, 0.18, 14.0, 0.0, seed=3), bar(b) + p + sw(int(p * 4)),
                          (0.75 if o else 0.9) * s.v(1, 0.06), ms=2)


DIALECT = dict(
    title=TITLE, bpm=116, seed=707, rms=RMS, swing=0.2, humanize_ms=3.0,
    sections=[("intro", 8), ("A", 16), ("B", 16), ("brk", 8), ("A2", 16)],
    chords=CH,
    plan={"intro": ["Am"] * 6 + ["F", "E7"], "A": PHRASE, "A2": PHRASE,
          "B": ["Am7", "Fmaj7", "Gb", "Dm9", "Fadd9", "G69", "Am9", "Esus|E"],
          "brk": ["F", "F", "G", "G", "Am", "Am", "E7", "E7"]},
    pad=dict(att=0.3, rel=0.6, detune=12.0, drift=4.0, gain={"intro": 0.65, "A": 0.6, "B": 0.75, "brk": 0.9, "A2": 0.65},
             cut={"intro": 800, "A": 1000, "B": 1200, "brk": 900, "A2": 1300}),
    bass=dict(pattern={"default": "X.xo.xX.x.ox.fo.", "intro": "X.....x.X.....x.", "brk": "X.......X......."}, wave="saw",
              q=3.0, env_oct=2.0, decay=0.1, gate=0.65, drive=5.0, level=0.45,
              cut={"intro": 220, "A": 300, "B": 330, "brk": 200, "A2": 380}, build_x=2.5),
    arp=dict(base=57, pattern=[0, 2, 1, 3, 2, 4, 3, 1], step=0.25, vel=(0.8, 0.45, 0.6, 0.45), pan=0.4,
             patch=lambda m: V.pluck(m, 0.35, "square", 0.9, 0.18), where=lambda sec, k: sec in ("B", "A2")),
    patches={"grit": lambda m, d, p: V3.grit(m, d, -2.0 if d >= 0.4 else 0.0, 110.0, 24.0, 5.8, 3.2, 3800.0)},
    lines=[
        dict(sec="A", bar=8, notes=HOOK, patch="grit"),
        dict(sec="B", bar=0, notes=lambda: dialect.theme_notes(69, "aeolian"), patch="grit"),
        dict(sec="B", bar=8, notes=lambda: dialect.theme_notes(69, "aeolian"), patch="grit"),
        dict(sec="B", bar=8, notes=lambda: dialect.theme_notes(69, "aeolian", steps=-2), patch="grit", part="lead2", gain=0.6, pan=-0.25),
        dict(sec="A2", bar=0, notes=HOOK, patch="grit"),
        dict(sec="A2", bar=0, notes=HOOK, patch="grit", shift=-12, gain=0.6, part="lead2", pan=0.2),
        dict(sec="A2", bar=8, notes=HOOK, patch="grit", bars=4),
    ],
    kit=dict(
        sounds={"kick": lambda i: V.kick(i % 3, 160.0, 45.0, 0.03, 0.24, 0.3),
                "snare": lambda i: V.snare(i % 3, 175.0, 0.16, 1200, 0.4, 0.8),
                "ghost": lambda i: V.snare(3 + i % 3, 200.0, 0.06, 2200, 0.18, 0.4),
                "scrap": lambda i: V.clank(i % 6, 330.0, 0.5, 1.0),
                "clank": lambda i: V.clank(3 + i % 3, METAL[(i // 2) % 4], 0.25, 0.8),
                "hat": lambda i: V.hat(i % 3, False, 7000)},
        patterns={"kick": {"default": KICK, "intro": NONE * 4 + KICK * 4, "brk": NONE * 4 + "X.......X......." * 4},
                  "snare": {"default": "....X.......X...", "intro": NONE * 4 + "....X.......X..." * 4, "brk": NONE * 6 + "....X.......X..." * 2},
                  "ghost": {"default": "..........o....o", "intro": NONE, "brk": NONE},
                  "scrap": {"default": "....x.......x...", "intro": NONE * 4 + "....x.......x..." * 4, "brk": NONE * 6 + "....x.......x..." * 2},
                  "clank": {"default": "..x...o...x..o..", "intro": "..o.......o.....", "brk": "......o.......o."},
                  "hat": {"default": "x-o-x-o-x-o-x-o-", "intro": "x.o.x.o.x.o.x.o."}},
        pan={"hat": 0.3, "clank": -0.4, "scrap": 0.15, "ghost": 0.1},
        roll=lambda k: V.snare(k % 3, 190.0, 0.08, 1800, 0.25, 0.55)),
    crash_at=("A", "B", "A2"),
    glitch=dict(stutter=(11, 19, 27, 35, 51, 59), roll=(23, 39, 55), crush=((15, 1), (31, 1), (44, 2)), tapestop=(47,), repeat=(63,)),
    pump=0.5, pump_release=0.28,
    mix={
        "pad": (dict(g=-9, hp=150, send=0.4, fx=("pad",)), dict(g=-12, hp=170, send=0.3, fx=("pad", "soft_pump"))),
        "bass": (dict(g=-10, hp=30, lp=380, order=4, send=0.05), dict(g=-10, hp=30, lp=4500, send=0.03, fx=("pump",), bus=True)),
        "sub": (dict(g=-18, hp=25, lp=140, send=0.0), dict(g=-20, hp=25, lp=140, send=0.0, fx=("pump",), bus=True)),
        "arp": (dict(g=-12, hp=300, lp=3500, send=0.3, fx=("echo",)), dict(g=-14, hp=300, lp=7000, send=0.2, fx=("echo",))),
        "lead": (dict(g=-6, hp=200, lp=2200, order=4, send=0.4, fx=("echo",)), dict(g=-2, hp=200, lp=6000, send=0.25, fx=("echo",))),
        "lead2": (dict(g=-10, hp=200, lp=2000, order=4, send=0.4), dict(g=-6, hp=150, lp=5000, send=0.25)),
        "stab": (dict(g=-16, hp=200, lp=1400, order=4, send=0.3), dict(g=-9, hp=200, lp=5000, send=0.25, fx=("soft_pump",), bus=True)),
        "kick": (dict(g=-19, hp=30, lp=200, order=4, send=0.03), dict(g=-14, hp=30, lp=6000, send=0.03, bus=True)),
        "snare": (None, dict(g=-4, hp=140, lp=11000, send=0.35, bus=True)),
        "ghost": (None, dict(g=-10, hp=200, lp=11000, send=0.2, bus=True)),
        "scrap": (dict(g=-12, hp=300, lp=3000, send=0.4), dict(g=-5, hp=250, lp=11000, send=0.3, bus=True)),
        "clank": (dict(g=-8, hp=400, lp=4500, send=0.45), dict(g=-5, hp=300, lp=11000, send=0.3, bus=True)),
        "hat": (dict(g=-4, hp=4000, lp=7000, send=0.25), dict(g=-3, hp=6000, lp=12000, send=0.1, bus=True)),
        "roll": (None, dict(g=-7, hp=150, send=0.3, bus=True)),
        "riser": (dict(g=-20, hp=300, lp=3000, send=0.4), dict(g=-12, hp=300, send=0.3)),
        "crash": (None, dict(g=-12, hp=500, lp=12000, send=0.3, bus=True)),
    },
    ir=(2.0, 12, 1.1, 71), rv_db=(-3, -5), air=(2.5, 3.0),
    env={"intro": 0.85, "A": 1.0, "brk": 0.92, "A2": 1.0},
)


def render():
    r = dialect.render(DIALECT, extras)
    render.bpm = r["bpm"]
    return r
