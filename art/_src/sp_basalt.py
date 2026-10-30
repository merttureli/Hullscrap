"""Basalt (silicon-based labour caste): wide, blocky, stone-plated shoulders, a small head sunk between them, thick slow legs.
Rock = D/E/W/S (cool slate), crystal veins = c/b/H (glow layer optional), outfit = harness straps and wraps (A/B/C, tinted)."""
from sp_common import *

def shade_stone(s, base='W', hi='S', lo='E'):
    n = s.copy()
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] != base: continue
            if s.get(x, y + 1) == '.' or s.get(x + 1, y) == '.': n.g[y][x] = lo
            elif s.get(x, y - 1) == '.' or s.get(x - 1, y) == '.': n.g[y][x] = hi
    return n

CRYSTAL_V = art("""
.cb
cHb
cbb
.bb
..b
""")
CRYSTAL_S = art("""
.c
cb
.b
""")

# ---------------------------------------------------------------- legs: thick, stone boots (slow: 6 fps, shorter swing than the fenn)
FOOT = {
 'plant': art("""
.SSSSS.
SSWWWWW
SWWWWWE
WWWWWEE
WEEEEEE
.EEEEE.
"""),
 'lift': art("""
.SSSSS.
SSSSWWW
SSWWWWE
SWWWWWE
WWWWWEE
WEEEEEE
.EEEEE.
"""),
}
LX = (8, 20)        # left edge of each 5-wide shin strip
def leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift, side in ((LX[0], dl, lift_l, -1), (LX[1], dr, lift_r, 1)):
        fy = 15 - d
        s.rect(lx - 1, 12, 7, 4, 'E')                                  # hip block (under the torso)
        step = -1 if fy < 15 else 1
        ys = list(range(15, fy + step, step))
        for i, y in enumerate(ys):
            near = i < len(ys) // 2
            x0 = lx - 1 if near else lx
            w = 7 if near else 5                                       # thigh 7 wide, shin 5
            s.hline(x0, y, w, 'E'); s.put(x0, y, 'W'); s.put(x0 + w - 1, y, 'D')
            if i % 4 == 3: s.hline(x0, y, w, 'D')                      # stone seams
        if len(ys) > 4:
            ky = ys[len(ys) // 2]                                      # knee wrap (outfit)
            wx = lx - 1
            s.hline(wx, ky, 7, 'B'); s.put(wx, ky, 'A'); s.hline(wx, ky + (1 if step < 0 else -1), 7, 'C')
        b = FOOT['lift' if lift else 'plant']
        s.stamp(lx - 1, fy - len(b) // 2, b)
        if side < 0 and len(ys) > 6: s.put(lx + 1, ys[len(ys) // 2 + 2], 'c')      # crystal fleck on one shin
    return s

WALK = [(11, -11, False, False), (6, -6, False, True), (-6, 6, False, True),
        (-11, 11, False, False), (-6, 6, True, False), (6, -6, True, False)]

# ---------------------------------------------------------------- torso
def torso_spr():
    s = Spr(N, N)
    # back slab + crystal cluster (behind the shoulders), pointing back
    bev(s, 12, 18, 9, 6, 'W', 'E', 'D')
    s.stamp(11, 21, CRYSTAL_V); s.stamp(15, 22, CRYSTAL_V); s.stamp(19, 21, CRYSTAL_V)
    s.stamp(14, 20, CRYSTAL_S); s.stamp(18, 24, CRYSTAL_S)
    # chest / upper back block between the pauldrons
    bev(s, 11, 8, 11, 13, 'W', 'E', 'D')
    # harness straps (outfit) from the pauldron inner edges meeting at a buckle on the upper back
    for (x, y) in ((12, 16), (13, 17), (14, 18), (15, 19), (16, 19), (17, 19), (18, 18), (19, 17), (20, 16)):
        s.put(x, y, 'B'); s.put(x, y + 1, 'C'); s.put(x, y - 1, 'A')
    s.put(16, 19, 'a'); s.put(15, 19, 'a'); s.put(16, 20, 'u')
    # pauldrons: two heavy slabs each, square corners (only the outer ones are knocked off), a rock ridge on top
    for (x, y, w, h) in ((3, 7, 9, 7), (4, 14, 8, 6)):
        bev(s, x, y, w, h, 'W', 'E', 'D', cham=False)
        s.erase(x, y); s.erase(x, y + h - 1)
    for (x, y, w, h) in ((21, 7, 9, 7), (21, 14, 8, 6)):
        bev(s, x, y, w, h, 'W', 'E', 'D', cham=False)
        s.erase(x + w - 1, y); s.erase(x + w - 1, y + h - 1)
    s.hline(5, 6, 3, 'E'); s.hline(23, 6, 3, 'E'); s.put(5, 6, 'W'); s.put(23, 6, 'W')       # ridge on each shoulder
    # top-left edge highlights
    for (x, y) in ((4, 8), (4, 9), (5, 8), (5, 7), (6, 7), (22, 8), (22, 9), (23, 8), (24, 7)): s.put(x, y, 'S')
    # crystal veins across the plates (asymmetric, like real rock)
    for (x, y, c) in ((6, 9, 'c'), (7, 10, 'c'), (8, 10, 'b'), (9, 11, 'b'), (7, 16, 'c'), (8, 17, 'b'),
                      (25, 9, 'b'), (24, 10, 'c'), (26, 11, 'c'), (27, 12, 'b'), (24, 17, 'c'), (25, 17, 'b')):
        s.put(x, y, c)
    s.put(5, 9, 'H'); s.put(26, 9, 'H')
    for (x, y) in ((9, 8), (10, 12), (6, 15), (6, 18), (26, 15), (28, 17), (27, 8), (25, 13)): s.put(x, y, 'D')   # cracks
    s.hline(4, 14, 8, 'D'); s.hline(21, 14, 8, 'D')                  # plate seam
    # brass strap buckles
    s.put(11, 12, 'a'); s.put(21, 12, 'a')
    return s

# ---------------------------------------------------------------- heads (small, sunk between the pauldron walls; no helmet)
def head_base():
    s = Spr(N, N)
    for (x, y) in ((12, 10), (12, 11), (12, 12), (12, 13), (12, 14), (12, 15), (20, 10), (20, 11), (20, 12), (20, 13), (20, 14), (20, 15)):
        s.put(x, y, 'D')                                                # stone collar slabs either side of the head
    s.hline(13, 17, 7, 'D'); s.put(12, 16, 'D'); s.put(20, 16, 'D')     # neck seat behind
    s.hline(14, 9, 5, 'S')                                              # rounded front
    s.rect(13, 10, 7, 7, 'S')
    s.erase(13, 16); s.erase(19, 16)
    return s
def head_shade(s):
    n = s.copy()
    for y in range(9, 17):
        for x in range(13, 20):
            if s.g[y][x] != 'S': continue
            if s.get(x, y + 1) in 'D.' or s.get(x + 1, y) in 'D.': n.g[y][x] = 'W'
            elif s.get(x, y - 1) in 'D.' or s.get(x - 1, y) in 'D.': n.g[y][x] = 'M'
    return n
def head_rock_a():
    s = head_shade(head_base())
    s.hline(14, 10, 5, 'W')                                             # heavy brow
    s.put(15, 11, 'c'); s.put(18, 11, 'c')                              # crystal eyes
    for (x, y) in ((16, 13), (17, 14), (17, 15)): s.put(x, y, 'E')      # crack down the crown
    s.put(14, 12, 'M'); s.put(15, 14, 'b'); s.put(14, 15, 'c')
    return s
def head_rock_b():
    s = head_shade(head_base())
    s.hline(14, 10, 5, 'W')
    s.put(15, 11, 'c'); s.put(18, 11, 'c')
    s.hline(14, 13, 5, 'W'); s.hline(14, 15, 5, 'W')                    # strata bands
    s.hline(14, 14, 5, 'M'); s.hline(14, 12, 4, 'M')
    s.put(18, 14, 'c'); s.put(19, 13, 'b')
    return s

# ---------------------------------------------------------------- arms (thick stone, a lighter tone than the torso so they read, big fists)
def fist(s, x, y):
    s.stamp(x - 2, y - 2, art("""
.SSS.
SSWWE
SWWWE
.EEE.
"""))
    s.hline(x - 1, y + 1, 3, 'E')                                       # finger seam
def wrap(s, x, y):
    s.rect(x - 2, y - 2, 4, 4, 'B'); s.hline(x - 2, y - 2, 4, 'A'); s.hline(x - 2, y + 1, 4, 'C')
def arm(s, x0, y0, x1, y1):
    brush(s, x0, y0, x1, y1, 4, 'W')
def stone_arm_shade(s): return shade_stone(s, 'W', 'S', 'E')
def arms_spr(pose):
    s = Spr(N, N)
    A = HANDS.get(pose)
    if pose == 'unarmed':
        for cx in (1, 28):
            s.rect(cx, 11, 4, 9, 'W')
        s = stone_arm_shade(s)
        for cx in (1, 28):
            s.hline(cx, 15, 4, 'B'); s.hline(cx, 16, 4, 'C'); s.hline(cx, 14, 4, 'A')   # wrist wrap
        fist(s, 3, 22); fist(s, 29, 22)
        s.put(2, 12, 'c'); s.put(30, 13, 'c')
        return s
    S = {'pistol': [(27, 12, 19, 7), (5, 12, 13, 7)], 'rifle': [(27, 12, 22, 10), (5, 12, 16, 3)],
         'tool': [(27, 12, 22, 6), (5, 12, 12, 10)], 'heavy': [(27, 13, 22, 12), (5, 13, 14, 4)],
         'melee': [(27, 12, 24, 9), (5, 12, 12, 8)]}[pose]
    for (a, b, c, d) in S: arm(s, a, b, c, d)
    s = stone_arm_shade(s)
    for (a, b, c, d) in S:                                              # wrist wrap two thirds along each arm
        wrap(s, a + round((c - a) * 0.62), b + round((d - b) * 0.62))
    for k in ('hand_l', 'hand_r'): fist(s, *A[k])
    return s

class Basalt(Species):
    id = 'basalt'
    walk_fps = 6
    head_names = ['rock_a', 'rock_b']
    notes = ('Basalt: wide blocky stone-plated shoulders (29 px), a small head sunk between them, thick short-stride legs, no helmet '
             'variant (they do not breathe): two rock-pattern heads instead. Crystal veins (c/b/H) carry the optional glow layer. '
             'Outfit mask = harness straps, knee and wrist wraps.')
    def legs(self): return [outlined(leg_frame(*w)) for w in WALK] + [outlined(leg_frame(1, -1))]
    def torso(self): return outlined(torso_spr())
    def arms(self, pose): return outlined(arms_spr(pose))
    def head(self, name): return outlined({'rock_a': head_rock_a, 'rock_b': head_rock_b}[name]())
    def torso_anchors(self): return {'head': [16, 13], 'back': [16, 23], 'shoulder_l': [7, 13], 'shoulder_r': [25, 13]}
    def arm_anchors(self): return pose_anchors((3, 22), (29, 22))
    def torso_glow(self):
        g = new_glow(); t = torso_spr()
        glow_px(g, spr_pts(t, 'cH'), (60, 242, 255), 0.55, 2.6)
        return [g]
    def head_glow(self):
        out = []
        for fn in (head_rock_a, head_rock_b):
            g = new_glow(); glow_px(g, spr_pts(fn(), 'c'), (60, 242, 255), 0.6, 2.4); out.append(g)
        return out
