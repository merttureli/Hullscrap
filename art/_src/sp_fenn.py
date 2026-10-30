"""Fenn: slim, quick, clever-handed. Cream/tan fur, LONG SWEPT-BACK EARS (the silhouette), a tool harness with a rack of pouches
and tool handles on the back, quick legs (6-frame walk, long stride)."""
from sp_common import *

# ---------------------------------------------------------------- legs: slim trousers (outfit), brown boots, long stride
BOOT = {
 'plant': art("""
.QQ.
QQqq
qqqn
.nn.
"""),
 'lift': art("""
.QQ.
QQQq
QQqq
qqqn
.nn.
"""),
}
LX = (10, 20)
def leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift, side in ((LX[0], dl, lift_l, -1), (LX[1], dr, lift_r, 1)):
        fy = 15 - d
        s.stamp(lx - (0 if side < 0 else 0), 13, art("""
BBBB
BBBB
CCCC
"""))
        step = -1 if fy < 15 else 1
        ys = list(range(15, fy + step, step))
        for i, y in enumerate(ys):
            near = i < len(ys) // 2
            if near:
                s.put(lx, y, 'A'); s.put(lx + 1, y, 'B'); s.put(lx + 2, y, 'B'); s.put(lx + 3, y, 'C')      # thigh 4
            else:
                s.put(lx + 1, y, 'A'); s.put(lx + 2, y, 'B'); s.put(lx + 3, y, 'C')                        # shin 3
        if len(ys) > 8:
            ky = ys[len(ys) // 2]; s.put(lx + 1, ky, 'L'); s.put(lx + 2, ky, 'A')                          # knee pad
        b = BOOT['lift' if lift else 'plant']
        s.stamp(lx, fy - len(b) // 2, b)
    return s

WALK = [(13, -13, False, False), (7, -7, False, True), (-7, 7, False, True),
        (-13, 13, False, False), (-7, 7, True, False), (7, -7, True, False)]

# ---------------------------------------------------------------- torso: coverall, harness, pouch rack
SPANS = [(12, 20), (10, 22), (10, 22), (10, 22), (10, 22), (11, 21), (11, 21), (12, 20), (12, 20), (12, 20), (13, 19), (13, 19)]
POUCH = art("""
QQQ
qqq
qaq
nnn
""")
def torso_spr():
    s = Spr(N, N)
    for j, (x0, x1) in enumerate(SPANS): s.hline(x0, 11 + j, x1 - x0 + 1, 'B')
    s = shade_edges(s)
    for y in range(12, 22):                                          # seam down the back
        if s.g[y][16] != '.': s.put(16, y, 'C')
    # harness: two leather straps over the shoulders crossing on the back, a belt, a brass ring
    for i in range(9):
        s.put(12 + i, 12 + i, 'q'); s.put(20 - i, 12 + i, 'q')
    s.put(12, 12, 'Q'); s.put(20, 12, 'Q'); s.put(16, 16, 'a'); s.put(15, 16, 'u'); s.put(17, 16, 'u')
    s.hline(10, 21, 13, 'q'); s.hline(10, 20, 13, 'Q')
    # pouch rack on the back, tools poking out
    for x in (9, 13, 17, 21): s.stamp(x, 21, POUCH)
    for (x, y, c) in ((10, 25, 'M'), (10, 26, 'b'), (14, 25, 'M'), (14, 26, 'r'), (14, 27, 'r'),
                      (18, 25, 'a'), (22, 25, 'M'), (22, 26, 'M'), (22, 27, 'y')):
        s.put(x, y, c)
    s.put(19, 25, 'M'); s.put(21, 25, 'S')                              # wire coil bits
    # shoulder stitching / patch
    s.put(11, 14, 'L'); s.put(21, 14, 'L')
    return s

# ---------------------------------------------------------------- heads: fur head, big swept-back ears
HEAD_SPANS = [(16, 16), (15, 17), (14, 18), (13, 19), (13, 19), (13, 19), (13, 19), (14, 18), (14, 18)]
def fur_head():
    s = Spr(N, N)
    for j, (x0, x1) in enumerate(HEAD_SPANS): s.hline(x0, 7 + j, x1 - x0 + 1, 'f')
    s = shade_gen(s, 'f', 'f', 's')
    for (x, y) in ((13, 13), (19, 13), (14, 14), (18, 14)): s.put(x, y, 's')       # tan cheek tufts
    s.put(16, 12, 's'); s.put(16, 13, 's')                                      # a tan stripe over the crown
    s.put(16, 7, 'n'); s.put(15, 8, 's'); s.put(17, 8, 's')                    # nose and muzzle shade
    s.put(14, 10, 'n'); s.put(18, 10, 'n')                                     # eyes (brow line)
    return s
EAR_PATH = [(11, 10, 3), (10, 13, 3), (8, 17, 3), (7, 21, 3), (6, 24, 2), (6, 27, 1)]    # (x centre, y, width) for the LEFT ear
def ear_cells(side):
    cells = {}
    for (a, b) in zip(EAR_PATH, EAR_PATH[1:]):
        n = b[1] - a[1]
        for i in range(n):
            t = i / float(n)
            xc = a[0] + (b[0] - a[0]) * t; w = a[2] + (b[2] - a[2]) * t
            y = a[1] + i
            x0 = int(round(xc - w / 2.0 + 0.5)); x1 = x0 + max(1, int(round(w))) - 1
            for x in range(x0, x1 + 1):
                cells[(x if side < 0 else 2 * C - x, y)] = (i, a[1])
    return cells
def ears(s):
    e = Spr(N, N)
    for side in (-1, 1):
        for (x, y) in ear_cells(side): e.put(x, y, 's')
    e = shade_gen(e, 's', 'f', 'v')
    # pink inner stripe and dark tips
    for side in (-1, 1):
        cells = sorted(ear_cells(side), key=lambda c: c[1])
        rows = {}
        for (x, y) in cells: rows.setdefault(y, []).append(x)
        for y, xs in rows.items():
            xs.sort()
            if 12 <= y <= 24:
                xm = xs[len(xs) // 2] if side < 0 else xs[(len(xs) - 1) // 2]
                if len(xs) >= 3: e.put(xm, y, 'p')
            if y >= 25:
                for x in xs: e.put(x, y, 'n')
    for side in (-1, 1):                                              # shadowed root where the ear meets the head
        for y in (10, 11, 12):
            xs = sorted(x for (x, yy) in ear_cells(side) if yy == y)
            if xs: e.put(xs[-1] if side < 0 else xs[0], y, 'v')
    for y in range(N):
        for x in range(N):
            if e.g[y][x] != '.': s.g[y][x] = e.g[y][x]
def head_ears():
    s = Spr(N, N)
    ears(s)
    h = fur_head()
    for y in range(N):
        for x in range(N):
            if h.g[y][x] != '.': s.g[y][x] = h.g[y][x]
    return s
def head_goggles():
    s = head_ears()
    for cx in (14, 18):                                                         # brass goggles pushed up on the forehead
        s.rect(cx - 1, 11, 3, 3, 'a'); s.put(cx, 12, 'b'); s.put(cx - 1, 11, 'y'); s.put(cx + 1, 13, 'u')
    s.hline(13, 14, 7, 'q')                                                    # strap round the head
    s.put(16, 12, 'q')
    return s
HELM = art("""
..DDDDD..
.AAAAABB.
AHHAAABBC
AHAAAABBC
DDDDDDDDD
AAAAABBBC
AABBBBBCC
.ABBBBCC.
..CCCCC..
""")
def head_helmet():
    s = Spr(N, N)
    # ears fold back flat through slots in the shell: short swept stubs
    for side in (-1, 1):
        for (x, y) in ((11, 13), (10, 14), (10, 15), (9, 16), (9, 17), (8, 18), (8, 19)):
            xx = x if side < 0 else 2 * C - x
            s.put(xx, y, 'f'); s.put(xx + (1 if side < 0 else -1), y, 's')
        s.put(8 if side < 0 else 24, 19, 'n'); s.put(8 if side < 0 else 24, 20, 'n')
    s.stamp(12, 8, HELM)
    s.put(16, 12, 'D'); s.hline(14, 12, 5, 'D')
    s.put(15, 12, 'c'); s.put(17, 12, 'c')                                      # visor glints
    return s

# ---------------------------------------------------------------- arms: slim sleeves, brown wrist strap, fur hands with long fingers
def limb(s, x0, y0, x1, y1):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(2):
            for k in range(2): s.put(x - 1 + k, y - 1 + j, 'B')
    s = shade_edges(s)
    for i in range(int(n * 0.72), int(n * 0.72) + 2):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(2):
            for k in range(2): s.put(x - 1 + k, y - 1 + j, 'q')
    return s
def paw(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 'f'); s.put(x + 1, y + 1, 's'); s.put(x, y + 1, 's'); s.put(x, y - 2, 'f')
def arms_spr(pose):
    s = Spr(N, N)
    A = HANDS.get(pose)
    if pose == 'unarmed':
        for cx in (7, 24):
            s.rect(cx, 12, 2, 8, 'B')
        s = shade_edges(s)
        for cx in (7, 24):
            s.hline(cx, 17, 2, 'q')
        paw(s, 8, 21); paw(s, 25, 21)
        return s
    if pose == 'pistol':   S = [(10, 13, 13, 7), (22, 13, 19, 7)]
    elif pose == 'rifle':  S = [(22, 13, 22, 10), (10, 13, 16, 3)]
    elif pose == 'tool':   S = [(22, 13, 22, 6), (10, 13, 12, 10)]
    elif pose == 'heavy':  S = [(22, 13, 22, 12), (10, 13, 14, 4)]
    elif pose == 'melee':  S = [(22, 13, 24, 9), (10, 13, 12, 8)]
    for (a, b, c, d) in S: s = limb(s, a, b, c, d)
    for k in ('hand_l', 'hand_r'): paw(s, *A[k])
    return s

class Fenn(Species):
    id = 'fenn'
    walk_fps = 10
    head_names = ['ears', 'goggles', 'helmet']
    notes = ('Fenn: slim (13 px shoulders) but with long swept-back ears that stick out past the shoulders (cream fur, pink inner, dark tips), '
             'a tool harness with a rack of pouches and tool handles on the back, quick legs: 6-frame walk with a longer stride, 10 fps. '
             'Outfit mask = coverall (torso, sleeves, trousers) and the helmet shell.')
    def legs(self): return [outlined(leg_frame(*w)) for w in WALK] + [outlined(leg_frame(1, -1))]
    def torso(self): return outlined(torso_spr())
    def arms(self, pose): return outlined(arms_spr(pose))
    def head(self, name): return outlined({'ears': head_ears, 'goggles': head_goggles, 'helmet': head_helmet}[name]())
    def torso_anchors(self): return {'head': [16, 13], 'back': [16, 23], 'shoulder_l': [10, 14], 'shoulder_r': [22, 14]}
    def arm_anchors(self): return pose_anchors((8, 21), (25, 21))
