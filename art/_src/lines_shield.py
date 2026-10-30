"""Shields, 4x4: Mk1 and Mk2 (Concord), Bubble Rig (Scrap), Neon Lattice (Neon), Mirror Veil (unique).
New animation (owner: shields need better motion): on = 8 frames with counter-rotating emitter rings/segments, energy arcs crawling between the emitter prongs and a core that breathes;
hit = 3 frames (flare + ripple from the core), recharge = 4 frames (the rings spinning up)."""
import math
from lines_kit import *

# ---------------------------------------------------------------- motion helpers
def _ang(dx, dy): return math.degrees(math.atan2(dx, -dy)) % 360

def seg_ring(s, cx, cy, r0, r1, n, duty, rot, c, head=None, direction=1, hollow_only=False):
    """n arc segments round (cx, cy), each `duty` of its slot long; rot = degrees clockwise from up. head colours the leading edge."""
    per = 360.0 / n; ln = per * duty
    for y in range(int(cy - r1 - 1), int(cy + r1 + 2)):
        for x in range(int(cx - r1 - 1), int(cx + r1 + 2)):
            dx, dy = x + .5 - cx, y + .5 - cy; d = dx * dx + dy * dy
            if not (r0 * r0 < d <= r1 * r1): continue
            loc = (_ang(dx, dy) - rot) % per
            if loc < ln:
                col = c
                if head and ((direction > 0 and loc > ln - per * 0.16) or (direction < 0 and loc < per * 0.16)): col = head
                s.put(x, y, col)

JIT = [0, 1, 1, 0, -1, 0, -1, 0, 1, 0, 0, -1, 1, -1, 0, 1]

def arc(s, p0, ctrl, p2, frame, k, base, mid, hot, nframes=8, flare=False, drop=0):
    """a crackling arc along a quadratic curve p0 -> p2 bent toward ctrl; a bright packet crawls along it (one length per loop)."""
    length = math.dist(p0, ctrl) + math.dist(ctrl, p2); N = int(length * 1.6)
    tp = ((frame / float(nframes)) + k * 0.25) % 1.0
    for n in range(N + 1):
        t = n / float(N)
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * ctrl[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * ctrl[1] + t * t * p2[1]
        dx = 2 * (1 - t) * (ctrl[0] - p0[0]) + 2 * t * (p2[0] - ctrl[0]); dy = 2 * (1 - t) * (ctrl[1] - p0[1]) + 2 * t * (p2[1] - ctrl[1])
        ln = math.hypot(dx, dy) or 1; nx, ny = -dy / ln, dx / ln
        off = JIT[(n // 2 + 3 * frame + 5 * k) % len(JIT)] if 0.04 < t < 0.96 else 0
        px, py = int(round(x + off * nx)), int(round(y + off * ny))
        d = abs(t - tp); d = min(d, 1 - d)
        if flare: col = hot if d < 0.5 else mid
        elif d < 0.06: col = hot
        elif d < 0.13: col = mid
        elif (n // 2 + frame) % 4 == drop: continue
        else: col = base
        if col: s.put(px, py, col)

def put_ex(s, x, y, c):
    if s.get(x, y) != '.': s.put(x, y, c)

def ring_ex(s, cx, cy, r0, r1, c):
    for y in range(int(cy - r1 - 1), int(cy + r1 + 2)):
        for x in range(int(cx - r1 - 1), int(cx + r1 + 2)):
            d = (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2
            if r0 * r0 < d <= r1 * r1: put_ex(s, x, y, c)

BR = [4, 5, 6, 7, 7, 6, 5, 4]         # the core breathes (radius per frame of the 8-frame loop)

# ---------------------------------------------------------------- shared shield behaviour
class ShieldBase(LComp):
    cells = (4, 4)
    glow_pad = (12, 12, 12, 12)
    anims = [('on', 'on', 8, 8), ('off', 'off', 1, 0), ('hit', 'hit', 3, 12), ('recharge', 'recharge', 4, 10), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (2, 5)
    HITC = ('H', 'c', 'b')               # ripple colours per hit frame
    CORE = (32, 32)
    GLOW = BLUE
    def static(self, s, on): raise NotImplementedError
    def dyn(self, s, i): pass            # the 8-frame on loop
    def interior(self, state, i):
        s = Spr(64, 64)
        self.static(s, state != 'off')
        if state == 'on': self.dyn(s, i)
        elif state == 'recharge': self.dyn_recharge(s, i)
        elif state == 'hit':
            self.dyn(s, 1 + 2 * i)
            cx, cy = self.CORE
            r = (9, 6, 4)[i]
            circle(s, cx, cy, r + 3, 'c' if i == 0 else 'b') if i < 2 else None
            circle(s, cx, cy, r, 'H' if i < 2 else 'c')
            specs = [[(10, 12.4, 'H')], [(18, 20.4, 'H'), (11, 12.6, 'c')], [(26, 28.6, 'c'), (19, 20.6, 'b')]][i]
            for (r0, r1, c) in specs: ring_ex(s, cx, cy, r0, r1, c)
        return s
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        cx, cy = self.CORE
        if state == 'hit':
            glow(g, ox + cx, oy + cy, 34, (200, 230, 255), (0.75, 0.55, 0.38)[i], 1.2)
            glow(g, ox + cx, oy + cy, 12, (255, 255, 255), (0.8, 0.6, 0.4)[i], 1.4)
            return
        if state == 'recharge':
            glow(g, ox + cx, oy + cy, 24, self.GLOW, 0.12 + 0.05 * i, 1.5); glow(g, ox + cx, oy + cy, 6 + i, CYAN, 0.15 + 0.1 * i, 1.8)
            self.glow_extra(g, ox, oy, i, 0.35)
            return
        br = BR[i % 8]
        glow(g, ox + cx, oy + cy, 24 + br, self.GLOW, (0.26 + 0.02 * br) * k, 1.4)
        glow(g, ox + cx, oy + cy, 5 + br, CYAN, 0.45 * k, 1.8)
        self.glow_extra(g, ox, oy, i, k, flick)
    def glow_extra(self, g, ox, oy, i, k, flick=None): pass
    def dyn_recharge(self, s, j):
        self.dyn(s, (j * 3) % 8, spin=3.0, dim=True, rj=j)

# ---------------------------------------------------------------- Concord Mk1 / Mk2
PYL = [(26, 1, 12, 9), (54, 26, 9, 12), (26, 54, 12, 9), (1, 26, 9, 12)]     # N, E, S, W mounts
TIPS = [(32, 11), (52, 32), (32, 52), (11, 32)]
CORN = [(52, 11), (52, 52), (11, 52), (11, 11)]
def std_static(s, on):
    chamfer_fill(s, 1, 1, 61, 61, 'S', 6); rim(s, 'S', 'M', 'W')
    chamfer_fill(s, 4, 4, 55, 55, 'E', 5)
    chamfer_fill(s, 9, 9, 45, 45, 'W', 4); rim(s, 'W', 'S', 'E', (9, 9, 53, 53))
    chamfer_fill(s, 13, 13, 37, 37, 'E', 4)
    for (x, y, w, h) in PYL:
        bev(s, x, y, w, h, 'L', 'M', 'S'); s.rect(x + w // 2 - 2, y + h // 2 - 2, 4, 4, 'D')
    chamfer_fill(s, 20, 20, 24, 24, 'E', 7)
    if on: chamfer_fill(s, 21, 21, 22, 22, 'b', 6)
    else:
        chamfer_fill(s, 21, 21, 22, 22, 'W', 6); chamfer_fill(s, 23, 23, 10, 10, 'S', 3); s.put(25, 25, 'M'); s.put(26, 25, 'M')
        for (x, y, w, h) in PYL: s.put(x + w // 2 - 1, y + h // 2 - 1, 'W')

def std_dyn(s, i, mk2, spin=1.0, dim=False, rj=0):
    hot = (i // 2) % 4
    for k, (x, y, w, h) in enumerate(PYL):                         # pylon crystals take turns: N, E, S, W
        cx, cy = x + w // 2 - 2, y + h // 2 - 2
        s.rect(cx, cy, 4, 4, 'b'); s.put(cx + 3, cy + 3, 'E')
        if k == hot and not dim: s.put(cx, cy, 'c'); s.put(cx + 1, cy, 'H'); s.put(cx, cy + 1, 'c'); s.put(cx + 1, cy + 1, 'c')
        else: s.put(cx, cy, 'c' if (k - hot) % 4 == 3 and not dim else 'b'); s.put(cx, cy + 1, 'c' if not dim else 'b')
    for t in range(13, 50, 3):                                      # conduit lights, chasing round the ring
        for (x, y) in ((t, 11), (t, 52), (11, t), (52, t)): s.put(x, y, 'c' if ((t // 3) + i) % 5 == 0 and not dim else 'b')
    seg_ring(s, 32, 32, 15.4, 17.9, 8, .56, i * 5.625 * spin, 'b' if not dim else 'W', 'c' if not dim else 'M')
    if mk2: seg_ring(s, 32, 32, 12.0, 14.2, 6, .6, -i * 7.5 * spin, 'c' if not dim else 'S', 'H' if not dim else 'M', -1)
    seg_ring(s, 32, 32, 8.0, 10.3, 4, .5, (-1 if not mk2 else 1) * i * 11.25 * spin, 'c' if not dim else 'W', 'H' if not dim else 'M', -1 if not mk2 else 1)
    br = BR[i % 8] - 1 if not dim else (2, 3, 4, 5)[rj % 4]
    circle(s, 32, 32, br, 'c' if not dim else 'b'); circle(s, 32, 32, max(1, br - 2), 'H' if not dim else 'c')
    if not dim:
        for k in range(4): arc(s, TIPS[k], CORN[k], TIPS[(k + 1) % 4], i, k, 'b', 'c', 'H')
    else:
        arc(s, TIPS[rj % 4], CORN[rj % 4], TIPS[(rj + 1) % 4], rj, 0, 'b', 'c', 'H', nframes=4)

class ShieldMk1(ShieldBase):
    id = 'shield_mk1'
    MK2 = False
    notes = ('Concord Mk1. On loop (8 frames): an emitter ring turning clockwise round the dome while the dome petals turn the other way, energy arcs crawling between the four pylons, the pylon crystals lighting in turn N, E, S, W, the core breathing. '
             'hit (3): a white flare from the core and a ripple running out. recharge (4): the rings spinning up, core dim and growing. '
             'Damaged: the dome is cracked with a dark chip, the west pylon crystal is dead, a casing flap hangs off the lower-right corner. Disabled: dome shattered, west pylon smashed, casing split.')
    def static(self, s, on): std_static(s, on)
    def dyn(self, s, i, spin=1.0, dim=False, rj=0): std_dyn(s, i, self.MK2, spin, dim, rj)
    def glow_extra(self, g, ox, oy, i, k, flick=None):
        for kk, (x, y) in enumerate(((32, 5), (55, 32), (32, 59), (9, 32))):
            if flick is not None and kk == 3: continue
            hot = kk == (i // 2) % 4
            glow(g, ox + x, oy + y, 7 if hot else 4.5, BLUE, (0.6 if hot else 0.35) * k, 2.0)
    def hurt(self, s, i):
        crack(s, [(23, 21), (26, 25), (25, 29), (30, 32), (31, 37), (36, 41)], 'H')
        for (x, y) in ((33, 23), (34, 23), (34, 24), (35, 24), (33, 24)): s.put(x, y, 'D')
        s.rect(3, 29, 9, 6, 'D'); hollow(s, 3, 29, 9, 6, 'K'); s.put(6, 31, 'W'); s.put(5, 32, 'M'); s.put(8, 30 - i, 'y')
        s.stamp(46, 44, art("KKKK..\nKSMSK.\nKWSMSK\n.KKSWK\n...KKK")); s.stamp(54, 46, art(".K\nKD"))
        for (x, y) in ((17, 21), (18, 21), (18, 20), (19, 20)): s.put(x, y, 'K')
        stamp_on(s, 44, 12, SCORCH_S)
        s.put(30 + 5 * i, 28, 'y'); s.put(37, 33 - i, 'H' if i else 'y')
    def wreck(self, s):
        s.stamp(21, 21, art("..KKKKKKKK..\n.KDDKDDDDDK.\nKDDDDKDDDDDK\nKDKDDDDKDDDK\nKDDDKDDDDKDK\nKDDKDDKDDDDK\n.KDDDDDDKDK.\n..KKKKKKKK.."))
        crack(s, [(3, 4), (8, 8), (12, 14), (17, 19)]); crack(s, [(60, 60), (55, 55), (49, 52), (44, 48)])
        s.rect(3, 29, 9, 6, 'K'); s.stamp(4, 30, art("DD.D\n.DDK")); s.stamp(8, 33, art("K.K\nKSK"))
        s.stamp(46, 44, art("KKKK..\nKSWSK.\nKWSWSK\n.KKSWK")); stamp_on(s, 40, 12, SCORCH_L)
        for (x, y) in ((17, 21), (18, 21), (18, 20), (19, 20), (45, 40), (45, 41)): s.put(x, y, 'K')

class ShieldMk2(ShieldMk1):
    id = 'shield_mk2'; MK2 = True
    DMG = (3, 6)
    notes = ('Concord Mk2 (two layers): Mk1 plus a second ring counter-rotating inside the first, a thin outer ring round the dome with blue nodes, two layer pips, corner lamps and registry stencil. '
             'On loop (8): two emitter rings and the dome petals turning against each other, arcs crawling between the pylons, pylons lighting N, E, S, W, the core breathing. hit (3): flare and ripple. recharge (4): rings spinning up. '
             'Damaged: dome cracked with a dark chip, west pylon dead, a casing flap hangs off the lower-right corner, the outer ring has a gap. Disabled: dome shattered, west pylon smashed, casing split corner to corner.')
    def static(self, s, on):
        std_static(s, on)
        edge(s, 17, 17, 30, 30, 9, 'L' if on else 'S')
        for (x, y) in ((24, 18), (39, 18), (18, 24), (45, 39), (24, 45), (39, 45), (18, 39), (45, 24)): s.put(x, y, 'b' if on else 'M')
        for x in (29, 34): s.put(x, 22, 'b' if on else 'W')
        for (x, y) in ((6, 6), (56, 6), (6, 56), (56, 56)):
            s.rect(x, y, 2, 2, 'b' if on else 'W'); s.put(x, y, 'H' if on else 'M')
        stencil(s, 24, 58, 'L', 0); stencil(s, 38, 58, 'L', 2)

# ---------------------------------------------------------------- Bubble Rig (scrap)
class ShieldScrap(ShieldBase):
    id = 'shield_scrap_mk1'
    DMG = (2, 5)
    notes = ('Scrapper Clans "Bubble Rig": a salvaged emitter dish (a rim section replaced with rust plate, a dent bitten out of the opposite side) on a bolted girder scaffold with cross-braces and a taped upright. '
             'On loop (8): the rim lamps chase round clockwise while the tripod of feed struts turns the other way, arcs sputter between the strut tips (and drop out now and then), the horn bead breathes unevenly. '
             'hit (3): flare and ripple. recharge (4): the lamps and struts spinning up. '
             'Damaged: the dish has torn loose from the north strut and sags, the patch hangs by a bolt, the horn arcs and flickers. Disabled: the dish is cracked through and slid off its tripod, the horn snapped, a girder bent.')
    def static(self, s, on):
        chamfer_fill(s, 1, 1, 61, 61, 'W', 6); rim(s, 'W', 'S', 'E')
        chamfer_fill(s, 6, 6, 51, 51, 'D', 4)
        for (x, y, w, h, t) in ((1, 1, 61, 6, 'S'), (1, 56, 61, 6, 'M'), (1, 1, 6, 61, 'M'), (56, 1, 6, 61, 'S')): plate(s, x, y, w, h, t, False)
        for (x0, y0, x1, y1) in ((7, 7, 17, 17), (56, 7, 46, 17), (7, 56, 17, 46), (56, 56, 46, 46)): thick(s, x0, y0, x1, y1, 2, 'S', 'M', 'W')
        for (x0, y0, x1, y1) in ((7, 17, 17, 7), (56, 17, 46, 7), (7, 46, 17, 56), (56, 46, 46, 56)): line(s, x0, y0, x1, y1, 'W')
        bolts(s, [(2, 2), (58, 2), (2, 58), (58, 58), (30, 2), (30, 58), (2, 30), (58, 30)])
        weld(s, 12, 4, 10); weld(s, 38, 59, 10); hazard(s, 2, 14, 4, 14); weld(s, 59, 38, 8, True)
        s.rect(16, 2, 8, 5, 'u'); s.hline(16, 2, 8, 'Q'); s.hline(16, 6, 8, 'n'); bolts(s, [(17, 3), (21, 3)])
        circle(s, 32, 32, 21, 'K'); circle(s, 32, 32, 20, 'S'); ring(s, 32, 32, 19, 20, 'W')
        circle(s, 32, 32, 18.5, 'L'); ring(s, 32, 32, 17.5, 18.5, 'M')
        ring(s, 32, 32, 14, 16, 'M'); ring(s, 32, 32, 10.5, 13, 'M'); ring(s, 32, 32, 7.5, 10, 'M'); circle(s, 32, 32, 7, 'S')
        for (r0, r1, c) in ((16, 17, 'M'), (13, 14, 'S'), (10, 11, 'M'), (7, 8, 'S')): ring(s, 32, 32, r0, r1, c)
        for y in range(10, 54):
            for x in range(10, 54):
                if s.get(x, y) in ('M', 'L') and (x - 32) + (y - 32) > 10: s.put(x, y, 'S' if s.get(x, y) == 'M' else 'M')
        for (x, y) in [(32 + dx, 32 + dy) for dx in range(-18, 18) for dy in range(-18, 18) if 8 <= (dx * dx + dy * dy) ** .5 <= 17 and -14 < dx + dy < -8 and (dx + dy) % 2 == 0]: s.put(x, y, 'H')
        for y in range(11, 21):
            for x in range(42, 54):
                if s.get(x, y) in ('L', 'M', 'S', 'W') and (x - 32) ** 2 + (y - 32) ** 2 > 12 * 12: s.put(x, y, 'u' if (x + y) % 9 else 'q')
        for y in range(11, 21):
            for x in range(42, 54):
                if s.get(x, y) == 'u' and (s.get(x - 1, y) != 'u' or s.get(x, y - 1) != 'u'): s.put(x, y, 'Q')
        bolts(s, [(44, 14), (49, 17)])
        for (x, y) in ((16, 44), (17, 45), (18, 46), (15, 45), (16, 46), (17, 47)): s.put(x, y, 'W')
        for (x, y) in ((17, 44), (18, 45), (16, 47)): s.put(x, y, 'E')
        circle(s, 32, 32, 4.5, 'E'); circle(s, 32, 32, 3.5, 'W')
    TIPS_ = None
    def dyn(self, s, i, spin=1.0, dim=False, rj=0):
        stutter = [0, 1, 1, 2, 3, 3, 4, 5][i % 8]                   # the lamp chase stutters: a hand-rigged motor
        seg_ring(s, 32, 32, 17.3, 19.2, 12, .38, stutter * 7.5 * spin * (1 if not dim else 1.4), 'b' if not dim else 'M', 'c' if not dim else 'L')
        for k in range(3):                                           # tripod of feed struts, turning against the lamps
            a = math.radians(-i * 15.0 * spin + k * 120.0)
            tx, ty = 32 + 16.5 * math.sin(a), 32 - 16.5 * math.cos(a)
            line(s, 32, 32, int(round(tx)), int(round(ty)), 'E'); line(s, 33, 32, int(round(tx)) + 1, int(round(ty)), 'W')
            circle(s, tx, ty, 1.8, 'E'); s.put(int(tx) - 1, int(ty) - 1, 'L')
            tips = (tx, ty)
            if k == 0: t0 = tips
            if k == 1: t1 = tips
            if k == 2: t2 = tips
        circle(s, 32, 32, 4.5, 'E'); circle(s, 32, 32, 3.5, 'W')
        br = (BR[i % 8] - 2 + (i % 3 == 1)) if not dim else (1, 2, 3, 3)[rj % 4]       # uneven breathing
        circle(s, 32, 32, br, 'c' if not dim else 'b'); s.put(31, 31, 'H')
        if not dim:
            for (a_, b_, k) in ((t0, t1, 0), (t1, t2, 1), (t2, t0, 2)):
                mid = ((a_[0] + b_[0]) / 2 * 0.7 + 32 * 0.3, (a_[1] + b_[1]) / 2 * 0.7 + 32 * 0.3)
                if (i + k) % 5 != 3: arc(s, (int(a_[0]), int(a_[1])), mid, (int(b_[0]), int(b_[1])), i, k, 'b', 'c', 'H', drop=1)
        else:
            arc(s, (int(t0[0]), int(t0[1])), (32, 32), (int(t1[0]), int(t1[1])), rj, 0, 'b', 'c', 'H', nframes=4)
    def glow_extra(self, g, ox, oy, i, k, flick=None):
        inten = [1.0, 0.55, 0.8, 0.9, 0.45, 0.85, 0.6, 1.0][i % 8]            # flickers unevenly
        glow(g, ox + 32, oy + 32, 28, BLUE, 0.1 * inten * k, 1.4)
    def hurt(self, s, i):
        for (x, y) in [(32 + dx, 11 + dy) for dx in range(-4, 5) for dy in range(0, 3)]: s.put(x, y, 'D')
        s.hline(28, 13, 9, 'K'); s.put(27, 12, 'K'); s.put(37, 12, 'K')
        crack(s, [(46, 17), (44, 21), (47, 25)], 'M')
        s.rect(42, 11, 11, 4, '.'); s.rect(42, 11, 11, 3, 'K'); s.stamp(43, 14, art("uuuuu\nuQuQu\nn.nn.")); bolts(s, [(44, 15)])
        s.put(31, 31, 'D'); s.put(32, 32, 'D'); s.put(32, 31, 'y' if i else 'D'); s.put(31, 32, 'D' if i else 'y')
        for (x, y) in ((30, 26), (34, 24), (36, 37)): s.put(x, y, 'y' if i else 'H')
        stamp_on(s, 12, 12, SCORCH_S); stamp_on(s, 50, 48, SCORCH_S)
    def wreck(self, s):
        crack(s, [(15, 21), (22, 26), (25, 32), (33, 35), (40, 41), (48, 44)], 'M'); crack(s, [(25, 32), (22, 39), (24, 46)], 'M')
        s.stamp(30, 30, art(".KKKK.\nKDDDDK\nKDKKDK\n.KKKK.")); s.stamp(35, 18, art("KKK.\nKDDK\n.KDK\n..KK"))
        shear(s, 34, 54, 2, 12, 52)
        s.stamp(8, 8, art("KKKK\nKSMK\nKKSK")); s.stamp(50, 50, art("KK.\nKSK\n.KK"))
        stamp_on(s, 12, 40, SCORCH_L); stamp_on(s, 4, 20, SCORCH_S)
        for (x, y) in ((16, 44), (17, 45), (18, 46)): s.put(x, y, 'K')

# ---------------------------------------------------------------- Neon Lattice
PYLN = art("""
...cc...
..cHcC..
.cHHcCB.
.cHccCB.
.cHccCB.
.cHccCB.
.cHccCB.
.cHccCB.
.cHccCB.
.cHccCB.
.cccCCB.
..ccCB..
...CB...
""")
def pylon(s, x, y, vertical, level):
    ramp = {3: {'c': 'H', 'H': 'H', 'C': 'c', 'B': 'C'}, 2: {'c': 'c', 'H': 'H', 'C': 'C', 'B': 'B'}, 1: {'c': 'C', 'H': 'c', 'C': 'B', 'B': 'N'}, 0: {'c': 'W', 'H': 'M', 'C': 'E', 'B': 'D'}}[level]
    p = Spr(8, 13); p.stamp(0, 0, PYLN, ramp)
    if not vertical: p = p.transpose()
    for j in range(p.h):
        for i2 in range(p.w):
            if p.g[j][i2] != '.': s.put(x + i2, y + j, p.g[j][i2])

class ShieldNeon(ShieldBase):
    id = 'shield_neon_mk1'
    GLOW = CYAN
    DMG = (0, 4)
    PYLONS = [(28, 5, True), (51, 26, False), (28, 46, True), (5, 26, False)]
    ENDS = [(32, 14), (50, 32), (32, 50), (14, 32)]
    notes = ('Lumen "Neon Lattice": four crystal pylons (N, E, S, W) round a core, joined by a 1px cyan lattice that splits the field into four sectors. '
             'On loop (8): the pylons light in sequence N, E, S, W (two frames each) with an arc crawling along the lattice edge to the next pylon and that sector\'s magenta lamp lit; the core facets turn clockwise while a 4-segment ring counter-rotates; the core breathes. '
             'hit (3): flare and ripple. recharge (4): ring and facets spinning up. '
             'Damaged: the west pylon is dark and cracked, a lattice edge flickers out, the core is chipped. Disabled: pylons dull, the north pylon snapped off, core shattered, every lattice line dead.')
    def static(self, s, on):
        chamfer_fill(s, 1, 1, 61, 61, 'J', 6); rim(s, 'J', 'j', 'I')
        chamfer_fill(s, 4, 4, 55, 55, 'I', 5); edge(s, 4, 4, 55, 55, 5, 'c' if on else 'W')
        chamfer_fill(s, 7, 7, 49, 49, 'N', 4)
        for k in range(4):
            a, b = self.ENDS[k], self.ENDS[(k + 1) % 4]
            line(s, a[0], a[1], b[0], b[1], 'C' if on else 'E')
        for k, (x, y, vertical) in enumerate(self.PYLONS):
            if vertical: s.rect(31, 18 if k == 0 else 38, 2, 8, 'I'); s.vline(31, 18 if k == 0 else 38, 8, 'B' if on else 'E')
            else: s.rect(18 if k == 3 else 38, 31, 8, 2, 'I'); s.hline(18 if k == 3 else 38, 31, 8, 'B' if on else 'E')
        for k, (x, y) in enumerate(((46, 17), (46, 46), (17, 46), (17, 17))):
            s.rect(x - 1, y - 1, 3, 3, 'N'); s.put(x, y, 'P' if on else 'E')
        for (x, y) in ((11, 11), (52, 11), (11, 52), (52, 52)): s.put(x, y, 'B' if on else 'E')
        circle(s, 32, 32, 12, 'J'); ring(s, 32, 32, 11, 12, 'c' if on else 'W'); circle(s, 32, 32, 10.5, 'N')
        if not on:
            for y in range(25, 39):
                for x in range(25, 39):
                    dx, dy = x + .5 - 32, y + .5 - 32
                    if abs(dx) + abs(dy) <= 8 and abs(dx) <= 5 and abs(dy) <= 5: s.put(x, y, ('W', 'S', 'W', 'E')[octant(dx, dy) % 4])
            for k, (x, y, v) in enumerate(self.PYLONS): pylon(s, x, y, v, 0)
            for (x, y) in ((8, 8), (55, 8), (8, 55), (55, 55)): s.put(x, y, 'E')
            stencil(s, 24, 58, 'E', 3)
    def dyn(self, s, i, spin=1.0, dim=False, rj=0):
        hot = (i // 2) % 4
        ph = (i % 2)                                                   # second frame of a pylon's turn: the arc is half way along
        for k, (x, y, v) in enumerate(self.PYLONS):
            lvl = 3 if (k == hot and ph == 0) else 2 if k == hot else (2 if k == (hot - 1) % 4 and ph == 0 else 1)
            if dim: lvl = 1
            pylon(s, x, y, v, lvl)
        for k in range(4):
            lit = k == hot and not dim
            qx, qy = ((46, 17), (46, 46), (17, 46), (17, 17))[k]
            s.put(qx, qy, 'm' if lit else 'P')
            if lit:
                for (dx, dy) in ((0, -1), (-1, 0), (1, 0), (0, 1)): s.put(qx + dx, qy + dy, 'P')
            a, b = self.ENDS[k], self.ENDS[(k + 1) % 4]
            mid = ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)
            if lit: arc(s, a, mid, b, ph * 4 + 0, 0, 'C', 'c', 'H', nframes=8)
            else: line(s, a[0], a[1], b[0], b[1], 'c' if k == (hot - 1) % 4 and not dim else 'C')
            # radial conduit of the lit pylon
        for k, (x, y, v) in enumerate(self.PYLONS):
            lit = k == hot and not dim
            if v: s.vline(31, 18 if k == 0 else 38, 8, 'H' if lit else 'C')
            else: s.hline(18 if k == 3 else 38, 31, 8, 'H' if lit else 'C')
        # core: facets turn clockwise, a four-segment ring turns the other way, the core breathes
        tb = BR[i % 8] - 2 if not dim else (1, 2, 3, 4)[rj % 4]
        for y in range(25, 39):
            for x in range(25, 39):
                dx, dy = x + .5 - 32, y + .5 - 32
                if abs(dx) + abs(dy) <= 8 and abs(dx) <= 5 and abs(dy) <= 5:
                    k = octant(dx, dy)
                    tone = ['H', 'c', 'C', 'B', 'B', 'C', 'c', 'c'][(k - int(i * spin)) % 8] if not dim else ['C', 'B', 'C', 'B', 'B', 'C', 'B', 'B'][(k - i) % 8]
                    s.put(x, y, tone)
        circle(s, 32, 32, max(1, tb - 1), 'H' if not dim else 'c')
        seg_ring(s, 32, 32, 8.9, 10.3, 4, .5, -i * 11.25 * spin, 'c' if not dim else 'C', 'H' if not dim else 'c', -1)
    def glow_extra(self, g, ox, oy, i, k, flick=None):
        hot = (i // 2) % 4
        for kk, (x, y) in enumerate(((32, 11), (55, 32), (32, 53), (9, 32))):
            if flick is not None and kk == 3: continue
            glow(g, ox + x, oy + y, 12 if kk == hot else 6, CYAN, (0.6 if kk == hot else 0.2) * k, 1.8)
        q = [(46, 17), (46, 46), (17, 46), (17, 17)][hot]
        glow(g, ox + q[0] + .5, oy + q[1] + .5, 6, MAGENTA, 0.5 * k, 2.0)
    def hurt(self, s, i):
        x, y, v = self.PYLONS[3]
        s.rect(x - 1, y - 1, 12, 10, 'N'); pylon(s, x, y, v, 0)
        crack(s, [(x + 1, y + 2), (x + 4, y + 4), (x + 3, y + 6), (x + 8, y + 7)], 'H' if i else 'M')
        s.stamp(x + 7, y - 2 - i, art("K.K\nKcK"))
        crack(s, [(29, 28), (32, 31), (31, 35), (35, 37)], 'H')
        for (xx, yy) in ((34, 28), (35, 28), (35, 29)): s.put(xx, yy, 'N')
        a, b = (45, 32), (32, 45)
        for t in range(0, 14):
            if (t + i) % 3 == 0: s.put(a[0] - t, a[1] + t, 'N')
        s.stamp(46, 46, art("..K..\n.KcK.\nKCBBK\n.KKK.")); s.put(44 + i % 2, 47, 'H')
        stamp_on(s, 12, 40, SCORCH_S)
        for (xx, yy) in ((20, 4), (21, 4), (22, 4), (59, 20), (59, 21)): s.put(xx, yy, 'B' if i % 2 else 'N')
    def wreck(self, s):
        x, y, v = self.PYLONS[0]
        s.rect(x - 1, y - 1, 10, 15, 'N'); s.stamp(x, y + 6, art("..K.K...\n.KDKNK..\nKDDNDDK.\nKDKDDKK.\n.KKKK..."))
        s.stamp(x + 3, y + 14, art("KK..\nKSMK\n.KSK")); s.stamp(40, 8, art(".KK\nKSM\n.K."))
        x, y, v = self.PYLONS[3]; s.stamp(x + 1, y + 2, art("K.K\nKSK"))
        crack(s, [(26, 26), (29, 29), (28, 33), (33, 35), (37, 39)], 'M'); s.stamp(29, 29, art("KKKK\nKNNK\nKNKK\n.KK."))
        crack(s, [(48, 49), (52, 50), (55, 54)], 'M'); stamp_on(s, 12, 40, SCORCH_S); stamp_on(s, 46, 40, SCORCH_L)

# ---------------------------------------------------------------- Mirror Veil (unique, standard family)
class MirrorVeil(ShieldBase):
    id = 'mirror_veil'
    DMG = (2, 6)
    notes = ('Unique. A polished mirror dish in a standard blue-steel frame with gold trim (edge line, corner brackets, boss). '
             'On loop (8): two glints sweep diagonally across the mirror, the gold rim segments turn clockwise while the inner facet ring turns the other way, bright reflection arcs crawl between the four gold mounts, the gold boss breathes. '
             'hit (3): a white flare and ripple, the mirror flashing. recharge (4): the gold rim and facet ring spinning up. '
             'Damaged: a crack spreads over the glass with a dark chipped wedge, the trim is bent at one corner. Disabled: the mirror shattered to dull shards with a hole, the trim dead and scorched.')
    TIPS_ = [(32, 14), (50, 32), (32, 50), (14, 32)]
    CORN_ = [(50, 14), (50, 50), (14, 50), (14, 14)]
    def static(self, s, on):
        chamfer_fill(s, 1, 1, 61, 61, 'S', 6); rim(s, 'S', 'M', 'W')
        chamfer_fill(s, 4, 4, 55, 55, 'E', 5)
        edge(s, 4, 4, 55, 55, 5, 'a')
        for (x, y) in ((5, 12), (6, 13), (12, 5), (13, 6)): s.put(x, y, 'y' if (x, y) in ((5, 12), (12, 5)) else 'a')
        for (cx, cy, sx, sy) in ((5, 5, 1, 1), (58, 5, -1, 1), (5, 58, 1, -1), (58, 58, -1, -1)):
            for d in range(0, 6): s.put(cx + sx * d, cy, 'a'); s.put(cx, cy + sy * d, 'a')
            s.put(cx, cy, 'y'); s.put(cx + sx, cy + sy, 'a')
        for (x, y, w, h) in ((26, 7, 12, 7), (26, 50, 12, 7), (7, 26, 7, 12), (50, 26, 7, 12)):
            bev(s, x, y, w, h, 'L', 'M', 'S'); cx, cy = x + w // 2 - 1, y + h // 2 - 1
            s.rect(cx, cy, 2, 2, 'a'); s.put(cx, cy, 'y')
        circle(s, 32, 32, 21, 'K'); circle(s, 32, 32, 20, 'a'); ring(s, 32, 32, 19, 20, 'a')
        for (x, y) in [(x, y) for x in range(10, 54) for y in range(10, 54) if s.get(x, y) == 'a' and (x - 32) + (y - 32) < -12]: s.put(x, y, 'y')
        for (x, y) in [(x, y) for x in range(10, 54) for y in range(10, 54) if s.get(x, y) == 'a' and (x - 32) + (y - 32) > 14]: s.put(x, y, 'u')
        circle(s, 32, 32, 18.5, 'S')
        for y in range(10, 54):
            for x in range(10, 54):
                if s.get(x, y) != 'S': continue
                dx, dy = x + .5 - 32, y + .5 - 32
                if dx * dx + dy * dy > 17.8 ** 2: continue
                d = dx + dy
                s.put(x, y, 'L' if d < -14 else ('M' if d < 8 else ('S' if d < 20 else 'W')))
        for r in (7.5, 12.5): ring(s, 32, 32, r, r + 1, 'S')
        for (x, y) in [(x, y) for x in range(10, 54) for y in range(10, 54) if s.get(x, y) == 'S' and (x - 32) + (y - 32) < -2]: s.put(x, y, 'M')
        ring(s, 32, 32, 17.4, 18.4, 'W')
        for (x, y) in ((24, 38), (40, 24), (38, 41), (25, 27)): s.put(x, y, 'b' if on else 'S')
        circle(s, 32, 32, 4.5, 'K'); circle(s, 32, 32, 3.6, 'a'); circle(s, 31.5, 31.5, 2.2, 'y'); s.put(30, 30, 'H'); s.put(33, 33, 'u')
        stencil(s, 28, 59, 'y', 1)
    def dyn(self, s, i, spin=1.0, dim=False, rj=0):
        for gl, off in ((0, 0), (1, 0)):                                       # two glints, one diagonal sweep each
            g0 = (14 + (i * 13 + gl * 52) % 104) if not dim else (14 + (rj * 26 + gl * 52) % 104)
            for y in range(10, 54):
                for x in range(10, 54):
                    if s.get(x, y) in 'LMSW' and (x - 32) ** 2 + (y - 32) ** 2 <= 17.2 ** 2 and ((x + y) in (g0, g0 + 1) or (x + y) == g0 + 4):
                        s.put(x, y, 'H' if (x + y) <= g0 + 1 else 'L')
        seg_ring(s, 32, 32, 19.0, 20.4, 12, .5, i * 7.5 * spin, 'y', 'H', 1)       # gold rim segments turn clockwise
        seg_ring(s, 32, 32, 8.2, 10.0, 6, .5, -i * 7.5 * spin, 'H' if not dim else 'M', 'L', -1)   # facet ring turns back
        br = BR[i % 8] - 3 if not dim else (1, 2, 2, 3)[rj % 4]                  # the gold boss breathes
        ring_ex(s, 32, 32, 4.6, 4.6 + 1.0 + br * .4, 'y' if not dim else 'a')
        for k in range(4):
            if not dim: arc(s, self.TIPS_[k], self.CORN_[k], self.TIPS_[(k + 1) % 4], i, k, 'b', 'H', 'H', drop=2)
        if dim: arc(s, self.TIPS_[rj % 4], self.CORN_[rj % 4], self.TIPS_[(rj + 1) % 4], rj, 0, 'b', 'H', 'H', nframes=4)
        for (x, y) in ((24, 38), (40, 24), (38, 41), (25, 27)): s.put(x, y, 'b' if (x + y + i) % 3 else 'c')
    def glow_extra(self, g, ox, oy, i, k, flick=None):
        for (x, y) in ((32, 10.5), (32, 53.5), (10.5, 32), (53.5, 32)): glow(g, ox + x, oy + y, 4.5, AMBER, 0.45 * k, 2.0)
        gx = (14 + (i * 13) % 104) / 2.0
        glow(g, ox + gx, oy + gx, 8, (235, 245, 255), 0.3 * k, 1.8)
        glow(g, ox + 32, oy + 32, 6, YEL, 0.4 * k, 1.8)
    def hurt(self, s, i):
        crack(s, [(32, 32), (28, 27), (30, 22), (25, 17), (27, 12)], 'H'); crack(s, [(32, 32), (38, 29), (42, 31), (47, 27)], 'H'); crack(s, [(32, 32), (35, 38), (33, 44), (37, 49)], 'H')
        s.stamp(37, 36, art("KKKKK.\nKDDDDK\n.KDDKK\n..KKK.")); s.put(40, 38, 'W')
        for (x, y) in ((53, 14), (54, 15), (55, 16), (55, 17)): s.put(x, y, 'K')
        for (x, y) in ((52, 13), (53, 13)): s.put(x, y, 'u')
        for (x, y) in ((6, 6), (7, 5)): s.put(x, y, 'u')
        s.put(35 + 3 * (i % 2), 30, 'H'); s.put(23, 41 - 2 * (i % 2), 'y')
        if i % 2: stamp_on(s, 12, 44, SCORCH_S)
    def wreck(self, s):
        s.stamp(24, 26, art("KKKKKKKK..\nKDDKDDDDK.\nKDKDKDDDDK\nKKDDDKDKDK\n.KDKDDDDDK\n..KKDKKKKK"))
        crack(s, [(32, 32), (26, 22), (28, 15), (24, 12)], 'M'); crack(s, [(32, 32), (41, 28), (47, 30)], 'M'); crack(s, [(32, 32), (36, 42), (31, 48)], 'M')
        for (x, y, c) in ((19, 21, 'D'), (44, 38, 'D'), (40, 20, 'E'), (22, 40, 'E')): s.stamp(x, y, art("KK.\nKcK".replace('c', c)))
        s.stamp(46, 44, art("KKK.\nKMSK\n.KSK")); stamp_on(s, 12, 44, SCORCH_L); stamp_on(s, 44, 8, SCORCH_S)
        for (x, y) in ((53, 14), (54, 15), (55, 16), (55, 17), (6, 6), (7, 5)): s.put(x, y, 'K')

ALL = [ShieldMk1, ShieldMk2, ShieldScrap, ShieldNeon, MirrorVeil]
