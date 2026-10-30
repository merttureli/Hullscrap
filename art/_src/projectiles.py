"""Projectiles. All face UP at rotation 0 (travel direction = up); beam and laser segments tile along y."""
from px_structure import *

# ======================================================================== LASER: 4 wide x 16 tall tileable segment
def laser_segment():
    t = Spr(4, 16)
    for y in range(16):
        t.put(0, y, 'r'); t.put(3, y, 'r')
        t.put(1, y, 'H'); t.put(2, y, 'H')
    for y in (6, 7, 14):                                    # hot beads travelling along the beam: orange rim
        t.put(0, y, 'o'); t.put(3, y, 'o')
    t.put(0, 15, 'r'); t.put(3, 15, 'r')
    return t


def laser_impact():
    """3 frames, 16x16: hot flare where the beam hits (centre 8,8)."""
    f0 = Spr(16, 16)
    f0.stamp(5, 5, ("..HH..", ".HHHH.", "HHHHHH", "HHHHHH", ".HHHH.", "..HH.."))
    for (x, y, c) in ((8, 2, 'y'), (7, 2, 'o'), (8, 1, 'r'), (8, 13, 'y'), (7, 13, 'o'), (2, 7, 'y'), (1, 7, 'o'), (13, 8, 'y'), (14, 8, 'o'), (4, 4, 'o'), (11, 11, 'o'), (11, 4, 'r'), (4, 11, 'r')):
        f0.put(x, y, c)
    f1 = Spr(16, 16)
    f1.stamp(5, 5, (".yHHy.", "yHHHHy", "HHHHHH", "HHHHHH", "yHHHHy", ".yHHy."))
    for (x, y, c) in ((7, 0, 'r'), (8, 0, 'r'), (7, 1, 'o'), (8, 1, 'o'), (7, 2, 'y'), (8, 2, 'y'), (7, 13, 'y'), (8, 13, 'y'), (7, 14, 'o'), (8, 14, 'o'), (7, 15, 'r'), (8, 15, 'r'),
                      (0, 7, 'r'), (1, 7, 'o'), (2, 7, 'y'), (15, 8, 'r'), (14, 8, 'o'), (13, 8, 'y'), (3, 3, 'o'), (2, 2, 'r'), (12, 12, 'o'), (13, 13, 'r'), (12, 3, 'o'), (13, 2, 'r'), (3, 12, 'o'), (2, 13, 'r')):
        f1.put(x, y, c)
    f2 = Spr(16, 16)
    f2.stamp(6, 6, ("oyyo", "yHHy", "yHHy", "oyyo"))
    for (x, y, c) in ((8, 2, 'o'), (7, 1, 'r'), (8, 12, 'o'), (7, 13, 'r'), (2, 8, 'o'), (1, 7, 'r'), (12, 7, 'o'), (14, 8, 'r'), (4, 4, 'r'), (11, 11, 'r'), (11, 4, 'o'), (4, 11, 'o')):
        f2.put(x, y, c)
    return [f0, f1, f2]


# ======================================================================== BOLT: 4 frames, 6 wide x 12 tall (pellet head up, flickering tail)
BOLT_HEAD = ["..yy..", ".yHHy.", "yHHHHy", "yHHHHy", ".yHHy.", "..yy.."]
BOLT_TAILS = [
    ("..oo..", ".roor.", "..oo..", "..ro..", "...r.."),
    (".roo..", "..oo..", "..oo..", "...r..", "...r.."),
    ("..oo..", "..oor.", "..ro..", "..r...", "......"),
    ("..oor.", ".roo..", "..oo..", "..or..", "...r.."),
]


def bolt_frames():
    out = []
    for i, tail in enumerate(BOLT_TAILS):
        s = Spr(6, 12)
        s.stamp(0, 0, BOLT_HEAD)
        for j, row in enumerate(tail[:6]):
            s.stamp(0, 6 + j, [row]) if 6 + j < 12 else None
        if i % 2: s.put(2, 2, 'y'); s.put(3, 3, 'y')           # the core flutters
        out.append(s)
    return out


# ======================================================================== FLAK: 2 frames, 6 x 8 (dark shell, hot spark behind it)
def flak_frames():
    shell = ["..EE..", ".EMME.", "EMLMSE", "EMMSSE", ".ESSE.", "..EE.."]
    f0 = Spr(6, 8); f0.stamp(0, 0, shell); f0.put(2, 6, 'o'); f0.put(3, 6, 'y'); f0.put(3, 7, 'r')
    f1 = Spr(6, 8); f1.stamp(0, 0, shell); f1.put(2, 6, 'y'); f1.put(3, 6, 'o'); f1.put(2, 7, 'r'); f1.put(4, 7, 'r')
    return [f0, f1]


# ======================================================================== MISSILE: 3 frames, 6 wide x 20 tall (12px body + 8px exhaust)
MISSILE_BODY = art_strict("""
..KK..
.KrrK.
.KrrK.
KLMSEK
KLMSEK
KLMSEK
KMMSEK
KLMSEK
KWWWWK
KWKKWK
.KaaK.
.KKKK.
""", 6, 12, 'missile_body')
EXHAUST = [
    ("..yy..", ".yHHy.", ".oyyo.", "..oo..", "..rr..", "...r.."),
    (".yHHy.", ".yHHy.", ".oyyo.", ".ooo..", "..oo..", "..rr..", "..rr..", "...r.."),
    ("..yy..", "..oy..", "..oo..", "..r..."),
]


def missile_frames():
    out = []
    for ex in EXHAUST:
        s = Spr(6, 20)
        s.stamp(0, 0, MISSILE_BODY)
        for j, row in enumerate(ex): s.stamp(0, 12 + j, [row])
        out.append(s)
    return out


# ======================================================================== BEAM: 6 wide x 16 tall tileable, 3 flicker frames
def beam_frames():
    out = []
    # per-row widths of the bright part: pulses travel along the beam; each frame the pulses sit in different rows
    pulses = [(2, 9), (5, 12), (0, 7, 14)]
    for fi, pr in enumerate(pulses):
        t = Spr(6, 16)
        for y in range(16):
            t.put(2, y, 'H'); t.put(3, y, 'H')
            t.put(1, y, 'c'); t.put(4, y, 'c')
            if (y + fi) % 4 != 0:
                t.put(0, y, 'b'); t.put(5, y, 'b')
        for y in pr:
            for dy in (0, 1):
                yy = (y + dy) % 16
                t.put(0, yy, 'c'); t.put(5, yy, 'c'); t.put(1, yy, 'H'); t.put(4, yy, 'H')
        out.append(t)
    return out


def beam_impact():
    """3 frames, 16x16, cyan flare at the end of the beam (beam comes in from the bottom)."""
    f0 = Spr(16, 16)
    f0.stamp(5, 5, ("..HH..", ".HHHH.", "HHHHHH", "HHHHHH", ".HHHH.", "..HH.."))
    for (x, y, c) in ((8, 1, 'c'), (7, 1, 'b'), (8, 2, 'c'), (1, 7, 'c'), (2, 7, 'c'), (14, 8, 'c'), (13, 8, 'c'), (4, 4, 'b'), (11, 4, 'b'), (7, 13, 'c'), (8, 14, 'b'), (3, 11, 'b'), (12, 11, 'b')):
        f0.put(x, y, c)
    f1 = Spr(16, 16)
    f1.stamp(5, 5, (".cHHc.", "cHHHHc", "HHHHHH", "HHHHHH", "cHHHHc", ".cHHc."))
    for (x, y, c) in ((7, 0, 'b'), (8, 0, 'b'), (7, 1, 'c'), (8, 1, 'c'), (7, 2, 'c'), (8, 2, 'c'), (0, 7, 'b'), (1, 7, 'c'), (2, 7, 'c'), (15, 8, 'b'), (14, 8, 'c'), (13, 8, 'c'),
                      (3, 3, 'c'), (2, 2, 'b'), (12, 3, 'c'), (13, 2, 'b'), (12, 12, 'c'), (13, 13, 'b'), (3, 12, 'c'), (2, 13, 'b')):
        f1.put(x, y, c)
    f2 = Spr(16, 16)
    f2.stamp(6, 6, ("bccb", "cHHc", "cHHc", "bccb"))
    for (x, y, c) in ((8, 3, 'c'), (7, 2, 'b'), (3, 8, 'c'), (2, 7, 'b'), (12, 7, 'c'), (13, 8, 'b'), (8, 12, 'c'), (7, 13, 'b'), (4, 4, 'b'), (11, 4, 'b'), (4, 11, 'b'), (11, 11, 'b')):
        f2.put(x, y, c)
    return [f0, f1, f2]
