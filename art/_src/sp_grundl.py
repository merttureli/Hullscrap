"""Grundl: huge haulers, freight families on Concord barges. THE LARGE RIG: a 49x49 frame with the pivot at (24,24), the normal 2x2 body
(32 px) sitting at the centre, so the art overhangs it. The hand and mount targets are the shared ones moved by (+8,+8): identical
relative to the pivot, so every item fits every body. A hunched back carrying a strapped cargo container, a dark brown hide (q/Q/n), a heavy
tusked jaw, thick limbs with big fists and a slow stomping stride. Outfit = cargo-harness straps, trouser apron, wrist and shin wraps, cap."""
from sp_common import *

N = 49; C = 24; SH = C - 16        # frame, pivot, and the shift of the shared 33x33 rig targets

def R(dx, dy): return (C + dx, C + dy)                       # pivot-relative to frame coordinates
def hide(s, base='q'): return shade_gen(s, base, 'Q', 'n')
def merge(dst, src):
    for y in range(N):
        for x in range(N):
            if src.g[y][x] != '.': dst.g[y][x] = src.g[y][x]
def spans(s, y0, rows, c, cx=C):
    for j, (a, b) in enumerate(rows): s.hline(cx + a, y0 + j, b - a + 1, c)
def seg(s, x0, y0, x1, y1, w, c):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(w):
            for k in range(w): s.put(x - w // 2 + k, y - w // 2 + j, c)

# ---------------------------------------------------------------- legs: thick columns, big toed feet, a slow stomp
FOOT = {
 'plant': art("""
f.ff.ff.f
qQqqQqqQq
QqqqqqqqQ
qqqqqqqqn
qqqqqqqnn
.qqqqqnn.
..nnnnn..
"""),
 'lift': art("""
f.ff.ff.f
qQqqQqqQq
QqqqqqqqQ
qqqqqqqqn
qqqqqqqqn
qqqqqqqnn
.qqqqqnn.
..nnnnn..
"""),
}
LXC = (C - 8, C + 8)         # leg centre columns
def leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for cx, d, lift, side in ((LXC[0], dl, lift_l, -1), (LXC[1], dr, lift_r, 1)):
        fy = C - d
        leg = Spr(N, N)
        leg.rect(cx - 5, C - 4, 10, 6, 'q')                                         # hip block under the torso
        step = -1 if fy < C else 1
        ys = list(range(C, fy + step, step))
        for i, y in enumerate(ys):
            w = 9 if i < len(ys) // 2 else 7
            leg.hline(cx - w // 2, y, w, 'q')
        leg = hide(leg)
        merge(s, leg)
        if len(ys) > 6:
            wy = ys[len(ys) * 3 // 4]                                                # a shin wrap (outfit)
            s.hline(cx - 3, wy, 7, 'B'); s.hline(cx - 3, wy + (1 if step < 0 else -1), 7, 'C'); s.put(cx - 3, wy, 'A')
            ky = ys[len(ys) // 2]; s.put(cx - 2, ky, 'Q'); s.put(cx - 1, ky, 'Q'); s.put(cx, ky + step, 'n')      # knee crease
        b = FOOT['lift' if lift else 'plant']
        s.stamp(cx - 4, fy - len(b) // 2 - (2 if fy < C else 0), b)
    # a trouser apron / belt skirt (outfit) hanging off the harness, under the torso
    s.hline(C - 12, C - 2, 25, 'B'); s.hline(C - 12, C - 1, 25, 'C')
    return s

WALK = [(13, -13, False, False), (7, -7, False, True), (-7, 7, False, True),
        (-13, 13, False, False), (-7, 7, True, False), (7, -7, True, False)]

# ---------------------------------------------------------------- torso: shoulder mass, the hunch, a cargo container in a harness
GIRDLE = [(-8, 8), (-12, 12), (-15, 15), (-16, 16), (-16, 16), (-16, 16), (-16, 16), (-16, 16), (-16, 16), (-16, 16), (-16, 16),
          (-15, 15), (-14, 14), (-12, 12), (-9, 9)]                                                       # dy -9..+5
HUMP = [(-14, 14), (-14, 14), (-13, 13), (-13, 13), (-12, 12), (-11, 11), (-10, 10), (-8, 8), (-6, 6), (-3, 3)]    # dy +6..+15 (behind the crate)
CRATE = art("""
.MMMMMMMMMMMMMMMM.
MLLLLLLLLLLLLLLLLS
MLSSSSSSSSSSSSSSWS
MSWWWWWWWWWWWWWWSW
MSrrrrrrrrrrrrrrSW
MSrHrHHrHrrHHrrrSW
MSSSSSSSSSSSSSSSSW
MSSWSSSSWSSSSWSSSW
MSSWSSSSWSSSSWSSEW
MSSWSSSSWSSSSWSSEW
MSSSSSSSSSSSSSSSEW
MWWWWWWWWWWWWWWWEW
.EEEEEEEEEEEEEEEE.
""")
def torso_spr():
    s = Spr(N, N)
    # the hump and the container on it
    h = Spr(N, N); spans(h, C + 6, HUMP, 'q'); h = hide(h); merge(s, h)
    s.stamp(C - 9, C + 8, CRATE)
    for (dx, dy) in ((-6, 17), (-5, 18), (5, 16), (6, 17), (3, 18)): s.put(C + dx, C + dy, 'u')           # rust bleeding down the container
    s.put(C - 8, C + 10, 'H'); s.put(C - 7, C + 10, 'H')
    # the shoulder mass
    g = Spr(N, N); spans(g, C - 9, GIRDLE, 'q'); g = hide(g); merge(s, g)
    # folds: the trapezius ridges from the neck out to each shoulder, and creases on the back
    for i in range(9):
        s.put(C - 5 - i, C - 6 + i // 3, 'n'); s.put(C + 5 + i, C - 6 + i // 3, 'n')
    for (dx, dy) in ((-12, -4), (-11, -3), (-13, 0), (-10, 2), (-9, 3), (12, -4), (11, -3), (13, 0), (10, 2)): s.put(C + dx, C + dy, 'Q')
    for (dx, dy) in ((-8, 1), (-7, 1), (7, 1), (8, 2), (-3, 4), (3, 4)): s.put(C + dx, C + dy, 'n')
    # the cargo harness (outfit): two straps over the shoulders down to the container, a chest strap, a brass buckle
    for dx in (-8, 6):
        for dy in range(-8, 11):
            s.put(C + dx, C + dy, 'A'); s.put(C + dx + 1, C + dy, 'B'); s.put(C + dx + 2, C + dy, 'C')
    s.hline(C - 8, C + 0, 17, 'B'); s.hline(C - 8, C - 1, 17, 'A'); s.hline(C - 8, C + 1, 17, 'C')
    s.rect(C - 1, C - 2, 3, 5, 'a'); s.put(C - 1, C - 2, 'y'); s.put(C, C, 'u'); s.put(C + 1, C + 2, 'u')
    s.put(C - 8, C + 11, 'a'); s.put(C + 7, C + 11, 'a')
    return s

# ---------------------------------------------------------------- heads: a heavy skull, a blunt jaw, tusks (no mouth line: they are always chewing something)
SKULL = [(-5, 5), (-6, 6), (-6, 6), (-7, 7), (-7, 7), (-7, 7), (-7, 7), (-6, 6), (-6, 6), (-5, 5), (-4, 4)]      # dy -7..+3
def head_base():
    s = Spr(N, N)
    # tusks first (they sit under the jaw outline): cream, thick at the root, a bright tip, curving out and forward
    for sd in (-1, 1):
        t = Spr(N, N)
        for (x0, y0, x1, y1, w) in ((6, -3, 9, -5, 3), (9, -5, 11, -7, 2), (11, -7, 12, -9, 2)):
            seg(t, C + sd * x0, C + y0, C + sd * x1, C + y1, w, 'f')
        t = shade_gen(t, 'f', 'L' if sd < 0 else 'f', 's' if sd > 0 else 'f')
        merge(s, t)
        s.put(C + sd * 12, C - 9, 'H'); s.put(C + sd * 10, C - 5, 'L'); s.put(C + sd * 8, C - 3, 's')
    sk = Spr(N, N); spans(sk, C - 7, SKULL, 'v'); sk = shade_gen(sk, 'v', 's', 'q'); merge(s, sk)
    for (dx, dy) in ((-2, -6), (2, -6)): s.put(C + dx, C + dy, 'n')                                      # nostrils on the blunt jaw
    s.hline(C - 5, C - 3, 11, 'q'); s.hline(C - 4, C - 2, 9, 'v')                                         # the brow ridge
    for dx in (-4, 4): s.put(C + dx, C - 2, 'a'); s.put(C + dx, C - 3, 'n')                                # small amber eyes under it
    for (dx, dy) in ((-4, -5), (-3, -5), (-5, -4), (-4, -4)): s.put(C + dx, C + dy, 's')
    for (dx, dy) in ((0, 0), (0, 1), (-1, 2), (1, 2), (0, -1)): s.put(C + dx, C + dy, 's' if dy < 1 else 'q')      # a crease down the crown
    s.put(C - 8, C + 0, 'v'); s.put(C - 8, C + 1, 'q'); s.put(C + 8, C + 0, 'v'); s.put(C + 8, C + 1, 'q')   # small ears
    return s
CAP = art("""
...BBBBBBB...
.ABBBBBBBBBC.
AABBBBBBBBBCC
AAABBBBBBBCCC
.CCCCCCCCCCC.
""")
def head_cap():
    s = head_base()
    s.stamp(C - 6, C - 6, CAP)                                                                          # a flat hauler's cap, brim over the brow
    s.hline(C - 6, C - 7, 13, 'D')                                                                       # the brim's shadow line
    s.put(C - 5, C - 5, 'H'); s.put(C - 4, C - 5, 'H')
    s.rect(C - 1, C - 3, 3, 2, 'a'); s.put(C, C - 3, 'y')                                              # a company badge
    return s

# ---------------------------------------------------------------- arms: thick forelimbs, big knuckly fists
FIST = art("""
.QQQQQ.
QQqqqQn
QqqqqqN
QqnqnqN
.qqqqnn
..nnnn.
""".replace('N', 'n'))
def fist(s, x, y):
    s.stamp(x - 3, y - 3, FIST)
def arm(s, x0, y0, x1, y1):
    t = Spr(N, N); seg(t, x0, y0, x1, y1, 6, 'q'); t = hide(t); merge(s, t)
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    i = int(n * 0.66); x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
    s.rect(x - 3, y - 1, 6, 3, 'B'); s.hline(x - 3, y + 1, 6, 'C'); s.put(x - 3, y - 1, 'A')            # a wrist strap (outfit)
    s.put(x + 1, y, 'a')
def arms_spr(pose):
    s = Spr(N, N)
    H = pose_anchors(R(-20, 11), R(20, 11), shift=SH)[pose]
    if pose == 'unarmed':
        arm(s, C - 14, C - 3, C - 20, C + 6); arm(s, C + 14, C - 3, C + 20, C + 6)
        fist(s, *R(-20, 11)); fist(s, *R(20, 11))
        return s
    L = {'pistol': (-14, -3, -2, -11), 'rifle': (-14, -3, 1, -15), 'tool': (-14, -3, -3, -7), 'heavy': (-14, -3, -2, -13), 'melee': (-14, -3, -4, -9)}[pose]
    Rr = {'pistol': (14, -3, 2, -11), 'rifle': (14, -3, 5, -7), 'tool': (14, -3, 5, -12), 'heavy': (14, -3, 5, -4), 'melee': (14, -3, 7, -8)}[pose]
    for (a, b, c, d) in (L, Rr): arm(s, C + a, C + b, C + c, C + d)
    for k in ('hand_l', 'hand_r'): fist(s, *H[k])
    return s

class Grundl(Species):
    id = 'grundl'
    N = N
    C = C
    walk_fps = 5
    head_names = ['tusked', 'cap']
    notes = ('Grundl: huge haulers. THE LARGE RIG: the frame is 49x49 with the pivot at (24,24) (the normal 2x2 body, 32 px, sits at the centre, '
             'its shadow and pathing stay there; the art overhangs it). Mounts and hands are the shared targets moved by (+8,+8), so they are '
             'identical relative to the pivot and every item fits (item top-left = mount - item.grip, as everywhere). A hunched back under a strapped '
             'cargo container, a dark brown hide, a blunt tusked jaw with small amber eyes, thick limbs, big fists, a slow stomp (5 fps). Head '
             'variants: tusked, cap (a flat hauler\'s cap, tinted). Outfit mask = harness straps, apron, wrist and shin wraps, cap.')
    def legs(self): return [outlined(leg_frame(*w)) for w in WALK] + [outlined(leg_frame(1, -1))]
    def torso(self): return outlined(torso_spr())
    def arms(self, pose): return outlined(arms_spr(pose))
    def head(self, name): return outlined({'tusked': head_base, 'cap': head_cap}[name]())
    def torso_anchors(self): return {'head': [C, C - 2], 'back': [C, C + 14], 'shoulder_l': [C - 14, C - 3], 'shoulder_r': [C + 14, C - 3]}
    def arm_anchors(self): return pose_anchors(R(-20, 11), R(20, 11), shift=SH)
