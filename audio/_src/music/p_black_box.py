"""black_box: the default space piece. Darksynth in C minor, 118 BPM, 64 bars (2:10), EXPLORE and BATTLE.
The round-2 "Black Box" demo grown into a full loop with the same sounds:
  intro (0-7)   a Cm pedal, the pulse bass waking; BATTLE's kick comes in at bar 4
  A (8-23)      the groove: Cm - Abmaj7 - Fm - Dbmaj7#11 - Gsus4>G (8 bars, twice); the hook on the detuned lead from bar 16
  B (24-39)     the Hullscrap theme in C aeolian over Cm7 - Abmaj7 - Bb - Fm9 - Abadd9 - Bb6/9 - Cm9 - Gsus4>G,
                then again an octave up with a harmony a third below
  brk (40-47)   the groove without kick or snare, then the build (the bass filter opens, snare roll, riser, tape-stop)
  A2 (48-63)    the drop: the hook doubled an octave up, then its first half, and the groove carries into the loop.
EXPLORE hears the groove through a wall (bass low-passed, kick a thump, lead muffled); BATTLE opens it with the
sidechain pump, a gated snare on 2 and 4, stutters at phrase ends, a crush sweep and the tape-stop into the drop."""
import voices as V
import voices2 as V2
import dialect
import synth as S

TITLE = "Black Box"
MODE = "C minor: aeolian with the harmonic-minor V (G7) and the phrygian bII (Dbmaj7#11)"
RMS = {"explore": -18.0, "battle": -15.0}
CH = {
    "Cm": ([55, 60, 63, 67], 36, "m"), "Ab": ([55, 60, 63, 68], 32, "M"), "Fm": ([56, 60, 65, 68], 29, "m"),
    "Db": ([56, 60, 65, 67], 37, "M"), "Gsus": ([55, 60, 62, 65], 31, "M"), "G": ([55, 59, 62, 65], 31, "M"),
    "Cm7": ([55, 58, 63, 67], 36, "m"), "Bb": ([53, 58, 62, 65], 34, "M"), "Fm9": ([56, 60, 63, 67], 29, "m"),
    "Abadd9": ([58, 60, 63, 68], 32, "M"), "Bb69": ([55, 60, 62, 65], 34, "M"), "Cm9": ([51, 55, 58, 62], 36, "m"),
}
PHRASE = ["Cm", "Cm", "Ab", "Ab", "Fm", "Fm", "Db", "Gsus|G"]
# the hook from the round-2 demo (C minor, the theme's opening shape: long, leap up, step down, step down)
HOOK = [(0, 72, 1.5), (1.5, 79, 0.5), (2, 75, 1), (3, 74, 1), (4, 72, 3), (7, 70, 1),
        (8, 75, 1.5), (9.5, 72, 0.5), (10, 68, 2), (12, 67, 1), (13, 68, 1), (14, 72, 2),
        (16, 77, 1.5), (17.5, 75, 0.5), (18, 72, 1), (19, 68, 1), (20, 72, 2), (22, 75, 1), (23, 77, 1),
        (24, 80, 1.5), (25.5, 79, 0.5), (26, 77, 2), (28, 79, 2), (30, 77, 0.5), (30.5, 75, 0.5), (31, 74, 1)]
FOUR = "X...X...X...X..."
NONE = "." * 16

DIALECT = dict(
    title=TITLE, bpm=118, seed=509, rms=RMS,
    sections=[("intro", 8), ("A", 16), ("B", 16), ("brk", 8), ("A2", 16)],
    chords=CH,
    plan={"intro": ["Cm"] * 6 + ["Ab", "Gsus|G"], "A": PHRASE, "brk": PHRASE, "A2": PHRASE,
          "B": ["Cm7", "Ab", "Bb", "Fm9", "Abadd9", "Bb69", "Cm9", "Gsus|G"]},
    pad=dict(att=0.6, rel=0.9, detune=9.0, gain={"intro": 0.7, "A": 0.8, "B": 0.85, "brk": 1.0, "A2": 0.9},
             cut={"intro": 700, "A": 900, "B": 1100, "brk": 900, "A2": 1500}),
    bass=dict(pattern={"default": "XxxxXxoxXxxxXxox", "brk": "Xxx.Xxo.Xxx.Xxo."}, q=2.4, env_oct=2.2, decay=0.075, gate=0.72,
              drive=2.0, level=0.55, cut={"intro": 160, "A": 230, "B": 260, "brk": 150, "A2": 300}, build_x=2.8),
    arp=dict(intervals=True, base=24, pattern=[0, 7, 12, 7, 15, 12, 7, 12], step=0.5, vel=(0.8, 0.6), pan=0.5,
             patch=lambda m: V.pluck(m, 0.5, "saw", 1.1, 0.25), where=lambda sec, k: sec != "intro" and not (sec == "brk" and k < 4)),
    lines=[
        dict(sec="A", bar=8, notes=HOOK, patch="supersaw", legato=1.0),
        dict(sec="B", bar=0, notes=lambda: dialect.theme_notes(60, "aeolian"), patch="supersaw", legato=1.0),
        dict(sec="B", bar=8, notes=lambda: dialect.theme_notes(60, "aeolian"), patch="supersaw", shift=12, gain=0.8, legato=1.0),
        dict(sec="B", bar=8, notes=lambda: dialect.theme_notes(60, "aeolian", steps=-2), patch="supersaw", shift=12, gain=0.5,
             part="lead_hi", legato=1.0),
        dict(sec="A2", bar=0, notes=HOOK, patch="supersaw", legato=1.0),
        dict(sec="A2", bar=0, notes=HOOK, patch="supersaw", shift=12, gain=0.45, part="lead_hi", legato=1.0),
        dict(sec="A2", bar=8, notes=HOOK, patch="supersaw", bars=4, legato=1.0),
    ],
    kit=dict(
        sounds={"kick": lambda i: V.kick(i % 3, 170.0, 44.0, 0.028, 0.26, 0.35),
                "gsnare": lambda i: V2.gated_snare((i // 4) % 2, 0.2, 1.4, 180.0),
                "hat": lambda i: V.hat(i % 3, False, 7500), "ohat": lambda i: V.hat(2, True, 6000)},
        patterns={"kick": {"default": FOUR, "intro": NONE * 4 + FOUR * 4, "brk": NONE * 4 + FOUR * 4},
                  "gsnare": {"default": "....X.......X...", "intro": NONE, "brk": NONE * 6 + "....X.......X..."},
                  "hat": {"default": "o-x-o-x-o-x-o-x-", "intro": "o.x.o.x.o.x.o.x."},
                  "ohat": {"A2": "..o...o...o...o."}},
        pan={"hat": 0.3, "ohat": -0.25},
        roll=lambda k: V.snare(k % 3, 200.0, 0.07, 2100, 0.22, 0.47)),
    crash_at=("B", "A2"),
    glitch=dict(stutter=(11, 19, 27, 35, 51, 59), roll=(23, 39, 55), crush=((44, 2),), tapestop=(47,), repeat=(63,)),
    pump=0.6, pump_release=0.3,
    fx=lambda s, ctx: {"lead_echo": dialect.once(lambda x: x + 0.25 * S.pingpong(x, 0.75 * s.spb, 0.4, 5, 5000, 400))},
    mix={  # part: (EXPLORE spec, BATTLE spec)
        "pad": (dict(g=-8, hp=130, send=0.5, fx=("pad",)), dict(g=-9, hp=150, send=0.35, fx=("pad", "soft_pump"))),
        "bass": (dict(g=-8, hp=30, lp=320, order=4, send=0.05), dict(g=-9, hp=30, lp=5000, send=0.03, fx=("pump",), bus=True)),
        "sub": (dict(g=-17, hp=25, lp=140, send=0.0), dict(g=-16, hp=25, lp=140, send=0.0, fx=("pump",), bus=True)),
        "arp": (dict(g=-8, hp=300, lp=3600, send=0.45, fx=("echo",)), dict(g=-11, hp=300, lp=7000, send=0.3, fx=("echo", "soft_pump"))),
        "lead": (dict(g=-8, hp=200, lp=2200, order=4, send=0.6, fx=("lead_echo",)), dict(g=-3, hp=200, lp=9000, send=0.3, fx=("lead_echo",))),
        "lead_hi": (dict(g=-14, hp=300, lp=2600, order=4, send=0.6, fx=("lead_echo",)), dict(g=-7, hp=300, lp=10000, send=0.3, fx=("lead_echo",))),
        "kick": (dict(g=-15, hp=28, lp=180, order=4, send=0.05), dict(g=-13, hp=28, lp=6000, send=0.02, bus=True)),
        "gsnare": (None, dict(g=-1, hp=120, send=0.1, bus=True)),
        "hat": (dict(g=-2, hp=3000, lp=6000, send=0.4), dict(g=-6, hp=6500, lp=12000, send=0.1, bus=True)),
        "ohat": (None, dict(g=-6, hp=6000, lp=12000, send=0.1, bus=True)),
        "roll": (None, dict(g=-6, hp=150, send=0.3, bus=True)),
        "riser": (dict(g=-20, hp=300, lp=2500, send=0.4), dict(g=-12, hp=300, send=0.3)),
        "crash": (None, dict(g=-12, hp=500, send=0.3, bus=True)),
    },
    ir=(2.8, 18, 1.0, 51), rv_db=(-2, -4), air=(3.0, 4.0),
    env={"intro": 0.85, "A": 1.0, "brk": 0.9, "A2": 1.0},
)


def render():
    r = dialect.render(DIALECT)
    render.bpm = r["bpm"]
    return r
