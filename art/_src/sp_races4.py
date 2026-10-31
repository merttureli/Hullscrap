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

# ================================================================== MURROW: asteroid-colony diggers, mole-folk. THE LARGE RIG (49x49, pivot (24,24)), like the Grundl and the Drakkin
# Dark velvet fur (E, lit W, shade D) caked with tan dust (Q/q), a stocky hunched barrel of a body, a small head with a long snout ending in a pink star-nose (p/s)
# and TINY eyes, and HUGE digging claws: pink palms with three long cream spade claws (f/L/H) on each arm. A miner's harness (outfit: crossed straps, the belt, the
# wrist wraps, the headband and the hard hat), an ore sack on the back, a lamp battery on the hip. The tail is a short pink stub in the legs layer.
def mR(dx, dy): return (DC + dx, DC + dy)
def mu_fur(s): return shade_gen(s, 'E', 'W', 'D')
def mu_dust(s, y0, y1, k):
    """dust caked into the fur: tan specks (a fixed lattice, no randomness) over the dark fur between rows y0 and y1."""
    for y in range(max(0, y0), min(s.h, y1)):
        for x in range(s.w):
            if s.g[y][x] in ('E', 'D', 'W') and ((x * 5 + y * 3) % k == 0 or (x * 3 - y * 7) % (k + 4) == 0): s.g[y][x] = 'q' if (x + y) % 3 else 'Q'

MU_FOOT = {
 'plant': art("""
f.f.f.f
vsssssv
ssssssv
.vvvvv.
"""),
 'lift': art("""
f.f.f.f
vsssssv
ssssssv
vsssssv
.vvvvv.
"""),
}
def mu_leg_frame(dl, dr, lift_l=False, lift_r=False, tail=0):
    s = Spr(DN, DN)
    for i, y in enumerate(range(DC + 12, DC + 20)):                                           # the short bare tail, swinging a px
        x = DC + int(round(tail * (i / 7.0))); w = 3 if i < 5 else 2
        for k in range(w): s.put(x - w // 2 + k, y, 'p' if k < w - 1 else 'v')
    for cx, d, lift in ((DC - 8, dl, lift_l), (DC + 8, dr, lift_r)):
        fy = DC - d
        t = Spr(DN, DN); t.rect(cx - 5, DC - 3, 10, 6, 'E')
        step = -1 if fy < DC else 1
        for y in range(DC, fy + step, step): t.hline(cx - 4, y, 8, 'E')
        merge(s, mu_fur(t))
        b = MU_FOOT['lift' if lift else 'plant']
        s.stamp(cx - 3, fy - len(b) // 2 - (2 if fy < DC else 0), b)
    return s
MU_WALK = [(11, -11, False, False, 2), (6, -6, False, True, 1), (-6, 6, False, True, -1), (-11, 11, False, False, -2), (-6, 6, True, False, -1), (6, -6, True, False, 1)]

def mu_torso():
    s = Spr(DN, DN)
    # the ore sack and its rope, on the back (under the belt)
    sk = Spr(DN, DN); ell(sk, DC, DC + 12, 7.5, 5.2, 'q'); merge(s, shade_gen(sk, 'q', 'Q', 'n'))
    for (dx, dy) in ((-3, 9), (0, 8), (3, 9)): s.put(DC + dx, DC + dy, 'u')                       # the rope ties
    for (dx, dy) in ((-4, 11), (-1, 12), (2, 10), (4, 12), (0, 14)): s.put(DC + dx, DC + dy, 'y' if (dx + dy) % 2 else 'a')   # nuggets showing in the neck
    # the body: a barrel with two heavy shoulders
    b = Spr(DN, DN); ell(b, DC, DC + 3, 13.5, 11.5, 'E')
    for sd in (-1, 1): ell(b, DC + sd * 13, DC - 3, 7.0, 6.5, 'E')
    f = mu_fur(b)
    for y in range(DN):
        for x in range(DN):
            if f.g[y][x] != '.' and not (s.g[y][x] != '.' and DC + 6 < y): s.g[y][x] = f.g[y][x]
    for dy in range(1, 11, 3): s.put(DC, DC + dy, 'W')                                          # a ridge of lighter fur down the spine
    mu_dust(s, DC - 12, DC + 2, 9)                                                              # heavy dust over the shoulders
    mu_dust(s, DC + 2, DC + 16, 14)
    # the miner's harness (outfit): crossed straps from the shoulders to the belt, the belt and its buckle
    for i in range(18):
        for (x0, sg) in ((DC - 11, 1), (DC + 11, -1)):
            x = x0 + sg * i * 10 // 18; y = DC - 8 + i
            s.put(x - 1, y, 'A'); s.put(x, y, 'B'); s.put(x + 1, y, 'C')
    s.hline(DC - 12, DC + 8, 25, 'B'); s.hline(DC - 12, DC + 7, 25, 'A'); s.hline(DC - 12, DC + 9, 25, 'C')
    s.rect(DC - 2, DC + 7, 5, 4, 'a'); s.hline(DC - 2, DC + 7, 5, 'y'); s.put(DC + 2, DC + 10, 'u'); s.rect(DC - 1, DC + 8, 3, 2, 'n')    # a brass buckle
    # a lamp battery on the left hip with its cable running up to the neck, and a pick stowed on the right
    s.rect(DC - 12, DC + 3, 4, 4, 'S'); s.hline(DC - 12, DC + 3, 4, 'M'); s.put(DC - 10, DC + 5, 'y'); s.put(DC - 9, DC + 6, 'W')
    for i in range(10): s.put(DC - 11 + i // 4, DC + 2 - i, 'n')
    s.vline(DC + 11, DC + 6, 10, 'q'); s.vline(DC + 12, DC + 6, 10, 'n'); s.hline(DC + 8, DC + 15, 7, 'S'); s.put(DC + 8, DC + 15, 'M'); s.put(DC + 14, DC + 16, 'W')
    return s

MU_HEADS = ['snout', 'lamp', 'helmet']
def mu_head(kind):
    s = Spr(DN, DN)
    for sd in (-1, 1): ell(s, DC + sd * 7, DC - 6, 2.2, 2.2, 'W')                              # small fur flaps where ears would be
    sk = Spr(DN, DN); ell(sk, DC, DC - 8, 6.6, 6.4, 'W')
    poly(sk, [(DC - 4, DC - 12), (DC + 4, DC - 12), (DC + 2, DC - 18), (DC - 2, DC - 18)], 'W')
    merge(s, shade_gen(sk, 'W', 'S', 'E'))
    for (dx, dy) in ((-3, -13), (3, -13), (-2, -16), (2, -16)): s.put(DC + dx, DC + dy, 'D')       # whisker roots
    for (dx, dy) in ((-6, -15), (-5, -16), (6, -15), (5, -16), (-7, -13), (7, -13)): s.put(DC + dx, DC + dy, 'M')
    nx, ny = DC, DC - 19                                                                        # the star-nose: a pink centre with short rays
    s.hline(nx - 1, ny, 3, 'p'); s.put(nx, ny - 1, 'p'); s.put(nx, ny + 1, 'p')
    for (dx, dy) in ((-2, 0), (2, 0), (0, -2), (0, 2)): s.put(nx + dx, ny + dy, 's')
    for (dx, dy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)): s.put(nx + dx, ny + dy, 'v')
    for sd in (-1, 1): s.put(DC + sd * 4, DC - 9, 'N'); s.put(DC + sd * 4, DC - 10, 'M')       # tiny eyes with a glint
    if kind == 'lamp':                                                                      # a headband and a lamp (the light is the glow layer)
        s.hline(DC - 6, DC - 10, 13, 'B'); s.hline(DC - 6, DC - 11, 13, 'A'); s.hline(DC - 5, DC - 9, 11, 'C')
        s.rect(DC - 2, DC - 13, 5, 4, 'S'); s.hline(DC - 2, DC - 13, 5, 'M'); s.hline(DC - 1, DC - 12, 3, 'y'); s.put(DC, DC - 12, 'H'); s.put(DC + 2, DC - 10, 'W')
    if kind == 'helmet':                                                                    # a dented hard hat with a brim over the snout's root and a lamp
        h = Spr(DN, DN); ell(h, DC, DC - 7, 7.8, 6.2, 'B'); merge(s, cv2.shade_edges(h))
        s.hline(DC - 8, DC - 11, 17, 'C'); s.hline(DC - 7, DC - 12, 15, 'B'); s.hline(DC - 6, DC - 13, 13, 'C')                # the brim
        for dy in range(-12, -3): s.put(DC, DC + dy, 'A')                                    # the ridge
        for (dx, dy) in ((-4, -9), (-3, -8), (4, -7), (3, -6)): s.put(DC + dx, DC + dy, 'C')   # dents
        s.rect(DC - 2, DC - 12, 5, 3, 'S'); s.hline(DC - 2, DC - 12, 5, 'M'); s.hline(DC - 1, DC - 11, 3, 'y'); s.put(DC, DC - 11, 'H')
    return s

def mu_hand(s, x, y, big=True):
    """a pink palm with three long cream spade claws pointing forward (up); the grip version is smaller, so two of them fit round an item."""
    rx, ry, sp, ln = (5.5, 3.0, 4, 9) if big else (4.0, 2.4, 3, 6)
    p = Spr(DN, DN); ell(p, x, y, rx, ry, 's'); merge(s, shade_gen(p, 's', 'f', 'v'))
    for cx in (x - sp, x, x + sp):
        toward = (1 if cx < x else -1 if cx > x else 0)
        for j in range(ln):
            yy = y - 2 - j
            if j < ln - 5: s.put(cx - 1, yy, 'f'); s.put(cx, yy, 'f'); s.put(cx + 1, yy, 'M')
            elif j < ln - 2: s.put(cx, yy, 'f'); s.put(cx + 1, yy, 'M')
            else: s.put(cx + (toward if j == ln - 1 else 0), yy, 'L' if j < ln - 1 else 'H')
    s.hline(int(x - rx) + 1, y + 1, int(2 * rx) - 1, 'v')                                       # a crease across the palm
def mu_arm(s, a, b):
    t = Spr(DN, DN); m = ((a[0] * 2 + b[0]) // 3, (a[1] * 2 + b[1]) // 3)
    seg(t, a[0], a[1], m[0], m[1], 7, 'E'); seg(t, m[0], m[1], b[0], b[1], 5, 'E'); merge(s, mu_fur(t))     # a heavy upper arm tapering to the wrist
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    for k in (0.25, 0.5):
        x = a[0] + round((b[0] - a[0]) * k); y = a[1] + round((b[1] - a[1]) * k)
        for (dx, dy) in ((-2, 0), (1, 1), (0, -2)): s.put(x + dx, y + dy, 'q')                  # dust
    x = a[0] + round((b[0] - a[0]) * 0.82); y = a[1] + round((b[1] - a[1]) * 0.82)
    s.rect(x - 3, y - 1, 7, 3, 'B'); s.hline(x - 3, y - 1, 7, 'A'); s.hline(x - 3, y + 1, 7, 'C')   # the wrist wrap (outfit)
MU_UNARMED = (mR(-18, 8), mR(18, 8))
def mu_arms(pose):
    s = Spr(DN, DN); A = pose_anchors(*MU_UNARMED, shift=DSH)[pose]
    if pose == 'unarmed':
        mu_arm(s, mR(-14, -3), (MU_UNARMED[0][0], MU_UNARMED[0][1] - 1)); mu_arm(s, mR(14, -3), (MU_UNARMED[1][0], MU_UNARMED[1][1] - 1))
        mu_hand(s, *MU_UNARMED[0]); mu_hand(s, *MU_UNARMED[1])
        return s
    for sh, k, sd in ((mR(-14, -3), 'hand_l', -1), (mR(14, -3), 'hand_r', 1)):          # the claws grip a little wider than the anchors, so they show beside the snout
        h = (A[k][0] + sd * 4, A[k][1] + 1)
        mu_arm(s, sh, (h[0], h[1] + 2)); mu_hand(s, *h, big=False)
    return s

class Murrow(Species):
    id = 'murrow'
    N = DN; C = DC
    walk_fps = 6
    glow_fps = 3
    kind = 'large'
    head_names = MU_HEADS
    notes = ('Murrow: asteroid-colony diggers, mole-folk, on THE LARGE RIG: the frame is 49x49 with the pivot at (24,24) (the normal 2x2 body, 32 px, sits at the centre, its '
             'shadow and pathing stay there; the art overhangs it). Mounts and hands are the shared targets moved by (+8,+8), identical relative to the pivot, so every item '
             'fits (item top-left = mount - item.grip). Dark velvet fur caked with tan dust on a stocky hunched barrel of a body, a small head with a long snout ending in a pink '
             'star-nose and tiny eyes, and HUGE digging claws: pink palms with three long cream spade claws (spread wide when unarmed, a smaller grip round an item). A miner\'s '
             'harness (crossed straps, belt with a brass buckle), an ore sack on the back, a lamp battery on the hip, a pick stowed on the right, a short bare tail in the legs layer '
             '(it swings with the walk). head_glow (2 frames per head, ~3 fps) is the headlamp of the lamp and helmet heads; torso_glow the battery lamp. Head variants: snout, lamp '
             '(a tinted headband with a lamp), helmet (a dented hard hat, tinted, with a lamp). Outfit mask = the harness straps, belt, wrist wraps, headband and hard hat.')
    def legs(self): return [outlined(mu_leg_frame(*w[:4], tail=w[4])) for w in MU_WALK] + [outlined(mu_leg_frame(1, -1, tail=0))]
    def torso(self): return outlined(mu_torso())
    def arms(self, pose): return outlined(mu_arms(pose))
    def head(self, name): return outlined(mu_head(name))
    def torso_anchors(self): return {'head': [DC, DC - 2], 'back': [DC, DC + 12], 'shoulder_l': [DC - 13, DC - 3], 'shoulder_r': [DC + 13, DC - 3]}
    def arm_anchors(self): return pose_anchors(*MU_UNARMED, shift=DSH)
    def torso_glow(self):
        out = []
        for f in (0, 1):
            g = ng(DN); glow_px_max(g, [(DC - 10, DC + 5)], (255, 210, 58), (0.7, 0.4)[f], (3.0, 2.4)[f], 1.4)
            out.append(g)
        return out
    def head_glow(self):
        out = []
        for f in (0, 1):
            for nm in self.head_names:
                g = ng(DN)
                if nm == 'lamp': glow_px_max(g, [(DC, DC - 12), (DC - 1, DC - 12), (DC + 1, DC - 12)], (255, 210, 58), (0.75, 0.5)[f], (5.0, 4.0)[f], 1.4)
                if nm == 'helmet': glow_px_max(g, [(DC, DC - 11), (DC - 1, DC - 11), (DC + 1, DC - 11)], (255, 210, 58), (0.75, 0.5)[f], (5.0, 4.0)[f], 1.4)
                out.append(g)
        return out

# ================================================================== SILTBORN: gas-giant ring floaters, jellyfish-like. A FLOATING rig (49x49, pivot (24,24))
# A translucent bell seen from above (a round disc with a frilled, scalloped rim: pale cream, a dithered glassy shoulder, eight radial canals), an amber gas sac
# in the crown (the head layer) lighting it from inside, tentacle arms with a curled tip, and in the LEGS layer a ruffled skirt and five wavy trailing tendrils with
# amber beads (`float` = frames 0-5 played by time, a closed loop; `stand` = frame 6). The body is drawn on the 33x33 grid and lifted to the middle (+8,+8): the drawer
# bobs it, so no bob is baked in. Outfit = a cloth sling across the bell with a streamer hanging behind (the only tinted part).
SB_R = 12.0
def sb_rim(th): return SB_R + 1.1 * math.cos(12 * th)
def sb_torso():
    s = Spr(N, N)
    for y in range(N):
        for x in range(N):
            dx, dy = x - 16, y - 16; r = math.hypot(dx, dy); R = sb_rim(math.atan2(dy, dx))
            if r > R + 0.4: continue
            lit = (dx + dy) < 1
            if r > R - 2.3:                                                                  # the frill: a pink band with a bright (or deep) outer edge
                c = ('H' if lit else 'v') if r > R - 1.2 else 'p'
            elif r > 5.0:                                                                    # the glassy shoulder: a dither of two tones
                c = (('H' if (x + y) % 2 else 'f') if lit else ('f' if (x + y) % 2 else 's'))
            else: c = 'f' if lit else 's'
            s.put(x, y, c)
    for k in range(8):                                                                       # eight radial canals
        a = k * math.pi / 4.0
        for r in range(5, int(SB_R - 2.4) + 1):
            s.put(int(round(16 + r * math.cos(a))), int(round(16 + r * math.sin(a))), 'p')
    for (x, y) in ((10, 9), (22, 11), (9, 21), (23, 22), (15, 25), (18, 8), (12, 24)):          # gas bubbles trapped in the bell
        s.put(x, y, 'H'); s.put(x + 1, y, 'p')
    # the sling (outfit): a band across the bell and a streamer hanging off its low end, behind
    for i in range(24):
        x = 4 + i; y = 9 + (i * 13) // 24
        s.put(x, y - 1, 'A'); s.put(x, y, 'B'); s.put(x, y + 1, 'C')
    for j in range(9):
        x = 26 + (j * 2) // 9; s.put(x, 22 + j, 'B' if j % 2 else 'A'); s.put(x + 1, 22 + j, 'C')
    s.put(26, 31, 'C'); s.put(27, 31, 'C')
    return s

SB_HEADS = ['crown', 'bloom', 'helmet']
def sb_head(kind):
    s = Spr(N, N)
    if kind == 'bloom':                                                                      # an open bloom: six rose petals round the sac
        for k in range(6):
            a = k * math.pi / 3.0 + math.pi / 6.0
            p = Spr(N, N); ell(p, 16 + 6.3 * math.cos(a), 15 + 6.3 * math.sin(a), 2.6, 2.6, 'p'); merge(s, shade_gen(p, 'p', 'f', 'v'))
    sc = Spr(N, N); ell(sc, 16, 15, 5.2, 5.2, 'a'); merge(s, shade_gen(sc, 'a', 'y', 'o'))
    ell(s, 16, 15, 2.8, 2.8, 'y'); s.put(15, 14, 'H'); s.put(16, 14, 'H'); s.put(15, 15, 'H')                    # the gas sac and its hot core
    if kind == 'crown':
        for k in range(8):
            a = k * math.pi / 4.0 + math.pi / 8.0
            x = int(round(16 + 7.2 * math.cos(a))); y = int(round(15 + 7.2 * math.sin(a))); s.put(x, y, 'f'); s.put(x + 1, y, 'p')   # cilia beads round the sac
    if kind == 'helmet':                                                                     # a salvaged bubble helm: a steel ring, the glass tinted blue, glints
        for y in range(N):
            for x in range(N):
                r = math.hypot(x - 16, y - 15)
                if 6.0 <= r <= 7.6: s.put(x, y, 'L' if (x - 16) + (y - 15) < 0 else ('S' if r < 7.0 else 'W'))
                elif r < 6.0 and ((x + y) % 3 == 0) and (x - 16) + (y - 15) < 2: s.put(x, y, 'b')
        for (x, y) in ((11, 11), (12, 10), (13, 9)): s.put(x, y, 'H')
        s.put(21, 20, 'M'); s.put(22, 19, 'M')
        for (x, y) in ((16, 8), (16, 22)): s.put(x, y, 'M')                                  # two clamps
    return s

def sb_tentacle(s, a, b, bend):
    mid = (int(round((a[0] + b[0]) / 2.0 + bend)), int(round((a[1] + b[1]) / 2.0)))
    t = Spr(N, N); seg(t, a[0], a[1], mid[0], mid[1], 2, 'p'); seg(t, mid[0], mid[1], b[0], b[1], 2, 'p')
    merge(s, shade_gen(t, 'p', 'f', 'v'))
    for k in (0.3, 0.65):                                                                    # pale sucker beads along the arm
        s.put(a[0] + round((b[0] - a[0]) * k) + (1 if bend > 0 else -1) * 0, a[1] + round((b[1] - a[1]) * k), 'H')
def sb_curl(s, x, y, sd):
    """the tip: a little curled loop that wraps whatever it holds, with an amber bead."""
    for (dx, dy, c) in ((0, 0, 'p'), (sd, 0, 'f'), (sd, -1, 'p'), (0, -1, 'f'), (-sd, 0, 'v'), (0, 1, 'v')): s.put(x + dx, y + dy, c)
    s.put(x, y - 2, 'a'); s.put(x + sd, y - 2, 'y')
SB_UNARMED = ((5, 22), (27, 22))
def sb_arms(pose):
    s = Spr(N, N); A = pose_anchors(*SB_UNARMED)[pose]
    if pose == 'unarmed':
        sb_tentacle(s, (7, 14), (5, 22), -3); sb_tentacle(s, (25, 14), (27, 22), 3)
        sb_curl(s, 5, 23, -1); sb_curl(s, 27, 23, 1)
        return s
    for sh, k, bend, sd in (((7, 14), 'hand_l', -3, -1), ((25, 14), 'hand_r', 3, 1)):
        sb_tentacle(s, sh, (A[k][0], A[k][1] + 1), bend); sb_curl(s, A[k][0], A[k][1] + 1, sd)
    return s

SB_PH = [i * math.pi / 3.0 for i in range(6)]                       # 6 steps = one full wave, so the loop closes
SB_TIPS = {-10: 40, -5: 44, 0: 47, 5: 44, 10: 40}
def sb_leg_frame(i):
    s = Spr(FN, FN)
    ph = SB_PH[i] if i < 6 else 0.7; amp = 2.6 if i < 6 else 1.0
    for dx in range(-10, 11):                                                                # the ruffled skirt under the bell: pale lobes with a pink edge
        yb = int(round(36 + 3.0 * math.cos(dx * 0.95 - ph) * (1.0 - abs(dx) / 14.0)))
        for y in range(30, yb + 1): s.put(FC + dx, y, 'f' if y < yb else 'p')
    for k, off in enumerate((-10, -5, 0, 5, 10)):
        ymax = SB_TIPS[off]
        for y in range(31, ymax + 1):
            tt = (y - 31) / float(ymax - 31)
            x = FC + off * (1.0 + 0.1 * tt) + amp * math.sin(0.55 * (y - 31) - ph + k * 1.1) * (0.25 + tt)
            xi = int(round(x))
            s.put(xi, y, 'p' if (y // 2) % 3 else 'f')
            if (y - 31) % 6 == 5 and y < ymax - 1: s.put(xi, y, 'a')                       # an amber bead every few px
        tx = int(round(FC + off * 1.1 + amp * math.sin(0.55 * (ymax - 31) - ph + k * 1.1) * 1.25))
        s.put(tx, ymax, 'y'); s.put(tx, ymax - 1, 'a')
    return s

class Siltborn(Species):
    id = 'siltborn'
    N = FN; C = FC
    kind = 'floating'; legs_anim = 'float'
    walk_fps = 5
    glow_fps = 2
    head_names = SB_HEADS
    notes = ('Siltborn: gas-giant ring floaters, jellyfish-like; a FLOATING rig (kind "floating": 49x49, pivot (24,24)). No walk: the legs layer is a ruffled skirt and five wavy trailing '
             'tendrils with amber beads, drawn pointing back (down at rotation 0) and turned to the movement direction (`float`: 6 frames, 5 fps, a closed loop played by time; '
             '`stand`: the calm idle frame). The body (torso, head, arms) sits in the middle of the frame as a normal body and the drawer bobs it, so no bob is baked in: a translucent '
             'bell seen from above (a frilled, scalloped rim, a dithered glassy shoulder, eight radial canals, trapped bubbles), an amber gas sac in the crown (head layer) lighting it '
             'from inside, tentacle arms ending in a curl round the item. The mounts are the human\'s moved by (+8,+8). torso_glow (2 frames, ~2 fps) is the faint glow of the canals, head_glow '
             '(2 frames per head) the sac, legs_glow (one frame per legs frame) the tendril tips. Head variants: crown (a ring of cilia beads), bloom (six rose petals), helmet '
             '(a salvaged bubble helm). Outfit mask = the cloth sling across the bell and its streamer.')
    def legs(self): return [outlined(sb_leg_frame(i)) for i in range(7)]
    def torso(self): return outlined(lift(sb_torso(), FN, 8))
    def arms(self, pose): return outlined(lift(sb_arms(pose), FN, 8))
    def head(self, name): return outlined(lift(sb_head(name), FN, 8))
    def torso_anchors(self): return {'head': [FC, FC - 1], 'back': [FC, FC + 8], 'shoulder_l': [FC - 9, FC - 2], 'shoulder_r': [FC + 9, FC - 2]}
    def arm_anchors(self): return pose_anchors((5 + 8, 22 + 8), (27 + 8, 22 + 8), shift=8)
    def legs_glow(self):
        out = []
        for i in range(7):
            g = ng(FN); t = sb_leg_frame(i)
            glow_px_max(g, spr_pts(t, 'y'), (255, 210, 58), 0.6, 3.0, 1.5)
            glow_px_max(g, spr_pts(t, 'a'), (225, 161, 54), 0.3, 2.2, 1.5)
            out.append(g)
        return out
    def torso_glow(self):
        out = []
        for f in (0, 1):
            g = ng(33); t = sb_torso()
            glow_px_max(g, spr_pts(t, 'p'), (232, 138, 160), (0.3, 0.18)[f], 2.4, 1.5)
            glow_px_max(g, [(16, 15)], (255, 138, 30), (0.4, 0.25)[f], (11.0, 9.0)[f], 1.8)
            out.append(lift_glow(clear_under(g, t), FN, 8))
        return out
    def head_glow(self):
        out = []
        for f in (0, 1):
            for nm in self.head_names:
                g = ng(33)
                glow_px_max(g, [(16, 15), (15, 14), (16, 14)], (255, 210, 58), (0.85, 0.55)[f], (6.0, 4.6)[f], 1.4)
                out.append(lift_glow(g, FN, 8))
        return out

# ================================================================== CORVIN: crow-like wreck traders with an eye for shine (standard rig)
# Blue-black feathers (D lit E, deep N, a sheen of j) in a scalloped feather cloak over the shoulders and back, a beaked head (an amber beak, bright gold eyes), a fan of
# long tail feathers behind (in the legs layer: it sways with the walk), thin scaly bird legs with three-toed talons, pockets everywhere (outfit: a bandolier with
# pouches and a belt of pouches at each hip) and shiny trinkets pinned on the cloak (a coin, a bead, a spark of glass).
CV_FOOT = {
 'plant': art("""
f.f.f
Q.Q.Q
QQqQQ
.qqq.
"""),
 'lift': art("""
f.f.f
Q.Q.Q
QQqQQ
QQqQQ
.qqq.
"""),
}
def cv_leg_frame(dl, dr, lift_l=False, lift_r=False, sway=0):
    s = Spr(N, N)
    for k, ang in enumerate((-36, -18, 0, 18, 36)):                                         # the tail: five long feathers fanning from the rump
        a = math.radians(ang); L = 9 if k == 2 else 8
        tx = 16 + int(round(L * math.sin(a) + sway * (1 if k % 2 else 0.6))); ty = 22 + int(round(L * math.cos(a)))
        t = Spr(N, N); seg(t, 16, 21, tx, ty, 2, 'D'); merge(s, shade_gen(t, 'D', 'E', 'N'))
        s.put(tx, ty, 'j')
    for lx, d, lift in ((10, dl, lift_l), (22, dr, lift_r)):
        fy = 16 - d
        step = -1 if fy < 16 else 1
        ys = list(range(16, fy + step, step))
        t = Spr(N, N); t.rect(lx - 2, 14, 5, 4, 'D'); merge(s, shade_gen(t, 'D', 'E', 'N'))            # the feathered thigh
        for y in ys: s.put(lx - 1, y, 'Q'); s.put(lx, y, 'q')                                  # a thin scaly shin
        if len(ys) > 5: s.put(lx, ys[len(ys) // 2], 'n')                                       # the ankle joint
        b = CV_FOOT['lift' if lift else 'plant']
        s.stamp(lx - 2, fy - len(b) // 2 - (1 if fy < 16 else 0), b)
    return s
CV_WALK = [(8, -8, False, False, 2), (4, -4, False, True, 1), (-4, 4, False, True, -1), (-8, 8, False, False, -2), (-4, 4, True, False, -1), (4, -4, True, False, 1)]

CV_CLOAK = [(10, 11), (22, 11), (26, 13), (28, 18), (27, 24), (26, 27), (24, 26), (22, 29), (19, 28), (17, 30), (16, 28), (15, 30), (13, 28), (10, 29), (8, 26), (6, 27), (5, 24), (4, 18), (6, 13)]   # a ragged feather hem
def cv_pouch(s, x, y):
    s.rect(x, y, 3, 3, 'B'); s.hline(x, y, 3, 'A'); s.hline(x, y + 2, 3, 'C'); s.put(x + 1, y + 1, 'a')
def cv_torso():
    s = Spr(N, N)
    c = Spr(N, N); poly(c, CV_CLOAK, 'D'); merge(s, shade_gen(c, 'D', 'E', 'N'))
    for r, y0 in enumerate((12, 16, 20, 24)):                                                # rows of overlapping feathers
        off = 2 * (r % 2)
        for x in range(4, 29):
            for y in (y0 + 2, y0 + 3):
                if s.get(x, y) in ('D', 'E'):
                    k = (x + off) % 4
                    if y == y0 + 3 and k in (0, 1): s.put(x, y, 'E')
                    if y == y0 + 3 and k == 3: s.put(x, y, 'N')
                    if y == y0 + 2 and k == 0: s.put(x, y, 'j')                              # the blue sheen on a feather
    for y in range(13, 28): s.put(16, y, 'N') if y % 4 else None                              # a broken spine seam
    # the bandolier (outfit) from the left shoulder to the right hip, with three pouches on it, and a pouch belt at each hip
    for i in range(16):
        x = 8 + i; y = 13 + (i * 11) // 16
        s.put(x, y - 1, 'A'); s.put(x, y, 'B'); s.put(x, y + 1, 'C')
    for (x, y) in ((10, 15), (14, 18), (19, 22)): cv_pouch(s, x, y + 1)
    for sd in (-1, 1):
        for y in (17, 21):
            cv_pouch(s, 16 + sd * 11 - (1 if sd < 0 else 0), y)
    # shiny trinkets pinned on the cloak: a gold coin, a bead, a spark of glass, a gem
    s.put(12, 22, 'y'); s.put(13, 22, 'a'); s.put(21, 14, 'c'); s.put(8, 20, 'H'); s.put(24, 19, 'm'); s.put(18, 26, 'y'); s.put(17, 26, 'a'); s.put(21, 25, 'H')
    return s

CV_HEADS = ['beak', 'loupe', 'helmet']
def cv_head(kind):
    s = Spr(N, N)
    h = Spr(N, N); ell(h, 16, 11, 4.4, 4.6, 'E'); poly(h, [(13, 9), (19, 9), (18, 5), (14, 5)], 'E'); merge(s, shade_gen(h, 'E', 'j', 'D'))
    # the beak: long, pointed, amber with a bright ridge and a dark underside
    s.stamp(14, 1, art("""
..y..
..a..
.yan.
.yan.
yaaan
yaaan
.nnn.
"""))
    s.put(15, 4, 'N'); s.put(17, 4, 'N')                                                    # the nostrils
    for sd in (-1, 1):                                                                       # bright gold eyes with a dark pupil
        ex = 16 + sd * 3
        s.put(ex, 9, 'y'); s.put(ex + sd, 9, 'y'); s.put(ex, 10, 'N'); s.put(ex + sd, 10, 'y')
        s.put(ex, 8, 'D')                                                                    # a brow
    for (x, y) in ((13, 13), (19, 13), (16, 14)): s.put(x, y, 'N')                           # throat feathers
    if kind == 'loupe':                                                                      # a jeweller's loupe over the right eye on a cord
        for (x, y) in ((17, 7), (18, 7), (19, 7), (20, 8), (20, 9), (20, 10), (20, 11), (19, 11), (18, 11), (17, 10), (17, 9), (17, 8)): s.put(x, y, 'a')
        s.put(18, 8, 'c'); s.put(19, 8, 'c'); s.put(18, 9, 'N'); s.put(19, 9, 'c'); s.put(18, 10, 'c'); s.put(19, 10, 'c'); s.put(17, 8, 'H'); s.put(18, 7, 'y')
        for (x, y) in ((21, 11), (21, 12), (21, 13), (20, 14)): s.put(x, y, 'n')
    if kind == 'helmet':                                                                     # a dented pot helm of scrap steel with a rust patch and a pinned trinket
        pt = Spr(N, N); ell(pt, 16, 8, 5.4, 3.6, 'S'); merge(s, shade_gen(pt, 'S', 'L', 'W'))
        s.hline(11, 10, 11, 'B'); s.hline(11, 11, 11, 'C'); s.put(11, 10, 'A')                    # a tinted strap round the helm's rim
        for (x, y) in ((13, 7), (14, 6), (19, 8)): s.put(x, y, 'u')
        s.put(12, 8, 'H'); s.put(20, 7, 'H'); s.put(15, 9, 'M')
        s.put(18, 6, 'y'); s.put(19, 6, 'a')
        s.rect(15, 5, 3, 2, 'E')                                                             # the helm's nose bar over the beak's root
        for x in (13, 19): s.put(x, 9, 'N')
        for sd in (-1, 1):
            ex = 16 + sd * 3; s.put(ex, 9, 'y'); s.put(ex + sd, 9, 'y'); s.put(ex, 10, 'N'); s.put(ex + sd, 10, 'y')
    return s

def cv_talon(s, x, y):
    for (dx, dy, c) in ((-1, -2, 'f'), (1, -2, 'f'), (-1, -1, 'Q'), (0, -1, 'Q'), (1, -1, 'Q'), (-1, 0, 'q'), (0, 0, 'q'), (1, 0, 'n')): s.put(x + dx, y + dy, c)   # three long toes with pale claws
def cv_arm(s, a, b):
    t = Spr(N, N); seg(t, a[0], a[1], b[0], b[1], 3, 'D'); merge(s, shade_gen(t, 'D', 'E', 'N'))
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    s.put(a[0] + round((b[0] - a[0]) * 0.4), a[1] + round((b[1] - a[1]) * 0.4), 'j')         # a blue sheen
    cx = a[0] + round((b[0] - a[0]) * 0.82); cy = a[1] + round((b[1] - a[1]) * 0.82)
    s.hline(cx - 1, cy, 3, 'B'); s.put(cx - 1, cy - 1, 'A'); s.put(cx + 1, cy + 1, 'C')       # a tinted cuff
CV_UNARMED = ((6, 21), (26, 21))
def cv_arms(pose):
    s = Spr(N, N); A = pose_anchors(*CV_UNARMED)[pose]
    if pose == 'unarmed':
        cv_arm(s, (8, 15), (6, 20)); cv_arm(s, (24, 15), (26, 20)); cv_talon(s, 6, 22); cv_talon(s, 26, 22)
        return s
    for sh, k in (((8, 15), 'hand_l'), ((24, 15), 'hand_r')):
        cv_arm(s, sh, (A[k][0], A[k][1] + 1)); cv_talon(s, A[k][0], A[k][1] + 2)
    return s

class Corvin(Species):
    id = 'corvin'
    walk_fps = 8
    glow_fps = 1
    head_names = CV_HEADS
    notes = ('Corvin: crow-like wreck traders with an eye for shine (standard rig). Blue-black feathers in a scalloped feather cloak over the shoulders and back, a beaked head '
             '(an amber beak, bright gold eyes), a fan of five long tail feathers behind (in the legs layer: it sways with the walk), thin scaly bird legs ending in three-toed '
             'talons, pockets everywhere (a bandolier with three pouches and a belt of pouches at each hip) and shiny trinkets pinned on the cloak (a gold coin, a bead, a spark of '
             'glass, a gem). Head variants: beak, loupe (a jeweller\'s loupe over one eye, brass ring and cyan glass), helmet (a dented scrap pot helm with a tinted strap and a pinned '
             'trinket). head_glow lights the loupe glass; torso_glow the glint of the trinkets (2 frames, ~1 fps). Outfit mask = the bandolier, the pouches, the cuffs, the helm strap.')
    def legs(self): return [outlined(cv_leg_frame(*w[:4], sway=w[4])) for w in CV_WALK] + [outlined(cv_leg_frame(1, -1, sway=0))]
    def torso(self): return outlined(cv_torso())
    def arms(self, pose): return outlined(cv_arms(pose))
    def head(self, name): return outlined(cv_head(name))
    def torso_anchors(self): return {'head': [16, 11], 'back': [16, 26], 'shoulder_l': [8, 15], 'shoulder_r': [24, 15]}
    def arm_anchors(self): return pose_anchors(*CV_UNARMED)
    def torso_glow(self):
        out = []; t = cv_torso()
        for f in (0, 1):
            g = ng(N)
            pts = [(21, 14), (8, 20), (24, 19), (12, 22), (18, 26)] if f == 0 else [(21, 14), (8, 20), (24, 19), (21, 25), (17, 26)]
            glow_px_max(g, pts, (244, 246, 248), (0.5, 0.35)[f], 2.2, 1.5)
            out.append(clear_under(g, t))
        return out
    def head_glow(self):
        out = []
        for f in (0, 1):
            for nm in self.head_names:
                g = ng(N)
                if nm == 'loupe': glow_px_max(g, [(18, 9), (19, 9), (18, 10), (19, 10)], (60, 242, 255), (0.6, 0.4)[f], 2.6, 1.5)
                out.append(g)
        return out

# ================================================================== BRINE: crab-shelled Concord dockworkers. THE LARGE RIG (49x49, pivot (24,24))
# A broad brick-red carapace (e, lit r/u, deep n) wider than the 2x2 body with a row of orange spines along its front edge, salt-crust specks (f), jointed crab legs
# jutting out to the sides (legs layer: three a side, they step in alternation), two eyes on stalks, and ONE BIG WORK CLAW on the right arm (a red pincer with a serrated
# bite that closes round whatever it holds) against a small claw on the left. Dock-union gear (outfit): crossed cargo straps over the shell, the claw's wrist band, the
# goggles and the hard hat; a stencilled union plate on the rear of the shell.
def bR(dx, dy): return (DC + dx, DC + dy)
BR_ROOTS = ((-2, 12), (3, 13), (8, 12))                                                    # the three leg roots on each side: (dy, dx)
def br_leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(DN, DN)
    for sd, d in ((-1, dl), (1, dr)):
        for i, (ry, rx) in enumerate(BR_ROOTS):
            m = int(round(d * 0.32 * (1 if i % 2 == 0 else -1)))
            root = (DC + sd * rx, DC + ry); knee = (DC + sd * (rx + 8), DC + ry - 3 + m); tip = (DC + sd * (rx + 10), DC + ry + 5 + m)
            t = Spr(DN, DN); seg(t, root[0], root[1], knee[0], knee[1], 3, 'e'); seg(t, knee[0], knee[1], tip[0], tip[1], 2, 'e')
            merge(s, shade_gen(t, 'e', 'r', 'n'))
            s.put(knee[0], knee[1], 'o'); s.put(tip[0], tip[1], 'f'); s.put(tip[0], tip[1] + 1, 'f')                # a bright knee joint and a pale pointed dactyl
    return s
BR_WALK = [(11, -11, False, False), (6, -6, False, True), (-6, 6, False, True), (-11, 11, False, False), (-6, 6, True, False), (6, -6, True, False)]

def br_torso():
    s = Spr(DN, DN)
    sh = Spr(DN, DN); ell(sh, DC, DC + 2, 16.0, 11.5, 'e')
    for k in range(-5, 6):                                                                  # the front-lateral spines, round the front half of the rim
        th = math.radians(-90 + k * 15.5)
        px_ = DC + 16.0 * math.cos(th); py_ = DC + 2 + 11.5 * math.sin(th)
        nx, ny = math.cos(th) * 11.5, math.sin(th) * 16.0; nl = math.hypot(nx, ny); nx, ny = nx / nl, ny / nl
        tx, ty = px_ + nx * 4.6, py_ + ny * 4.6; ox, oy = -ny * 1.9, nx * 1.9
        poly(sh, [(px_ - nx * 1.5 + ox, py_ - ny * 1.5 + oy), (px_ - nx * 1.5 - ox, py_ - ny * 1.5 - oy), (tx, ty)], 'e')
    f = shade_gen(sh, 'e', 'r', 'n')
    merge(s, f)
    for y in range(DN):                                                                      # a lit top-left shoulder to the carapace: two tones with a dither seam
        for x in range(DN):
            if s.g[y][x] == 'e':
                v = (x - DC) + (y - DC)
                if v < -11 or (v < -8 and (x + y) % 2 == 0): s.g[y][x] = 'u'
    for (dx, dy) in ((-2, -10), (-1, -11), (1, -11), (2, -10)): s.put(DC + dx, DC + dy, 'o')   # the frontal teeth
    for dx in range(-12, 13):                                                                # a bowed ridge across the shell, and the two grooves of the gastric region
        y = DC - 3 + int(round(4.0 * (dx / 12.0) ** 2))
        if s.get(DC + dx, y) in ('e', 'u'): s.put(DC + dx, y, 'r' if dx % 3 else 'o')
    for sd in (-1, 1):
        for dy in range(0, 9): s.put(DC + sd * 5, DC + dy, 'n')
        for dy in range(2, 10): s.put(DC + sd * 9, DC + dy + (dy > 7), 'n') if dy % 3 else None
    for y in range(DC - 12, DC + 14):                                                        # salt crust and barnacle specks
        for x in range(DC - 17, DC + 18):
            if s.get(x, y) in ('e', 'u', 'r') and (x * 7 + y * 5) % 29 == 0: s.put(x, y, 'f' if (x + y) % 3 else 'H')
    for (dx, dy) in ((-9, 6), (7, 9), (11, 1)): s.put(DC + dx, DC + dy, 'f'); s.put(DC + dx + 1, DC + dy, 'f'); s.put(DC + dx, DC + dy + 1, 'M')    # barnacle patches
    # the dock-union harness (outfit): two straps crossing over the shell, and a belt of cargo hooks round the rear
    for i in range(22):
        for (x0, sg) in ((DC - 12, 1), (DC + 12, -1)):
            x = x0 + sg * (i * 24 // 22); y = DC - 7 + (i * 18) // 22
            s.put(x, y - 1, 'A'); s.put(x, y, 'B'); s.put(x, y + 1, 'C')
    s.put(DC, DC + 2, 'a'); s.rect(DC - 1, DC + 1, 3, 3, 'a'); s.put(DC - 1, DC + 1, 'y'); s.put(DC + 1, DC + 3, 'u')                                   # the cross-over buckle
    s.rect(DC - 5, DC + 8, 10, 4, 'a'); s.rect(DC - 5, DC + 8, 10, 1, 'y'); s.hline(DC - 5, DC + 11, 10, 'u')                                           # the union plate, stencilled
    for dx in (-4, -2, 0, 2, 3): s.put(DC + dx, DC + 9, 'N'); s.put(DC + dx, DC + 10, 'n') if dx % 2 == 0 else None
    return s

BR_HEADS = ['stalks', 'goggles', 'helmet']
def br_head(kind):
    s = Spr(DN, DN)
    for sd in (-1, 1):                                                                       # the eyestalks, then the eyes (drawn first: the helmet covers their roots)
        t = Spr(DN, DN); seg(t, DC + sd * 3, DC - 9, DC + sd * 5, DC - 13, 2, 'e'); merge(s, shade_gen(t, 'e', 'r', 'n'))
        ex, ey = DC + sd * 6, DC - 15
        ell(s, ex, ey, 2.3, 2.3, 'f'); s.put(ex, ey, 'N'); s.put(ex, ey - 1, 'N'); s.put(ex - 1, ey - 1, 'H'); s.put(ex + 1, ey + 1, 'M')
    fr = Spr(DN, DN); ell(fr, DC, DC - 8, 6.8, 3.2, 'e'); merge(s, shade_gen(fr, 'e', 'r', 'n'))      # the frontal plate between the stalks
    for dx in (-3, -1, 1, 3): s.put(DC + dx, DC - 7, 'n')                                    # mouthparts
    s.put(DC, DC - 6, 'p')
    if kind == 'goggles':                                                                    # union goggles: a tinted frame round each eye on a strap
        for sd in (-1, 1):
            ex, ey = DC + sd * 6, DC - 15
            for (dx, dy) in ((-3, 0), (3, 0), (0, -3), (0, 3), (-2, -2), (2, -2), (-2, 2), (2, 2)): s.put(ex + dx, ey + dy, 'B' if dx <= 0 else 'C')
            s.put(ex - 2, ey - 2, 'A'); s.put(ex, ey - 3, 'A')
        s.hline(DC - 3, DC - 11, 7, 'B'); s.hline(DC - 3, DC - 10, 7, 'C')
    if kind == 'helmet':                                                                     # a dock hard hat on the frontal plate, the stalks out through the sides
        h = Spr(DN, DN); ell(h, DC, DC - 6, 5.6, 4.0, 'B'); merge(s, cv2.shade_edges(h))
        s.hline(DC - 6, DC - 4, 13, 'C'); s.hline(DC - 5, DC - 5, 11, 'B'); s.hline(DC - 4, DC - 9, 9, 'A')
        for dy in range(-9, -5): s.put(DC, DC + dy, 'A')
        s.put(DC - 2, DC - 8, 'C'); s.put(DC + 3, DC - 7, 'C')
    return s

def br_claw(s, x, y, big=True):
    """a crab claw pointing up, centred on x, its wrist at y: the palm, two fingers that close at the tips (the gap narrows), teeth along the bite."""
    if big: palm, fl, fr_, ln, sc = (5.6, 5.0), [(-5, -2), (-1, -2), (-2, -12), (-5, -10), (-6, -6)], [(1, -2), (5, -2), (6, -6), (5, -10), (2, -12)], 12, 1.0
    else: palm, fl, fr_, ln, sc = (3.4, 3.2), [(-3, -1), (-1, -1), (-1, -7), (-3, -6), (-4, -3)], [(1, -1), (3, -1), (4, -3), (3, -6), (1, -7)], 7, 0.7
    t = Spr(DN, DN); ell(t, x, y, palm[0], palm[1], 'r')
    poly(t, [(x + a, y + b) for a, b in fl], 'r'); poly(t, [(x + a, y + b) for a, b in fr_], 'r')
    merge(s, shade_gen(t, 'r', 'o', 'e'))
    for j in range(3, ln - 1, 2):                                                            # teeth on the inner edges of the bite
        s.put(x - 1, y - j, 'f'); s.put(x + 1, y - j + 1, 'f')
    s.put(x - 2, y - ln + 1, 'o'); s.put(x + 2, y - ln + 1, 'o')
    s.hline(x - int(palm[0]) + 1, y + int(palm[1]) - 1, int(2 * palm[0]) - 1, 'n')            # the wrist shadow
def br_arm(s, a, b, w=5):
    t = Spr(DN, DN); seg(t, a[0], a[1], b[0], b[1], w, 'e'); merge(s, shade_gen(t, 'e', 'r', 'n'))
    ex = a[0] + round((b[0] - a[0]) * 0.5); ey = a[1] + round((b[1] - a[1]) * 0.5); s.put(ex, ey, 'o')           # the elbow
def br_band(s, a, b):
    cx = a[0] + round((b[0] - a[0]) * 0.8); cy = a[1] + round((b[1] - a[1]) * 0.8)
    s.rect(cx - 3, cy - 1, 7, 3, 'B'); s.hline(cx - 3, cy - 1, 7, 'A'); s.hline(cx - 3, cy + 1, 7, 'C')
BR_UNARMED = (bR(-15, 5), bR(15, 5))
def br_arms(pose):
    s = Spr(DN, DN); A = pose_anchors(*BR_UNARMED, shift=DSH)[pose]
    if pose == 'unarmed':
        bl, brr = (BR_UNARMED[0][0], BR_UNARMED[0][1]), (BR_UNARMED[1][0] + 2, BR_UNARMED[1][1] - 6)
        br_arm(s, bR(-14, -4), (bl[0], bl[1] - 1), 4); br_arm(s, bR(14, -4), (brr[0], brr[1] + 3), 5)
        br_claw(s, *bl, big=False); br_claw(s, *brr)
        br_band(s, bR(14, -4), (brr[0], brr[1] + 3))
        return s
    hl = A['hand_l']; hr = (A['mount'][0], A['hand_r'][1])                                    # the pincer straddles the item, whose grip is at the mount
    br_arm(s, bR(-14, -4), (hl[0], hl[1] + 1), 4); br_arm(s, bR(14, -4), (hr[0], hr[1] + 2), 5)
    br_claw(s, hl[0], hl[1] + 1, big=False); br_claw(s, hr[0], hr[1] + 2)
    br_band(s, bR(14, -4), (hr[0], hr[1] + 2))
    return s

class Brine(Species):
    id = 'brine'
    N = DN; C = DC
    walk_fps = 6
    glow_fps = 1
    kind = 'large'
    head_names = BR_HEADS
    notes = ('Brine: crab-shelled Concord dock-union workers, on THE LARGE RIG: the frame is 49x49 with the pivot at (24,24) (the normal 2x2 body, 32 px, sits at the centre, its '
             'shadow and pathing stay there; the art overhangs it). Mounts and hands are the shared targets moved by (+8,+8), identical relative to the pivot, so every item fits '
             '(item top-left = mount - item.grip). A broad brick-red carapace with a row of orange spines along its front edge and salt-crust specks, three jointed crab legs a side in the '
             'legs layer (they step in alternation at 6 fps), two eyes on stalks, ONE BIG WORK CLAW on the right arm (a red pincer with a toothed bite that straddles the held item) and a '
             'small claw on the left. Head variants: stalks, goggles (union goggles, tinted frames), helmet (a dock hard hat, tinted). Outfit mask = the crossed cargo straps, the claw\'s wrist '
             'band, the goggle frames, the hard hat.')
    def legs(self): return [outlined(br_leg_frame(*w)) for w in BR_WALK] + [outlined(br_leg_frame(1, -1))]
    def torso(self): return outlined(br_torso())
    def arms(self, pose): return outlined(br_arms(pose))
    def head(self, name): return outlined(br_head(name))
    def torso_anchors(self): return {'head': [DC, DC - 8], 'back': [DC, DC + 12], 'shoulder_l': [DC - 14, DC - 4], 'shoulder_r': [DC + 14, DC - 4]}
    def arm_anchors(self): return pose_anchors(*BR_UNARMED, shift=DSH)

# ================================================================== ECHO: a polite shimmering mimic (standard rig)
# A smooth chrome body with no seams: every surface is shaded like a mirror ball (a bright sky band, a hard dark horizon line right under it, a ground tone with a faint
# violet bounce light, a vertical specular streak), a long smooth head, tube limbs ending in plain rounded mitts, slim capsule legs. It copies whoever is near: a faint
# lilac figure of a person is mirrored in a pane on the back, and the `mimic` head wears a faint copy of a face. The shimmer is the glow layers (4 frames, ~4 fps): a
# soft diagonal sheen that sweeps across the whole body. Outfit = a thin sash, armbands and the cap band (the only tinted parts).
def ec_chrome(s, cx, cy, rx, ry, hz=0.05, lean=0.35, spec=True):
    """a chrome ball: an ellipse shaded with a mirror's environment (sky, a hard horizon, ground, a bounce light)."""
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            nx = (x - cx) / rx; ny = (y - cy) / ry
            if nx * nx + ny * ny > 1.0: continue
            tt = ny - hz - lean * nx
            if tt < -0.9: c = 'M'
            elif tt < -0.45: c = 'L'
            elif tt < -0.1: c = 'H'
            elif tt < 0.1: c = 'W'
            elif tt < 0.5: c = 'S'
            elif tt < 1.1: c = 'M'
            else: c = 'X' if nx > 0.2 else 'M'                                              # a faint violet bounce light on the lower right rim only
            if spec and -0.62 < nx < -0.38 and -0.65 < ny < 0.35: c = 'H'
            if tt < -0.9 and nx < -0.3 and ny < -0.5: c = 'Y'                                  # a cyan reflection of the sky at the top left
            s.put(x, y, c)
def ec_tube(s, a, b, w=3):
    t = Spr(N, N); seg(t, a[0], a[1], b[0], b[1], w, 'M'); merge(s, shade_gen(t, 'M', 'H', 'S'))
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    for k in (0.3, 0.6): s.put(a[0] + round((b[0] - a[0]) * k), a[1] + round((b[1] - a[1]) * k), 'L')     # a gleam along the tube

EC_FOOT = {
 'plant': art("""
.LMM.
LMMMS
MMMSS
.SSW.
"""),
 'lift': art("""
.LMM.
LMMMS
MMMSS
MMSSS
.SSW.
"""),
}
def ec_leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift in ((10, dl, lift_l), (22, dr, lift_r)):
        fy = 16 - d
        step = -1 if fy < 16 else 1
        ys = list(range(16, fy + step, step))
        for y in ys:                                                                       # a smooth capsule leg, shaded across like a tube
            for k, c in enumerate('LMSW'): s.put(lx - 2 + k, y, c)
        for k, c in enumerate('LMMS'): s.put(lx - 2 + k, 16, c)
        b = EC_FOOT['lift' if lift else 'plant']
        s.stamp(lx - 2, fy - len(b) // 2 - (1 if fy < 16 else 0), b)
    return s
EC_WALK = walk_cycle(8, 4)

def ec_torso():
    s = Spr(N, N)
    ec_chrome(s, 16, 19, 7.4, 8.6)
    for sd in (-1, 1): ec_chrome(s, 16 + sd * 8, 15, 3.4, 3.4, spec=False)                  # the shoulders: smooth balls
    # the reflection pane on the back: a faint lilac figure of a person mirrored in the chrome (a head, shoulders, a body)
    for (x, y) in ((16, 20), (17, 20), (16, 21), (17, 21)): s.put(x, y, 'L')
    s.put(16, 20, 'X'); s.put(17, 21, 'X')
    s.hline(13, 23, 8, 'L'); s.hline(12, 24, 10, 'L'); s.hline(14, 25, 6, 'L'); s.hline(14, 26, 6, 'M')
    s.put(12, 24, 'X'); s.put(21, 24, 'X'); s.put(13, 23, 'X'); s.put(20, 23, 'X')
    # the sash (outfit) across the chest, and an armband on each shoulder ball
    for i in range(14):
        x = 9 + i; y = 13 + (i * 8) // 14
        s.put(x, y - 1, 'A'); s.put(x, y, 'B'); s.put(x, y + 1, 'C')
    for sd in (-1, 1): s.hline(16 + sd * 8 - 1, 13 + (1 if sd > 0 else 0), 3, 'B')
    return s

EC_HEADS = ['smooth', 'mimic', 'helmet']
def ec_head(kind):
    s = Spr(N, N)
    ell(s, 16, 14, 2.2, 1.6, 'S')                                                           # the neck, smooth
    ec_chrome(s, 16, 10, 4.3, 5.4, hz=-0.05)
    if kind == 'mimic':                                                                     # a faint copy of a face: two eye hollows, a nose, a mouth line (lilac, soft)
        for ex in (14, 18): s.put(ex, 9, 'V'); s.put(ex, 10, 'X')
        s.put(16, 11, 'X'); s.hline(15, 13, 3, 'V')
    if kind == 'helmet':                                                                    # a polished cap with a tinted band and a mirror visor strip
        for y in range(5, 10):
            for x in range(11, 22):
                if s.get(x, y) != '.': s.put(x, y, 'L' if (x - 16) + (y - 9) < 0 else 'M')
        s.hline(11, 9, 11, 'B'); s.hline(11, 8, 11, 'A'); s.hline(12, 10, 9, 'C')
        s.hline(13, 11, 6, 'N'); s.put(13, 11, 'c'); s.put(14, 11, 'Y'); s.hline(13, 12, 6, 'S')
        s.put(13, 6, 'H'); s.put(14, 5, 'H')
    return s

def ec_mitt(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 'M'); s.put(x - 1, y - 1, 'H'); s.put(x, y - 1, 'L'); s.put(x + 1, y + 1, 'S'); s.put(x, y + 1, 'S'); s.put(x - 1, y - 2, 'L'); s.put(x, y - 2, 'M')   # a plain rounded mitt, no fingers
EC_UNARMED = ((6, 22), (26, 22))
def ec_arms(pose):
    s = Spr(N, N); A = pose_anchors(*EC_UNARMED)[pose]
    if pose == 'unarmed':
        ec_tube(s, (8, 15), (6, 21)); ec_tube(s, (24, 15), (26, 21)); ec_mitt(s, 6, 22); ec_mitt(s, 26, 22)
    else:
        for sh, k in (((8, 15), 'hand_l'), ((24, 15), 'hand_r')):
            ec_tube(s, sh, (A[k][0], A[k][1] + 1)); ec_mitt(s, *A[k])
    return s

def sheen(layer, spr, c, a=100):
    """a soft diagonal sheen: the band x + y = c on every pixel of `spr` (white core, a cyan fringe), alpha only: the hue stays a palette colour."""
    for y in range(spr.h):
        for x in range(spr.w):
            if spr.g[y][x] == '.': continue
            d = abs(x + y - c)
            if d <= 1: layer.p[y][x] = [244, 246, 248, a]
            elif d == 2: layer.p[y][x] = [60, 242, 255, int(a * 0.45)]

class Echo(Species):
    id = 'echo'
    walk_fps = 8
    glow_fps = 4
    head_names = EC_HEADS
    notes = ('Echo: a polite shimmering mimic (standard rig). A smooth chrome body with no seams: every surface is shaded like a mirror ball (a bright sky band, a hard dark horizon '
             'line under it, a ground tone with a faint violet bounce, a vertical specular streak), a long smooth head, tube limbs ending in plain rounded mitts, slim capsule '
             'legs. It copies whoever is near: a faint lilac figure of a person is mirrored in a pane on the back, and the mimic head wears a faint copy of a face. The shimmer is '
             'the glow layers: torso_glow and head_glow have 4 frames (head_glow 4 per head variant) at ~4 fps, a soft diagonal sheen sweeping across the body. Head variants: smooth, '
             'mimic (a faint face), helmet (a polished cap with a tinted band and a mirror visor strip). Outfit mask = the sash, the armbands, the cap band.')
    def legs(self): return [outlined(ec_leg_frame(*w)) for w in EC_WALK] + [outlined(ec_leg_frame(1, -1))]
    def torso(self): return outlined(ec_torso())
    def arms(self, pose): return outlined(ec_arms(pose))
    def head(self, name): return outlined(ec_head(name))
    def torso_anchors(self): return {'head': [16, 11], 'back': [16, 25], 'shoulder_l': [8, 15], 'shoulder_r': [24, 15]}
    def arm_anchors(self): return pose_anchors(*EC_UNARMED)
    def torso_glow(self):
        out = []; t = ec_torso()
        for c in (18, 26, 34, 44):
            g = ng(N); sheen(g, t, c); out.append(clear_under(g, t))
        return out
    def head_glow(self):
        out = []
        for c in (14, 22, 30, 38):
            for nm in self.head_names:
                g = ng(N); h = ec_head(nm); sheen(g, h, c, 90); out.append(clear_under(g, h))
        return out

SPECIES = [WardenFrame, Murrow, Siltborn, Corvin, Brine, Echo]
