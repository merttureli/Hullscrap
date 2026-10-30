"""Top-down layered human, v2. Every layer faces UP (rotation 0) on a 33x33 frame, centre pixel (16,16).
Draw order: legs (rotate to MOVE dir), torso, arms, item, head (rotate to AIM dir).
Outfit symbols A/B/C = light/base/dark: neutral greys in the base PNG, white in the _color mask."""
import math
from px import *
from mach import outline_all

N = 33; C = 16
OUTFIT_GREY = {'A': 'L', 'B': 'M', 'C': 'S'}
OUTFIT = set('ABC')
TEAL = (79, 196, 184)
OUTLINE = True

def outlined(s):
    n = s.copy()
    if OUTLINE: outline_all(n)
    return n

def shade_edges(s):
    """'B' pixels get A on top/left-facing edges and C on bottom/right-facing edges (top-left light)."""
    n = s.copy()
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] != 'B': continue
            if s.get(x, y + 1) == '.' or s.get(x + 1, y) == '.': n.g[y][x] = 'C'
            elif s.get(x, y - 1) == '.' or s.get(x - 1, y) == '.': n.g[y][x] = 'A'
    return n

# ================================================================== LEGS
BOOT = {
 'plant': art("""
.QQ.
QQqq
qqqq
qqqn
qqnn
.nn.
"""),
 'lift': art("""
.QQ.
QQQq
QQqq
qqqq
qqqn
qqnn
.nn.
"""),
}
LEG_X = (10, 20)          # left edge of each 3-wide shin strip; thighs are 4 wide, boots sit one px further out
def leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift, side in ((LEG_X[0], dl, lift_l, -1), (LEG_X[1], dr, lift_r, 1)):
        fy = 15 - d                                      # boot centre row (forward = up)
        s.stamp(lx - (1 if side < 0 else 0), 13, art("""
BBBB
BBBB
CCCC
"""))                                                    # hip stub (under the torso)
        step = -1 if fy < 15 else 1
        ys = list(range(15, fy + step, step))
        for i, y in enumerate(ys):
            near_hip = i < len(ys) // 2
            if near_hip:                                 # thigh, 4 wide, flaring outward
                x0 = lx - 1 if side < 0 else lx
                s.put(x0, y, 'A'); s.put(x0 + 1, y, 'B'); s.put(x0 + 2, y, 'B'); s.put(x0 + 3, y, 'C')
            else:                                        # shin, 3 wide
                s.put(lx, y, 'A'); s.put(lx + 1, y, 'B'); s.put(lx + 2, y, 'C')
        if len(ys) > 5:                                  # knee pad
            ky = ys[len(ys) // 2]
            s.put(lx, ky, 'L'); s.put(lx + 1, ky, 'A')
        b = BOOT['lift' if lift else 'plant']
        bx = lx - 1 if side < 0 else lx
        s.stamp(bx, fy - len(b) // 2, b)
    return s

# 6-frame cycle (left foot offset; the right foot mirrors it). Frames 1-2: right leg swings (lifted), 4-5: left leg.
WALK = [(11, -11, False, False), (6, -6, False, True), (-6, 6, False, True),
        (-11, 11, False, False), (-6, 6, True, False), (6, -6, True, False)]
def legs():
    return [outlined(leg_frame(*w)) for w in WALK] + [outlined(leg_frame(1, -1))]

# ================================================================== TORSO (shoulder plates, chest, backpack)
SPANS = [(4, 16), (2, 18), (1, 19), (0, 20), (0, 20), (0, 20), (0, 20), (1, 19), (2, 18), (3, 17), (5, 15), (7, 13)]
def body():
    s = Spr(21, 12)
    for j, (x0, x1) in enumerate(SPANS): s.hline(x0, j, x1 - x0 + 1, 'B')
    s = shade_edges(s)
    for j in range(1, 11):                               # darker chest between the plates
        for x in range(6, 15):
            if s.g[j][x] != '.': s.g[j][x] = 'C'
    for j in range(1, 11):                               # plate seams
        s.put(5, j, 'E'); s.put(15, j, 'E')
    for (x, y) in ((2, 4), (2, 7), (18, 4), (18, 7)): s.put(x, y, 'L')      # rivets
    for (x, y) in ((1, 3), (2, 3), (1, 4)): s.put(x, y, 'H')                # plate glint (stays white)
    for x in range(8, 13): s.put(x, 10, 'B')
    return s
PACK = art("""
.MMMMMMM.
MLSSSSSSW
MSEEEEESW
MSEgEaESW
MSEEEEESW
WSSSSSSSE
.WEEEEEE.
""")
STRAPS = [(9, 10), (9, 11), (23, 10), (23, 11)]
def torso():
    s = Spr(N, N)
    s.stamp(12, 21, PACK)
    s.stamp(6, 10, body().rows())
    for (x, y) in STRAPS: s.put(x, y, 'q')               # pack straps over the shoulders
    return outlined(s)

# ================================================================== HEADS (strip: hair, helmet). Same 33x33 frame, centre (16,14)
HAIR = art("""
..sssss..
.qqqvnnn.
qQqqvnnnn
sqqqvnnnv
sqqqqvnnv
qqqqqvnnn
.qqqnnnn.
..qnnnn..
...nnn...
""")
HELMET = art("""
..DDcDD..
.EDcDDDE.
AHHAAEBBC
AHAAAEBBC
AAAABEBBC
AAABBEBCC
.ABBBECC.
..BBBEC..
...CCC...
""")
HEADS = ['hair', 'helmet']
def head(kind):
    s = Spr(N, N)
    s.stamp(12, 10, HAIR if kind == 'hair' else HELMET)
    return outlined(s)

# ================================================================== ARMS (poses)
def brush(s, x0, y0, x1, y1, w=3, c='B'):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(w):
            for k in range(w): s.put(x - w // 2 + k, y - w // 2 + j, c)
def hand(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 's'); s.put(x + 1, y + 1, 'v')
POSES = ['unarmed', 'pistol', 'rifle', 'tool', 'heavy', 'melee']
# anchors relative to the frame's top-left (centre pixel = (16,16)). mount = where the item's grip goes.
ARM = {
 'unarmed': dict(hand_l=(5, 19), hand_r=(27, 19), mount=None),
 'pistol':  dict(hand_l=(14, 5), hand_r=(18, 5), mount=(16, 5)),
 'rifle':   dict(hand_l=(17, 1), hand_r=(21, 9), mount=(20, 8)),
 'tool':    dict(hand_l=(13, 9), hand_r=(21, 4), mount=(21, 4)),
 # new classes (art-species): shared by every species so any item fits any body
 'heavy':   dict(hand_l=(14, 3), hand_r=(21, 12), mount=(19, 11)),     # big gun braced at the hip, left hand forward on the barrel
 'melee':   dict(hand_l=(12, 7), hand_r=(23, 8), mount=(23, 8)),       # weapon held out front-right, left fist up as a guard
}
def arms(pose):
    s = Spr(N, N)
    a = ARM[pose]
    if pose == 'unarmed':                                # arms hang along the sides, hands by the hips
        for cx in (5, 27):
            s.rect(cx - 1, 12, 3, 6, 'B')
    elif pose == 'pistol':                               # both hands meet in front of the chest
        brush(s, 7, 12, 13, 7); brush(s, 25, 12, 19, 7)
    elif pose == 'rifle':                                # right hand on the grip, left reaches the foregrip
        brush(s, 25, 12, 22, 10); brush(s, 7, 12, 16, 3)
    elif pose == 'tool':                                 # tool hand forward, other arm bent across
        brush(s, 25, 12, 22, 6); brush(s, 7, 12, 12, 10)
    elif pose == 'heavy':                                # right hand low on the grip at the hip, left arm reaches along the barrel
        brush(s, 25, 13, 22, 12); brush(s, 7, 13, 14, 4)
    elif pose == 'melee':                                # weapon arm out front-right, left fist raised as a guard
        brush(s, 25, 12, 23, 9); brush(s, 7, 12, 12, 8)
    s = shade_edges(s)
    for k in ('hand_l', 'hand_r'): hand(s, *a[k])
    return outlined(s)

# ================================================================== ITEMS (own sprites, facing up)
ITEM_ART = {
 'pistol': art("""
.E.
WSE
MSW
MSW
LSW
MEW
MSW
MSW
MSW
LSW
qQn
.Qn
"""),
 'rifle': art("""
...E...
..EWE..
..EWE..
..ESE..
..MSW..
..MSW..
..MSW..
..MSW..
..MSW..
..MSW..
..MSW..
.MMSWW.
.MESEW.
.MSSSW.
.MESEW.
.MSSSW.
.MESEW.
.MMSWW.
MLSSSMW
MSESESW
MSSgSSW
MSESESW
MLSSSMW
.WEEEW.
..QQq..
.QQQqn.
.QQqqn.
.QQqqn.
.QQqqn.
.QqqnN.
.qqnnn.
""".replace('N', 'n')),
 'wrench': art("""
MM...WW
MMS.SWW
MSS.SSW
.MSSSW.
..MSW..
..MSW..
..MSW..
..MSW..
..MSW..
..MSW..
..MSW..
..MSW..
..MSW..
..QQq..
..QQq..
..QqN..
..qnN..
""".replace('N', 'n')),
 'extinguisher': art("""
..EW...
...EW..
..KKE..
.MMMS..
.LLMMS.
rrrrrru
rHrrrru
rHrrrru
rrrrrru
rrrrrru
rHrrrru
rrrrrru
rrrrruu
urrrruu
.uuuuu.
"""),
}
# rows (from the top of the interior) where the hand closes, and where the business end is
ITEM_POINTS = {'pistol': dict(grip=9, muzzle=0), 'rifle': dict(grip=25, muzzle=0, foregrip=12),
               'wrench': dict(grip=14, muzzle=0), 'extinguisher': dict(grip=4, muzzle=0)}
def item(name):
    rows = ITEM_ART[name]
    s = Spr(len(rows[0]) + 2, len(rows) + 2)
    s.stamp(1, 1, rows)
    return outlined(s)
def item_anchors(name):
    rows = ITEM_ART[name]; w = len(rows[0]) + 2; cx = w // 2
    p = ITEM_POINTS[name]
    out = {'grip': [cx, p['grip'] + 1], 'muzzle': [cx, p['muzzle']]}
    if name == 'extinguisher': out['muzzle'] = [3, 0]
    if 'foregrip' in p: out['foregrip'] = [cx, p['foregrip'] + 1]
    return out

# ================================================================== helpers for composition
def mask_of(s):
    m = Spr(s.w, s.h)
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] in OUTFIT: m.g[y][x] = 'H'
    return m
def base_of(s): return s.sub(OUTFIT_GREY)
def tinted_rgba(s, tint=TEAL):
    o = Rgba(s.w, s.h)
    for y in range(s.h):
        for x in range(s.w):
            c = s.g[y][x]
            if c == '.': continue
            rgb = tint_mul(RGB[OUTFIT_GREY[c]], tint) if c in OUTFIT else RGB[c]
            o.p[y][x] = list(rgb) + [255]
    return o
