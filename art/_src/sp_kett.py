"""Kett: insectoid hive-workers, stranded fragments working the Scrapper docks. Amber chitin (y/a/u, seams n, joints q/Q), a domed
chitin shell on the back (split elytra with a welded scrap patch), FOUR thin arms (the upper pair holds items at the shared hand
targets, the lower pair is small and tucked against the chest), antennae, compound eyes as dark glossy blobs. Outfit = a tool belt,
shoulder straps, bracers and knee bands (tinted)."""
from sp_common import *

# ---------------------------------------------------------------- legs: thin chitin bent outward at a spurred knee (insect legs), claw feet
FOOT = {
 'plant': art("""
n.nn
aaau
.aau
.unu
"""),
 'lift': art("""
n.nn
aaau
.aau
.aua
.unu
"""),
}
HIP = (11, 21)
def seg(s, x0, y0, x1, y1, w=2, c='a'):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(w):
            for k in range(w): s.put(x - w // 2 + k, y - w // 2 + j, c)
def leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for hx, d, lift, side in ((HIP[0], dl, lift_l, -1), (HIP[1], dr, lift_r, 1)):
        fy = 15 - d
        far = abs(d)
        fx = hx + side * (1 if far > 4 else 0)                                                    # the foot toes out a little
        leg = Spr(N, N)
        seg(leg, hx, 15, fx, fy, 2)
        leg = shade_gen(leg, 'a', 'y', 'u')
        for y in range(N):
            for x in range(N):
                if leg.g[y][x] != '.': s.g[y][x] = leg.g[y][x]
        if far > 4:
            ky = (15 + fy) // 2
            ox = hx + (-2 if side < 0 else 2)
            s.put(ox, ky, 'u'); s.put(ox + side, ky + (1 if fy > 15 else -1), 'n')               # a spurred knee
            wy = ky + (3 if fy > 15 else -3)
            s.put(fx, wy, 'B'); s.put(fx + 1, wy, 'C')                                            # shin wrap (outfit)
        b = FOOT['lift' if lift else 'plant']
        s.stamp(fx - 1, fy - len(b) // 2 - (1 if fy < 15 else 0), b)
    return s

WALK = [(13, -13, False, False), (7, -7, False, True), (-7, 7, False, True),
        (-13, 13, False, False), (-7, 7, True, False), (7, -7, True, False)]

# ---------------------------------------------------------------- torso: thorax, harness, the domed shell
THORAX = [(14, 18), (12, 20), (11, 21), (10, 22), (10, 22), (10, 22), (10, 22), (11, 21)]            # y 8..15
SHELL = [(9, 23), (8, 24), (8, 24), (8, 24), (8, 24), (8, 24), (8, 24), (9, 23), (10, 22), (11, 21), (13, 19), (14, 18), (15, 17)]   # y 16..28 (a pointed abdomen)
def half(rows, y0, side):
    """one elytron: the shell spans cut at the seam (x=16)."""
    s = Spr(N, N)
    for j, (x0, x1) in enumerate(rows):
        a, b = (x0, 15) if side < 0 else (17, x1)
        if b >= a: s.hline(a, y0 + j, b - a + 1, 'u')
    return shade_gen(s, 'u', 'a', 'q')
def torso_spr():
    s = Spr(N, N)
    for side in (-1, 1):
        h = half(SHELL, 16, side)
        for y in range(N):
            for x in range(N):
                if h.g[y][x] != '.': s.g[y][x] = h.g[y][x]
    for y in range(16, 29): s.put(16, y, 'n')                                                         # the seam
    for (x, y) in ((15, 18), (15, 19), (15, 20), (17, 18), (17, 19), (17, 20)): s.put(x, y, 'a')       # lit shoulders of the seam
    for (x, y) in ((11, 20), (12, 20), (13, 20), (14, 20), (18, 20), (19, 20), (20, 20), (21, 20),   # segment ridges (a darker brown groove)
                   (10, 23), (11, 23), (12, 23), (13, 24), (19, 24), (20, 23), (21, 23), (22, 23)):
        s.put(x, y, 'q')
    for (x, y) in ((11, 21), (12, 21), (13, 21), (21, 24), (22, 24)): s.put(x, y, 'Q')
    for (x, y) in ((9, 18), (10, 17), (10, 18), (9, 19)): s.put(x, y, 'a')                            # lit edges of the dome
    s.put(11, 18, 'y'); s.put(10, 17, 'y'); s.put(12, 18, 'a')
    for (x, y) in ((14, 25), (18, 25), (15, 22), (17, 22)): s.put(x, y, 'n')                          # vent holes
    # a welded scrap patch on the right elytron: steel plate, two bolts, a weld seam in amber
    s.stamp(19, 17, art("""
MMMM
MSSW
SSWW
"""))
    s.put(19, 17, 'H'); s.put(22, 19, 'L'); s.put(18, 18, 'a'); s.put(18, 19, 'a'); s.put(19, 20, 'a'); s.put(20, 20, 'a')
    # thorax
    for j, (x0, x1) in enumerate(THORAX): s.hline(x0, 8 + j, x1 - x0 + 1, 'a')
    t = shade_gen(s, 'a', 'y', 'u')
    for y in range(8, 16):
        for x in range(N): s.g[y][x] = t.g[y][x]
    for (x, y) in ((10, 11), (22, 11), (10, 14), (22, 14)): s.put(x, y, 'u')                         # shoulder sockets for the four arms
    for (x, y) in ((11, 11), (11, 14), (21, 11), (21, 14)): s.put(x, y, 'n')
    # tool belt at the waist, and straps from the shoulders to it (outfit)
    s.hline(9, 15, 15, 'B'); s.hline(9, 16, 15, 'C'); s.hline(9, 14, 15, 'A')
    s.put(8, 15, 'C'); s.put(24, 15, 'C')
    s.rect(15, 14, 3, 3, 'M'); s.put(15, 14, 'L'); s.put(17, 16, 'W'); s.put(16, 15, 'D')           # steel buckle
    for i in range(4):
        s.put(12 + i, 11 + i, 'B'); s.put(20 - i, 11 + i, 'B')
        s.put(11 + i, 11 + i, 'A'); s.put(21 - i, 11 + i, 'C')
    return s

# ---------------------------------------------------------------- heads: antennae, compound eyes
HEAD = art("""
....uau....
...uaaau...
.EDaaaaaDE.
DDDayaayDDD
DLDaaaaaDLD
.DDuaaauDD.
...uaaau...
....uuu....
""")
def head_base():
    s = Spr(N, N)
    s.stamp(11, 9, HEAD)
    s.put(15, 10, 'n'); s.put(17, 10, 'n')                                                       # antenna roots
    s.put(16, 11, 'u'); s.put(16, 12, 'n'); s.put(16, 13, 'u')                                   # suture
    return s
def antennae(s, torn=False):
    for side in (-1, 1):
        pts = [(15, 9), (14, 8), (13, 7), (12, 6), (11, 5), (10, 4), (9, 3), (9, 2)] if not torn or side > 0 else [(15, 9), (14, 8), (13, 7), (12, 7), (12, 6)]
        for (x, y) in pts:
            s.put(x if side < 0 else 2 * C - x, y, 'u')
        if not torn or side > 0:
            tx = 9 if side < 0 else 23
            s.put(tx, 1, 'y'); s.put(tx, 2, 'a'); s.put(tx + (1 if side < 0 else -1), 1, 'a')
    return s
def head_antennae(): return antennae(head_base())
def head_torn(): return antennae(head_base(), torn=True)
HARDHAT = art("""
..BBBBB..
.ABBBBBC.
AABBBBBCC
ADDDDDDDC
AAABBBCCC
.ABBBBBC.
..CCCCC..
""")
def head_helmet():
    s = Spr(N, N)
    s.stamp(12, 10, HARDHAT)
    s.put(12, 13, 'D'); s.put(20, 13, 'D')
    s.put(13, 13, 'M'); s.put(19, 13, 'M')                                                        # visor glints (the eyes behind the strip)
    s.put(14, 10, 'H'); s.put(13, 11, 'H')
    s.put(16, 9, 'S'); s.put(16, 10, 'M')                                                        # lamp bracket
    for side in (-1, 1):                                                                         # antennae come through two slots
        for (x, y) in ((14, 9), (13, 8), (12, 7), (11, 6), (10, 5), (9, 4), (9, 3), (9, 2)):
            s.put(x if side < 0 else 2 * C - x, y, 'u')
        s.put(9 if side < 0 else 23, 1, 'y'); s.put(9 if side < 0 else 23, 2, 'a')
    return s

# ---------------------------------------------------------------- arms: four of them
def limb(s, x0, y0, x1, y1, base='a', hi='y', lo='u', w=2):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    t = Spr(N, N)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(w):
            for k in range(w): t.put(x - 1 + k, y - 1 + j, base)
    t = shade_gen(t, base, hi, lo)
    for y in range(N):
        for x in range(N):
            if t.g[y][x] != '.': s.g[y][x] = t.g[y][x]
    return n
def bracer(s, x0, y0, x1, y1, at=0.64):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(int(n * at), int(n * at) + 2):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(2):
            for k in range(2): s.put(x - 1 + k, y - 1 + j, 'B')
def claw(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 'a'); s.put(x + 1, y + 1, 'u'); s.put(x, y + 1, 'u'); s.put(x - 1, y - 1, 'y')
    s.put(x - 1, y - 2, 'n'); s.put(x + 1, y - 2, 'n')                                           # two pincer tips, forward
def tucked(s):
    """the small lower pair: folded against the chest, hands crossed under the head. Same in every pose."""
    for side in (-1, 1):
        pts = [(9, 14), (9, 16), (11, 17), (13, 16)]
        for (a, b) in zip(pts, pts[1:]):
            n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
            for i in range(n + 1):
                x = a[0] + round((b[0] - a[0]) * i / n); y = a[1] + round((b[1] - a[1]) * i / n)
                s.put(x if side < 0 else 2 * C - x, y, 'q')
        s.put(9 if side < 0 else 23, 14, 'Q'); s.put(9 if side < 0 else 23, 15, 'Q')
        hx = 14 if side < 0 else 18
        s.put(hx, 16, 'Q'); s.put(hx, 17, 'n'); s.put(hx + (1 if side < 0 else -1), 17, 'n')
def arms_spr(pose):
    s = Spr(N, N)
    A = HANDS.get(pose)
    SH = ((10, 12), (22, 12))
    if pose == 'unarmed':
        for (sx, sy), ex in zip(SH, (6, 26)):
            limb(s, sx, sy, ex, 13); limb(s, ex, 13, ex, 19)
            s.put(ex + (-1 if ex < 16 else 1), 13, 'u')                                          # elbow spike
        bracer(s, 6, 13, 6, 19); bracer(s, 26, 13, 26, 19)
        tucked(s)
        claw(s, 6, 21); claw(s, 26, 21)
        return s
    ends = {'pistol': [(10, 12, 14, 5), (22, 12, 18, 5)], 'rifle': [(22, 12, 21, 9), (10, 12, 17, 1)],
            'tool': [(22, 12, 21, 4), (10, 12, 13, 9)], 'heavy': [(22, 12, 21, 12), (10, 12, 14, 3)],
            'melee': [(22, 12, 23, 8), (10, 12, 12, 7)]}[pose]
    for (a, b, c, d) in ends: limb(s, a, b, c, d); bracer(s, a, b, c, d)
    tucked(s)
    for k in ('hand_l', 'hand_r'): claw(s, *A[k])
    return s

class Kett(Species):
    id = 'kett'
    walk_fps = 9
    head_names = ['antennae', 'torn', 'helmet']
    notes = ('Kett: insectoid hive-workers. Amber chitin, a split domed shell on the back with a welded scrap patch, FOUR thin arms '
             '(the upper two hold items at the shared hand targets; the lower two are small and stay tucked against the chest in every pose), '
             'antennae and two glossy dark compound eyes, thin legs with a long stride. Head variants: antennae, torn (one antenna snapped), '
             'helmet (a work hardhat, tinted, antennae through slots). Outfit mask = tool belt, shoulder straps, bracers, shin wraps, hardhat.')
    def legs(self): return [outlined(leg_frame(*w)) for w in WALK] + [outlined(leg_frame(1, -1))]
    def torso(self): return outlined(torso_spr())
    def arms(self, pose): return outlined(arms_spr(pose))
    def head(self, name): return outlined({'antennae': head_antennae, 'torn': head_torn, 'helmet': head_helmet}[name]())
    def torso_anchors(self): return {'head': [16, 13], 'back': [16, 23], 'shoulder_l': [10, 12], 'shoulder_r': [22, 12]}
    def arm_anchors(self): return pose_anchors((6, 21), (26, 21))
