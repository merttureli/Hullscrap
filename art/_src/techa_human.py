"""Human tech (docs/waves/racial_tech_1.md): Concord clean and Clan practical. The standard steel line (M/S/W, symmetrical, registry stencils, tidy seams) with a Concord blue
accent (shield blue b, navy J/I) and Clan amber (hazard tape, a/o lamps); nothing ornamental. The generalists' parts are the baseline the other races bend.
Weapons: human_volley_rack, human_concord_railgun, human_flak_screen. Components: human_reactor_plus (reactor), human_comms_array and human_crew_quarters_deluxe (utilities).
Projectile art: clean tracers, Concord rail flashes."""
from techa_kit import *
from comp_new import pipe_v, pipe_h as _pipe_h
from lines_kit import stencil

class Std:
    """the standard line's flange (steel, bolts), with a thin Concord blue line on it."""
    def trim(self, s, st, half):
        fy = 2 if half == 'in' else s.h - 3
        s.hline(6, fy, 52, 'b' if st.powered else 'W')
        for x in (10, 22, 41, 53): s.put(x, fy, 'c' if st.powered else 'W')

def blue_strip(s, st, y):
    strip(s, st, STRIP_X, y, cols=('c', 'b', 'g'))

def stencil_h(s, x, y, c='W'):
    s.hline(x, y, 3, c); s.hline(x + 4, y, 2, c); s.hline(x + 7, y, 3, c)

# ============================================================ VOLLEY RACK
class VolleyRack(Std, Weapon):
    id = 'human_volley_rack'
    blen, bwid = 62, 29
    bpivot = (6, 14)
    bmuzzle = (46, 6)
    out_notes = ('OUTSIDE half of the Human Volley Rack: the Concord steel block with an amber-lit loader hatch (three lamps, one per tube) on the left, a sensor and rounds counter on the right, a blue registry stripe. '
                 'damaged: ring cracked, cover flapping, sparks; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Human Volley Rack: a three-slot missile cradle with a feed chute on the right; a small missile slides into each slot as it charges (frames 0..5 seat 0,1,1,2,2,3; frame 5 = three seated, strip green), '
             'power coupling, repair hatch. fire: all three slots empty and the strip discharges. damaged: chute cracked, a missile jammed crooked, lamps dead; disabled: a missile jammed half way in the chute. '
             'Barrel layer human_volley_rack_barrel: a three-tube launcher head, a small missile in each tube; fire: the three leave one after another, smoke.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        gun_housing(s)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')
        bev(s, 5, 8, 12, 8, 'M', 'S', 'W', cham=False); s.hline(7, 12, 8, 'W'); s.put(6, 9, 'L'); s.put(15, 14, 'L')
        for k in range(3): s.rect(5 + 4 * k, 18, 3, 3, 'o' if pw and (k < 2 or i == 0 or st.state != 'on') else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')
        s.rect(48, 9, 10, 6, 'D'); s.hline(48, 9, 10, 'K')
        for k in range(3): s.put(50 + 3 * k, 12, 'c' if pw else 'E'); s.put(51 + 3 * k, 12, 'c' if pw else 'E')
        s.rect(49, 17, 8, 3, 'J'); s.hline(49, 17, 8, 'j'); stencil_h(s, 48, 22)
        bolts(s, [(47, 8), (58, 8), (47, 22), (58, 22)])
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y)
        coupling(s, 3, y + 2, st, 'o'); hatch(s, 3, y + 16, st, 9, 8)
        bev(s, 14, y + 5, 34, 15, 'W', 'E', 'D', cham=False)
        s.hline(15, y + 6, 32, 'S'); s.hline(15, y + 18, 32, 'W')
        for bx in (25, 36): s.vline(bx, y + 7, 11, 'E')
        bev(s, 48, y + 5, 15, 15, 'S', 'E', 'D')
        s.rect(51, y + 8, 12, 9, 'D'); s.hline(51, y + 8, 12, 'K'); s.hline(51, y + 17, 12, 'M')
        n = {'on': 3, 'damaged': 3, 'off': 3, 'disabled': 1}.get(st.state, 0)
        if st.charge: n = (st.i + 1) // 2
        if st.state == 'fire': n = 0
        for k in range(3):                                                         # three missile slots
            x0 = 16 + 11 * k
            s.rect(x0, y + 9, 9, 7, 'D'); s.hline(x0, y + 9, 9, 'K')
            if k < n or (st.state == 'disabled' and k == 0):
                off = 0 if st.state != 'disabled' else 5
                for r, c in enumerate('LMSW'): s.hline(x0 + 1 + off, y + 10 + r, 6, c)
                s.hline(x0 + 6 + off, y + 10, 2, 'r'); s.hline(x0 + 6 + off, y + 11, 2, 'r'); s.put(x0 + 8 + off, y + 11, 'o') if off == 0 else None
        for k in range(2): s.put(54 + 4 * k, y + 11, 'a'); s.put(55 + 4 * k, y + 12, 'a'); s.put(54 + 4 * k, y + 13, 'a')
        blue_strip(s, st, y + STRIP_DY)
        stencil_h(s, 20, y + 22, 'W') if False else None
    def hurt_out(self, s, st):
        crack(s, [(31, 4), (30, 8), (32, 11), (30, 14)]); crack(s, [(52, 6), (53, 9), (51, 12)])
        s.stamp(2, 5, FLAP); wire(s, [(10, 6), (12, 7), (14, 7)])
        hurt_pair(s, st, (10, 4), (56, 3))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 4), (30, 8), (32, 11), (30, 14), (31, 17), (33, 22)], [(52, 7), (53, 10), (51, 14)]],
                 dents=[(7, 17, 6, 5), (50, 14, 6, 4)], soots=[(22, 3, 1), (44, 5, 0), (5, 8, 2)],
                 wires_=[[(56, 6), (58, 9), (57, 12)]], sparks=[(26, 8), (56, 4)], flap=(2, 5))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(35, y + 6), (36, y + 10), (35, y + 14)]); s.stamp(27, y + 11, art("QQq\nqQQ\n.nq"))
        hurt_pair(s, st, (21, y + 12), (52, y + 14))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(25, y + 6), (24, y + 10), (26, y + 14), (24, y + 19)]); crack(s, [(48, y + 8), (51, y + 12), (50, y + 15)])
        wire(s, [(14, y + 19), (16, y + 22), (19, y + 23)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, live_rgb=(60, 242, 255))
        glow(g, ox + 12, oy + y + 6, 3, ORANGE, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        for k in range(3): glow(g, ox + 6.5 + 4 * k, oy + 19.5, 3, ORANGE, 0.45, 2.0)
        for k in range(3): glow(g, ox + 51 + 3 * k, oy + 12.5, 3, CYAN, 0.4, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 1, 5, 11, 19, 'M', 'S', 'W'); b.rect(4, 11, 5, 5, 'D'); b.put(6, 13, 'L'); b.put(7, 14, 'W')
        for bx in (12,): b.vline(bx, 3, 23, 'L'); b.vline(bx + 1, 3, 23, 'W')
        bev(b, 14 + o, 2, 31, 25, 'M', 'S', 'W')                                    # the rack body
        for k, ty in enumerate((4, 12, 20)):                                         # three tubes
            b.rect(17 + o, ty, 28, 5, 'D'); b.hline(17 + o, ty, 28, 'K'); b.hline(17 + o, ty + 4, 28, 'W')
            gone = st.fire and st.i >= 1 and k <= st.i - 1 or (st.fire and st.i == 2)
            if st.state != 'disabled' and not gone and not (st.fire and k == 0 and st.i >= 1):
                x0 = 18 + o
                for r, c in enumerate('LMSW'): b.hline(x0, ty + r if r < 4 else ty + 3, 22, c) if r < 4 else None
                b.hline(x0 + 22, ty, 3, 'r'); b.hline(x0 + 22, ty + 1, 3, 'r'); b.hline(x0 + 22, ty + 2, 3, 'o'); b.put(x0 + 25, ty + 1, 'o')
            if st.state == 'disabled': b.hline(18 + o, ty + 1, 10, 'W')
            b.vline(44 + o, ty - 1, 7, 'S')
        b.hline(20 + o, 9, 22, 'J'); b.hline(20 + o, 17, 22, 'J')
        for x in (20, 30, 40): b.put(x + o, 1, 'L')
    def bhurt(self, b, st):
        crack(b, [(22, 2), (24, 6), (22, 10)]); move(b, 38, 12, 8, 7, 1, 3); b.put(40, 20, 'S')
        hurt_pair(b, st, (45, 3), (22, 27)) if False else None
        spark(b, 44, 26, False) if st.i == 0 else spark(b, 22, 2, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 32, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(21, 2), (23, 8), (22, 14), (24, 22)], 'K', 'S'); wire(b, [(33, 8), (36, 10)])
    def bafter(self, b, st):
        if st.fire:
            for k, ty in enumerate((6, 14, 22)):
                if k <= st.i: stamp_flash(b, st, 47, ty, FLASH_S) if False else b.stamp(47 - st.rc + 1, ty - 3, FLASH_S[min(2, st.i - k)])
            for (x, y) in ((50 + 3 * st.i, 4), (51 + 2 * st.i, 16), (50, 24)): b.stamp(x, y, SMOKE[st.i % 2]) if x < 58 else None
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            for k, ty in enumerate((6, 14, 22)):
                if k <= i: glow(g, ox + 47, oy + ty + .5, (10, 8, 6)[min(2, i - k)], ORANGE, (0.55, 0.45, 0.3)[min(2, i - k)], 2.0, sx=1.3)

# ============================================================ CONCORD RAILGUN
class ConcordRailgun(Std, Weapon):
    id = 'human_concord_railgun'
    blen, bwid = 74, 19
    bpivot = (6, 9)
    bmuzzle = (58, 9)
    out_notes = ('OUTSIDE half of the Human Concord Railgun: the Concord steel block, a bank of three capacitors with blue bands on the left, and a rail cooler with vents and a sensor lamp on the right, stencilled. '
                 'damaged: ring cracked, cover flapping, a capacitor leaking sparks; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Human Concord Railgun: a bank of four tall capacitors that fill with blue-white charge from the bottom (frame 5 = all four bright, strip green), thick power coupling, hatch. '
             'fire: the bank flashes white and drops dark. damaged: one capacitor cracked and weeping, two cells dead; disabled: the bank dark, a capacitor split. '
             'Barrel layer human_concord_railgun_barrel: two long parallel rails with blue field coils and a bright gap between them; fire: a blue-white flash and arc at the muzzle.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        gun_housing(s)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')
        for cx in (6, 9, 12):
            cylv(s, cx, 8, 3, 14, 'LSW')
            s.hline(cx, 13, 3, 'E'); s.hline(cx, 14, 3, 'b' if pw else 'W'); s.hline(cx, 15, 3, 'E')
        s.put(3, 13, 'c' if pw else 'E'); s.put(3, 14, 'c' if pw else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')
        for vx in (48, 53): s.rect(vx, 8, 5, 2, 'D')
        s.rect(48, 12, 10, 1, 'D'); s.rect(48, 15, 10, 1, 'D')
        s.rect(54, 18, 3, 3, 'c' if pw and i == 0 or pw and st.state != 'on' else ('b' if pw else 'E'))
        stencil_h(s, 47, 22)
        bolts(s, [(47, 8), (58, 8), (47, 22), (58, 22)])
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 5 if st.i == 0 else 0
        for k in range(4):                                                         # four tall capacitors
            x0 = 16 + 8 * k
            bev(s, x0, y + 4, 7, 20, 'M', 'S', 'W')
            s.rect(x0 + 1, y + 6, 5, 16, 'D')
            if pw and n:
                hgt = round(n / 5 * 16) if not (st.state == 'damaged' and k == 2) else round(n / 5 * 6)
                for r in range(hgt):
                    s.hline(x0 + 1, y + 21 - r, 5, 'H' if (st.state == 'fire' and st.i == 0) else ('H' if r == hgt - 1 else ('c' if r % 2 == 0 else 'b')))
            s.hline(x0, y + 4, 7, 'L')
        bev(s, 49, y + 4, 12, 20, 'M', 'S', 'W'); hatch(s, 50, y + 8, st, 10, 8)
        s.hline(51, y + 19, 3, 'W'); s.hline(55, y + 19, 2, 'W')
        blue_strip(s, st, y + STRIP_DY + 0)
    def hurt_out(self, s, st):
        crack(s, [(31, 4), (30, 8), (32, 11), (30, 14)]); crack(s, [(9, 8), (10, 12), (8, 16)])
        s.stamp(46, 3, FLAP); wire(s, [(48, 6), (50, 8)])
        hurt_pair(s, st, (9, 18), (56, 3))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 4), (30, 8), (32, 11), (30, 14), (31, 17), (33, 22)], [(9, 8), (10, 12), (8, 16)]],
                 dents=[(7, 17, 6, 5), (50, 14, 6, 4)], soots=[(22, 3, 1), (44, 5, 0), (5, 8, 2)],
                 wires_=[[(56, 6), (58, 9), (57, 12)]], sparks=[(26, 8), (56, 4)], flap=(46, 3))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(34, y + 5), (35, y + 10), (33, y + 16), (35, y + 22)]); s.put(34, y + 23, 'c'); s.put(34, y + 24 + st.i, 'b')
        hurt_pair(s, st, (28, y + 8), (54, y + 14))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(26, y + 5), (25, y + 10), (27, y + 16), (25, y + 22)]); crack(s, [(41, y + 6), (43, y + 12)]); wire(s, [(14, y + 19), (16, y + 22), (19, y + 23)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, live_rgb=(60, 242, 255))
        n = {'charge': i, 'on': 5, 'damaged': 4}.get(state, 0)
        if state == 'fire' and i == 0: n = 5
        for k in range(4):
            if n: glow(g, ox + 19.5 + 8 * k, oy + y + 22 - round(n / 5 * 16) / 2, 8, CYAN, 0.1 + 0.05 * n, 2.0)
        glow(g, ox + 12, oy + y + 14, 3, CYAN, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 3.5, oy + 14, 4, CYAN, 0.5, 2.0)
        glow(g, ox + 55.5, oy + 19.5, 3, CYAN, 0.45, 2.0)
        for cx in (7, 10, 13): glow(g, ox + cx, oy + 14.5, 4, BLUE, 0.3, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        breech(b, 9, 15)
        bev(b, 12 + o, 1, 10, 17, 'M', 'S', 'W')                                      # rail coupling
        for ry in (2, 12):                                                           # the twin rails
            cylh(b, 22 + o, ry, 34, 5, 'LMSWE')
            for bx in range(26, 52, 9): bev(b, bx + o, ry - 1, 3, 7, 'L', 'M', 'S', cham=False); b.put(bx + 1 + o, ry + 2, 'b')
            bev(b, 52 + o, ry - 1, 6, 7, 'S', 'E', 'D')
        b.rect(24 + o, 7, 30, 5, 'D')
        for x in range(25, 53): b.put(x + o, 9, ('c' if st.fire else 'b') if x % 3 else ('H' if st.fire else 'c'))
        if st.state == 'disabled':
            for x in range(25, 53): b.put(x + o, 9, 'W')
    def bhurt(self, b, st):
        crack(b, [(32, 2), (33, 5), (31, 7)]); move(b, 52, 12, 6, 7, 1, 3); wire(b, [(51, 17), (53, 19)])
        spark(b, 56, 18, False) if st.i == 0 else spark(b, 32, 1, False)
    def bbreak(self, b, st):
        for y in (2, 4, 6): b.erase(38, y)
        return cleave(b, lambda y: 39, 2, 3, rows=(0, 9))
    def bwreck(self, b, st):
        wire(b, [(37, 4), (39, 6), (41, 7)]); crack(b, [(17, 3), (17, 8), (16, 12)])
    def bafter(self, b, st):
        if st.fire:
            stamp_flash(b, st, 59, 9, FLASH_R)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 59, 9, CYAN, WHITE, sx=1.6, scale=1.0)
        if state in ('idle', 'damaged'): glow(g, ox + 40, oy + 9.5, 6, CYAN, 0.2, 2.0, sx=3.5)

FLASH_R = [art("""
..cc..........
.cHHcc........
cHHHHHcc......
HHHHHHHHcc....
HHHHHHHHHHHcc.
HHHHHHHHHHHHHc
HHHHHHHHHHHcc.
HHHHHHHHcc....
cHHHHHcc......
.cHHcc........
..cc..........
"""), art("""
..c.........
.cHc........
cHHHcc......
HHHHHHcc....
HHHHHHHHHc..
HHHHHHcc....
cHHHcc......
.cHc........
..c.........
"""), art("""
.c.....
cHc....
HHHcc..
cHc....
.c.....
""")]
FLASH_S = [art("""
.oy.......
.yHyoo....
oyHHHyyo..
yHHHHHHyyo
oyHHHyyo..
.yHyoo....
.oy.......
"""), art("""
.o.......
oyyo.....
yHHyoo...
oyyo.....
.o.......
"""), art("""
.o....
oyo...
yHyo..
oyo...
.o....
""")]
FLAP = art("""
....SSM.
..SSMMS.
SSMMSS..
""")
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

# ============================================================ FLAK SCREEN (turret)
class FlakScreen(Std, Weapon):
    id = 'human_flak_screen'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 46, 27
    bpivot = (9, 13)
    bmuzzle = (33, 8)
    out_notes = ('OUTSIDE half of the Human Flak Screen (a TURRET): the Concord ring seat, a hopper of amber flak shells on the left, a radar console with a blue scope and a stencilled panel on the right. '
                 'damaged: ring cracked, cover flapping, sparks; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Human Flak Screen: a belt of amber flak shells in a feed channel; shells slide along the belt as it charges (frame 5 = belt full, strip green), power coupling, hatch. '
             'fire: the belt jerks and the strip flashes. damaged: the belt jammed with a crooked shell, lamps dead; disabled: the belt snapped, shells spilled. '
             'Barrel layer human_flak_screen_barrel: a round head with twin short flak barrels and a small radar dish on top; it shoots down missiles.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        turret_seat(s, 32, 15)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')                                           # left: shell hopper
        s.rect(6, 9, 10, 9, 'D'); s.hline(6, 9, 10, 'K')
        for k in range(3):
            for r in range(2): s.rect(7 + 3 * k, 10 + 4 * r, 2, 3, 'a'); s.put(7 + 3 * k, 10 + 4 * r, 'y'); s.put(8 + 3 * k, 12 + 4 * r, 'u')
        s.hline(5, 19, 12, 'W'); s.put(5, 20, 'o' if pw else 'E'); s.put(16, 20, 'o' if pw else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')                                          # right: radar console
        chamfer_fill(s, 47, 8, 12, 9, 'D', 3); rim(s, 'D', 'E', 'M', (47, 8, 58, 16))
        s.put(53, 12, 'c' if pw else 'E'); s.hline(51, 12, 5, 'b' if pw else 'W') if False else None
        for (dx, dy) in ((-3, 0), (3, 0), (0, -2), (0, 2)): s.put(53 + dx, 12 + dy, 'b' if pw else 'W')
        s.put(54 + i % 2, 11, 'g' if pw else 'E')
        s.rect(48, 18, 8, 3, 'J'); s.hline(48, 18, 8, 'j')
        stencil_h(s, 47, 22)
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        bev(s, 14, y + 8, 33, 11, 'W', 'E', 'D', cham=False)                           # the feed channel
        s.rect(15, y + 11, 31, 5, 'D'); s.hline(15, y + 11, 31, 'K'); s.hline(15, y + 15, 31, 'W')
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 0
        for k in range(6):
            if (k < n + (1 if n == 5 else 0) and pw) or (st.state == 'disabled' and k in (0, 2, 5)):
                x = 16 + 5 * k + (st.i % 2 if st.state == 'fire' else 0)
                s.rect(x, y + 11, 4, 4, 'a'); s.vline(x, y + 11, 4, 'y'); s.vline(x + 3, y + 11, 4, 'u'); s.put(x + 1, y + 11, 'o')
        hatch(s, 49, y + 8, st, 11, 9)
        blue_strip(s, st, y + STRIP_DY)
    def hurt_out(self, s, st):
        crack(s, [(28, 4), (29, 8), (27, 11), (28, 14)]); crack(s, [(50, 7), (52, 10), (50, 14)])
        s.stamp(2, 5, FLAP); wire(s, [(10, 6), (12, 7), (14, 7)])
        hurt_pair(s, st, (10, 4), (54, 8))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(28, 5), (29, 8), (27, 11), (28, 14), (30, 18), (29, 22)], [(50, 7), (52, 10), (50, 14)]],
                 dents=[(6, 17, 5, 5), (51, 18, 6, 4)], soots=[(21, 3, 2), (44, 6, 1), (4, 7, 0)],
                 wires_=[[(14, 6), (16, 9), (15, 12)]], sparks=[(35, 5), (8, 11)], flap=(2, 5))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(25, y + 8), (27, y + 12), (25, y + 18)]); s.stamp(33, y + 12, art("QQq\nqQQ\n.nq"))
        hurt_pair(s, st, (38, y + 9), (52, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(22, y + 8), (24, y + 13), (22, y + 18)]); crack(s, [(38, y + 8), (40, y + 14)]); wire(s, [(14, y + 19), (18, y + 23)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, live_rgb=(60, 242, 255))
        glow(g, ox + 12, oy + y + 14, 3, CYAN, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 53, oy + 12, 6, BLUE, 0.3, 2.0)
        glow(g, ox + 10, oy + 20.5, 7, ORANGE, 0.2, 2.0, sx=1.5)
    def barrel(self, b, st):
        o = -st.rc
        hub(b, 13, 17)
        for ty in (7, 15):                                                           # twin short flak barrels
            cylh(b, 18 + o, ty, 13, 5, 'LMSWE'); b.vline(23 + o, ty - 1, 7, 'W'); b.vline(24 + o, ty - 1, 7, 'S')
            bev(b, 30 + o, ty - 1, 5, 7, 'S', 'E', 'D', cham=False)
            b.rect(33 + o, ty + 1, 2, 3, 'o' if st.fire else 'D')
        # the radar dish on top of the head
        circle(b, 8.5, 5.5, 3.6, 'M'); circle(b, 8.5, 5.5, 2.6, 'S'); b.put(7, 4, 'L'); b.put(8, 5, 'D')
        b.put(8, 1, 'c' if st.state in ('idle', 'fire') else 'W'); b.vline(8, 1, 3, 'S')
        b.hline(12, 23, 6, 'J'); b.put(13, 24, 'b' if st.state != 'disabled' else 'W')
    def bhurt(self, b, st):
        crack(b, [(5, 12), (8, 16), (7, 20)]); move(b, 30, 15, 6, 7, 0, 2)
        spark(b, 35, 6, False) if st.i == 0 else spark(b, 8, 2, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 28, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(5, 12), (8, 16), (7, 21)], 'K', 'S'); wire(b, [(25, 9), (27, 11)])
    def bafter(self, b, st):
        if st.fire:
            for ty in (9, 17): stamp_flash(b, st, 36, ty, FLASH_S)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            for ty in (9, 17): fire_glow(g, ox, oy, i, 36, ty, scale=0.5)
        if state in ('idle',): glow(g, ox + 8.5, oy + 1.5, 3, CYAN, 0.45, 2.0)

WEAPONS = [VolleyRack, ConcordRailgun, FlakScreen]


# ================================================================== COMPONENTS
class ReactorPlus(LK.LComp):
    id = 'human_reactor_plus'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    PULSE = [6, 7, 8, 7]
    notes = ('Human "Standard Reactor Plus" (+1 power): the Concord Mk2 housing (corner capacitors with green lamps, four feed pipes, registry stencils) with a plus-shaped core: a cross of amber light in a dark octagon, '
             'breathing over 4 frames, and a lit "+" module with a blue stripe on the north edge. Damaged: a corner capacitor split and sparking, a pipe slipped its flange, the cross stutters. '
             'Disabled: the cross dark, the casing split corner to corner, the plus module blown out.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 61, 61, 'S', 8); rim(s, 'S', 'M', 'W')
        chamfer_fill(s, 5, 5, 53, 53, 'W', 7)
        for d in range(5, 58, 8): s.put(d, 31, 'E'); s.put(31, d, 'E')
        pipe_v(s, 29, 2, 13, (6, 11)); pipe_v(s, 29, 49, 13, (51, 56))
        LK.line(s, 3, 3, 3, 3, 'L') if False else None
        from comp_new import pipe_h as ph
        ph(s, 2, 29, 13, (6, 11)); ph(s, 49, 29, 13, (51, 56))
        for (bx, by) in ((6, 6), (46, 6), (6, 46), (46, 46)):
            bev(s, bx, by, 12, 12, 'M', 'S', 'W')
            s.rect(bx + 2, by + 7, 8, 1, 'D'); s.rect(bx + 2, by + 9, 8, 1, 'D')
            s.rect(bx + 3, by + 3, 2, 2, 'g' if on else 'E'); s.put(bx + 3, by + 3, 'H' if on else 'E')
            s.put(bx + 8, by + 3, 'L'); s.put(bx + 8, by + 4, 'S')
        chamfer_fill(s, 16, 16, 32, 32, 'M', 9); rim(s, 'M', 'L', 'S', (16, 16, 47, 47))
        chamfer_fill(s, 19, 19, 26, 26, 'E', 7)
        chamfer_fill(s, 21, 21, 22, 22, 'D', 6)
        for (x, y) in ((31, 17), (32, 17), (31, 46), (32, 46), (17, 31), (17, 32), (46, 31), (46, 32)): s.put(x, y, 'H' if (x + y) % 2 else 'L')
        if on:                                                                       # the plus: a cross of light
            w = self.PULSE[i]
            for (x0, y0, x1, y1) in ((32 - w, 30, 32 + w, 33), (30, 32 - w, 33, 32 + w)):
                s.rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1, 'o')
            for (x0, y0, x1, y1) in ((32 - w + 1, 31, 32 + w - 1, 32), (31, 32 - w + 1, 32, 32 + w - 1)):
                s.rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1, 'y')
            s.rect(30, 30, 4, 4, 'o'); s.rect(31, 31, 2, 2, 'H')
        else:
            for (x0, y0, x1, y1) in ((26, 30, 37, 33), (30, 26, 33, 37)): s.rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1, 'E')
            s.put(27, 31, 'W'); s.put(32, 28, 'W')
        # the plus module on the north edge
        bev(s, 25, 2, 14, 10, 'M', 'S', 'W'); s.rect(26, 9, 12, 1, 'J'); s.hline(26, 9, 12, 'j')
        for (x, y) in ((31, 4), (32, 4), (31, 5), (32, 5), (30, 5), (33, 5), (31, 6), (32, 6)): s.put(x, y, 'y' if on else 'W')
        s.put(31, 5, 'H' if on else 'W')
        stencil(s, 7, 14, 'L', 0); stencil(s, 55, 49, 'L', 1)
        s.hline(10, 60, 44, 'J') if False else None
        return s
    def hurt(self, s, i):
        bev(s, 46, 46, 12, 12, 'S', 'E', 'D')
        for (x, y) in ((47, 47), (48, 48), (49, 49), (50, 50), (51, 52), (52, 53), (53, 54), (54, 55)): s.put(x, y, 'K')
        s.rect(52, 46, 6, 4, 'D'); s.hline(52, 46, 6, 'K'); s.put(54, 48, 'r'); s.put(55, 47, 'a'); s.put(56, 48, 'a')
        for (x, y) in ((50, 49), (53, 51)): s.put(x, y, 'H' if i else 'y')
        s.put(58, 50 + i, 'y')
        s.rect(7, 29, 3, 6, '.'); s.rect(6, 31, 2, 5, 'q'); s.vline(6, 31, 5, 'Q')
        for (x, y) in ((8, 29), (9, 28), (9, 35), (8, 36)): s.put(x, y, 'L' if i else 'M')
        s.put(8, 37 + i, 'L')
        stamp_on(s, 38, 17, SCORCH_S)
        crack(s, [(10, 12), (12, 15), (11, 18)], 'L')
        if i == 1:
            for (x, y) in ((31, 31), (32, 31), (31, 32), (32, 32)): s.put(x, y, 'o')
    def wreck(self, s):
        crack(s, [(3, 11), (7, 14), (6, 18), (11, 21), (13, 26), (18, 28)])
        crack(s, [(46, 49), (50, 47), (53, 51), (57, 50), (60, 54)])
        bev(s, 46, 46, 12, 12, 'S', 'D', 'K'); s.rect(48, 48, 8, 8, 'K'); s.stamp(47, 47, SCORCH_L)
        bev(s, 25, 2, 14, 10, 'S', 'E', 'D'); stamp_on(s, 27, 3, SCORCH_S)
        s.stamp(36, 38, art("KKKK.\nKDDDK\n.KDKK")); stamp_on(s, 24, 38, SCORCH_S)
        s.stamp(6, 45, art("KKK\nKLL\nKLM")); s.put(8, 47, 'S')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.85)
        w = self.PULSE[i]
        glow(g, ox + 32, oy + 32, 22 + w, ORANGE, (0.3 + 0.025 * w) * k, 1.4)
        glow(g, ox + 32, oy + 32, 5 + w * 0.8, YEL, 0.55 * k, 1.6)
        glow(g, ox + 32, oy + 5.5, 6, YEL, 0.45 * k, 2.0)
        for (bx, by) in ((6, 6), (46, 6), (6, 46), (46, 46)):
            if flick is not None and (bx, by) == (46, 46): continue
            glow(g, ox + bx + 4, oy + by + 4, 5, GREEN, 0.5 * k, 2.0)
        if flick is not None: glow(g, ox + 55, oy + 49, 6, YEL, 0.5 if flick else 0.25, 2.0)

class CommsArray(LK.LComp):
    id = 'human_comms_array'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    DMG = (0, 1)
    notes = ('Human "Concord Comms Array": a steel console with a small dish on a pedestal (the feed horn blinks), a round radar scope with a green sweep that jumps a step each frame and a blip, and a navy stencilled panel '
             'with blue lamps. Damaged: the dish knocked askew, the scope glitching with a dead lamp, sparks. Disabled: the dish snapped, the scope dark and cracked.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        bev(s, 1, 1, 30, 30, 'M', 'S', 'W')
        s.hline(3, 2, 26, 'b' if on else 'W')
        # the dish
        circle(s, 9, 10, 6.5, 'W'); circle(s, 9, 10, 5.5, 'M'); circle(s, 9, 10, 3.5, 'L'); circle(s, 9, 10, 1.6, 'S'); s.put(8, 9, 'H')
        s.put(9, 10, 'E'); line(s, 9, 10, 14, 5, 'W'); s.put(14, 5, 'c' if on and i == 0 else ('L' if on else 'W')); s.put(15, 4, 'S')
        mat(s, 5, 17, 9, 4, ('M', 'S', 'W'), cham=False)
        # the radar scope
        circle(s, 23, 11, 6.5, 'W'); circle(s, 23, 11, 5.5, 'D')
        ring(s, 23, 11, 3, 3.8, 'E'); ring(s, 23, 11, 1, 1.6, 'E')
        if on:
            for (dx, dy) in ((0, -5), (4, -3), (5, 0), (4, 3), (0, 5), (-4, 3), (-5, 0), (-4, -3))[(i * 3) % 8:(i * 3) % 8 + 1]:
                line(s, 23, 11, 23 + dx, 11 + dy, 'g')
            s.put(26, 8 + i, 'H'); s.put(20, 13, 'g')
        s.put(23, 11, 'E')
        # lamp panel
        s.rect(4, 23, 24, 6, 'J'); s.hline(4, 23, 24, 'j'); s.hline(4, 28, 24, 'I')
        for k in range(5): s.rect(6 + 4 * k, 25, 2, 2, ('b', 'c', 'g', 'b', 'a')[k] if on and (k + i) % 3 else 'E')
        return s
    def hurt(self, s, i):
        s.rect(2, 3, 14, 14, '.') if False else None
        move(s, 3, 3, 14, 14, 1, 2 + i); crack(s, [(9, 6), (11, 10), (9, 14)], 'K')
        crack(s, [(21, 7), (24, 11), (22, 15)], 'K'); s.rect(14, 25, 2, 2, 'E')
        spark(s, 14, 5, False) if i == 0 else spark(s, 24, 10, False)
    def wreck(self, s):
        crack(s, [(9, 6), (11, 10), (9, 14)], 'K'); crack(s, [(21, 7), (24, 11), (22, 15)], 'K'); crack(s, [(3, 22), (9, 26)], 'K')
        s.stamp(11, 4, art("KK.\nKLK\n.KK")); s.stamp(13, 19, art("KKK\nKMK\n.KK"))
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.6 if flick else 0.9)
        if state == 'on':
            glow(g, ox + 14.5, oy + 5.5, 3.5, CYAN, (0.55 if i == 0 else 0.15) * k, 2.0)
            glow(g, ox + 23, oy + 11, 7, GREEN, 0.3 * k, 2.0)
        for q, c in enumerate((BLUE, CYAN, GREEN, BLUE, AMBER)): glow(g, ox + 7 + 4 * q, oy + 26, 3, c, 0.3 * k, 2.0)

class CrewQuartersDeluxe(LK.LComp):
    id = 'human_crew_quarters_deluxe'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 2, 2), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    DMG = (0, 1)
    notes = ('Human "Crew Quarters Deluxe" (a bed: heals x2): a made bunk seen from above with a white pillow at the head and a navy Concord blanket with a blue stripe, a bedside table with a warm amber lamp, '
             'and a small vitals monitor whose green line blips on the 2-frame loop. Damaged: the monitor cracked and flickering, the lamp dead, the blanket torn, sparks. Disabled: the lamp and monitor dark, the blanket slumped, the frame cracked.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        bev(s, 1, 1, 30, 30, 'M', 'S', 'W')                                           # the cabin tile
        bev(s, 3, 3, 17, 26, 'S', 'W', 'E')                                           # the bed frame
        bev(s, 5, 5, 13, 8, 'H', 'L', 'M'); s.hline(6, 6, 11, 'H')                      # the pillow
        s.rect(5, 14, 13, 13, 'J'); s.hline(5, 14, 13, 'j'); s.vline(5, 14, 13, 'j'); s.hline(5, 26, 13, 'I'); s.vline(17, 14, 13, 'I')
        s.hline(6, 17, 11, 'b'); s.hline(6, 18, 11, 'c' if on else 'b')                 # the blue stripe
        for (x, y) in ((8, 21), (13, 23), (10, 25)): s.put(x, y, 'j')
        bev(s, 22, 4, 7, 8, 'M', 'S', 'W')                                            # the bedside table
        s.rect(24, 6, 3, 3, 'a' if on else 'E'); s.put(24, 6, 'y' if on else 'W'); s.hline(23, 5, 5, 'M')
        bev(s, 22, 15, 7, 12, 'W', 'E', 'D')                                          # the vitals monitor
        s.rect(23, 17, 5, 6, 'D'); s.hline(23, 17, 5, 'K')
        if on:
            blip = [(23, 21), (24, 21), (25, 19), (26, 22), (27, 21)] if i == 0 else [(23, 21), (24, 20), (25, 21), (26, 18), (27, 21)]
            for (x, y) in blip: s.put(x, y, 'g')
            s.put(27, 25, 'g')
        else: s.hline(23, 20, 5, 'W')
        return s
    def hurt(self, s, i):
        crack(s, [(23, 17), (25, 20), (24, 22)], 'K'); s.rect(24, 6, 3, 3, 'E')
        s.stamp(8, 19, art("KKK.\nK.JK\n.KKJ")); s.put(12, 22, 'K')
        spark(s, 26, 16 if i == 0 else 7, False)
    def wreck(self, s):
        crack(s, [(23, 17), (25, 20), (24, 22)], 'K'); crack(s, [(4, 4), (10, 9), (14, 12)], 'K')
        s.stamp(8, 19, art("KKK.\nK.JK\n.KKJ")); s.stamp(23, 5, art("KK.\nKMK"))
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.6 if flick else 0.9)
        if state == 'on':
            glow(g, ox + 25.5, oy + 7.5, 7, AMBER, 0.45 * k, 1.8)
            glow(g, ox + 25, oy + 20, 5, GREEN, 0.3 * k, 2.0)
            glow(g, ox + 11, oy + 18.5, 8, CYAN, 0.12 * k, 2.0, sx=1.4)

COMPONENTS = [ReactorPlus, CommsArray, CrewQuartersDeluxe]

# ================================================================== PROJECTILES AND IMPACTS (clean tracers, Concord rail flashes)
def _vmissile():
    out = []
    for k in range(3):
        s = Spr(5, 14)
        s.stamp(0, 0, art("""
..r..
.rrr.
.MLM.
.MSM.
.MSM.
.MSW.
MWSWW
.WWW.
"""))
        ex = [("..y..", ".yHy.", "..o..", "..r.."), (".yHy.", "..o..", "..o..", "...r."), ("..y..", ".yoy.", "..r..", "..r..")][k]
        for j, row in enumerate(ex):
            for i, c in enumerate(row):
                if c != '.': s.put(i, 8 + j, c)
        out.append(s)
    return out

def _vmissile_impact():
    f = []
    s = Spr(16, 16); disc(s, 8, 8, 5, 'o'); disc(s, 8, 8, 3.5, 'y'); disc(s, 8, 8, 1.8, 'H'); rays(s, 8, 8, 8, 5, 7, 'yo', 0.2)
    f.append(s)
    s = Spr(16, 16); disc(s, 8, 8, 4, 'o'); disc(s, 8, 8, 2.2, 'y'); rays(s, 8, 8, 8, 5, 7, 'o', 0.0); dots(s, 8, 8, 6, 8, 'y', 0.3); dots(s, 8, 8, 5, 6, 'L', 0.1)
    f.append(s)
    s = Spr(16, 16); disc(s, 8, 8, 2.5, 'r'); ring(s, 8, 8, 4, 5.4, 'L'); dots(s, 8, 8, 7, 8, 'o', 0.2)
    f.append(s)
    s = Spr(16, 16); ring(s, 8, 8, 5, 6.3, 'M'); dots(s, 8, 8, 3, 4, 'r', 0.3); dots(s, 8, 8, 7, 5, 'L', 0.5)
    f.append(s)
    return f

def _rail():
    out = []
    for k in range(3):
        s = Spr(5, 22)
        for y in range(0, 9): s.put(2, y, 'H'); s.put(1, y, 'c' if y < 7 else 'b'); s.put(3, y, 'c' if y < 7 else 'b')
        s.put(2, 0, 'H'); s.put(1, 0, '.'); s.put(3, 0, '.')
        for y in range(9, 22):
            t = y - 9
            if t < 6 or (t + k) % 3 != 0: s.put(2, y, 'c' if t < 5 else 'b')
        for y in range(9, 18): 
            if (y + 2 * k) % 4 == 0: s.put(1, y, 'b'); s.put(3, y, 'b')
        out.append(s)
    return out

def _rail_impact():
    f = []
    s = Spr(20, 20); disc(s, 10, 10, 4, 'H'); rays(s, 10, 10, 4, 4, 9, 'Hcc', 0.0); rays(s, 10, 10, 4, 4, 9, 'Hcc', math.pi / 4); ring(s, 10, 10, 6, 7, 'c')
    f.append(s)
    s = Spr(20, 20); disc(s, 10, 10, 2.5, 'H'); ring(s, 10, 10, 6.5, 7.8, 'c'); ring(s, 10, 10, 8.2, 9.2, 'b'); rays(s, 10, 10, 4, 3, 8, 'cb', 0.0); dots(s, 10, 10, 5, 8, 'H', 0.2)
    f.append(s)
    s = Spr(20, 20); disc(s, 10, 10, 1.5, 'c'); ring(s, 10, 10, 8.5, 9.5, 'b'); dots(s, 10, 10, 6, 8, 'c', 0.1); dots(s, 10, 10, 4, 4, 'H', 0.4)
    f.append(s)
    s = Spr(20, 20); dots(s, 10, 10, 8, 8, 'b', 0.2); dots(s, 10, 10, 5, 4, 'c', 0.6)
    f.append(s)
    return f

def _flak_shell():
    out = []
    for k in range(2):
        s = Spr(4, 10)
        s.stamp(0, 0, art("""
.yy.
yHHy
yHHy
.ay.
.aa.
"""))
        ex = [(".o..", ".r..", "...."), ("..o.", "..r.", "..r.")][k]
        for j, row in enumerate(ex):
            for i, c in enumerate(row):
                if c != '.': s.put(i, 5 + j, c)
        s.put(1 + k, 8 + k, 'y')
        out.append(s)
    return out

def _flak_impact():
    f = []
    s = Spr(16, 16); disc(s, 8, 8, 5, 'L'); disc(s, 8, 8, 3.8, 'H'); disc(s, 8, 8, 2, 'y'); rays(s, 8, 8, 10, 5, 7, 'yo', 0.1)
    f.append(s)
    s = Spr(16, 16); ring(s, 8, 8, 4, 6.2, 'L'); ring(s, 8, 8, 2, 4, 'M'); disc(s, 8, 8, 2, 'o'); rays(s, 8, 8, 10, 6, 7, 'o', 0.1); dots(s, 8, 8, 7, 10, 'y', 0.4)
    f.append(s)
    s = Spr(16, 16); ring(s, 8, 8, 5, 7, 'M'); ring(s, 8, 8, 6.2, 7.2, 'S'); dots(s, 8, 8, 4, 5, 'o', 0.3); dots(s, 8, 8, 7, 8, 'L', 0.1, 2)
    f.append(s)
    s = Spr(16, 16); ring(s, 8, 8, 6.2, 7.5, 'S'); dots(s, 8, 8, 7, 8, 'M', 0.2, 2)
    f.append(s)
    return f

PROJECTILES = [
    Proj('human_volley_rack', _vmissile(), _vmissile_impact(), (2, 0), (2, 11), fps=14, ifps=14, pad=4, ipad=4, bands=((1.5, 100), (3.2, 48)),
         notes='A small missile, 5x14: steel body, red ogive, small tail fins and a 3-frame exhaust. Three leave per salvo.',
         inotes='A compact blast: a bright disc, sparks, a smoke ring, a thin settling ring (4 frames, 16x16).'),
    Proj('human_concord_railgun', _rail(), _rail_impact(), (2, 0), (2, 21), fps=16, ifps=16, pad=5, ipad=5, bands=((1.5, 110), (3.2, 56), (5.0, 24)),
         notes='A rail slug: a white-hot 9 px head with a cyan sheath and a long blue-white streak behind it (3 frames, the streak shimmers). 22 long; fast and thin: it pierces 2.',
         inotes='A Concord rail flash: a white core with a cross of cyan rays and a blue shock ring that grows and thins (4 frames, 20x20). Play it on every pierce.'),
    Proj('human_flak_screen', _flak_shell(), _flak_impact(), (2, 1), (2, 9), fps=14, ifps=14, pad=3, ipad=4, bands=((1.5, 100), (3.2, 48)),
         notes='A flak tracer, 4x10: a bright amber shell with a short ember tail (2 frames). Fired at incoming missiles within 300 px.',
         inotes='A flak burst: a white-yellow puff with a grey smoke ring and flung sparks, thinning to a faint ring (4 frames, 16x16).'),
]
