"""concord: the Concord's regions. The darksynth language in E dorian with a mixolydian lift, 112 BPM, 64 bars (2:17).
The orderly human federation: clean high tech, paperwork, polite surveillance. Everything sits exactly on the grid
(no swing, no humanising): a gallop of straight 16ths in the square-wave bass, a clean 16th square arpeggio, a digital
kit (short clicky kick, clap, machine hats, sine blips like data ticks) and a "broadcast" chime (the beacon's first
three notes) at every section. The lead is a clean square, the theme a sine.
  intro (0-7)  Em9 - A6/9 - Gmaj9 - Asus2>A | A (8-23) Em9 - A6/9 - Gmaj9 - D6/9 - Asus2>A, the hook from bar 16
  B (24-39)    the Hullscrap theme in E dorian on the sine, then up an octave with the square a third below
  brk (40-47)  Cmaj7 - D - Em9 - Esus4>E (the major lift), the build | A2 (48-63) the hook doubled, then its first half.
BATTLE is precise and relentless: four-on-the-floor, claps on 2 and 4, 16th hats, exact 16th stutters and buffer
repeats (no tape-stop: the Concord's machines do not wind down)."""
import voices as V
import voices2 as V2
import voices3 as V3
import dialect
import synth as S

TITLE = "Concord"
MODE = "E dorian, with a mixolydian lift (E major) into the drop"
RMS = {"explore": -18.0, "battle": -15.0}
CH = {
    "Em9": ([55, 59, 62, 66], 40, "m"), "A69": ([54, 59, 61, 64], 45, "M"), "Gmaj9": ([54, 57, 59, 62], 43, "M"),
    "D69": ([54, 57, 59, 64], 38, "M"), "Asus2": ([57, 59, 64, 69], 45, "M"), "A": ([57, 61, 64, 69], 45, "M"),
    "Cmaj7": ([55, 59, 64, 67], 36, "M"), "Bm7": ([54, 57, 62, 66], 35, "m"), "D": ([54, 57, 62, 66], 38, "M"),
    "Esus": ([57, 59, 64, 69], 40, "M"), "E": ([56, 59, 64, 68], 40, "M"),
}
PHRASE = ["Em9", "Em9", "A69", "A69", "Gmaj9", "Gmaj9", "D69", "Asus2|A"]
# the theme's opening shape (long, leap up a fourth, step down, step down) sequenced up the chords, in strict time
HOOK = [(0, 71, 1.5), (1.5, 76, 0.5), (2, 74, 1), (3, 71, 1), (4, 78, 1.5), (5.5, 76, 0.5), (6, 74, 2),
        (8, 73, 1.5), (9.5, 78, 0.5), (10, 76, 1), (11, 73, 1), (12, 71, 1.5), (13.5, 73, 0.5), (14, 76, 2),
        (16, 74, 1.5), (17.5, 79, 0.5), (18, 78, 1), (19, 74, 1), (20, 73, 1.5), (21.5, 74, 0.5), (22, 78, 2),
        (24, 76, 1), (25, 78, 1), (26, 81, 2), (28, 81, 1.5), (29.5, 76, 0.5), (30, 73, 2)]
CHIME = [(0.0, 78), (0.75, 73), (1.5, 76)]   # the beacon's first three notes, up a tone: F#5 C#5 E5
FOUR = "X...X...X...X..."
NONE = "." * 16


def extras(s, ctx):
    """The broadcast chime at every section start (both versions)."""
    for name, b0 in ctx["starts"].items():
        for bt, m in CHIME:
            s.put("chime", V.bell(m, 3.0, 2.0, 1.4, 1.1), ctx["bar"](b0) + bt, 0.8, pan=0.25)
            s.put("chime", V3.sine(m + 12, 0.4, 0.002, 1.2, 0.0), ctx["bar"](b0) + bt, 0.35, pan=-0.25)


DIALECT = dict(
    title=TITLE, bpm=112, seed=601, rms=RMS, swing=0.0, humanize_ms=0.0,
    sections=[("intro", 8), ("A", 16), ("B", 16), ("brk", 8), ("A2", 16)],
    chords=CH,
    plan={"intro": ["Em9"] * 4 + ["A69", "A69", "Gmaj9", "Asus2|A"], "A": PHRASE, "A2": PHRASE,
          "B": ["Em9", "Em9", "A69", "A69", "Cmaj7", "Cmaj7", "Bm7", "Bm7"],
          "brk": ["Cmaj7", "Cmaj7", "D", "D", "Em9", "Em9", "Esus|E", "E"]},
    pad=dict(att=0.4, rel=0.7, detune=5.0, drift=1.5, gain={"intro": 0.7, "A": 0.75, "B": 0.85, "brk": 1.0, "A2": 0.85},
             cut={"intro": 1100, "A": 1400, "B": 1700, "brk": 1300, "A2": 2000}),
    bass=dict(pattern={"default": "X.xoX.xoX.xoX.xo", "intro": "X...X...X...X...", "brk": "X...x...X...x..."}, wave="square",
              q=1.8, env_oct=2.0, decay=0.06, gate=0.6, drive=1.4, level=0.6,
              cut={"intro": 200, "A": 280, "B": 320, "brk": 200, "A2": 360}, build_x=2.5),
    arp=dict(base=64, pattern=[0, 1, 2, 3, 4, 3, 2, 1, 0, 2, 4, 5, 4, 2, 1, 3], step=0.25, vel=(0.85, 0.5, 0.65, 0.5), pan=0.35,
             patch=lambda m: V2.chip(m, 0.09, 0.5, 0.001, 0.06, 0.2, 0.04, bits=0),
             where=lambda sec, k: sec in ("A", "B", "A2") or (sec == "brk" and k >= 4)),
    lines=[
        dict(sec="A", bar=8, notes=HOOK, patch="square"),
        dict(sec="B", bar=0, notes=lambda: dialect.theme_notes(64, "dorian"), patch="sine", part="lead2", gain=1.2),
        dict(sec="B", bar=8, notes=lambda: dialect.theme_notes(64, "dorian"), patch="sine", part="lead2", shift=12, gain=1.0),
        dict(sec="B", bar=8, notes=lambda: dialect.theme_notes(64, "dorian", steps=-2), patch="square", shift=12, gain=0.5, pan=-0.2),
        dict(sec="A2", bar=0, notes=HOOK, patch="square"),
        dict(sec="A2", bar=0, notes=HOOK, patch="sine", shift=12, gain=0.6, part="lead2"),
        dict(sec="A2", bar=8, notes=HOOK, patch="square", bars=4),
    ],
    kit=dict(
        sounds={"kick": lambda i: V.kick(i % 2, 190.0, 52.0, 0.012, 0.13, 0.55),
                "clap": lambda i: V3.clap(i // 4 % 2, 0.12, 1400.0),
                "snare": lambda i: S.crush(V.snare(2, 240.0, 0.05, 3000, 0.16, 0.35), 8),
                "hat": lambda i: V.hat(i % 3, False, 8000),
                "blip": lambda i: V3.blip((1568.0, 2349.0, 1760.0, 2637.0)[(i // 2) % 4], 0.03)},
        patterns={"kick": {"default": FOUR, "intro": NONE * 4 + FOUR * 4, "brk": NONE * 4 + FOUR * 4},
                  "clap": {"default": "....X.......X...", "intro": NONE * 4 + "....X.......X..." * 4, "brk": NONE * 6 + "....X.......X..." * 2},
                  "snare": {"default": "....x.......x...", "intro": NONE * 4 + "....x.......x..." * 4, "brk": NONE * 6 + "....x.......x..." * 2},
                  "hat": {"default": "x-o-x-o-x-o-x-o-", "intro": "x...x...x...x..."},
                  "blip": {"default": "..o...o...o.o..o", "brk": "..o...o...o...o."}},
        pan={"hat": 0.3, "blip": -0.35, "clap": 0.05},
        roll=lambda k: S.crush(V.snare(k % 3, 230.0, 0.05, 2600, 0.16, 0.35), 8)),
    crash_at=("A", "B", "A2"),
    glitch=dict(stutter=(11, 19, 27, 35, 51, 59), roll=(23, 39, 55), repeat=(47, 63)),
    pump=0.45, pump_release=0.25,
    mix={
        "pad": (dict(g=-7, hp=150, send=0.45, fx=("pad",)), dict(g=-10, hp=170, send=0.3, fx=("pad", "soft_pump"))),
        "bass": (dict(g=-9, hp=30, lp=420, order=4, send=0.05), dict(g=-10, hp=30, lp=4000, send=0.03, fx=("pump",), bus=True)),
        "sub": (dict(g=-18, hp=25, lp=140, send=0.0), dict(g=-17, hp=25, lp=140, send=0.0, fx=("pump",), bus=True)),
        "arp": (dict(g=-5, hp=300, lp=6000, send=0.3, fx=("echo",)), dict(g=-7, hp=300, lp=9000, send=0.2, fx=("echo", "soft_pump"))),
        "lead": (dict(g=-7, hp=250, lp=5000, send=0.35, fx=("echo",)), dict(g=-4, hp=250, lp=9000, send=0.25, fx=("echo",))),
        "lead2": (dict(g=-6, hp=200, lp=6000, send=0.4, fx=("echo",)), dict(g=-4, hp=200, lp=9000, send=0.3, fx=("echo",))),
        "chime": (dict(g=-8, hp=400, send=0.8, fx=("echo_long",)), dict(g=-9, hp=400, send=0.6, fx=("echo_long",))),
        "kick": (dict(g=-14, hp=30, lp=220, order=4, send=0.03), dict(g=-10, hp=30, lp=8000, send=0.02, bus=True)),
        "clap": (None, dict(g=3, hp=300, lp=11000, send=0.25, bus=True)),
        "snare": (None, dict(g=-2, hp=200, lp=11000, send=0.15, bus=True)),
        "hat": (dict(g=-2, hp=5000, lp=9000, send=0.2), dict(g=1, hp=7000, lp=12000, send=0.08, bus=True)),
        "blip": (dict(g=-8, hp=800, lp=9000, send=0.4, fx=("echo",)), dict(g=-9, hp=800, lp=10000, send=0.25, bus=True)),
        "roll": (None, dict(g=-8, hp=200, send=0.25, bus=True)),
        "riser": (dict(g=-20, hp=300, lp=4000, send=0.4), dict(g=-12, hp=300, send=0.3)),
        "crash": (None, dict(g=-13, hp=500, lp=12000, send=0.3, bus=True)),
    },
    ir=(2.4, 16, 1.0, 61), rv_db=(-3, -5), air=(3.5, 4.0),
    env={"intro": 0.85, "A": 1.0, "brk": 0.92, "A2": 1.0},
)


def render():
    r = dialect.render(DIALECT, extras)
    render.bpm = r["bpm"]
    return r
