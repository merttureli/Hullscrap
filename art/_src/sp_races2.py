"""Race wave 2 crew rigs (docs/waves/races_2_4.md): VELLUM (the small rig), OORTH, DRAKKIN (the large rig), WISP and LANTERN (floating rigs), HULLKIN.
One module, no new palette colours: every letter already exists (pal_lines / pal_races1 register the navy, cyan and violet ones). The layers,
animations and item mounts are the shared rig's. Rig kinds are fixed by art/README.md "Crew" (crew.json `kind`; PersonDrawer.RIGS):
  * normal (Oorth, Hullkin): 33x33 frame, pivot (16,16);
  * LARGE (Drakkin): 49x49, pivot (24,24), the art overhangs the 2x2 body, like the Grundl;
  * SMALL (Vellum): 25x25, pivot (12,12), the 1x1 body of the trait `body` 1: legs, torso and head inside the central 15x15 (pivot +-7), only the arms
    reach beyond it, out to the shared mounts;
  * FLOATING (Wisp, Lantern): 49x49, pivot (24,24), no walk: the `legs` layer is the trailing tail (drawn pointing back, down at rotation 0), its
    `float` animation is played by time and `stand` is the idle frame; the body (torso, head, arms) is the normal body in the middle of the frame
    and the drawer bobs it, so no bob is baked into any frame.
In EVERY kind the arms `mount` anchors are the human's moved by pivot - (16,16), so any item fits any body.
Outfit symbols A/B/C = light/base/dark (tint mask); B and C are NOT the neon cyans here, Y and z are (pal_races1)."""
import math
from sp_common import *
import pal_races1     # noqa: F401  (registers the private cyan letters Y / z)

# ---------------------------------------------------------------- shared drawing helpers
def inside(pts, x, y):
    """is pixel (x, y) in the polygon? Coordinates are PIXEL INDICES (pixel i has its centre at i, so a shape symmetric about the pivot pixel stays
    symmetric); a pixel exactly on an edge counts as inside (ray cast, tried half a hair either side)."""
    for ex in (-1e-6, 1e-6):
        px, py = x + ex, y + 1e-4; n = len(pts); c = False
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            if (y0 > py) != (y1 > py) and px < (x1 - x0) * (py - y0) / float(y1 - y0) + x0: c = not c
        if c: return True
    return False
def poly(s, pts, c):
    ys = [p[1] for p in pts]; xs = [p[0] for p in pts]
    for y in range(max(0, int(min(ys))), min(s.h, int(max(ys)) + 1)):
        for x in range(max(0, int(min(xs))), min(s.w, int(max(xs)) + 1)):
            if inside(pts, x, y): s.put(x, y, c)
def line(s, a, b, c):
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    for i in range(n + 1): s.put(a[0] + round((b[0] - a[0]) * i / n), a[1] + round((b[1] - a[1]) * i / n), c)
def ell(s, cx, cy, rx, ry, c):
    """filled ellipse centred on pixel (cx, cy) (pixel indices, may be x.5 for a centre between pixels)."""
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0: s.put(x, y, c)
def seg(s, x0, y0, x1, y1, w, c):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
        for j in range(w):
            for k in range(w): s.put(x - w // 2 + k, y - w // 2 + j, c)
def merge(dst, src):
    for y in range(dst.h):
        for x in range(dst.w):
            if src.g[y][x] != '.': dst.g[y][x] = src.g[y][x]
def shade(s, base, hi, lo):
    """shade_gen applied in place to every `base` pixel of `s` (top-left light)."""
    t = shade_gen(s, base, hi, lo)
    for y in range(s.h):
        for x in range(s.w): s.g[y][x] = t.g[y][x]
def limb(s, a, b, w, base, hi, lo):
    """a shaded thick line a -> b drawn over `s` (a fresh layer is shaded, then merged, so existing pixels are not re-shaded)."""
    t = Spr(s.w, s.h); seg(t, a[0], a[1], b[0], b[1], w, base); merge(s, shade_gen(t, base, hi, lo))

def lift(s, n, d):
    """a sprite drawn on a smaller frame, placed on an n x n frame with its top-left at (d, d): the body of a floating rig drawn on the 33x33 frame
    goes to the middle of the 49x49 one (d = 8), the small rig's torso and head from 17x17 to 25x25 (d = 4)."""
    o = Spr(n, n); o.stamp(d, d, s.rows()); return o
def lift_glow(g, n, d):
    o = Rgba(n, n); o.blit_rgba(g, d, d); return o
def ng(n): return Rgba(n, n)

def walk_cycle(a, b):
    """the 6-frame walk with foot offsets (a = reach, b = half reach): the same phases as every other rig."""
    return [(a, -a, False, False), (b, -b, False, True), (-b, b, False, True), (-a, a, False, False), (-b, b, True, False), (b, -b, True, False)]

# ================================================================== VELLUM: folded paper-folk. THE SMALL RIG (25x25, pivot (12,12))
# Cream paper (f lit planes H, shade planes M, creases S), ink-mark eyes (N), star-chart lines (j) and a gold star dot (y): they are folded
# from salvaged star charts. Outfit = a paper sash (tinted) and the cap.
VN = 17; VC = 8                      # the body is drawn on a 17x17 grid round (8,8), then lifted onto the 25x25 frame (+4,+4): torso and head stay in pivot +-7
SN = 25; SC = 12
def planes(n, shape, tones, base='f'):
    """a sprite of the polygon `shape` filled with `base`, then each (polygon, tone) of `tones` painted only where the shape is."""
    s = Spr(n, n); poly(s, shape, base)
    for pts, c in tones:
        t = Spr(n, n); poly(t, pts, c)
        for y in range(n):
            for x in range(n):
                if t.g[y][x] != '.' and s.g[y][x] != '.': s.g[y][x] = t.g[y][x]
    return s

V_BOOT = {
 'plant': art("""
.H.
ffM
.MS
"""),
 'lift': art("""
.H.
ffM
ffM
.MS
"""),
}
V_LX = (3, 12)        # left column of each 2-wide leg strip: out at the sides, so the stride shows under the kite
def v_leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(VN, VN)
    for lx, d, lift, side in ((V_LX[0], dl, lift_l, -1), (V_LX[1], dr, lift_r, 1)):
        fy = 8 - d                                          # boot centre row (forward = up)
        step = -1 if fy < 8 else 1
        ys = list(range(8, fy + step, step))
        for y in ys: s.put(lx, y, 'H'); s.put(lx + 1, y, 'M')
        if len(ys) > 3:
            wy = ys[len(ys) * 2 // 3]; s.put(lx, wy, 'B'); s.put(lx + 1, wy, 'C')              # an ankle band (outfit)
        b = V_BOOT['lift' if lift else 'plant']
        s.stamp(lx - 1 if side < 0 else lx, fy - len(b) // 2 - (1 if fy < 8 else 0), b)
    return s
V_WALK = walk_cycle(3, 2)                                   # short steps: legs stay inside the central 15x15

V_SHAPE = [(8, 4), (14, 8), (12, 11), (8, 14), (4, 11), (2, 8)]
def v_torso():
    """a kite of folded planes: sharp shoulder corners, a vertical crease, diagonal folds, a hanging tab."""
    s = planes(VN, V_SHAPE, [([(0, 0), (8, 0), (8, 17), (0, 17)], 'H'), ([(8, 9), (17, 9), (17, 17), (8, 17)], 'M'),
                             ([(0, 9), (8, 9), (8, 17), (0, 17)], 'f')])
    line(s, (8, 5), (8, 13), 'S')                                                                   # the centre crease
    line(s, (8, 5), (13, 8), 'S'); line(s, (8, 5), (3, 8), 'M')                                     # the shoulder folds
    s.put(4, 9, 'S'); s.put(12, 9, 'S')
    # the sash (outfit), a knot on the right with a hanging tail
    s.hline(4, 10, 9, 'B'); s.hline(4, 11, 9, 'C'); s.put(12, 12, 'B'); s.put(12, 13, 'C')
    # the star chart printed on the paper: a navy line of ink and a gold star dot on each shoulder
    s.put(10, 7, 'j'); s.put(11, 7, 'j'); s.put(12, 8, 'j'); s.put(5, 7, 'y'); s.put(11, 6, 'y'); s.put(6, 8, 'j')
    return s

V_HEAD = [(8, 3), (11, 6), (11, 7), (8, 10), (5, 7), (5, 6)]
def v_head(kind):
    s = planes(VN, V_HEAD, [([(0, 0), (8, 0), (8, 17), (0, 17)], 'H'), ([(8, 8), (17, 8), (17, 17), (8, 17)], 'M')])
    line(s, (8, 4), (8, 9), 'S')
    if kind == 'fold':
        s.put(8, 3, 'M')                                                                 # the peak fold
    elif kind == 'cap':                                                                 # a folded boat-hat across the brow (outfit)
        s.hline(6, 5, 5, 'A'); s.hline(7, 4, 3, 'B'); s.put(8, 3, 'B'); s.hline(5, 6, 7, 'C')
    else:                                                                               # an origami helmet with a visor slit
        s.hline(6, 5, 5, 'M'); s.hline(7, 4, 3, 'M'); s.put(8, 3, 'S'); s.hline(5, 6, 7, 'N')
    if kind != 'helmet':
        for x in (6, 10): s.put(x, 6, 'N'); s.put(x, 7, 'N')                              # ink-mark eyes
    else:
        s.put(6, 7, 'N'); s.put(10, 7, 'N'); s.put(6, 6, 'H'); s.put(10, 6, 'H')
    return s

def s_hand(s, x, y):
    s.put(x, y, 'f'); s.put(x - 1, y, 'H'); s.put(x, y - 1, 'H'); s.put(x + 1, y, 'M'); s.put(x, y + 1, 'M')    # a pointed paper mitt
def s_rel(dx, dy): return (SC + dx, SC + dy)
# hand targets (pivot-relative): the human's, with the reach clamped to 11 px ahead so the hand and its outline stay in the frame. Art only: the MOUNTS are the human's.
S_HANDS = {'unarmed': ((-6, 3), (6, 3)),
           'pistol': ((-2, -11), (2, -11)), 'rifle': ((1, -11), (5, -7)), 'tool': ((-3, -7), (5, -11)), 'heavy': ((-2, -11), (5, -4)), 'melee': ((-4, -9), (7, -8))}
def s_anchors():
    """the pose anchors: mounts = the human's moved by (-4,-4); hands = S_HANDS."""
    out = pose_anchors(s_rel(*S_HANDS['unarmed'][0]), s_rel(*S_HANDS['unarmed'][1]), shift=SC - 16)
    for p in POSES[1:]: out[p]['hand_l'] = s_rel(*S_HANDS[p][0]); out[p]['hand_r'] = s_rel(*S_HANDS[p][1])
    return out
def s_arms(pose):
    """long thin paper arms from the kite's shoulder corners out to the hands (they may reach beyond the central 15x15, up to the mounts)."""
    s = Spr(SN, SN); A = s_anchors()[pose]
    sh_l, sh_r = s_rel(-5, -1), s_rel(5, -1)
    limb(s, sh_l, A['hand_l'], 2, 'f', 'H', 'M'); limb(s, sh_r, A['hand_r'], 2, 'f', 'H', 'M')
    for k in ('hand_l', 'hand_r'): s_hand(s, *A[k])
    s.put(sh_l[0], sh_l[1] + 1, 'B'); s.put(sh_r[0], sh_r[1] + 1, 'C')                  # a tinted cuff at each shoulder
    return s

class Vellum(Species):
    id = 'vellum'
    N = SN; C = SC
    walk_fps = 8
    kind = 'small'
    head_names = ['fold', 'cap', 'helmet']
    notes = ('Vellum: folded paper-folk, THE SMALL RIG (kind "small": 25x25, pivot (12,12)). Legs, torso and head stay inside the central 15x15 (pivot +-7), so the '
             'body fits the 1x1 cell of the trait `body` 1 and a 1-wide crawlspace; only the long thin paper arms reach beyond it, out to the shared mounts '
             '(the human\'s, moved by (-4,-4): item top-left = mount - item.grip as everywhere; hand anchors are art only). Cream paper with lit and shade planes, '
             'creases, ink-mark eyes, a star-chart line and a gold star dot. Head variants: fold, cap (a boat-hat, tinted), helmet. '
             'Outfit mask = sash, shoulder and ankle bands, the cap.')
    def legs(self): return [outlined(lift(v_leg_frame(*w), SN, 4)) for w in V_WALK] + [outlined(lift(v_leg_frame(1, -1), SN, 4))]
    def torso(self): return outlined(lift(v_torso(), SN, 4))
    def arms(self, pose): return outlined(s_arms(pose))
    def head(self, name): return outlined(lift(v_head(name), SN, 4))
    def torso_anchors(self): return {'head': [SC, SC - 2], 'back': [SC, SC + 4], 'shoulder_l': [SC - 5, SC - 1], 'shoulder_r': [SC + 5, SC - 1]}
    def arm_anchors(self): return s_anchors()

# ================================================================== OORTH: tall, still and hooded telepaths; a glowing third-eye ridge (standard rig)
# Deep indigo mantle and hood (N/I/J/j), a long robe with a train and long bell sleeves (the outfit, tinted), lilac-grey skin (X/V/Z) with long
# fingers, a bone ridge on the brow with the third eye in it (head_glow pulses it, cyan with a white heart). The train, the pointed hood and the
# narrow shoulders are the "tall" read from above.
O_TRAIN = [5, 5, 5, 6, 6, 6, 7, 7, 7, 7, 7, 7, 6, 6, 5, 4, 3, 2, 1]       # half-widths of the train, y 12..30: a flared bell that ends in a point
def o_train(s, sway):
    """the robe's train behind the body (it lives in the legs layer, so it follows the way they walk): a flared bell, pleats, a navy hem."""
    for j, hw in enumerate(O_TRAIN):
        y = 12 + j; t = j / 18.0
        cx = 16 + int(round(sway * t * t))
        for x in range(cx - hw, cx + hw + 1):
            c = 'B'
            if x == cx - hw: c = 'A'
            elif x >= cx + hw - 1: c = 'C'
            elif (x - cx) in (-3, 0, 3) and 14 < y < 26: c = 'C' if y % 4 else 'A'                 # pleats, broken
            s.put(x, y, c)
        if y >= 26:
            for x in range(cx - hw, cx + hw + 1): s.put(x, y, 'I' if (x + y) % 2 else 'N')    # the navy hem band
        elif y == 25:
            for x in range(cx - hw, cx + hw + 1): s.put(x, y, 'a' if (x - cx) % 3 == 0 else 'C')   # a thread of gold above the band
O_TOE = {
 'plant': art("""
.X.
XXV
XVV
"""),
 'lift': art("""
.X.
XXV
XXV
XVV
"""),
}
def o_leg_frame(dl, dr, lift_l=False, lift_r=False, sway=0):
    s = Spr(N, N)
    o_train(s, sway)
    for lx, d, lift in ((12, dl, lift_l), (19, dr, lift_r)):
        fy = 12 - d
        if fy < 12:                                              # the toe peeks out from under the hem only when it reaches forward
            b = O_TOE['lift' if lift else 'plant']
            s.stamp(lx - 1, fy - len(b) // 2 - 1, b)
    return s
O_WALK = [(7, -7, False, False, 3), (4, -4, False, True, 1), (-4, 4, False, True, -1), (-7, 7, False, False, -3), (-4, 4, True, False, -1), (4, -4, True, False, 1)]

O_MANTLE = [(12, 20), (10, 22), (9, 23), (8, 24), (8, 24), (8, 24), (8, 24), (8, 24), (9, 23), (10, 22), (12, 20), (13, 19)]   # y 10..21
def o_torso():
    s = Spr(N, N)
    for j, (x0, x1) in enumerate(O_MANTLE): s.hline(x0, 10 + j, x1 - x0 + 1, 'J')
    shade(s, 'J', 'j', 'I')
    for y in range(12, 21): s.put(16, y, 'N')                                                   # the back seam
    for (x, y) in ((11, 13), (12, 14), (21, 13), (20, 14), (13, 18), (19, 18)): s.put(x, y, 'I')      # drape folds
    for (x, y) in ((10, 12), (9, 13), (11, 11)): s.put(x, y, 'j')
    # a stole down the back and a band along each shoulder (outfit)
    for y in range(13, 22): s.put(15, y, 'A'); s.put(16, y, 'B'); s.put(17, y, 'C')
    s.put(15, 22, 'B'); s.put(16, 23, 'C'); s.put(17, 22, 'C'); s.put(16, 22, 'B')
    for x in range(9, 15): s.put(x, 11 + (14 - x) // 3, 'B')
    for x in range(18, 24): s.put(x, 11 + (x - 18) // 3, 'B')
    # a sigil on the mantle: the third eye, small, in violet
    s.put(16, 17, 'X'); s.put(15, 18, 'V'); s.put(17, 18, 'V')
    return s

O_HOOD_R = [(4, 4), (5, 5), (6, 6), (6, 6), (6, 6), (5, 5), (5, 5), (4, 4), (4, 4), (3, 3), (3, 3), (2, 2), (1, 1), (1, 1), (0, 0)]  # half-widths y 8..22
def o_hood(kind):
    s = Spr(N, N)
    if kind == 'bare':                                          # the hood pushed back: a long smooth skull and the ridge, the hood a roll at the nape
        ell(s, 16, 13, 5, 6.5, 'X'); shade(s, 'X', 'L', 'V')
        for (x, y) in ((11, 13), (21, 13), (12, 17), (20, 17)): s.put(x, y, 'V')
        t = Spr(N, N)
        for y in range(18, 24):
            hw = 7 - (y - 18) // 2
            t.hline(16 - hw, y, 2 * hw + 1, 'J')
        shade(t, 'J', 'j', 'I'); merge(s, t)
    else:
        for j, hw in enumerate((x for x, _ in O_HOOD_R)): s.hline(16 - O_HOOD_R[j][0] - 1, 8 + j, 2 * O_HOOD_R[j][0] + 3, 'J')
        shade(s, 'J', 'j', 'I')
        for y in range(17, 22): s.put(16, y, 'N')                                              # the hood's seam running down to its tip
        s.put(16, 22, 'I')
        # the opening: dark, with the pale face inside
        ell(s, 16, 11, 3.6, 3.0, 'N')
        ell(s, 16, 11, 2.6, 2.4, 'V')
        s.put(14, 10, 'N'); s.put(18, 10, 'N')                                                  # the two ordinary eyes
        s.hline(15, 13, 3, 'Z')
    # the brow ridge: a bone ridge with the third eye set in it (the glow layer lights it)
    s.put(16, 8 if kind == 'bare' else 9, 'V'); s.put(16, 9 if kind == 'bare' else 10, 'Z')
    for y in ((8, 9) if kind == 'bare' else (9, 10)): s.put(16, y, 'H')
    if kind == 'bare':
        s.put(14, 10, 'N'); s.put(18, 10, 'N'); s.hline(15, 13, 3, 'Z')
    if kind == 'helmet':                                                                        # a pressure hood: a glass visor over the opening
        ell(s, 16, 11, 4.2, 3.4, 'b'); ell(s, 16, 11, 3.2, 2.5, 'N'); s.put(14, 9, 'H'); s.put(15, 9, 'L'); s.put(14, 10, 'L')
        s.put(16, 9, 'H'); s.put(16, 10, 'c')
        for x in (11, 21): s.put(x, 11, 'S')
    return s
O_HEADS = ['hood', 'bare', 'helmet']

def o_sleeve(s, a, b, w0=4):
    """a bell sleeve: tapers from the shoulder a to the cuff b, in outfit cloth, with a flared cuff."""
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    t = Spr(N, N)
    for i in range(n + 1):
        x = a[0] + round((b[0] - a[0]) * i / n); y = a[1] + round((b[1] - a[1]) * i / n)
        w = max(3, w0 - i * 2 // max(1, n // 2))
        for j in range(w):
            for k in range(w): t.put(x - w // 2 + k, y - w // 2 + j, 'B')
    t = shade_gen(t, 'B', 'A', 'C'); merge(s, t)
    x, y = b
    s.hline(x - 2, y, 5, 'C'); s.hline(x - 2, y - 1, 5, 'A'); s.put(x - 2, y - 1, 'B'); s.put(x + 2, y - 1, 'B')         # the flared cuff
def o_hand(s, x, y):
    s.rect(x - 1, y - 2, 3, 3, 'X'); s.put(x + 1, y, 'V'); s.put(x, y, 'V'); s.put(x - 1, y - 3, 'X'); s.put(x + 1, y - 3, 'V')   # two long fingers, forward
def o_arms(pose):
    s = Spr(N, N); A = pose_anchors((13, 12), (19, 12))[pose]
    if pose == 'unarmed':
        # the sleeves folded across the chest, the hands hidden inside (only the finger tips show)
        o_sleeve(s, (8, 14), (17, 12)); o_sleeve(s, (24, 14), (15, 13))
        s.put(18, 11, 'X'); s.put(14, 12, 'X'); s.put(18, 12, 'V')
        return s
    for sh, k in (((8, 14), 'hand_l'), ((24, 14), 'hand_r')):
        o_sleeve(s, sh, (A[k][0], A[k][1] + 2))
        o_hand(s, *A[k])
    return s

class Oorth(Species):
    id = 'oorth'
    walk_fps = 5
    head_names = O_HEADS
    glow_fps = 2
    notes = ('Oorth: tall, still and hooded telepaths (standard rig). Deep indigo mantle and a pointed hood, narrow shoulders, a long robe with a '
             'flared train that sways with the walk (it lives in the legs layer) and long bell sleeves; only a toe tip shows when they step. Lilac-grey '
             'skin, long fingers, a bone ridge on the brow with the third eye set in it: head_glow has 2 pulse frames per variant (alternate at ~2 fps). '
             'Head variants: hood (default), bare (the hood pushed back), helmet (a pressure hood with a visor). '
             'Outfit mask = the robe and train, the sleeves, the stole and the shoulder bands.')
    def legs(self): return [outlined(o_leg_frame(*w)) for w in O_WALK] + [outlined(o_leg_frame(1, -1, sway=0))]
    def torso(self): return outlined(o_torso())
    def arms(self, pose): return outlined(o_arms(pose))
    def head(self, name): return outlined(o_hood(name))
    def torso_anchors(self): return {'head': [16, 13], 'back': [16, 22], 'shoulder_l': [8, 14], 'shoulder_r': [24, 14]}
    def arm_anchors(self): return pose_anchors((13, 12), (19, 12))
    def head_glow(self):
        out = []
        for f in (0, 1):
            for nm in self.head_names:
                g = new_glow(); h = o_hood(nm)
                ys = (8, 9) if nm == 'bare' else (9, 10)
                glow_px_max(g, [(16, ys[0]), (16, ys[1])], (60, 242, 255), (0.8, 0.55)[f], (4.5, 3.5)[f], 1.4)
                glow_px_max(g, [(16, ys[1])], (244, 246, 248), 0.5, 2.0, 1.2)
                out.append(g)
        return out

# ================================================================== DRAKKIN: reptile pit-fighters. THE LARGE RIG (49x49, pivot (24,24)), like the Grundl
# A scaled hide in rust (u) with ochre (a) edge lights and ember shade (e/n), a lean wide-shouldered body with a ridge of bone plates down the spine,
# shoulder spurs, a head with a short blunt snout and a fan crest, cream claws, and a thick tail behind (it lives in the legs layer, so it follows
# the move direction and swishes with the walk). Outfit = a fighter's waist wrap, a chest strap, wrist and ankle wraps, the helmet.
DN = 49; DC = 24; DSH = DC - 16
def dR(dx, dy): return (DC + dx, DC + dy)
def hide(s, base='u'): return shade_gen(s, base, 'a', 'e')
def scales(s, only='u'):
    """a lattice of ochre scale highlights over the rust hide (only on pixels still `only`)."""
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] == only:
                if (x + 2 * y) % 7 == 0: s.g[y][x] = 'a'
                elif (x - y) % 6 == 0 and (x + y) % 2: s.g[y][x] = 'e'

D_FOOT = {
 'plant': art("""
f..f..f
uuuuuuu
uuuuuue
.uuuuee
..eeee.
"""),
 'lift': art("""
f..f..f
uuuuuuu
uuuuuue
uuuuuue
.uuuuee
..eeee.
"""),
}
D_LX = (DC - 7, DC + 7)
def d_tail(s, a):
    """the tail: from under the hips to a spiked tip, swinging a px sideways at the end."""
    for i, y in enumerate(range(DC + 4, DC + 24)):
        t = i / 19.0
        x = DC + int(round(a * t * t * 1.0))
        w = 9 if t < 0.2 else 8 if t < 0.4 else 6 if t < 0.65 else 4 if t < 0.85 else 2
        x0 = x - w // 2
        for k in range(w):
            c = 'u'
            if k == 0: c = 'a'
            elif k >= w - 2: c = 'e'
            if i % 4 == 3 and 0 < k < w - 1: c = 'e'                                           # a band every fourth row
            s.put(x0 + k, y, c)
        if t > 0.2 and t < 0.9 and i % 3 == 0: s.put(x, y, 'a')                                 # the ridge plates down its back
    tx = DC + int(round(a)); ty = DC + 24
    s.put(tx, ty, 'a'); s.put(tx, ty + 1, 'f'); s.put(tx - 1, ty, 'u'); s.put(tx + 1, ty, 'e')
def d_leg_frame(dl, dr, lift_l=False, lift_r=False, a=0):
    s = Spr(DN, DN)
    t = Spr(DN, DN); d_tail(t, a); merge(s, t)
    for cx, d, lift, side in ((D_LX[0], dl, lift_l, -1), (D_LX[1], dr, lift_r, 1)):
        fy = DC - d
        leg = Spr(DN, DN)
        leg.rect(cx - 4, DC - 3, 8, 6, 'u')                                                       # hip block under the torso
        step = -1 if fy < DC else 1
        ys = list(range(DC, fy + step, step))
        for i, y in enumerate(ys):
            w = 8 if i < len(ys) // 2 else 6
            leg.hline(cx - w // 2, y, w, 'u')
        leg = hide(leg); merge(s, leg)
        if len(ys) > 6:
            wy = ys[len(ys) * 3 // 4]                                                              # an ankle wrap (outfit)
            s.hline(cx - 3, wy, 6, 'B'); s.hline(cx - 3, wy + (1 if step < 0 else -1), 6, 'C'); s.put(cx - 3, wy, 'A')
            ky = ys[len(ys) // 2]; s.put(cx - 1, ky, 'a'); s.put(cx, ky + step, 'e')
        b = D_FOOT['lift' if lift else 'plant']
        s.stamp(cx - 3, fy - len(b) // 2 - (2 if fy < DC else 0), b)
    s.hline(DC - 9, DC - 2, 19, 'B'); s.hline(DC - 9, DC - 1, 19, 'C')                          # the waist wrap, hanging a little under the torso
    return s
D_WALK = [(13, -13, False, False, 3), (7, -7, False, True, 1), (-7, 7, False, True, -1), (-13, 13, False, False, -3), (-7, 7, True, False, -1), (7, -7, True, False, 1)]

D_GIRDLE = [(-7, 7), (-10, 10), (-12, 12), (-13, 13), (-13, 13), (-13, 13), (-13, 13), (-13, 13), (-13, 13), (-13, 13), (-12, 12), (-11, 11), (-9, 9),
            (-7, 7), (-6, 6)]                                                                        # dy -9..+5, then the hips
D_HIPS = [(-8, 8), (-8, 8), (-7, 7), (-7, 7), (-6, 6), (-5, 5)]                                      # dy +6..+11
def d_spans(s, y0, rows, c):
    for j, (a, b) in enumerate(rows): s.hline(DC + a, y0 + j, b - a + 1, c)
def d_torso():
    s = Spr(DN, DN)
    h = Spr(DN, DN); d_spans(h, DC - 9, D_GIRDLE, 'u'); d_spans(h, DC + 6, D_HIPS, 'u'); h = hide(h); merge(s, h)
    # shoulder spurs: bone-ochre spikes out and forward
    for sd in (-1, 1):
        t = Spr(DN, DN)
        poly(t, [(DC + sd * 12, DC - 7), (DC + sd * 18, DC - 8), (DC + sd * 13, DC - 2)], 'a')
        t = shade_gen(t, 'a', 'f', 'u'); merge(s, t)
        s.put(DC + sd * 18, DC - 8, 'f')
    # the ridge of bone plates down the spine: ochre plates, ember shadows
    for dy in range(-3, 14, 3):
        w = 3 if dy < 9 else 2
        s.hline(DC - w // 2, DC + dy, w, 'a'); s.hline(DC - w // 2, DC + dy + 1, w, 'u'); s.put(DC - w // 2, DC + dy, 'f'); s.put(DC + w // 2, DC + dy + 1, 'e')
    # dark bands across the back (a tiger-banded hide), either side of the spine, and old scars
    for dy in (-5, -1, 3):
        for dx in list(range(-10, -3)) + list(range(4, 11)):
            if s.get(DC + dx, DC + dy) == 'u' and (abs(dx) + dy) % 3 != 1: s.put(DC + dx, DC + dy, 'e')
    for (dx, dy) in ((6, -5), (7, -5), (7, -4)): s.put(DC + dx, DC + dy, 'f')                         # an old claw scar
    # a chest strap (outfit) over the shoulder, and a belt with a brass buckle
    for i in range(14):
        s.put(DC - 12 + i, DC - 6 + i, 'A'); s.put(DC - 11 + i, DC - 6 + i, 'B'); s.put(DC - 10 + i, DC - 6 + i, 'C')
    s.hline(DC - 12, DC + 6, 25, 'B'); s.hline(DC - 12, DC + 5, 25, 'A'); s.hline(DC - 12, DC + 7, 25, 'C')
    s.rect(DC - 1, DC + 5, 3, 3, 'a'); s.put(DC - 1, DC + 5, 'y'); s.put(DC + 1, DC + 7, 'u')
    return s

D_HEAD_R = [(2, 2), (2, 2), (3, 3), (3, 3), (4, 4), (5, 5), (6, 6), (6, 6), (6, 6), (6, 6), (5, 5), (4, 4), (3, 3)]       # dy -9..+3: a blunt snout, a broad skull
def d_crest(s):
    """the fan crest swept back over the neck: ember membrane, ochre ribs, cream tips (drawn first: the skull sits over its roots)."""
    tips = [-65, -33, 0, 33, 65]; vals = [-49, -16, 16, 49]
    pts = [(DC - 4, DC - 1)]
    for i, th in enumerate(tips):
        r = math.radians(th); pts.append((DC + 13.5 * math.sin(r), DC + 3 + 13.5 * math.cos(r) * 0.85))
        if i < len(vals):
            r = math.radians(vals[i]); pts.append((DC + 8.5 * math.sin(r), DC + 3 + 8.5 * math.cos(r) * 0.85))
    pts.append((DC + 4, DC - 1))
    poly(s, pts, 'e')
    for th in tips:
        r = math.radians(th)
        line(s, (DC, DC + 1), (round(DC + 12.5 * math.sin(r)), round(DC + 3 + 12.5 * math.cos(r) * 0.85)), 'u')
        s.put(round(DC + 13 * math.sin(r)), round(DC + 3 + 13 * math.cos(r) * 0.85), 'f')
    for th in (-33, 0, 33): r = math.radians(th); line(s, (DC, DC + 2), (round(DC + 10 * math.sin(r)), round(DC + 3 + 10 * math.cos(r) * 0.85)), 'a')
def d_head(kind):
    s = Spr(DN, DN)
    d_crest(s)
    sk = Spr(DN, DN)
    for j, (a, b) in enumerate(D_HEAD_R): sk.hline(DC - a, DC - 9 + j, a + b + 1, 'a')
    sk = shade_gen(sk, 'a', 'f', 'u'); merge(s, sk)                                                 # the head is ochre, lighter than the rust body
    for dx in (-1, 1): s.put(DC + dx, DC - 8, 'n')                                                  # nostrils
    for y in range(DC - 7, DC + 2):
        s.put(DC, y, 'u')                                                                           # a bony ridge down the snout and crown
        if y > DC - 4: s.put(DC - 1, y, 'u')
    s.hline(DC - 6, DC - 3, 5, 'e'); s.hline(DC + 2, DC - 3, 5, 'e')                                 # the brow ridges
    for sd in (-1, 1):                                                                              # slit eyes under the ridge: yellow, a dark pupil
        ex = DC + sd * 4
        s.put(ex, DC - 2, 'y'); s.put(ex + sd, DC - 2, 'y'); s.put(ex, DC - 1, 'n')
        s.put(DC + sd * 3, DC - 6, 'H'); s.put(DC + sd * 3, DC - 5, 'H')                             # teeth at the edge of the snout
    if kind == 'helmet':                                                                            # an iron-banded fighter's cap, the crest through the back
        s.hline(DC - 6, DC - 1, 13, 'B'); s.hline(DC - 6, DC, 13, 'C'); s.hline(DC - 5, DC - 2, 11, 'A')
        s.rect(DC - 1, DC - 6, 3, 5, 'S'); s.put(DC - 1, DC - 6, 'M'); s.put(DC, DC - 6, 'L'); s.put(DC + 1, DC - 2, 'W')
        for dx in (-5, 5): s.put(DC + dx, DC - 1, 'M')
    if kind == 'scarred':                                                                           # a scar across the snout and a notched brow
        for (dx, dy) in ((-3, -6), (-2, -5), (-1, -4)): s.put(DC + dx, DC + dy, 'f')
        s.put(DC + 4, DC - 3, 'n'); s.put(DC + 5, DC - 2, 'n')
    return s
D_HEADS = ['crest', 'helmet', 'scarred']

D_CLAW = art("""
f.f.f
.uuu.
uuuuu
uuuue
.eee.
""")
def d_hand(s, x, y, down=False): s.stamp(x - 2, y - 2, D_CLAW[::-1] if down else D_CLAW)
def d_arm(s, x0, y0, x1, y1):
    t = Spr(DN, DN); seg(t, x0, y0, x1, y1, 5, 'u'); t = hide(t); merge(s, t)
    n = max(abs(x1 - x0), abs(y1 - y0), 1); i = int(n * 0.66)
    x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
    s.rect(x - 2, y - 1, 5, 3, 'B'); s.hline(x - 2, y + 1, 5, 'C'); s.put(x - 2, y - 1, 'A')          # a wrist wrap (outfit)
def d_arms(pose):
    s = Spr(DN, DN); H = pose_anchors(dR(-20, 11), dR(20, 11), shift=DSH)[pose]
    if pose == 'unarmed':
        d_arm(s, DC - 13, DC - 3, DC - 19, DC + 6); d_arm(s, DC + 13, DC - 3, DC + 19, DC + 6)
        d_hand(s, *dR(-20, 11), down=True); d_hand(s, *dR(20, 11), down=True)
        return s
    L = {'pistol': (-13, -3, -2, -11), 'rifle': (-13, -3, 1, -15), 'tool': (-13, -3, -3, -7), 'heavy': (-13, -3, -2, -13), 'melee': (-13, -3, -4, -9)}[pose]
    Rr = {'pistol': (13, -3, 2, -11), 'rifle': (13, -3, 5, -7), 'tool': (13, -3, 5, -12), 'heavy': (13, -3, 5, -4), 'melee': (13, -3, 7, -8)}[pose]
    for (a, b, c, d) in (L, Rr): d_arm(s, DC + a, DC + b, DC + c, DC + d)
    for k in ('hand_l', 'hand_r'): d_hand(s, *H[k])
    return s

class Drakkin(Species):
    id = 'drakkin'
    N = DN; C = DC
    walk_fps = 7
    kind = 'large'
    head_names = D_HEADS
    notes = ('Drakkin: reptile pit-fighters on THE LARGE RIG: the frame is 49x49 with the pivot at (24,24) (the normal 2x2 body, 32 px, sits at the centre, its '
             'shadow and pathing stay there; the art overhangs it). Mounts and hands are the shared targets moved by (+8,+8), identical relative to the pivot, '
             'so every item fits (item top-left = mount - item.grip). A rust and ochre scaled hide, a ridge of bone plates down the spine, shoulder spurs, '
             'cream claws, a fan crest on a blunt-snouted head and a thick tail behind (in the legs layer: it swishes with the walk at 7 fps). Head variants: '
             'crest, helmet (an iron-banded cap, tinted), scarred. Outfit mask = waist wrap, chest strap, wrist and ankle wraps, the helmet band.')
    def legs(self): return [outlined(d_leg_frame(*w[:4], a=w[4])) for w in D_WALK] + [outlined(d_leg_frame(1, -1, a=1))]
    def torso(self): return outlined(d_torso())
    def arms(self, pose): return outlined(d_arms(pose))
    def head(self, name): return outlined(d_head(name))
    def torso_anchors(self): return {'head': [DC, DC - 2], 'back': [DC, DC + 12], 'shoulder_l': [DC - 13, DC - 3], 'shoulder_r': [DC + 13, DC - 3]}
    def arm_anchors(self): return pose_anchors(dR(-20, 11), dR(20, 11), shift=DSH)

# ================================================================== WISP: living current, a FLOATING rig (standard 33x33 frame, no legs)
# A body of braided ribbons of light (cyan c / Y / z, white hearts H, magenta sparks m) round a bright core, an orb of a head, ribbon arms that end in
# spark knots, and a trailing glow tail in the LEGS layer (two helix strands that narrow to a flicker; `walk` = the 6-frame float cycle: the helix
# turns and the tail sways, `stand` = the idle ripple). The tail follows the move direction. Outfit = a scrap-cloth scarf the current has caught
# (a chest band and a streamer behind): the only tinted part, so crews still tell apart.
def clear_under(g, spr, chars='ABC'):
    """no light over the tinted outfit pixels of `spr` (a glow would wash the cloth out)."""
    for (x, y) in spr_pts(spr, chars): g.p[y][x] = [0, 0, 0, 0]
    return g
FN = 49; FC = 24            # the floating rigs' frame and pivot; the body is drawn on the 33x33 grid and lifted to the middle (+8,+8)
W_TAIL_PH = [0.0, 1.05, 2.1, 3.15, 4.2, 5.25]      # helix phase per float frame (6 steps = one turn, so the loop closes)
def w_tail(s, ph, sway):
    """the glow tail on the 49x49 frame, from under the body (y 23) back to the frame edge (y 47): two helix strands that narrow to a flicker."""
    for y in range(FC - 1, FN):
        t = (y - (FC - 1)) / 24.0
        env = 4.6 * (1 - t) + 0.8
        cx = FC + sway * t * math.sin(ph + 2.0 * t)
        for strand in (0, 1):
            a = ph + 0.85 * (y - (FC - 1)) + strand * math.pi
            x = cx + env * math.sin(a); front = math.cos(a) > 0
            w = 2 if t < 0.8 else 1
            for k in range(w): s.put(int(round(x)) + k, y, 'c' if front else 'Y')
            if abs(math.sin(a)) < 0.18: s.put(int(round(x)), y, 'H')                          # a spark where the strands cross
        if t < 0.55 and y % 2 == 0: s.put(int(round(cx)), y, 'z')                              # the dark seam between them near the body
    s.put(int(round(FC + sway * math.sin(ph + 2.0))), FN - 1, 'm')                             # the flicker at the very end
def w_leg_frame(i):
    s = Spr(FN, FN)
    if i == 6: w_tail(s, 0.5, 1.0); return s                                                  # the idle frame
    w_tail(s, W_TAIL_PH[i], 3.0)
    return s

def w_torso():
    s = Spr(N, N)
    ell(s, 16, 16, 8.5, 7.0, 'z')
    for A, col, ph in ((-6.5, 'J', 0.0), (-3.5, 'Y', 0.8), (0.0, 'c', 1.6), (3.5, 'Y', 2.4), (6.5, 'J', 3.2)):       # the braided ribbons
        for y in range(8, 25):
            x = 16 + int(round(A * math.sin(math.pi * (y - 8) / 16.0 + 0.35 * math.sin(ph + y * 0.5))))
            if s.get(x, y) != '.': s.put(x, y, col); s.put(x + 1, y, col) if col == 'Y' and s.get(x + 1, y) != '.' else None
    for (x, y) in ((11, 13), (21, 12), (10, 18), (22, 19), (14, 22), (18, 22)): s.put(x, y, 'N')                  # dark gaps between ribbons
    for (x, y) in ((13, 11), (19, 11), (9, 15), (23, 15), (12, 20), (20, 21)): s.put(x, y, 'c')
    ell(s, 16, 20, 2.6, 2.2, 'c'); ell(s, 16, 20, 1.5, 1.2, 'H')                                                   # the core, low on the back so the head leaves it visible
    s.put(11, 16, 'm'); s.put(21, 17, 'm'); s.put(13, 23, 'm')                                                      # magenta sparks the lightning left
    # the scarf (outfit): a band round the back, knotted, and a streamer trailing behind
    s.hline(9, 18, 15, 'A'); s.hline(9, 19, 15, 'B'); s.hline(10, 20, 13, 'C')
    for j in range(8): s.put(22 - j // 4, 19 + j, 'B' if j % 2 else 'A'); s.put(23 - j // 4, 19 + j, 'C')
    return s

def w_head(kind):
    s = Spr(N, N)
    if kind == 'forked':                                                                # lightning tendrils sweeping back over the shoulders
        for sd in (-1, 1):
            pts = [(16 + sd * 3, 12), (16 + sd * 6, 13), (16 + sd * 7, 15), (16 + sd * 9, 16), (16 + sd * 8, 18), (16 + sd * 10, 19)]
            for a, b in zip(pts, pts[1:]): line(s, a, b, 'c')
            s.put(16 + sd * 10, 19, 'H')
    ell(s, 16, 13, 4.6, 4.4, 'c'); shade(s, 'c', 'H', 'Y')
    for sd in (-1, 1): s.put(16 + sd * 2, 12, 'z'); s.put(16 + sd * 2, 11, 'z')           # two dark eye marks
    s.put(16, 9, 'H'); s.put(15, 9, 'c'); s.put(17, 9, 'c')
    return s
W_HEADS = ['orb', 'forked']

def w_ribbon(s, a, b, bend):
    """a ribbon arm a -> b through a mid point pushed sideways by `bend`, 2 px thick, bright edge on the lit side."""
    mid = ((a[0] + b[0]) / 2.0 + bend, (a[1] + b[1]) / 2.0)
    mid = (int(round(mid[0])), int(round(mid[1])))
    t = Spr(N, N); seg(t, a[0], a[1], mid[0], mid[1], 2, 'c'); seg(t, mid[0], mid[1], b[0], b[1], 2, 'c')
    merge(s, shade_gen(t, 'c', 'H', 'Y'))
def w_knot(s, x, y):
    for (dx, dy, c) in ((0, 0, 'H'), (-1, 0, 'c'), (1, 0, 'Y'), (0, -1, 'c'), (0, 1, 'Y'), (0, -2, 'H')): s.put(x + dx, y + dy, c)    # a spark knot with a forward flick
def w_arms(pose):
    s = Spr(N, N); A = pose_anchors((6, 21), (26, 21))[pose]
    if pose == 'unarmed':
        w_ribbon(s, (8, 13), (6, 21), -2); w_ribbon(s, (24, 13), (26, 21), 2)
        w_knot(s, 6, 22); w_knot(s, 26, 22)
        return s
    for sh, k, bend in (((8, 13), 'hand_l', -3), ((24, 13), 'hand_r', 3)):
        w_ribbon(s, sh, A[k], bend); w_knot(s, *A[k])
    return s

class Wisp(Species):
    id = 'wisp'
    N = FN; C = FC
    kind = 'floating'; legs_anim = 'float'
    walk_fps = 8
    glow_fps = 4
    head_names = W_HEADS
    notes = ('Wisp: living current, a FLOATING rig (kind "floating": 49x49, pivot (24,24)). No walk: the legs layer is the trailing glow tail, drawn pointing '
             'back (down at rotation 0) and turned to the movement direction: two helix strands of light that narrow to a flicker and run to the frame edge. Its '
             '`float` animation (6 frames, 8 fps, a closed loop) plays by time; `stand` is the idle frame. The body (torso, head, arms) sits in the middle of the frame '
             'as a normal body and the drawer bobs it, so no bob is baked in. A body of braided ribbons round a bright core, ribbon arms ending in spark knots, an orb '
             'head with two dark eye marks (head variants: orb, forked = lightning tendrils over the shoulders). The mounts are the human\'s moved by (+8,+8). torso_glow '
             '(2 flicker frames at ~4 fps), head_glow and legs_glow (one frame per legs frame) are strong: the Wisp is mostly light. Outfit mask = the scrap-cloth scarf '
             '(chest band and streamer).')
    def legs(self): return [outlined(w_leg_frame(i)) for i in range(7)]
    def torso(self): return outlined(lift(w_torso(), FN, 8))
    def arms(self, pose): return outlined(lift(w_arms(pose), FN, 8))
    def head(self, name): return outlined(lift(w_head(name), FN, 8))
    def torso_anchors(self): return {'head': [FC, FC - 3], 'back': [FC, FC + 6], 'shoulder_l': [FC - 8, FC - 3], 'shoulder_r': [FC + 8, FC - 3]}
    def arm_anchors(self): return pose_anchors((6 + 8, 21 + 8), (26 + 8, 21 + 8), shift=8)
    def legs_glow(self):
        out = []
        for i in range(7):
            g = ng(FN); t = w_leg_frame(i)
            glow_px_max(g, spr_pts(t, 'cH'), (60, 242, 255), 0.5, 3.2, 1.5)
            glow_px_max(g, spr_pts(t, 'm'), (255, 79, 216), 0.6, 2.6, 1.5)
            out.append(g)
        return out
    def torso_glow(self):
        out = []
        for f in (0, 1):
            g = ng(33); t = w_torso()
            glow_px_max(g, spr_pts(t, 'cH'), (60, 242, 255), (0.3, 0.2)[f], 2.6, 1.5)
            glow_px_max(g, [(16, 20)], (244, 246, 248), (0.6, 0.4)[f], (5.0, 4.0)[f], 1.4)
            glow_px_max(g, spr_pts(t, 'm'), (255, 79, 216), (0.6, 0.4)[f], 2.8, 1.5)
            out.append(lift_glow(clear_under(g, t), FN, 8))
        return out
    def head_glow(self):
        out = []
        for f in (0, 1):
            for nm in self.head_names:
                g = ng(33); h = w_head(nm)
                glow_px_max(g, spr_pts(h, 'cH'), (60, 242, 255), (0.55, 0.4)[f], 3.2, 1.5)
                out.append(lift_glow(g, FN, 8))
        return out

# ================================================================== HULLKIN: barnacle-folk who live on the outside of old hulls (standard rig)
# A ridged shell back (a chiton: six curved plates, grooves W, lit ridges M/L, barnacle cones H, rust streaks and a flake of hull paint), soft pale-pink
# flesh (s/v/f) for the small grasping limbs, the side feet and the head, an eye on a stalk (off to one side so it never covers a held item).
# Outfit = a mooring-rope harness (a band round the shell, a strap and a hanging end).
H_SHELL = dict(zip(range(10, 30), [5, 7, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 8, 8, 7, 6, 4, 2]))        # the shell trails behind the head, y 10..29
H_FOOT = {
 'plant': art("""
s.s.s
sssss
.vvv.
"""),
 'lift': art("""
s.s.s
sssss
sssss
.vvv.
"""),
}
H_LX = (3, 27)                 # centre column of each side leg
def h_leg_frame(dl, dr, lift_l=False, lift_r=False):
    s = Spr(N, N)
    for cx, d, lift in ((H_LX[0], dl, lift_l), (H_LX[1], dr, lift_r)):
        fy = 16 - d
        step = -1 if fy < 16 else 1
        ys = list(range(16, fy + step, step))
        for y in ys: s.put(cx - 1, y, 's'); s.put(cx, y, 's'); s.put(cx + 1, y, 'v')
        s.hline(cx - 2, 15, 5, 'v'); s.hline(cx - 2, 16, 5, 'v')                                   # the stubby hip
        if len(ys) > 4:
            wy = ys[len(ys) * 2 // 3]; s.hline(cx - 1, wy, 3, 'B')                                  # a rope turn round the ankle (outfit)
        b = H_FOOT['lift' if lift else 'plant']
        s.stamp(cx - 2, fy - len(b) // 2 - (1 if fy < 16 else 0), b)
    return s
H_WALK = walk_cycle(7, 4)

def h_torso():
    s = Spr(N, N)
    for y, hw in H_SHELL.items(): s.hline(16 - hw, y, 2 * hw + 1, 'S')
    shade(s, 'S', 'M', 'W')
    # six curved plates: a groove between each, bowed to the rear, and a lit ridge down the middle of each plate
    for gy in (13, 16, 19, 22, 25):
        for x in range(8, 25):
            y = gy + int(round(1.4 * math.cos((x - 16) / 9.0 * math.pi / 2)))
            if s.get(x, y) in ('S', 'M'): s.put(x, y, 'W')
            if s.get(x, y - 1) == 'S' and x % 2: s.put(x, y - 1, 'M')
    for y in range(12, 28):
        if s.get(16, y) in ('S', 'M'): s.put(16, y, 'L' if y % 3 else 'M')                          # the dorsal ridge
    # barnacle cones: a pale ring and a dark mouth
    for (cx, cy) in ((10, 23), (22, 16), (20, 26), (12, 16)):
        for (dx, dy) in ((0, -1), (-1, 0), (1, 0), (0, 1)): s.put(cx + dx, cy + dy, 'H' if dx + dy < 0 else 'L')
        s.put(cx, cy, 'N')
    for (x, y) in ((8, 18), (24, 22), (14, 24), (18, 14), (12, 27)): s.put(x, y, 'L')                # small spat
    # rust streaks bleeding off the grooves, and a flake of the old hull paint
    for (x, y) in ((11, 17), (11, 18), (21, 20), (21, 21), (21, 22), (15, 26), (15, 27)): s.put(x, y, 'u')
    s.put(19, 18, 'a'); s.put(20, 18, 'a'); s.put(19, 19, 'u')
    # the mooring-rope harness (outfit): a band round the shell, a thin strap over one side, a hanging end
    s.hline(8, 20, 17, 'B'); s.hline(8, 21, 17, 'C')
    for i in range(7): s.put(9 + i, 12 + i, 'B')
    s.put(24, 22, 'B'); s.put(24, 23, 'B'); s.put(25, 24, 'C'); s.put(24, 24, 'C')
    return s

def h_head(kind):
    s = Spr(N, N)
    # the stalk first (the soft head sits over its root): one stalk off to the left, or one each side
    sides = ((-1,),) if kind == 'stalk' else ((-1,), (1,))
    for (sd,) in sides:
        pts = [(16 + sd * 2, 10), (16 + sd * 3, 8), (16 + sd * 4, 6), (16 + sd * 5, 4)]
        for a, b in zip(pts, pts[1:]): seg(s, a[0], a[1], b[0], b[1], 2, 's')
        ex, ey = 16 + sd * 5, 3
        ell(s, ex, ey, 2.4, 2.4, 'H'); s.put(ex, ey - 1, 'N'); s.put(ex + sd * 0, ey, 'N'); s.put(ex, ey + 1, 'L')
        s.put(ex - 1, ey - 2, 'L')
    h = Spr(N, N); ell(h, 16, 10, 4.6, 3.6, 'f'); shade(h, 'f', 'H', 'v'); merge(s, h)
    s.put(15, 7, 'N'); s.put(17, 7, 'N'); s.put(16, 8, 'v'); s.hline(14, 11, 5, 'v')                    # two feeding slits and a mouth line
    return s
H_HEADS = ['stalk', 'twin']

def h_claw(s, x, y):
    s.put(x - 1, y - 1, 'f'); s.put(x + 1, y - 1, 'f'); s.hline(x - 1, y, 3, 's'); s.put(x + 1, y, 'v'); s.put(x, y + 1, 'v')        # a two-prong pincer
def h_arm(s, a, b):
    t = Spr(N, N); seg(t, a[0], a[1], b[0], b[1], 2, 's'); merge(s, shade_gen(t, 's', 'f', 'v'))
def h_arms(pose):
    s = Spr(N, N); A = pose_anchors((6, 19), (26, 19))[pose]
    if pose == 'unarmed':
        h_arm(s, (8, 15), (6, 19)); h_arm(s, (24, 15), (26, 19)); h_claw(s, 6, 20); h_claw(s, 26, 20)
        return s
    for sh, k in (((8, 15), 'hand_l'), ((24, 15), 'hand_r')):
        h_arm(s, sh, A[k]); h_claw(s, *A[k])
    return s

class Hullkin(Species):
    id = 'hullkin'
    walk_fps = 5
    head_names = H_HEADS
    notes = ('Hullkin: barnacle-folk who live on the outside of old hulls (standard rig). A ridged shell back (six curved plates, barnacle cones, rust '
             'streaks), pale pink flesh for the small grasping limbs and the stubby side feet (a slow, wide crab-walk at 5 fps), and an eye on a stalk '
             'held off to one side so it never covers a held item. Head variants: stalk (default, one stalk on the left), twin (a stalk each side). '
             'Outfit mask = the mooring-rope harness (shell band, strap, hanging end) and the ankle turns.')
    def legs(self): return [outlined(h_leg_frame(*w)) for w in H_WALK] + [outlined(h_leg_frame(1, -1))]
    def torso(self): return outlined(h_torso())
    def arms(self, pose): return outlined(h_arms(pose))
    def head(self, name): return outlined(h_head(name))
    def torso_anchors(self): return {'head': [16, 11], 'back': [16, 24], 'shoulder_l': [8, 15], 'shoulder_r': [24, 15]}
    def arm_anchors(self): return pose_anchors((6, 19), (26, 19))

# ================================================================== LANTERN: moth-folk, Concord pilots by tradition. A FLOATING rig when gliding (standard 33x33 frame)
# Dusty wings (Q/q/n with cream f edges and powder) folded on the back like a swept tent with a swallow-tail, a fuzzy cream ruff, big dark compound
# eyes, feathery (pectinate) antennae whose tips and the wings' eye-spots glow amber (a lantern each, the glow layers). Outfit = a pilot's scarf
# (tinted, trails over the right wing) and the goggle frames. The LEGS layer: `stand` = the wings folded and thin legs hanging at the sides;
# `walk` = the glide: the legs tucked and a pair of wing tips opening and closing at the sides (a 6-frame flutter).
L_FLARE = [0.15, 0.35, 0.6, 0.7, 0.45, 0.25]                    # the wing tips' flutter over the 6 float frames (the idle `stand` frame has none)
def l_leg_frame(i):
    """the legs layer of a floating rig, on the 33x33 grid (lifted to the 49x49 frame): the thin legs hanging behind the swallow-tail, and wing tips that open and close at the sides."""
    s = Spr(N, N)
    for sd in (-1, 1):
        seg(s, 16 + sd * 2, 26, 16 + sd * 3, 30, 1, 'q'); s.put(16 + sd * 3, 31, 'n')
    if i == 6: return s
    f = L_FLARE[i]
    for sd in (-1, 1):
        tip = int(round(6 - 5 * f))                      # how far the wing tip reaches out (mirrored below)
        t = Spr(N, N); poly(t, [(8, 19), (tip, 21), (tip + 1, 26), (tip + 3, 28), (9, 27)], 'Q')
        t = shade_gen(t, 'Q', 'f', 'q')
        if sd > 0: t = t.flipx()
        merge(s, t)
        ex = (tip + 4) if sd < 0 else 32 - (tip + 4)
        s.put(ex, 24, 'a'); s.put(ex, 25, 'N')
        for k in range(3): s.put((tip + 1 + k) if sd < 0 else 32 - (tip + 1 + k), 22 + k, 'M')          # the dusty leading edge
    return s

L_WING = [(0, 12), (-5, 13), (-7, 17), (-9, 21), (-11, 25), (-11, 28), (-8, 28), (-8, 30), (-5, 29), (-4, 31), (-1, 29), (0, 28)]
def l_torso():
    s = Spr(N, N)
    wing = Spr(N, N)
    left = [(16 + dx, y) for dx, y in L_WING]; right = [(16 - dx, y) for dx, y in reversed(L_WING)]
    poly(wing, left[:-1] + right[1:], 'Q')
    wing = shade_gen(wing, 'Q', 'f', 'q'); merge(s, wing)
    for sd in (-1, 1):
        for (x1, y1) in ((11, 27), (8, 29), (4, 30)):                                              # wing veins fanning to the scallops
            line(s, (16 + sd * 1, 15), (16 + sd * x1, y1), 'q')
        ex = 16 + sd * 6                                                                          # an eye-spot, amber with a dark pupil
        for (dx, dy) in ((-1, 0), (1, 0), (0, -1), (0, 1)): s.put(ex + dx, 22 + dy, 'a')
        s.put(ex, 22, 'N'); s.put(ex - 1, 21, 'y')
    for y in range(13, 28): s.put(16, y, 'n')                                                     # the spine seam
    for (x, y) in ((12, 24), (20, 24), (14, 27), (18, 27), (9, 22), (23, 22), (12, 18), (20, 18), (8, 26), (24, 26)): s.put(x, y, 'M')    # powder
    # the fuzzy ruff over the shoulders
    ru = Spr(N, N); ell(ru, 16, 12.5, 6.0, 3.6, 'f'); ru = shade_gen(ru, 'f', 'H', 'Q'); merge(s, ru)
    for x in range(11, 22, 2): s.put(x, 15, 'Q')
    # the pilot's scarf (outfit): round the neck, trailing down the right wing in a swallow-tail
    s.hline(12, 14, 9, 'B')
    for j in range(7):
        x = 19 + (j * 3) // 7; s.put(x, 15 + j, 'B'); s.put(x + 1, 15 + j, 'C')
    s.put(21, 22, 'B'); s.put(23, 23, 'C'); s.put(22, 23, 'C')
    return s

def l_head(kind):
    s = Spr(N, N)
    if kind != 'helmet':                                                                         # feathery antennae: a stem with barbs, a lamp at the tip
        for sd in (-1, 1):
            stem = [(16 + sd * 2, 6), (16 + sd * 3, 4), (16 + sd * 5, 2), (16 + sd * 7, 1)]
            for a, b in zip(stem, stem[1:]): line(s, a, b, 'Q')
            for (bx, by) in ((16 + sd * 3, 3), (16 + sd * 4, 2), (16 + sd * 5, 1), (16 + sd * 5, 3), (16 + sd * 6, 2), (16 + sd * 7, 3)): s.put(bx, by, 'f')
            s.put(16 + sd * 8, 1, 'a'); s.put(16 + sd * 8, 0, 'y')
    h = Spr(N, N); ell(h, 16, 10, 4.4, 3.8, 'Q'); h = shade_gen(h, 'Q', 'f', 'q'); merge(s, h)
    for sd in (-1, 1):                                                                           # big dark compound eyes with a glint
        ex = 16 + sd * 3
        s.rect(ex - 1, 9, 3, 3, 'N'); s.put(ex - 1, 9, 'c') if sd < 0 else s.put(ex + 1, 9, 'c')
    s.put(16, 12, 'q'); s.put(15, 12, 'f'); s.put(17, 12, 'f')
    if kind == 'goggles':                                                                        # pilot's goggles: tinted frames, blue glass
        s.hline(11, 9, 11, 'B'); s.hline(11, 12, 11, 'C'); s.vline(11, 10, 2, 'B'); s.vline(21, 10, 2, 'C'); s.put(16, 10, 'B'); s.put(16, 11, 'C')
        for sd in (-1, 1): s.rect(16 + sd * 3 - 1, 10, 3, 2, 'b'); s.put(16 + sd * 3 - 1, 10, 'H') if sd < 0 else s.put(16 + sd * 3 + 1, 10, 'H')
    if kind == 'helmet':                                                                         # a leather pilot's cap (tinted) with the antennae out through two slits
        s.hline(11, 8, 11, 'B'); s.hline(12, 7, 9, 'B'); s.hline(13, 6, 7, 'A'); s.hline(11, 9, 11, 'C')
        for sd in (-1, 1):
            for (bx, by) in ((16 + sd * 3, 5), (16 + sd * 4, 4), (16 + sd * 5, 3), (16 + sd * 6, 2), (16 + sd * 7, 1)): s.put(bx, by, 'Q')
            s.put(16 + sd * 7, 2, 'f'); s.put(16 + sd * 6, 1, 'f'); s.put(16 + sd * 8, 0, 'y'); s.put(16 + sd * 8, 1, 'a')
    return s
L_HEADS = ['antennae', 'goggles', 'helmet']

def l_claw(s, x, y):
    s.put(x - 1, y - 1, 'n'); s.put(x + 1, y - 1, 'n'); s.hline(x - 1, y, 3, 'Q'); s.put(x + 1, y, 'q'); s.put(x, y + 1, 'q')
def l_arm(s, a, b):
    t = Spr(N, N); seg(t, a[0], a[1], b[0], b[1], 2, 'Q'); merge(s, shade_gen(t, 'Q', 'f', 'q'))
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1); i = int(n * 0.7)
    s.put(a[0] + round((b[0] - a[0]) * i / n), a[1] + round((b[1] - a[1]) * i / n), 'f')              # a fuzzy cuff
def l_arms(pose):
    s = Spr(N, N); A = pose_anchors((6, 20), (26, 20))[pose]
    if pose == 'unarmed':
        l_arm(s, (9, 14), (6, 20)); l_arm(s, (23, 14), (26, 20)); l_claw(s, 6, 21); l_claw(s, 26, 21)
        return s
    for sh, k in (((9, 14), 'hand_l'), ((23, 14), 'hand_r')):
        l_arm(s, sh, A[k]); l_claw(s, *A[k])
    return s

class Lantern(Species):
    id = 'lantern'
    N = FN; C = FC
    kind = 'floating'; legs_anim = 'float'
    walk_fps = 6
    glow_fps = 2
    head_names = L_HEADS
    notes = ('Lantern: moth-folk, Concord pilots by tradition; a FLOATING rig when gliding (kind "floating": 49x49, pivot (24,24)). Dusty wings folded on the back '
             'like a swept tent with a swallow-tail, a fuzzy cream ruff, big dark compound eyes and feathery antennae; the body is the normal body in the middle of '
             'the frame (the drawer bobs it). The legs layer is what hangs behind it: thin legs under the swallow-tail and a pair of wing tips that open and close at the '
             'sides (`float`: 6 frames, 6 fps, played by time; `stand`: wings folded). The mounts are the human\'s moved by (+8,+8). torso_glow (2 pulse frames at ~2 fps) lights '
             'the wings\' eye-spots, head_glow the antenna lamps. Head variants: antennae (default), goggles (tinted frames, blue glass), helmet (a tinted leather cap, '
             'antennae out through slits). Outfit mask = the pilot\'s scarf, the goggle frames and the cap.')
    def legs(self): return [outlined(lift(l_leg_frame(i), FN, 8)) for i in range(7)]
    def torso(self): return outlined(lift(l_torso(), FN, 8))
    def arms(self, pose): return outlined(lift(l_arms(pose), FN, 8))
    def head(self, name): return outlined(lift(l_head(name), FN, 8))
    def torso_anchors(self): return {'head': [FC, FC - 6], 'back': [FC, FC + 8], 'shoulder_l': [FC - 7, FC - 2], 'shoulder_r': [FC + 7, FC - 2]}
    def arm_anchors(self): return pose_anchors((6 + 8, 20 + 8), (26 + 8, 20 + 8), shift=8)
    def torso_glow(self):
        out = []
        for f in (0, 1):
            g = ng(33)
            glow_px_max(g, [(10, 22), (22, 22)], (225, 161, 54), (0.7, 0.45)[f], (4.5, 3.5)[f], 1.4)
            out.append(lift_glow(g, FN, 8))
        return out
    def head_glow(self):
        out = []
        for f in (0, 1):
            for nm in self.head_names:
                g = ng(33)
                glow_px_max(g, [(8, 0), (24, 0), (8, 1), (24, 1)], (255, 210, 58), (0.7, 0.45)[f], (3.5, 2.8)[f], 1.4)
                out.append(lift_glow(g, FN, 8))
        return out
