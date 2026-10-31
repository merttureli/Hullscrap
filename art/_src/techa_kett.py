"""Kett tech (docs/waves/racial_tech_1.md): chitin plates, hive cells, drone bays. Amber chitin (y/a/u, seams n, joints q/Q) like the Kett crew, overlapping rounded plates
with dark seams, honeycomb cells (7x5 hexes, lit yellow or green), round drone bays with a tiny drone inside, dark glossy compound-eye lamps (r/n). No steel: it is grown.
Weapons: kett_hive_swarm_launcher, kett_chitin_thrower, kett_drone_picket. Components: kett_hive_battery (shield), kett_nest_reactor (reactor), kett_brood_hold (utility).
Projectile art: drone swarms, chitin needles."""
from techa_kit import *
from lines_shield import ShieldBase, seg_ring, BR

CH = ('y', 'a', 'u')                 # chitin plate: light, body, shade
CH_D = ('a', 'u', 'n')

def hexcell(s, x, y, fill='n', rim='u', hi=None, drone=False, lit=False):
    """a honeycomb cell, 7 wide x 5 tall; `fill` is its inside colour, `rim` the wall; a drone dot inside when asked."""
    rows = ("..RRR..", ".RFFFR.", "RFFFFFR", ".RFFFR.", "..RRR..")
    for j, r in enumerate(rows):
        for i, c in enumerate(r):
            if c == '.': continue
            s.put(x + i, y + j, rim if c == 'R' else fill)
    if hi: s.put(x + 2, y + 1, hi)
    if drone: s.put(x + 3, y + 2, 'L'); s.put(x + 2, y + 2, 'q'); s.put(x + 4, y + 2, 'q')

def honeycomb(s, x, y, cols, rows, fills, rim='u', pitch_x=6, pitch_y=4, drones=False):
    """cols x rows of cells, alternate columns dropped by half a pitch; fills(k, c, r) -> colour of the cell k."""
    k = 0
    for c in range(cols):
        for r in range(rows):
            cx = x + c * pitch_x; cy = y + r * pitch_y + (pitch_y // 2 if c % 2 else 0)
            hexcell(s, cx, cy, fills(k, c, r), rim)
            k += 1

def plate_k(s, x, y, w, h, tone=CH, seams=True):
    """an overlapping chitin plate: rounded, light top-left, dark seam under it."""
    mat(s, x, y, w, h, tone)
    if h > 5: s.hline(x + 1, y + h - 1, w - 2, 'n')
    if seams and w > 9: s.vline(x + w // 2, y + 2, h - 4, tone[2])

def eye_k(s, x, y, lit=True):
    """a compound-eye lamp: a dark glossy blob with a red glint."""
    s.rect(x, y, 4, 3, 'n'); s.put(x, y, 'q'); s.put(x + 1, y, 'q'); s.put(x + 2, y + 1, 'r' if lit else 'q'); s.put(x + 1, y + 1, 'D')

def drone(s, x, y, wings=0):
    """a tiny drone, 5 wide: body, two wings that beat (wings 0/1)."""
    s.put(x + 2, y, 'y'); s.put(x + 2, y + 1, 'a'); s.put(x + 2, y + 2, 'u')
    if wings: s.put(x, y, 'L'); s.put(x + 1, y, 'L'); s.put(x + 3, y, 'L'); s.put(x + 4, y, 'L')
    else: s.put(x, y + 1, 'L'); s.put(x + 1, y + 1, 'L'); s.put(x + 3, y + 1, 'L'); s.put(x + 4, y + 1, 'L')

class KettMount:
    """a chitin flange: amber with dark segment ticks."""
    def trim(self, s, st, half):
        fy = 1 if half == 'in' else s.h - 4
        s.rect(1, fy, 62, 4, 'a'); s.hline(1, fy, 62, 'y'); s.hline(1, fy + 3, 62, 'u')
        for x in range(4, 62, 6): s.vline(x, fy + 1, 2, 'n')

def housing_k(s, y0):
    mat(s, 2, y0 + 1, 60, 30, CH_D)
    s.hline(3, y0 + 2, 58, 'a')
    for x in range(6, 60, 8): s.put(x, y0 + 29, 'n')

def cells_row(s, st, x, y, n=5, pitch=8):
    """the charge indicator: a row of hive cells that fill with light (yellow while charging, green when ready, white flash on the discharge)."""
    recess(s, x - 2, y - 2, n * pitch + 2, 8, 'n', 'K')
    for k in range(n):
        on = st.powered and k < st.lit
        if getattr(st, 'flash', False) and st.powered: f = 'H'
        elif on: f = 'g' if st.ready else 'y'
        else: f = 'D'
        hexcell(s, x + k * pitch, y - 1, f, 'u')

def cells_glow(g, ox, oy, state, i, x, y, n=5, pitch=8):
    lit = {'charge': i, 'on': 5, 'damaged': 3}.get(state, 0)
    rdy = state in ('on', 'damaged') or (state == 'charge' and i == 5)
    if state == 'damaged' and i == 1: rdy = False
    for k in range(lit): glow(g, ox + x + k * pitch + 3.5, oy + y + 1.5, 5, GREEN if rdy else YEL, 0.5, 2.0, sx=1.4)

def dead_cells_k(s, st, y, ks=(3, 4), x0=STRIP_X, pitch=8):
    for k in ks: hexcell(s, x0 + k * pitch, y - 1, 'D', 'n')
    s.put(x0 + ks[-1] * pitch + 3, y + 1, 'r')

# ============================================================ HIVE SWARM LAUNCHER
FLOWER = [(22, 7), (22, 17), (28, 2), (28, 12), (28, 22), (34, 7), (34, 17)]
class HiveSwarmLauncher(KettMount, Weapon):
    id = 'kett_hive_swarm_launcher'
    blen, bwid = 58, 29
    bpivot = (6, 14)
    bmuzzle = (40, 14)
    out_notes = ('OUTSIDE half of the Kett Hive Swarm Launcher: overlapping chitin plates round a honeycomb face of lit cells, a round brood sac on the left with drones crawling on it, and a pair of antennae and compound-eye lamps on the right. '
                 'damaged: a plate peeled back, two cells dark and leaking, sparks; disabled: plates cracked and grey, cells dead, the sac slumped.')
    notes = ('INSIDE half of the Kett Hive Swarm Launcher: a brood chamber of honeycomb cells that fill with drones as it charges (frame 5 = every cell holds a drone, strip green), power coupling, hatch. '
             'fire: the cells flash white and empty. damaged: cells cracked and dark, a plate hanging; disabled: cold grey cells, the chamber split. '
             'Barrel layer kett_hive_swarm_launcher_barrel: a flower of seven honeycomb cells, each with a drone in its mouth; fire: the cells flash and a cloud of drones leaves in a fan.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        mat(s, 6, 20, 52, 12, CH_D)
        plate_k(s, 19, 2, 26, 26); plate_k(s, 22, 1, 20, 8)
        s.rect(26, 2, 12, 6, 'D'); s.hline(26, 2, 12, 'K')
        mat(s, 18, 9, 28, 5, CH_D, cham=False); s.put(32, 12, 'L'); s.put(33, 13, 'W')
        honeycomb(s, 21, 15, 4, 2, lambda k, c, r: ('y' if (k + i) % 4 == 0 else 'o') if pw else 'n', 'u')    # the lit honeycomb face
        plate_k(s, 3, 8, 16, 16)                                                   # left: brood sac
        circle(s, 11, 16, 6, 'u'); circle(s, 11, 16, 5, 'a'); circle(s, 11, 16, 3, 'y'); s.put(9, 14, 'H')
        for (x, y) in ((6, 20), (14, 21)): drone(s, x, y, (i + x) % 2)
        plate_k(s, 45, 6, 16, 18)                                                  # right: antennae and eyes
        eye_k(s, 47, 14, pw); eye_k(s, 54, 14, pw)
        line(s, 48, 12, 46, 3, 'u'); line(s, 56, 12, 59, 3, 'u'); s.put(46, 2, 'y' if pw and i == 0 else 'n'); s.put(59, 2, 'y' if pw and i == 1 else 'n')
        s.hline(47, 20, 3, 'n'); s.hline(51, 20, 2, 'n'); s.hline(54, 20, 3, 'n')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing_k(s, y)
        cable_stub(s, 3, y + 8, st, 'y', CH_D)
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 0
        mat(s, 14, y + 4, 33, 17, ('n', 'D', 'K'), cham=False)
        k = 0
        for c in range(5):
            for r in range(3):
                cx = 16 + c * 6; cy = y + 5 + r * 5 + (2 if c % 2 else 0)
                if cy + 5 > y + 21: continue
                filled = k < n * 2 + (1 if n == 5 else 0) and pw
                if st.state == 'fire' and st.i == 0: f = 'H'
                elif filled: f = 'y'
                else: f = 'D'
                hexcell(s, cx, cy, f, 'u', drone=filled and st.state != 'fire')
                k += 1
        hatch_k(s, 49, y + 6, CH_D, 11, 9, 'y')
        cells_row(s, st, STRIP_X, y + STRIP_DY)
    def hurt_out(self, s, st):
        move(s, 46, 8, 14, 6, 2, -1); s.rect(48, 9, 4, 2, 'n')
        for (x, y) in ((21, 15), (22, 16), (27, 17), (28, 18)): hexcell(s, x - 1, y - 1, 'D', 'n') if (x, y) == (21, 15) or (x, y) == (27, 17) else None
        crack(s, [(31, 4), (30, 8), (32, 11)]); s.put(11, 20, 'o' if st.i else 'y')
        hurt_pair(s, st, (9, 6), (53, 22))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 3), (30, 8), (32, 12), (30, 17), (31, 22)], [(8, 9), (10, 14), (9, 19)]],
                 dents=[(6, 20, 6, 4), (49, 18, 6, 3)], soots=[(22, 3, 1), (45, 6, 0), (4, 8, 2)],
                 wires_=[[(50, 6), (52, 9), (51, 12)]], sparks=[(35, 6), (9, 12)])
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells_k(s, st, y + STRIP_DY)
        crack(s, [(22, y + 5), (24, y + 10), (22, y + 16)]); s.stamp(33, y + 12, art("qQQ\nQqQ\n.nq"))
        hurt_pair(s, st, (40, y + 8), (52, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(22, y + 5), (24, y + 10), (22, y + 16)]); crack(s, [(36, y + 6), (38, y + 12)])
        s.stamp(40, y + 22, art(".KK.\nKqQK\nKnqK\n.KK.")); wire(s, [(14, y + 18), (18, y + 21)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        cells_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        n = {'charge': i, 'on': 5, 'damaged': 4}.get(state, 0)
        if state == 'fire' and i == 0: n = 5
        if n: glow(g, ox + 30, oy + y + 12, 14, YEL, 0.08 + 0.04 * n, 1.8, sx=1.5)
        glow(g, ox + 12, oy + y + 14, 3, YEL, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 33, oy + 17, 10, ORANGE, 0.28, 1.8, sx=1.4)
        glow(g, ox + 11, oy + 16, 6, YEL, 0.25, 2.0)
        glow(g, ox + 49, oy + 15, 3, RED, 0.35, 2.0); glow(g, ox + 56, oy + 15, 3, RED, 0.35, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        mat(b, 1, 4, 11, 21, CH)                                                   # breech: a grown chitin knob
        b.rect(3, 12, 5, 5, 'n'); b.put(5, 14, 'y'); b.put(6, 15, 'u')
        for bx in (12, 14): b.vline(bx + 0, 3, 23, 'u' if bx == 14 else 'a')
        mat(b, 15 + o, 1, 22, 27, CH_D)
        for (cx, cy) in FLOWER:
            fill = 'H' if st.fire else ('D' if st.state != 'disabled' else 'W')
            hexcell(b, cx + o, cy, fill, 'u' if st.state != 'disabled' else 'W')
            if not st.fire and st.state != 'disabled': b.put(cx + o + 4, cy + 2, 'y'); b.put(cx + o + 3, cy + 2, 'L')
        for (x, y) in ((17, 3), (17, 24), (35, 3), (35, 24)): b.put(x + o, y, 'y')
    def bhurt(self, b, st):
        hexcell(b, 28 + o if False else 28, 2, 'D', 'n'); hexcell(b, 34, 17, 'n', 'n')
        crack(b, [(20, 4), (22, 9), (21, 14)]); move(b, 15, 22, 8, 5, 0, 2)
        spark(b, 36, 3, False) if st.i == 0 else spark(b, 20, 20, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 27, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(19, 4), (21, 9), (20, 14), (22, 20)], 'K', 'S'); wire(b, [(33, 12), (36, 14)])
    def bafter(self, b, st):
        if st.fire:
            for k, (dx, dy) in enumerate(((3, 0), (5, -4), (5, 4), (8, -7), (8, 0), (8, 7), (11, -3), (11, 3), (12, 10), (12, -10))):
                if k < 4 + st.i * 3 + 3 - st.i: drone(b, 41 + dx * (1 + st.i // 2) - st.rc + (st.i == 2) * 2, 14 + dy - 1, (k + st.i) % 2)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            glow(g, ox + 40, oy + 14.5, (14, 12, 9)[i], YEL, (0.5, 0.4, 0.3)[i], 1.8, sx=1.3)
        if state in ('idle', 'damaged'):
            for (cx, cy) in FLOWER: glow(g, ox + cx + 3.5, oy + cy + 2.5, 4, YEL, 0.25, 2.0)

# ============================================================ CHITIN THROWER
class ChitinThrower(KettMount, Weapon):
    id = 'kett_chitin_thrower'
    blen, bwid = 58, 23
    bpivot = (6, 11)
    bmuzzle = (42, 11)
    out_notes = ('OUTSIDE half of the Kett Chitin Thrower: a plated block with a quiver of spare spines on the left, and two operator crank-levers with grips (it needs two Kett to work it) and an eye lamp on the right. '
                 'damaged: a lever bent, the quiver split with spines spilling, sparks; disabled: plates cracked and grey, a lever snapped, sparking.')
    notes = ('INSIDE half of the Kett Chitin Thrower: a magazine of spines racked like a comb; the racks fill with amber spines as it charges (frame 5 = full, cells green), two crank stations, power coupling, hatch. '
             'fire: the magazine flashes and empties. damaged: the comb cracked, a spine jammed crooked, cells dead; disabled: spines scattered, the comb split. '
             'Barrel layer kett_chitin_thrower_barrel: a grown chitin horn flaring into a spined mouth with two grips; fire: a cone of needles leaves it.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        mat(s, 6, 20, 52, 12, CH_D)
        plate_k(s, 19, 2, 26, 26); plate_k(s, 22, 1, 20, 8)
        s.rect(26, 2, 12, 6, 'D'); s.hline(26, 2, 12, 'K')
        mat(s, 18, 9, 28, 5, CH_D, cham=False); s.put(32, 12, 'L'); s.put(33, 13, 'W')
        for (x, y) in ((22, 14), (41, 14)): s.put(x, y, 'y')
        plate_k(s, 3, 7, 16, 17)                                                   # left: the quiver of spare spines
        for k in range(6):
            s.vline(5 + 2 * k, 5 - (k % 2), 14, 'Q' if k % 2 else 'y'); s.put(5 + 2 * k, 4 - (k % 2), 'H')
        s.rect(4, 16, 14, 3, 'n'); s.hline(4, 16, 14, 'u'); s.hline(4, 19, 14, 'u')
        plate_k(s, 45, 6, 16, 18)                                                  # right: the two crank levers and an eye
        for lx in (48, 55):
            s.rect(lx, 9, 2, 8, 'u'); s.vline(lx, 9, 8, 'a'); s.rect(lx - 1, 7, 4, 2, 'Q'); s.hline(lx - 1, 7, 4, 'y')
        eye_k(s, 50, 18, pw)
        s.hline(47, 22, 3, 'n'); s.hline(53, 22, 3, 'n')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing_k(s, y)
        cable_stub(s, 3, y + 8, st, 'y', CH_D)
        mat(s, 14, y + 4, 33, 17, ('n', 'D', 'K'), cham=False)
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 0
        for k in range(10):
            x = 16 + 3 * k
            full = k < n * 2 and pw
            s.vline(x, y + 6, 13, 'D')
            if full: s.vline(x, y + 7, 11, 'y' if k % 2 else 'Q'); s.put(x, y + 6, 'H'); s.put(x, y + 18, 'u')
            elif st.state == 'disabled' and k in (2, 5, 7): s.vline(x + 1, y + 12, 6, 'q')
        if st.state == 'fire' and st.i == 0: s.rect(15, y + 5, 31, 15, 'L')
        mat(s, 49, y + 4, 11, 6, CH); s.vline(53, y + 2, 4, 'a'); s.vline(57, y + 2, 4, 'a')        # two crank stations
        hatch_k(s, 49, y + 12, CH_D, 11, 8, 'y')
        cells_row(s, st, STRIP_X, y + STRIP_DY)
    def hurt_out(self, s, st):
        move(s, 54, 6, 5, 11, 2, 2); s.put(57, 8, 'K')
        for k in range(3): s.put(10 + 3 * k, 18 + k, 'Q'); s.put(10 + 3 * k, 19 + k, 'q')
        s.stamp(4, 4, art("KKK.\nKQQK\n.KnK")) if False else None
        crack(s, [(31, 4), (30, 8), (32, 11)]); crack(s, [(7, 8), (9, 14)])
        hurt_pair(s, st, (9, 4), (53, 22))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 3), (30, 8), (32, 12), (30, 17), (31, 22)], [(8, 9), (10, 14), (9, 19)]],
                 dents=[(6, 20, 6, 4), (49, 20, 6, 3)], soots=[(22, 3, 1), (45, 6, 0), (4, 8, 2)],
                 wires_=[[(50, 6), (52, 9), (51, 12)]], sparks=[(35, 6), (9, 12)])
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells_k(s, st, y + STRIP_DY)
        crack(s, [(25, y + 5), (27, y + 10), (25, y + 16)]); s.stamp(36, y + 12, art(".y\ny."))
        hurt_pair(s, st, (40, y + 8), (52, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(25, y + 5), (27, y + 10), (25, y + 16)]); crack(s, [(38, y + 6), (40, y + 12)]); wire(s, [(14, y + 18), (18, y + 21)]); s.stamp(40, y + 22, art(".KK.\nKqQK\nKnqK\n.KK."))
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        cells_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        n = {'charge': i, 'on': 5, 'damaged': 4}.get(state, 0)
        if state == 'fire' and i == 0: n = 5
        if n: glow(g, ox + 30, oy + y + 12, 14, YEL, 0.05 + 0.04 * n, 1.8, sx=1.5)
        glow(g, ox + 12, oy + y + 14, 3, YEL, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 52, oy + 19, 3, RED, 0.35, 2.0)
        for k in range(6): glow(g, ox + 6 + 2 * k, oy + 5, 2.5, YEL, 0.25, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        mat(b, 1, 3, 11, 17, CH); b.rect(3, 8, 5, 5, 'n'); b.put(5, 10, 'y')
        b.vline(12, 2, 19, 'u'); b.vline(13, 2, 19, 'n')
        cylh(b, 14 + o, 6, 16, 11, 'yyaaauun')                                      # the horn tube
        for bx in (19, 25): b.vline(bx + o, 5, 13, 'u'); b.vline(bx + 1 + o, 5, 13, 'n')
        for (x0, x1, y0, y1) in ((30, 33, 4, 18), (34, 37, 2, 20), (38, 43, 0, 22)): cylh(b, x0 + o, y0, x1 - x0 + 1, y1 - y0 + 1, 'yyaaauun')   # the flared mouth
        b.rect(40 + o, 3, 4, 17, 'n')
        for k in range(4): b.put(41 + o, 5 + 4 * k, 'y' if not st.fire else 'H')                    # spine tips inside the mouth
        for (x, y) in ((22, 5), (28, 4), (33, 3), (38, 1), (22, 18), (28, 19), (33, 20), (38, 22)): b.put(x + o, y, 'Q'); b.put(x + o, y - 1 if y < 11 else y + 1, 'H')   # spikes on the horn
        for (gy, gx) in ((0, 20), (22, 20)): b.rect(gx + o, gy, 4, 1, 'Q')                                   # the two operator grips
    def bhurt(self, b, st):
        crack(b, [(22, 6), (23, 11), (22, 16)]); move(b, 34, 2, 10, 19, 0, 2)
        spark(b, 43, 1, False) if st.i == 0 else spark(b, 24, 4, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 32, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(21, 6), (23, 11), (21, 16)], 'K', 'S'); wire(b, [(27, 8), (30, 10)])
    def bafter(self, b, st):
        if st.fire:
            for k in range(5):
                x0 = 44 - st.rc + st.i * 2
                for j in range(2 + st.i): b.put(x0 + j * 2, 11 + (k - 2) * (2 + st.i * 2) + (j % 2 if False else 0), 'H' if j == 1 else 'y')
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': glow(g, ox + 46, oy + 11.5, (13, 10, 7)[i], YEL, (0.5, 0.4, 0.3)[i], 1.8, sx=1.3)
        if state == 'idle': glow(g, ox + 41, oy + 11.5, 5, YEL, 0.25, 2.0)

# ============================================================ DRONE PICKET (turret)
class DronePicket(KettMount, Weapon):
    id = 'kett_drone_picket'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 40, 27
    bpivot = (13, 13)
    bmuzzle = (30, 13)
    out_notes = ('OUTSIDE half of the Kett Drone Picket (a TURRET): a plated ring seat, two drone bays on the left (round hatches with a drone dozing in each) and an eye lamp with antennae on the right. '
                 'damaged: a bay door hanging, an antenna bent, sparks; disabled: plates cracked and grey, a bay dark, sparking.')
    notes = ('INSIDE half of the Kett Drone Picket: a rack of five drone cells; each drone wakes and lights up as it charges (frame 5 = five awake, cells green), power coupling, hatch. '
             'fire: the cells flash and the drones are gone. damaged: a cell cracked and dark, a drone stuck half out; disabled: drones dead and grey. '
             'Barrel layer kett_drone_picket_barrel: a round chitin dome with two open drone bays, compound-eye blobs on the front and a launch slit; fire: the drones leave the bays.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        mat(s, 6, 19, 52, 13, CH_D)
        plate_k(s, 18, 2, 28, 24)
        turret_ring(s, 32, 15, 25, 'y', 'a', 'u', 'n')
        for (x, y) in ((32, 4), (32, 26), (20, 15), (44, 15)): s.put(x, y, 'H')
        plate_k(s, 3, 6, 16, 18)                                                   # left: two drone bays
        for by in (8, 16):
            circle(s, 11, by + 3, 4.2, 'n'); ring(s, 11, by + 3, 3.4, 4.6, 'u'); drone(s, 9, by + 2, (i + by) % 2) if pw else None
        plate_k(s, 45, 6, 16, 18)                                                  # right: eye and antennae
        eye_k(s, 49, 14, pw); eye_k(s, 55, 14, pw)
        line(s, 50, 12, 47, 3, 'u'); line(s, 57, 12, 59, 2, 'u'); s.put(47, 2, 'y' if pw and i == 0 else 'n'); s.put(59, 1, 'y' if pw and i == 1 else 'n')
        s.hline(47, 20, 3, 'n'); s.hline(52, 20, 2, 'n')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing_k(s, y)
        cable_stub(s, 3, y + 8, st, 'y', CH_D)
        mat(s, 14, y + 5, 33, 15, ('n', 'D', 'K'), cham=False)
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 0
        for k in range(5):
            x = 16 + 6 * k
            circle(s, x + 2.5, y + 12.5, 2.9, 'n'); ring(s, x + 2.5, y + 12.5, 2.2, 3.3, 'u')
            awake = k < n and pw
            if awake: drone(s, x, y + 11, (k + st.i) % 2); s.put(x + 2, y + 10, 'g' if st.ready else 'y')
            elif st.state == 'disabled' and k in (1, 3): drone(s, x, y + 11, 0); s.put(x + 2, y + 11, 'q')
        if st.state == 'fire' and st.i == 0: s.rect(15, y + 6, 31, 13, 'L')
        hatch_k(s, 49, y + 8, CH_D, 11, 9, 'y')
        cells_row(s, st, STRIP_X, y + STRIP_DY)
    def hurt_out(self, s, st):
        move(s, 4, 15, 14, 8, 1, 2); s.put(8, 22, 'o' if st.i else 'y')
        s.put(59, 1, 'K'); move(s, 56, 2, 5, 9, 1, 1)
        crack(s, [(31, 3), (30, 7), (32, 10)]); crack(s, [(52, 8), (54, 12)])
        hurt_pair(s, st, (9, 4), (53, 22))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 3), (30, 8), (32, 12), (30, 17), (31, 22)], [(8, 9), (10, 14), (9, 19)]],
                 dents=[(6, 19, 6, 4), (49, 20, 6, 3)], soots=[(22, 3, 1), (45, 6, 0), (4, 8, 2)],
                 wires_=[[(50, 6), (52, 9), (51, 12)]], sparks=[(35, 6), (9, 12)])
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells_k(s, st, y + STRIP_DY)
        crack(s, [(30, y + 6), (32, y + 12), (30, y + 18)]); drone(s, 28, y + 8, 0)
        hurt_pair(s, st, (40, y + 8), (52, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(25, y + 6), (27, y + 12), (25, y + 18)]); crack(s, [(38, y + 6), (40, y + 14)]); wire(s, [(14, y + 18), (18, y + 21)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        cells_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        n = {'charge': i, 'on': 5, 'damaged': 4}.get(state, 0)
        for k in range(n): glow(g, ox + 18.5 + 6 * k, oy + y + 12, 3.5, YEL, 0.4, 2.0)
        glow(g, ox + 12, oy + y + 14, 3, YEL, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        for by in (8, 16): glow(g, ox + 11, oy + by + 3, 4, YEL, 0.2, 2.0)
        glow(g, ox + 51, oy + 15, 3, RED, 0.35, 2.0); glow(g, ox + 57, oy + 15, 3, RED, 0.35, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        chamfer_fill(b, 1, 4, 19, 19, 'a', 6); rim(b, 'a', 'y', 'u', (1, 4, 19, 22))                  # the dome
        for (x, y) in ((6, 8), (11, 6), (14, 12), (8, 17), (13, 18), (5, 13)): b.put(x, y, 'u')
        for (a, c) in (((4, 9), (16, 9)), ((4, 17), (16, 17))): line(b, a[0], a[1], c[0], c[1], 'u')
        b.put(10, 13, 'y'); b.put(11, 13, 'H'); b.put(10, 12, 'y')
        for by in (0, 23):                                                           # two drone bays on the flanks
            mat(b, 12, by, 12, 4, CH_D, cham=True)
            if st.state != 'disabled' and not st.fire: drone(b, 15, by + 1, st.i % 2) if False else b.put(17, by + 1, 'L')
        mat(b, 19 + o, 8, 16, 11, CH)                                                # the front plate with the launch slit
        b.rect(24 + o, 12, 10, 3, 'n'); b.hline(24 + o, 12, 10, 'K')
        eye_k(b, 20 + o, 9, st.state != 'disabled'); eye_k(b, 20 + o, 15, st.state != 'disabled')
        if st.fire: b.rect(25 + o, 13, 9, 1, 'H'); b.hline(25 + o, 12, 9, 'y')
    def bhurt(self, b, st):
        move(b, 12, 0, 12, 4, 0, -1) if False else b.put(18, 1, 'K'); move(b, 12, 23, 12, 4, 1, 1)
        crack(b, [(6, 7), (9, 11), (7, 16)], 'K', 'S')
        spark(b, 32, 10, False) if st.i == 0 else spark(b, 14, 3, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 20, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(6, 7), (9, 11), (7, 16), (10, 20)], 'K', 'S'); wire(b, [(26, 10), (29, 12)])
    def bafter(self, b, st):
        if st.fire:
            for k, (dx, dy) in enumerate(((0, -11), (0, 11), (6, -8), (6, 8), (10, 0))):
                drone(b, 13 + dx * 0 + 8 * (st.i + 1) - st.rc * 0 + (3 if dy == 0 else 0), 13 + dy + (0 if dy == 0 else (st.i * 0)) - 1, (k + st.i) % 2) if (k < 2 + st.i * 2) else None
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': glow(g, ox + 30, oy + 13.5, (12, 10, 7)[i], YEL, (0.5, 0.4, 0.3)[i], 1.8, sx=1.3)
        if state in ('idle', 'damaged'):
            glow(g, ox + 22, oy + 10, 3, RED, 0.3, 2.0); glow(g, ox + 22, oy + 16, 3, RED, 0.3, 2.0)

WEAPONS = [HiveSwarmLauncher, ChitinThrower, DronePicket]


# ================================================================== COMPONENTS
from lines_shield import arc, TIPS, CORN

def bighex(s, cx, cy, fill, rim='u', hi=None):
    """a big hive cell, 13 wide x 11 tall, centred on (cx, cy)."""
    chamfer_fill(s, cx - 6, cy - 5, 13, 11, rim, 3)
    chamfer_fill(s, cx - 5, cy - 4, 11, 9, fill, 2)
    if hi: s.put(cx - 4, cy - 3, hi); s.put(cx - 3, cy - 3, hi); s.put(cx - 4, cy - 2, hi)

HEXC = [(18, 32), (46, 32), (25, 21), (39, 21), (25, 43), (39, 43)]      # the six outer cells, then the centre (32, 32)
class HiveBattery(ShieldBase):
    id = 'kett_hive_battery'
    DMG = (3, 6)
    GLOW = BLUE
    notes = ('Kett "Hive Battery" (full layers only with 3 operators): an amber chitin frame holding a flower of seven big hive cells, each a blue shield cell. '
             'On loop (8): a wave of light runs round the six outer cells while the centre cell breathes; arcs crawl between the corner plates. hit (3): flare and ripple. recharge (4): the cells spinning up from dim. '
             'Damaged: one outer cell cracked and dark, the frame split at the corner with a flap hanging, the wave stutters. Disabled: every cell dark and grey, the frame split, the centre cell burst.')
    def static(self, s, on):
        chamfer_fill(s, 1, 1, 61, 61, 'u', 6); rim(s, 'u', 'a', 'n')
        chamfer_fill(s, 3, 3, 57, 57, 'a', 5); rim(s, 'a', 'y', 'u', (3, 3, 59, 59))
        chamfer_fill(s, 7, 7, 49, 49, 'n', 5)
        for (x, y) in ((8, 8), (54, 8), (8, 54), (54, 54)): s.rect(x - 1, y - 1, 3, 3, 'y'); s.put(x, y, 'n')
        for t in range(10, 54, 6): s.put(t, 4, 'n'); s.put(t, 59, 'n'); s.put(4, t, 'n'); s.put(59, t, 'n')
        for (cx, cy) in HEXC + [(32, 32)]: bighex(s, cx, cy, 'D' if on else 'W', 'u' if on else 'q')
        if not on:
            for (cx, cy) in HEXC + [(32, 32)]: bighex(s, cx, cy, 'W', 'q')
            for (cx, cy) in HEXC + [(32, 32)]: s.put(cx - 2, cy - 1, 'M'); s.put(cx - 3, cy, 'S')
    def dyn(self, s, i, spin=1.0, dim=False, rj=0):
        lit = (i * 6) // 8 % 6 if not dim else rj % 6
        for k, (cx, cy) in enumerate(HEXC):
            near = (k - lit) % 6
            if dim: fill = 'W' if k != lit else 'S'; hi = 'M' if k == lit else None
            elif near == 0: fill, hi = 'c', 'H'
            elif near == 5: fill, hi = 'b', 'c'
            else: fill, hi = 'B', 'b'
            bighex(s, cx, cy, fill, 'u', hi)
        br = BR[i % 8] - 1 if not dim else (1, 2, 3, 4)[rj % 4]
        bighex(s, 32, 32, 'B' if not dim else 'W', 'u')
        circle(s, 32, 32, min(5, br), 'b' if not dim else 'S'); circle(s, 32, 32, max(1, min(5, br) - 2), 'c' if not dim else 'M')
        if not dim:
            for k in range(4): arc(s, TIPS[k], CORN[k], TIPS[(k + 1) % 4], i, k, 'b', 'c', 'H')
        else: arc(s, TIPS[rj % 4], CORN[rj % 4], TIPS[(rj + 1) % 4], rj, 0, 'b', 'c', 'H', nframes=4)
    def glow_extra(self, g, ox, oy, i, k, flick=None):
        lit = (i * 6) // 8 % 6
        for kk, (cx, cy) in enumerate(HEXC):
            if flick is not None and kk == 3: continue
            glow(g, ox + cx, oy + cy, 9 if kk == lit else 6, BLUE, (0.5 if kk == lit else 0.25) * k, 2.0)
    def hurt(self, s, i):
        bighex(s, 39, 21, 'D', 'n'); crack(s, [(35, 17), (38, 21), (36, 25), (40, 26)], 'K')
        s.stamp(46, 44, art("KKKK..\nKaayK.\nKuaayK\n.KKuuK\n...KKK")); s.stamp(54, 46, art(".K\nKD"))
        s.rect(3, 29, 9, 6, 'D'); hollow(s, 3, 29, 9, 6, 'K'); s.put(5, 31, 'u')
        stamp_on(s, 44, 8, SCORCH_S)
        s.put(30 + 5 * i, 28, 'y'); s.put(37, 33 - i, 'H' if i else 'y')
    def wreck(self, s):
        s.stamp(26, 27, art("..KKKKKK..\n.KDDKDDDDK.\nKDDDDKDDDDK\nKDKDDDDKDDK\n.KDDDDDDDK.\n..KKKKKK.."))
        crack(s, [(3, 4), (8, 8), (12, 14), (17, 19)]); crack(s, [(60, 60), (55, 55), (49, 52), (44, 48)])
        bighex(s, 39, 21, 'K', 'n'); s.stamp(46, 44, art("KKKK..\nKuaaK.\nKaaauK\n.KKuuK")); stamp_on(s, 40, 8, SCORCH_L)

class NestReactor(LK.LComp):
    id = 'kett_nest_reactor'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    PULSE = [7, 8, 9, 8]
    RING = [(32, 8), (53, 20), (53, 44), (32, 56), (11, 44), (11, 20)]            # six hive cells round the dome
    notes = ('Kett "Nest Reactor" (+1 power per Kett in the room): a round chitin dome of overlapping plates grown over an amber egg-core that pulses (4 frames), six hive cells round the rim that light green in turn, '
             'four corner drone bays with a drone in each. Damaged: a dome plate peeled back with light leaking, two rim cells dark, a bay door hanging, the core stutters. '
             'Disabled: the plates grey and cracked, the core a dull husk, cells dead, a bay broken.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 62, 62, 'u', 8); rim(s, 'u', 'a', 'n')
        chamfer_fill(s, 4, 4, 56, 56, 'a', 7); rim(s, 'a', 'y', 'u', (4, 4, 59, 59))
        for (x, y) in ((6, 6), (50, 6), (6, 50), (50, 50)):                           # corner drone bays
            circle(s, x + 4, y + 4, 4.6, 'n'); ring(s, x + 4, y + 4, 3.8, 5.0, 'u'); drone(s, x + 2, y + 2, i % 2) if on else None
        for k, (cx, cy) in enumerate(self.RING):
            f = ('g' if (k + i) % 3 == 0 else 'y') if on else 'D'
            hexcell(s, cx - 3, cy - 2, f, 'u' if on else 'q', hi='H' if on and (k + i) % 3 == 0 else None)
        circle(s, 32, 32, 22, 'n'); circle(s, 32, 32, 21, 'u')                          # the dome
        for k in range(8):                                                            # plates: wedges separated by dark seams
            a = math.pi * k / 4 + math.pi / 8
            for r in range(8, 21): s.put(int(round(32 + r * math.cos(a) - .5)), int(round(32 + r * math.sin(a) - .5)), 'n')
        for y in range(10, 54):
            for x in range(10, 54):
                d = ((x - 31.5) ** 2 + (y - 31.5) ** 2) ** .5
                if s.get(x, y) == 'u' and d < 20.2 and d > 9: s.put(x, y, 'y' if (x - 32) + (y - 32) < -13 else ('a' if (x - 32) + (y - 32) < 10 else 'u'))
        ring(s, 32, 32, 13, 14.2, 'n'); ring(s, 32, 32, 18, 19.2, 'n')
        circle(s, 32, 32, 10, 'n'); circle(s, 32, 32, 9, 'D')
        if on:
            r = self.PULSE[i]
            circle(s, 32, 32, r, 'o'); circle(s, 32, 32, r - 1.5, 'y'); circle(s, 32, 32, max(2, r - 4), 'H')
            for (a, b) in (((32, 24), (32, 28)), ((24, 32), (28, 32)), ((40, 32), (36, 32)), ((32, 40), (32, 36))): line(s, a[0], a[1], b[0], b[1], 'o')
        else:
            circle(s, 32, 32, 6, 'q'); circle(s, 32, 32, 4, 'n'); s.put(30, 30, 'Q')
        return s
    def hurt(self, s, i):
        for (x, y) in ((40, 20), (41, 20), (41, 21), (42, 21), (42, 22), (41, 22), (40, 21)): s.erase(x, y)
        for (x, y) in ((39, 19), (40, 19), (42, 20), (43, 21)): s.put(x, y, 'K')
        for (x, y) in ((44, 23), (45, 24), (44, 25)): s.put(x, y, 'y' if (x + i) % 2 else 'o')
        hexcell(s, 50, 18, 'D', 'n'); hexcell(s, 8, 41, 'D', 'n')
        move(s, 50, 50, 9, 9, 3, 2 + i); s.put(60, 52, 'o')
        spark(s, 14, 14, False) if i == 0 else spark(s, 48, 54, False)
        if i == 1:
            for (x, y) in ((32, 32), (33, 32), (32, 33), (33, 33)): s.put(x, y, 'o')
    def wreck(self, s):
        crack(s, [(3, 10), (8, 15), (12, 20), (14, 27)], 'K'); crack(s, [(60, 50), (54, 54), (50, 59)], 'K'); crack(s, [(28, 16), (32, 24), (30, 30)], 'K')
        s.stamp(47, 6, art("KKKKK.\nKaayyK\n.KuuKK")); fallen_chunk(s, 50, 52); wire(s, [(20, 56), (26, 58)])
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.85)
        r = self.PULSE[i]
        glow(g, ox + 32, oy + 32, 22 + r, ORANGE, (0.28 + 0.03 * r) * k, 1.4)
        glow(g, ox + 32, oy + 32, 5 + r * 0.8, YEL, 0.55 * k, 1.6)
        for kk, (cx, cy) in enumerate(self.RING):
            if flick is not None and kk == 1: continue
            if (kk + i) % 3 == 0: glow(g, ox + cx, oy + cy, 6, GREEN, 0.55 * k, 2.0)
            else: glow(g, ox + cx, oy + cy, 4, YEL, 0.25 * k, 2.0)
        if flick is not None: glow(g, ox + 44, oy + 24, 6, YEL, 0.5 if flick else 0.25, 2.0)

class BroodHold(LK.LComp):
    id = 'kett_brood_hold'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    DMG = (0, 1)
    EGGS = [(6, 5), (12, 5), (18, 5), (6, 9), (12, 9), (18, 9), (6, 13), (12, 13), (18, 13)]
    notes = ('Kett "Brood Hold" (Kett heal and work x1.2 here, others x0.8): a chitin nursery cabinet of nine hive cells, each holding a pale larva; on loop (2) the larvae glow in alternating cells as they squirm. '
             'A row of three small drone bays along the bottom. Damaged: a cell burst open and dark, the larva gone, a plate hanging, sparks. Disabled: the cells grey and empty, the cabinet cracked, a bay dark.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        mat(s, 1, 1, 30, 30, CH_D)
        mat(s, 3, 3, 26, 21, ('n', 'D', 'K'), cham=False)
        k = 0
        for c in range(3):
            for r in range(3):
                cx = 4 + c * 8; cy = 4 + r * 6 + (3 if c % 2 else 0)
                if cy + 5 > 24: continue
                glowing = on and (k + i) % 2 == 0
                hexcell(s, cx, cy, 'D', 'u' if on else 'q')
                if state != 'disabled':
                    s.put(cx + 2, cy + 2, 'H' if glowing else ('f' if on else 'M')); s.put(cx + 3, cy + 2, 'y' if glowing else ('f' if on else 'W')); s.put(cx + 4, cy + 2, 'f' if on else 'W')
                    s.put(cx + 3, cy + 1, 'f' if on and not glowing else 'D')
                k += 1
        for k in range(3):
            circle(s, 7 + 9 * k, 27, 2.4, 'n'); ring(s, 7 + 9 * k, 27, 1.8, 2.8, 'u')
            if on: drone(s, 5 + 9 * k, 26, (k + i) % 2)
        return s
    def hurt(self, s, i):
        hexcell(s, 12, 4, 'n', 'n'); crack(s, [(14, 4), (15, 7), (13, 9)], 'K')
        s.stamp(22, 20, art("KKK.\nKauK\n.KKK")); move(s, 20, 22, 8, 3, 1, 1)
        spark(s, 13, 8 if i == 0 else 20, False)
    def wreck(self, s):
        crack(s, [(14, 4), (15, 7), (13, 9), (15, 14)], 'K'); crack(s, [(4, 18), (9, 22)], 'K'); s.stamp(22, 20, art("KKK.\nKauK\n.KKK"))
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.6 if flick else 0.9)
        n = 0
        for c in range(3):
            for r in range(3):
                cx = 4 + c * 8; cy = 4 + r * 6 + (3 if c % 2 else 0)
                if cy + 5 > 24: continue
                if state == 'on' and (n + i) % 2 == 0: glow(g, ox + cx + 3.5, oy + cy + 2.5, 5, YEL, 0.4 * k, 2.0)
                n += 1

COMPONENTS = [HiveBattery, NestReactor, BroodHold]

# ================================================================== PROJECTILES AND IMPACTS (drone swarms, chitin needles)
def _swarm():
    out = []
    pos = [[(2, 1), (7, 2), (4, 5), (9, 7), (1, 8), (6, 10), (3, 13), (8, 14)],
           [(3, 2), (8, 1), (5, 4), (8, 8), (2, 7), (5, 11), (2, 13), (9, 13)],
           [(1, 2), (6, 3), (4, 6), (9, 6), (2, 9), (7, 9), (4, 12), (8, 15)],
           [(3, 1), (8, 3), (5, 5), (8, 9), (1, 7), (6, 12), (3, 14), (9, 12)]]
    for k in range(4):
        s = Spr(12, 17)
        for n, (x, y) in enumerate(pos[k]):
            wing = (n + k) % 2
            s.put(x, y, 'y'); s.put(x, y + 1, 'u')
            if wing: s.put(x - 1, y, 'L'); s.put(x + 1, y, 'L')
            else: s.put(x - 1, y + 1, 'L'); s.put(x + 1, y + 1, 'L')
        out.append(s)
    return out

def _swarm_impact():
    f = []
    s = Spr(16, 16); disc(s, 8, 8, 3, 'o'); disc(s, 8, 8, 1.8, 'y'); disc(s, 8, 8, 0.8, 'H'); dots(s, 8, 8, 5, 8, 'y', 0.2); dots(s, 8, 8, 6, 8, 'L', 0.6)
    f.append(s)
    s = Spr(16, 16); dots(s, 8, 8, 4, 8, 'y', 0.1); dots(s, 8, 8, 6, 8, 'L', 0.5); dots(s, 8, 8, 7, 6, 'u', 0.3); s.put(8, 8, 'H'); s.put(7, 8, 'o'); s.put(8, 7, 'o')
    f.append(s)
    s = Spr(16, 16); dots(s, 8, 8, 6, 8, 'y', 0.3); dots(s, 8, 8, 7, 8, 'L', 0.0, 2); dots(s, 8, 8, 3, 5, 'o', 0.7)
    f.append(s)
    s = Spr(16, 16); dots(s, 8, 8, 7, 6, 'u', 0.6); dots(s, 8, 8, 5, 4, 'y', 0.2)
    f.append(s)
    return f

def _needles():
    out = []
    for k in range(3):
        s = Spr(11, 14)
        for (x0, y0, x1, y1) in ((5, 0, 5, 9), (3 + (k % 2), 2, 1, 11 + (k == 1)), (7 - (k % 2), 2, 9, 11 + (k == 2))):
            line(s, x0, y0, x1, y1, 'a'); s.put(x0, y0, 'H'); s.put(x0 + (1 if x1 > x0 else (-1 if x1 < x0 else 0)), y0 + 1, 'y')
        for (x0, y0, x1, y1) in ((4, 5, 3, 13), (6, 5, 7, 13)): line(s, x0, y0 + k % 2, x1, y1, 'u')
        s.put(5, 10 + k % 2, 'Q')
        out.append(s)
    return out

def _needle_impact():
    f = []
    s = Spr(14, 14); disc(s, 7, 7, 2.5, 'H'); rays(s, 7, 7, 8, 3, 6, 'ya', 0.1)
    f.append(s)
    s = Spr(14, 14); disc(s, 7, 7, 1.5, 'y'); rays(s, 7, 7, 8, 3, 6, 'Qa', 0.4); dots(s, 7, 7, 6, 8, 'y', 0.2)
    f.append(s)
    s = Spr(14, 14); rays(s, 7, 7, 8, 5, 6, 'u', 0.1); dots(s, 7, 7, 3, 4, 'a', 0.5)
    f.append(s)
    return f

def _interceptor():
    out = []
    body = art("""
..y..
.yay.
.yry.
.uau.
..u..
..n..
""")
    wings = [art("""
L...L
LL.LL
.....
.....
.....
.....
"""), art("""
.....
.L.L.
LL.LL
.....
.....
.....
"""), art("""
.....
.....
.L.L.
LL.LL
.....
.....
"""), art("""
.....
.L.L.
LL.LL
.....
.....
.....
""")]
    for k in range(4):
        s = Spr(7, 12)
        s.stamp(1, 1, wings[k]); s.stamp(1, 0, body)
        s.put(3, 7, 'o'); s.put(3, 8, 'y' if k % 2 else 'o'); s.put(3, 9, 'r'); s.put(2 + (k % 2) * 2, 10, 'r')
        out.append(s)
    return out

def _interceptor_impact():
    f = []
    s = Spr(14, 14); disc(s, 7, 7, 4, 'o'); disc(s, 7, 7, 2.8, 'y'); disc(s, 7, 7, 1.3, 'H'); rays(s, 7, 7, 8, 4, 6, 'yo', 0.4)
    f.append(s)
    s = Spr(14, 14); ring(s, 7, 7, 4, 5.6, 'y'); disc(s, 7, 7, 1.5, 'o'); dots(s, 7, 7, 6, 8, 'L', 0.2)
    f.append(s)
    s = Spr(14, 14); ring(s, 7, 7, 5.2, 6.5, 'u'); dots(s, 7, 7, 3, 4, 'o', 0.3)
    f.append(s)
    return f

PROJECTILES = [
    Proj('kett_hive_swarm_launcher', _swarm(), _swarm_impact(), (6, 8), (6, 16), fps=16, ifps=14, pad=4, ipad=4, bands=((1.5, 90), (3.2, 44)),
         notes='A swarm of eight tiny drones, 12x17: amber bodies with pale wings that beat out of step; the loose cloud reshuffles over 4 frames. One sprite = the whole volley (the weapon fires many at full rate).',
         inotes='The swarm lands: a small flash, the drones scatter and burst into specks (4 frames, 16x16).'),
    Proj('kett_chitin_thrower', _needles(), _needle_impact(), (5, 0), (5, 13), fps=16, ifps=16, pad=3, ipad=4, bands=((1.5, 90), (3.2, 44)),
         notes='A fan of three amber chitin needles with pale tips, 11x14, over a thin second layer (3 frames). It is a cone: fire several at spread angles.',
         inotes='The needles stick and splinter: a pale flash and amber shards flying out (3 frames, 14x14).'),
    Proj('kett_drone_picket', _interceptor(), _interceptor_impact(), (3, 1), (3, 10), fps=16, ifps=14, pad=3, ipad=4, bands=((1.5, 90), (3.2, 44)),
         notes='An interceptor drone, 7x12: an amber dart with red eye and a short exhaust, wings beating over 4 frames. It homes on missiles and boarders.',
         inotes='The drone detonates: a small amber-white pop, a ring, fading specks (3 frames, 14x14).'),
]
