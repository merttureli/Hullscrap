"""Prismatic racial tech (docs/waves/racial_tech_1.md): crystal-born. Housings of faceted violet and navy with cyan, magenta and white light cores, cut at the corners like gems; every lens splits its light.
Weapons: prismatic_prism_lens (fixed beam), prismatic_refractor (fixed), prismatic_glimmer_turret (turret). Components: prismatic_lattice_shield, prismatic_song_reactor, prismatic_resonance_helm."""
from tech_kit import *
from lines_kit import LComp, crack as lcrack, line as lline, circle as lcircle, ring as lring
from comp_base import stamp_on, SCORCH_S, SCORCH_L

HT = ('V', 'Z', 'N'); HT2 = ('j', 'J', 'I')
DK = {'V': 'S', 'Z': 'W', 'N': 'D', 'X': 'M', 'c': 'W', 'C': 'E', 'B': 'D', 'm': 'E', 'P': 'D', 'I': 'D', 'J': 'E', 'j': 'W', 'H': 'M', 'y': 'u'}
RAIN = {'o': 'm', 'y': 'c'}
F_RAIN = flash_arts(RAIN)

def gem_h(b, cx, cy, hl, hw, tones=('c', 'C', 'B'), lit=True):
    """a crystal lying along x (pointing east): lit upper facet, mid body, dark lower facet, a white ridge when lit."""
    top, bot = (cx - hl * 0.3, cy - hw), (cx - hl * 0.3, cy + hw)
    tail, tip = (cx - hl, cy), (cx + hl, cy)
    fillpoly(b, [tail, top, tip, bot], tones[1])
    fillpoly(b, [tail, bot, tip], tones[2])
    fillpoly(b, [tail, top, (cx + hl * 0.2, cy - hw * 0.2)], tones[0])
    if lit:
        for x in range(int(cx - hl * 0.4), int(cx + hl * 0.8)): b.put(x, int(cy), 'H') if x % 2 == 0 else None

def facet_panel(s, x, y, w, h, t1=('V', 'Z'), t2=('Z', 'N')):
    """a rectangle cut by its diagonal into two facets, light top-left."""
    fillpoly(s, [(x, y), (x + w, y), (x, y + h)], t1[0]); fillpoly(s, [(x + w, y), (x + w, y + h), (x, y + h)], t2[1])
    fillpoly(s, [(x + 1, y + 1), (x + w - 1, y + 1), (x + 1, y + h - 1)], t1[1]) if w > 4 else None
    s.hline(x, y, w, t1[0]); s.vline(x, y, h, t1[0])

def lens_ring(s, cx, cy, r, lit, i=0):
    """a round lens: steel ring, dark well, a cyan core that splits into a magenta fringe."""
    lcircle(s, cx, cy, r, 'M'); lcircle(s, cx, cy, r - 1, 'D'); lcircle(s, cx, cy, r - 2, 'c' if lit else 'E')
    if lit: s.put(cx - 1, cy - 1, 'H'); s.put(cx + 1, cy, 'm') if r > 3 else None
    s.put(cx - r + 1, cy - r + 1, 'L')

class PrismW(RW):
    HT = HT; FT = HT; CH = ('m', 'P', 'H'); DK = DK
    LIVE = RGB_['magenta']; READY = (200, 250, 255)
    def flange_trim(self, s, st, half, y):
        for x in (4, 13, 50, 59): s.put(x, y + 2, 'X')
        s.hline(18, y + 2, 28, 'c' if st.powered else 'E')
        for x in range(21, 44, 7): s.put(x, y + 2, 'm' if st.powered else 'E')
    def rstrip(self, s, st, y0):
        """five small crystals: dark grey when empty, magenta while charging, cyan-white when ready."""
        y = y0 + STRIP_DY
        recess(s, STRIP_X - 2, y - 1, 5 * 8 + 2, 7, 'N', 'K')
        for k in range(5):
            cx = STRIP_X + k * 8 + 3; on = st.powered and k < st.lit
            if getattr(st, 'flash', False) and st.powered: tn = ('H', 'H', 'L')
            elif on and st.ready: tn = ('H', 'c', 'C')
            elif on: tn = ('m', 'm', 'P')
            else: tn = ('W', 'E', 'D')
            fillpoly(s, [(cx - 3, y + 2.5), (cx, y - 0.3), (cx + 3, y + 2.5), (cx, y + 5.3)], tn[1]); fillpoly(s, [(cx, y - 0.3), (cx + 3, y + 2.5), (cx, y + 5.3)], tn[2]); s.put(cx - 1, y + 1, tn[0])
    def pgun_housing(self, s, cy=12, bw=26, bh=26, out_h=32):
        """fixed gun, outside: the standard forward-heavy block, but cut like a gem (angled corners) in violet with a cyan edge."""
        x0, top = self.rgun_housing(s, cy, bw, bh, out_h)
        for (cx_, cy_, dx, dy) in ((x0, top, 1, 1), (x0 + bw - 1, top, -1, 1)):         # cut the corners of the block
            for k in range(3): s.erase(cx_ + dx * 0, cy_ + k * 0) if False else None
        s.hline(x0 + 2, top + 2, bw - 4, 'c'); s.put(x0 + 1, top + 3, 'c'); s.put(x0 + bw - 2, top + 3, 'c')
        return x0, top

# ============================================================ PRISM LENS (fixed beam)
class PrismLens(PrismW):
    id = 'prismatic_prism_lens'; aim = 'fixed'
    blen, bwid = 60, 19
    bpivot = (6, 9)
    bmuzzle = (46, 9)
    out_notes = ('OUTSIDE half of the Prismatic Prism Lens (a FIXED beam gun, crystal): a violet housing with a cyan edge, a cluster of three crystals (cyan, magenta, violet) on the left and a stack of three round lenses on the right that light one after the other. '
                 'damaged: a crystal is cracked and flickers, a lens is dark; disabled: scorched grey, the crystals dull and one snapped, never destroyed.')
    notes = ('INSIDE half of the Prismatic Prism Lens: a big cyan crystal in a violet cradle with light shafts to two small lenses, a steel hatch, power coupling and five crystals that light magenta while charging and cyan-white when ready. '
             'fire: the crystals flash white. damaged: the crystal is cracked and flickers, two crystals dark; disabled: the crystal split and dull. '
             'Barrel layer prismatic_prism_lens_barrel: a long violet tube with cyan inlays, a focusing lens ring and a glass prism at the tip; fire: a white beam splits into magenta, cyan and yellow at the prism.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.pgun_housing(s)
        facet_panel(s, 3, 6, 16, 18, ('V', 'Z'), ('Z', 'N'))
        for (gx, gy, hw, hh, tn) in ((7, 18, 3, 5, ('c', 'C', 'B')), (13, 15, 3, 7, ('m', 'm', 'P')), (10, 12, 2, 4, ('X', 'V', 'Z'))):
            gem(s, gx, gy, hw, hh, tn if pw else ('S', 'W', 'E'), lit=pw)
        facet_panel(s, 45, 6, 16, 18, ('V', 'Z'), ('Z', 'N'))
        for k, ly in enumerate((11, 16, 21)): lens_ring(s, 53, ly, 3, pw and (k + i) % 3 != 0)
        for (x, y) in ((46, 7), (59, 7), (46, 22)): s.put(x, y, 'X')
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        facet_panel(s, 15, y + 4, 32, 17, ('Z', 'N'), ('N', 'N'))
        gem(s, 31, y + 12, 7, 8, ('c', 'C', 'B') if pw else ('S', 'W', 'E'), lit=pw)
        if pw:
            for k in range(6): s.put(18 + k * 2, y + 12 + (k % 2), 'c' if k % 2 else 'H'); s.put(40 + k * 2, y + 12 - (k % 2), 'm' if k % 2 else 'H')
        lens_ring(s, 18, y + 12, 3, pw); lens_ring(s, 44, y + 12, 3, pw)
        hatch(s, 50, y + 7, st, 10, 11)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        s.rect(3, 6, 16, 18, 'N'); facet_panel(s, 3, 6, 16, 18, ('V', 'Z'), ('Z', 'N'))
        gem(s, 7, 18, 3, 5, ('c', 'C', 'B'), lit=st.i == 0); gem(s, 13, 17, 3, 5, ('m', 'm', 'P'), lit=True); lcrack(s, [(13, 12), (12, 16), (14, 20)], 'L') if False else crack(s, [(13, 12), (12, 16), (14, 20)])
        lens_ring(s, 53, 21, 3, False); lens_ring(s, 53, 16, 3, st.i == 1)
        spark(s, 9, 8, False) if st.i else spark(s, 57, 10, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(10, 8), (9, 14), (11, 20)], [(53, 8), (52, 14), (54, 20)]], dents=[(46, 20, 6, 3), (22, 4, 6, 4)],
                 soots=[(4, 8, 0), (47, 6, 1), (30, 12, 2)], wires_=[], sparks=[(14, 10), (56, 6)])
        s.rect(5, 7, 12, 8, '.'); s.stamp(6, 15, art("KSK\nKSSK\n.KEK"))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(29, y + 6), (30, y + 11), (28, y + 17)]); s.rect(31, y + 12, 3, 2, 'E') if st.i else None
        spark(s, 55, y + 20, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(27, y + 5), (31, y + 12), (29, y + 18)]); crack(s, [(35, y + 5), (34, y + 12)])
        s.rect(33, y + 6, 4, 12, 'D'); wire(s, [(14, y + 21), (16, y + 24), (22, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 31, oy + y + 12, 14, RGB_['cyan'], 0.3, 2.0, sx=1.5)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['cyan'], 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 10, oy + 14, 9, RGB_['cyan'], 0.25, 2.0); glow(g, ox + 53.5, oy + 11 + 5 * ((2 * i) % 3), 5, RGB_['cyan'], 0.45, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 13 + o, 3, 28, 13, 'XVVZZNN')                                   # the violet tube
        b.hline(13 + o, 9, 28, 'c')                                              # a cyan inlay along it
        for bx in (17, 33):
            b.rect(bx + o, 2, 2, 15, 'X'); b.vline(bx + o + 1, 2, 15, 'Z')
        lens_ring(b, 26 + o, 9, 6, True)                                         # the focusing lens ring
        fillpoly(b, [(40 + o, 2), (40 + o, 16), (50 + o, 9)], 'L'); fillpoly(b, [(40 + o, 2), (50 + o, 9), (44 + o, 9)], 'H'); fillpoly(b, [(40 + o, 16), (50 + o, 9), (44 + o, 10)], 'M')
        for (x, y_, c) in ((41, 3, 'c'), (41, 15, 'm'), (45, 5, 'm'), (45, 13, 'c')): b.put(x + o, y_, c)
        breech(b, 9, 15, *HT)
    def bhurt(self, b, st):
        crack(b, [(20, 3), (21, 8), (19, 13)], 'K', 'M'); b.rect(26, 4, 5, 3, 'E')
        move(b, 40, 2, 11, 15, 0, 2)
        spark(b, 36, 7, False) if st.i == 0 else spark(b, 22, 16, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 38, 2, 3)
    def bwreck(self, b, st):
        b.stamp(36, 7, art("KSS\nKSE")); crack(b, [(16, 3), (17, 8), (15, 14)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire:
            stamp_flash(b, st, 51, 9, F_RAIN)
            for (dy, c) in ((-1, 'c'), (0, 'H'), (1, 'm')):
                n = (14, 9, 4)[st.i]
                for k in range(n): b.put(52 + k, 9 + dy * (1 + k // 2) if dy else 9, c) if (52 + k) < b.w else None
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 49, 9, rgb=(160, 110, 230), core=(244, 246, 248), scale=1.0)
        if state == 'idle': glow(g, ox + 26.5, oy + 9.5, 7, RGB_['cyan'], 0.35, 2.0); glow(g, ox + 46, oy + 9.5, 4, RGB_['magenta'], 0.3, 2.0)

# ============================================================ REFRACTOR (fixed)
class Refractor(PrismW):
    id = 'prismatic_refractor'; aim = 'fixed'
    blen, bwid = 54, 21
    bpivot = (6, 10)
    bmuzzle = (42, 10)
    out_notes = ('OUTSIDE half of the Prismatic Refractor (a FIXED gun): a violet housing, a stack of shard crystals on the left and a faceted diamond mirror on the right that glints on the loop. '
                 'damaged: a shard is snapped and the mirror cracked; disabled: scorched grey, the shards dull and fallen, never destroyed.')
    notes = ('INSIDE half of the Prismatic Refractor: three small crystals in a row with a thin light line passing through them that splits into colours, a steel hatch, power coupling and five crystals. '
             'damaged: the middle crystal cracked and dark, lines flicker; disabled: crystals split and dull. '
             'Barrel layer prismatic_refractor_barrel: a short violet barrel ending in a big faceted crystal head; fire: three shards leave the head fanning out, flashing.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.pgun_housing(s)
        facet_panel(s, 3, 6, 16, 18, ('V', 'Z'), ('Z', 'N'))
        for (gx, gy, hw, hh, tn) in ((6, 19, 2, 6, ('c', 'C', 'B')), (10, 16, 2, 8, ('X', 'V', 'Z')), (15, 19, 2, 6, ('c', 'C', 'B'))):
            gem(s, gx, gy, hw, hh, tn if pw else ('S', 'W', 'E'), lit=pw)
        facet_panel(s, 45, 6, 16, 18, ('V', 'Z'), ('Z', 'N'))
        fillpoly(s, [(53, 8), (59, 15), (53, 22), (47, 15)], 'M' if pw else 'S'); fillpoly(s, [(53, 8), (59, 15), (53, 15)], 'L'); fillpoly(s, [(53, 15), (59, 15), (53, 22)], 'W')
        s.put(51 + i * 3, 13, 'H' if pw else 'L'); s.put(52 + i * 3, 12, 'H') if pw else None
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        facet_panel(s, 15, y + 4, 32, 17, ('Z', 'N'), ('N', 'N'))
        for k, gx in enumerate((22, 31, 40)): gem(s, gx, y + 12, 3, 5, ('c', 'C', 'B') if pw else ('S', 'W', 'E'), lit=pw)
        if pw:
            for x in range(16, 47):
                if s.get(x, y + 12) in ('D', 'N', 'Z', 'V', '.'): s.put(x, y + 12, 'H' if x < 27 else ('c' if (x + i) % 2 else 'm'))
            for k in range(3): s.put(44 + k, y + 12 - (k + 1), 'c'); s.put(44 + k, y + 12 + (k + 1), 'm')
        hatch(s, 50, y + 7, st, 10, 11)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        s.rect(3, 6, 16, 18, 'N'); facet_panel(s, 3, 6, 16, 18, ('V', 'Z'), ('Z', 'N'))
        gem(s, 6, 19, 2, 6, ('c', 'C', 'B'), lit=st.i == 0); s.rect(9, 8, 3, 5, '.'); gem(s, 10, 19, 2, 4, ('X', 'V', 'Z'), lit=False); gem(s, 15, 19, 2, 6, ('c', 'C', 'B'), lit=True)
        crack(s, [(50, 12), (53, 15), (51, 19)]); spark(s, 12, 9, False) if st.i else spark(s, 58, 10, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(10, 8), (9, 14), (11, 20)], [(53, 8), (52, 14), (54, 20)]], dents=[(46, 20, 6, 3), (22, 4, 6, 4)],
                 soots=[(4, 8, 0), (47, 6, 1), (30, 12, 2)], wires_=[], sparks=[(14, 10), (56, 6)])
        s.rect(4, 7, 14, 10, '.'); s.stamp(6, 16, art("KSK\nKSSK\n.KEK")); s.stamp(12, 18, art("KK\nKS"))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        s.rect(29, y + 7, 5, 11, 'N'); crack(s, [(31, y + 7), (30, y + 12), (32, y + 17)]); gem(s, 31, y + 12, 3, 5, ('S', 'W', 'E'), lit=False)
        spark(s, 55, y + 20, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        for gx in (22, 31, 40): s.rect(gx - 3, y + 7, 7, 11, 'N'); gem(s, gx, y + 14, 3, 3, ('S', 'W', 'E'), lit=False)
        crack(s, [(27, y + 5), (31, y + 12), (29, y + 18)]); wire(s, [(14, y + 21), (16, y + 24), (22, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        for gx in (22, 31, 40): glow(g, ox + gx + .5, oy + y + 12, 6, RGB_['cyan'], 0.3, 2.0)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['cyan'], 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 10, oy + 15, 9, RGB_['cyan'], 0.25, 2.0); glow(g, ox + 53, oy + 15, 7, RGB_['magenta'], 0.2 + 0.1 * i, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 13 + o, 5, 18, 11, 'XVVZZNN'); b.hline(13 + o, 10, 18, 'c')
        for bx in (17, 25): b.rect(bx + o, 4, 2, 13, 'X'); b.vline(bx + o + 1, 4, 13, 'Z')
        gem_h(b, 36 + o, 10, 9, 9, ('c', 'C', 'B') if not st.fire else ('H', 'c', 'C'), True)                  # the faceted head
        for (x, y_, c) in ((33, 5, 'm'), (40, 14, 'm'), (30, 10, 'H')): b.put(x + o, y_, c)
        breech(b, 10, 15, *HT)
    def bhurt(self, b, st):
        b.rect(34, 1, 12, 8, '.'); gem_h(b, 37, 12, 8, 6, ('c', 'C', 'B'), st.i == 0); crack(b, [(20, 5), (21, 9), (19, 14)], 'K', 'M')
        b.stamp(41, 3, art("KS\nSK"))
        spark(b, 40, 6, False) if st.i == 0 else spark(b, 28, 16, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 30, 2, 3)
    def bwreck(self, b, st):
        b.stamp(31, 9, art("KSS\nKSE")); crack(b, [(16, 5), (17, 10), (15, 15)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire:
            n = (3, 2, 1)[st.i]
            for k in range(n):
                for (dy, c) in ((-1, 'c'), (0, 'H'), (1, 'm')):
                    sx, sy = 46 + st.i * 4 + k, 10 + dy * (3 + st.i * 3)
                    fillpoly(b, [(sx, sy - 1), (sx + 3, sy), (sx, sy + 1)], c) if k == 0 else None
            stamp_flash(b, st, 49, 10, F_RAIN)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 47, 10, rgb=(160, 110, 230), core=(200, 250, 255), scale=1.0)
        if state == 'idle': glow(g, ox + 37, oy + 10.5, 9, RGB_['cyan'], 0.3, 2.0)

# ============================================================ GLIMMER TURRET (turret)
class GlimmerTurret(PrismW):
    id = 'prismatic_glimmer_turret'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 44, 23
    bpivot = (8, 11)
    bmuzzle = (32, 11)
    out_notes = ('OUTSIDE half of the Prismatic Glimmer Turret (a TURRET, crystal): a violet turret seat cut like a gem, a tall cyan crystal on the left that glints on the loop and a magenta lens on the right. '
                 'damaged: the crystal is cracked and flickers, the lens dark; disabled: scorched grey, the crystal snapped, never destroyed.')
    notes = ('INSIDE half of the Prismatic Glimmer Turret: a single tall crystal on a violet pedestal with two small light-guides, a steel hatch, power coupling and five crystals. '
             'damaged: the crystal cracked and dark; disabled: split and dull. The rotating head prismatic_glimmer_turret_barrel swivels in the ring: a violet ring head carrying a floating faceted crystal that points where it aims, two orbiting shards and a sensor crystal; fire: the crystal flares and a bright shard darts out.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.rturret_seat(s, 15)
        hi, mid, lo = HT
        facet_panel(s, 3, 6, 16, 18, ('V', 'Z'), ('Z', 'N'))
        gem(s, 11, 15, 4, 9, ('c', 'C', 'B') if pw else ('S', 'W', 'E'), lit=pw)
        if pw: s.put(10 + i * 2, 9 + i * 3, 'H')
        facet_panel(s, 45, 6, 16, 18, ('V', 'Z'), ('Z', 'N'))
        lens_ring(s, 53, 15, 5, pw, i); lcircle(s, 53, 15, 1.2, 'm' if pw else 'E')
        for (x, y) in ((24, 8), (40, 8), (24, 22), (40, 22)): s.put(x, y, 'X')
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        facet_panel(s, 15, y + 4, 32, 17, ('Z', 'N'), ('N', 'N'))
        fillpoly(s, [(26, y + 19), (36, y + 19), (34, y + 16), (28, y + 16)], 'V')
        gem(s, 31, y + 11, 5, 8, ('c', 'C', 'B') if pw else ('S', 'W', 'E'), lit=pw)
        lens_ring(s, 19, y + 12, 3, pw); lens_ring(s, 43, y + 12, 3, pw)
        hatch(s, 50, y + 7, st, 10, 11)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        s.rect(3, 6, 16, 18, 'N'); facet_panel(s, 3, 6, 16, 18, ('V', 'Z'), ('Z', 'N'))
        gem(s, 11, 15, 4, 9, ('c', 'C', 'B'), lit=st.i == 0); crack(s, [(11, 7), (10, 12), (12, 17), (11, 22)])
        lens_ring(s, 53, 15, 5, False)
        spark(s, 14, 8, False) if st.i else spark(s, 56, 9, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(24, 8), (26, 12), (25, 16)], [(52, 7), (53, 12), (51, 17)]], dents=[(46, 20, 6, 3), (6, 20, 5, 4)],
                 soots=[(20, 3, 0), (46, 5, 1), (8, 7, 2)], wires_=[], sparks=[(30, 6), (12, 10)])
        s.rect(4, 6, 14, 10, '.'); s.stamp(7, 16, art("KSK\nKSSK\n.KEK"))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(31, y + 6), (30, y + 11), (32, y + 16)]); gem(s, 31, y + 11, 5, 8, ('S', 'W', 'E'), lit=False) if st.i else None
        spark(s, 55, y + 20, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        s.rect(26, y + 5, 11, 12, 'N'); gem(s, 31, y + 14, 4, 3, ('S', 'W', 'E'), lit=False)
        crack(s, [(27, y + 5), (31, y + 12)]); wire(s, [(14, y + 21), (16, y + 24), (22, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 31, oy + y + 11, 11, RGB_['cyan'], 0.3, 2.0)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['cyan'], 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 11, oy + 15, 10, RGB_['cyan'], 0.3, 2.0); glow(g, ox + 53.5, oy + 15.5, 6, RGB_['magenta'], 0.4, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        hub(b, 11, 17, 'Z', 'V', 'N')
        gem_h(b, 24 + o, 11, 8, 6, ('c', 'C', 'B') if not st.fire else ('H', 'c', 'C'), True)               # the floating crystal
        for (sx, sy) in ((18, 3), (18, 19)): gem_h(b, sx + o, sy, 3, 2, ('m', 'm', 'P'), False)           # two orbiting shards
        eye(b, 11, 0, 'm'); b.put(12, 3, 'Z'); b.put(12, 4, 'N')
        for k in range(3): b.put(31 + k + o, 11, 'X')
    def bhurt(self, b, st):
        b.rect(15, 3, 18, 17, '.'); gem_h(b, 22, 12, 7, 5, ('c', 'C', 'B'), st.i == 0); crack(b, [(21, 8), (23, 12), (21, 16)], 'K', 'M')
        b.rect(30, 8, 3, 3, '.'); spark(b, 31, 10, False) if st.i == 0 else spark(b, 18, 4, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 25, 2, 3, rows=(2, 22))
    def bwreck(self, b, st):
        b.stamp(26, 9, art("KSS\nKSE")); crack(b, [(18, 8), (19, 12), (17, 16)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire:
            stamp_flash(b, st, 33, 11, F_RAIN)
            sx = 34 + st.i * 3
            fillpoly(b, [(sx, 10), (sx + 5, 11), (sx, 12)], 'H')
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 34, 11, rgb=(160, 110, 230), core=(200, 250, 255), scale=0.9)
        if state != 'disabled': glow(g, ox + 24.5, oy + 11.5, 9, RGB_['cyan'], 0.35, 2.0); glow(g, ox + 12.5, oy + 1.5, 3, RGB_['magenta'], 0.5, 2.0)

# ============================================================ components
class PrismC(LComp):
    dark = DK
    glow_pad = (10, 10, 10, 10)

def cut_frame(s, x, y, w, h, tones=('V', 'Z', 'N'), cut=9):
    """a gem-cut frame: a square with large 45-degree corners, light top-left."""
    chamfer_fill(s, x, y, w, h, tones[1], cut); rim(s, tones[1], tones[0], tones[2], (x, y, x + w - 1, y + h - 1))

class LatticeShield(PrismC):
    id = 'prismatic_lattice_shield'; cells = (4, 4)
    anims = [('on', 'on', 6, 7), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 4)
    notes = ('Prismatic Lattice Shield, 4x4: a gem-cut violet frame round two nested diamond lattices (two layers) of thin cyan lines with a node on every crossing and a big faceted crystal in the middle; light chases along the lattice lines and the nodes flash magenta in turn (the 6-frame loop). '
             'Off: dark grey lattice and a dull crystal. Damaged: a lattice line snapped and a node dark, a facet cracked, the light stutters. Disabled: the lattice broken and dull, the crystal split.')
    def lat(self, s, r, on, i, col, nodes):
        pts = [(32, 32 - r), (32 + r, 32), (32, 32 + r), (32 - r, 32)]
        for k in range(4):
            (x0, y0), (x1, y1) = pts[k], pts[(k + 1) % 4]
            lline(s, x0, y0, x1, y1, col)
        if nodes:
            for k in range(4):
                (x0, y0), (x1, y1) = pts[k], pts[(k + 1) % 4]
                s.put((x0 + x1) // 2, (y0 + y1) // 2, 'H' if on else 'W')
        return pts
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        cut_frame(s, 1, 1, 62, 62)
        cut_frame(s, 5, 5, 54, 54, ('Z', 'N', 'K'), 8)
        for (x, y) in ((8, 8), (55, 8), (8, 55), (55, 55)): gem(s, x, y, 2, 3, ('X', 'V', 'Z') if on else ('S', 'W', 'E'), lit=on)
        for (r, col) in ((26, 'C' if on else 'W'), (17, 'c' if on else 'S')):
            pts = self.lat(s, r, on, i, col, True)
            for k, (nx, ny) in enumerate(pts):
                lit = on and (k + i) % 4 == 0
                chamfer_fill(s, nx - 2, ny - 2, 5, 5, 'm' if lit else ('J' if on else 'E'), 1); s.put(nx - 1, ny - 1, 'H' if lit else ('j' if on else 'W'))
        for (a, b_) in ((0, 2), (1, 3)): pass
        lline(s, 32, 6, 32, 58, 'I' if on else 'D'); lline(s, 6, 32, 58, 32, 'I' if on else 'D')
        if on:                                                                    # light chases along the outer diamond
            pts = [(32, 6), (58, 32), (32, 58), (6, 32)]
            for k in range(4):
                (x0, y0), (x1, y1) = pts[k], pts[(k + 1) % 4]
                t = ((i + k * 1.5) % 6) / 6.0
                s.put(int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t)), 'H'); s.put(int(round(x0 + (x1 - x0) * ((t + 0.08) % 1))), int(round(y0 + (y1 - y0) * ((t + 0.08) % 1))), 'c')
        gem(s, 32, 32, 7, 10, ('c', 'C', 'B') if on else ('S', 'W', 'E'), lit=on)
        return s
    def hurt(self, s, i):
        for (x, y) in ((22, 20), (23, 19), (24, 18), (25, 17)): s.put(x, y, 'K')
        chamfer_fill(s, 30, 4, 5, 5, 'E', 1); s.put(32, 6, 'W')
        lcrack(s, [(3, 14), (6, 19), (4, 24), (8, 28)], 'X'); lcrack(s, [(30, 28), (32, 33), (31, 38)], 'L')
        s.stamp(42, 42, art("KKKK.\nKDDDK\n.KDKK"))
        if i: s.hline(28, 33, 8, 'm')
    def wreck(self, s):
        lcrack(s, [(3, 11), (7, 15), (6, 20), (11, 24), (13, 30)], 'M'); lcrack(s, [(50, 49), (54, 47), (57, 52), (60, 55)], 'M'); lcrack(s, [(28, 24), (32, 32), (35, 41)], 'S')
        for (nx, ny) in ((32, 6), (58, 32), (32, 58), (6, 32), (32, 15), (49, 32)): s.rect(nx - 2, ny - 2, 5, 5, 'D')
        s.stamp(42, 42, art("KKKK.\nKDDDK\n.KDKK")); s.stamp(6, 45, art("KKK\nKLL\nKLM"))
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        glow(g, ox + 32, oy + 32, 24, RGB_['cyan'], 0.18 * k, 1.6)
        glow(g, ox + 32, oy + 32, 9, RGB_['cyan'], 0.4 * k, 1.8)
        for (r, kk) in ((26, 0), (17, 1)):
            for j, (nx, ny) in enumerate(((32, 32 - r), (32 + r, 32), (32, 32 + r), (32 - r, 32))):
                if (j + i) % 4 == 0 and not (flick is not None and j == 0): glow(g, ox + nx + .5, oy + ny + .5, 5, RGB_['magenta'], 0.5 * k, 2.0)

class SongReactor(PrismC):
    id = 'prismatic_song_reactor'; cells = (4, 4)
    anims = [('on', 'on', 6, 7), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 4)
    notes = ('Prismatic Song Reactor, 4x4: a gem-cut violet frame round a tall crystal that sings: concentric rings of cyan and magenta light spread outward from its white-gold core on the 6-frame loop, with four small tuning crystals in the corners that light in turn. '
             'Off: a dull dark crystal, no rings. Damaged: the crystal is cracked and a corner crystal dark, the rings stutter. Disabled: the crystal split and grey, the frame cracked.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        cut_frame(s, 1, 1, 62, 62)
        cut_frame(s, 5, 5, 54, 54, ('Z', 'N', 'K'), 8)
        chamfer_fill(s, 12, 12, 40, 40, 'I' if on else 'N', 14); rim(s, 'I' if on else 'N', 'J' if on else 'Z', 'N', (12, 12, 51, 51))
        for k, (x, y) in enumerate(((9, 9), (54, 9), (9, 54), (54, 54))): gem(s, x, y, 3, 4, (('c', 'C', 'B'), ('m', 'm', 'P'))[k % 2] if on and (k + i) % 2 == 0 else (('X', 'V', 'Z') if on else ('S', 'W', 'E')), lit=on and (k + i) % 2 == 0)
        if on:
            for r0 in (3, 9, 15):                                                  # the song: rings spreading out
                r = (r0 + i * 2) % 18 + 4
                if r < 19: lring(s, 32, 32, r - 1, r, 'c' if (r0 // 6) % 2 == 0 else 'm')
        gem(s, 32, 32, 7, 13, ('c', 'C', 'B') if on else ('S', 'W', 'E'), lit=on)
        if on:
            lcircle(s, 32, 31, 3, 'y'); lcircle(s, 32, 31, 1.8, 'H')
            for k in range(3): s.put(29 + k * 3, 22 + (i + k) % 3 * 6, 'H')
        return s
    def hurt(self, s, i):
        lcrack(s, [(30, 20), (32, 28), (30, 36), (33, 44)], 'L'); lcrack(s, [(3, 14), (6, 19), (4, 24)], 'X')
        gem(s, 54, 54, 3, 4, ('S', 'W', 'E'), lit=False); s.rect(50, 50, 8, 2, 'K')
        s.stamp(42, 12, art("KKKK.\nKDDDK\n.KDKK"))
        if i: s.hline(28, 31, 8, 'o')
    def wreck(self, s):
        lcrack(s, [(3, 11), (7, 15), (6, 20), (11, 24), (13, 30)], 'M'); lcrack(s, [(50, 49), (54, 47), (57, 52), (60, 55)], 'M'); lcrack(s, [(28, 20), (32, 32), (36, 44)], 'S')
        s.rect(29, 28, 7, 8, 'K'); s.stamp(6, 45, art("KKK\nKLL\nKLM")); s.stamp(42, 12, art("KKKK.\nKDDDK\n.KDKK"))
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        glow(g, ox + 32, oy + 32, 26, RGB_['cyan'], 0.2 * k, 1.6)
        glow(g, ox + 32, oy + 31, 9, RGB_['yellow'], 0.5 * k, 1.8)
        for r0 in (3, 9, 15):
            r = (r0 + i * 2) % 18 + 4
            if r < 19: glow(g, ox + 32, oy + 32, r + 2, RGB_['magenta'] if (r0 // 6) % 2 else RGB_['cyan'], 0.1 * k, 1.0)

class ResonanceHelm(PrismC):
    id = 'prismatic_resonance_helm'; cells = (2, 2)
    glow_pad = (6, 6, 6, 6)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    notes = ('Prismatic Resonance Helm, 2x2: a violet pilot console with a lattice-star screen along the top, a violet cushion seat, and a crystal on a pedestal at the left that hums: cyan rings spread from it on the 4-frame loop and the screen scans. '
             'Off: dark screen, dull crystal. Damaged: the screen glitches and the crystal is cracked. Disabled: the crystal snapped, the screen dead.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        cut_frame(s, 0, 0, 32, 32, ('V', 'Z', 'N'), 4)
        bev(s, 3, 3, 26, 8, 'j', 'J', 'I', cham=False); s.rect(5, 5, 22, 4, 'N')                       # the screen
        if on:
            for x in range(6, 26, 4): s.put(x, 6 + ((x // 4 + i) % 3), 'c'); s.put(x + 1, 7 + ((x // 4 + i) % 2), 'm')
            s.put(6 + (i * 5) % 20, 8, 'H')
        else: s.hline(6, 7, 20, 'I')
        chamfer_fill(s, 14, 15, 14, 14, 'X', 4); rim(s, 'X', 'H' if False else 'X', 'V', (14, 15, 27, 28)); chamfer_fill(s, 16, 17, 10, 10, 'V', 3)       # the seat
        for x in (17, 21): s.vline(x, 18, 8, 'Z')
        chamfer_fill(s, 3, 14, 9, 9, 'Z', 3); rim(s, 'Z', 'V', 'N', (3, 14, 11, 22))                      # the pedestal
        gem(s, 7, 14, 3, 6, ('c', 'C', 'B') if on else ('S', 'W', 'E'), lit=on)
        if on: lring(s, 7, 16, 4 + i, 5 + i, 'c') if 4 + i < 9 else None
        s.put(3, 28, 'g' if on else 'E'); s.put(5, 28, 'm' if on and i % 2 else 'E')
        return s
    def hurt(self, s, i):
        s.rect(5, 5, 22, 4, 'N'); s.hline(6, 6 + i, 20, 'c' if i else 'm'); s.hline(8, 8, 10, 'N')
        lcrack(s, [(7, 9), (6, 13), (8, 17)], 'L'); spark(s, 24, 14, False) if i else None
        s.stamp(20, 22, art("KKK.\nKDDK\n.KDK"))
    def wreck(self, s):
        s.rect(5, 5, 22, 4, 'K'); lcrack(s, [(8, 4), (12, 8), (18, 6)], 'M')
        s.rect(4, 8, 8, 10, 'K'); s.stamp(4, 18, art("KSK\nKSSK\n.KEK")); lcrack(s, [(20, 14), (22, 20), (19, 26)], 'M')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        glow(g, ox + 7.5, oy + 14, 9, RGB_['cyan'], 0.4 * k, 1.8)
        glow(g, ox + 16, oy + 7, 9, RGB_['cyan'], 0.2 * k, 2.0, sx=1.8)

WEAPONS = [PrismLens, Refractor, GlimmerTurret]
COMPS = [LatticeShield, SongReactor, ResonanceHelm]
ALL = WEAPONS + COMPS
