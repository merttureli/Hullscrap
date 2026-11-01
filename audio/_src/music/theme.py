"""The Hullscrap theme: an 8-bar motif in D dorian, and the beacon's four notes.
Notes are (beat, MIDI, beats) in 4/4 from beat 0. D4 = 62. Odd bars state the motif (long, quick leap up,
step down, step down: A-D-C-A), even bars answer; the last bar hangs on A so the loop turns back to D."""
THEME = [
    (0.0, 69, 1.5), (1.5, 74, 0.5), (2.0, 72, 1.0), (3.0, 69, 1.0),       # bar 1  Dm   A  D  C  A
    (4.0, 65, 1.5), (5.5, 69, 0.5), (6.0, 67, 2.0),                        # bar 2       F  A  G
    (8.0, 71, 1.5), (9.5, 74, 0.5), (10.0, 76, 1.0), (11.0, 74, 1.0),      # bar 3  G    B  D  E  D
    (12.0, 71, 1.5), (13.5, 69, 0.5), (14.0, 67, 2.0),                     # bar 4       B  A  G
    (16.0, 74, 1.5), (17.5, 77, 0.5), (18.0, 74, 1.0), (19.0, 72, 1.0),    # bar 5  Bb   D  F  D  C
    (20.0, 69, 1.5), (21.5, 72, 0.5), (22.0, 74, 2.0),                     # bar 6       A  C  D
    (24.0, 76, 1.5), (25.5, 74, 0.5), (26.0, 72, 1.0), (27.0, 69, 1.0),    # bar 7  Am   E  D  C  A
    (28.0, 64, 1.5), (29.5, 67, 0.5), (30.0, 69, 2.0),                     # bar 8       E  G  A
]
# The beacon (Ada's four notes): E5 B4 D5, a breath, then A4. The last note is the theme's first note.
BEACON = [(0.0, 76, 0.9), (1.0, 71, 0.9), (2.0, 74, 0.9), (4.0, 69, 2.5)]

MODES = {"dorian": [0, 2, 3, 5, 7, 9, 10], "aeolian": [0, 2, 3, 5, 7, 8, 10], "mixolydian": [0, 2, 4, 5, 7, 9, 10],
         "minor": [0, 2, 3, 5, 7, 8, 10], "major": [0, 2, 4, 5, 7, 9, 11]}
_D = MODES["dorian"]


def degree(midi):
    """Scale degree of a D-dorian pitch counted from D4 (negative below)."""
    o, pc = divmod(midi - 62, 12)
    return o * 7 + _D.index(pc)


def pitch(deg, root, mode="dorian"):
    """The pitch of scale degree deg (0 = the tonic at `root`) in a mode."""
    o, i = divmod(deg, 7)
    return root + 12 * o + MODES[mode][i]


def notes(root=62, mode="dorian", speed=1.0, start=0.0, bars=8, steps=0, shift=0, skip_bars=0):
    """The theme re-voiced: degrees mapped into `mode` on `root`; speed 2 plays it twice as fast; steps moves every
    note that many scale degrees (-2 = a diatonic third below, for harmonies); shift is added in semitones."""
    out = []
    for b, m, d in THEME:
        if not (skip_bars * 4 <= b < (skip_bars + bars) * 4):
            continue
        out.append(((b - skip_bars * 4) / speed + start, pitch(degree(m) + steps, root, mode) + shift, d / speed))
    return out
