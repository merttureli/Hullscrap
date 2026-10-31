"""Fenn tech (docs/waves/racial_tech_1.md): delicate, quick, many small parts and antennas. Cream panels (H/f/Q) on thin steel struts (M/S), tiny coloured lamps
(c/p/g/y), antennas with blinking beads, small gears and dials, lots of little boxes instead of a few big ones; lighter and more open than the other races.
Weapons: fenn_twitch_cannon, fenn_spark_lattice, fenn_market_missile. Components: fenn_haggle_engine (engine), fenn_jury_reactor (reactor), fenn_quickfix_bay (utility).
Projectile art: quick sparks, tiny bolts."""
from techa_kit import *
from lines_eng_base import ANIMS

CRM = ('H', 'f', 'Q')              # cream panel: light, body, shade
CRM_D = ('f', 'Q', 'q')

def antenna(s, x, y, h, on, i=0, c='c', k=0):
    """a thin mast standing on (x, y), h tall; a bead on top that blinks."""
    s.vline(x, y - h + 1, h, 'M'); s.put(x, y, 'S')
    s.put(x, y - h, c if on and (i + k) % 2 == 0 else ('L' if on else 'W'))
    if h > 5: s.put(x - 1, y - h + 3, 'S'); s.put(x + 1, y - h + 3, 'S')

def antenna_h(b, x, y, n, on, i=0, c='c', k=0):
    """a mast on an east-pointing barrel canvas: a thin line going 'up' (-y) from (x, y)."""
    for j in range(n): b.put(x, y - j, 'M')
    b.put(x, y - n, c if on and (i + k) % 2 == 0 else 'L')

def gear(s, cx, cy, r, tone=('M', 'S', 'W'), teeth=8, turn=0):
    """a small gear, centre (cx, cy): body disc, teeth that shift by `turn` half-steps, an axle pixel."""
    circle(s, cx + .5, cy + .5, r, tone[1]); circle(s, cx + .5, cy + .5, max(1, r - 2), tone[0] if r > 2 else tone[1])
    for k in range(teeth):
        a = 2 * math.pi * (k + 0.5 * (turn % 2)) / teeth
        s.put(int(round(cx + (r + 1) * math.cos(a))), int(round(cy + (r + 1) * math.sin(a))), tone[0] if k % 2 else tone[2])
    s.put(cx, cy, 'E')

def leds(s, st, x, y, n=10, c=('c', 'g'), pitch=4):
    """a row of n tiny lamps (2 per charge step): cyan while charging, green when ready, white flash on the discharge."""
    recess(s, x - 2, y - 1, n * pitch + 1, 4, 'D', 'K')
    for k in range(n):
        on = st.powered and k < st.lit * 2
        if getattr(st, 'flash', False) and st.powered: col = 'H'
        elif on: col = c[1] if st.ready else c[0]
        else: col = 'E'
        s.rect(x + k * pitch, y, 2, 2, col)
        if on and col != 'H': s.put(x + k * pitch, y, 'H')

def leds_glow(g, ox, oy, state, i, x, y, n=10, pitch=4):
    lit = {'charge': i, 'on': 5, 'damaged': 3}.get(state, 0) * 2
    rdy = state in ('on', 'damaged') or (state == 'charge' and i == 5)
    for k in range(min(n, lit)): glow(g, ox + x + k * pitch + 1, oy + y + 1, 3.5, GREEN if rdy else CYAN, 0.45, 2.0)

class FennMount:
    """a cream flange with tiny lamps."""
    def trim(self, s, st, half):
        fy = 2 if half == 'in' else s.h - 3
        s.hline(3, fy, 58, 'f')
        for x in range(6, 58, 8): s.put(x, fy, 'p' if (x // 8) % 2 else 'c')

def thin_block(s, x, y, w, h, tone=CRM):
    mat(s, x, y, w, h, tone)

def housing_f(s, y0):
    mat(s, 2, y0 + 1, 60, 30, CRM)
    s.hline(3, y0 + 2, 58, 'H')
    for x in (9, 31, 53): s.put(x, y0 + 29, 'q')

def fenn_out_base(s, cy=12, wide=False):
    """the slim outside body: a narrow cream housing on a thin steel pad, the barrel sleeve and a gimbal ring."""
    mat(s, 8, 22, 48, 10, ('M', 'S', 'W'))
    mat(s, 22, 4, 20, 22, CRM)
    mat(s, 25, 2, 14, 7, CRM)
    s.rect(28, 3, 8, 5, 'D'); s.hline(28, 3, 8, 'K')
    mat(s, 21, 10, 22, 4, ('L', 'M', 'S'), cham=False); s.put(32, 12, 'L'); s.put(33, 13, 'W')

# ============================================================ TWITCH CANNON
class TwitchCannon(FennMount, Weapon):
    id = 'fenn_twitch_cannon'
    blen, bwid = 58, 13
    bpivot = (6, 6)
    bmuzzle = (43, 6)
    out_notes = ('OUTSIDE half of the Fenn Twitch Cannon: a slim cream body on a thin pad, a cluster of tiny gears and dials on the left, a mast with a blinking bead and a lamp panel on the right. '
                 'damaged: the mast bent over, a gear hanging by its axle, a panel cracked, sparks; disabled: scorched, dented, mast snapped, sparking.')
    notes = ('INSIDE half of the Fenn Twitch Cannon: a small escapement gear that ticks half a step on every charge frame, a spring, and a row of ten tiny lamps that fill two per step (frame 5 = all green); '
             'power coupling, small hatch. fire: the lamps flash white and the spring is slack. damaged: the gear cracked and out of true, lamps dead, sparks; disabled: the gear off its axle, the spring sprung. '
             'Barrel layer fenn_twitch_cannon_barrel: a slim steel barrel with a coiled recoil spring and a slotted muzzle brake; it twitches (fire recoil 2/1/0).')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        fenn_out_base(s)
        mat(s, 3, 8, 17, 16, CRM)                                                  # left: tiny gears and dials
        gear(s, 8, 14, 3, turn=i); gear(s, 14, 12, 2, turn=i + 1); gear(s, 13, 19, 2, turn=i)
        for k in range(3): s.put(5 + 4 * k, 22, 'c' if pw and (k + i) % 2 else ('p' if pw else 'E'))
        mat(s, 44, 8, 17, 16, CRM)                                                 # right: lamp panel + mast
        s.rect(46, 10, 13, 5, 'D')
        for k in range(4): s.rect(47 + 3 * k, 11, 2, 3, ('c', 'g', 'y', 'p')[k] if pw and (k + i) % 4 != 3 else 'E')
        antenna(s, 56, 9, 8, pw, i, 'c', 0)
        s.hline(46, 19, 3, 'q'); s.hline(50, 19, 2, 'q'); s.hline(53, 19, 3, 'q')
        antenna(s, 50, 8, 5, pw, i, 'p', 1)
        for (x, y) in ((24, 6), (39, 6), (24, 24), (39, 24)): s.put(x, y, 'M')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing_f(s, y)
        cable_stub(s, 3, y + 8, st, 'c', ('M', 'S', 'W'))
        mat(s, 15, y + 5, 28, 15, ('M', 'S', 'W'), cham=False)                    # the works
        gear(s, 24, y + 12, 5, turn=(st.i if st.charge else (1 if st.state == 'fire' and st.i == 1 else 0)))
        gear(s, 34, y + 10, 3, turn=(st.i if st.charge else 0))
        gear(s, 36, y + 16, 2, turn=(st.i + 1 if st.charge else 0))
        for (a, b) in (((17, y + 17), (20, y + 14)), ((17, y + 8), (19, y + 10))): line(s, a[0], a[1], b[0], b[1], 'q')
        for k in range(5): s.hline(40 + 0, y + 6 + 2 * k, 2, 'D') if False else None
        hatch_k(s, 47, y + 6, CRM_D, 11, 9, 'p')
        leds(s, st, 16, y + 25 - 0)
        s.put(8, y + 3, 'p'); s.put(55, y + 3, 'c')
    def hurt_out(self, s, st):
        move(s, 54, 0, 5, 9, 2, 1); s.put(58, 1, 'K')
        s.vline(10, 12, 3, 'K'); s.stamp(4, 20, art("KKK\nKMK\n.KK")); crack(s, [(46, 10), (49, 13), (47, 16)])
        hurt_pair(s, st, (14, 8), (57, 4))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 5), (30, 9), (32, 13), (30, 18), (31, 23)], [(48, 9), (50, 13), (48, 17)]],
                 dents=[(6, 18, 6, 4), (48, 18, 6, 3)], soots=[(24, 3, 1), (45, 8, 0), (4, 8, 2)],
                 wires_=[[(56, 6), (58, 9), (57, 12)]], sparks=[(35, 6), (9, 12)])
    def hurt_in(self, s, st):
        y = self.iy
        for k in (5, 6, 7, 8, 9): s.erase(8 + 2 * k, y + 25) if False else None
        for k in (7, 8, 9): s.rect(16 + 4 * k, y + 25, 2, 2, 'E')
        crack(s, [(21, y + 8), (24, y + 12), (22, y + 17)]); s.put(26, y + 12, 'E')
        hurt_pair(s, st, (36, y + 8), (52, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(21, y + 8), (24, y + 12), (22, y + 17)]); s.stamp(38, y + 21, art(".KK.\nKMSK\nKSWK\n.KK.")); wire(s, [(16, y + 18), (19, y + 21), (24, y + 20)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        leds_glow(g, ox, oy, state, i, 16, y + 25)
        glow(g, ox + 12, oy + y + 14, 3, CYAN, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        for k in range(4): glow(g, ox + 48 + 3 * k, oy + 12.5, 3, (CYAN, GREEN, YEL, PINK)[k], 0.4, 2.0)
        glow(g, ox + 56, oy + 1, 3, CYAN, 0.5, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 1, 1, 10, 11, 'H', 'f', 'Q'); b.rect(3, 4, 4, 4, 'D'); b.put(5, 6, 'L')
        cylh(b, 12 + o, 4, 28, 5, 'LMSWE')                                         # slim steel barrel
        for x in range(14, 36, 2):                                                 # the recoil spring: a coil round the barrel
            b.put(x + o, 3, 'M'); b.put(x + 1 + o, 9, 'M'); b.put(x + o, 4, 'S') if False else None
        b.vline(14 + o, 2, 9, 'S'); b.vline(36 + o, 2, 9, 'S')
        bev(b, 38 + o, 2, 7, 9, 'M', 'S', 'W', cham=False)                         # slotted muzzle brake
        for k in range(3): b.vline(39 + 2 * k + o, 3, 7, 'D')
        if st.fire: b.rect(43 + o, 4, 2, 5, 'y'); b.put(44 + o, 6, 'H')
        else: b.put(44 + o, 6, 'c')
        antenna_h(b, 20, 2, 2, st.state == 'idle', st.i, 'c')
    def bhurt(self, b, st):
        crack(b, [(22, 4), (23, 7), (22, 9)]); move(b, 38, 2, 7, 9, 0, 2); b.put(44, 12, 'S')
        spark(b, 46, 2, False) if st.i == 0 else spark(b, 24, 2, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 30, 2, 2)
    def bwreck(self, b, st):
        crack(b, [(21, 4), (23, 7), (21, 9)], 'K', 'S'); wire(b, [(29, 5), (32, 7)])
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 46, 6, FLASH_T, {'o': 'c', 'y': 'y'})
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 46, 6, CYAN, (230, 255, 255) if False else WHITE, scale=0.65)
        if state in ('idle', 'damaged'): glow(g, ox + 44.5, oy + 6.5, 3, CYAN, 0.4, 2.0)

FLASH_T = [art("""
.cy......
cyHycc...
.cy......
"""), art("""
.c.....
cyyc...
.c.....
"""), art("""
.c...
cyc..
.c...
""")]

# ============================================================ SPARK LATTICE
class SparkLattice(FennMount, Weapon):
    id = 'fenn_spark_lattice'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 44, 25
    bpivot = (11, 12)
    bmuzzle = (34, 12)
    out_notes = ('OUTSIDE half of the Fenn Spark Lattice (a TURRET): a slim ring seat, a stack of three small coils on the left that light in turn, a lamp panel and two aerials on the right. '
                 'damaged: ring cracked, an aerial snapped, a coil unwinding; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Fenn Spark Lattice: a row of three small coils on a rail that charge up cyan one after another (frame 5 = all lit, white sparks between them, lamps green), power coupling, hatch. '
             'fire: the coils flash white and go dark. damaged: one coil unwound and dead, lamps dead, sparks; disabled: coils cold, a coil off its post. '
             'Barrel layer fenn_spark_lattice_barrel: an open lattice cage of thin struts round a crackling spark core, with three aerial whiskers; fire: sparks fly.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        mat(s, 8, 20, 48, 12, ('M', 'S', 'W'))
        mat(s, 20, 3, 24, 22, CRM)
        turret_ring(s, 32, 15, 23, 'M', 'S', 'W', 'D')
        for (x, y) in ((32, 5), (32, 25), (22, 15), (42, 15)): s.put(x, y, 'c' if pw else 'W')
        mat(s, 3, 7, 16, 17, CRM)                                                  # left: three coils
        for k in range(3):
            lit = pw and (k + i) % 3 == 0 if st.state == 'on' else pw
            cylv(s, 5 + 5 * k, 9, 4, 12, 'MSSW') if False else None
            for r in range(0, 12, 2):
                s.hline(5 + 5 * k, 9 + r, 4, 'c' if lit else 'S'); s.hline(5 + 5 * k, 10 + r, 4, 'B' if lit else 'W')
            s.put(6 + 5 * k, 8, 'H' if lit else 'M')
        mat(s, 45, 8, 16, 16, CRM)                                                 # right: lamps and aerials
        s.rect(47, 11, 12, 4, 'D')
        for k in range(4): s.rect(48 + 3 * k, 12, 2, 2, ('g', 'c', 'p', 'y')[k] if pw and (k + i) % 4 != 1 else 'E')
        antenna(s, 50, 7, 6, pw, i, 'c', 0); antenna(s, 57, 7, 8, pw, i, 'p', 1)
        s.hline(47, 20, 3, 'q'); s.hline(51, 20, 2, 'q')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing_f(s, y)
        cable_stub(s, 3, y + 8, st, 'c', ('M', 'S', 'W'))
        mat(s, 15, y + 5, 30, 15, ('M', 'S', 'W'), cham=False)                      # the coil rail
        s.rect(16, y + 14, 28, 2, 'D')
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 5 if st.i == 0 else 0
        for k in range(3):
            lit = pw and n >= (1 + 2 * k)
            x = 18 + 9 * k
            if st.state == 'damaged' and k == 1: lit = False
            for r in range(0, 8, 2):
                s.hline(x, y + 6 + r, 6, ('H' if (st.state == 'fire' and st.i == 0) else 'c') if lit else 'S'); s.hline(x, y + 7 + r, 6, 'B' if lit else 'W')
            s.put(x + 2, y + 5, 'H' if lit else 'M'); s.put(x + 3, y + 5, 'H' if lit else 'M')
            if st.state == 'disabled' and k == 2: s.hline(x, y + 6, 6, 'W')
        if pw and n == 5:
            for (x, yy) in ((24, y + 9), (33, y + 8), (26, y + 11), (35, y + 10)): s.put(x, yy, 'H')
        hatch_k(s, 47, y + 6, CRM_D, 11, 9, 'p')
        leds(s, st, 16, y + 25)
    def hurt_out(self, s, st):
        move(s, 56, 0, 3, 8, 2, 1); s.put(60, 1, 'K'); crack(s, [(31, 4), (30, 8), (32, 11)]); wire(s, [(9, 9), (11, 11), (10, 14)], 'c')
        crack(s, [(48, 10), (50, 14)])
        hurt_pair(s, st, (9, 6), (53, 22))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 4), (30, 8), (32, 12), (30, 17), (31, 22)], [(49, 9), (51, 14), (49, 18)]],
                 dents=[(6, 18, 6, 4), (49, 19, 6, 3)], soots=[(22, 3, 1), (44, 8, 0), (4, 8, 2)],
                 wires_=[[(12, 22), (10, 26)]], sparks=[(35, 6), (9, 12)])
    def hurt_in(self, s, st):
        y = self.iy
        dead = Spr(1, 1)
        for k in (7, 8, 9): s.rect(16 + 4 * k, y + 25, 2, 2, 'E')
        crack(s, [(27, y + 6), (28, y + 10), (26, y + 13)]); s.hline(27, y + 8, 6, 'q')
        hurt_pair(s, st, (40, y + 10), (52, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(27, y + 6), (28, y + 10), (26, y + 13)]); s.stamp(36, y + 21, art(".KK.\nKMSK\nKSWK\n.KK.")); wire(s, [(16, y + 18), (20, y + 21), (26, y + 20)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        leds_glow(g, ox, oy, state, i, 16, y + 25)
        n = {'charge': i, 'on': 5, 'damaged': 4}.get(state, 0)
        if state == 'fire' and i == 0: n = 5
        for k in range(3):
            if n >= 1 + 2 * k and not (state == 'damaged' and k == 1): glow(g, ox + 21 + 9 * k, oy + y + 9, 6, CYAN, 0.4, 2.0)
        glow(g, ox + 12, oy + y + 14, 3, CYAN, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        for k in range(3):
            if state == 'on' and (k + i) % 3 != 0: continue
            glow(g, ox + 7 + 5 * k, oy + 14, 5, CYAN, 0.3, 2.0)
        for x in (50, 57): glow(g, ox + x, oy + 0.5, 3, CYAN, 0.45, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        circ = Spr(44, 25)
        chamfer_fill(b, 1, 5, 14, 15, 'f', 4); rim(b, 'f', 'H', 'Q', (1, 5, 14, 19)); b.put(7, 12, 'L'); b.put(8, 12, 'W')       # the hub
        # the lattice cage: two diamond cells of crossed struts, with a spark core
        cx = 24 + o
        for (x0, y0, x1, y1) in ((14, 12, 22, 3), (14, 12, 22, 21), (22, 3, 31, 12), (22, 21, 31, 12), (22, 3, 22, 21), (13, 12, 13, 12)):
            line(b, x0 + o, y0, x1 + o, y1, 'M'); line(b, x0 + o + (1 if x0 != x1 else 0), y0, x1 + o + (1 if x0 != x1 else 0), y1 + (1 if y0 != y1 else 0), 'S') if False else None
        for (x0, y0, x1, y1) in ((22, 3, 22, 21), (22, 12, 31, 12), (26, 7, 26, 17), (14, 12, 22, 12)): line(b, x0 + o, y0, x1 + o, y1, 'S')
        for (x, y) in ((22, 3), (22, 21), (31, 12), (14, 12), (26, 7), (26, 17), (22, 12)): b.put(x + o, y, 'L'); b.put(x + 1 + o, y, 'M')
        if st.state != 'disabled':
            core = 'H' if st.fire else 'c'
            for (x, y) in ((22, 12), (23, 12), (23, 11), (22, 11)): b.put(x + o, y, core)
            if st.state in ('idle', 'fire') and not st.fire:
                for (x, y) in ((20, 9), (25, 14), (24, 8)): b.put(x + o, y, 'c' if (x + st.i) % 2 else 'C')
        antenna_h(b, 5, 5, 4, st.state == 'idle', st.i, 'c'); antenna_h(b, 9, 5, 3, st.state == 'idle', st.i, 'p', 1); antenna_h(b, 5, 19, 0, False)
    def bhurt(self, b, st):
        move(b, 28, 3, 6, 18, 0, 1); crack(b, [(6, 7), (8, 11), (7, 15)]); b.put(30, 12, 'E')
        spark(b, 33, 5, False) if st.i == 0 else spark(b, 18, 21, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 25, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(6, 7), (8, 11), (7, 15), (9, 18)], 'K', 'S'); wire(b, [(20, 6), (23, 9)])
    def bafter(self, b, st):
        if st.fire:
            for (x, y, c) in ((31, 12, 'H'), (33, 10, 'c'), (34, 14, 'c'), (36, 12, 'H'), (35, 8, 'y'), (36, 16, 'y'), (38, 11, 'c'), (39, 13, 'c')): b.put(x - st.rc + st.i, y, c)
            stamp_flash(b, st, 33, 12, FLASH_T, {'o': 'c', 'y': 'y'})
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 34, 12, CYAN, WHITE, scale=0.8)
        if state in ('idle', 'damaged'): glow(g, ox + 23.5, oy + 12.5, 8, CYAN, 0.3, 2.0)

# ============================================================ MARKET MISSILE
def _tiny_missile():
    """a cheap scrap missile, nose east, 15x5: a tin body, a crooked fin, a red nose."""
    return art("""
.MMMMMMMMMMrr..
LSSSSSSSSSSSrro
.WWWWWWWWWWrr..
...Q.....Q....
...QQ.........
""")

class MarketMissile(FennMount, Weapon):
    id = 'fenn_market_missile'
    blen, bwid = 58, 19
    bpivot = (6, 9)
    bmuzzle = (38, 5)
    out_notes = ('OUTSIDE half of the Fenn Market Missile: a cheerful cream body with a brown crate of scrap warheads on the left (lids tied with string), a price-tag flag on a stick and a lamp panel on the right. '
                 'damaged: crate lid hanging, the flag torn, sparks; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Fenn Market Missile: a rough brown crate with five slots; a scrap missile drops into the chute and the slots fill one by one as it charges (frame 5 = five loaded, lamps green), power coupling, hatch. '
             'fire: the lead missile is gone and the lamps flash. damaged: a slot cracked, a dud missile stuck crooked, lamps dead; disabled: the crate broken, missiles spilled. '
             'Barrel layer fenn_market_missile_barrel: a light twin-rail cradle with two crooked scrap missiles, a pennant; fire: the missiles leave, smoke.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        fenn_out_base(s)
        mat(s, 3, 8, 17, 16, ('Q', 'q', 'n'))                                      # left: the crate
        for yy in (10, 16, 21): s.hline(4, yy, 15, 'n')
        for xx in (8, 14): s.vline(xx, 9, 14, 'n')
        for (x, y) in ((6, 12), (11, 13), (16, 11)): s.put(x, y, 'r')
        s.hline(4, 9, 15, 'Q'); s.put(5, 10, 'H')
        wire(s, [(3, 18), (10, 18), (19, 16)], 'f')
        mat(s, 44, 8, 17, 16, CRM)                                                 # right: lamp panel + flag
        s.rect(46, 11, 13, 4, 'D')
        for k in range(4): s.rect(47 + 3 * k, 12, 2, 2, ('r', 'y', 'g', 'c')[k] if pw and (k + i) % 4 != 2 else 'E')
        s.vline(56, 1, 8, 'M'); s.rect(52, 1, 4, 3, 'p'); s.put(52, 1, 'H'); s.put(53, 2 + i % 2, 'D')
        s.hline(46, 19, 3, 'q'); s.hline(50, 19, 2, 'q')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing_f(s, y)
        cable_stub(s, 3, y + 8, st, 'y', ('M', 'S', 'W'))
        mat(s, 15, y + 5, 30, 15, ('Q', 'q', 'n'), cham=False)                      # the crate
        for k in range(5): s.rect(17 + 6 * k, y + 7, 5, 11, 'D'); s.hline(17 + 6 * k, y + 7, 5, 'K')
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 4 if st.i == 0 else 3
        for k in range(5):
            if k < n and pw or (st.state == 'disabled' and k in (1, 3)):
                x = 17 + 6 * k
                s.rect(x + 1, y + 9, 3, 8, 'M'); s.hline(x + 1, y + 8, 3, 'r'); s.put(x + 2, y + 9, 'H'); s.hline(x + 1, y + 16, 3, 'Q')
        hatch_k(s, 47, y + 6, CRM_D, 11, 9, 'p')
        leds(s, st, 16, y + 25, c=('y', 'g'))
        s.put(8, y + 3, 'p')
    def hurt_out(self, s, st):
        move(s, 3, 8, 17, 4, 1, -1) if False else s.stamp(4, 4, art("KKKKK.\nKQQqnK\n.KKKK."))
        s.hline(52, 3, 4, 'K'); s.put(54, 3, 'K'); crack(s, [(48, 10), (50, 14)])
        hurt_pair(s, st, (9, 5), (53, 22))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 5), (30, 9), (32, 13), (30, 18), (31, 23)], [(48, 9), (50, 13), (48, 17)]],
                 dents=[(6, 18, 6, 4), (49, 19, 6, 3)], soots=[(24, 3, 1), (45, 8, 0), (4, 8, 2)],
                 wires_=[[(56, 6), (58, 9), (57, 12)]], sparks=[(35, 6), (9, 12)])
    def hurt_in(self, s, st):
        y = self.iy
        for k in (7, 8, 9): s.rect(16 + 4 * k, y + 25, 2, 2, 'E')
        crack(s, [(29, y + 6), (30, y + 11), (28, y + 15)]); s.stamp(33, y + 12, art("QQq\nqQQ\n.nq"))
        hurt_pair(s, st, (40, y + 8), (52, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(23, y + 6), (24, y + 11), (22, y + 17)]); crack(s, [(36, y + 6), (37, y + 12)]); s.stamp(40, y + 21, art(".KK.\nKMrK\nKSWK\n.KK.")); wire(s, [(16, y + 18), (20, y + 21)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        leds_glow(g, ox, oy, state, i, 16, y + 25)
        glow(g, ox + 12, oy + y + 14, 3, YEL, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        for k in range(4): glow(g, ox + 48 + 3 * k, oy + 12.5, 3, (RED, YEL, GREEN, CYAN)[k], 0.35, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 1, 3, 10, 13, 'H', 'f', 'Q'); b.rect(3, 7, 4, 4, 'D'); b.put(5, 9, 'L')
        for ry in (1, 15):                                                         # two light rails
            cylh(b, 11 + o, ry, 27, 3, 'MSW'); b.vline(14 + o, ry - 1, 5, 'S'); b.vline(26 + o, ry - 1, 5, 'S'); b.vline(37 + o, ry - 1, 5, 'M')
        bev(b, 11 + o, 6, 4, 7, 'M', 'S', 'W', cham=False)
        if not (st.fire and st.i >= 1) and st.state != 'disabled' or st.state == 'disabled':
            b.stamp(16 + o, 4, _tiny_missile()); b.stamp(18 + o, 11, _tiny_missile(), None)
        if st.fire:
            for (x, y) in ((19 + 2 * st.i, 8), (22 + st.i, 13), (14 + st.i * 3, 6)): b.stamp(x, y, SMOKE[st.i % 2]) if x < 50 else None
        s = b
        b.vline(8, 0, 3, 'M'); b.rect(5, 0, 3, 2, 'p'); b.put(5, 0, 'H')
    def bhurt(self, b, st):
        move(b, 16, 11, 16, 5, 0, 2); b.put(31, 15, 'q')
        crack(b, [(24, 1), (25, 3)]); spark(b, 36, 6, False) if st.i == 0 else spark(b, 24, 0, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 27, 2, 2)
    def bwreck(self, b, st):
        wire(b, [(20, 8), (23, 10)]); crack(b, [(17, 1), (18, 3)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 33, 9, FLASH_T, {'o': 'o', 'y': 'y'})
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 33, 9, ORANGE, WHITE, scale=0.55)

SMOKE = [art("""
.LL..
LMML.
.LMSL
..LL.
"""), art("""
..L.
.LML
LMMS
.LS.
""")]
WEAPONS = [TwitchCannon, SparkLattice, MarketMissile]


# ================================================================== COMPONENTS
def slim_bell(s, x0, w, y0, y1, on, i, k=0):
    """a slim cream-and-steel nozzle: flared lip at y0, a tube down to y1, a thin rim ring, a small flame when lit."""
    T = col_tones(w, 'HLfffQQq')
    for y in range(y0 + 3, y1):
        for q in range(w): s.put(x0 + q, y, T[q])
    for q in range(w + 2): s.put(x0 - 1 + q, y0 + 1, 'M' if q < w // 2 else 'S'); s.put(x0 - 1 + q, y0 + 2, 'S' if q < w // 2 else 'W')
    for q in range(w + 2): s.put(x0 - 1 + q, y0 + 3, 'W')
    s.hline(x0, y0, w, 'D')
    for yy in range(y0 + 6, y1 - 1, 6): s.hline(x0, yy, w, 'M'); s.hline(x0, yy + 1, w, 'Q')
    s.put(x0 + 1, y0 + 8, 'L') if y1 - y0 > 10 else None
    if on:
        sk = [0, 1, 0][(i + k) % 3]
        s.hline(x0 + 1, y0, w - 2, 'o'); s.hline(x0 + 2 + sk, y0, max(1, w - 4 - 2 * sk), 'y')
        flame(s, x0 + (w - 3) // 2, y0 - 1, 4 + ((i + k) % 3), 3, i + k, hot=True)
    else: s.hline(x0 + 1, y0, w - 2, 'E')

class HaggleEngine(EngBase):
    id = 'fenn_haggle_engine'; KIND = 'std'; DMG = (0, 2)
    pad_out = (10, 30, 10, 4)
    anchors_out = {'exhaust_a': (10, 8), 'exhaust_b': (24, 4), 'exhaust_c': (40, 6), 'exhaust_d': (54, 10)}
    anchors_in = {'power_coupling': (33, 29), 'repair_hatch': (13, 29)}
    notes = ('Fenn "Haggle Engine" (thrust x1.3, fragile), a hull mount (outward is up): outside, four slim nozzles of different heights standing on a thin cream pad, joined by steel struts, with a blinking antenna '
             'between them and a small quick flame on each (3 frames); a collar through the wall; inside, a cream core of gear trains (they turn on the loop), small dials, a row of lamps, a hatch and a coupling. '
             'Damaged: the second nozzle has cracked off its neck and hangs, a gear is loose, sparks. Disabled: nozzles bent and dark, the antenna snapped, gears stopped.')
    def flange_out(self, o):
        o.hline(3, 29, 58, 'f')
        for x in range(6, 58, 8): o.put(x, 29, 'p' if (x // 8) % 2 else 'c')
    def flange_in(self, c):
        c.hline(3, 2, 58, 'f')
        for x in range(6, 58, 8): c.put(x, 2, 'p' if (x // 8) % 2 else 'c')
    NOZ = [(5, 8, 9), (19, 9, 5), (35, 9, 7), (49, 8, 11)]
    def out(self, o, on, i):
        mat(o, 3, 25, 58, 4, ('M', 'S', 'W'))
        for (x0, w, y0) in self.NOZ: slim_bell(o, x0, w, y0, 26, on, i, x0)
        for yy in (17, 21): o.hline(8, yy, 50, 'S'); o.hline(8, yy + 1, 50, 'W')
        antenna(o, 31, 21, 17, on, i, 'c', 0)
        for (x, y) in ((16, 17), (30, 17), (44, 17)): o.put(x, y, 'L')
    def core(self, c, on, i):
        mat(c, 1, 1, 62, 30, CRM); c.hline(3, 3, 58, 'H')
        for x0 in (8, 24, 40, 54): c.rect(x0, 0, 4, 3, 'M'); c.vline(x0, 0, 3, 'L'); c.vline(x0 + 3, 0, 3, 'W')
        mat(c, 4, 6, 24, 15, ('M', 'S', 'W'), cham=False)                              # gear trains
        gear(c, 10, 13, 4, turn=i if on else 0); gear(c, 19, 11, 3, turn=i + 1 if on else 0); gear(c, 22, 17, 2, turn=i if on else 0)
        line(c, 6, 18, 8, 17, 'q')
        for k, gx in enumerate((34, 42, 50, 58)): gauge(c, gx, 11, 3 if k % 2 == 0 else 2, on, (i + k) % 4 if on else 0)
        c.hline(31, 17, 29, 'q')
        for x in range(32, 59, 5): c.put(x, 17, 'Q')
        for k in range(8):
            col = ('c', 'g', 'y', 'p')[k % 4] if on and (k + i) % 3 else 'E'
            c.rect(31 + 4 * k, 20, 2, 2, col)
        mat(c, 5, 22, 17, 8, CRM_D); hollow(c, 8, 24, 11, 4, 'q'); c.put(10, 26, 'p' if on else 'q')
        for (x, y) in ((7, 24), (19, 24)): c.put(x, y, 'M')
        mat(c, 27, 22, 12, 8, ('M', 'S', 'W'))
        circle(c, 33, 26, 3.2, 'D'); ring(c, 33, 26, 2.2, 3.8, 'c' if on else 'W')
        for q, x in enumerate((44, 48, 52, 56)): c.put(x, 27, 'c' if on and (q + i) % 2 else 'E'); c.put(x, 28, 'p' if on and (q + i) % 2 == 0 else 'E')
    def hurt_out(self, o, i):
        move(o, 18, 3, 10, 10, -2, 5); o.hline(18, 14, 11, 'K'); o.put(21, 13, 'o'); o.put(22, 12 - i, 'y')
        antenna_bent = None
        move(o, 28, 0, 6, 5, 2, 1)
        crack(o, [(36, 14), (38, 18), (37, 22)], 'M'); o.put(42 + i, 6, 'o')
    def wreck_out(self, o):
        for (x0, w, y0) in self.NOZ: shift_rect(o, x0 - 1, x0 + w + 1, 0, 25, (-2 if x0 < 30 else 2), 2)
        o.stamp(30, 3, art("KKK\nKML\n.KK")); crack(o, [(10, 12), (12, 18), (11, 24)], 'M'); crack(o, [(52, 14), (54, 20)], 'M')
        for (x, y) in ((24, 14), (40, 15)): o.put(x, y, 'K')
    def hurt_core(self, c, i):
        gear(c, 19, 11, 3, turn=0); c.stamp(18, 17, art("KKK.\nKMSK\n.KSK")); crack(c, [(5, 7), (8, 11), (6, 15)], 'M')
        gauge(c, 42, 11, 2, False, 0); crack(c, [(41, 9), (43, 12)], 'K')
        spark(c, 33, 25, False) if i == 0 else spark(c, 52, 17, False)
        for k in (5, 6, 7): c.rect(31 + 4 * k, 20, 2, 2, 'E')
    def wreck_core(self, c):
        crack(c, [(5, 7), (8, 11), (6, 15), (9, 19)], 'M'); crack(c, [(38, 4), (40, 12), (37, 20)], 'M')
        c.stamp(14, 15, art(".KK.\nKMSK\nKSWK\n.KK.")); wire(c, [(30, 24), (34, 28), (38, 28)], 'q')
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        for n, (x0, w, y0) in enumerate(self.NOZ):
            if flick is not None and n == 1: continue
            inten = [0.8, 1.0, 0.9][(i + n) % 3]
            glow_xy(g, ox + x0 + w / 2, oy + y0 - 1, 6, 15, ORANGE, 0.5 * inten * k, 1.8)
            glow(g, ox + x0 + w / 2, oy + y0, 4, YEL, 0.5 * inten * k, 1.7)
        glow(g, ox + 31, oy + 3, 3, CYAN, 0.5, 2.0)
    def glow_core(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        b = oy + 4
        for q, x in enumerate((44, 48, 52, 56)):
            if (q + i) % 2: glow(g, ox + x + 1, b + 27.5, 3, CYAN, 0.4 * k, 2.0)
        glow(g, ox + 33.5, b + 26.5, 4, CYAN, 0.4 * k, 2.0)

class JuryReactor(LK.LComp):
    id = 'fenn_jury_reactor'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    PULSE = [8, 9, 10, 9]
    notes = ('Fenn "Jury Reactor": a jury-rigged cream frame holding a round glass jar with a pulsing amber core, four mismatched capacitor cans in the corners (coloured caps that blink in turn), '
             'loops of wire and taped joints between them, and two blinking antennas. Damaged: the jar cracked and leaking light, a can hanging off its wire, sparks at a joint. '
             'Disabled: the jar dark and split, cans knocked loose, the tape peeled, the antennas bent.')
    CANS = [(5, 5, 'r'), (49, 5, 'g'), (5, 49, 'c'), (49, 49, 'y')]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 62, 62, 'f', 7); rim(s, 'f', 'H', 'Q')
        chamfer_fill(s, 5, 5, 54, 54, 'S', 5); rim(s, 'S', 'M', 'W', (5, 5, 58, 58))
        for t in range(6, 58, 6): s.put(t, 3, 'p' if (t // 6) % 2 else 'c'); s.put(t, 60, 'c' if (t // 6) % 2 else 'p')
        for (x, y, c) in self.CANS:                                                   # capacitor cans
            mat(s, x, y, 10, 10, ('M', 'S', 'W')); circle(s, x + 5, y + 5, 3.2, 'D'); circle(s, x + 5, y + 5, 2.2, 'E')
            k = self.CANS.index((x, y, c))
            lit = on and (k + i) % 4 == 0
            s.rect(x + 3, y + 3, 4, 4, c if on else 'W'); s.put(x + 3, y + 3, 'H' if lit else (c if on else 'W'))
        for (a, b) in (((14, 10), (24, 20)), ((49, 10), (40, 20)), ((14, 54), (24, 43)), ((49, 54), (40, 43))): line(s, a[0], a[1], b[0], b[1], 'q'); line(s, a[0], a[1] + 1, b[0], b[1] + 1, 'n')
        hazard(s, 27, 5, 10, 3); hazard(s, 27, 56, 10, 3)
        for yy in (28, 33): s.rect(3, yy, 4, 2, 'a'); s.rect(57, yy, 4, 2, 'a')
        circle(s, 32, 32, 18, 'M'); circle(s, 32, 32, 17, 'S'); ring(s, 32, 32, 15, 17, 'f')                     # the jar: a cream rim, glass inside
        for y in range(13, 52):
            for x in range(13, 52):
                if s.get(x, y) == 'f' and (x - 32) + (y - 32) < -12: s.put(x, y, 'H')
        circle(s, 32, 32, 14.4, 'D')
        if on:
            r = self.PULSE[i]
            circle(s, 32, 32, r, 'a'); circle(s, 32, 32, r - 1.5, 'o'); circle(s, 32, 32, r - 4, 'y'); circle(s, 32, 32, max(2, r - 7), 'H')
            for (dx, dy) in ((-9, -6), (8, -8), (10, 5), (-7, 9)): s.put(32 + dx + (i % 2), 32 + dy, 'y')
            for (x, y) in ((22, 24), (41, 24)): s.put(x, y, 'L')
        else:
            circle(s, 32, 32, 8, 'E'); circle(s, 32, 32, 5, 'D'); s.put(30, 30, 'W'); s.put(34, 33, 'W')
        s.rect(29, 18, 6, 3, 'M'); s.rect(29, 43, 6, 3, 'M')
        antenna(s, 8, 5, 0, False) if False else None
        s.vline(20, 0, 6, 'M'); s.put(20, 0, 'c' if on and i % 2 == 0 else 'L'); s.vline(44, 0, 6, 'M'); s.put(44, 0, 'p' if on and i % 2 else 'L')
        return s
    def hurt(self, s, i):
        crack(s, [(22, 20), (26, 24), (25, 30), (30, 34), (29, 40)], 'K')
        for (x, y) in ((24, 24), (27, 29), (28, 36)): s.put(x, y, 'o' if (x + i) % 2 else 'y')
        move(s, 5, 49, 10, 10, 3, 2 + i); line(s, 14, 50, 16, 52, 'q'); spark(s, 16, 50, False)
        s.stamp(18, 18, art("KK.\nKfK\n.KK")) if False else None
        s.hline(27, 5, 10, 'K'); s.put(30, 5, 'a'); s.put(34, 6, 'a')
        if i == 1:
            for (x, y) in ((32, 32), (33, 32), (32, 33), (33, 33)): s.put(x, y, 'o')
    def wreck(self, s):
        crack(s, [(22, 20), (26, 24), (25, 30), (30, 34), (29, 40), (33, 46)], 'K'); crack(s, [(40, 22), (36, 28), (38, 33)], 'K')
        move(s, 49, 5, 10, 10, 4, 3); move(s, 5, 5, 10, 10, -2, 4); s.stamp(20, 0, art("KK\nKM")); s.stamp(40, 1, art(".KK\nKMK"))
        wire(s, [(14, 54), (20, 58), (28, 60)], 'q'); fallen_chunk(s, 52, 50)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.85)
        r = self.PULSE[i]
        glow(g, ox + 32, oy + 32, 22 + r, ORANGE, (0.28 + 0.025 * r) * k, 1.4)
        glow(g, ox + 32, oy + 32, 5 + r * 0.8, YEL, 0.5 * k, 1.6)
        for kk, (x, y, c) in enumerate(self.CANS):
            if (kk + i) % 4 == 0: glow(g, ox + x + 5, oy + y + 5, 6, {'r': RED, 'g': GREEN, 'c': CYAN, 'y': YEL}[c], 0.5 * k, 2.0)
        glow(g, ox + 20.5, oy + 0.5, 3, CYAN, 0.4 if i % 2 == 0 else 0.15, 2.0); glow(g, ox + 44.5, oy + 0.5, 3, PINK, 0.4 if i % 2 else 0.15, 2.0)
        if flick is not None: glow(g, ox + 16, oy + 50, 6, YEL, 0.5 if flick else 0.25, 2.0)

class QuickfixBay(LK.LComp):
    id = 'fenn_quickfix_bay'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 2, 4), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    DMG = (0, 1)
    notes = ('Fenn "Quickfix Bay": a cream workbench cabinet with a circuit board on the bench and two thin jointed arms that reach in from both sides; on loop (2) the arms swap poses and a solder spark flashes at one tip, '
             'then the other. A tool rack of tiny coloured handles along the bottom. Damaged: one arm snapped and dangling, the board cracked, sparks. Disabled: arms folded and dark, board dead, a tool fallen.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        mat(s, 1, 1, 30, 30, CRM)
        mat(s, 4, 4, 24, 16, ('S', 'W', 'E'), cham=False); s.hline(4, 4, 24, 'K')
        mat(s, 11, 8, 10, 8, ('g', 'T' if False else 'g', 'E'), cham=False) if False else None
        s.rect(11, 8, 10, 8, 'D'); s.hline(11, 8, 10, 'g'); s.hline(11, 15, 10, 'E')
        for k, (x, y) in enumerate(((13, 10), (16, 11), (19, 10), (14, 13), (18, 13))): s.put(x, y, 'y' if on and (k + i) % 2 == 0 else 'M')
        s.put(12, 9, 'H')
        # two thin arms reaching in from both sides (pose A / pose B)
        pa = [((5, 6), (8, 9), (12, 10)), ((5, 6), (9, 5), (13, 7))][i % 2] if on else ((5, 6), (8, 9), (11, 10))
        pb = [((27, 17), (24, 14), (20, 13)), ((27, 17), (23, 17), (19, 15))][i % 2] if on else ((27, 17), (24, 14), (21, 13))
        for pts in (pa, pb):
            for (a, b) in zip(pts, pts[1:]): line(s, a[0], a[1], b[0], b[1], 'H')
            for (x, y) in pts[1:-1]: s.rect(x, y, 2, 2, 'L')
            s.put(pts[-1][0], pts[-1][1], 'S')
        mat(s, 3, 3, 4, 4, ('M', 'S', 'W')); mat(s, 25, 15, 4, 4, ('M', 'S', 'W'))
        if on:
            sx, sy = (pa[-1] if i == 0 else pb[-1])
            s.put(sx, sy, 'H'); s.put(sx - 1, sy, 'y'); s.put(sx + 1, sy, 'y'); s.put(sx, sy - 1, 'y')
        # the tool rack
        s.rect(4, 23, 24, 6, 'D'); s.hline(4, 23, 24, 'K')
        for k, c in enumerate(('c', 'p', 'y', 'g', 'c', 'p')): s.rect(6 + 4 * k, 24, 2, 4, 'M'); s.rect(6 + 4 * k, 24, 2, 2, c if True else 'W')
        s.put(26, 22, 'g' if on else 'E')
        return s
    def hurt(self, s, i):
        line(s, 24, 14, 22, 20, 'M'); line(s, 22, 20, 24, 22, 'S'); s.rect(21, 12, 6, 4, 'E') if False else None
        crack(s, [(14, 8), (16, 11), (14, 15)], 'K')
        spark(s, 22, 21, False) if i == 0 else spark(s, 12, 9, False)
        for (x, y) in ((24, 22), (25, 23)): s.put(x, y, 'S')
    def wreck(self, s):
        crack(s, [(14, 8), (16, 11), (14, 15)], 'K'); line(s, 24, 14, 22, 19, 'S'); s.stamp(8, 24, art("KK.\nKMK\n.KK")); crack(s, [(3, 18), (8, 22)], 'K')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.6 if flick else 0.9)
        if state == 'on':
            tip = (12, 10) if i == 0 else (19, 15)
            glow(g, ox + tip[0] + .5, oy + tip[1] + .5, 6, YEL, 0.6 * k, 2.0)
        glow(g, ox + 27, oy + 22.5, 3, GREEN, 0.4 * k, 2.0)
        for q, c in enumerate((CYAN, PINK, YEL, GREEN, CYAN, PINK)): glow(g, ox + 7 + 4 * q, oy + 25, 3, c, 0.25 * k, 2.0)

COMPONENTS = [Half2(HaggleEngine(), 'core'), Half2(HaggleEngine(), 'out'), JuryReactor, QuickfixBay]

# ================================================================== PROJECTILES AND IMPACTS (quick sparks, tiny bolts)
def _bolt():
    out = []
    for k in range(3):
        s = Spr(5, 11)
        s.stamp(1, 0, art("""
.y.
yHy
yHy
.y.
"""))
        tail = [(".o.", ".r.", ".o.", "..."), (".r.", ".o.", "...", ".r."), (".o.", "...", ".r.", ".o.")][k]
        for j, row in enumerate(tail):
            for i, c in enumerate(row):
                if c != '.': s.put(1 + i, 4 + j, c)
        for (x, y) in (((1 + 2 * k) % 5, 3 + 3 * (k % 2)), ((3 + k) % 5, 9 - k)): s.put(x, y, 'c')
        out.append(s)
    return out

def _bolt_impact():
    f = []
    s = Spr(12, 12); disc(s, 6, 6, 2.5, 'H'); rays(s, 6, 6, 8, 3, 5, 'yc', 0.2)
    f.append(s)
    s = Spr(12, 12); disc(s, 6, 6, 1.5, 'y'); rays(s, 6, 6, 8, 3, 5, 'cy', 0.4); dots(s, 6, 6, 5, 8, 'c', 0.0, 2)
    f.append(s)
    s = Spr(12, 12); dots(s, 6, 6, 4, 6, 'c', 0.3); dots(s, 6, 6, 5, 8, 'y', 0.0, 2)
    f.append(s)
    return f

def _splinters():
    out = []
    for k in range(3):
        s = Spr(9, 14)
        for (x0, y0, x1, y1, c) in (((4, 1, 4, 9, 'H')), (((2 + k % 2), 3, 1, 10, 'c')), ((6 - k % 2, 3, 7, 10, 'c')), ((3, 4, 2 - k % 2, 12, 'C')), ((5, 4, 6 + k % 2, 12, 'C')) ):
            pass
        for (x0, y0, x1, y1, c) in ((4, 0, 4, 8, 'H'), (3, 3, 1 + (k % 2), 10, 'c'), (5, 3, 7 - (k % 2), 10, 'c'), (3, 6, 2, 13 - k % 2, 'C'), (5, 6, 6, 13 - (k + 1) % 2, 'C')):
            line(s, x0, y0, x1, y1, c)
        s.put(4, 0, 'H'); s.put(4, 1, 'H'); s.put(3, 3, 'H') if k == 1 else None
        out.append(s)
    return out

def _splinter_impact():
    f = []
    s = Spr(16, 16); disc(s, 8, 8, 2.5, 'H'); rays(s, 8, 8, 12, 3, 7, 'Hcc', 0.0)
    f.append(s)
    s = Spr(16, 16); disc(s, 8, 8, 1.5, 'c'); rays(s, 8, 8, 12, 4, 7, 'cC', 0.26); dots(s, 8, 8, 7, 12, 'H', 0.0, 3)
    f.append(s)
    s = Spr(16, 16); rays(s, 8, 8, 12, 6, 7, 'C', 0.13); dots(s, 8, 8, 4, 6, 'c', 0.2); s.put(8, 8, 'c')
    f.append(s)
    return f

def _market():
    out = []
    for k in range(3):
        s = Spr(7, 16)
        s.stamp(1, 0, art("""
..r..
.rrr.
.MLM.
.MSM.
.MSM.
.MSW.
.MSW.
.WWW.
"""))
        s.put(0, 6 + (k % 2), 'Q'); s.put(0, 7 + (k % 2), 'q'); s.put(6, 5, 'Q'); s.put(6, 6, 'q')
        s.put(3, 1, 'H') if k == 1 else None
        ex = [("..y..", ".yoy.", "..o..", "..r.."), (".yHy.", "..o..", ".o.r.", "..r.."), ("..y..", ".yoo.", "..r..", "...r.")][k]
        for j, row in enumerate(ex):
            for i, c in enumerate(row):
                if c != '.': s.put(1 + i, 8 + j, c)
        for (x, y) in ((k % 2, 12 + k), (5 + (k % 2) - 1, 13 + (k % 2))): s.put(x, y, 'y')
        out.append(s)
    return out

def _market_impact():
    f = []
    s = Spr(16, 16); disc(s, 8, 8, 4.5, 'o'); disc(s, 8, 8, 3, 'y'); disc(s, 8, 8, 1.5, 'H'); rays(s, 8, 8, 8, 5, 7, 'yo', 0.2)
    f.append(s)
    s = Spr(16, 16); disc(s, 8, 8, 2.5, 'o'); disc(s, 8, 8, 1.2, 'y')
    for k, (dx, dy, c) in enumerate(((5, -2, 'p'), (3, 5, 'y'), (-4, 5, 'c'), (-6, -1, 'g'), (-3, -5, 'p'), (1, -6, 'y'), (6, 3, 'c'), (-6, 4, 'g'))): s.rect(8 + dx, 8 + dy, 2, 1, c)
    f.append(s)
    s = Spr(16, 16)
    for k, (dx, dy, c) in enumerate(((7, -4, 'p'), (4, 7, 'y'), (-6, 7, 'c'), (-8, -2, 'g'), (-5, -7, 'p'), (2, -8, 'y'), (8, 4, 'c'), (-8, 5, 'g'))): s.put(8 + dx, 8 + dy, c)
    dots(s, 8, 8, 3, 5, 'r', 0.2)
    f.append(s)
    s = Spr(16, 16)
    for k, (dx, dy, c) in enumerate(((7, 1, 'p'), (3, 8, 'y'), (-7, 5, 'c'), (-8, 3, 'g'), (-5, 7, 'p'), (1, 6, 'y'))): s.put(8 + dx, 8 + dy, c)
    f.append(s)
    return f

PROJECTILES = [
    Proj('fenn_twitch_cannon', _bolt(), _bolt_impact(), (2, 3), (2, 10), fps=18, ifps=18, pad=4, ipad=3, bands=((1.5, 110), (3.0, 52)),
         notes='A tiny quick bolt, 5x11: a small yellow-white pellet with a short orange tail and cyan sparks (3 frames, 18 fps, it flickers fast).',
         inotes='A little spark pop: white disc, a ring of cyan and yellow sparks, scatter (3 frames, 12x12).'),
    Proj('fenn_spark_lattice', _splinters(), _splinter_impact(), (4, 1), (4, 12), fps=18, ifps=16, pad=4, ipad=4, bands=((1.5, 100), (3.2, 48)),
         notes='A fan of three cyan-white splinters, 9x14, that jitter over 3 frames: the lattice fires shards. Head anchor is the lead splinter tip.',
         inotes='A starburst of splinters: a white flash and twelve cyan rays, then fading shards (3 frames, 16x16).'),
    Proj('fenn_market_missile', _market(), _market_impact(), (3, 1), (3, 12), fps=14, ifps=12, pad=4, ipad=4, bands=((1.5, 100), (3.2, 48)),
         notes='A cheap scrap missile, 7x16: a tin body, a red nose, two crooked fins of mismatched cardboard-brown, a sputtering exhaust (3 frames). 25% of them are duds: stop them early with no impact.',
         inotes='A pop: a small fireball, then a burst of coloured scraps like confetti (pink, yellow, cyan, green), settling (4 frames, 16x16).'),
]
