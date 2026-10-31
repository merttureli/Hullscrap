"""Race wave 3 crew rigs (docs/waves/races_2_4.md): REVENANT, CHOIR, RATTLER (the small rig), TESSELLATE (and its 1x1 half, TESSELLATE_HALF: a second small rig),
SABLE, QUILLBACK and KITE. One module, no new palette colours (every letter already exists; pal_races1 registers the private cyans Y / z).
The layers, animations and item mounts are the shared rig's (see sp_races2.py and art/README.md "Crew"): every layer faces UP at rotation 0 on one frame
(normal 33x33 pivot (16,16); small 25x25 pivot (12,12)); the arms `mount` anchors are the human's moved by pivot - (16,16), so any item fits any body.
Outfit symbols A/B/C = light/base/dark (tint mask); B and C are NOT the neon cyans here, Y and z are (pal_races1).
  * normal: Revenant, Choir, Tessellate, Sable, Quillback, Kite;
  * SMALL (Rattler, Tessellate_half): legs, torso and every head inside the central 15x15 (pivot +-7: the interior is at most 13x13, the outline makes it 15);
    only the arms reach beyond it, to the shared mounts."""
import math
from sp_common import *
import pal_races1     # noqa: F401  (registers the private cyan letters Y / z)
from sp_races2 import inside, poly, line, ell, seg, merge, shade, limb, lift, lift_glow, ng, walk_cycle, clear_under, planes
from sp_races2 import SN, SC, S_HANDS, s_anchors, s_rel, V_WALK         # the small rig's frame, pivot, hand targets and 4 px stride

def hands_of(pose, A=None): return pose_anchors((0, 0), (0, 0))[pose]

def cuff(s, a, b, f, c='S', lo='W', w=3):
    """a ring (w x 2) on the limb a -> b, `f` of the way along."""
    x = a[0] + round((b[0] - a[0]) * f); y = a[1] + round((b[1] - a[1]) * f)
    s.rect(x - w // 2, y - 1, w, 2, c); s.hline(x - w // 2, y, w, lo)

# ================================================================== REVENANT: pale, stitched, in a salvaged pressure-suit with dead lamps (standard rig)
# Hollow-touched survivors. A cold bluish-pale skin (L, lit H, shade M), black thread stitches (E), a pressure-suit patched from many wrecks (the tinted outfit
# is the suit, brown and rust patches are salvage), a life-support pack on the back with two tanks and a dead gauge, ring pauldrons with lamps that no longer
# light (D), a hose that dangles behind (it lives in the legs layer and sways). Eyes: two faint cold dots (head_glow, a slow flicker).
R_BOOT = {
 'plant': art("""
.EEEEE.
EWEEEED
EEEEEED
EEEEEDD
.DDDDD.
"""),
 'lift': art("""
.EEEEE.
EWEEEED
EEEEEED
EEEEEED
EEEEEDD
.DDDDD.
"""),
}
def r_hose(s, sway):
    """the dangling hose from the pack's foot: two px of brown rubber ending in a dead coupling."""
    pts = [(16, 26), (17, 27), (16 + sway // 2 + 1, 29), (16 + sway, 31)]
    for a, b in zip(pts, pts[1:]): seg(s, a[0], a[1], b[0], b[1], 2, 'q')
    ex, ey = pts[-1]; s.put(ex - 1, ey + 1, 'S'); s.put(ex, ey + 1, 'S'); s.put(ex + 1, ey + 1, 'W'); s.put(ex, ey + 2, 'D')
    for (x, y) in pts[1:3]: s.put(x + 1, y, 'n')
def r_leg_frame(dl, dr, lift_l=False, lift_r=False, sway=0):
    s = Spr(N, N)
    r_hose(s, sway)
    for lx, d, lift in ((10, dl, lift_l), (22, dr, lift_r)):
        fy = 16 - d
        step = -1 if fy < 16 else 1
        ys = list(range(16, fy + step, step))
        t = Spr(N, N)
        for y in ys: t.hline(lx - 2, y, 5, 'B')
        t = cv2.shade_edges(t); merge(s, t)
        if len(ys) > 5:
            ky = ys[len(ys) // 2]; s.rect(lx - 1, ky, 3, 2, 'q'); s.put(lx - 1, ky, 'Q'); s.put(lx + 1, ky + 1, 'n')       # a knee patch, the stitches dark
            s.put(lx - 2, ky, 'E'); s.put(lx + 2, ky + 1, 'E')
            wy = ys[len(ys) * 3 // 4]; s.hline(lx - 2, wy, 5, 'S'); s.hline(lx - 2, wy + (1 if step < 0 else -1), 5, 'W')    # a sealing ring at the ankle
        b = R_BOOT['lift' if lift else 'plant']
        s.stamp(lx - 3, fy - len(b) // 2 - (1 if fy < 16 else 0), b)
    return s
R_WALK = [(8, -8, False, False, 3), (4, -4, False, True, 1), (-4, 4, False, True, -1), (-8, 8, False, False, -3), (-4, 4, True, False, -1), (4, -4, True, False, 1)]

def r_ring(s, cx, cy):
    """a ring pauldron with a dead lamp on its front."""
    t = Spr(N, N); ell(t, cx, cy, 3.8, 3.8, 'S'); t = shade_gen(t, 'S', 'L', 'W'); merge(s, t)
    ell(s, cx, cy, 1.7, 1.7, 'E'); s.put(cx, cy, 'D')
    s.put(cx - 1, cy - 4, 'W'); s.put(cx, cy - 4, 'D'); s.put(cx + 1, cy - 4, 'W')                       # the lamp: dead, a dark lens in a steel frame
    s.put(cx, cy - 3, 'K')
def r_torso():
    s = Spr(N, N)
    t = Spr(N, N); ell(t, 16, 18, 8.2, 6.2, 'B'); merge(s, cv2.shade_edges(t))
    # the life-support pack: two tanks side by side on the back, a valve block between and above them, a dead gauge
    pk = Spr(N, N)
    pk.rect(11, 19, 11, 8, 'S')
    pk = shade_gen(pk, 'S', 'M', 'W'); merge(s, pk)
    for tx in (12, 18):
        s.rect(tx, 20, 3, 6, 'M'); s.vline(tx, 20, 6, 'L'); s.vline(tx + 2, 20, 6, 'W')
        s.hline(tx, 22, 3, 'u'); s.hline(tx, 24, 3, 'u'); s.put(tx + 2, 22, 'n'); s.put(tx + 2, 24, 'n')    # rust straps
    s.rect(15, 19, 3, 3, 'E'); s.put(16, 20, 'D'); s.put(15, 19, 'W'); s.put(17, 19, 'W')
    s.hline(12, 26, 9, 'W'); s.hline(13, 27, 7, 'D')
    # a hose loop round the left of the pack
    for (x, y) in ((11, 20), (10, 21), (10, 22), (10, 23), (11, 24), (12, 25)): s.put(x, y, 'q')
    for (x, y) in ((11, 21), (11, 22), (11, 23)): s.put(x, y, 'n')
    # ring pauldrons with dead lamps
    r_ring(s, 8, 15); r_ring(s, 24, 15)
    # harness straps over the chest (outfit) and a collar seat where the head sits
    for i in range(5): s.put(11 + i, 12 + i, 'A'); s.put(12 + i, 12 + i, 'B')
    for i in range(5): s.put(21 - i, 12 + i, 'A'); s.put(20 - i, 12 + i, 'B')
    # salvage: a brown patch with black thread, a rust patch, stitched seams
    s.rect(12, 16, 4, 3, 'q'); s.hline(12, 16, 4, 'Q'); s.put(12, 16, 'E'); s.put(15, 18, 'E'); s.put(12, 18, 'E'); s.put(15, 16, 'E')
    s.rect(19, 17, 3, 3, 'u'); s.put(19, 17, 'E'); s.put(21, 19, 'E')
    for y in range(13, 19, 2): s.put(16, y, 'E')
    for x in (5, 27):
        for y in (17, 19): s.put(x, y, 'E')
    return s

R_HEADS = ['bare', 'hood', 'helmet']
def r_head(kind):
    s = Spr(N, N)
    ring = Spr(N, N); ell(ring, 16, 14, 6.4, 3.0, 'S'); ring = shade_gen(ring, 'S', 'L', 'W'); merge(s, ring)       # the neck seal the head rises out of
    ell(s, 16, 14, 4.6, 1.8, 'E')
    if kind == 'helmet':
        h = Spr(N, N); ell(h, 16, 11, 5.4, 5.6, 'S'); h = shade_gen(h, 'S', 'L', 'W'); merge(s, h)
        ell(s, 16, 12, 3.9, 2.7, 'D'); s.hline(13, 11, 7, 'E')                                           # the visor, a dark slot with the pale face deep in it
        s.hline(12, 9, 9, 'u'); s.put(12, 9, 'n'); s.put(20, 9, 'n')                                      # a rust band across the brow
        s.rect(15, 6, 3, 2, 'W'); s.put(16, 6, 'D'); s.put(16, 7, 'D'); s.put(14, 7, 'K'); s.put(18, 8, 'K')       # the helmet lamp, dark and cracked
        for (x, y) in ((11, 8), (21, 8)): s.put(x, y, 'L')
    else:
        h = Spr(N, N); ell(h, 16, 11, 4.4, 4.9, 'L'); h = shade_gen(h, 'L', 'H', 'M'); merge(s, h)
        for (x, y) in ((12, 13), (20, 13), (13, 14), (19, 14)): s.put(x, y, 'M')                        # hollow cheeks
        for y in range(7, 10): s.put(16, y, 'E' if y % 2 else 'D')                                       # a stitched seam over the crown
        s.put(15, 8, 'E'); s.put(17, 9, 'E')
        for (x, y) in ((18, 12), (19, 13), (20, 14)): s.put(x, y, 'E')                                   # a scar sewn shut across the right cheek
        for x in range(14, 19): s.put(x, 15, 'E' if x % 2 else '.')                                      # the mouth, stitched
        if kind == 'hood':                                                                               # a salvaged cloth hood (outfit) over the crown and neck
            hd = Spr(N, N); ell(hd, 16, 10, 5.6, 5.8, 'B')
            for y in range(N):
                for x in range(N):
                    if ((x - 16) / 3.5) ** 2 + ((y - 12.4) / 3.6) ** 2 <= 1.0: hd.erase(x, y)
            hd = cv2.shade_edges(hd)
            for y in range(hd.h):
                for x in range(hd.w):
                    if hd.g[y][x] != '.': s.g[y][x] = hd.g[y][x]
            for y in range(9, 17):
                for x in range(13, 20):
                    if ((x - 16) / 3.4) ** 2 + ((y - 12.5) / 3.6) ** 2 <= 1.0 and s.g[y][x] == '.': s.g[y][x] = 'L'
            for (x, y) in ((13, 10), (19, 10)): s.put(x, y, 'A')
            s.put(16, 5, 'C'); s.put(16, 6, 'C')
    # the eyes: two small cold dots in dark sockets (the glow layer gives them their cold light)
    for ex in (14, 18):
        s.rect(ex - 1, 11 if kind != 'helmet' else 12, 3, 2, 'D'); s.put(ex, 11 if kind != 'helmet' else 12, 'c')
    return s

def r_hand(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 'L'); s.put(x - 1, y - 1, 'H'); s.put(x + 1, y + 1, 'M'); s.put(x, y + 1, 'M'); s.put(x - 1, y - 2, 'L'); s.put(x + 1, y - 2, 'M')   # fingers
    s.put(x, y, 'E')                                                                                    # a stitch across the knuckles
def r_arm(s, a, b):
    t = Spr(N, N); seg(t, a[0], a[1], b[0], b[1], 4, 'B'); merge(s, cv2.shade_edges(t))
    cuff(s, a, b, 0.78, 'S', 'W', 4)
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1); i = int(n * 0.4)
    s.put(a[0] + round((b[0] - a[0]) * i / n) + 1, a[1] + round((b[1] - a[1]) * i / n), 'E')            # a stitch down the sleeve
def r_arms(pose):
    s = Spr(N, N); A = pose_anchors((6, 21), (26, 21))[pose]
    if pose == 'unarmed':
        r_arm(s, (8, 16), (6, 21)); r_arm(s, (24, 16), (26, 21)); r_hand(s, 6, 22); r_hand(s, 26, 22)
        return s
    for sh, k in (((8, 16), 'hand_l'), ((24, 16), 'hand_r')):
        r_arm(s, sh, (A[k][0], A[k][1] + 1)); r_hand(s, *A[k])
    return s

class Revenant(Species):
    id = 'revenant'
    walk_fps = 6
    glow_fps = 1
    head_names = R_HEADS
    notes = ('Revenant: Hollow-touched survivors (standard rig). A cold, pale, stitched face (black thread seams, a mouth sewn shut) in a pressure-suit patched together '
             'from many wrecks: the suit is the tinted outfit, brown and rust patches are salvage. A life-support pack on the back (two tanks, a dead gauge), ring '
             'pauldrons whose lamps no longer light, and a hose that dangles behind (in the legs layer: it sways with the walk). Eyes are two faint cold dots: '
             'head_glow has 2 frames per head variant (a slow flicker, ~1 fps). Head variants: bare, hood (a salvaged cloth hood, tinted), helmet (a dented pressure '
             'helm with a dead lamp). Outfit mask = the suit, the harness straps, the hood.')
    def legs(self): return [outlined(r_leg_frame(*w[:4], sway=w[4])) for w in R_WALK] + [outlined(r_leg_frame(1, -1, sway=0))]
    def torso(self): return outlined(r_torso())
    def arms(self, pose): return outlined(r_arms(pose))
    def head(self, name): return outlined(r_head(name))
    def torso_anchors(self): return {'head': [16, 12], 'back': [16, 24], 'shoulder_l': [8, 15], 'shoulder_r': [24, 15]}
    def arm_anchors(self): return pose_anchors((6, 21), (26, 21))
    def head_glow(self):
        out = []
        for f in (0, 1):
            for nm in self.head_names:
                g = ng(N); y = 11 if nm != 'helmet' else 12
                glow_px_max(g, [(14, y), (18, y)], (60, 242, 255), (0.42, 0.26)[f], (2.8, 2.2)[f], 1.5)
                out.append(g)
        return out


# ================================================================== CHOIR: crystal singers of the Lumen chantry (standard rig)
# A hollow resonant body of lilac crystal (X lit H, shade V, deep Z) shaped like a violin's body: two sound holes (f-holes) and a round rose hole that is dark
# inside (the light in it is the torso glow, a 2-frame resonance pulse), a gold bridge and tailpiece. A ring of tuning prongs (gold forks: stem a, tines y, tips H)
# stands round the shoulders like a halo. Crystal limbs with gold rings, a smooth crystal head with a round open mouth (head_glow lights it) and closed eye slits.
# Outfit = the chantry vestment: a stole down the front and back, a collar and the cuffs; the mitre.
def c_prongs(s):
    """a ring of 11 tuning forks round the neck: a stem, then two tines with a gap between them, gold with a pale tip (the back ones are under the body)."""
    cx, cy = 16.0, 15.0
    for deg in range(-150, 151, 30):
        a = math.radians(deg); sx, sy = math.sin(a), -math.cos(a)
        px_, py_ = -sy, sx                                      # the perpendicular
        for r in range(7, 12):
            x = cx + r * sx; y = cy + r * sy
            if r <= 8: s.put(int(round(x)), int(round(y)), 'a')
            else:
                for o in (-1, 1): s.put(int(round(x + o * px_)), int(round(y + o * py_)), 'y' if r < 11 else 'H')
                if r == 9: s.put(int(round(x)), int(round(y)), 'a')
def c_torso():
    s = Spr(N, N)
    c_prongs(s)
    b = Spr(N, N); ell(b, 16, 16, 8.6, 4.8, 'X'); ell(b, 16, 21.5, 6.6, 5.0, 'X'); ell(b, 16, 19, 4.6, 3.0, 'X')
    b = shade_gen(b, 'X', 'H', 'V')
    merge(s, b)
    # crystal facets: shade lines from the crown of the body, lit planes on the left
    for (a, c, col) in (((16, 12), (8, 17), 'L'), ((16, 12), (24, 17), 'V'), ((16, 13), (11, 26), 'H'), ((16, 13), (22, 27), 'V'), ((10, 16), (12, 22), 'V'), ((22, 16), (20, 22), 'H')):
        t = Spr(N, N); line(t, a, c, col)
        for y in range(N):
            for x in range(N):
                if t.g[y][x] != '.' and s.g[y][x] == 'X': s.g[y][x] = t.g[y][x]
    # the rose hole (dark, with a violet inner wall) and the two f-holes
    ell(s, 16, 21.5, 3.0, 3.4, 'Z'); ell(s, 16, 21.5, 2.2, 2.6, 'N'); s.put(15, 20, 'I'); s.put(16, 20, 'I')
    for sd in (-1, 1):                                                                    # the f-holes: a slim S-curve each side of the rose hole
        for (dx, dy) in ((1, 0), (0, 1), (0, 2), (0, 3), (1, 4), (1, 5)): s.put(16 + sd * (4 + dx + 1), 19 + dy, 'N')
        s.put(16 + sd * 6, 19, 'Z'); s.put(16 + sd * 5, 24, 'Z')
    s.hline(14, 18, 5, 'a'); s.put(13, 18, 'y'); s.put(19, 18, 'y')                          # the gold bridge
    s.hline(14, 26, 5, 'y'); s.hline(15, 27, 3, 'a')                                          # the tailpiece
    # the vestment (outfit): a stole down the front and back, a collar at the neck
    for y in range(13, 17): s.put(15, y, 'A'); s.put(16, y, 'B'); s.put(17, y, 'C')
    s.hline(12, 25, 9, 'B'); s.hline(12, 24, 2, 'A'); s.hline(19, 24, 2, 'A'); s.put(20, 25, 'C'); s.put(19, 25, 'C')               # a hem band
    s.hline(11, 14, 11, 'B'); s.hline(11, 15, 11, 'C'); s.put(11, 14, 'A'); s.put(12, 14, 'A')
    return s

C_HEADS = ['singer', 'mitre', 'helmet']
def c_head(kind):
    s = Spr(N, N)
    h = Spr(N, N); ell(h, 16, 11.5, 4.3, 5.0, 'X'); h = shade_gen(h, 'X', 'H', 'V'); merge(s, h)
    for (a, b, col) in (((16, 7), (12, 12), 'L'), ((16, 7), (20, 12), 'V'), ((12, 12), (16, 16), 'V')):
        t = Spr(N, N); line(t, a, b, col)
        for y in range(N):
            for x in range(N):
                if t.g[y][x] != '.' and s.g[y][x] == 'X': s.g[y][x] = t.g[y][x]
    for ex in (13, 18): s.hline(ex, 11, 2, 'Z')                                                # closed eye slits
    ell(s, 16, 8.3, 1.7, 1.2, 'Z'); s.put(16, 8, 'N'); s.put(15, 8, 'N'); s.put(17, 8, 'N')    # the round mouth, open mid-note
    if kind == 'mitre':
        m = Spr(N, N); poly(m, [(16, 3), (21, 8), (21, 13), (11, 13), (11, 8)], 'B'); m = cv2.shade_edges(m)
        for y in range(N):
            for x in range(N):
                if m.g[y][x] != '.' and not (13 <= x <= 19 and 9 <= y <= 12): s.g[y][x] = m.g[y][x]
        s.hline(13, 7, 7, 'a'); s.put(16, 4, 'y'); s.put(16, 5, 'a')
        for y in range(5, 9): s.put(16, y, 'A')
        s.hline(13, 13, 7, 'C')
        for ex in (13, 18): s.hline(ex, 11, 2, 'Z')
        ell(s, 16, 10.2, 1.5, 0.9, 'N')
    if kind == 'helmet':                                                                         # a glass dome with a brass rim: the singer's note stays inside
        d = Spr(N, N); ell(d, 16, 11.5, 5.8, 6.2, 'b'); d = shade_gen(d, 'b', 'H', 'Y'); 
        for y in range(N):
            for x in range(N):
                if d.g[y][x] != '.' and s.g[y][x] == '.': s.g[y][x] = d.g[y][x]
        for y in range(N):
            for x in range(N):
                if ((x - 16) / 5.8) ** 2 + ((y - 11.5) / 6.2) ** 2 > 0.62 and d.g[y][x] != '.': s.g[y][x] = 'a' if (x + y) % 3 else 'y'
        s.put(12, 7, 'H'); s.put(13, 6, 'H'); s.put(11, 9, 'L')
    return s

def c_hand(s, x, y):
    for dx in (-1, 0, 1): s.put(x + dx, y, 'X'); s.put(x + dx, y - 1, 'L' if dx < 1 else 'X')
    s.put(x - 1, y - 2, 'H'); s.put(x + 1, y - 2, 'L'); s.put(x, y + 1, 'V'); s.put(x + 1, y, 'V')       # three crystal fingers
def c_arm(s, a, b):
    t = Spr(N, N); seg(t, a[0], a[1], b[0], b[1], 3, 'X'); merge(s, shade_gen(t, 'X', 'H', 'V'))
    cuff(s, a, b, 0.7, 'y', 'a', 3)
    s.put(a[0], a[1], 'a')
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    s.put(a[0] + round((b[0] - a[0]) * 0.4) , a[1] + round((b[1] - a[1]) * 0.4), 'B')
def c_arms(pose):
    s = Spr(N, N); A = pose_anchors((6, 21), (26, 21))[pose]
    if pose == 'unarmed':
        c_arm(s, (9, 16), (6, 21)); c_arm(s, (23, 16), (26, 21)); c_hand(s, 6, 22); c_hand(s, 26, 22)
        return s
    for sh, k in (((9, 16), 'hand_l'), ((23, 16), 'hand_r')):
        c_arm(s, sh, (A[k][0], A[k][1] + 1)); c_hand(s, *A[k])
    return s

C_FOOT = {
 'plant': art("""
.XXX.
XLXVV
VVVVZ
.ZZZ.
"""),
 'lift': art("""
.XXX.
XLXVV
XVVVV
VVVVZ
.ZZZ.
"""),
}
def c_leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift in ((12, dl, lift_l), (20, dr, lift_r)):
        fy = 16 - d
        step = -1 if fy < 16 else 1
        ys = list(range(16, fy + step, step))
        t = Spr(N, N)
        for y in ys: t.hline(lx - 1, y, 3, 'X')
        merge(s, shade_gen(t, 'X', 'H', 'V'))
        if len(ys) > 4:
            ky = ys[len(ys) * 2 // 3]; s.hline(lx - 1, ky, 3, 'y'); s.put(lx + 1, ky, 'a')              # a gold ring at the shin
        b = C_FOOT['lift' if lift else 'plant']
        s.stamp(lx - 2, fy - len(b) // 2 - (1 if fy < 16 else 0), b)
    return s

class Choir(Species):
    id = 'choir'
    walk_fps = 6
    glow_fps = 2
    head_names = C_HEADS
    notes = ('Choir: crystal singers of the Lumen chantry (standard rig). A hollow resonant body of lilac crystal shaped like a violin\'s: two f-holes, a round dark rose '
             'hole, a gold bridge and tailpiece; a ring of 11 gold tuning forks stands round the shoulders like a halo (the back ones are under the body). Crystal limbs with '
             'gold rings and three-fingered hands, forked crystal feet. torso_glow (2 frames, ~2 fps) is the resonance light in the rose hole, the f-holes and the fork tips; '
             'head_glow lights the singer\'s open mouth. Head variants: singer (bare crystal, a round open mouth), mitre (a chantry mitre, tinted), helmet (a glass dome with a '
             'brass rim). Outfit mask = the stole, the collar, the cuff ring-bands are gold (not tinted), the mitre.')
    def legs(self): return [outlined(c_leg_frame(*w)) for w in walk_cycle(12, 6)] + [outlined(c_leg_frame(1, -1))]
    def torso(self): return outlined(c_torso())
    def arms(self, pose): return outlined(c_arms(pose))
    def head(self, name): return outlined(c_head(name))
    def torso_anchors(self): return {'head': [16, 12], 'back': [16, 24], 'shoulder_l': [9, 16], 'shoulder_r': [23, 16]}
    def arm_anchors(self): return pose_anchors((6, 21), (26, 21))
    def torso_glow(self):
        out = []
        for f in (0, 1):
            g = ng(N)
            glow_px_max(g, [(16, 21)], (196, 160, 240), (0.75, 0.45)[f], (6.0, 4.5)[f], 1.4)
            glow_px_max(g, [(9, 20), (9, 21), (9, 22), (23, 20), (23, 21), (23, 22)], (196, 160, 240), (0.4, 0.55)[f], 2.6, 1.5)
            tips = [(round(16 + 11 * math.sin(math.radians(d))), round(15 - 11 * math.cos(math.radians(d)))) for d in range(-120, 121, 30)]
            glow_px_max(g, tips, (255, 210, 58), (0.35, 0.55)[f], 2.6, 1.5)
            out.append(g)
        return out
    def head_glow(self):
        out = []
        for f in (0, 1):
            for nm in self.head_names:
                g = ng(N)
                if nm != 'helmet': glow_px_max(g, [(16, 8)], (196, 160, 240), (0.6, 0.35)[f], (3.4, 2.4)[f], 1.4)
                out.append(g)
        return out


# ================================================================== RATTLER: scrap gremlins who live in Rusthold's walls. THE SMALL RIG (25x25, pivot (12,12))
# Drawn on a 17x17 grid round (8,8) and lifted onto the 25x25 frame (+4,+4), so legs, torso and head stay inside the central 15x15 (the interior is at most
# 13x13: grid 2..14). Gunmetal-grey skin (S lit M, shade W) with two huge bat ears (pink inside), brass goggles with blue glass, rust leather gloves and boots,
# a tool belt that bristles with a wrench, a screwdriver and a hammer head. Outfit = the overalls (and the hard hat).
RA_BOOT = {
 'plant': art("""
nn
nn
"""),
 'lift': art("""
qn
nn
n.
"""),
}
def ra_leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(VN, VN)
    for lx, d, lift in ((2, dl, lift_l), (13, dr, lift_r)):
        fy = 9 - d
        step = -1 if fy < 9 else 1
        ys = list(range(9, fy + step, step))
        for y in ys: s.put(lx, y, 'M'); s.put(lx + 1, y, 'S')
        if len(ys) > 2: s.put(lx, ys[len(ys) // 2], 'B'); s.put(lx + 1, ys[len(ys) // 2], 'C')                  # a patched knee (outfit)
        b = RA_BOOT['lift' if lift else 'plant']
        s.stamp(lx, fy - len(b) // 2 - (1 if fy < 9 else 0), b)
    return s
VN = 17; VC = 8
def ra_torso():
    s = Spr(VN, VN)
    b = Spr(VN, VN); ell(b, 8, 9.5, 4.2, 3.6, 'B'); merge(s, cv2.shade_edges(b))
    s.hline(4, 11, 9, 'n'); s.hline(5, 12, 7, 'q'); s.put(8, 11, 'a'); s.put(7, 11, 'y')                              # the tool belt and its buckle
    s.rect(4, 12, 2, 2, 'q'); s.put(4, 12, 'Q'); s.rect(11, 12, 2, 2, 'q'); s.put(11, 12, 'Q')                      # pouches
    s.put(12, 10, 'M'); s.put(13, 10, 'M'); s.put(13, 9, 'L'); s.put(14, 9, 'S'); s.put(14, 10, 'S')                  # a wrench stuck in the belt, its jaw out to the right
    s.put(3, 11, 'a'); s.put(3, 10, 'a'); s.put(3, 9, 'S')                                                           # a screwdriver, amber handle
    s.put(9, 13, 'M'); s.put(9, 14, 'W'); s.put(10, 14, 'W')                                                         # a hammer head hanging behind
    for (x, y) in ((6, 8), (10, 8)): s.put(x, y, 'a')                                                              # the overalls' brass buttons
    s.put(7, 9, 'u'); s.put(8, 9, 'u')                                                                              # a rust smear
    return s
def ra_head(kind):
    s = Spr(VN, VN)
    for sd in (-1, 1):                                                                                              # the huge ears: a grey flap with a pink inside
        e = Spr(VN, VN); poly(e, [(8 + sd * 3, 5), (8 + sd * 6, 2), (8 + sd * 6, 6), (8 + sd * 4, 8)], 'S'); e = shade_gen(e, 'S', 'M', 'W'); merge(s, e)
        for (x, y) in ((8 + sd * 4, 5), (8 + sd * 5, 4), (8 + sd * 5, 5), (8 + sd * 4, 6)): s.put(x, y, 'p')
    h = Spr(VN, VN); ell(h, 8, 5.7, 3.6, 3.3, 'S'); h = shade_gen(h, 'S', 'M', 'W'); merge(s, h)
    s.put(8, 8, 'H'); s.put(9, 8, 'W')                                                                              # a single fang
    if kind == 'pushed':                                                                                            # goggles up on the brow, the eyes bare and bright
        s.hline(5, 4, 7, 'n')
        for cx in (6, 10): s.rect(cx - 1, 3, 3, 2, 'a'); s.put(cx, 3, 'b'); s.put(cx, 4, 'b'); s.put(cx - 1, 3, 'H')
        for cx in (6, 10): s.put(cx, 6, 'y'); s.put(cx, 7, 'N')
    else:
        s.hline(4, 5, 9, 'n')
        for cx in (6, 10):
            s.rect(cx - 1, 5, 3, 3, 'a'); s.put(cx, 6, 'b'); s.put(cx - 1, 5, 'H'); s.put(cx + 1, 7, 'W')
        s.put(8, 6, 'n')
    if kind == 'helmet':                                                                                            # a hard hat made from a bucket, with a lamp
        hh = Spr(VN, VN); ell(hh, 8, 4.4, 3.8, 2.6, 'B'); hh = cv2.shade_edges(hh); merge(s, hh)
        s.hline(4, 6, 9, 'C'); s.put(8, 2, 'y'); s.put(7, 3, 'a'); s.put(9, 3, 'a')
        s.put(5, 7, 'W'); s.put(11, 7, 'W')
    return s
RA_HEADS = ['goggles', 'pushed', 'helmet']

def ra_hand(s, x, y):
    s.rect(x - 1, y - 1, 2, 2, 'u'); s.put(x - 1, y - 1, 'a'); s.put(x, y, 'n')                                     # an oversized rust leather glove
def ra_arms(pose):
    s = Spr(SN, SN); A = s_anchors()[pose]
    sh_l, sh_r = s_rel(-4, 0), s_rel(4, 0)
    limb(s, sh_l, A['hand_l'], 2, 'S', 'M', 'W'); limb(s, sh_r, A['hand_r'], 2, 'S', 'M', 'W')
    for k in ('hand_l', 'hand_r'): ra_hand(s, *A[k])
    s.put(sh_l[0], sh_l[1] + 1, 'B'); s.put(sh_r[0], sh_r[1] + 1, 'C')
    return s

class Rattler(Species):
    id = 'rattler'
    N = SN; C = SC
    walk_fps = 9
    kind = 'small'
    head_names = RA_HEADS
    notes = ('Rattler: scrap gremlins who live in Rusthold\'s walls. THE SMALL RIG (kind "small": 25x25, pivot (12,12)): legs, torso and every head stay inside the central '
             '15x15 (pivot +-7), so the body fits the 1x1 cell of the trait `body` 1 and a 1-wide crawlspace; only the thin arms reach beyond it, out to the shared mounts '
             '(the human\'s, moved by (-4,-4): item top-left = mount - item.grip as everywhere; hand anchors are art only). Gunmetal-grey skin, two huge pink-lined ears, '
             'brass goggles with blue glass, rust leather gloves and boots, a tool belt that bristles with a wrench, a screwdriver and a hammer. Head variants: goggles (over '
             'the eyes), pushed (goggles up on the brow, bright eyes), helmet (a bucket hard hat with a lamp, tinted). Outfit mask = the overalls, the knee patches, the hard hat.')
    def legs(self): return [outlined(lift(ra_leg_frame(*w), SN, 4)) for w in V_WALK] + [outlined(lift(ra_leg_frame(1, -1), SN, 4))]
    def torso(self): return outlined(lift(ra_torso(), SN, 4))
    def arms(self, pose): return outlined(ra_arms(pose))
    def head(self, name): return outlined(lift(ra_head(name), SN, 4))
    def torso_anchors(self): return {'head': [SC, SC - 3], 'back': [SC, SC + 4], 'shoulder_l': [SC - 4, SC], 'shoulder_r': [SC + 4, SC]}
    def arm_anchors(self): return s_anchors()


# ================================================================== TESSELLATE: a runaway Concord repair swarm that woke up (standard rig, plus a small 1x1 half)
# A person-shaped swarm of tiny repair bots: every bot is a 2x2 block of steel (L lit, M, S, W) with a 1 px GAP of floor between neighbours, so the figure is
# a lattice (pitch 3): a few bots carry a cyan status light (c) or an amber work lamp (a), the eyes are two lit bots, a row of bots in the outfit colour is a
# sash, and a couple of strays hover off the silhouette. The outline is drawn round the OUTSIDE only (swarm_outline: a 1 px gap between two bots stays open, the
# floor shows through), so nothing is filled in. The torso glow (2 frames) is the status lights chasing each other.
# TESSELLATE_HALF is the 1x1 "split" body (trait `split_on_death`): the SMALL rig (25x25, pivot (12,12)), the same bots in a 4x4 lattice (about half of them).
BOT = {
 'a': ('LM', 'MS'), 'b': ('MS', 'SW'), 'c': ('cM', 'MS'), 'd': ('aM', 'MS'), 'e': ('Hc', 'cM'), 'h': ('HL', 'LM'), 'f': ('SW', 'WE'),
 'o': ('AB', 'BC'), 'O': ('BB', 'CC'),
}
def bot(s, x, y, k='a'):
    p = BOT[k]
    for j in (0, 1):
        for i in (0, 1): s.put(x + i, y + j, p[j][i])
def swarm_kind(i, j):
    k = (i * 5 + j * 3 + abs(i * j)) % 7
    return 'b' if k < 2 else 'c' if k == 2 else 'd' if k == 3 else 'a'
def swarm_outline(s):
    """a 1 px dark outline round the OUTSIDE of a swarm: a gap of one px between two bots (open on both sides) counts as inside, so it stays transparent."""
    mask = {(x, y) for y in range(s.h) for x in range(s.w) if s.g[y][x] != '.'}
    filled = set(mask)
    for y in range(s.h):
        for x in range(s.w):
            if (x, y) in mask: continue
            if ((x - 1, y) in mask and (x + 1, y) in mask) or ((x, y - 1) in mask and (x, y + 1) in mask): filled.add((x, y))
    for (x, y) in filled:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in filled and 0 <= q[0] < s.w and 0 <= q[1] < s.h: s.g[q[1]][q[0]] = 'K'
def swarm_outlined(s):
    n = s.copy()
    if cv2.OUTLINE: swarm_outline(n)
    return n
def PREVIEW_HOOK(name):
    """the preview compositor outlines every rotated layer with outline_all; a swarm needs its own outline (the export uses swarm_outlined)."""
    import sp_compose
    if name.startswith('tessellate'): sp_compose.outline_all = swarm_outline

# ---- the full swarm (normal rig): bot (i, j) has its top-left at (15 + 3i, 15 + 3j), so bot (0, 0) sits on the pivot
def tb(i, j): return (15 + 3 * i, 15 + 3 * j)
def t_chain(s, start, end, kinds=('a', 'b'), n=None):
    """a trail of bots from the bot whose top-left is `start` toward the point `end` (the hand): a step of 3 px along the longer axis (a gap of 1 px between
    neighbours), the last bot lit (the hand) and the one before it in the outfit colour."""
    dx, dy = end[0] - 1 - start[0], end[1] - 1 - start[1]
    m = max(abs(dx), abs(dy), 1); n = n if n is not None else max(1, int(round(m / 3.0)))
    for k in range(n + 1):
        x = start[0] + dx / float(m) * 3.0 * k; y = start[1] + dy / float(m) * 3.0 * k
        kind = 'h' if k == n else 'o' if k == n - 1 and n > 2 else kinds[k % len(kinds)]
        bot(s, int(round(x)), int(round(y)), kind)
def t_leg_frame(dl, dr, lift_l=False, lift_r=False):
    """legs under the torso (which ends at y 22): the foot bots show below it; a leg that swings back is a trail of 2-3 bots, one swinging forward hides under the body."""
    s = Spr(N, N)
    for cx, d, lift in ((12, dl, lift_l), (18, dr, lift_r)):
        back = max(0, int(round(-d / 3.0)))
        for m in range(back + 1):
            bot(s, cx + (1 if lift and m == back and m > 0 else 0), 24 + 3 * m, 'f' if m == back else swarm_kind(cx, m + 8))
        if d > 1: bot(s, cx, 18, 'f')                                      # a foot swinging forward, mostly under the body
    return s
T_ROWS = {-1: range(-2, 3), 0: range(-2, 3), 1: range(-2, 3), 2: range(-1, 2)}
def t_torso():
    s = Spr(N, N)
    for j, cols in T_ROWS.items():
        for i in cols:
            x, y = tb(i, j)
            kind = 'o' if j == 1 else swarm_kind(i, j)
            if j == 1 and i == 0: kind = 'O'
            bot(s, x, y, kind)
    bot(s, tb(3, 1)[0] + 1, tb(3, 1)[1] + 2, 'c'); bot(s, tb(-3, 2)[0], tb(-3, 2)[1] + 1, 'd')              # two strays hovering off the body
    return s
T_HEADS = ['swarm', 'visor', 'helmet']
def t_head(kind):
    s = Spr(N, N)
    for j in (-3, -2):
        for i in (-1, 0, 1):
            x, y = tb(i, j)
            k = 'a' if (i + j) % 2 else 'b'
            if kind == 'swarm' and j == -2 and i != 0: k = 'e'
            if kind == 'visor' and j == -2: k = 'e'
            if kind == 'helmet':
                k = 'o' if j == -3 else ('e' if i == 0 else 'b')
            bot(s, x, y, k)
    if kind == 'swarm': bot(s, tb(0, -4)[0] + 1, tb(0, -4)[1] + 2, 'h')                                      # one bot floating above like an antenna
    return s
def t_arms(pose):
    s = Spr(N, N); A = pose_anchors((6, 21), (26, 21))[pose]
    for sd, k in ((-1, 'hand_l'), (1, 'hand_r')):
        st = tb(3 * sd, -1)
        t_chain(s, st, (st[0] + 1, st[1] + 10) if pose == 'unarmed' else A[k], n=3 if pose == 'unarmed' else None)
    return s
def t_torso_glow(kind_rows, frames, cvt):
    out = []
    for f in (0, 1):
        g = ng(frames)
        pts = [cvt(i, j) for (i, j) in kind_rows if (i + j) % 2 == f]
        glow_px_max(g, pts, (60, 242, 255), (0.55, 0.55)[f], 2.6, 1.5)
        out.append(g)
    return out
T_LIGHTS = [(i, j) for j, cols in T_ROWS.items() for i in cols if swarm_kind(i, j) == 'c' and j != 1] + [(-1, 0), (1, 0), (0, 2)]

class Tessellate(Species):
    id = 'tessellate'
    walk_fps = 8
    glow_fps = 3
    head_names = T_HEADS
    notes = ('Tessellate: a runaway Concord repair swarm that woke up (standard rig). A person-shaped swarm of tiny bots: each bot is a 2x2 block of steel with a 1 px GAP '
             'of floor between neighbours (pitch 3), a few with a cyan status light or an amber work lamp, the eyes two lit bots, a sash of bots in the outfit colour, and a '
             'couple of strays hovering off the body. The outline is drawn round the outside of the swarm only, so the gaps between bots stay open (floor shows through). '
             'Arms and legs are trails of bots. torso_glow (2 frames, ~3 fps) is the status lights chasing each other. Head variants: swarm (default, one bot floating above), '
             'visor (a lit strip), helmet (a tinted crown of bots). Outfit mask = the sash and the bot before each hand. `tessellate_half` is the 1x1 body it splits into.')
    def legs(self): return [swarm_outlined(t_leg_frame(*w)) for w in walk_cycle(10, 6)] + [swarm_outlined(t_leg_frame(-1, -1))]
    def torso(self): return swarm_outlined(t_torso())
    def arms(self, pose): return swarm_outlined(t_arms(pose))
    def head(self, name): return swarm_outlined(t_head(name))
    def torso_anchors(self): return {'head': [16, 9], 'back': [16, 22], 'shoulder_l': [6, 13], 'shoulder_r': [25, 13]}
    def arm_anchors(self): return pose_anchors((6, 21), (26, 21))
    def torso_glow(self): return t_torso_glow(T_LIGHTS, N, lambda i, j: (tb(i, j)[0], tb(i, j)[1]))

# ---- the half (small rig): a 4x4 lattice, bot (i, j) at (7 + 3i, 7 + 3j) on the 25x25 frame (x and y 7..17: the interior is pivot +-5)
def hb(i, j): return (7 + 3 * i, 7 + 3 * j)
def h_leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(SN, SN)
    for ci, d in ((1, dl), (2, dr)):
        bot(s, hb(ci, 0)[0], 16 if d <= 1 else 13, 'f')                       # the foot below the body; one swinging forward hides under it
    return s
H_ROWS = {1: (0, 1, 2, 3), 2: (1, 2)}                                          # the torso rows of the lattice; row 0 is the head, row 3 the feet
def h_torso():
    s = Spr(SN, SN)
    for j, cols in H_ROWS.items():
        for i in cols:
            x, y = hb(i, j)
            bot(s, x, y, 'o' if j == 2 else swarm_kind(i, j))
    return s
H_HEADS = ['swarm', 'visor', 'helmet']
def h_head(kind):
    s = Spr(SN, SN)
    for i in (1, 2):
        x, y = hb(i, 0)
        bot(s, x, y, 'o' if kind == 'helmet' else 'e')
    return s
def h_arms(pose):
    s = Spr(SN, SN); A = s_anchors()[pose]
    for sd, k in ((0, 'hand_l'), (3, 'hand_r')):
        st = hb(sd, 1)
        t_chain(s, st, (st[0] + 1, st[1] + 5) if pose == 'unarmed' else A[k], n=1 if pose == 'unarmed' else None)
    return s
H_LIGHTS = [(i, j) for j, cols in H_ROWS.items() for i in cols if swarm_kind(i, j) == 'c'] or [(1, 1), (2, 2)]
class TessellateHalf(Species):
    id = 'tessellate_half'
    N = SN; C = SC
    walk_fps = 9
    glow_fps = 3
    kind = 'small'
    head_names = H_HEADS
    notes = ('Tessellate, split in two: the 1x1 body a Tessellate becomes at `split_on_death` (THE SMALL RIG: kind "small", 25x25, pivot (12,12)). The same 2x2 bots with 1 px gaps '
             'as the full swarm, in a 4x4 lattice (about half of the bots: a two-bot head, a four-bot shoulder row, a sash row). Legs, torso and head stay inside the central '
             '15x15 (pivot +-7); only the short bot trails of the arms reach the shared mounts (item top-left = mount - item.grip as everywhere; hand anchors are art only). '
             'Same head variants and outfit mask as `tessellate`. The outline is round the outside of the swarm only.')
    def legs(self): return [swarm_outlined(h_leg_frame(*w)) for w in V_WALK] + [swarm_outlined(h_leg_frame(1, -1))]
    def torso(self): return swarm_outlined(h_torso())
    def arms(self, pose): return swarm_outlined(h_arms(pose))
    def head(self, name): return swarm_outlined(h_head(name))
    def torso_anchors(self): return {'head': [SC, SC - 4], 'back': [SC, SC + 4], 'shoulder_l': [SC - 5, SC - 1], 'shoulder_r': [SC + 5, SC - 1]}
    def arm_anchors(self): return s_anchors()
    def torso_glow(self): return t_torso_glow(H_LIGHTS, SN, hb)


# ================================================================== SABLE: lean boarding-crew families in long dark coats, a cutter torch strapped to each forearm (standard rig)
# A long charcoal coat (E lit W, shade D) with narrow shoulders, a high collar and tails that flare behind; a bandolier and a collar lining (the tinted outfit);
# a cutter fuel tank on the back with hoses; a lean dark-furred head (n, lit q) with a cream muzzle and amber eyes. The torches are steel tubes on the outside of
# each forearm, nozzle at the hand end, with a small blue-white flame (b, c, H) that always burns forward along the arm: they are the one bright thing on the figure.
SA_BOOT = {
 'plant': art("""
.nn.
nqnn
nnnn
.nn.
"""),
 'lift': art("""
.nn.
nqnn
nnnn
nnnn
.nn.
"""),
}
def sa_leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift in ((12, dl, lift_l), (20, dr, lift_r)):
        fy = 16 - d
        step = -1 if fy < 16 else 1
        ys = list(range(16, fy + step, step))
        t = Spr(N, N)
        for y in ys: t.hline(lx - 1, y, 3, 'D')
        merge(s, shade_gen(t, 'D', 'E', 'K'))
        if len(ys) > 5: s.put(lx, ys[len(ys) // 2], 'W')                                           # a worn knee
        b = SA_BOOT['lift' if lift else 'plant']
        s.stamp(lx - 2, fy - len(b) // 2 - (1 if fy < 16 else 0), b)
    return s
SA_WALK = walk_cycle(12, 6)
def sa_torso():
    s = Spr(N, N)
    c = Spr(N, N); poly(c, [(11, 17), (21, 17), (22, 26), (10, 26)], 'E'); ell(c, 16, 16, 6.4, 4.3, 'E'); merge(s, shade_gen(c, 'E', 'W', 'D'))
    for y in range(14, 26): s.put(16, y, 'D')                                                       # the back vent seam
    s.put(16, 26, 'K'); s.put(15, 25, 'D'); s.put(17, 25, 'D')
    for (x0, y0) in ((13, 21), (19, 21)):
        for y in range(y0, y0 + 4, 2): s.put(x0, y, 'D')                                          # folds in the tails
    # the cutter's fuel tank on the back, left, with a valve and hoses to both shoulders
    tk = Spr(N, N); tk.rect(11, 19, 4, 7, 'S'); tk = shade_gen(tk, 'S', 'M', 'W'); merge(s, tk)
    s.put(12, 19, 'o'); s.put(13, 19, 'o'); s.hline(11, 22, 4, 'W')
    for (x, y) in ((13, 18), (12, 17), (11, 16), (10, 15), (9, 15)): s.put(x, y, 'q')              # the hose up over the left shoulder
    for (x, y) in ((14, 18), (15, 17), (17, 17), (19, 16), (21, 15), (22, 15)): s.put(x, y, 'q')   # and across to the right
    # the bandolier (outfit): from the left shoulder down across the back, a row of amber cartridges
    bl = Spr(N, N); seg(bl, 10, 15, 21, 25, 2, 'B'); merge(s, cv2.shade_edges(bl))
    for k in range(1, 5): s.put(round(10 + 11 * k / 5.0), round(15 + 10 * k / 5.0) + 1, 'a')
    s.hline(11, 23, 10, 'W'); s.put(16, 23, 'a')                                                    # the belt and its buckle
    # the collar, high, lined in the outfit colour
    cl = Spr(N, N); ell(cl, 16, 14, 5.8, 2.8, 'B'); merge(s, cv2.shade_edges(cl)); ell(s, 16, 14.2, 4.4, 1.9, 'D')
    return s
SA_HEADS = ['bare', 'hood', 'helmet']
def sa_head(kind):
    s = Spr(N, N)
    if kind == 'hood':
        hd = Spr(N, N); ell(hd, 16, 11, 5.4, 5.8, 'E'); merge(s, shade_gen(hd, 'E', 'W', 'D'))
        for y in range(N):
            for x in range(N):
                if ((x - 16) / 3.2) ** 2 + ((y - 10.6) / 3.9) ** 2 <= 1.0: s.erase(x, y)
        for y in range(13, 17): s.put(16, y, 'D')
    for sd in (-1, 1):
        if kind != 'hood': ell(s, 16 + sd * 3.6, 9.2, 1.6, 1.8, 'n'); s.put(int(round(16 + sd * 3.6)), 9, 'q')                           # ears
    h = Spr(N, N); ell(h, 16, 11.4, 3.5, 5.0, 'n'); h = shade_gen(h, 'n', 'q', 'D')
    for y in range(N):
        for x in range(N):
            if h.g[y][x] != '.' and (kind != 'hood' or s.g[y][x] == '.'): s.g[y][x] = h.g[y][x]
    sn = Spr(N, N); ell(sn, 16, 7.8, 1.6, 1.9, 'f'); merge(s, shade_gen(sn, 'f', 'H', 'Q'))                                # the cream muzzle
    s.put(16, 5, 'D')
    for ex in (13, 18): s.put(ex, 10, 'y'); s.put(ex + (1 if ex < 16 else -1), 10, 'a')                                      # amber eyes
    s.put(16, 12, 'q'); s.put(15, 13, 'q'); s.put(17, 13, 'q')
    if kind == 'helmet':                                                                                                      # a breacher's helm: steel dome, a visor slit, a lamp, a tinted chin strap
        hm = Spr(N, N); ell(hm, 16, 10.5, 5.3, 5.6, 'S'); merge(s, shade_gen(hm, 'S', 'L', 'W'))
        s.hline(12, 10, 9, 'D'); s.hline(13, 11, 7, 'D'); s.put(14, 10, 'y'); s.put(18, 10, 'y')
        s.rect(15, 6, 3, 2, 'W'); s.put(16, 6, 'y'); s.hline(11, 14, 3, 'B'); s.hline(19, 14, 3, 'C'); s.put(11, 13, 'B'); s.put(21, 13, 'C')
    return s

def sa_torch(s, a, b, sd):
    """a cutter torch on the outside of the forearm a -> b: a steel tube, a nozzle at the hand end and a small flame burning on along the arm."""
    L = math.hypot(b[0] - a[0], b[1] - a[1]) or 1.0
    ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    nx, ny = -uy, ux                                                                        # the normal; make it point outwards (away from the body's middle)
    if nx * sd < 0: nx, ny = -nx, -ny
    p0 = (a[0] + ux * L * 0.3 + nx * 2.6, a[1] + uy * L * 0.3 + ny * 2.6); p1 = (a[0] + ux * L * 0.8 + nx * 2.6, a[1] + uy * L * 0.8 + ny * 2.6)
    t = Spr(N, N); seg(t, round(p0[0]), round(p0[1]), round(p1[0]), round(p1[1]), 2, 'S'); merge(s, shade_gen(t, 'S', 'M', 'W'))
    s.put(round(p1[0]), round(p1[1]), 'M')
    for k, c in ((1.6, 'H'), (2.6, 'c'), (3.6, 'b')): s.put(round(p1[0] + ux * k), round(p1[1] + uy * k), c)
def sa_hand(s, x, y):
    s.rect(x - 1, y - 1, 2, 3, 'n'); s.put(x - 1, y - 1, 'q'); s.put(x, y + 1, 'D')                                  # a dark-furred hand
def sa_arm(s, a, b, sd):
    t = Spr(N, N); seg(t, a[0], a[1], b[0], b[1], 3, 'E'); merge(s, shade_gen(t, 'E', 'W', 'D'))
    sa_torch(s, a, b, sd)
    cuff(s, a, b, 0.93, 'B', 'C', 3)
def sa_arms(pose):
    s = Spr(N, N); A = pose_anchors((6, 21), (26, 21))[pose]
    if pose == 'unarmed':
        sa_arm(s, (10, 16), (6, 21), -1); sa_arm(s, (22, 16), (26, 21), 1); sa_hand(s, 6, 22); sa_hand(s, 26, 22)
        return s
    for sh, k, sd in (((10, 16), 'hand_l', -1), ((22, 16), 'hand_r', 1)):
        sa_arm(s, sh, (A[k][0], A[k][1] + 1), sd); sa_hand(s, *A[k])
    return s

class Sable(Species):
    id = 'sable'
    walk_fps = 8
    head_names = SA_HEADS
    notes = ('Sable: lean boarding-crew families (standard rig). A long charcoal coat with narrow shoulders, a high collar and tails that flare behind, a bandolier of amber '
             'cartridges and the collar lining (the tinted outfit), a cutter fuel tank on the back with hoses over the shoulders, and long-striding dark legs. A lean dark-furred head '
             'with a cream muzzle and amber eyes. A cutter torch is strapped to the outside of each forearm (a steel tube, a nozzle at the hand end) with a small blue-white flame '
             'burning forward along the arm in every pose (hard pixels, no glow layer). Head variants: bare, hood (the coat\'s hood), helmet (a breacher\'s helm with a lamp). '
             'Outfit mask = the bandolier, the collar lining, the cuffs, the helm\'s chin strap.')
    def legs(self): return [outlined(sa_leg_frame(*w)) for w in SA_WALK] + [outlined(sa_leg_frame(1, -1))]
    def torso(self): return outlined(sa_torso())
    def arms(self, pose): return outlined(sa_arms(pose))
    def head(self, name): return outlined(sa_head(name))
    def torso_anchors(self): return {'head': [16, 11], 'back': [16, 24], 'shoulder_l': [10, 16], 'shoulder_r': [22, 16]}
    def arm_anchors(self): return pose_anchors((6, 21), (26, 21))


# ================================================================== QUILLBACK: spined, proud Clan duellists (standard rig)
# Warm brown fur (q lit Q, shade n); the whole back is a fan of long banded quills (cream f and dark n, a pale tip H) that lie swept back at rest (in the torso layer);
# in the `melee` arm pose they FLARE: the arms layer carries a full sunburst of longer quills round the sides and back (the drawer draws the arms over the torso, so the
# flare opens over the resting fan; the forward 80 degrees stay clear, so the head and the weapon are not hidden). A duelist's cravat and epaulettes (the tinted outfit),
# a short crest of quills over the brow, a pointed snout, amber eyes, claw hands.
QB_PATTERN = 'nqnnfffnnfffnnn'      # a quill by distance from the fan's centre (r - 2): a dark root mass, then cream and dark bands; the last pixel is a pale tip
def qb_quill(s, cx, cy, deg, r0, L):
    a = math.radians(deg); sx, sy = math.sin(a), math.cos(a)
    for r in range(r0, L + 1):
        c = 'H' if r == L else QB_PATTERN[min(len(QB_PATTERN) - 1, r - 2)]
        s.put(int(round(cx + r * sx)), int(round(cy + r * sy)), c)
def qb_fan(s, cx, cy, lo, hi, step, r0, Lmax, Lmin, span):
    degs = list(range(lo, hi + 1, step))
    for deg in sorted(degs, key=lambda d: -abs(d)):
        L = int(round(Lmax - (Lmax - Lmin) * min(1.0, abs(deg) / float(span))))
        qb_quill(s, cx, cy, deg, r0, L)
QB_BOOT = {
 'plant': art("""
..f.f.f..
.qqqqqqq.
qqQqqqqqn
.nnnnnnn.
"""),
 'lift': art("""
..f.f.f..
.qqqqqqq.
qqQqqqqqn
qqqqqqqqn
.nnnnnnn.
"""),
}
def qb_leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for lx, d, lift in ((12, dl, lift_l), (20, dr, lift_r)):
        fy = 16 - d
        step = -1 if fy < 16 else 1
        ys = list(range(16, fy + step, step))
        t = Spr(N, N)
        for y in ys: t.hline(lx - 2, y, 5, 'q')
        merge(s, shade_gen(t, 'q', 'Q', 'n'))
        if len(ys) > 4:
            wy = ys[len(ys) * 3 // 4]; s.hline(lx - 2, wy, 5, 'B'); s.hline(lx - 2, wy + (1 if step < 0 else -1), 5, 'C')       # an ankle wrap (outfit)
        b = QB_BOOT['lift' if lift else 'plant']
        s.stamp(lx - 4, fy - len(b) // 2 - (2 if fy < 16 else 0), b)
    return s
def qb_torso():
    s = Spr(N, N)
    b = Spr(N, N); ell(b, 16, 16, 8.2, 5.0, 'q'); merge(s, shade_gen(b, 'q', 'Q', 'n'))
    qb_fan(s, 16, 16, -75, 75, 10, 2, 13, 8, 75)                                                  # the resting fan of quills, swept back
    for deg in (-52, -26, 0, 26, 52):                                                           # a few short ones in front of them, fur-coloured at the root
        a = math.radians(deg); s.put(int(round(16 + 3 * math.sin(a))), int(round(16 + 3 * math.cos(a))), 'Q')
    for sd in (-1, 1):                                                                            # epaulettes (outfit) on the shoulders
        e = Spr(N, N); e.rect(16 + sd * 8 - 2, 13, 4, 4, 'B'); merge(s, cv2.shade_edges(e)); s.put(16 + sd * 8, 14, 'a')
    cv = Spr(N, N); ell(cv, 16, 14.5, 5.6, 2.8, 'B'); merge(s, cv2.shade_edges(cv)); ell(s, 16, 14.7, 3.8, 1.6, 'n')     # the cravat, round the neck
    for x in range(12, 21, 2): s.put(x, 17, 'A')
    return s
QB_HEADS = ['crest', 'helmet', 'scarred']
def qb_head(kind):
    s = Spr(N, N)
    for sd in (-1, 1): ell(s, 16 + sd * 3.8, 10.4, 1.5, 1.7, 'q'); s.put(int(round(16 + sd * 3.8)), 10, 'Q')                      # ears
    h = Spr(N, N); ell(h, 16, 11.4, 4.1, 5.0, 'q'); merge(s, shade_gen(h, 'q', 'Q', 'n'))
    sn = Spr(N, N); ell(sn, 16, 7.6, 2.0, 2.6, 'Q'); merge(s, shade_gen(sn, 'Q', 'f', 'q')); s.put(16, 5, 'K'); s.put(15, 5, 'n'); s.put(17, 5, 'n')   # the pointed snout
    for ex in (13, 19): s.put(ex, 10, 'y'); s.put(ex, 11, 'n'); s.hline(ex - 1 if ex < 16 else ex, 9, 2, 'n')                    # amber eyes under a stern brow
    for y in range(8, 13): s.put(16, y, 'f' if y % 2 else 'n')                                  # a crest of short quills along the crown, swept back
    for (dx, y) in ((-2, 9), (2, 9), (-3, 11), (3, 11), (-2, 12), (2, 12)): s.put(16 + dx, y, 'f' if (y + dx) % 2 else 'n')
    if kind == 'scarred':
        for (x, y) in ((12, 9), (13, 10), (14, 11)): s.put(x, y, 'f')
        s.put(11, 8, 'n')
    if kind == 'helmet':                                                                         # a duelist's open steel cap with a tinted band, the quills coming through the top
        c = Spr(N, N); ell(c, 16, 10, 4.6, 3.8, 'S'); merge(s, shade_gen(c, 'S', 'L', 'W'))
        s.hline(11, 11, 11, 'B'); s.hline(11, 12, 11, 'C'); s.put(11, 11, 'A'); s.put(12, 11, 'A')
        for dx in (-2, 0, 2): s.put(16 + dx, 6, 'f'); s.put(16 + dx, 7, 'n')
    return s
def qb_claw(s, x, y):
    s.rect(x - 1, y - 1, 3, 3, 'q'); s.put(x - 1, y - 1, 'Q'); s.put(x + 1, y + 1, 'n')
    for dx in (-1, 0, 1): s.put(x + dx, y - 2, 'f')                                              # three cream claws, forward
def qb_arm(s, a, b):
    t = Spr(N, N); seg(t, a[0], a[1], b[0], b[1], 4, 'q'); merge(s, shade_gen(t, 'q', 'Q', 'n'))
    cuff(s, a, b, 0.8, 'B', 'C', 4)
def qb_arms(pose):
    s = Spr(N, N); A = pose_anchors((6, 21), (26, 21))[pose]
    if pose == 'melee':                                                                          # THE FLARE: the quills open into a sunburst round the back and sides
        qb_fan(s, 16, 16, -145, 145, 9, 3, 16, 10, 145)
    if pose == 'unarmed':
        qb_arm(s, (9, 16), (6, 21)); qb_arm(s, (23, 16), (26, 21)); qb_claw(s, 6, 22); qb_claw(s, 26, 22)
        return s
    for sh, k in (((9, 16), 'hand_l'), ((23, 16), 'hand_r')):
        qb_arm(s, sh, (A[k][0], A[k][1] + 1)); qb_claw(s, *A[k])
    return s

class Quillback(Species):
    id = 'quillback'
    walk_fps = 7
    head_names = QB_HEADS
    notes = ('Quillback: spined, proud Clan duellists (standard rig). Warm brown fur; the back is a fan of long banded quills (cream and dark, a pale tip) that lie swept back '
             'at rest (the torso layer). THE FLARE is a pose of the arms layer: in the `melee` pose (their sidearm, the ember knife, is a melee weapon) the arms layer also carries a '
             'full sunburst of longer quills round the back and sides (the forward 80 degrees stay clear). The drawer draws arms over the torso and the item and head over the arms, so '
             'the flare opens over the resting fan without hiding the weapon or the face. The torso layer is one frame (the validator and the drawer take one), so this is the way a '
             'drawer shows the flare without code: pick the melee pose. A duelist\'s cravat and epaulettes (the tinted outfit), a crest of short quills over the brow, a pointed snout, '
             'amber eyes, claw hands, bare clawed feet. Head variants: crest, helmet (an open steel cap with a tinted band), scarred. Outfit mask = the cravat, the epaulettes, the '
             'cuffs and ankle wraps, the cap band.')
    def legs(self): return [outlined(qb_leg_frame(*w)) for w in walk_cycle(10, 5)] + [outlined(qb_leg_frame(1, -1))]
    def torso(self): return outlined(qb_torso())
    def arms(self, pose): return outlined(qb_arms(pose))
    def head(self, name): return outlined(qb_head(name))
    def torso_anchors(self): return {'head': [16, 11], 'back': [16, 26], 'shoulder_l': [9, 16], 'shoulder_r': [23, 16]}
    def arm_anchors(self): return pose_anchors((6, 21), (26, 21))


# ================================================================== KITE: drift-nomads born in zero-g (standard rig)
# Long thin periwinkle limbs (b lit L, shade j), a slim ribbed body with a cream belly, huge round amber eyes (a dark pupil and a glint) in a small head with swept-back
# fins, three long gripping toes and fingers, and a long prehensile tail with a hooked tip that curls behind (it lives in the legs layer and sways with the walk).
# Outfit = a cross-harness over the chest and a neck scarf with two ends.
KT_FOOT = {
 'plant': art("""
b.b.b
.bbb.
.bjb.
"""),
 'lift': art("""
b.b.b
.bbb.
.bbb.
.bjb.
"""),
}
def kt_tail(s, sw):
    """the prehensile tail: banded blue and navy, tapering, ending in a hook with a yellow tip (sw px of sideways sway at the end)."""
    pts = [(16, 22), (16 + sw // 3, 25), (16 + (sw * 2) // 3, 28), (16 + sw, 30)]
    t = Spr(N, N)
    for a, b in zip(pts, pts[1:]): seg(t, a[0], a[1], b[0], b[1], 2, 'b')
    merge(s, shade_gen(t, 'b', 'L', 'j'))
    ex = 16 + sw
    s.put(ex + 1, 31, 'b'); s.put(ex + 2, 31, 'j'); s.put(ex + 2, 30, 'y'); s.put(ex + 2, 29, 'y')            # the hook, curling forward, with a yellow tip
    for (x, y) in ((16 + sw // 3, 25), (16 + (sw * 2) // 3, 28)): s.put(x, y, 'j')                          # bands
def kt_leg_frame(dl, dr, lift_l=False, lift_r=False, sw=0):
    s = Spr(N, N)
    kt_tail(s, sw)
    for lx, d, lift in ((12, dl, lift_l), (20, dr, lift_r)):
        fy = 16 - d
        step = -1 if fy < 16 else 1
        ys = list(range(16, fy + step, step))
        t = Spr(N, N)
        for y in ys: t.hline(lx, y, 2, 'b')
        merge(s, shade_gen(t, 'b', 'L', 'j'))
        if len(ys) > 5: s.put(lx, ys[len(ys) // 2], 'j')                                                      # a knuckle
        b = KT_FOOT['lift' if lift else 'plant']
        s.stamp(lx - 2, fy - len(b) // 2 - (1 if fy < 16 else 0), b)
    return s
KT_WALK = [(10, -10, False, False, 3), (5, -5, False, True, 1), (-5, 5, False, True, -1), (-10, 10, False, False, -3), (-5, 5, True, False, -1), (5, -5, True, False, 1)]
def kt_torso():
    s = Spr(N, N)
    b = Spr(N, N); ell(b, 16, 15, 6.6, 3.2, 'b'); ell(b, 16, 19, 4.4, 5.6, 'b'); merge(s, shade_gen(b, 'b', 'L', 'j'))
    for y in (17, 19, 21, 23): s.hline(14, y, 5, 'j')                                                        # ribs
    s.hline(15, 18, 3, 'f'); s.hline(15, 20, 3, 'f'); s.hline(15, 22, 3, 'f')
    for i in range(7): s.put(11 + i, 13 + i, 'A'); s.put(12 + i, 13 + i, 'B')                                # the cross-harness (outfit)
    for i in range(7): s.put(21 - i, 13 + i, 'A'); s.put(20 - i, 13 + i, 'C')
    sc = Spr(N, N); ell(sc, 16, 13.5, 4.4, 2.0, 'B'); merge(s, cv2.shade_edges(sc))                          # the neck scarf and its two ends
    s.put(18, 15, 'B'); s.put(19, 16, 'C'); s.put(14, 15, 'B'); s.put(13, 16, 'C')
    s.put(16, 24, 'j'); s.put(15, 24, 'j'); s.put(17, 24, 'j')
    return s
KT_HEADS = ['wide', 'goggles', 'helmet']
def kt_head(kind):
    s = Spr(N, N)
    for sd in (-1, 1):                                                                                       # fins swept back from the head
        poly(s, [(16 + sd * 3, 10), (16 + sd * 7, 12), (16 + sd * 5, 14), (16 + sd * 3, 13)], 'j')
        s.put(16 + sd * 6, 12, 'b')
    h = Spr(N, N); ell(h, 16, 11, 4.4, 4.6, 'b'); merge(s, shade_gen(h, 'b', 'L', 'j'))
    s.put(16, 7, 'f'); s.put(15, 8, 'f'); s.put(17, 8, 'f'); s.put(16, 6, 'N')                              # a tiny snout
    for ex in (13, 19):                                                                                      # huge eyes: amber ring, dark pupil, a glint
        ell(s, ex, 10.5, 2.5, 2.7, 'y'); ell(s, ex, 10.8, 1.5, 1.7, 'N'); s.put(ex - 1 if ex < 16 else ex, 9, 'H')
    if kind == 'goggles':                                                                                    # flight goggles round the eyes, a tinted strap
        for ex in (13, 19):
            for dx, dy in ((-3, 0), (3, 0), (0, -3), (0, 3), (-2, -2), (2, -2), (-2, 2), (2, 2)): s.put(ex + dx, 10 + dy + (1 if dy >= 0 and False else 0), 'B' if dx <= 0 else 'C')
        s.hline(10, 11, 3, 'B'); s.hline(20, 11, 3, 'C'); s.put(16, 10, 'B'); s.put(16, 11, 'C')
        for ex in (13, 19): s.put(ex + 1, 8, 'c')
    if kind == 'helmet':                                                                                     # a soft flight cap with ear flaps
        c = Spr(N, N); ell(c, 16, 8.6, 4.8, 2.8, 'B'); merge(s, cv2.shade_edges(c))
        for sd in (-1, 1): s.rect(16 + sd * 5 - 1, 9, 2, 5, 'B' if sd < 0 else 'C')
        s.hline(12, 9, 9, 'C')
        for ex in (13, 19): ell(s, ex, 11.4, 2.5, 2.2, 'y'); ell(s, ex, 11.6, 1.5, 1.4, 'N'); s.put(ex - 1 if ex < 16 else ex, 10, 'H')
    return s
def kt_hand(s, x, y):
    s.put(x, y, 'b'); s.put(x - 1, y - 1, 'b'); s.put(x + 1, y - 1, 'b'); s.put(x - 1, y - 2, 'L'); s.put(x, y - 2, 'L'); s.put(x + 1, y - 2, 'L')    # three long fingers
    s.put(x, y + 1, 'j'); s.put(x + 1, y, 'j')
def kt_arm(s, a, b):
    t = Spr(N, N); seg(t, a[0], a[1], b[0], b[1], 2, 'b'); merge(s, shade_gen(t, 'b', 'L', 'j'))
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    s.put(a[0] + round((b[0] - a[0]) * 0.55), a[1] + round((b[1] - a[1]) * 0.55), 'j')                       # an elbow
    cuff(s, a, b, 0.85, 'B', 'C', 3)
KT_UNARMED = ((3, 23), (29, 23))                                                                           # in zero-g the arms drift out wide
def kt_arms(pose):
    s = Spr(N, N); A = pose_anchors(*KT_UNARMED)[pose]
    if pose == 'unarmed':
        kt_arm(s, (9, 15), (4, 22)); kt_arm(s, (23, 15), (28, 22)); kt_hand(s, 3, 23); kt_hand(s, 29, 23)
        return s
    for sh, k in (((9, 15), 'hand_l'), ((23, 15), 'hand_r')):
        kt_arm(s, sh, (A[k][0], A[k][1] + 1)); kt_hand(s, *A[k])
    return s

class Kite(Species):
    id = 'kite'
    walk_fps = 8
    head_names = KT_HEADS
    notes = ('Kite: drift-nomads born in zero-g (standard rig). Long thin periwinkle limbs, a slim ribbed body with a cream belly, a small head with swept-back fins and huge round '
             'amber eyes, three long gripping toes and fingers, and a long prehensile tail with a hooked yellow tip behind (in the legs layer: it sways with the walk). The unarmed arms '
             'drift out wide. Head variants: wide, goggles (flight goggles with a tinted strap), helmet (a soft flight cap with ear flaps, tinted). Outfit mask = the cross-harness, '
             'the neck scarf, the cuffs, the goggle straps, the cap.')
    def legs(self): return [outlined(kt_leg_frame(*w[:4], sw=w[4])) for w in KT_WALK] + [outlined(kt_leg_frame(1, -1, sw=0))]
    def torso(self): return outlined(kt_torso())
    def arms(self, pose): return outlined(kt_arms(pose))
    def head(self, name): return outlined(kt_head(name))
    def torso_anchors(self): return {'head': [16, 11], 'back': [16, 22], 'shoulder_l': [9, 15], 'shoulder_r': [23, 15]}
    def arm_anchors(self): return pose_anchors(*KT_UNARMED)

SPECIES = [Revenant, Choir, Rattler, Tessellate, TessellateHalf, Sable, Quillback, Kite]
