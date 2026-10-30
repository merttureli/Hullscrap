"""Sporeling: a walking fungus colony grown aboard derelicts. A big mushroom-cap head (cream with rust spots), a fibrous brown body,
a small colony of caps sprouting off the back, rooty stub legs, and spore puffs on the GLOW layers (two frames that drift).
Outfit = a sash and wrist / ankle wraps (tinted)."""
from sp_common import *

def fibre(s, base='q'):
    """fibrous grain over every `base` pixel: pale Q strands drifting down the body, dark n gaps between them (a fixed rule, no noise)."""
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] != base: continue
            k = (x - y // 3) % 5
            s.g[y][x] = 'Q' if k == 0 else 'n' if (k == 3 and y % 2 == 0) else 'q'
    return s

# ---------------------------------------------------------------- legs: stubby root-legs, a short slow stride
FOOT = {
 'plant': art("""
.nqqn.
nQqqqn
qqQqqq
nqqnqq
f.q.nf
"""),
 'lift': art("""
.nqqn.
nQqqqn
qqQqqq
qqqqnq
nqqnqq
f.q.nf
"""),
}
LX = (10, 19)
def leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift, side in ((LX[0], dl, lift_l, -1), (LX[1], dr, lift_r, 1)):
        fy = 15 - d
        s.stamp(lx - 1, 13, art("""
qqqqqq
qqqqqq
nnnnnn
"""))
        step = -1 if fy < 15 else 1
        ys = list(range(15, fy + step, step))
        leg = Spr(N, N)
        for i, y in enumerate(ys):
            if i < len(ys) // 2: leg.hline(lx - 1, y, 6, 'q')
            else: leg.hline(lx, y, 4, 'q')
        leg = fibre(shade_gen(leg, 'q', 'Q', 'n'))
        for y in range(N):
            for x in range(N):
                if leg.g[y][x] != '.': s.g[y][x] = leg.g[y][x]
        if len(ys) > 5:
            wy = ys[len(ys) * 3 // 4]                                                          # ankle wrap (outfit)
            s.hline(lx, wy, 4, 'B'); s.hline(lx, wy + (1 if step < 0 else -1), 4, 'C')
        b = FOOT['lift' if lift else 'plant']
        s.stamp(lx - 1, fy - len(b) // 2 - (1 if fy < 15 else 0), b)
    return s

WALK = [(9, -9, False, False), (5, -5, False, True), (-5, 5, False, True),
        (-9, 9, False, False), (-5, 5, True, False), (5, -5, True, False)]

# ---------------------------------------------------------------- torso: fibrous shoulders, a colony sprouting off the back
BODY = [(10, 22), (9, 23), (9, 23), (9, 23), (9, 23), (9, 23), (9, 23), (9, 23), (10, 22), (10, 22), (11, 21), (12, 20)]   # y 12..23 (narrower than the cap: a stem)
def mini_cap(s, x, y, w, h, base, hi, lo, spot):
    t = Spr(N, N)
    for j in range(h):
        inset = 1 if (j == 0 or j == h - 1) and w > 3 else 0
        t.hline(x + inset, y + j, w - 2 * inset, base)
    t = shade_gen(t, base, hi, lo)
    for yy in range(N):
        for xx in range(N):
            if t.g[yy][xx] != '.': s.g[yy][xx] = t.g[yy][xx]
    s.put(x + 1, y + 1, spot)
    if w > 4: s.put(x + w - 2, y + h - 2, spot)
def torso_spr():
    s = Spr(N, N)
    # fibrous body
    b = Spr(N, N)
    for j, (x0, x1) in enumerate(BODY): b.hline(x0, 12 + j, x1 - x0 + 1, 'q')
    b = fibre(shade_gen(b, 'q', 'Q', 'n'))
    for y in range(N):
        for x in range(N):
            if b.g[y][x] != '.': s.g[y][x] = b.g[y][x]
    for (x, y) in ((7, 18), (25, 19), (10, 21)): s.put(x, y, 'f')                                    # pale mycelium threads
    # the colony: caps growing off the shoulders and the back, on short stalks
    for (x, y) in ((8, 15), (8, 16), (9, 15), (25, 16), (24, 17), (14, 21), (15, 21), (20, 22), (9, 22)): s.put(x, y, 'Q')
    mini_cap(s, 4, 10, 6, 5, 'u', 'a', 'q', 'f')           # left shoulder: rust cap, cream spots
    mini_cap(s, 22, 12, 5, 4, 'f', 'f', 's', 'u')          # right shoulder: cream cap, rust spot
    mini_cap(s, 11, 22, 7, 4, 'u', 'a', 'q', 'f')          # on the back: a big rust one and two small cream ones
    mini_cap(s, 19, 23, 4, 3, 'f', 'f', 's', 'u')
    mini_cap(s, 8, 23, 3, 3, 'f', 'f', 's', 'u')
    # sash across the body (outfit), from the left shoulder to the right hip
    for i in range(11):
        x = 8 + i * 17 // 11; y = 14 + i * 7 // 11
        s.put(x, y, 'B'); s.put(x, y + 1, 'C'); s.put(x + 1, y, 'B'); s.put(x, y - 1, 'A')
    s.put(22, 20, 'a'); s.put(23, 20, 'u')                                                          # a brass pin
    return s

# ---------------------------------------------------------------- heads: the mushroom cap
CAP = [(12, 20), (10, 22), (9, 23), (8, 24), (8, 24), (8, 24), (8, 24), (8, 24), (8, 24), (9, 23), (10, 22), (12, 20)]   # y 6..17 (17 wide: it overhangs the body)
def cap_base():
    m = Spr(N, N)
    for j, (x0, x1) in enumerate(CAP): m.hline(x0, 6 + j, x1 - x0 + 1, 'f')
    s = m.copy()
    for y in range(N):
        for x in range(N):
            if m.g[y][x] != 'f': continue
            if m.get(x + 1, y + 1) == '.' or m.get(x + 1, y) == '.' or m.get(x, y + 1) == '.': s.g[y][x] = 'v'      # outer rim, lower right
            elif m.get(x + 2, y + 2) == '.' or m.get(x + 2, y + 1) == '.' or m.get(x + 1, y + 2) == '.': s.g[y][x] = 's'
    # the gill fringe: the cap is tilted, so its underside shows along the back rim as pleats
    for i, x in enumerate(range(12, 21)):
        s.put(x, 18, 'Q' if i % 2 == 0 else 'q')
    for x in (13, 15, 17, 19): s.put(x, 19, 'n')
    return s
def blot(s, x, y, rows):
    for j, r in enumerate(rows):
        for i, c in enumerate(r):
            if c != '.' and s.get(x + i, y + j) in 'fsHv': s.put(x + i, y + j, c)
SPOTS = {
 'a': ('.aa.', 'auuq', 'uuuq', '.qq.'),
 'b': ('.au', 'uuq', '.q.'),
 'c': ('au', 'uq'),
 'd': ('.aa.', 'auuu', 'uuuq', 'uuqq', '.qq.'),
}
def sprouts(s):
    """two small caps growing off the rim of the big one: a bumpy outline."""
    for (x, y, w, h, base, hi, lo) in ((21, 3, 4, 3, 'u', 'a', 'q'), (7, 5, 3, 3, 'f', 'f', 's')):
        t = Spr(N, N)
        for j in range(h): t.hline(x + (1 if j == 0 and w > 3 else 0), y + j, w - (2 if j == 0 and w > 3 else 0), base)
        t = shade_gen(t, base, hi, lo)
        for yy in range(N):
            for xx in range(N):
                if t.g[yy][xx] != '.': s.g[yy][xx] = t.g[yy][xx]
    s.put(22, 6, 'Q'); s.put(9, 7, 'Q'); s.put(22, 3, 'f'); s.put(8, 5, 'u')
    return s
def head_spotted():
    s = sprouts(cap_base())
    blot(s, 11, 8, SPOTS['b']); blot(s, 18, 7, SPOTS['c']); blot(s, 14, 11, SPOTS['d']); blot(s, 10, 13, SPOTS['c'])
    blot(s, 20, 12, SPOTS['a']); blot(s, 17, 15, SPOTS['c']); blot(s, 13, 7, SPOTS['c'])
    s.put(11, 7, 'H'); s.put(12, 7, 'H'); s.put(10, 8, 'H'); s.put(10, 9, 'H')
    return s
def head_brown():
    """the other colour of cap in the colony: rust-brown with cream spots (the inverse of the spotted one)."""
    s = sprouts(cap_base())
    for y in range(N):
        for x in range(N):
            s.g[y][x] = {'f': 'u', 'H': 'a', 's': 'q', 'v': 'n'}.get(s.g[y][x], s.g[y][x])
    for y in range(N):
        for x in range(N):
            if s.g[y][x] in 'aq' and (x + y) % 4 == 0 and 8 < y < 16: s.g[y][x] = 'u'
    SP2 = {'a': ('.ff.', 'ffsq', '.sq.'), 'b': ('ff', 'sq'), 'c': ('.f.', 'fff', '.s.')}
    for (x, y, k) in ((12, 9, 'a'), (19, 8, 'b'), (15, 12, 'c'), (11, 14, 'b'), (20, 13, 'a'), (17, 15, 'b')):
        for j, r in enumerate(SP2[k]):
            for i, c in enumerate(r):
                if c != '.' and s.get(x + i, y + j) in 'uaqn': s.put(x + i, y + j, c)
    s.put(11, 7, 'a'); s.put(12, 7, 'y'); s.put(10, 8, 'a')
    return s

# ---------------------------------------------------------------- arms: knotty fibre limbs, rooty fingers
def limb(s, x0, y0, x1, y1, w=3):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    t = Spr(N, N)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(w):
            for k in range(w): t.put(x - w // 2 + k, y - w // 2 + j, 'q')
    t = fibre(shade_gen(t, 'q', 'Q', 'n'))
    for y in range(N):
        for x in range(N):
            if t.g[y][x] != '.': s.g[y][x] = t.g[y][x]
def root_hand(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 'q'); s.put(x - 1, y - 1, 'Q'); s.put(x + 1, y + 1, 'n')
    s.put(x - 2, y - 2, 'Q'); s.put(x, y - 2, 'f'); s.put(x + 2, y - 2, 'Q'); s.put(x - 1, y - 2, 'n'); s.put(x + 1, y - 2, 'n')   # three rootlet fingers
def arms_spr(pose):
    s = Spr(N, N)
    A = HANDS.get(pose)
    SH = ((9, 14), (23, 14))
    if pose == 'unarmed':
        for (sx, sy), ex in zip(SH, (5, 27)):
            limb(s, sx, sy, ex, 17, 3)
            limb(s, ex, 17, ex, 20, 3)
        for cx in (5, 27): s.hline(cx - 1, 18, 3, 'B'); s.hline(cx - 1, 19, 3, 'C')
        root_hand(s, 5, 22); root_hand(s, 27, 22)
        return s
    ends = {'pistol': [(9, 14, 14, 6), (23, 14, 18, 6)], 'rifle': [(23, 14, 21, 10), (9, 14, 17, 2)],
            'tool': [(23, 14, 21, 5), (9, 14, 13, 10)], 'heavy': [(23, 14, 21, 13), (9, 14, 14, 4)],
            'melee': [(23, 14, 23, 9), (9, 14, 12, 8)]}[pose]
    for (a, b, c, d) in ends: limb(s, a, b, c, d, 3)
    for (a, b, c, d) in ends:                                                                      # wrist wrap (outfit)
        n = max(abs(c - a), abs(d - b), 1); i = int(n * 0.68)
        x = a + round((c - a) * i / n); y = b + round((d - b) * i / n)
        s.rect(x - 1, y - 1, 3, 2, 'B'); s.hline(x - 1, y + 1, 3, 'C')
    for k in ('hand_l', 'hand_r'): root_hand(s, *A[k])
    return s

# ---------------------------------------------------------------- glow: spore puffs (two frames that drift up and sideways)
PUFFS_HEAD = [(9, 6), (23, 8), (7, 14), (25, 16), (13, 4), (19, 3), (16, 19)]
PUFFS_BACK = [(10, 26), (22, 24), (14, 29), (25, 27), (8, 22)]
def puff_glow(pts, f, rgb=(226, 208, 172), r=2.6):
    g = new_glow()
    for i, (x, y) in enumerate(pts):
        dx = (1 if i % 2 else -1) * f; dy = -f if i % 3 else f
        glow_px_max(g, [(x + dx, y + dy)], rgb, 0.62, r + (0.6 if i % 3 == 0 else 0))
    for i, (x, y) in enumerate(pts[::2]):
        glow_px_max(g, [(x + (f if i % 2 else -f), y + 1 - 2 * f)], (255, 210, 58), 0.5, 1.5)
    return g

class Sporeling(Species):
    id = 'sporeling'
    glow_fps = 4
    walk_fps = 6
    head_names = ['spotted', 'brown']
    notes = ('Sporeling: a walking fungus colony. A big mushroom-cap head (cream with rust spots; the brown variant is the inverse, a rust cap with cream spots), '
             'a fibrous brown body, a small colony of caps sprouting off the back, rooty stub legs with a short slow stride, and spore puffs on the '
             'glow layers (head_glow and torso_glow have 2 drifting frames per variant: alternate them at ~4 fps). '
             'Outfit mask = sash, wrist and ankle wraps.')
    def legs(self): return [outlined(leg_frame(*w)) for w in WALK] + [outlined(leg_frame(1, -1))]
    def torso(self): return outlined(torso_spr())
    def arms(self, pose): return outlined(arms_spr(pose))
    def head(self, name): return outlined({'spotted': head_spotted, 'brown': head_brown}[name]())
    def torso_anchors(self): return {'head': [16, 12], 'back': [16, 25], 'shoulder_l': [9, 14], 'shoulder_r': [23, 14]}
    def arm_anchors(self): return pose_anchors((5, 22), (27, 22))
    def torso_glow(self): return [puff_glow(PUFFS_BACK, f) for f in (0, 1)]
    def head_glow(self): return [puff_glow(PUFFS_HEAD, f) for f in (0, 1) for _ in self.head_names]
