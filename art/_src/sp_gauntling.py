"""Gauntling: salvage cyborgs, Scrapper outcasts rebuilt after accidents, proud of every part. Deliberately lopsided: the LEFT side is
machine (mismatched steel plates, rust, hazard paint, a hydraulic arm and a piston leg), the RIGHT side is flesh and coverall.
A work-lamp eye (the glow layer), cable dreadlocks down the back, a salvaged battery pack. Outfit = coverall, straps, helmet (tinted)."""
from sp_common import *
from mach import bev
import crew_v2 as cv2

def hazard(s, x, y, w, h, phase=0):
    for j in range(h):
        for i in range(w): s.put(x + i, y + j, 'a' if (i + j + phase) % 3 else 'D')

# ---------------------------------------------------------------- legs: left = a piston leg and a slab foot, right = coverall and a boot
BOOT = cv2.BOOT
SLAB = {
 'plant': art("""
.WSSW.
WSSSWE
WuuSWE
WSSEEE
EEEEEE
.EEEE.
"""),
 'lift': art("""
.WSSW.
WSSSWE
WSSSWE
WuuSWE
WSSEEE
EEEEEE
.EEEE.
"""),
}
LEG_X = cv2.LEG_X
def leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift, side in ((LEG_X[0], dl, lift_l, -1), (LEG_X[1], dr, lift_r, 1)):
        fy = 15 - d
        step = -1 if fy < 15 else 1
        ys = list(range(15, fy + step, step))
        if side < 0:                                                      # the machine leg
            s.stamp(lx - 1, 13, art("""
WSSW
SSSE
EEEE
"""))
            for i, y in enumerate(ys):
                if i < len(ys) // 2:
                    s.hline(lx - 1, y, 4, 'S'); s.put(lx - 1, y, 'M'); s.put(lx + 2, y, 'W')
                else:
                    s.hline(lx, y, 3, 'S'); s.put(lx, y, 'M'); s.put(lx + 2, y, 'W'); s.put(lx + 1, y, 'L' if i % 3 else 'S')      # a piston rod
            if len(ys) > 5:
                ky = ys[len(ys) // 2]
                s.hline(lx - 1, ky, 4, 'W'); s.put(lx - 1, ky, 'M'); s.put(lx, ky, 'H')                                            # knee joint
                wy = ys[len(ys) * 3 // 4]; s.hline(lx, wy, 3, 'a'); s.put(lx + 2, wy, 'u')                                         # an amber stripe
            b = SLAB['lift' if lift else 'plant']
            s.stamp(lx - 1, fy - len(b) // 2, b)
        else:                                                              # the flesh leg
            s.stamp(lx, 13, art("""
BBBB
BBBB
CCCC
"""))
            for i, y in enumerate(ys):
                if i < len(ys) // 2:
                    s.put(lx, y, 'A'); s.put(lx + 1, y, 'B'); s.put(lx + 2, y, 'B'); s.put(lx + 3, y, 'C')
                else:
                    s.put(lx, y, 'A'); s.put(lx + 1, y, 'B'); s.put(lx + 2, y, 'C')
            if len(ys) > 5:
                ky = ys[len(ys) // 2]
                s.put(lx, ky, 'L'); s.put(lx + 1, ky, 'A'); s.put(lx + 2, ky, 'u')                                                  # a patch on the knee
            b = BOOT['lift' if lift else 'plant']
            s.stamp(lx, fy - len(b) // 2, b)
    return s

WALK = cv2.WALK

# ---------------------------------------------------------------- torso: machine shoulder and chest plate, coverall, a battery pack
PACK = art("""
.SSSSSSSS.
SMLSSSSSSW
SSWDDDDWSE
SDgWaWrWDE
SSWDDDDWSE
WSSSSSSSSE
.WEEEEEEE.
""")
def torso_spr():
    s = Spr(N, N)
    # battery pack on the back (under the body), a rust weld along its top and an exhaust pipe on the right
    s.stamp(11, 22, PACK)
    for x in (12, 13, 16, 17): s.put(x, 22, 'u')
    s.stamp(22, 23, art("""
MS
SW
SW
"""))
    s.put(22, 22, 'o'); s.put(23, 22, 'u')
    # the coverall half (right): the human body outline, light panels and rivets
    body = cv2.body()
    for j in range(body.h):
        for i in range(body.w):
            c = body.g[j][i]
            if c != '.': s.put(6 + i, 10 + j, c)
    # the machine half (left): a pauldron slab and a mismatched chest plate with hazard paint
    for j in range(12):
        for i in range(0, 11):
            if body.g[j][i] != '.': s.erase(6 + i, 10 + j)
    bev(s, 6, 10, 10, 7, 'M', 'S', 'W')
    bev(s, 7, 17, 9, 5, 'S', 'E', 'D')
    hazard(s, 8, 19, 7, 2)
    for (x, y) in ((8, 11), (13, 11), (8, 15), (13, 15)): s.put(x, y, 'L')                           # rivets
    s.put(7, 11, 'H'); s.put(8, 12, 'M')
    for (x, y) in ((9, 14), (10, 14), (9, 15), (10, 15), (11, 15)): s.put(x, y, 'u')                 # rust bloom on the pauldron
    s.put(11, 14, 'q'); s.put(8, 14, 'q')
    s.stamp(7, 2, art("""
DDD
MSW
MSW
LSW
MSW
aaa
MSW
"""))                                                                                                   # a salvaged smokestack bolted to the pauldron: the lopsided silhouette
    s.put(8, 2, 'u'); s.put(7, 3, 'L')
    s.vline(16, 10, 12, 'E')                                                                         # the seam between machine and flesh
    for y in (11, 14, 17, 20): s.put(16, y, 'L')
    # coverall strap across the machine side, and the flesh shoulder cap
    for i in range(5): s.put(12 + i, 12 + i, 'B'); s.put(11 + i, 12 + i, 'A')
    return s

# ---------------------------------------------------------------- heads: a lamp eye, cable dreadlocks
LOCKS = [  # (x, length, insulation colour): mostly dark cable with a coloured band, a metal ferrule on the end
    (11, 5, 'a'), (13, 8, 'r'), (15, 10, 'b'), (17, 9, 'u'), (19, 7, 'r'), (21, 4, 'b'),
]
def dreadlocks(s, y0=17):
    for (x, ln, c) in LOCKS:
        for j in range(ln):
            s.put(x, y0 + j, c if j % 4 in (2, 3) else 'E')
        s.put(x, y0 + ln, 'M')                                                                       # ferrule on the end
    s.put(15, y0 + 11, 'g')                                                                           # one LED left on at a tip
def head_lamp():
    s = Spr(N, N)
    dreadlocks(s, 17)
    s.stamp(12, 10, art("""
..SSSss..
.MSSSsss.
MLWWWsvvs
MSWoWsvvv
SSWWWsvvv
SSSSssvvv
.SSEssvv.
..EEssv..
...EEs...
"""))
    s.put(14, 13, 'y'); s.put(14, 12, 'H')                                                           # the lamp lens: a lit ring in the faceplate
    s.hline(12, 12, 1, 'L')
    s.put(18, 12, 'n'); s.put(19, 12, 'n')                                                           # the flesh eye, a squint
    s.put(16, 10, 'q'); s.put(17, 10, 'q'); s.put(18, 10, 'q'); s.put(19, 11, 'q')                   # stubble of hair
    return s
HELMET = art("""
..DDDDD..
.AAABBBC.
AHHAABBBC
AHAAABBBC
DDDDDDDDD
AAABBBBCC
.ABBBBCC.
..CCCCC..
""")
def head_helmet():
    s = Spr(N, N)
    dreadlocks(s, 17)
    s.stamp(12, 10, HELMET)
    s.stamp(13, 13, art("""
WSW
SyS
WSW
"""))                                                                                                 # a headlamp bolted to the brim
    s.put(14, 14, 'H'); s.put(13, 13, 'M')
    s.put(18, 15, 'n'); s.put(19, 15, 'n')
    return s

# ---------------------------------------------------------------- arms: left = hydraulic, right = flesh
def mech_arm(s, x0, y0, x1, y1):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    t = Spr(N, N)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(4):
            for k in range(4): t.put(x - 2 + k, y - 2 + j, 'S')
    t = shade_gen(t, 'S', 'M', 'W')
    for i in range(n + 1):                                                                           # hydraulic line and joint rings
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        if i % 4 == 2: t.put(x, y, 'L')
        if i in (n // 3, 2 * n // 3):
            for j in range(4):
                for k in range(4):
                    if t.get(x - 2 + k, y - 2 + j) != '.': t.put(x - 2 + k, y - 2 + j, 'E')
            t.put(x, y, 'u')
    for y in range(N):
        for x in range(N):
            if t.g[y][x] != '.': s.g[y][x] = t.g[y][x]
def flesh_arm(s, x0, y0, x1, y1):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    t = Spr(N, N)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(3):
            for k in range(3): t.put(x - 1 + k, y - 1 + j, 'B' if i < n * 0.45 else 's')
    for y in range(N):                                                                               # sleeve shade, skin shade
        for x in range(N):
            if t.g[y][x] == 'B' and (t.get(x, y + 1) == '.' or t.get(x + 1, y) == '.'): t.g[y][x] = 'C'
            elif t.g[y][x] == 'B' and (t.get(x, y - 1) == '.' or t.get(x - 1, y) == '.'): t.g[y][x] = 'A'
            elif t.g[y][x] == 's' and (t.get(x, y + 1) == '.' or t.get(x + 1, y) == '.'): t.g[y][x] = 'v'
    for y in range(N):
        for x in range(N):
            if t.g[y][x] != '.': s.g[y][x] = t.g[y][x]
    i = int(n * 0.72)
    x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
    s.rect(x - 1, y - 1, 3, 2, 'a'); s.hline(x - 1, y + 1, 3, 'u')                                  # an amber wristband
def clamp(s, x, y):
    """the machine hand: a four-finger clamp."""
    s.rect(x - 2, y - 2, 4, 4, 'M'); s.vline(x + 1, y - 2, 4, 'W'); s.hline(x - 2, y + 1, 4, 'W')
    s.put(x - 2, y - 2, 'L'); s.put(x - 1, y - 3, 'W'); s.put(x + 1, y - 3, 'W'); s.put(x - 1, y - 2, 'D'); s.put(x + 1, y - 2, 'D')
    s.put(x - 1, y - 1, 'S')
def fist(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 's'); s.put(x + 1, y + 1, 'v'); s.put(x - 1, y - 1, 's'); s.put(x, y + 1, 'v')
def arms_spr(pose):
    s = Spr(N, N)
    A = HANDS.get(pose)
    if pose == 'unarmed':
        mech_arm(s, 6, 12, 4, 19)
        flesh_arm(s, 26, 12, 28, 19)
        clamp(s, 4, 21); fist(s, 28, 21)
        return s
    L = {'pistol': (7, 12, 14, 5), 'rifle': (7, 12, 17, 1), 'tool': (7, 12, 13, 9), 'heavy': (7, 12, 14, 3), 'melee': (7, 12, 12, 7)}[pose]
    R = {'pistol': (25, 12, 18, 5), 'rifle': (25, 12, 21, 9), 'tool': (25, 12, 21, 4), 'heavy': (25, 12, 21, 12), 'melee': (25, 12, 23, 8)}[pose]
    mech_arm(s, *L); flesh_arm(s, *R)
    clamp(s, *A['hand_l']); fist(s, *A['hand_r'])
    return s

# ---------------------------------------------------------------- glow: the lamp eye, a few lit LEDs
def lamp_glow(helmet):
    g = new_glow()
    ly = 14 if helmet else 13
    glow_px_max(g, [(14, ly)], (255, 210, 58), 0.7, 4.2, 1.5)
    glow_px_max(g, [(14, ly)], (244, 246, 248), 0.45, 1.8, 1.2)
    glow_px_max(g, [(15, 28)], (107, 211, 74), 0.6, 2.0)                                                 # the LED on a lock
    return g
def led_glow():
    g = new_glow()
    glow_px_max(g, [(13, 25)], (107, 211, 74), 0.7, 2.4)
    glow_px_max(g, [(17, 25)], (224, 65, 59), 0.7, 2.4)
    glow_px_max(g, [(15, 25)], (225, 161, 54), 0.6, 2.0)
    glow_px_max(g, [(22, 22)], (255, 138, 30), 0.5, 2.2)
    return g

class Gauntling(Species):
    id = 'gauntling'
    walk_fps = 8
    head_names = ['lamp', 'helmet']
    notes = ('Gauntling: salvage cyborgs, lopsided on purpose. The LEFT side (the character\'s left, image left at rotation 0) is machine: mismatched '
             'plates with rust and hazard paint, a hydraulic arm with a four-finger clamp, a piston leg and a slab foot; the RIGHT side is flesh and '
             'coverall. A work-lamp eye (head_glow), cable dreadlocks down the back, a battery pack with three lit LEDs (torso_glow). '
             'Head variants: lamp (faceplate, lamp eye), helmet (a hardhat with a headlamp, tinted). Outfit mask = coverall, straps, trouser leg, sleeve, helmet.')
    def legs(self): return [outlined(leg_frame(*w)) for w in WALK] + [outlined(leg_frame(1, -1))]
    def torso(self): return outlined(torso_spr())
    def arms(self, pose): return outlined(arms_spr(pose))
    def head(self, name): return outlined({'lamp': head_lamp, 'helmet': head_helmet}[name]())
    def torso_anchors(self): return {'head': [16, 14], 'back': [16, 24], 'shoulder_l': [8, 14], 'shoulder_r': [24, 14]}
    def arm_anchors(self): return pose_anchors((4, 21), (28, 21))
    def torso_glow(self): return [led_glow()]
    def head_glow(self): return [lamp_glow(False), lamp_glow(True)]
