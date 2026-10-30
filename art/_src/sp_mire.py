"""Mire: amphibians, shipboard firefighters by tradition (Concord fire crews). Smooth teal-green skin (U/T/t) with a pale cream belly band
(f) down the flanks, a wide flat head with two bulging gold eyes on top, webbed hands and big webbed feet, and their own rig accessory:
a dripping water-tank backpack (steel tank, fire-crew red bands, a blue sight glass, a leaky valve). Outfit = tank straps, belt, a
fire-crew helmet, ankle straps (tinted)."""
from sp_common import *

def skin(s, base='T'): return shade_gen(s, base, 'U', 't')

# ---------------------------------------------------------------- legs: thick thighs, big webbed flippers, a waddling stride
FOOT = {
 'plant': art("""
t.tt.t
TfTTfT
TTTTTT
UTTTTt
.TTTt.
"""),
 'lift': art("""
t.tt.t
TfTTfT
TTTTTT
UTTTTt
UTTTTt
.TTTt.
"""),
}
LX = (9, 20)
def leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift, side in ((LX[0], dl, lift_l, -1), (LX[1], dr, lift_r, 1)):
        fy = 15 - d
        s.stamp(lx - 1, 13, art("""
BBBBBB
BBBBBB
CCCCCC
"""))                                                        # belt skirt under the torso (outfit)
        step = -1 if fy < 15 else 1
        ys = list(range(15, fy + step, step))
        leg = Spr(N, N)
        for i, y in enumerate(ys):
            if i < len(ys) // 2: leg.hline(lx - 1, y, 6, 'T')       # thigh 6 wide
            else: leg.hline(lx, y, 4, 'T')                          # shin 4
        leg = skin(leg)
        for y in range(N):
            for x in range(N):
                if leg.g[y][x] != '.': s.g[y][x] = leg.g[y][x]
        if len(ys) > 5:
            wy = ys[len(ys) * 3 // 4]                                                          # ankle strap (outfit)
            s.hline(lx, wy, 4, 'B'); s.hline(lx, wy + (1 if step < 0 else -1), 4, 'C')
        b = FOOT['lift' if lift else 'plant']
        s.stamp(lx - 1, fy - len(b) // 2 - (1 if fy < 15 else 0), b)
    return s

WALK = [(11, -11, False, False), (6, -6, False, True), (-6, 6, False, True),
        (-11, 11, False, False), (-6, 6, True, False), (6, -6, True, False)]

# ---------------------------------------------------------------- torso: round shoulders, pale flanks, the water-tank backpack
SPANS = [(9, 23), (7, 25), (6, 26), (6, 26), (6, 26), (6, 26), (6, 26), (7, 25), (8, 24), (9, 23), (10, 22), (11, 21)]   # y 10..21
TANK = art("""
..LLLLLLLLL..
.LMMMMMMMMMS.
LMSbbbbbbbSSW
LMSbHbbbbbSWE
MSSSSSSSSSSWE
.WSSSSSSSSWE.
..WWWWWWWEE..
""")
def torso_spr():
    s = Spr(N, N)
    # the tank first (it sits behind the shoulders), then the body over its top edge
    s.stamp(10, 21, TANK)
    for x in (13, 19): s.vline(x, 22, 6, 'r'); s.vline(x + 1, 22, 6, 'r'); s.vline(x, 22, 1, 'a')       # fire-crew red bands
    s.put(16, 20, 'a'); s.put(16, 21, 'y'); s.put(15, 21, 'a'); s.put(17, 21, 'a')                    # brass valve on the top
    s.put(21, 25, 'E'); s.put(22, 24, 'E'); s.put(22, 25, 'E'); s.put(22, 26, 'E'); s.put(21, 27, 'E')  # the hose coil on the right end
    b = Spr(N, N)
    for j, (x0, x1) in enumerate(SPANS): b.hline(x0, 10 + j, x1 - x0 + 1, 'T')
    b = skin(b)
    for y in range(N):
        for x in range(N):
            if b.g[y][x] != '.': s.g[y][x] = b.g[y][x]
    # pale flank bands down both sides (the belly band wraps round the ribs) and mottling
    for y in range(14, 20):
        for x in (6, 7, 25, 26):
            if s.g[y][x] != '.': s.g[y][x] = 'f'
    for (x, y) in ((12, 12), (13, 12), (19, 12), (18, 13), (11, 15), (21, 16), (14, 19), (18, 18), (16, 21)): s.put(x, y, 't')
    for (x, y) in ((12, 16), (20, 14), (15, 17), (17, 20), (13, 18)): s.put(x, y, 'U')
    s.put(9, 11, 'H'); s.put(10, 11, 'U')                                                              # wet gloss on the shoulder
    s.put(23, 11, 'U')
    # tank straps over the shoulders, and a belt (outfit)
    for i in range(6):
        s.put(10 + i // 2, 12 + i, 'B'); s.put(22 - i // 2, 12 + i, 'B')
        s.put(9 + i // 2, 12 + i, 'A'); s.put(23 - i // 2, 12 + i, 'C')
    s.hline(8, 19, 17, 'B'); s.hline(8, 20, 17, 'C'); s.put(16, 19, 'M'); s.put(15, 19, 'L')
    # a drip falling from the valve and a wet stain
    s.put(18, 28, 'b'); s.put(18, 29, 'b'); s.put(14, 29, 'H'); s.put(14, 28, 'b')
    return s

# ---------------------------------------------------------------- heads: wide, flat, bulging gold eyes
HEAD_SPANS = [(12, 20), (10, 22), (9, 23), (9, 23), (9, 23), (10, 22), (11, 21), (12, 20), (13, 19)]     # y 9..17
def head_base():
    s = Spr(N, N)
    for j, (x0, x1) in enumerate(HEAD_SPANS): s.hline(x0, 9 + j, x1 - x0 + 1, 'T')
    s = skin(s)
    for x in range(13, 20): s.put(x, 17, 'f')                                                          # pale chin edge
    for x in range(14, 19): s.put(x, 16, 'f')
    s.put(15, 10, 't'); s.put(17, 10, 't')                                                              # nostrils
    for x in range(11, 22): s.put(x, 13, 't') if s.g[13][x] != '.' else None                          # the wide mouth line
    for (x, y) in ((14, 14), (18, 14), (16, 15)): s.put(x, y, 'U')
    s.stamp(9, 7, art("""
.yy.
yaaa
aKKa
.uu.
""")); s.stamp(20, 7, art("""
.yy.
aaay
aKKa
.uu.
"""))                                                                                                  # bulging eyes sit proud of the head: gold iris, slit pupil
    s.put(10, 8, 'H')
    return s
HELMET = art("""
...BBBBB...
..BBBBBBB..
.ABBABBBBC.
AABBABBBBCC
AABBBBBBBCC
AAABBBBBBCC
.AAMMMMMCC.
..MMMMMMM..
""")
def head_helmet():
    s = Spr(N, N)
    s.stamp(10, 9, HELMET)
    s.hline(12, 16, 9, 'W'); s.hline(13, 17, 7, 'E')                                                    # the brim shadows the face
    s.stamp(8, 11, art("""
.yy.
yaaa
aKKa
.uu.
""")); s.stamp(21, 11, art("""
.yy.
aaay
aKKa
.uu.
"""))                                                                                                  # the eyes bulge out from under the shell
    s.put(16, 9, 'r'); s.put(16, 10, 'r'); s.put(16, 11, 'r')                                          # fire-crew stripe up the crest
    s.put(13, 10, 'H'); s.put(12, 11, 'H')
    s.put(15, 16, 'r'); s.put(16, 16, 'r'); s.put(17, 16, 'r')
    return s

# ---------------------------------------------------------------- arms: thick smooth limbs, webbed hands
def limb(s, x0, y0, x1, y1, w=3):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    t = Spr(N, N)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(w):
            for k in range(w): t.put(x - w // 2 + k, y - w // 2 + j, 'T')
    t = skin(t)
    for y in range(N):
        for x in range(N):
            if t.g[y][x] != '.': s.g[y][x] = t.g[y][x]
def webhand(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 'T'); s.put(x - 1, y - 1, 'U'); s.put(x + 1, y + 1, 't')
    s.put(x - 2, y - 2, 't'); s.put(x, y - 2, 'T'); s.put(x + 2, y - 2, 't')                           # three fingers, webbed between
    s.put(x - 1, y - 2, 'f'); s.put(x + 1, y - 2, 'f'); s.put(x - 2, y - 1, 'T'); s.put(x + 2, y - 1, 'T')
def arms_spr(pose):
    s = Spr(N, N)
    A = HANDS.get(pose)
    SH = ((7, 13), (25, 13))
    if pose == 'unarmed':
        for (sx, sy), ex in zip(SH, (6, 26)):
            limb(s, sx, sy, ex, 18, 4)
        for cx in (6, 26): s.vline(cx - 1 if cx < 16 else cx + 1, 14, 3, 'f')
        webhand(s, 6, 21); webhand(s, 26, 21)
        return s
    ends = {'pistol': [(7, 13, 14, 6), (25, 13, 18, 6)], 'rifle': [(25, 13, 21, 10), (7, 13, 17, 2)],
            'tool': [(25, 13, 21, 5), (7, 13, 13, 10)], 'heavy': [(25, 13, 21, 13), (7, 13, 14, 4)],
            'melee': [(25, 13, 23, 9), (7, 13, 12, 8)]}[pose]
    for (a, b, c, d) in ends: limb(s, a, b, c, d, 3)
    for (a, b, c, d) in ends:                                                                          # wrist strap (outfit)
        n = max(abs(c - a), abs(d - b), 1); i = int(n * 0.66)
        x = a + round((c - a) * i / n); y = b + round((d - b) * i / n)
        s.rect(x - 1, y - 1, 3, 2, 'B'); s.hline(x - 1, y + 1, 3, 'C')
    for k in ('hand_l', 'hand_r'): webhand(s, *A[k])
    return s

class Mire(Species):
    id = 'mire'
    walk_fps = 7
    head_names = ['bare', 'helmet']
    notes = ('Mire: amphibians and shipboard firefighters. Smooth teal-green skin with a pale belly band down the flanks, a wide flat head with two '
             'bulging gold eyes, webbed hands (three fingers and a pale web) and big webbed feet with a waddling stride, and a dripping '
             'water-tank backpack (their own rig accessory: red fire-crew bands, blue sight glass, a leaking valve). Head variants: bare, '
             'helmet (a fire-crew helmet, tinted, the eyes bulge out under the brim). Outfit mask = tank straps, belt, ankle and wrist straps, helmet shell.')
    def legs(self): return [outlined(leg_frame(*w)) for w in WALK] + [outlined(leg_frame(1, -1))]
    def torso(self): return outlined(torso_spr())
    def arms(self, pose): return outlined(arms_spr(pose))
    def head(self, name): return outlined({'bare': head_base, 'helmet': head_helmet}[name]())
    def torso_anchors(self): return {'head': [16, 13], 'back': [16, 25], 'shoulder_l': [8, 13], 'shoulder_r': [24, 13]}
    def arm_anchors(self): return pose_anchors((6, 21), (26, 21))
