"""Neon (Lumen) line weapons: dark navy-slate panels, crisp 1 px neon edge lines (cyan and magenta accents), crystal facets; the glow carries the neon.
Hull mounts: outside half, inside half, rotating barrel."""
from wbase import *
from compose import rotate

FLAP = art("""
....SSM.
..SSMMS.
SSMMSS..
""")
CRYSTAL = art("""
...c...
..cHc..
..cHb..
.cHHbb.
.cHbbb.
cHHbbbE
cHbbbEE
.bbbEE.
..bEE..
""")
BIG = art("""
.......cc.......
......cHHb......
.....cHHHbb.....
....cHHHbbbb....
...cHHHHbbbbE...
..cHHHHHbbbbEE..
..cHHHHbbbbbEE..
.cHHHHbbbbbbEEE.
.cHHHbbbbbbEEEE.
..cHHbbbbbEEEE..
..cHbbbbbEEEE...
...cbbbbEEEE....
....bbbEEEE.....
.....bbEEE......
......bEE.......
.......E........
""")
LEVELS = [{'c': 'W', 'H': 'S', 'b': 'E', 'E': 'D'}, {'c': 'b', 'H': 'S', 'b': 'E', 'E': 'D'}, {'c': 'b', 'H': 'M', 'b': 'E', 'E': 'D'},
          {'c': 'c', 'H': 'b', 'b': 'E', 'E': 'D'}, {'c': 'c', 'H': 'c', 'b': 'b', 'E': 'E'}, {'c': 'H', 'H': 'c', 'b': 'c', 'E': 'b'}]
MAGENTA = {'c': 'm', 'H': 'p', 'b': 'm', 'E': 'E'}

def neon_ring(s, cx=32, cy=15, d=25):
    turret_ring(s, cx, cy, d, 'W', 'E', 'D', 'K')
    box = (cx - d // 2, cy - d // 2, cx + d // 2, cy + d // 2)
    edge = [(x, y) for y in range(box[1], box[3] + 1) for x in range(box[0], box[2] + 1)
            if s.get(x, y) == 'K' and any(s.get(x + dx, y + dy) not in ('K', '.') for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    for (x, y) in edge: s.g[y][x] = 'c'

def arc(b, cx, cy, r, c, span=62):
    """a sound-wave arc round the mouth: 1 px, within +-span degrees of east (FX)."""
    import math
    for a in range(-span, span + 1):
        x = round(cx + r * math.cos(math.radians(a))); y = round(cy + r * math.sin(math.radians(a)))
        b.put(x, y, c)

# ============================================================ SIREN ION (neon, TURRET)
class SirenIon(Weapon):
    id = 'siren_ion_neon'; line = 'neon'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 52, 27
    bpivot = (8, 13)
    bmuzzle = (35, 13)
    out_notes = ('OUTSIDE half of the Siren Ion (neon, a TURRET): dark navy-slate ring base with a cyan edge line, a cyan crystal cluster and a magenta crystal. '
                 'damaged: ring cracked, a crystal chipped; disabled: scorched, dented, crystals dark, sparking.')
    notes = ('INSIDE half of the Siren Ion (neon): a big faceted crystal capacitor that brightens as it charges (dull, blue edges, cyan, then white-cyan with a magenta core at ready), '
             'power coupling, hatch, cyan/magenta strip. fire: the crystal flashes white. damaged: crystal cracked, lamps dead; disabled: crystal dark and split. '
             'Barrel layer siren_ion_neon_barrel: a horn-shaped emitter with crystal fins and a sensor pod; fire: sound-wave arcs in magenta and cyan roll out of the mouth.')
    def outside(self, s, st):
        pw = st.powered
        turret_seat(s, 32, 15, 'neon')
        bev(s, 3, 6, 16, 18, 'W', 'E', 'D')                                   # left: cyan crystal cluster
        s.hline(3, 6, 16, 'c'); s.vline(3, 6, 18, 'c')
        for (x, y) in ((5, 9), (11, 11)):
            s.stamp(x, y, CRYSTAL, None if pw else {'c': 'W', 'H': 'S', 'b': 'E', 'E': 'D'})
        bev(s, 45, 6, 16, 18, 'W', 'E', 'D')                                  # right: magenta crystal and sensor
        s.hline(45, 6, 16, 'c'); s.vline(45, 6, 18, 'c')
        s.stamp(51, 8, CRYSTAL, MAGENTA if pw else {'c': 'W', 'H': 'S', 'b': 'E', 'E': 'D'})
        s.rect(48, 19, 10, 3, 'D'); s.put(49, 20, 'c' if pw else 'E'); s.put(51, 20, 'm' if pw else 'E'); s.put(53, 20, 'c' if pw else 'E')
        neon_ring(s)
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y, 'neon')
        s.hline(2, y + 1, 60, 'c')
        coupling(s, 3, y + 8, st, 'c')
        lvl = 5 if st.flash else (st.lit if pw else 0)
        s.stamp(24, y + 5, BIG, LEVELS[lvl])
        if lvl == 5 and not st.flash:
            for (dx, dy) in ((7, 7), (8, 7), (7, 8), (8, 8), (7, 9), (8, 9)): s.put(24 + dx, y + 5 + dy, 'm')
        if st.flash: s.rect(27, y + 9, 10, 8, 'H')
        hatch(s, 46, y + 8, st)
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('m', 'm', 'c'))
        s.hline(4, y + 25, 2, 'c'); s.hline(55, y + 25, 3, 'c')
    def hurt_out(self, s, st):
        crack(s, [(28, 5), (29, 8), (27, 11), (28, 15)])
        s.stamp(2, 5, FLAP) if False else None
        s.erase(7, 9); s.erase(8, 9); s.put(9, 10, 'K')                          # a crystal tip chipped off
        wire(s, [(10, 14), (12, 17), (11, 20)], 'c')
        spark(s, 8, 8, False) if st.i == 0 else spark(s, 55, 10, False)
        crack(s, [(54, 12), (55, 16), (53, 19)])
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(28, 5), (29, 8), (27, 11), (28, 15), (30, 19), (29, 23)], [(54, 8), (55, 14), (53, 19)]],
                 dents=[(7, 18, 5, 4), (49, 18, 6, 3)], soots=[(21, 3, 0), (46, 7, 1), (4, 8, 2)],
                 wires_=[[(14, 7), (16, 10), (15, 13)]], sparks=[(35, 5), (9, 11)])
    def hurt_in(self, s, st):
        y = self.iy
        crack(s, [(31, y + 6), (32, y + 10), (30, y + 14), (32, y + 18)])
        dead_cells(s, st, y + STRIP_DY)
        spark(s, 31, y + 12, False) if st.i == 0 else spark(s, 14, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(31, y + 6), (32, y + 10), (30, y + 14), (32, y + 18), (31, y + 21)]); crack(s, [(36, y + 9), (38, y + 14)])
        wire(s, [(14, y + 20), (16, y + 23), (22, y + 24)], 'c')
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, ready_rgb=(60, 242, 255), live_rgb=(255, 79, 216))
        lvl = {'charge': i, 'on': 5, 'damaged': 3}.get(state, 0)
        if state == 'fire' and i == 0: lvl = 5
        if lvl >= 2: glow(g, ox + 32, oy + y + 13, 8 + lvl * 2, (60, 242, 255) if lvl < 5 else (200, 250, 255), 0.18 + 0.05 * lvl, 2.0)
        if lvl == 5: glow(g, ox + 32, oy + y + 13, 6, (255, 79, 216), 0.45, 2.0)
        glow(g, ox + 12, oy + y + 14, 3, (60, 242, 255), 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 8, oy + 14, 9, (60, 242, 255), 0.25, 2.0); glow(g, ox + 55, oy + 13, 9, (255, 79, 216), 0.28, 2.0)
        glow(g, ox + 32, oy + 15, 15, (60, 242, 255), 0.12, 2.0)
    # ---- barrel: the horn
    def barrel(self, b, st):
        o = -st.rc
        hh = lambda x: 3 + (x - 13) * 8 // 22
        for x in range(13, 36):
            h = hh(x)
            for k, yy in enumerate(range(13 - h, 13 + h + 1)):
                top = yy == 13 - h; bot = yy == 13 + h
                b.put(x + o, yy, 'c' if (top or bot) else ('W' if k < 2 else ('D' if abs(yy - 13) > h - 3 else 'E')))
        for x in range(31, 36):                                                   # the dark mouth
            h = hh(x) - 3
            for yy in range(13 - h, 13 + h + 1): b.put(x + o, yy, 'K')
        for yy in range(13 - hh(35), 13 + hh(35) + 1): b.put(35 + o, yy, 'm')    # magenta lip
        for x0 in (17, 23):                                                       # crystal fins
            for yy0, flip in ((13 - hh(x0 + 2) - 5, False), (13 + hh(x0 + 2) + 1, True)):
                for j, r in enumerate(CRYSTAL[2:7] if not flip else CRYSTAL[2:7][::-1]):
                    for i2, c in enumerate(r[:5]):
                        if c != '.': b.put(x0 + i2 + o, yy0 + j, MAGENTA.get(c, c) if x0 == 23 else c)
        b.rect(12 + o, 9, 4, 9, 'E'); b.hline(12 + o, 9, 4, 'c'); b.hline(12 + o, 17, 4, 'c')
        hub(b, 13, 17, 'E', 'W', 'D')
        b.put(8, 13, 'c')
        pod(b, 10, 1, 'm')
    def bhurt(self, b, st):
        crack(b, [(27, 8), (28, 11), (27, 14)]); crack(b, [(31, 17), (32, 21), (31, 24)])
        for yy in range(3, 8): b.erase(24, yy)                                  # a crystal fin chipped
        b.put(23, 5, 'K'); b.put(25, 4, 'K'); b.put(25, 6, 'E')
        wire(b, [(21, 5), (22, 8)], 'c')
        spark(b, 24, 4, False) if st.i == 0 else spark(b, 33, 22, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 25, 2, 3)
    def bwreck(self, b, st):
        for y in (10, 16): wire(b, [(23, y), (25, y + 1), (27, y + 1)], 'c' if False else 'u')
        crack(b, [(31, 6), (32, 10), (31, 15), (33, 20)], 'K', 'S')
        for (x, y) in ((20, 3), (22, 4), (26, 22), (28, 23)): b.put(x, y, 'S')
    def bafter(self, b, st):
        if st.fire:
            r = (4, 8, 12)[st.i]
            for k, rr in enumerate((r, r - 4)):
                if rr >= 3: arc(b, 33 - st.rc, 13, rr + 2, ('c', 'm')[(k + st.i) % 2], 58)
            b.put(36 - st.rc, 13, 'H'); b.put(37 - st.rc, 13, 'H')
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            glow(g, ox + 38, oy + 13.5, (14, 12, 9)[i], (255, 79, 216), (0.4, 0.3, 0.2)[i], 2.0, sx=1.4)
            glow(g, ox + 36, oy + 13.5, (10, 8, 6)[i], (60, 242, 255), (0.5, 0.4, 0.3)[i], 2.0, sx=1.3)
        if state != 'disabled': glow(g, ox + 12.5, oy + 2.5, 3, (255, 79, 216), 0.5, 2.0)
        if state in ('idle', 'damaged'): glow(g, ox + 28, oy + 13.5, 10, (60, 242, 255), 0.14, 2.0, sx=1.4)

# ============================================================ HEAT LANCE (neon, fixed)
FIN_LIT = [0, 2, 5, 7, 10, 12]
class HeatLance(Weapon):
    id = 'heat_lance_neon'; line = 'neon'
    blen, bwid = 76, 17
    bpivot = (6, 8)
    bmuzzle = (58, 8)
    out_notes = ('OUTSIDE half of the Heat Lance (neon, a FIXED gun): a forward-heavy dark housing with cyan edge lines, a heat crystal (orange core) and a sensor. '
                 'damaged: housing cracked, crystal chipped; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Heat Lance (neon): twelve heat fins in two banks that glow orange fin by fin as it charges (frame 5 = all twelve white-hot at the tips, strip yellow), '
             'a heat-core window, power coupling, hatch. fire: every fin flashes white. damaged: fins bent and dead, sparks; disabled: fins dark, a bank split. '
             'Barrel layer heat_lance_neon_barrel: the long beam-focus lens head with heat fins; fire: the lens flares white-orange and a beam starts.')
    def outside(self, s, st):
        pw = st.powered
        gun_housing(s, 'neon')
        bev(s, 3, 6, 16, 18, 'W', 'E', 'D')                                   # left: the heat crystal
        s.hline(3, 6, 16, 'c'); s.vline(3, 6, 18, 'c')
        s.stamp(8, 9, CRYSTAL, {'c': 'o', 'H': 'y', 'b': 'o', 'E': 'u'} if pw else {'c': 'W', 'H': 'S', 'b': 'E', 'E': 'D'})
        bev(s, 45, 6, 16, 18, 'W', 'E', 'D')                                  # right: sensor and vents
        s.hline(45, 6, 16, 'c'); s.vline(45, 6, 18, 'c')
        s.rect(48, 9, 10, 4, 'D'); s.put(50, 10, 'c' if pw else 'E'); s.put(53, 10, 'o' if pw else 'E'); s.put(56, 10, 'c' if pw else 'E')
        for vy in (15, 18, 21): s.rect(48, vy, 10, 1, 'D')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y, 'neon')
        s.hline(2, y + 1, 60, 'c')
        coupling(s, 3, y + 8, st, 'o')
        n = 12 if (st.flash or st.ready) and pw else (FIN_LIT[st.i] if st.charge else (6 if st.state == 'damaged' else 0))
        k = 0
        for bank_x in (16, 36):
            for f in range(6):
                x = bank_x + 2 * f
                lit = k < n
                hot = n == 12 or st.flash
                for r in range(15):
                    yy = y + 6 + r
                    if lit: c = 'H' if (st.flash) else ('y' if r < 2 and hot else ('o' if r < 9 else 'u'))
                    else: c = 'W' if r == 0 else 'E'
                    s.put(x, yy, c)
                k += 1
            s.hline(bank_x - 1, y + 21, 13, 'c' if pw else 'W')
        s.rect(30, y + 7, 4, 13, 'D')
        if pw and n:
            for r in range(13): s.put(31, y + 7 + r, 'o' if n < 12 else 'y'); s.put(32, y + 7 + r, 'y' if n >= 6 else 'o')
        hatch(s, 50, y + 8, st, 11, 9)
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('o', 'o', 'y'))
    def hurt_out(self, s, st):
        crack(s, [(31, 4), (30, 8), (32, 11), (30, 14)])
        s.erase(11, 9); s.erase(12, 9); s.put(10, 10, 'K')
        wire(s, [(10, 14), (12, 17), (11, 20)], 'o')
        spark(s, 9, 8, False) if st.i == 0 else spark(s, 54, 8, False)
        crack(s, [(52, 12), (53, 16), (51, 19)])
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 4), (30, 8), (32, 11), (30, 14), (31, 18), (33, 23)], [(52, 8), (53, 14), (51, 19)]],
                 dents=[(7, 18, 5, 4), (49, 17, 6, 3)], soots=[(22, 3, 0), (46, 7, 1), (4, 8, 2)],
                 wires_=[[(14, 7), (16, 10), (15, 13)]], sparks=[(26, 8), (10, 12)])
    def hurt_in(self, s, st):
        y = self.iy
        for f in (3, 4): s.vline(16 + 2 * f, y + 6, 7, 'E'); s.put(16 + 2 * f + 1, y + 10, 'K')           # fins bent and dead
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(40, y + 8), (42, y + 12), (41, y + 16)])
        spark(s, 41, y + 12, False) if st.i == 0 else spark(s, 24, y + 8, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(40, y + 6), (42, y + 12), (41, y + 17), (43, y + 20)]); crack(s, [(22, y + 8), (24, y + 13), (23, y + 18)])
        wire(s, [(14, y + 20), (16, y + 23), (22, y + 24)], 'u')
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, ready_rgb=(255, 210, 58), live_rgb=(255, 138, 30))
        n = {'charge': FIN_LIT[i] if state == 'charge' else 0, 'on': 12, 'damaged': 6}.get(state, 0)
        if state == 'fire' and i == 0: n = 12
        k = 0
        for bank_x in (16, 36):
            for f in range(6):
                if k < n: glow(g, ox + bank_x + 2 * f + 0.5, oy + y + 13, 6, (255, 138, 30), 0.22, 2.0)
                k += 1
        glow(g, ox + 12, oy + y + 14, 3, (255, 138, 30), 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 11, oy + 15, 10, (255, 138, 30), 0.3, 2.0)
        glow(g, ox + 50.5, oy + 10.5, 3, (60, 242, 255), 0.5, 2.0); glow(g, ox + 53.5, oy + 10.5, 3, (255, 138, 30), 0.5, 2.0)
    # ---- barrel: the long lens head
    def barrel(self, b, st):
        o = -st.rc
        b.rect(13 + o, 4, 34, 9, 'E'); b.hline(13 + o, 4, 34, 'c'); b.hline(13 + o, 12, 34, 'c'); b.hline(13 + o, 5, 34, 'W')
        for fx in (16, 20, 24, 28):                                                # heat fins
            b.rect(fx + o, 1, 2, 3, 'E'); b.put(fx + o, 1, 'W'); b.rect(fx + o, 13, 2, 3, 'D')
            if st.fire: b.put(fx + o, 1, 'o'); b.put(fx + o + 1, 1, 'y'); b.put(fx + o, 15, 'o')
        bev(b, 44 + o, 1, 14, 15, 'W', 'E', 'D')                                   # the lens housing
        b.hline(44 + o, 1, 14, 'c'); b.hline(44 + o, 15, 14, 'c')
        for k, c in enumerate('KEE'): pass
        chamfer_fill(b, 46 + o, 3, 10, 11, 'K', 3)                                  # lens glass
        if st.fire:
            chamfer_fill(b, 47 + o, 4, 8, 9, 'o', 3); chamfer_fill(b, 48 + o, 5, 6, 7, 'y', 2); chamfer_fill(b, 49 + o, 6, 4, 5, 'H', 1)
        else:
            chamfer_fill(b, 47 + o, 4, 8, 9, 'b', 3); chamfer_fill(b, 48 + o, 5, 6, 7, 'c', 2)
            b.put(49 + o, 6, 'H'); b.put(50 + o, 6, 'H'); b.put(52 + o, 10, 'o')
        breech(b, 8, 13)
    def bhurt(self, b, st):
        crack(b, [(47, 4), (50, 7), (49, 10), (53, 13)]); crack(b, [(55, 6), (52, 8)])
        move(b, 24, 1, 2, 3, 0, -1) if False else b.erase(24, 1)
        b.put(25, 2, 'K'); b.erase(25, 1)
        wire(b, [(24, 14), (25, 16)], 'o')
        spark(b, 25, 15, False) if st.i == 0 else spark(b, 51, 8, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 40, 2, 3)
    def bwreck(self, b, st):
        for y in (6, 10): wire(b, [(39, y), (41, y + 1), (43, y + 1)], 'u')
        crack(b, [(46, 3), (49, 7), (48, 11), (51, 14)], 'K', 'S')
        b.rect(51, 7, 4, 4, 'K'); b.put(52, 7, 'S'); b.put(54, 10, 'S')
    def bafter(self, b, st):
        if st.fire:
            L = (14, 10, 6)[st.i]
            for x in range(59 - st.rc, 59 - st.rc + L):
                b.put(x, 8, 'H')
                if x < 59 - st.rc + L - 2: b.put(x, 7, 'y'); b.put(x, 9, 'y')
                if x < 59 - st.rc + L - 5: b.put(x, 6, 'o'); b.put(x, 10, 'o')
            b.stamp(58 - st.rc, 8 - len(FLASH_S[st.i]) // 2, FLASH_S[st.i])
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            glow(g, ox + 52, oy + 8.5, (14, 12, 10)[i], (255, 138, 30), (0.6, 0.5, 0.4)[i], 2.0)
            glow(g, ox + 62, oy + 8.5, (14, 10, 6)[i], (255, 210, 120), (0.5, 0.4, 0.3)[i], 2.0, sx=2.5)
        if state in ('idle', 'damaged'): glow(g, ox + 51, oy + 8.5, 9, (60, 242, 255), 0.22, 2.0)

FLASH_S = [art("""
..o.......
.oyo......
oyHHyo....
yHHHHHyyo.
oyHHyo....
.oyo......
..o.......
"""), art("""
.o.....
oyo....
yHyoo..
oyo....
.o.....
"""), art("""
.o...
oyo..
.o...
""")]

ALL = [SirenIon, HeatLance]
