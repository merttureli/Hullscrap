"""Prismatic: Lumen crystal-born, grown in the Prism's growth chambers. A faceted crystal body in navy (N/I/J/j) and cyan (c, Y, z), sharp
shoulder shards, a fan of crystals down the back, a light core in the chest (the glow layers carry the core and the lit edges; it pulses
over two frames, they hum when content), and no visible mouth. Outfit = a waist sash, cuffs and ankle bands (tinted cloth).
Y and z are the neon cyan mid / dark (B and C are the outfit symbols, see pal_races1)."""
import math
from sp_common import *
import pal_races1     # noqa: F401  (registers Y / z)

def inside(pts, x, y):
    """is the pixel centre inside the polygon (ray cast)."""
    px, py = x + 0.5, y + 0.5; n = len(pts); c = False
    for i in range(n):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
        if (y0 > py) != (y1 > py) and px < (x1 - x0) * (py - y0) / float(y1 - y0) + x0: c = not c
    return c
def poly(s, pts, c):
    ys = [p[1] for p in pts]; xs = [p[0] for p in pts]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        for x in range(int(min(xs)), int(max(xs)) + 1):
            if inside(pts, x, y): s.put(x, y, c)
def line(s, a, b, c):
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    for i in range(n + 1): s.put(a[0] + round((b[0] - a[0]) * i / n), a[1] + round((b[1] - a[1]) * i / n), c)
def shard(s, pts, lit, dark, split, edge='c'):
    """a crystal: the polygon split along `split` (two points) into a lit and a dark half, with a bright ridge along the split."""
    a, b = split
    for y in range(N):
        for x in range(N):
            if inside(pts, x, y):
                side = (b[0] - a[0]) * (y + 0.5 - a[1]) - (b[1] - a[1]) * (x + 0.5 - a[0])
                s.put(x, y, lit if side <= 0 else dark)
    line(s, a, b, edge)

# ---------------------------------------------------------------- legs: crystal struts with a cyan seam, shard feet
FOOT = {
 'plant': art("""
.cj.
jJJI
JJII
.II.
"""),
 'lift': art("""
.cj.
jJJI
jJJI
JJII
.II.
"""),
}
LX = (10, 20)
def leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift, side in ((LX[0], dl, lift_l, -1), (LX[1], dr, lift_r, 1)):
        fy = 15 - d
        s.stamp(lx - 1, 13, art("""
JJJJ
IIII
NNNN
"""))
        step = -1 if fy < 15 else 1
        ys = list(range(15, fy + step, step))
        for i, y in enumerate(ys):
            if i < len(ys) // 2:
                s.put(lx - 1, y, 'j'); s.put(lx, y, 'J'); s.put(lx + 1, y, 'J'); s.put(lx + 2, y, 'I')       # a 4-wide thigh
            else:
                s.put(lx, y, 'j'); s.put(lx + 1, y, 'J'); s.put(lx + 2, y, 'I')                              # a 3-wide shin
            if i % 3 == 1: s.put(lx + 1, y, 'Y')                                                          # the cyan seam, dashed
        if len(ys) > 5:
            ky = ys[len(ys) // 2]; s.put(lx - 1, ky, 'c'); s.put(lx, ky, 'j')                              # a bright facet at the knee
            wy = ys[len(ys) * 3 // 4]; s.hline(lx, wy, 3, 'B'); s.hline(lx, wy + (1 if step < 0 else -1), 3, 'C')   # ankle band (outfit)
        b = FOOT['lift' if lift else 'plant']
        s.stamp(lx - (1 if side < 0 else 0), fy - len(b) // 2 - (1 if fy < 15 else 0), b)
    return s

WALK = [(11, -11, False, False), (6, -6, False, True), (-6, 6, False, True),
        (-11, 11, False, False), (-6, 6, True, False), (6, -6, True, False)]

# ---------------------------------------------------------------- torso: octagon of facets, shoulder shards, a fan of crystals down the back
OCT = [(16, 9), (22, 10), (25, 15), (22, 22), (16, 25), (10, 22), (7, 15), (10, 10)]
CORE = (16, 20)
def torso_spr():
    s = Spr(N, N)
    # the fan of back crystals (behind the body): short, fat shards
    shard(s, [(10, 21), (8, 28), (15, 25)], 'J', 'I', ((10, 21), (8, 28)), 'z')
    shard(s, [(13, 24), (16, 30), (19, 24)], 'j', 'I', ((16, 24), (16, 30)), 'Y')
    shard(s, [(17, 25), (24, 28), (22, 21)], 'I', 'N', ((22, 21), (24, 28)), 'z')
    # the body: eight big flat facets round the centre, light from the top left
    tones = ['j', 'J', 'J', 'I', 'N', 'I', 'J', 'j']
    cx, cy = 16, 16
    for i in range(8):
        poly(s, [(cx, cy), OCT[i], OCT[(i + 1) % 8]], tones[i])
    for i in (1, 2, 5, 6): line(s, (cx, cy), OCT[i], 'I' if i in (2, 5) else 'J')                        # two faint seams
    for i in range(8):                                                                                # a crisp 1px rim: cyan on the lit edges, dark on the shaded ones
        a, b = OCT[i], OCT[(i + 1) % 8]
        line(s, a, b, 'c' if i in (7, 0) else 'Y' if i in (6, 1) else 'N' if i in (3, 4) else 'J')
    # the light core, low on the back so the head leaves it visible
    poly(s, [(16, 17), (19, 20), (16, 24), (13, 20)], 'Y')
    poly(s, [(16, 18), (18, 20), (16, 23), (14, 20)], 'c')
    s.put(16, 19, 'H'); s.put(16, 20, 'H'); s.put(15, 20, 'H'); s.put(16, 21, 'H')
    # shoulder shards, a big one up and out and a small one low
    shard(s, [(9, 11), (2, 5), (5, 13), (8, 16)], 'j', 'J', ((9, 11), (5, 13)), 'c')
    shard(s, [(8, 17), (3, 21), (8, 23)], 'J', 'I', ((8, 17), (8, 23)), 'Y')
    shard(s, [(23, 11), (30, 5), (27, 13), (24, 16)], 'J', 'I', ((23, 11), (27, 13)), 'Y')
    shard(s, [(24, 17), (29, 21), (24, 23)], 'I', 'N', ((24, 17), (24, 23)), 'z')
    # a waist sash (outfit cloth)
    s.hline(9, 19, 15, 'A'); s.hline(9, 20, 15, 'B'); s.hline(9, 21, 15, 'C')
    s.put(9, 22, 'C'); s.put(8, 22, 'B'); s.put(8, 23, 'C')
    return s

# ---------------------------------------------------------------- heads: a faceted gem, no mouth, no eyes (the lit tones are cyan so it reads against the navy body)
GEM = [(16, 8), (20, 10), (21, 14), (19, 18), (16, 19), (13, 18), (11, 14), (12, 10)]
def head_gem(crown=False):
    s = Spr(N, N)
    if crown:                                                                                          # three prongs on the brow
        for (tip, base) in (((11, 4), [(12, 10), (14, 9)]), ((16, 2), [(14, 9), (18, 9)]), ((21, 4), [(18, 9), (20, 10)])):
            poly(s, [tip] + base, 'Y' if tip[0] < 16 else 'z'); line(s, tip, base[0], 'c')
    cx, cy = 16, 13
    tones = ['Y', 'Y', 'z', 'z', 'J', 'z', 'Y', 'Y']
    for i in range(8):
        poly(s, [(cx, cy), GEM[i], GEM[(i + 1) % 8]], tones[i])
    for i in (0, 2, 4, 6): line(s, (cx, cy), GEM[i], 'J' if i in (4, 2) else 'z')                        # the facet seams
    for i in range(8):
        a, b = GEM[i], GEM[(i + 1) % 8]
        line(s, a, b, 'c' if i in (7, 0, 6) else 'Y' if i in (1,) else 'J' if i in (3, 4, 5) else 'z')
    poly(s, [(16, 11), (18, 13), (16, 15), (14, 13)], 'j')                                             # the table facet at the crown
    s.put(15, 12, 'H'); s.put(16, 11, 'c'); s.put(14, 13, 'c')
    return s

# ---------------------------------------------------------------- arms: crystal beams, a bright facet at the elbow, kite hands
def beam(s, x0, y0, x1, y1, w=3):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    t = Spr(N, N)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(w):
            for k in range(w): t.put(x - w // 2 + k, y - w // 2 + j, 'J')
    t = shade_gen(t, 'J', 'j', 'I')
    for y in range(N):
        for x in range(N):
            if t.g[y][x] != '.': s.g[y][x] = t.g[y][x]
    m = n // 2
    s.put(x0 + round((x1 - x0) * m / n), y0 + round((y1 - y0) * m / n), 'c')                            # the elbow glint
    i = int(n * 0.7)
    x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
    s.rect(x - 1, y - 1, 3, 2, 'B'); s.hline(x - 1, y + 1, 3, 'C')                                      # a cuff (outfit)
def kite(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 'Y'); s.put(x - 1, y - 1, 'c'); s.put(x + 1, y + 1, 'z'); s.put(x, y + 1, 'z')
    s.put(x, y - 2, 'c'); s.put(x - 1, y - 2, 'Y'); s.put(x + 1, y - 2, 'z')                           # a fingertip, pointing forward
def arms_spr(pose):
    s = Spr(N, N)
    A = HANDS.get(pose)
    if pose == 'unarmed':
        beam(s, 7, 13, 6, 19); beam(s, 25, 13, 26, 19)
        kite(s, 6, 21); kite(s, 26, 21)
        return s
    ends = {'pistol': [(7, 13, 14, 6), (25, 13, 18, 6)], 'rifle': [(25, 13, 21, 10), (7, 13, 17, 2)],
            'tool': [(25, 13, 21, 5), (7, 13, 13, 10)], 'heavy': [(25, 13, 21, 13), (7, 13, 14, 4)],
            'melee': [(25, 13, 23, 9), (7, 13, 12, 8)]}[pose]
    for (a, b, c, d) in ends: beam(s, a, b, c, d)
    for k in ('hand_l', 'hand_r'): kite(s, *A[k])
    return s

# ---------------------------------------------------------------- glow: the core, and the lit edges
def core_glow(f):
    g = new_glow(); t = torso_spr()
    glow_px_max(g, [CORE], (60, 242, 255), (0.7, 0.5)[f], (5.5, 4.5)[f], 1.5)
    glow_px_max(g, [(16, 20)], (244, 246, 248), 0.4, 2.0, 1.2)
    glow_px_max(g, spr_pts(t, 'c'), (60, 242, 255), 0.26, 2.0)
    return g
def head_glow_f(name, f):
    g = new_glow(); h = head_gem(name == 'crown')
    glow_px_max(g, spr_pts(h, 'cH'), (60, 242, 255), (0.4, 0.3)[f], 2.2)
    return g

class Prismatic(Species):
    id = 'prismatic'
    glow_fps = 2
    walk_fps = 8
    head_names = ['gem', 'crown']
    notes = ('Prismatic: Lumen crystal-born. A faceted crystal body in navy and cyan, sharp shoulder shards, a fan of crystals down the back and a light '
             'core low on the back (torso_glow: the core and every lit cyan edge, 2 frames that pulse at ~2 fps, they hum when content). No eyes, no visible '
             'mouth. Head variants: gem (a cut gem), crown (three prongs on the brow); head_glow has 2 pulse frames per variant. '
             'Outfit mask = waist sash, cuffs and ankle bands (cloth worn over the crystal).')
    def legs(self): return [outlined(leg_frame(*w)) for w in WALK] + [outlined(leg_frame(1, -1))]
    def torso(self): return outlined(torso_spr())
    def arms(self, pose): return outlined(arms_spr(pose))
    def head(self, name): return outlined(head_gem(name == 'crown'))
    def torso_anchors(self): return {'head': [16, 14], 'back': [16, 24], 'shoulder_l': [7, 13], 'shoulder_r': [25, 13]}
    def arm_anchors(self): return pose_anchors((6, 21), (26, 21))
    def torso_glow(self): return [core_glow(0), core_glow(1)]
    def head_glow(self): return [head_glow_f(n, f) for f in (0, 1) for n in self.head_names]
