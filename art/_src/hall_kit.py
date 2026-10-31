"""The hall of ships frame kit and the score-panel ornaments (art/ui/): hall_frame (9-slice, three line variants), hall_plate (3-slice nameplate), hall_crest, hall_bg (tile),
score_ornaments (an atlas of dividers, corners, laurels, pips, a seal and banner pieces). Hard pixels in game-palette colours only (no endings-only colours), light from the top-left,
a riveted industrial frame that is Scrapper-meets-Concord with the line colour in its inlay and gems. Deterministic; run through endings_all.py."""
import math, json, os
from ill import *

# line variants: (plate ramp dark->light, inlay (dark, mid, light), gem (ring, core, glint), rivet (dark, light), glow colour)
VARIANTS = {
 'standard': dict(plate=['K', 'D', 'E', 'W', 'S', 'M', 'L'], inlay=('u', 'a', 'y'), gem=('S', 'y', 'H'), rivet=('E', 'L'), glow='y', fill='D'),
 'scrap':    dict(plate=['K', 'n', 'q', 'u', 'T', 'Q', 'Y'], inlay=('E', 'W', 'S'), gem=('n', 'r', 'o'), rivet=('n', 'Y'), glow='o', fill='K'),
 'neon':     dict(plate=['N', 'I', 'J', 'j', 'x', 't', 'z'], inlay=('B', 'C', 'c'), gem=('j', 'm', 'H'), rivet=('N', 'z'), glow='c', fill='N'),
}

FS, BT, CS = 96, 12, 24          # frame size, border thickness, corner size (= nine-slice margin)

def border_profile(v, lit):
    """colour of the border at depth d (0 = the outer edge ... 11 = against the opening). lit = the side that faces the light (top, left)."""
    P, (i0, i1, i2) = v['plate'], v['inlay']
    K, D, E, W, S, M, L = P
    if lit: return [K, L, M, S, S, W, E, K, i2, i1, i0, K]
    return [K, S, W, W, E, E, D, K, i0, i1, i2, M]

def frame(var='standard'):
    v = VARIANTS[var]
    im = Ill(FS, FS, '.')
    rv_d, rv_l = v['rivet']
    for y in range(BT, FS - BT):
        for x in range(BT, FS - BT): im.put(x, y, v['fill'])
    # the four sides (the 48 px between the corners repeats every 8 px, so it tiles)
    for y in range(FS):
        for x in range(FS):
            in_top, in_bot = y < BT, y >= FS - BT
            in_left, in_right = x < BT, x >= FS - BT
            if not (in_top or in_bot or in_left or in_right): continue
            if in_top: d, lit = y, True
            elif in_left: d, lit = x, True
            elif in_bot: d, lit = FS - 1 - y, False
            else: d, lit = FS - 1 - x, False
            c = border_profile(v, lit)[d]
            along = x if (in_top or in_bot) else y
            if CS <= along < FS - CS:
                if d in (3, 4) and along % 8 == 3: c = rv_l if (d == 3) == lit else rv_d     # a rivet every 8 px, lit on its top-left
                if d in (1, 2) and along % 8 in (0, 1) and lit: c = border_profile(v, True)[d + 1]   # a little dentil rhythm on the lit rim
                if d == 5 and along % 8 == 7: c = v['plate'][1]                              # a seam in the plate
                if d in (8, 9, 10) and along % 8 == 3: c = v['inlay'][2]                      # a bead in the inlay
            im.put(x, y, c)
    for x in range(BT, FS - BT): im.put(x, BT, v['plate'][0])
    for y in range(BT, FS - BT): im.put(BT, y, v['plate'][0])
    plate_ = corner_plate(v)
    for (ox, oy) in ((0, 0), (FS - CS, 0), (0, FS - CS), (FS - CS, FS - CS)):
        for yy in range(CS):
            for xx in range(CS):
                c = plate_.g[yy][xx]
                if c != '.': im.put(ox + xx, oy + yy, c)
    return im

def corner_plate(v):
    """one 24x24 corner plate, the same for all four corners (lit from the top-left): a chamfered slab with a recessed panel, a gem in a bezel,
    four filigree lines running to the recess corners, and a stud in each corner. The border's inlay butts into it with a bead."""
    P = v['plate']; K, D, E, W, S, M, L = P
    i0, i1, i2 = v['inlay']
    im = Ill(CS, CS, '.')
    ch = 5
    slab = poly_cells([(ch, 0), (CS - ch, 0), (CS, ch), (CS, CS - ch), (CS - ch, CS), (ch, CS), (0, CS - ch), (0, ch)])
    for (x, y) in slab: im.put(x, y, S)
    for (x, y) in slab:
        tl = (x - 1, y) not in slab or (x, y - 1) not in slab or (x - 1, y - 1) not in slab
        br = (x + 1, y) not in slab or (x, y + 1) not in slab or (x + 1, y + 1) not in slab
        if tl: im.put(x, y, M if (x + y) % 2 == 0 or y < 2 or x < 2 else L)
        elif br: im.put(x, y, E)
    # second ring in from the edge: highlight top-left, shadow bottom-right
    inner = shrink(slab, 2)
    for (x, y) in inner:
        if (x - 1, y) not in inner or (x, y - 1) not in inner: im.put(x, y, L)
        elif (x + 1, y) not in inner or (x, y + 1) not in inner: im.put(x, y, W)
    im.outline(slab, K)
    # the recessed panel
    rec = poly_cells([(7, 5), (17, 5), (19, 7), (19, 17), (17, 19), (7, 19), (5, 17), (5, 7)])
    for (x, y) in rec: im.put(x, y, W)
    for (x, y) in rec:
        if (x - 1, y) not in rec or (x, y - 1) not in rec: im.put(x, y, K if (x + y) % 2 == 0 else E)
        elif (x + 1, y) not in rec or (x, y + 1) not in rec: im.put(x, y, M)
    # filigree: lines in the inlay colour from the bezel toward each recess corner, ending in a bead
    for (dx, dy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        for k in range(4, 9):
            x, y = 12 + dx * k, 12 + dy * k
            if (x, y) in rec: im.put(x, y, i1 if k < 8 else i2)
        for k in (6,):
            x, y = 12 + dx * k, 12 + dy * (k - 1)
            if (x, y) in rec: im.put(x, y, i0)
    # the gem in its bezel
    bz = ellipse_cells(12, 12, 4.6, 4.6)
    im.fill(grow(bz, 1) - bz, K); im.fill(bz, v['gem'][0])
    for (x, y) in bz:
        if (x + y) > 24: im.put(x, y, darken(v['gem'][0]) if v['gem'][0] in UP or v['gem'][0] in DOWN else v['gem'][0])
    core = ellipse_cells(12, 12, 3.0, 3.0)
    im.fill(core, v['gem'][1])
    for (x, y) in core:
        if x + y > 24: im.put(x, y, i0 if i0 != v['gem'][1] else v['gem'][1])
    im.put(10, 10, v['gem'][2]); im.put(11, 10, v['gem'][2]); im.put(10, 11, v['gem'][2])
    # corner studs
    for (x, y) in ((6, 2), (17, 2), (2, 6), (21, 6), (2, 17), (21, 17), (6, 21), (17, 21)):
        im.put(x, y, v['rivet'][1]); im.put(x + 1, y + 1, v['rivet'][0])
    return im

def frame_glow(var='standard'):
    v = VARIANTS[var]
    g = Glow(FS, FS)
    col = v['glow']
    for (ox, oy) in ((12, 12), (FS - 12, 12), (12, FS - 12), (FS - 12, FS - 12)):
        g.blob(ox, oy, 13, col, 130, 1.8)
    for x in range(CS, FS - CS, 8):                                    # a faint line along the inlay on each side
        for (xx, yy) in ((x, 9), (x, FS - 10), (9, x), (FS - 10, x)): g.px(xx, yy, col, 28)
    return g

# ------------------------------------------------------------------ the nameplate: 3-slice (caps 12 wide), 48 x 20
PW, PH, PCAP = 48, 20, 12
def plate(var='standard'):
    v = VARIANTS[var]
    P = v['plate']; K, D, E, W, S, M, L = P
    i0, i1, i2 = v['inlay']
    im = Ill(PW, PH, '.')
    body_ = poly_cells([(3, 0), (PW - 3, 0), (PW, 3), (PW, PH - 3), (PW - 3, PH), (3, PH), (0, PH - 3), (0, 3)])
    for (x, y) in body_:
        t = y / float(PH - 1)
        im.put(x, y, P[min(6, max(1, int(5.3 - t * 4.6)))])
    im.outline(body_, K)
    # inset dark panel for the text (the game prints the ship name over it)
    inner = rect_cells(5, 4, PW - 10, PH - 8)
    im.fill(inner, v['fill'])
    for x in range(5, PW - 5): im.put(x, 4, K)
    for y in range(4, PH - 4): im.put(5, y, K)
    # inlay line round the panel
    for x in range(4, PW - 4):
        im.put(x, 3, i1); im.put(x, PH - 4, i0)
    im.put(4, 3, i2); im.put(PW - 5, PH - 4, i0)
    # rivets and end gems
    for (x, y) in ((2, 2), (PW - 3, 2), (2, PH - 3), (PW - 3, PH - 3)): im.put(x, y, v['rivet'][1])
    for x in (8, PW - 9):
        im.fill(ellipse_cells(x + 0.5, PH / 2.0, 1.6, 1.6), v['gem'][1]); im.put(x, PH // 2 - 1, v['gem'][2])
    return im

def plate_glow(var='standard'):
    v = VARIANTS[var]; g = Glow(PW, PH)
    for x in (8, PW - 9): g.blob(x + 0.5, PH / 2.0, 6, v['glow'], 100, 1.8)
    return g

def laurel_branch(im, cx, cy, R, a0, a1, n, ll, cols, K, tint=True):
    """a laurel branch: a stem along an arc (centre cx, cy, radius R, from angle a0 to a1 degrees) with a pair of leaves at each of n points, pointing along the branch and out."""
    pts = []
    for k in range(n * 3 + 1):
        a = math.radians(a0 + (a1 - a0) * k / float(n * 3))
        pts.append((cx + R * math.cos(a), cy + R * math.sin(a)))
    for (p, q) in zip(pts, pts[1:]): im.line(p[0], p[1], q[0], q[1], cols[0])
    for k in range(1, n + 1):
        a = math.radians(a0 + (a1 - a0) * k / float(n))
        px_, py_ = cx + R * math.cos(a), cy + R * math.sin(a)
        tang = a + math.pi / 2 * (1 if a1 > a0 else -1)
        for side in (-1, 1):
            ang = tang + side * 0.75
            ex, ey = px_ + ll * math.cos(ang), py_ + ll * math.sin(ang)
            mx_, my_ = px_ + ll * 0.5 * math.cos(ang), py_ + ll * 0.5 * math.sin(ang)
            nx, ny = -math.sin(ang) * ll * 0.28, math.cos(ang) * ll * 0.28
            lf = poly_cells([(px_, py_), (mx_ + nx, my_ + ny), (ex, ey), (mx_ - nx, my_ - ny)])
            im.fill(lf, cols[1] if (k + (side > 0)) % 2 else cols[2])
            for (x, y) in lf:
                if (x - 1, y - 1) not in lf: im.put(x, y, cols[3])
            im.outline(lf, K)
        im.put(int(round(px_)), int(round(py_)), cols[0])

# ------------------------------------------------------------------ the crest that sits on the top edge of the frame: a gate ring between laurels, 48 x 28
CW_, CH_ = 48, 28
def crest(var='standard'):
    v = VARIANTS[var]
    P = v['plate']; K, D, E, W, S, M, L = P
    i0, i1, i2 = v['inlay']
    im = Ill(CW_, CH_, '.')
    cx, cy = CW_ // 2, 14
    # laurel branches: an open wreath round the medallion
    cols = (i0, i1, i0, i2)
    laurel_branch(im, cx, cy, 16, 100, 205, 5, 5, cols, K)
    sub = Ill(CW_, CH_, '.')
    laurel_branch(sub, cx, cy, 16, 80, -25, 5, 5, cols, K)
    for yy in range(CH_):
        for xx in range(CW_):
            if sub.g[yy][xx] != '.': im.put(xx, yy, sub.g[yy][xx])
    # the medallion: a gate ring on a dark disc with a lit centre
    disc = ellipse_cells(cx, cy, 11, 11)
    im.shade(disc, [K, D, E, W, S, M], cx - 2, cy - 2, 12, 12, sharp=1.6)
    im.outline(disc, K)
    ring = ring_cells(cx, cy, 8.5, 8.5, 2.5)
    for (x, y) in ring: im.put(x, y, i1 if (x - cx) + (y - cy) >= 0 else i2)
    for (x, y) in ring_cells(cx, cy, 6, 6, 1): im.put(x, y, i0)
    inner = ellipse_cells(cx, cy, 4, 4)
    im.fill(inner, v['fill'])
    im.fill(ellipse_cells(cx, cy, 1.5, 1.5), v['gem'][1]); im.put(cx - 1, cy - 1, v['gem'][2])
    for k in range(4):                                               # four pylons on the ring
        a = math.radians(k * 90 + 45)
        im.put(int(round(cx + 8.5 * math.cos(a))), int(round(cy + 8.5 * math.sin(a))), v['rivet'][1])
    return im

def crest_glow(var='standard'):
    v = VARIANTS[var]; g = Glow(CW_, CH_)
    g.blob(CW_ // 2, 14, 12, v['glow'], 110, 1.8)
    return g

# ------------------------------------------------------------------ the display backdrop: a blueprint grid that tiles, 32 x 32
def bg_tile():
    im = Ill(32, 32, 'D')
    for k in range(0, 32, 8):
        for i in range(32):
            im.put(k, i, 'E'); im.put(i, k, 'E')
    for x in range(0, 32, 8):
        for y in range(0, 32, 8):
            im.put(x, y, 'W')
            im.put(x + 4, y + 4, 'E')
    for (x, y) in ((11, 3), (27, 13), (5, 21), (21, 29), (15, 17)): im.put(x, y, 'W')
    return im

# ------------------------------------------------------------------ score panel ornaments: one atlas, a JSON listing the rects
def ornaments():
    A = Ill(256, 96, '.')
    regs = {}
    P = VARIANTS['standard']['plate']; K, D, E, W, S, M, L = P
    i0, i1, i2 = VARIANTS['standard']['inlay']
    def put(name, x, y, spr_fn, w, h):
        sub = Ill(w, h, '.')
        spr_fn(sub)
        for yy in range(h):
            for xx in range(w): A.put(x + xx, y + yy, sub.g[yy][xx])
        regs[name] = [x, y, w, h]
    # divider: left cap, a tiling middle (8 wide: 1 px line with a bead), a centre piece, right cap
    def d_mid(s):
        s.hline(0, 3, 8, K); s.hline(0, 4, 8, i1); s.hline(0, 5, 8, i0); s.put(3, 4, i2); s.put(3, 3, i1)
    def d_cap(s, flip=False):
        for x in range(16):
            xx = 15 - x if flip else x
            s.put(xx, 3, K); s.put(xx, 4, i1 if x > 3 else i2); s.put(xx, 5, i0 if x > 3 else K)
        for (x, y, c) in ((0, 4, i2), (1, 3, i1), (1, 5, i1), (2, 2, i0), (2, 6, i0), (3, 4, i2)):
            s.put(15 - x if flip else x, y, c)
    def d_center(s):
        for x in range(24):
            s.put(x, 3, K); s.put(x, 4, i1 if (x < 6 or x > 17) else K); s.put(x, 5, i0 if (x < 6 or x > 17) else K)
        dia = poly_cells([(12, 0), (19, 4.5), (12, 9), (5, 4.5)])
        s.fill(dia, i1); s.outline(dia, K)
        for (x, y) in dia:
            if (x + y) < 15: s.put(x, y, i2)
        s.put(12, 4, 'H');
        for (x, y) in ((1, 4), (22, 4)): s.put(x, y, i2)
    put('divider_l', 0, 0, d_cap, 16, 9); put('divider_mid', 20, 0, d_mid, 8, 9); put('divider_c', 32, 0, d_center, 24, 9); put('divider_r', 60, 0, lambda s: d_cap(s, True), 16, 9)
    # corner flourishes (panel corners): an L bracket with a scroll and a bead, 16 x 16, four orientations lit from the top-left
    def corner_fl(s, sx, sy):
        def p(u, w, c): s.put(u if sx > 0 else 15 - u, w if sy > 0 else 15 - w, c)
        for k in range(16):
            p(k, 0, K); p(0, k, K)
            p(k, 1, i2 if (sx, sy) == (1, 1) else i1) if k > 1 else None; p(1, k, i2 if (sx, sy) == (1, 1) else i1) if k > 1 else None
            p(k, 2, i0) if k > 2 else None; p(2, k, i0) if k > 2 else None
        for (u, w, c) in ((3, 3, i1), (4, 4, i2), (5, 5, i1), (6, 6, i0), (7, 5, i0), (5, 7, i0), (8, 4, i1), (4, 8, i1), (9, 5, i2), (5, 9, i2), (10, 6, i0), (6, 10, i0)): p(u, w, c)
        for (u, w) in ((1, 1), (2, 2)): p(u, w, 'H' if u == 1 else i2)
    put('corner_tl', 80, 0, lambda s: corner_fl(s, 1, 1), 16, 16); put('corner_tr', 100, 0, lambda s: corner_fl(s, -1, 1), 16, 16)
    put('corner_bl', 120, 0, lambda s: corner_fl(s, 1, -1), 16, 16); put('corner_br', 140, 0, lambda s: corner_fl(s, -1, -1), 16, 16)
    # pips: a lit diamond and an empty one (8 x 8) for ratings and counters; a lit star (10 x 10)
    def pip(s, on):
        dia = poly_cells([(4, 0), (8, 4), (4, 8), (0, 4)])
        s.fill(dia, i1 if on else D); s.outline(dia, K) if False else None
        for (x, y) in dia:
            if on and x + y < 7: s.put(x, y, i2)
            if not on and (x + y) < 6: s.put(x, y, E)
        for (x, y) in grow(dia, 1) - dia: s.put(x, y, K)
        if on: s.put(3, 3, 'H')
    put('pip_on', 160, 0, lambda s: pip(s, True), 10, 10); put('pip_off', 172, 0, lambda s: pip(s, False), 10, 10)
    # laurels (20 x 36): a branch that curves round a score number, leaves opening outward; the right one is its mirror
    def laurel(s_, sg):
        sub = Ill(20, 36, '.')
        laurel_branch(sub, 20, 18, 15, 100, 258, 6, 6, (i0, i1, i0, i2), K)
        for yy in range(36):
            for xx in range(20):
                c = sub.g[yy][xx]
                if c != '.': s_.put(xx if sg > 0 else 19 - xx, yy, c)
    put('laurel_l', 190, 0, lambda s_: laurel(s_, 1), 20, 36); put('laurel_r', 214, 0, lambda s_: laurel(s_, -1), 20, 36)
    # seal: a rosette medal with two ribbon tails (32 x 40), blank centre for a rank glyph
    def seal(s):
        cx, cy = 16, 14
        for sg in (-1, 1):                                            # ribbon tails
            tail = poly_cells([(cx + sg * 3, cy + 8), (cx + sg * 11, cy + 8), (cx + sg * 11, 39), (cx + sg * 7, 35), (cx + sg * 3, 39)])
            s.fill(tail, 'r' if sg < 0 else 'r'); s.outline(tail, K)
            for (x, y) in tail:
                if (x - (cx + sg * 3)) * sg < 2: s.put(x, y, 'o')
        pts = []
        for k in range(16):
            a = math.radians(k * 22.5)
            rr = 14 if k % 2 == 0 else 11
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        star = poly_cells(pts)
        s.shade(star, [K, u_, i0, i1, i2], cx - 3, cy - 3, 15, 15, sharp=1.5) if False else s.fill(star, i1)
        for (x, y) in star:
            if (x - cx) + (y - cy) < -4: s.put(x, y, i2)
            elif (x - cx) + (y - cy) > 6: s.put(x, y, i0)
        s.outline(star, K)
        disc = ellipse_cells(cx, cy, 8, 8)
        s.fill(disc, D); s.outline(disc, i0)
        for (x, y) in ring_cells(cx, cy, 8, 8, 1): s.put(x, y, i2 if x + y < 28 else i0)
        s.fill(ellipse_cells(cx, cy, 6, 6), D)
        for (x, y) in ellipse_cells(cx, cy, 6, 6):
            if x + y < 24: s.put(x, y, E)
    put('seal', 0, 20, seal, 32, 40)
    # banner pieces behind the ending title: left cap, a tiling middle (8 x 20), right cap; steel with an amber edge
    def b_mid(s):
        for y in range(20):
            s.put(0, y, K) if False else None
        for x in range(8):
            s.put(x, 3, K); s.put(x, 4, i2); s.put(x, 5, i1)
            for y in range(6, 14): s.put(x, y, S if y < 8 else W if y < 12 else E)
            s.put(x, 14, i0); s.put(x, 15, i1); s.put(x, 16, K)
        for x in range(8):
            if x % 8 == 3:
                for y in (8, 11): s.put(x, y, M)
    def b_cap(s, flip=False):
        def p(x, y, c): s.put(15 - x if flip else x, y, c)
        body_ = poly_cells([(4, 3), (16, 3), (16, 17), (4, 17), (0, 10)])
        for (x, y) in body_:
            c = i2 if y == 4 else i1 if y == 5 else S if y < 8 else W if y < 12 else E if y < 14 else i0 if y == 14 else i1
            p(x, y, c)
        for (x, y) in grow(body_, 1) - body_: p(x, y, K)
        p(3, 10, i2); p(4, 10, 'H'); p(6, 10, i1)
    put('banner_l', 40, 20, b_cap, 16, 20); put('banner_mid', 60, 20, b_mid, 8, 20); put('banner_r', 72, 20, lambda s: b_cap(s, True), 16, 20)
    return A, regs

u_ = 'u'

def export(art_dir):
    ui = art_dir + '/ui'
    os.makedirs(ui, exist_ok=True)
    for var in VARIANTS:
        suf = '' if var == 'standard' else '_' + var
        im = frame(var); im.save_alpha('%s/hall_frame%s.png' % (ui, suf))
        frame_glow(var).__class__  # glow strip: one frame
        save_glow_strip([frame_glow(var)], '%s/hall_frame%s_glow.png' % (ui, suf))
        meta = {'frame': [FS, FS], 'nine_slice': True, 'margins': [CS, CS, CS, CS], 'axis_stretch': 'tile',
                'glow': {'image': 'hall_frame%s_glow.png' % suf, 'frame': [FS, FS], 'offset': [0, 0], 'blend': 'add (preferred) or alpha-over'},
                'notes': 'Hall of ships frame, %s line. 96x96, nine-slice with 24 px margins: the four 24x24 corners (chamfered plate, a fillet boss that reaches into the opening, a gem and an inlay that curls round it) '
                         'stay as they are; the 48 px edges repeat every 8 px (rivet, seam), so TILE them (not stretch). The centre is a flat dark fill: draw the display backdrop (hall_bg.png, tiled) and the ship silhouette over it, '
                         'inside the opening (inset 12 px from each side). The glow adds a soft light on the four gems and a faint line along the inlay.' % var}
        json.dump(meta, open('%s/hall_frame%s.json' % (ui, suf), 'w'), indent=1); open('%s/hall_frame%s.json' % (ui, suf), 'a').write('\n')
        pl = plate(var); pl.save_alpha('%s/hall_plate%s.png' % (ui, suf))
        save_glow_strip([plate_glow(var)], '%s/hall_plate%s_glow.png' % (ui, suf))
        meta = {'frame': [PW, PH], 'nine_slice': True, 'margins': [PCAP, 0, PCAP, 0], 'axis_stretch': 'tile',
                'glow': {'image': 'hall_plate%s_glow.png' % suf, 'frame': [PW, PH], 'offset': [0, 0], 'blend': 'add (preferred) or alpha-over'},
                'text_rect': [14, 4, PW - 28, PH - 8],
                'notes': 'The nameplate under a hall-of-ships frame (%s line): three slices, 12 px caps and a 24 px middle that tiles horizontally (it is a flat strip, so stretching also works). Print the ship name in the dark inset (text_rect, in source px).' % var}
        json.dump(meta, open('%s/hall_plate%s.json' % (ui, suf), 'w'), indent=1); open('%s/hall_plate%s.json' % (ui, suf), 'a').write('\n')
        cr = crest(var); cr.save_alpha('%s/hall_crest%s.png' % (ui, suf))
        save_glow_strip([crest_glow(var)], '%s/hall_crest%s_glow.png' % (ui, suf))
        meta = {'frame': [CW_, CH_], 'anchors': {'bottom_centre': [CW_ // 2, CH_ - 2]},
                'glow': {'image': 'hall_crest%s_glow.png' % suf, 'frame': [CW_, CH_], 'offset': [0, 0], 'blend': 'add (preferred) or alpha-over'},
                'notes': 'A crest (a gate ring on a medallion between laurels, %s line) that sits over the middle of the frame top edge: put its bottom centre on the frame edge, 2 px into the border.' % var}
        json.dump(meta, open('%s/hall_crest%s.json' % (ui, suf), 'w'), indent=1); open('%s/hall_crest%s.json' % (ui, suf), 'a').write('\n')
    bg_tile().save_alpha('%s/hall_bg.png' % ui)
    json.dump({'frame': [32, 32], 'tile': 'xy', 'notes': 'The display backdrop for the hall of ships: a dark blueprint grid (8 px cells) that tiles on both axes. Draw it inside the frame opening, under the ship silhouette.'},
              open('%s/hall_bg.json' % ui, 'w'), indent=1); open('%s/hall_bg.json' % ui, 'a').write('\n')
    A, regs = ornaments()
    A.save_alpha('%s/score_ornaments.png' % ui)
    json.dump({'frame': [256, 96], 'regions': regs,
               'notes': 'Score-panel ornaments, one atlas (rects are [x, y, w, h] in source px). Divider: divider_l + divider_mid repeated + divider_c + divider_mid repeated + divider_r (a rule with a diamond in the middle). '
                        'corner_tl/tr/bl/br: 16x16 amber brackets for the corners of a panel. pip_on/pip_off: rating and counter diamonds. laurel_l/laurel_r: a wreath either side of the score number. '
                        'seal: a rosette medal with ribbon tails and a blank centre for a rank glyph. banner_l + banner_mid repeated + banner_r: a steel ribbon behind the ending title. Amber on transparent; tint only if you must.'},
              open('%s/score_ornaments.json' % ui, 'w'), indent=1); open('%s/score_ornaments.json' % ui, 'a').write('\n')
    return regs
