"""Emberkin: small, lithe, warm-blooded to an absurd degree. Charred ember skin (n/e/u), an ember glow along the spine and the
crest (the _glow layers), heat-shimmer hair (o/y flicks), a tail behind (it lives in the LEGS layer, so it follows the move direction)."""
import math
from sp_common import *

# ---------------------------------------------------------------- legs + tail
FOOT = {
 'plant': art("""
.ee.
eeee
eenn
.nn.
"""),
 'lift': art("""
.ee.
eeee
eeee
eenn
.nn.
"""),
}
LX = (10, 20)       # left edge of each shin strip; thigh is 3 wide, shin 2
def tail(s, a):
    """a = sideways swing of the tip in px. Starts under the torso, ends in a glowing tip."""
    for i, y in enumerate(range(19, 31)):
        t = i / 11.0
        x = 16 + int(round(a * t * t))
        w = 3 if t < 0.45 else 2 if t < 0.8 else 1
        x0 = x - (w - 1) // 2
        for k in range(w):
            c = 'e'
            if k == 0 and w > 1: c = 'u'
            elif k == w - 1 and w > 1: c = 'n'
            s.put(x0 + k, y, c)
        if 0.5 < t < 0.85 and w > 1: s.put(x0 + 1, y, 'o')                 # ember line along the tail
    tx = 16 + int(round(a)); ty = 30
    s.put(tx, ty, 'o'); s.put(tx, ty + 1, 'y'); s.put(tx + (1 if a >= 0 else -1), ty, 'o' if abs(a) > 1 else 'y')
def leg_frame(dl, dr, lift_l=False, lift_r=False, a=0):
    s = Spr(N, N)
    tail(s, a)
    for lx, d, lift, side in ((LX[0], dl, lift_l, -1), (LX[1], dr, lift_r, 1)):
        fy = 15 - d
        s.stamp(lx - 1, 13, art("""
eeee
eeee
nnnn
"""))
        step = -1 if fy < 15 else 1
        ys = list(range(15, fy + step, step))
        for i, y in enumerate(ys):
            near = i < len(ys) // 2
            if near:
                x0 = lx - 1 if side < 0 else lx
                s.put(x0, y, 'u'); s.put(x0 + 1, y, 'e'); s.put(x0 + 2, y, 'n')
            else:
                x0 = lx if side < 0 else lx + 1
                s.put(x0, y, 'u'); s.put(x0 + 1, y, 'n')           # 2-wide shin
        if len(ys) > 6:
            wy = ys[len(ys) * 3 // 4]                                  # shin wrap (outfit)
            x0 = lx if side < 0 else lx + 1
            dy = 1 if step < 0 else -1
            s.put(x0, wy, 'A'); s.put(x0 + 1, wy, 'C'); s.put(x0, wy + dy, 'B'); s.put(x0 + 1, wy + dy, 'C')
        b = FOOT['lift' if lift else 'plant']
        bx = (lx if side < 0 else lx) - 1 + (1 if side > 0 else 0)
        s.stamp(bx, fy - len(b) // 2, b)
    return s

# (dl, dr, lift_l, lift_r, tail swing)
WALK = [(10, -10, False, False, 3), (5, -5, False, True, 4), (-5, 5, False, True, 1),
        (-10, 10, False, False, -3), (-5, 5, True, False, -4), (5, -5, True, False, -1)]

# ---------------------------------------------------------------- torso: skin shoulders, vest panels (outfit), an ember spine
SPANS = [(12, 20), (10, 22), (9, 23), (9, 23), (9, 23), (10, 22), (11, 21), (12, 20), (12, 20), (13, 19), (13, 19), (14, 18)]
def torso_spr():
    s = Spr(N, N)
    for j, (x0, x1) in enumerate(SPANS): s.hline(x0, 11 + j, x1 - x0 + 1, 'e')
    s = shade_gen(s, 'e', 'u', 'n')
    # vest panels either side of the spine channel (outfit, tinted)
    v = Spr(N, N)
    for (x0, x1) in ((11, 15), (17, 21)):
        for y in range(13, 22):
            inset = 1 if y >= 19 else 0
            v.hline(x0 + (inset if x0 == 11 else 0), y, x1 - x0 + 1 - inset, 'B')
    v = shade_edges(v)
    for (x, y) in ((11, 13), (12, 13), (20, 13), (21, 13)): v.put(x, y, 'A')
    for y in range(13, 22):
        for x in range(N):
            if v.g[y][x] != '.': s.g[y][x] = v.g[y][x]
    # spine channel: dark bone ridge with ember vertebrae
    for y in range(13, 23): s.put(16, y, 'n')
    for y, c in ((17, 'o'), (19, 'y'), (22, 'o')): s.put(16, y, c)
    for y in (17, 19): s.put(15, y, 'n'); s.put(17, y, 'n')
    # sash with a brass pin
    s.hline(12, 20, 9, 'a'); s.hline(12, 21, 3, 'u'); s.hline(18, 21, 3, 'u'); s.put(16, 20, 'y')
    # glowing cracks on the shoulder caps
    s.put(10, 13, 'o'); s.put(22, 14, 'o'); s.put(10, 14, 'u'); s.put(22, 15, 'u')
    return s

# ---------------------------------------------------------------- heads
def head_skin():
    s = Spr(N, N)
    for j, (x0, x1) in enumerate([(14, 18), (13, 19), (12, 20), (12, 20), (12, 20), (12, 20), (13, 19), (14, 18)]):
        s.hline(x0, 9 + j, x1 - x0 + 1, 'e')
    s = shade_gen(s, 'e', 'u', 'n')
    s.put(11, 12, 'u'); s.put(11, 13, 'e')                               # small pointed ears
    s.put(21, 12, 'e'); s.put(21, 13, 'n')
    s.hline(14, 10, 5, 'n')                                              # brow
    s.put(14, 11, 'o'); s.put(18, 11, 'o')                               # glowing eyes
    return s
def crest(s, f=0):
    """heat-shimmer hair: a thin flame crest from the forehead over the crown, a plume trailing down the neck.
    f flips the flicking pixels (the glow layer carries the 2-frame flicker too)."""
    for y in range(9, 17): s.put(16, y, 'o')
    for y in (10, 13, 16): s.put(16, y, 'y')                             # hot beads along the crest
    for (x, y) in ((15, 11), (17, 12), (15, 14), (17, 14)): s.put(x, y, 'u')           # crest roots
    s.put(16, 8, 'y'); s.put(15 + f, 8, 'o')
    # plume: breaks up into flicks down the neck
    for (x, y, c) in ((16, 17, 'o'), (16, 18, 'y'), (15 + f, 18, 'o'), (17 - f, 19, 'o'), (16, 19 + f, 'y'),
                      (15 - f, 20, 'o'), (17, 21, 'y'), (16 - f, 21 + f, 'o')):
        s.put(x, y, c)
    for (x, y, c) in ((14 - f, 10, 'o'), (18 + f, 13, 'y'), (14, 15 - f, 'o')): s.put(x, y, c)
def head_crest(f=0):
    s = head_skin(); crest(s, f); return s
HELMET = art("""
..AAAAA..
.AAAAABB.
AAHAAABBC
DDDDDDDDD
AAAAABBBC
AAABBBBBC
AABBBBBCC
.ABBBBCC.
..CCCCC..
""")
def head_helmet(f=0):
    s = Spr(N, N)
    s.stamp(12, 8, HELMET)
    s.put(13, 11, 'D'); s.put(19, 11, 'D')
    for x in (14, 15, 16, 17, 18): s.put(x, 11, 'o')                    # visor slit glows
    s.put(16, 11, 'y')
    for y in range(12, 17): s.put(16, y, 'o')                            # the crest comes through a slot in the shell
    s.put(16, 14, 'y')
    for (x, y, c) in ((16, 17, 'o'), (16, 18, 'y'), (15 + f, 18, 'o'), (17 - f, 19, 'o'), (16, 19 + f, 'y'),
                      (15 - f, 20, 'o'), (17, 21, 'y'), (16 - f, 21 + f, 'o')):
        s.put(x, y, c)
    return s

# ---------------------------------------------------------------- arms: thin, 2 px, ember skin, a bracer
def limb(s, x0, y0, x1, y1, band=0.62):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(2):
            for k in range(2): s.put(x - 1 + k, y - 1 + j, 'e')
    s = shade_gen(s, 'e', 'u', 'n')
    for i in range(int(n * band), int(n * band) + 2):                    # bracer (outfit), 2 steps along the limb
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(2):
            for k in range(2): s.put(x - 1 + k, y - 1 + j, 'B')
    return s
def paw(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 'e'); s.put(x + 1, y + 1, 'n'); s.put(x - 1, y - 1, 'u')
def arms_spr(pose):
    s = Spr(N, N)
    A = HANDS.get(pose)
    if pose == 'unarmed':
        for cx in (7, 24):
            s.rect(cx, 12, 2, 8, 'e')
        s = shade_gen(s, 'e', 'u', 'n')
        for cx in (7, 24):
            s.hline(cx, 16, 2, 'B'); s.hline(cx, 17, 2, 'C')
        paw(s, 8, 21); paw(s, 25, 21)
        return s
    if pose == 'pistol':   S = [(9, 13, 13, 7), (23, 13, 19, 7)]
    elif pose == 'rifle':  S = [(23, 13, 22, 10), (9, 13, 16, 3)]
    elif pose == 'tool':   S = [(23, 13, 22, 6), (9, 13, 12, 10)]
    elif pose == 'heavy':  S = [(23, 13, 22, 12), (9, 13, 14, 4)]
    elif pose == 'melee':  S = [(23, 13, 24, 9), (9, 13, 12, 8)]
    for (a, b, c, d) in S: s = limb(s, a, b, c, d)
    for k in ('hand_l', 'hand_r'): paw(s, *A[k])
    return s

class Emberkin(Species):
    id = 'emberkin'
    walk_fps = 8
    head_names = ['crest', 'helmet']
    notes = ('Emberkin: small and lithe (shoulders 15 px), charred ember skin, a glowing spine and a heat-shimmer flame crest '
             '(head_glow flickers between two frames), a tail behind that sways with the walk and lives in the legs layer. '
             'Outfit mask = sleeveless vest, shin wraps, arm bracers, helmet shell.')
    def legs(self): return [outlined(leg_frame(*w[:4], a=w[4])) for w in WALK] + [outlined(leg_frame(1, -1, a=1))]
    def torso(self): return outlined(torso_spr())
    def arms(self, pose): return outlined(arms_spr(pose))
    def head(self, name): return outlined({'crest': head_crest, 'helmet': head_helmet}[name]())
    def torso_anchors(self): return {'head': [16, 13], 'back': [16, 22], 'shoulder_l': [10, 14], 'shoulder_r': [22, 14]}
    def arm_anchors(self): return pose_anchors((8, 21), (25, 21))
    def legs_glow(self):
        out = []
        for w in WALK + [(1, -1, False, False, 1)]:
            g = new_glow(); t = Spr(N, N); tail(t, w[4])
            glow_px(g, spr_pts(t, 'oy'), (255, 138, 30), 0.55, 3.0)
            out.append(g)
        return out
    def torso_glow(self):
        g = new_glow(); t = torso_spr()
        glow_px(g, spr_pts(t, 'oy'), (255, 138, 30), 0.6, 3.0)
        return [g]
    def head_glow(self):
        out = []
        for f in (0, 1):
            for fn in (head_crest, head_helmet):
                g = new_glow(); glow_px(g, spr_pts(fn(f), 'oy'), (255, 138, 30), 0.6, 3.0); out.append(g)
        return out
