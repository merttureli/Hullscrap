"""Gauntling racial tech (docs/waves/racial_tech_1.md): machines bolted together from whatever was lying about. Mismatched steel, rust and dark plates, copper-wound coils, colour-coded
wires, ball electrodes and cyan electric arcs that jump on the loop. Weapons: gauntling_arc_hammer (fixed), gauntling_scrap_shotgun (fixed), gauntling_tesla_picket (turret).
Components: gauntling_arc_core (reactor), gauntling_overclock_engine (engine, two halves), gauntling_graft_bay (utility)."""
from tech_kit import *
from comp_base import stamp_on, SCORCH_S, SCORCH_L
from lines_kit import LComp, crack as lcrack, line as lline, circle as lcircle, ring as lring
from lines_eng_base import EngBase, Half2, flange_n

ARC = {'o': 'C', 'y': 'c'}
F_ARC = flash_arts(ARC)
DK = {'c': 'W', 'C': 'E', 'g': 'E', 'a': 'u', 'y': 'a', 'r': 'n'}

def patch(s, x, y, w, h, kind, bolts_=True):
    """a mismatched plate: kind 0 pale steel, 1 dark steel, 2 rust."""
    hi, mid, lo = (('M', 'S', 'W'), ('S', 'W', 'E'), ('Q', 'u', 'n'))[kind % 3]
    bev(s, x, y, w, h, hi, mid, lo, cham=False)
    if bolts_ and w > 6 and h > 6:
        for (bx, by) in ((x + 1, y + 1), (x + w - 2, y + 1), (x + 1, y + h - 2), (x + w - 2, y + h - 2)): s.put(bx, by, 'L')

def winding(s, x, y, w, h, lit=False, vert=True):
    """copper wire wound on a core: alternating bands; cyan-hot when lit."""
    for k in range(h if vert else w):
        a, b = ('c', 'C') if lit else ('a', 'u')
        c = a if k % 2 == 0 else b
        if vert: s.hline(x, y + k, w, c); s.put(x, y + k, 'y' if (not lit and k % 2 == 0) else c)
        else: s.vline(x + k, y, h, c)

def wires(s, pts, c='r'):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]): lline(s, x0, y0, x1, y1, c)

class GauntW(RW):
    HT = ('M', 'S', 'W'); FT = ('M', 'S', 'W'); CH = ('c', 'C', 'g'); DK = DK
    LIVE = RGB_['cyan']
    def flange_trim(self, s, st, half, y):
        s.rect(33, y, 29, FLANGE + 1, 'u'); s.hline(33, y, 29, 'Q'); s.hline(33, y + FLANGE, 29, 'n'); s.vline(33, y, FLANGE + 1, 'K')
        for x in (4, 13, 50, 59): s.put(x, y + 2, 'L')
        wires(s, [(16, y + 2), (24, y + 2)], 'r'); wires(s, [(24, y + 3), (30, y + 3)], 'y')
    def rhousing(self, s, y0, col=True):
        super().rhousing(s, y0, col)
        patch(s, 36, y0 + 2, 25, 18, 2)                                         # a rust patch over the right half
        s.hline(2, y0 + 15, 3, 'K'); weld(s, 34, y0 + 3, 10, True)
    def rstrip(self, s, st, y0):
        """five little copper coils: they light cyan one by one while charging and glow green-white when ready."""
        y = y0 + STRIP_DY
        recess(s, STRIP_X - 2, y - 1, 5 * 8 + 2, 7, 'D', 'K')
        for k in range(5):
            cx = STRIP_X + k * 8; on = st.powered and k < st.lit
            for r in range(5):
                if getattr(st, 'flash', False) and st.powered: c = 'H' if r % 2 == 0 else 'L'
                elif on and st.ready: c = 'g' if r % 2 == 0 else 'H'
                elif on: c = 'c' if r % 2 == 0 else 'C'
                else: c = 'u' if r % 2 == 0 else 'n'
                s.hline(cx, y + r, 6, c)
            s.put(cx - 1, y + 2, 'S'); s.put(cx + 6, y + 2, 'S')

def mismatch_gun(s, w, st, left_kind=2):
    """extra plates over a rgun_housing: a rust patch on the left wing, a dark plate on the right."""
    patch(s, 3, 6, 16, 18, left_kind); patch(s, 45, 6, 16, 18, 1)

# ============================================================ ARC HAMMER (fixed)
class ArcHammer(GauntW):
    id = 'gauntling_arc_hammer'; aim = 'fixed'
    blen, bwid = 58, 21
    bpivot = (6, 10)
    bmuzzle = (44, 10)
    out_notes = ('OUTSIDE half of the Gauntling Arc Hammer (a FIXED gun, scrap): a grey housing with a rust patch, a big copper-wound capacitor can with a cyan window on the left and, on the right, a pair of rods where a small arc climbs on the loop. '
                 'damaged: the capacitor leaks sparks, the rods bent and the arc stuttering; disabled: scorched, dented, the can split and its winding unwound, never destroyed.')
    notes = ('INSIDE half of the Gauntling Arc Hammer: three steel capacitor cans with copper bands, exposed contacts between them that spit an arc on the loop, a patched hatch, power coupling and five copper coils that light cyan while charging (frame 5 = ready, green). '
             'fire: the coils flash white then go out. damaged: a can dented and arcing to the casing, two coils dead; disabled: a can split, the contacts burnt, wires hanging. '
             'Barrel layer gauntling_arc_hammer_barrel: a ram tube with copper windings ending in a battered hammer head with two ball electrodes and an arc between them; fire: the head slams forward and a blue-white flash.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.rgun_housing(s)
        patch(s, 3, 6, 16, 18, 2)                                               # left: the capacitor can
        cylv(s, 6, 8, 11, 15, 'MMSSSWE' if pw else 'MSSWWE'); s.hline(6, 11, 11, 'D'); s.hline(6, 20, 11, 'D')
        winding(s, 6, 12, 11, 8, pw)
        s.rect(10, 8, 3, 3, 'D'); s.put(11, 9, 'c' if pw else 'E')
        patch(s, 45, 6, 16, 18, 1)                                              # right: the Jacob's ladder
        for rx in (49, 56): s.vline(rx, 8, 14, 'L'); s.vline(rx + 1, 8, 14, 'W')
        if pw:
            h = 20 - (i * 6 + 2)
            arc(s, [(50, h + 2), (52, h), (55, h + 1), (56, h - 1)], 'H', 'c', 'C')
        s.rect(48, 22, 11, 2, 'W'); s.put(52, 3, 'L'); s.put(52, 2, 'M')
        weld(s, 20, 17, 5, True); s.put(46, 5, 'r'); s.put(47, 6, 'y')
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        for k, cx in enumerate((14, 25, 36)):                                   # three capacitor cans with copper bands
            cylv(s, cx, y + 5, 9, 15, 'LMSSSWE' if k != 1 else 'QuuqqnE')
            s.hline(cx, y + 9, 9, 'a'); s.hline(cx, y + 10, 9, 'u'); s.hline(cx, y + 16, 9, 'a'); s.hline(cx, y + 17, 9, 'u')
            s.rect(cx + 3, y + 3, 3, 2, 'L')
        if pw: arc(s, [(23, y + 7), (25 + i, y + 9 - i), (27, y + 7)], 'H', 'c', 'C') if i else arc(s, [(34, y + 12), (35, y + 14), (36, y + 12)], 'H', 'c', 'C')
        hatch(s, 49, y + 7, st, 10, 11)
        wires(s, [(12, y + 6), (13, y + 4), (17, y + 3)], 'g'); wires(s, [(12, y + 7), (13, y + 5), (14, y + 4)], 'r')
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        crack(s, [(9, 12), (8, 16), (10, 20)]); s.rect(6, 12, 11, 8, 'u'); winding(s, 6, 12, 5, 8, False)
        spark(s, 14, 11, False) if st.i else spark(s, 8, 22, False)
        s.rect(47, 8, 4, 14, '.'); s.vline(49, 8, 5, 'L'); s.vline(46, 12, 10, 'L'); s.vline(47, 12, 10, 'W')           # a rod bent over
        arc(s, [(49, 13), (50 + st.i * 2, 15), (53, 14)], 'H', 'c', 'C')
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(10, 8), (9, 14), (11, 20)], [(53, 8), (52, 14), (54, 20)]], dents=[(46, 18, 6, 4), (22, 4, 6, 4)],
                 soots=[(4, 8, 0), (47, 6, 1), (30, 12, 2)], wires_=[[(16, 12), (18, 15), (17, 19)]], sparks=[(14, 10), (56, 6)])
        s.rect(6, 12, 11, 8, 'n'); wire(s, [(7, 14), (11, 17), (9, 21), (13, 22)], 'a')
        s.rect(49, 8, 9, 6, '.')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        dent(s, 26, y + 6, 6, 5); arc(s, [(31, y + 8), (34, y + 6 + st.i), (37, y + 3)], 'H', 'c', 'C')
        crack(s, [(15, y + 5), (16, y + 10), (14, y + 15)])
        spark(s, 54, y + 20, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(37, y + 5), (38, y + 10), (36, y + 15), (39, y + 19)]); crack(s, [(26, y + 5), (27, y + 12)])
        s.rect(28, y + 11, 6, 5, 'K'); wire(s, [(20, y + 17), (22, y + 21), (27, y + 22)], 'a'); wire(s, [(34, y + 9), (36, y + 11)], 'r')
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['cyan'], 0.5, 2.0)
        if i % 2 == 0: glow(g, ox + 30, oy + y + 9, 7, RGB_['cyan'], 0.35, 2.0, sx=1.6)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 11, oy + 9.5, 4, RGB_['cyan'], 0.5, 2.0); glow(g, ox + 53, oy + 15 - i * 6, 8, RGB_['cyan'], 0.4, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 13 + o, 5, 22, 11, 'LMSSSWE')                                   # the ram tube
        for bx in (16, 24):                                                    # copper windings
            for k in range(6): b.vline(bx + k + o, 4, 13, 'a' if k % 2 == 0 else 'u')
            b.put(bx + o, 4, 'y'); b.put(bx + 2 + o, 4, 'y')
        hm = o - (2 if st.fire else 0)
        bev(b, 34 + hm, 1, 11, 19, 'S', 'W', 'E', cham=False)                   # the battered hammer head
        for (x, y) in ((36, 3), (42, 3), (36, 17), (42, 17)): b.put(x + hm, y, 'L')
        dent(b, 37 + hm, 8, 4, 4)
        for ey in (6, 13):                                                     # two ball electrodes
            cylh(b, 44 + hm, ey, 4, 3, 'LMS'); b.put(48 + hm, ey + 1, 'L')
        if not st.fire: arc(b, [(47 + hm, 8), (46 + hm, 10), (48 + hm, 11), (47 + hm, 13)], 'H', 'c', 'C')
        else: arc(b, [(48 + hm, 7), (51 + hm, 10), (48 + hm, 13)], 'H', 'c', 'C')
        breech(b, 10, 17)
        weld(b, 13 + o, 17, 4)
    def bhurt(self, b, st):
        b.rect(24, 4, 6, 13, '.'); lline(b, 24, 6, 29, 12, 'a'); lline(b, 25, 6, 29, 14, 'u')                           # a winding unwound
        crack(b, [(36, 2), (38, 6), (37, 10)]); move(b, 44, 12, 4, 4, 0, 2)
        spark(b, 30, 8, False) if st.i == 0 else spark(b, 46, 16, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 33, 2, 3)
    def bwreck(self, b, st):
        wire(b, [(33, 9), (35, 11), (36, 13)], 'a'); b.stamp(24, 8, art("aa\nua"))
        crack(b, [(36, 3), (37, 8), (36, 14)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 51 - 2, 10, F_ARC)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 49, 10, rgb=(60, 242, 255), core=(244, 246, 248), scale=1.0)
        if state == 'idle': glow(g, ox + 47, oy + 10.5, 6, RGB_['cyan'], 0.45, 2.0)

# ============================================================ SCRAP SHOTGUN (fixed): a sawn-off pair of mismatched pipes fed from a junk hopper
SCRAP_BITS = [(0, 0, 'L'), (2, 1, 'M'), (4, 0, 'Q'), (1, 2, 'S'), (3, 2, 'u'), (5, 2, 'L')]
class ScrapShotgun(GauntW):
    id = 'gauntling_scrap_shotgun'; aim = 'fixed'
    blen, bwid = 50, 19
    bpivot = (6, 9)
    bmuzzle = (36, 9)
    out_notes = ('OUTSIDE half of the Gauntling Scrap Shotgun (a FIXED gun, scrap): a grey housing, a rust funnel hopper brimming with scrap on the left that jiggles on the loop, a patched plate with hazard tape and a gear on the right. '
                 'damaged: the hopper has a hole and spills bolts, the gear is missing teeth; disabled: scorched, dented, the hopper empty and torn, never destroyed.')
    notes = ('INSIDE half of the Gauntling Scrap Shotgun: a junk hopper full of bolts and scrap above a gear train, a feed chute to the right (the ammo rack sits beside it), power coupling, patched hatch and five copper coils. '
             'damaged: a gear cracked and stuttering, bits spilling; disabled: the gear train jammed, the chute split. '
             'Barrel layer gauntling_scrap_shotgun_barrel: two sawn-off pipes of different widths (one steel, one rust) clamped with wire and hazard tape; fire: a spray of scrap pellets from both muzzles.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.rgun_housing(s)
        patch(s, 3, 6, 16, 18, 2)                                               # left: the funnel hopper
        fillpoly(s, [(2, 5), (19, 5), (15, 17), (6, 17)], 'u'); fillpoly(s, [(2, 5), (6, 17), (2, 17)], 'Q') if False else None
        s.hline(2, 5, 18, 'Q'); s.hline(2, 6, 18, 'n'); s.vline(6, 7, 10, 'n')
        for k, (bx, by, c) in enumerate(SCRAP_BITS): s.put(5 + bx * 2 + (i if k % 2 else 0), 3 - (by if k % 3 else 0) + (i if k % 3 == 1 else 0), c); s.put(6 + bx * 2, 4, c)
        s.rect(8, 17, 5, 6, 'W'); s.vline(8, 17, 6, 'M')
        patch(s, 45, 6, 16, 18, 1); hazard(s, 46, 20, 14, 3)
        lcircle(s, 53, 13, 4, 'S'); lcircle(s, 53, 13, 2.5, 'D'); s.put(53, 13, 'L')
        for k in range(8):
            a = math.radians(k * 45 + (i * 20 if pw else 0)); s.put(int(round(53 + 5 * math.cos(a))), int(round(13 + 5 * math.sin(a))), 'M')
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 2, st, 'c'); hatch(s, 3, y + 16, st, 9, 8)
        fillpoly(s, [(15, y + 4), (37, y + 4), (33, y + 12), (19, y + 12)], 'W'); s.hline(15, y + 4, 23, 'M')                # the hopper from above
        for k, (bx, by, c) in enumerate(SCRAP_BITS): s.put(19 + bx * 3 + (i if k % 2 else 0), y + 5 + by * 2, c); s.put(20 + bx * 3, y + 6 + by, c)
        for gx, gc in ((24, 'M'), (32, 'Q')):                                   # a mismatched gear pair
            lcircle(s, gx, y + 17, 4, gc); lcircle(s, gx, y + 17, 2, 'D'); s.put(gx, y + 17, 'L')
            for k in range(8): a = math.radians(k * 45 + (i * 22 if pw else 0) * (1 if gx == 24 else -1)); s.put(int(round(gx + 5 * math.cos(a))), int(round(y + 17 + 5 * math.sin(a))), 'S')
        bev(s, 41, y + 5, 22, 15, 'S', 'E', 'D')                                # feed chute toward the ammo rack
        s.rect(44, y + 8, 19, 9, 'D'); s.hline(44, y + 8, 19, 'K'); s.hline(44, y + 17, 19, 'M')
        for k in range(3): s.put(48 + 5 * k, y + 12, 'L'); s.put(49 + 5 * k, y + 12, 'Q')
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        s.rect(7, 9, 4, 4, 'D'); 
        for k in range(4): s.put(8, 14 + (k * 2 + st.i) % 8, 'M' if k % 2 else 'Q')
        for k in range(3): s.put(51 + k * 2, 8, '.')
        crack(s, [(46, 8), (48, 12), (47, 16)])
        spark(s, 56, 11, False) if st.i else spark(s, 20, 20, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(10, 8), (9, 14), (11, 20)], [(53, 8), (52, 14), (54, 20)]], dents=[(46, 18, 6, 4), (6, 20, 5, 4)],
                 soots=[(4, 7, 0), (47, 6, 1), (30, 12, 2)], wires_=[], sparks=[(14, 10), (56, 6)])
        s.rect(2, 2, 18, 8, '.'); s.hline(4, 12, 12, 'n'); s.rect(7, 9, 5, 5, 'D')
        for k in range(4): s.put(10 + k * 2, 28, 'M' if k % 2 else 'u')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(24, y + 13), (25, y + 17), (23, y + 21)]); 
        for k in range(4): s.put(28 + k, y + 21 + (k + st.i) % 3, 'M' if k % 2 else 'Q')
        spark(s, 54, y + 18, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(45, y + 5), (47, y + 10), (46, y + 15)]); crack(s, [(31, y + 14), (33, y + 20)])
        s.rect(20, y + 5, 10, 5, 'D'); wire(s, [(14, y + 21), (16, y + 24), (22, y + 24)], 'a')
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 8, 3, RGB_['cyan'], 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy): glow(g, ox + 10, oy + 6, 4, RGB_['amber'], 0.2, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 13 + o, 1, 22, 8, 'LMMSSWE'); cylh(b, 13 + o, 10, 22, 8, 'QQuuuqnn')       # steel and rust pipes
        for bx in (17, 27):
            b.rect(bx + o, 0, 3, 19, 'W'); b.vline(bx + o, 0, 19, 'M'); b.put(bx + o + 1, 4, 'L'); b.put(bx + o + 1, 14, 'L')
        hazard(b, 21 + o, 0, 4, 19)
        bev(b, 33 + o, 0, 3, 10, 'M', 'S', 'W', cham=False); bev(b, 33 + o, 9, 3, 10, 'Q', 'u', 'n', cham=False)      # flared muzzles
        b.rect(35 + o, 2, 1, 6, 'D'); b.rect(35 + o, 11, 1, 6, 'D')
        wire(b, [(14 + o, 9), (22 + o, 9)], 'y'); b.hline(14 + o, 9, 20, 'D')
        breech(b, 9, 17)
    def bhurt(self, b, st):
        crack(b, [(20, 11), (21, 14), (19, 17)]); b.rect(27, 0, 3, 4, '.'); wire(b, [(28, 3), (30, 5)], 'r')
        move(b, 33, 9, 3, 10, 0, 2)
        spark(b, 31, 8, False) if st.i == 0 else spark(b, 24, 18, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 29, 2, 3, rows=(10, 19))
    def bwreck(self, b, st):
        wire(b, [(29, 12), (31, 14), (33, 15)], 'a'); b.stamp(34, 5, art("MM\nQu"))
        crack(b, [(16, 2), (17, 6), (15, 8)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire:
            for cy in (4, 14): stamp_flash(b, st, 36, cy, FLASH_S3)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            for cy in (4, 14): fire_glow(g, ox, oy, i, 36, cy, scale=0.7)
FLASH_S3 = [art("..o......\n.oyo.....\noyHyoo...\nyHHHHyo..\noyHyoo...\n.oyo.....\n..o......"), art(".o.......\noyo......\nyHyoo....\noyo......\n.o......."), art(".o.....\noyo....\n.o.....")]

# ============================================================ TESLA PICKET (turret)
class TeslaPicket(GauntW):
    id = 'gauntling_tesla_picket'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 46, 25
    bpivot = (8, 12)
    bmuzzle = (34, 12)
    out_notes = ('OUTSIDE half of the Gauntling Tesla Picket (a TURRET, scrap): a grey turret seat with a rust patch, a copper-wound transformer on the left with a cyan window and a pair of ball electrodes on the right where a small arc jumps on the loop. '
                 'damaged: the transformer sparks and a winding has slipped, the electrodes are bent; disabled: scorched, dented, windings unwound, never destroyed.')
    notes = ('INSIDE half of the Gauntling Tesla Picket: two big copper-wound coils side by side with a ball-electrode gap that arcs on the loop, a patched hatch, power coupling and five copper coils. '
             'damaged: a coil is scorched and arcs to the casing; disabled: both coils unwound. The rotating head gauntling_tesla_picket_barrel swivels in the ring: a tall copper-wound Tesla coil topped with a steel ball, arcs crawling off it, and a lamp eye; fire: forked lightning from the ball.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.rturret_seat(s, 15)
        patch(s, 3, 6, 16, 18, 1)
        cylv(s, 6, 8, 11, 14, 'MMSSSWE'); winding(s, 6, 11, 11, 9, pw); s.rect(10, 8, 3, 3, 'D'); s.put(11, 9, 'c' if pw else 'E')
        patch(s, 45, 6, 16, 18, 2)
        for ex, ey in ((49, 10), (56, 10)): lcircle(s, ex, ey, 2.6, 'M'); s.put(ex - 1, ey - 1, 'L')
        s.rect(48, 13, 3, 9, 'W'); s.rect(55, 13, 3, 9, 'W')
        if pw and i: arc(s, [(51, 10), (52, 9), (53, 11), (54, 9)], 'H', 'c', 'C')
        for (x, y) in ((24, 8), (40, 8), (24, 22), (40, 22)): s.put(x, y, 'L')
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        for k, cx in enumerate((15, 33)):                                       # two copper-wound coils
            patch(s, cx, y + 4, 15, 17, 1 + k)
            cylv(s, cx + 3, y + 6, 9, 13, 'QuuqqnE' if k else 'MSSSWEE'); winding(s, cx + 3, y + 8, 9, 9, pw and i % 2 == k)
        lcircle(s, 30, y + 11, 1.6, 'L'); lcircle(s, 32, y + 11, 1.6, 'L')
        if pw and i: arc(s, [(30, y + 11), (31, y + 9), (32, y + 12)], 'H', 'c', 'C')
        hatch(s, 50, y + 7, st, 10, 11)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        s.rect(6, 11, 11, 9, 'n'); winding(s, 6, 11, 5, 5, False); wire(s, [(11, 16), (14, 19), (13, 22)], 'a')
        spark(s, 14, 10, False) if st.i else spark(s, 8, 21, False)
        s.rect(54, 7, 6, 6, '.'); lcircle(s, 55, 14, 2.6, 'S')
        crack(s, [(46, 8), (48, 12), (47, 18)])
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(24, 8), (26, 12), (25, 16)], [(52, 7), (53, 12), (51, 17)]], dents=[(46, 20, 6, 3), (6, 20, 5, 4)],
                 soots=[(20, 3, 0), (46, 5, 1), (8, 7, 2)], wires_=[], sparks=[(30, 6), (12, 10)])
        s.rect(6, 11, 11, 9, 'K'); wire(s, [(7, 13), (11, 16), (9, 20), (13, 21)], 'a'); s.rect(54, 6, 6, 8, '.')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        s.rect(36, y + 8, 9, 9, 'n'); arc(s, [(43, y + 9), (47, y + 7 + st.i), (49, y + 4)], 'H', 'c', 'C')
        crack(s, [(18, y + 5), (19, y + 10), (17, y + 15)])
        spark(s, 54, y + 20, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        s.rect(18, y + 8, 9, 9, 'K'); s.rect(36, y + 8, 9, 9, 'K'); wire(s, [(20, y + 18), (24, y + 21), (30, y + 22)], 'a'); wire(s, [(38, y + 18), (36, y + 21)], 'a')
        crack(s, [(23, y + 5), (24, y + 12)]); crack(s, [(40, y + 5), (41, y + 12)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['cyan'], 0.5, 2.0)
        for k, cx in enumerate((22, 40)):
            if i % 2 == k: glow(g, ox + cx, oy + y + 13, 8, RGB_['cyan'], 0.35, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 11, oy + 9.5, 4, RGB_['cyan'], 0.5, 2.0)
        if i: glow(g, ox + 52, oy + 10, 6, RGB_['cyan'], 0.45, 2.0, sx=1.5)
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 14 + o, 8, 6, 9, 'MSSWE')                                       # the base can
        for k in range(14): b.vline(19 + k + o, 7 + (k // 5) // 1 * 0, 11 - 0, 'a' if k % 2 == 0 else 'u')          # the coil, windings
        b.rect(19 + o, 7, 14, 1, 'D') if False else None
        for k in range(14): b.put(19 + k + o, 7, 'y' if k % 2 == 0 else 'u'); b.put(19 + k + o, 17, 'n')
        lcircle(b, 38 + o, 12, 5.2, 'M'); lcircle(b, 38 + o, 12, 3.8, 'S'); b.put(36 + o, 10, 'L'); b.put(37 + o, 9, 'L'); b.put(36 + o, 11, 'L')
        for (x, y) in ((16, 6), (16, 18)): b.put(x + o, y, 'L')
        if st.state != 'fire':
            arc(b, [(42 + o, 9), (44 + o, 7), (46 + o, 8)], 'H', 'c', 'C') if False else None
        hub(b, 12, 17)
        eye(b, 10, 0, 'c'); b.put(11, 3, 'W'); b.put(11, 4, 'S')
    def bhurt(self, b, st):
        b.rect(21, 7, 7, 11, '.'); lline(b, 21, 9, 27, 15, 'a'); lline(b, 22, 9, 27, 17, 'u')
        crack(b, [(36, 8), (38, 12), (36, 15)]); b.rect(35, 10, 2, 2, 'D')
        spark(b, 30, 10, False) if st.i == 0 else spark(b, 42, 6, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 33, 2, 3, rows=(2, 23))
    def bwreck(self, b, st):
        wire(b, [(28, 12), (31, 14), (33, 16)], 'a'); b.stamp(24, 8, art("aa\nua"))
        crack(b, [(36, 8), (37, 12), (35, 16)], 'K', 'S')
    def bafter(self, b, st):
        if st.state == 'idle': arc(b, [(40, 7), (42, 5), (44, 6)], 'H', 'c', 'C'); arc(b, [(43, 15), (45, 17), (44, 19)], 'H', 'c', 'C')
        if st.fire:
            for k, (ex, ey) in enumerate(((46, 4), (47, 12), (46, 20))): arc(b, zig(41, 12, ex + 2 * st.i, ey + (st.i - 1) * 2, 4, 2, k + st.i), 'H', 'c', 'C')
            stamp_flash(b, st, 44, 12, F_ARC)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            fire_glow(g, ox, oy, i, 42, 12, rgb=(60, 242, 255), core=(244, 246, 248), scale=1.0)
        if state != 'disabled': glow(g, ox + 38.5, oy + 12.5, 8, RGB_['cyan'], 0.3, 2.0); glow(g, ox + 10.5, oy + 1.5, 3, RGB_['cyan'], 0.5, 2.0)

# ============================================================ ARC CORE (reactor 4x4)
class GauntC(LComp):
    dark = DK
    glow_pad = (10, 10, 10, 10)

class ArcCore(GauntC):
    id = 'gauntling_arc_core'; cells = (4, 4)
    anims = [('on', 'on', 4, 7), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    POST = [(10, 10), (53, 10), (10, 53), (53, 53)]
    notes = ('Gauntling Arc Core, 4x4: four mismatched plates (pale steel, rust, dark steel, patched) welded round a copper-wound ring with a steel ball in the middle; four electrode posts in the corners and cyan arcs that jump from the ball to a different post each frame (the 4-frame loop). '
             'Off: dark ball, windings dull. Damaged: a post sheared off and arcing to the casing, a plate lifting, the ball stuttering. Disabled: the ball cracked and dead, windings burnt, plates split.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 62, 62, 'W', 8)
        patch(s, 2, 2, 30, 30, 0); patch(s, 32, 2, 30, 26, 2); patch(s, 2, 32, 26, 30, 1); patch(s, 28, 28, 34, 34, 0)
        weld(s, 31, 4, 22, True); weld(s, 4, 31, 24); hazard(s, 4, 56, 22, 4)
        for (px_, py_) in self.POST:                                                         # electrode posts
            s.rect(px_ - 2, py_ - 2, 5, 5, 'E'); s.rect(px_ - 1, py_ - 1, 3, 3, 'S'); s.put(px_ - 1, py_ - 1, 'L'); s.put(px_, py_ - 3, 'L') if py_ < 30 else s.put(px_, py_ + 3, 'L')
        lcircle(s, 32, 32, 15, 'u'); lring(s, 32, 32, 12, 15, 'a')                           # the copper ring
        for k in range(24):
            a = math.radians(k * 15); s.put(int(round(32 + 13.5 * math.cos(a))), int(round(32 + 13.5 * math.sin(a))), 'y' if k % 2 == 0 else 'n')
        lcircle(s, 32, 32, 12, 'D'); lcircle(s, 32, 32, 8, 'E')
        lcircle(s, 32, 32, 6, 'S' if not on else 'M'); lcircle(s, 32, 32, 4.5, 'M' if not on else 'c'); s.put(30, 30, 'L'); s.put(31, 30, 'L'); s.put(30, 31, 'L')
        if on:
            lcircle(s, 32, 32, 3, 'c'); s.put(31, 31, 'H'); s.put(32, 31, 'H'); s.put(31, 32, 'H')
            for k, (px_, py_) in enumerate(self.POST):
                if (k + i) % 2 == 0 or i == 3:
                    arc(s, zig(32, 32, px_, py_, 5, 2, k + i), 'H', 'c', 'C')
        else:
            for (px_, py_) in self.POST: s.put(px_, py_, 'W')
        for (lx, ly) in ((30, 4), (34, 4), (30, 58), (34, 58)): s.put(lx, ly, 'g' if on and (lx + i) % 2 else ('E' if not on else 'y'))
        return s
    def hurt(self, s, i):
        s.rect(52, 8, 5, 5, '.'); s.stamp(51, 11, art(".SS.\nSMMS\nKSSK")); arc(s, [(52, 11), (56, 14), (58, 18)], 'H', 'c', 'C')
        lcrack(s, [(46, 4), (49, 9), (47, 14)], 'L'); lcrack(s, [(5, 40), (9, 44), (7, 49)], 'L')
        s.stamp(36, 40, art("KKKK.\nKDDDK\n.KDKK"))
        for (x, y) in ((24, 24), (25, 25), (26, 26)): s.put(x, y, 'K')
        if i: s.put(32, 31, 'o'); s.put(33, 31, 'o')
    def wreck(self, s):
        lcrack(s, [(3, 11), (7, 15), (6, 20), (11, 24), (13, 30)], 'M'); lcrack(s, [(50, 49), (54, 47), (57, 52), (60, 55)], 'M')
        lcircle(s, 32, 32, 6, 'K'); lcrack(s, [(28, 28), (32, 32), (36, 35)], 'S')
        s.rect(51, 8, 6, 6, 'K'); s.stamp(8, 8, art("KKK\nKLM\nKLM")); wire(s, [(14, 20), (18, 26), (20, 30)], 'a')
        s.stamp(36, 40, art("KKKK.\nKDDDK\n.KDKK")); stamp_on(s, 40, 20, SCORCH_S)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.85)
        glow(g, ox + 32, oy + 32, 24, RGB_['cyan'], 0.3 * k, 1.5)
        glow(g, ox + 32, oy + 32, 7, (244, 246, 248), 0.5 * k, 1.6)
        for j, (px_, py_) in enumerate(self.POST):
            if (j + i) % 2 == 0 or i == 3: glow(g, ox + px_ + .5, oy + py_ + .5, 6, RGB_['cyan'], 0.5 * k, 2.0)

# ============================================================ OVERCLOCK ENGINE (two halves)
class OverclockEngine(EngBase):
    id = 'gauntling_overclock_engine'; KIND = 'scrap'; DMG = (1, 2)
    pad_out = (10, 34, 10, 4)
    anchors_out = {'exhaust_left': (15, 2), 'exhaust_right': (46, 2)}
    anchors_in = {'power_coupling': (50, 29), 'repair_hatch': (12, 29)}
    dark = DK
    notes = ('Gauntling Overclock Engine, a hull mount (outward is up): a big pale steel bell and a smaller rust-coloured bell welded side by side, copper coils wound round both necks and cyan arcs that jump between the two rims and a spike between them on the loop; '
             'inside a core with a copper-wound coil stack, a knife switch on the front and mismatched plates. '
             'Damaged: the rust bell is bent over and sputtering, a coil unwound and sparking, an arc stuck on, the core coil scorched. Disabled: the big bell broken off its neck, the rust bell hanging, windings burnt, the core dead.')
    LB = (5, 21); RB = (39, 15)                                   # (x0, width) of the two bells
    def out(self, o, on, i):
        for (x0, w0, secs) in ((self.LB[0], self.LB[1], [(2, 6, 0), (7, 12, 2), (13, 18, 3)]), (self.RB[0], self.RB[1], [(8, 11, 0), (12, 15, 1), (16, 19, 2)])):
            from lines_eng_base import bell_gen
            bell_gen(o, x0, w0, secs, 28, on, i, bands=())
        for y in range(8, 28):                                                            # the right bell is a rust-coloured salvage
            for x in range(self.RB[0], self.RB[0] + self.RB[1]):
                c = o.get(x, y)
                if c in 'LMSWE': o.put(x, y, {'L': 'Q', 'M': 'Q', 'S': 'u', 'W': 'q', 'E': 'n'}[c])
        for (x0, w0, y0) in ((self.LB[0] + 6, self.LB[1] - 12, 21), (self.RB[0] + 3, self.RB[1] - 6, 21)):         # copper coils round the necks
            winding(o, x0, y0, w0, 6, on)
        o.rect(31, 6, 3, 21, 'W'); o.vline(31, 6, 21, 'M'); o.put(32, 4, 'L'); o.put(32, 5, 'M')                   # the spike between the bells
        hazard(o, 4, 24, 4, 3)
        if on:
            lx, rx = self.LB[0] + self.LB[1], self.RB[0]
            arc(o, zig(lx - 1, 3, 31, 5 + (i % 2), 3, 2, i), 'H', 'c', 'C'); arc(o, zig(33, 5 + (i % 2), rx + 3, 10, 3, 2, i + 1), 'H', 'c', 'C') if i != 1 else None
    def hurt_out(self, o, i):
        o.rect(self.RB[0] - 1, 6, self.RB[1] + 3, 22, '.')
        for y in range(8, 28):                                                            # the rust bell leans over and sputters
            for k, c in enumerate('QQuuqqnnQuqnQuq'): 
                if y < 24: o.put(self.RB[0] + 4 + k + (27 - y) // 3 * (-1), y, c)
        o.rect(self.RB[0] + 2, 22, 11, 6, 'u'); winding(o, self.RB[0] + 2, 22, 11, 5, False)
        arc(o, [(34, 6), (37, 12 + i * 2), (36, 20)], 'H', 'c', 'C')
        lcrack(o, [(12, 10), (13, 14), (11, 18)], 'L'); wire(o, [(14, 22), (16, 25), (18, 27)], 'a')
        spark(o, 24, 20, False) if i else spark(o, 44, 4, False)
    def wreck_out(self, o):
        o.rect(self.LB[0], 0, self.LB[1], 12, '.'); o.stamp(8, 12, art("KSSSSSSSK\nKEEEEEEEK"))                              # the big bell broken off
        o.stamp(14, 4, art("KKK.\nKMSK\nKSEK\n.KKK")); lcrack(o, [(12, 14), (14, 20), (12, 26)], 'M')
        for k in range(5): o.put(36 + k * 2, 14 + k, 'n'); o.put(37 + k * 2, 14 + k, 'q')
        wire(o, [(20, 22), (24, 25), (30, 26)], 'a'); o.stamp(40, 24, art("KKKK\nKnnK"))
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        glow_xy(g, ox + 15.5, oy + 5, 12, 30, (255, 138, 30), 0.4 * k * (0.9 + 0.05 * i), 1.9)
        glow_xy(g, ox + 46.5, oy + 11, 9, 24, (255, 138, 30), 0.3 * k, 1.9)
        glow(g, ox + 32, oy + 5.5, 12, RGB_['cyan'], 0.35 * k, 2.0, sx=2.2)
    def core(self, c, on, i):
        bev(c, 2, 2, 60, 29, 'M', 'S', 'W')
        patch(c, 36, 3, 25, 17, 2); weld(c, 34, 4, 12, True); hazard(c, 4, 25, 18, 3)
        for k, cx in enumerate((8, 20)):                                                    # the coil stack
            patch(c, cx, 4, 11, 18, 1); cylv(c, cx + 2, 5, 7, 15, 'MSSSWEE'); winding(c, cx + 2, 7, 7, 11, on and (i + k) % 2 == 0)
        for sx_ in (7, 19): c.hline(sx_, 21, 12, 'D')
        s_ = c
        s_.rect(40, 7, 18, 8, 'D'); s_.hline(40, 7, 18, 'K')                               # a knife switch
        s_.rect(42, 10, 14, 2, 'u'); s_.rect(44 + (4 if on else 0), 8, 2, 8, 'L'); s_.put(45 + (4 if on else 0), 7, 'r')
        lcircle(c, 44, 19, 2.5, 'S'); lcircle(c, 52, 19, 2.5, 'S'); c.put(43, 18, 'L'); c.put(51, 18, 'L')
        if on and i % 2: arc(c, [(46, 19), (48, 17), (50, 19)], 'H', 'c', 'C')
        for k in range(3): c.put(36 + k * 4, 24, ('g', 'y', 'r')[k] if on and (k + i) % 3 != 0 else 'E'); c.put(37 + k * 4, 24, 'E')
        coupling_ = c.rect(52, 24, 8, 4, 'W'); c.put(53, 25, 'g' if on else 'E')
    def hurt_core(self, c, i):
        c.rect(20, 5, 11, 17, 'n'); winding(c, 22, 7, 3, 8, False); wire(c, [(26, 12), (28, 16), (27, 21)], 'a')
        arc(c, [(30, 10), (34, 8 + i), (36, 5)], 'H', 'c', 'C'); lcrack(c, [(10, 5), (11, 10), (9, 15)], 'L')
        spark(c, 26, 22, False) if i else spark(c, 56, 6, False)
    def wreck_core(self, c):
        c.rect(8, 5, 11, 17, 'K'); c.rect(20, 5, 11, 17, 'K'); wire(c, [(10, 12), (14, 18), (24, 22)], 'a'); wire(c, [(22, 8), (26, 13)], 'a')
        lcrack(c, [(40, 8), (46, 12), (44, 18)], 'M'); c.stamp(52, 24, art("KKK\nKDK"))
    def glow_core(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        b = oy + 4
        for j, cx in enumerate((13.5, 25.5)):
            if (i + j) % 2 == 0: glow(g, ox + cx, b + 12, 9, RGB_['cyan'], 0.3 * k, 2.0)
        glow(g, ox + 38, b + 20, 3, RGB_['green'], 0.4 * k, 2.0)
        if i % 2: glow(g, ox + 48, b + 18, 6, RGB_['cyan'], 0.4 * k, 2.0, sx=1.6)

# ============================================================ GRAFT BAY (utility 4x4)
class GraftBay(GauntC):
    id = 'gauntling_graft_bay'; cells = (4, 4)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    notes = ('Gauntling Graft Bay, 4x4: a top-down repair bay on mismatched plates: a steel work table with a half-assembled limb, two jointed robot arms from the top corners that weld the limb together (a bright arc flickers and the arms shift on the 4-frame loop), '
             'a rack of spare hands and gears along the bottom and a hazard strip because organics are not welcome. '
             'Off: arms folded, table dark. Damaged: an arm is jammed at an angle and sparking, a plate lifts, the weld arc stutters. Disabled: both arms hanging limp, the table cracked, spares spilled.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 62, 62, 'W', 8)
        patch(s, 2, 2, 28, 22, 0); patch(s, 30, 2, 32, 22, 2); patch(s, 2, 24, 20, 38, 1); patch(s, 22, 44, 40, 18, 0)
        weld(s, 30, 4, 18, True); hazard(s, 24, 25, 38, 3); hazard(s, 4, 58, 16, 3)
        bev(s, 20, 20, 36, 24, 'L', 'M', 'S'); s.rect(22, 22, 32, 20, 'W')                       # the work table
        for x in range(22, 54, 8): s.vline(x, 22, 20, 'E')
        limb = [(25, 30, 12, 6, 'S'), (37, 31, 10, 4, 'Q'), (47, 29, 5, 8, 'M')]                  # a half-assembled limb: upper arm, forearm (rust), hand
        for (x, y, w, h, c) in limb: bev(s, x, y, w, h, 'L' if c == 'M' else 'M', c, 'W', cham=False)
        for k in range(4): s.put(48 + (k % 2) * 2, 30 + k, 'L'); s.put(51, 30 + k, 'L')
        ax = [0, 2, 3, 1][i] if on else 0
        for side, (bx, by) in enumerate(((8, 6), (50, 6))):                                    # two jointed robot arms
            dx = 1 if side == 0 else -1
            ex, ey = (bx + dx * (9 + ax * 2), by + 11 - ax), (32 - dx * 4 + (0 if on else -2), 31 if on else 25)
            lcircle(s, bx + 2, by + 2, 5, 'E'); lcircle(s, bx + 2, by + 2, 4, 'S'); lcircle(s, bx + 2, by + 2, 2, 'W'); s.put(bx + 1, by + 1, 'L')
            thick(s, bx + 2, by + 2, ex[0], ex[1], 4, 'S', 'M', 'W'); lcircle(s, ex[0], ex[1], 3, 'M'); lcircle(s, ex[0], ex[1], 1.4, 'E'); s.put(ex[0] - 1, ex[1] - 1, 'L')
            thick(s, ex[0], ex[1], ey[0], ey[1], 3, 'M', 'S', 'W'); s.put(ey[0], ey[1], 'L'); s.put(ey[0] - dx, ey[1] + 1, 'L'); s.put(ey[0] + dx, ey[1] + 1, 'L')
        if on:
            ax_, ay_ = 31 + [0, 1, 0, -1][i], 31
            arc(s, [(ax_ - 3, ay_ - 1), (ax_, ay_ + 1), (ax_ + 3, ay_ - 1)], 'H', 'c', 'C'); s.put(ax_, ay_, 'H')
        for k in range(5):                                                                  # the spares rack
            sx_ = 6 + k * 9
            if k % 2: lcircle(s, sx_ + 3, 52, 3.4, 'M'); lcircle(s, sx_ + 3, 52, 1.5, 'D')
            else: bev(s, sx_, 48, 7, 9, 'M', 'S', 'W', cham=False); s.rect(sx_ + 2, 56, 3, 3, 'u')
        for k in range(3): s.put(54 + k * 3, 10 + 40, 'g' if on and (k + i) % 3 else 'E') if False else None
        s.put(58, 36, 'g' if on else 'E'); s.put(58, 38, 'r' if on and i % 2 else 'E')
        return s
    def hurt(self, s, i):
        stamp_on(s, 44, 8, SCORCH_S); thick(s, 50, 8, 40, 30, 3, 'S', 'M', 'W'); lcircle(s, 40, 30, 2.2, 'M')
        arc(s, [(40, 30), (38, 33), (36, 35)], 'H', 'c', 'C') if i else spark(s, 39, 29, False)
        lcrack(s, [(5, 40), (9, 44), (7, 49)], 'L'); lcrack(s, [(34, 4), (36, 9), (34, 14)], 'L')
        s.stamp(36, 50, art("KKKK.\nKDDDK\n.KDKK")); s.stamp(10, 28, art("SS.\n.SS"))
        s.put(58, 36, 'r'); s.put(58, 38, 'E')
    def wreck(self, s):
        s.rect(3, 3, 58, 22, 'D') if False else None
        lcrack(s, [(3, 11), (7, 15), (6, 20), (11, 24)], 'M'); lcrack(s, [(46, 49), (50, 47), (53, 51), (57, 50)], 'M'); lcrack(s, [(30, 22), (34, 30), (31, 40)], 'M')
        stamp_on(s, 6, 4, SCORCH_L); stamp_on(s, 48, 4, SCORCH_L)
        thick(s, 10, 8, 14, 22, 3, 'W', 'S', 'E'); thick(s, 54, 8, 52, 24, 3, 'W', 'S', 'E')
        for k in range(3): s.put(12 + 3 * k, 56, 'u'); s.put(40 + 4 * k, 58, 'n')
        s.stamp(36, 50, art("KKKK.\nKDDDK\n.KDKK"))
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        glow(g, ox + 31.5 + [0, 1, 0, -1][i], oy + 31.5, 9, RGB_['cyan'], 0.5 * k, 1.8)
        glow(g, ox + 58, oy + 36, 4, RGB_['green'], 0.5 * k, 2.0)

WEAPONS = [ArcHammer, ScrapShotgun, TeslaPicket]
COMPS = [ArcCore, Half2(OverclockEngine(), 'core'), Half2(OverclockEngine(), 'out'), GraftBay]
ALL = WEAPONS + COMPS
