"""Race wave 4 crew rigs (docs/waves/races_2_4.md), completing the roster at 30: WARDEN_FRAME, MURROW (the large rig), SILTBORN (a floating rig), CORVIN,
BRINE (the large rig), ECHO and FERRO. One module, no new palette colours (every letter already exists; pal_races1 registers the private cyans Y / z).
The layers, animations and item mounts are the shared rig's (see sp_races2.py and art/README.md "Crew"): every layer faces UP at rotation 0 on one frame
(normal 33x33 pivot (16,16); large and floating 49x49 pivot (24,24)); the arms `mount` anchors are the human's moved by pivot - (16,16), so any item fits any body.
Outfit symbols A/B/C = light/base/dark (tint mask); B and C are NOT the neon cyans here, Y and z are (pal_races1).
  * normal: Warden-frame, Corvin, Echo, Ferro;
  * LARGE (49x49, the art overhangs the 2x2 body): Murrow, Brine;
  * FLOATING (49x49, no walk: the legs layer is the trailing tendrils, `float` is played by time): Siltborn."""
import math
from sp_common import *
import pal_races1     # noqa: F401  (registers the private cyan letters Y / z)
from sp_races2 import inside, poly, line, ell, seg, merge, shade, limb, lift, lift_glow, ng, walk_cycle, clear_under
from sp_races2 import FN, FC                                                   # the floating rigs' frame (49) and pivot (24)
from sp_races2 import DN, DC, DSH                                              # the large rig's frame (49), pivot (24) and its mount shift (+8)

def mirror_x(s):
    """a layer drawn for the left half, copied mirrored onto the right half about the pivot column 16 (pixel indices: x -> 32 - x)."""
    o = s.copy()
    for y in range(s.h):
        for x in range(s.w):
            c = s.g[y][x]
            if c != '.' and 0 <= 32 - x < s.w: o.g[y][32 - x] = c
    return o

# ================================================================== WARDEN-FRAME: a rebuilt Lumen drone (standard rig)
# Sleek navy panels (I/J/j) with crisp cyan edge lines (Y / z), a delta chassis that widens to two swept stabiliser fins behind, mechanical limbs (steel joints,
# navy sleeves with a cyan stripe, a two-prong gripper), and ONE lens: a magenta eye in a dark socket set in a smooth dome (head_glow pulses it). It was
# rebuilt: the left pauldron is a mismatched steel plate with rivets and a rust streak. Outfit = the owner's marking: a chest strap, a stripe on each
# pauldron and the cuffs, the helmet's brow plate.
W_FOOT = {
 'plant': art("""
M.M.M
SSSSS
JJYJJ
IJJJI
.III.
"""),
 'lift': art("""
M.M.M
SSSSS
JJYJJ
JJJJI
IJJJI
.III.
"""),
}
def wf_leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift in ((10, dl, lift_l), (22, dr, lift_r)):
        fy = 16 - d
        step = -1 if fy < 16 else 1
        ys = list(range(16, fy + step, step))
        t = Spr(N, N)
        for y in ys: t.hline(lx - 1, y, 3, 'J')
        merge(s, shade_gen(t, 'J', 'j', 'I'))
        for i, y in enumerate(ys):
            if len(ys) > 5 and i > len(ys) // 2 + 1 and i % 2 == 0: s.put(lx, y, 'Y')               # a cyan stripe down the shin
        if len(ys) > 5:
            ky = ys[len(ys) // 2]; s.rect(lx - 1, ky - 1, 3, 3, 'S'); s.put(lx - 1, ky - 1, 'M'); s.put(lx + 1, ky + 1, 'W'); s.put(lx, ky, 'E')    # the knee joint
        b = W_FOOT['lift' if lift else 'plant']
        s.stamp(lx - 2, fy - len(b) // 2 - (1 if fy < 16 else 0), b)
    return s
WF_WALK = walk_cycle(8, 4)

def wf_torso():
    s = Spr(N, N)
    for sd in (-1, 1):                                                                       # the swept stabiliser fins (under the chassis)
        f = Spr(N, N); poly(f, [(16 + sd * 7, 20), (16 + sd * 12, 28), (16 + sd * 9, 30), (16 + sd * 4, 25)], 'I')
        merge(s, shade_gen(f, 'I', 'J', 'N'))
        line(s, (16 + sd * 8, 22), (16 + sd * 11, 28), 'Y')                                   # a cyan edge along each fin
        s.put(16 + sd * 9, 29, 'N')
    c = Spr(N, N); poly(c, [(10, 12), (22, 12), (24, 16), (22, 22), (19, 27), (13, 27), (10, 22), (8, 16)], 'J')
    merge(s, shade_gen(c, 'J', 'j', 'I'))
    for y in range(13, 27): s.put(16, y, 'N')                                                # the centre seam
    line(s, (10, 13), (14, 20), 'Y'); line(s, (22, 13), (18, 20), 'Y')                         # chevron neon lines down to the power cell
    for sd in (-1, 1): line(s, (16 + sd * 7, 20), (16 + sd * 5, 25), 'z')
    s.rect(14, 20, 5, 5, 'I'); s.hline(14, 20, 5, 'N'); s.vline(14, 20, 5, 'N')               # the power cell: a dark housing with three lit bars
    for y in (21, 23): s.hline(15, y, 3, 'Y')
    s.put(16, 22, 'c'); s.put(16, 24, 'c')
    s.hline(14, 26, 5, 'z'); s.put(16, 27, 'N')
    for (x, y) in ((11, 20), (21, 20), (12, 24), (20, 24)): s.put(x, y, 'N')                  # panel screws
    # pauldrons: angular plates over the arm roots; the left one is a rebuilt plate of mismatched steel
    for sd in (-1, 1):
        p = Spr(N, N); poly(p, [(16 + sd * 11, 11), (16 + sd * 6, 11), (16 + sd * 5, 17), (16 + sd * 8, 19), (16 + sd * 11, 16)], 'S' if sd < 0 else 'J')
        merge(s, shade_gen(p, 'S', 'L', 'W') if sd < 0 else shade_gen(p, 'J', 'j', 'I'))
    line(s, (13, 11), (8, 12), 'Y'); s.hline(8, 11, 2, 'z')                                       # the right pauldron's cyan edge
    for (x, y) in ((24, 12), (25, 13), (26, 14)): s.put(x, y, 'Y')
    for (x, y) in ((7, 13), (9, 17)): s.put(x, y, 'H')                                          # rivets on the rebuilt plate
    for (x, y) in ((8, 14), (8, 15), (9, 16)): s.put(x, y, 'u')
    s.put(7, 15, 'n')
    # the owner's marking (outfit): a chest strap, and a stripe across each pauldron
    s.hline(11, 18, 11, 'B'); s.hline(11, 17, 11, 'A'); s.hline(12, 19, 9, 'C')
    for x in (7, 8): s.put(x, 12, 'A')
    for x in (24, 25): s.put(x, 14, 'B')
    return s

WF_HEADS = ['lens', 'hood', 'helmet']
def wf_head(kind):
    s = Spr(N, N)
    for sd in (-1, 1):                                                                       # a sensor nub on each side of the dome
        s.rect(16 + sd * 5 - (1 if sd < 0 else 0), 10, 2, 3, 'S'); s.put(16 + sd * 5 - (1 if sd < 0 else 0), 10, 'M')
    d = Spr(N, N); ell(d, 16, 11, 5.0, 5.2, 'J'); merge(s, shade_gen(d, 'J', 'j', 'I'))
    s.hline(13, 15, 7, 'N'); s.put(12, 14, 'I'); s.put(20, 14, 'I')                           # the rear seam where the dome meets the neck
    if kind == 'hood':                                                                      # a rebuilt scrap shroud over the back of the dome
        poly(s, [(10, 12), (22, 12), (23, 16), (9, 16)], 'S'); s.hline(10, 12, 13, 'M'); s.hline(9, 16, 15, 'W')
        for (x, y) in ((11, 14), (21, 14), (16, 15)): s.put(x, y, 'H')
        for (x, y) in ((13, 13), (13, 14), (18, 14), (18, 15)): s.put(x, y, 'u')
        s.put(15, 13, 'n')
    ell(s, 16, 10, 3.2, 3.2, 'N'); ell(s, 16, 10, 2.5, 2.5, 'I')                              # the lens socket and its ring
    ell(s, 16, 10, 1.8, 1.8, 'P'); s.put(16, 10, 'm'); s.put(15, 10, 'm'); s.put(17, 10, 'P')
    s.put(15, 9, 'H')                                                                       # a glint
    for (x, y) in ((13, 8), (14, 7), (18, 7), (19, 8)): s.put(x, y, 'Y')                      # a cyan arc of light round the socket
    if kind == 'helmet':                                                                    # a brow plate and ear plates in the owner's colour, a stub antenna
        s.hline(12, 7, 9, 'A'); s.hline(11, 6, 11, 'B'); s.hline(13, 5, 7, 'A'); s.hline(12, 8, 3, 'C'); s.hline(18, 8, 3, 'C')
        for sd in (-1, 1): s.rect(16 + sd * 6 - (1 if sd < 0 else 0), 9, 2, 5, 'B' if sd < 0 else 'C')
        s.put(21, 4, 'S'); s.put(21, 3, 'y')
    return s

def wf_hand(s, x, y):
    s.put(x - 1, y - 2, 'M'); s.put(x + 1, y - 2, 'M'); s.put(x - 1, y - 1, 'S'); s.put(x + 1, y - 1, 'S'); s.put(x, y - 1, 'E')
    s.hline(x - 1, y, 3, 'S'); s.put(x + 1, y, 'W'); s.put(x, y + 1, 'W')                       # a two-prong gripper
def wf_arm(s, a, b):
    t = Spr(N, N); seg(t, a[0], a[1], b[0], b[1], 3, 'J'); merge(s, shade_gen(t, 'J', 'j', 'I'))
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    ex = a[0] + round((b[0] - a[0]) * 0.45); ey = a[1] + round((b[1] - a[1]) * 0.45)
    s.rect(ex - 1, ey - 1, 3, 3, 'S'); s.put(ex - 1, ey - 1, 'M'); s.put(ex + 1, ey + 1, 'W')   # the elbow joint
    s.put(a[0] + round((b[0] - a[0]) * 0.75), a[1] + round((b[1] - a[1]) * 0.75), 'Y')         # a cyan lamp on the forearm
    cx = a[0] + round((b[0] - a[0]) * 0.9); cy = a[1] + round((b[1] - a[1]) * 0.9)
    s.hline(cx - 1, cy, 3, 'B'); s.put(cx - 1, cy - 1, 'A'); s.put(cx + 1, cy + 1, 'C')         # the tinted cuff
def wf_arms(pose):
    s = Spr(N, N); A = pose_anchors((7, 21), (25, 21))[pose]
    if pose == 'unarmed':
        wf_arm(s, (8, 15), (7, 21)); wf_arm(s, (24, 15), (25, 21)); wf_hand(s, 7, 22); wf_hand(s, 25, 22)
        return s
    for sh, k in (((8, 15), 'hand_l'), ((24, 15), 'hand_r')):
        wf_arm(s, sh, (A[k][0], A[k][1] + 1)); wf_hand(s, *A[k])
    return s

class WardenFrame(Species):
    id = 'warden_frame'
    walk_fps = 8
    glow_fps = 2
    head_names = WF_HEADS
    notes = ('Warden-frame: a rebuilt Lumen drone (standard rig). Sleek navy panels with crisp cyan edge lines, a delta chassis that widens to two swept stabiliser fins '
             'behind a lit power cell, mechanical limbs (steel joints, navy sleeves with a cyan stripe, a two-prong gripper) and ONE lens: a magenta eye in a dark socket '
             'in a smooth dome. It was rebuilt: the left pauldron is a mismatched steel plate with rivets and rust. torso_glow (2 frames, ~2 fps) lights the neon lines and '
             'the power cell, head_glow (2 frames per head) pulses the lens. Head variants: lens, hood (a scrap shroud over the back of the dome), helmet (a tinted brow '
             'plate and ear plates, a stub antenna). Outfit mask = the chest strap, the pauldron stripes, the cuffs, the helmet plates.')
    def legs(self): return [outlined(wf_leg_frame(*w)) for w in WF_WALK] + [outlined(wf_leg_frame(1, -1))]
    def torso(self): return outlined(wf_torso())
    def arms(self, pose): return outlined(wf_arms(pose))
    def head(self, name): return outlined(wf_head(name))
    def torso_anchors(self): return {'head': [16, 11], 'back': [16, 25], 'shoulder_l': [8, 15], 'shoulder_r': [24, 15]}
    def arm_anchors(self): return pose_anchors((7, 21), (25, 21))
    def torso_glow(self):
        out = []; t = wf_torso()
        for f in (0, 1):
            g = ng(N)
            glow_px_max(g, spr_pts(t, 'Y'), (31, 169, 194), (0.34, 0.2)[f], 2.2, 1.5)
            glow_px_max(g, spr_pts(t, 'c'), (60, 242, 255), (0.8, 0.5)[f], (3.6, 3.0)[f], 1.4)
            out.append(clear_under(g, t))
        return out
    def head_glow(self):
        out = []
        for f in (0, 1):
            for nm in self.head_names:
                g = ng(N)
                glow_px_max(g, [(16, 10), (15, 10)], (255, 79, 216), (0.85, 0.5)[f], (4.2, 3.2)[f], 1.4)
                glow_px_max(g, [(16, 10)], (244, 246, 248), (0.5, 0.3)[f], 2.0, 1.2)
                out.append(g)
        return out

SPECIES = [WardenFrame]
