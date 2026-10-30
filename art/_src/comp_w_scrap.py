"""Scrap (Scrapper Clans) line weapons: the standard silhouette, patched: mismatched plates in two greys and rust, bolt heads, weld seams, hazard tape,
exposed pipe and wire, warm amber lamps, slightly asymmetric. Hull mounts: outside half, inside half, rotating barrel."""
from wbase import *
from compose import rotate

FLAP = art("""
....SSM.
..SSMMS.
SSMMSS..
""")
FLASH_BIG = [art("""
...oo...........
..oyyoo.........
.oyyHHyoo.......
.yHHHHHyyoo.....
oyHHHHHHHyyoo...
yHHHHHHHHHHyyoo.
HHHHHHHHHHHHHyyo
HHHHHHHHHHHHHHHy
HHHHHHHHHHHHHyyo
yHHHHHHHHHHyyoo.
oyHHHHHHHyyoo...
.yHHHHHyyoo.....
.oyyHHyoo.......
..oyyoo.........
...oo...........
"""), art("""
..oo..........
.oyyo.........
.yHHyoo.......
oyHHHHyoo.....
yHHHHHHHyyo...
HHHHHHHHHHHyo.
yHHHHHHHyyo...
oyHHHHyoo.....
.yHHyoo.......
.oyyo.........
..oo..........
"""), art("""
.oo......
oyyo.....
yHHyo....
oyyo.....
.oo......
""")]
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

# ============================================================ RATTLE BURST (scrap)
class RattleBurst(Weapon):
    id = 'rattle_burst_scrap'; line = 'scrap'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 45, 22
    bpivot = (8, 10)
    bmuzzle = (32, 10)
    TUBES = ((4, 30, 'MSWE'), (9, 32, 'SWEE'), (14, 28, 'MSSW'))       # top row, tip x, tones: three barrels, three lengths
    out_notes = ('OUTSIDE half of the Rattle Burst (scrap): turret ring, a rust ammo box with the belt of brass rounds feeding the breech, a patched plate with hazard tape and a pipe. '
                 'damaged: ring cracked, belt link hanging, plate peeling; disabled: scorched, dented, the BELT SNAPPED and hanging, sparking.')
    notes = ('INSIDE half of the Rattle Burst (scrap): mismatched capacitor cans, a patched repair hatch, a bare cable stub, amber lamp strip (warm lamps, no clean indicators). '
             'charge: lamps fill; fire: the strip stutters (three quick flashes). damaged: a can dented and leaking, a lamp dead, sparks; disabled: dark, cracked, cable torn. '
             'Barrel layer rattle_burst_scrap_barrel: three welded barrels of different lengths clamped with rust bands and hazard tape. fire: the three barrels flash in turn (a 3-round burst). '
             'Disabled = JAMMED: the middle barrel is bent, a case is stuck in its mouth.')
    def outside(self, s, st):
        pw = st.powered
        turret_seat(s, 32, 15, 'scrap')
        plate(s, 3, 6, 16, 18, 'r')                                           # left: the rust ammo box and its belt
        s.rect(5, 9, 12, 5, 'n'); s.hline(5, 9, 12, 'K')
        for k in range(6): s.put(6 + 2 * k, 11, 'Q'); s.put(6 + 2 * k, 12, 'a')
        s.hline(4, 19, 14, 'W'); weld(s, 4, 21, 14)
        for k, (bx, by) in enumerate(((17, 12), (18, 14), (19, 15), (20, 16), (21, 16), (22, 16))):      # the belt, hanging to the breech
            s.put(bx, by, 'a' if k % 2 else 'Q'); s.put(bx, by + 1, 'q')
        plate(s, 45, 6, 16, 11, 'b'); plate(s, 45, 17, 16, 7, 'a')           # right: patched plates, hazard tape, a pipe
        hazard(s, 46, 18, 14, 3)
        s.rect(56, 8, 2, 8, 'q'); s.vline(56, 8, 8, 'Q'); s.put(57, 7, 'S'); weld(s, 46, 14, 8)
        s.put(48, 9, 'o' if pw else 'E'); s.put(49, 9, 'a' if pw else 'E')
        scrap_ring(s)
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y, 'scrap')
        coupling(s, 3, y + 8, st, 'o')
        for k, (cx, tone) in enumerate(((16, 'LMSWE'), (24, 'QqqnE'), (32, 'LMSWE'))):               # mismatched cans
            cylv(s, cx, y + 6, 6, 15, tone[:5] + tone[4:])
            s.hline(cx - 1, y + 9, 8, 'u'); s.hline(cx - 1, y + 17, 8, 'S'); s.hline(cx - 1, y + 18, 8, 'W')
        weld(s, 40, y + 7, 12, True)
        plate(s, 42, y + 6, 18, 16, 'b'); hatch(s, 46, y + 8, st)
        hazard(s, 44, y + 19, 14, 2)
        s.put(18, y + 12, 'a'); s.put(26, y + 14, 'a')
        wire(s, [(12, y + 4), (14, y + 3), (20, y + 3)], 'u')
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('a', 'o', 'y'))
        if st.state == 'fire': pass
    def hurt_out(self, s, st):
        crack(s, [(28, 5), (29, 8), (27, 11), (28, 15)])
        s.stamp(46, 3, FLAP); wire(s, [(48, 6), (50, 8)])
        for k in range(3): s.put(20, 16 + k, 'a' if k % 2 else 'Q')                # a belt link hanging loose
        spark(s, 50, 2, False) if st.i == 0 else spark(s, 21, 19, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(28, 5), (29, 8), (27, 11), (28, 15), (30, 19)], [(50, 8), (52, 12), (51, 16)]],
                 dents=[(46, 19, 6, 4), (6, 20, 6, 3)], soots=[(21, 3, 0), (46, 6, 2), (4, 8, 1)], wires_=[], sparks=[(24, 18), (52, 5)], flap=(46, 3))
        for k in range(5): s.put(17 + k, 12 + k // 2, 'n'); s.put(17 + k, 13 + k // 2, 'n')        # the belt: snapped, two dead ends
        s.rect(21, 14, 3, 4, '.')
        for k in range(4): s.put(20 + (k % 2), 17 + k, 'u' if k % 2 else 'n')
        s.put(23, 19, 'a'); s.put(24, 21, 'Q'); s.put(22, 23, 'a')                  # loose rounds
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        dent(s, 25, y + 7, 5, 4)
        for k in range(3): s.put(27, y + 21 + k, 'a')                                # leaking oil / a dripping round
        spark(s, 27, y + 12, False) if st.i == 0 else spark(s, 12, y + 4, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(24, y + 6), (26, y + 11), (25, y + 17)]); crack(s, [(48, y + 8), (51, y + 11), (50, y + 14)])
        wire(s, [(14, y + 20), (16, y + 23), (22, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, ready_rgb=(255, 190, 60), live_rgb=(255, 138, 30))
        glow(g, ox + 12, oy + y + 14, 3, (255, 138, 30), 0.5, 2.0)
        if state in ('on', 'damaged'):
            for (x, yy) in ((18, y + 12), (26, y + 14)): glow(g, ox + x + 0.5, oy + yy + 0.5, 3, (255, 138, 30), 0.4, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 48.5, oy + 9.5, 3, (255, 190, 60), 0.5, 2.0)
    # ---- barrel
    def barrel(self, b, st):
        o = -st.rc
        for k, (ty, tx, tones) in enumerate(self.TUBES):
            cylh(b, 12 + o, ty, tx - 11, 4, tones)
            b.rect(tx - 1 + o, ty, 2, 4, 'D')
            if st.fire and st.i == k: b.rect(tx - 1 + o, ty, 2, 4, 'o'); b.put(tx + o, ty + 1, 'H'); b.put(tx + o, ty + 2, 'H')
        for bx in (16, 25):                                                       # rust clamps
            b.rect(bx + o, 3, 3, 16, 'u'); b.vline(bx + o, 3, 16, 'Q'); b.vline(bx + o + 2, 3, 16, 'n')
            for by in (4, 11, 17): b.put(bx + o + 1, by, 'L')
        hazard(b, 20 + o, 3, 4, 16)
        weld(b, 13 + o, 8, 3); weld(b, 27 + o, 13, 3)
        hub(b, 10, 17)
        pod(b, 10, 0)                                                             # sensor pod: the turret aims itself
    def bhurt(self, b, st):
        b.rect(25, 3, 3, 16, '.'); b.rect(25, 3, 3, 1, 'u')                      # a clamp torn off ...
        wire(b, [(26, 4), (27, 5)]); b.stamp(24, 18, art("uuu\nQuQ\nnnn"))      # ... hanging
        for k in range(4): b.put(19 + k, 19 + (k % 2), 'a' if k % 2 else 'D')   # hazard tape peeling off
        b.put(31, 10, 'Q'); b.put(32, 10, 'q')                                    # a case stuck in the middle bore
        crack(b, [(17, 4), (18, 8), (17, 12)])
        spark(b, 28, 19, False) if st.i == 0 else spark(b, 32, 12, False)
    def bbreak(self, b, st):
        """jammed: the middle barrel is bent upward at the clamp and its mouth is choked with a stuck case."""
        keep = Spr(self.blen, self.bwid); keep.g = [r[:] for r in b.g]
        for y in range(9, 13):
            for x in range(21, 34): b.erase(x, y)
        for x in range(21, 34):
            for y in range(9, 13):
                c = keep.get(x, y)
                if c != '.': b.put(x + 1, y - 3 + (-1 if x > 27 else 0), c)
        for (x, y) in ((26, 7), (27, 6), (28, 7)): b.put(x, y, 'K')
        return b
    def bwreck(self, b, st):
        b.stamp(32, 5, art("QQ\nqQ"))
        crack(b, [(17, 5), (18, 9), (17, 13), (18, 17)], 'K', 'S')
        b.put(24, 7, 'u'); b.put(25, 6, 'n')
        for k in range(3): b.put(34, 12 + k, 'a' if k % 2 else 'Q')
    def bafter(self, b, st):
        if st.fire:
            ty, tx, _ = self.TUBES[st.i]
            stamp_flash(b, st, tx, ty + 2, FLASH_S3)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            ty, tx, _ = self.TUBES[i]
            glow(g, ox + tx + 3, oy + ty + 2.5, 9, (255, 150, 40), 0.6, 2.0, sx=1.3)
            glow(g, ox + tx + 2, oy + ty + 2.5, 4, (255, 235, 160), 0.7, 1.6)

FLASH_S3 = [art("""
..o......
.oyo.....
oyHyoo...
yHHHHyo..
oyHyoo...
.oyo.....
..o......
"""), art("""
.o.......
oyo......
yHyoo....
oyo......
.o.......
"""), art("""
.o.....
oyo....
.o.....
""")]
FLASH_S3 = FLASH_S3  # (one flash per tube, centred on its row)

# ============================================================ SHRAPNEL CANNON (scrap, heavy 4x6)
class ShrapnelCannon(Weapon):
    id = 'shrapnel_cannon_scrap'; line = 'scrap'
    cells = (4, 2); out_cells = (4, 3)
    pivot = (32, 16)
    blen, bwid = 70, 31
    bpivot = (6, 15)
    bmuzzle = (50, 15)
    out_notes = ('OUTSIDE half of the Shrapnel Cannon (scrap, heavy: 64x48): a big turret ring with the scrap hopper (junk visible in it) and a rust pressure tank. '
                 'damaged: ring cracked, hopper rim torn; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Shrapnel Cannon (scrap): the funnel spout that feeds the breech with scrap, mismatched cans, repair hatch, amber lamp strip. '
             'charge: lamps fill; fire: the strip stutters. damaged: spout dented, lamps dead; disabled: dark, cracked. '
             'Barrel layer shrapnel_cannon_scrap_barrel: a fat flak mortar tube with a flared mouth, rust bands, hazard tape; fire: a big flash with scrap flying.')
    def outside(self, s, st):
        pw = st.powered
        gun_housing(s, 'scrap', 48, 16, 32, 34)
        plate(s, 2, 9, 20, 26, 'r')                                            # left: the hopper
        s.rect(4, 11, 16, 14, 'n'); s.hline(4, 11, 16, 'K'); s.vline(4, 11, 14, 'K')
        for k, (jx, jy) in enumerate(((5, 12), (10, 13), (15, 12), (7, 17), (12, 18), (16, 17), (6, 21), (13, 22))): junk(s, jx, jy, k)
        bev(s, 5, 26, 14, 6, 'S', 'W', 'E', cham=False); s.hline(7, 29, 10, 'D')       # the spout
        weld(s, 4, 33, 16); hazard(s, 3, 34, 18, 2)
        plate(s, 52, 9, 10, 24, 'b'); s.rect(55, 12, 4, 17, 'q'); s.vline(55, 12, 17, 'Q'); s.vline(58, 12, 17, 'n')   # right: pressure tank
        for k in (14, 20, 26): s.hline(54, k, 6, 'S')
        s.put(53, 11, 'o' if pw else 'E'); weld(s, 53, 31, 8)
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y, 'scrap')
        coupling(s, 3, y + 8, st, 'o')
        bev(s, 16, y + 4, 14, 8, 'S', 'W', 'E', cham=False)                    # the funnel spout feeding the breech
        s.hline(18, y + 8, 10, 'D')
        for k, (jx, jy) in enumerate(((19, y + 14), (24, y + 15), (29, y + 14))): junk(s, jx, jy, k + 1)
        cylv(s, 34, y + 6, 8, 15, 'LMSWWE'); s.hline(33, y + 10, 10, 'u'); s.hline(33, y + 17, 10, 'S')
        plate(s, 46, y + 6, 14, 16, 'a'); hatch(s, 47, y + 8, st, 11, 9)
        hazard(s, 46, y + 19, 14, 2)
        weld(s, 15, y + 20, 18)
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('a', 'o', 'y'))
    def hurt_out(self, s, st):
        crack(s, [(31, 8), (32, 14), (30, 20), (32, 26)])
        for k in range(4): s.put(6 + 3 * k, 11, '.')                              # the hopper rim torn
        s.stamp(53, 5, FLAP); wire(s, [(55, 8), (57, 10)])
        spark(s, 12, 11, False) if st.i == 0 else spark(s, 57, 4, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 8), (32, 14), (30, 20), (32, 26), (31, 32)], [(8, 14), (9, 22)]],
                 dents=[(55, 31, 5, 4), (7, 28, 7, 3)], soots=[(24, 9, 0), (4, 12, 1), (53, 14, 2)],
                 wires_=[[(18, 26), (20, 30), (19, 35)]], sparks=[(30, 12), (14, 20)], flap=(53, 5))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        dent(s, 18, y + 5, 7, 5)
        crack(s, [(36, y + 6), (38, y + 11), (37, y + 16)])
        spark(s, 37, y + 12, False) if st.i == 0 else spark(s, 24, y + 14, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(36, y + 6), (38, y + 11), (37, y + 16), (39, y + 20)]); crack(s, [(50, y + 8), (53, y + 11)])
        wire(s, [(14, y + 20), (17, y + 23), (24, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, ready_rgb=(255, 190, 60), live_rgb=(255, 138, 30))
        glow(g, ox + 12, oy + y + 14, 3, (255, 138, 30), 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 53.5, oy + 11.5, 3, (255, 190, 60), 0.5, 2.0)
    # ---- barrel: a fat flak mortar
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 14 + o, 6, 30, 19, 'LMMSSSSSWWWEE')                            # tube, rows 6..24
        for bx in (20, 32):
            b.rect(bx + o, 4, 4, 23, 'u'); b.vline(bx + o, 4, 23, 'Q'); b.vline(bx + o + 3, 4, 23, 'n')
            for by in (6, 15, 24): b.put(bx + o + 1, by, 'L')
        hazard(b, 25 + o, 5, 5, 21)
        plate(b, 36 + o, 8, 7, 6, 'b'); weld(b, 37 + o, 18, 6)
        for k, (fx, h) in enumerate(((44, 21), (46, 23), (48, 25))):               # the flared mouth
            b.rect(fx + o, 15 - h // 2, 2, h, ('S', 'M', 'L')[k] if False else 'S'); b.vline(fx + o, 15 - h // 2, h, 'M'); b.vline(fx + o + 1, 15 - h // 2, h, 'W')
        b.rect(50 + o, 4, 2, 23, 'W'); b.vline(50 + o, 4, 23, 'a'); b.put(50 + o, 15, 'a')
        b.rect(47 + o, 8, 5, 15, 'D')                                              # the dark bore
        if st.fire: b.rect(48 + o, 9, 4, 13, 'o'); b.rect(49 + o, 11, 3, 9, 'y'); b.rect(50 + o, 13, 2, 5, 'H')
        breech(b, 15, 21)
    def bhurt(self, b, st):
        crack(b, [(46, 5), (48, 9), (47, 13)]); crack(b, [(22, 8), (23, 14), (22, 20)])
        b.rect(32, 4, 4, 23, '.'); b.rect(32, 4, 4, 1, 'u')                      # a band torn off, hanging by a wire
        wire(b, [(33, 5), (34, 6)]); b.stamp(32, 26, art("uuuu\nQuuQ\nnnnn")); wire(b, [(33, 25), (34, 27)])
        for k in range(5): b.put(26 + k, 27 + (k % 2), 'a' if k % 2 else 'D')    # hazard tape peeling
        spark(b, 35, 28, False) if st.i == 0 else spark(b, 49, 6, False)
    def bbreak(self, b, st):
        return cleave(b, lambda y: 43, 3, 3)                                        # the mouth cracked off and sagging
    def bwreck(self, b, st):
        for y in (9, 15, 21): wire(b, [(42, y), (44, y + 1), (46, y + 1)], 'u')
        crack(b, [(49, 6), (50, 12), (49, 18), (51, 24)], 'K', 'S')
        b.rect(51, 11, 3, 5, 'D')
    def bafter(self, b, st):
        if st.fire:
            stamp_flash(b, st, 52, 15, FLASH_BIG)
            if st.i < 2:
                for (x, y, c) in ((58, 8, 'S'), (62, 12, 'u'), (60, 20, 'M'), (66, 15, 'L'), (64, 23, 'S'), (57, 24, 'u'), (63, 6, 'M')):
                    b.put(x + st.i * 2 - st.rc, y + (st.i * (1 if y > 15 else -1)), c)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 52, 15, (255, 140, 40), (255, 235, 160), 1.3, 1.5)

# ============================================================ BOLT THROWER (scrap)
class BoltThrower(Weapon):
    id = 'bolt_thrower_scrap'; line = 'scrap'
    blen, bwid = 54, 21
    bpivot = (6, 10)
    bmuzzle = (41, 10)
    out_notes = ('OUTSIDE half of the Bolt Thrower (scrap): turret ring and the scrap HOPPER (a round funnel, junk visible in it) on the left, patched plates and a pipe on the right. '
                 'damaged: ring cracked, hopper rim bent; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Bolt Thrower (scrap): the FEED CHUTE to the right edge, where an ammo rack (scrap) sits beside it; charge: a scrap chunk rides the chute into the breech, lamps fill; '
             'fire: lamps stutter. damaged: chute dented, lamps dead; disabled: a chunk jammed in the chute. '
             'Barrel layer bolt_thrower_scrap_barrel: a crude launcher tube with a piece of scrap seated in its mouth; fire: the scrap flies out in a puff of smoke.')
    def outside(self, s, st):
        pw = st.powered
        gun_housing(s, 'scrap')
        plate(s, 3, 6, 16, 18, 'r')                                           # the hopper: a round funnel full of junk
        chamfer_fill(s, 4, 7, 14, 14, 'W', 4); rim(s, 'W', 'S', 'E', (4, 7, 17, 20))
        chamfer_fill(s, 6, 9, 10, 10, 'D', 3)
        for k, (jx, jy) in enumerate(((7, 10), (11, 10), (8, 14), (12, 14), (10, 17))): junk(s, jx, jy, k)
        weld(s, 4, 22, 14); s.put(3, 13, 'o' if pw else 'E')
        plate(s, 45, 6, 16, 10, 'b'); plate(s, 45, 16, 16, 8, 'a'); hazard(s, 46, 17, 14, 3)
        s.rect(56, 8, 2, 8, 'q'); s.vline(56, 8, 8, 'Q'); weld(s, 47, 13, 8)
        s.put(48, 9, 'o' if pw else 'E'); s.put(49, 9, 'a' if pw else 'E')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y, 'scrap')
        coupling(s, 3, y + 8, st, 'o')
        cylv(s, 16, y + 6, 12, 15, 'LMSSSSWWWWEE'); s.hline(15, y + 9, 14, 'u'); s.hline(15, y + 17, 14, 'S')   # the breech
        weld(s, 29, y + 7, 12, True)
        bev(s, 33, y + 6, 30, 14, 'W', 'E', 'D', cham=False)                   # the feed chute out to the ammo rack
        s.rect(33, y + 9, 30, 8, 'D'); s.hline(33, y + 9, 30, 'K'); s.hline(33, y + 16, 30, 'S')
        for k in range(3):
            for q, (dx, dy) in enumerate(((1, 0), (0, 1), (1, 2))): s.put(54 + 3 * k + dx, y + 11 + dy, 'a')
        chunk = {'on': 36, 'off': 36, 'damaged': 36, 'charge': (None, 52, 46, 41, 38, 36)[st.i] if st.charge else None, 'disabled': 46}.get(st.state)
        if chunk is not None:
            junk(s, chunk, y + 11, 1); junk(s, chunk + 3, y + 12, 3) if chunk < 50 else None
        hatch(s, 18, y + 20, st, 9, 3) if False else None
        s.hline(4, y + 25, 2, 'W'); s.hline(7, y + 25, 3, 'W')
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('a', 'o', 'y'))
    def hurt_out(self, s, st):
        crack(s, [(28, 5), (29, 8), (27, 11), (28, 15)])
        for k in range(3): s.erase(5 + 3 * k, 7)
        s.stamp(46, 3, FLAP); wire(s, [(48, 6), (50, 8)])
        spark(s, 11, 6, False) if st.i == 0 else spark(s, 50, 2, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(28, 5), (29, 8), (27, 11), (28, 15), (30, 19)], [(8, 9), (12, 12), (9, 17)]],
                 dents=[(46, 17, 6, 4), (14, 20, 4, 3)], soots=[(21, 3, 1), (46, 6, 0), (4, 8, 2)], wires_=[[(18, 14), (19, 18), (18, 22)]],
                 sparks=[(10, 14), (52, 6)], flap=(46, 3))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        dent(s, 40, y + 6, 6, 4); crack(s, [(21, y + 6), (22, y + 11), (21, y + 16)])
        spark(s, 22, y + 12, False) if st.i == 0 else spark(s, 40, y + 14, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(21, y + 6), (22, y + 11), (21, y + 16), (23, y + 20)]); crack(s, [(46, y + 7), (48, y + 12)])
        wire(s, [(14, y + 20), (17, y + 23), (24, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, ready_rgb=(255, 190, 60), live_rgb=(255, 138, 30))
        glow(g, ox + 12, oy + y + 14, 3, (255, 138, 30), 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 3.5, oy + 13.5, 3, (255, 138, 30), 0.5, 2.0); glow(g, ox + 48.5, oy + 9.5, 3, (255, 190, 60), 0.5, 2.0)
    # ---- barrel
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 12 + o, 4, 26, 13, 'MMSSSWWWWEEEE')                          # a crude tube
        for bx in (16, 28): b.rect(bx + o, 3, 3, 15, 'u'); b.vline(bx + o, 3, 15, 'Q'); b.vline(bx + o + 2, 3, 15, 'n'); b.put(bx + o + 1, 5, 'L'); b.put(bx + o + 1, 15, 'L')
        plate(b, 20 + o, 5, 7, 6, 'b'); weld(b, 20 + o, 14, 8)
        b.rect(37 + o, 3, 3, 15, 'W'); b.vline(37 + o, 3, 15, 'M'); b.vline(40 + o, 4, 13, 'W')   # the rough, flared lip
        b.rect(39 + o, 5, 2, 11, 'D')
        sc = {'fire': (None, None, None)}.get(st.state, (1,))
        if not st.fire: junk(b, 38 + o, 9, 1); b.put(41 + o, 10, 'u')
        if st.fire:
            hx = (44, 50, None)[st.i]
            if hx: junk(b, hx - st.rc, 8, 3 - st.i); junk(b, hx - st.rc + 3, 12, 1 + st.i)
            for (x, y) in ((40, 6), (42, 14)): b.stamp(x + st.i * 2, y, SMOKE[st.i % 2])
        breech(b, 10, 15)
    def bhurt(self, b, st):
        crack(b, [(18, 4), (19, 8), (18, 12)])
        b.rect(28, 3, 3, 15, '.'); b.rect(28, 3, 3, 1, 'u'); wire(b, [(29, 4), (30, 5)])
        b.stamp(28, 17, art("uuu\nQuQ\nnnn")); wire(b, [(29, 16), (30, 18)])
        for k in range(4): b.put(21 + k, 18 + (k % 2), 'a' if k % 2 else 'D')
        spark(b, 31, 19, False) if st.i == 0 else spark(b, 19, 6, False)
    def bbreak(self, b, st):
        return cleave(b, lambda y: 27, 2, 3)
    def bwreck(self, b, st):
        for y in (6, 11): wire(b, [(26, y), (28, y + 1), (30, y + 1)], 'u')
        crack(b, [(38, 5), (39, 9), (38, 13)], 'K', 'S')
        junk(b, 39, 18, 1)
    def bafter(self, b, st):
        if st.fire and st.i < 2: stamp_flash(b, st, 41, 10, FLASH_S3 if False else FLASH_S3)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 41, 10, (255, 150, 40), scale=0.7)

ALL = [RattleBurst, ShrapnelCannon, BoltThrower]
