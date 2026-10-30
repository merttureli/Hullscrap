"""Standard (Concord) line weapons: clean, symmetrical, tidy seams, a registry stencil, indicator lights in the family colour.
Hull mounts (4x5): outside | wall collar | inside, plus the rotating barrel layer."""
from wbase import *
from compose import rotate

FLAP = art("""
....SSM.
..SSMMS.
SSMMSS..
""")

# ============================================================ LASER MK2
class LaserMk2(Weapon):
    id = 'laser_mk2'
    blen, bwid = 58, 25
    bpivot = (6, 12)
    bmuzzle = (43, 12)
    out_notes = 'OUTSIDE half of the Laser Mk2: steel capacitors with magenta bands, twin sensor masts. damaged: ring cracked, cover flapping; disabled: scorched, dented, sparking.'
    notes = ('INSIDE half of the Laser Mk2: three steel capacitors, repair hatch, power coupling, 5-cell strip plus a second row of magenta pips (the Mk2 accent). '
             'charge: frame round(fraction*5), 5 = ready; fire: strip discharge. Barrel layer laser_mk2_barrel: twin emitter rails with a fork gap, magenta trim; '
             'damaged: rail cracked, lower emitter cap hangs by a wire; disabled: the top rail snaps and droops into the fork.')
    def outside(self, s, st):
        pw = st.powered
        gun_housing(s)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')                                   # left wing: capacitors
        for cx in (6, 9, 12):
            cylv(s, cx, 8, 3, 14, 'LSW')
            s.hline(cx, 13, 3, 'E'); s.hline(cx, 14, 3, 'm' if pw else 'W'); s.hline(cx, 15, 3, 'E')
        s.put(3, 13, 'g' if pw else 'E'); s.put(3, 14, 'g' if pw else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')                                  # right wing: twin masts and vents
        s.rect(48, 2, 4, 4, 'W'); s.put(48, 2, 'M'); s.put(49, 1, 'c' if pw else 'E')
        s.rect(55, 2, 4, 4, 'W'); s.put(55, 2, 'M'); s.put(56, 1, 'm' if pw else 'E')
        for vx in (48, 53): s.rect(vx, 10, 5, 2, 'D')
        s.rect(48, 15, 10, 1, 'D'); s.rect(48, 18, 10, 1, 'D')
        s.hline(48, 21, 3, 'W'); s.hline(52, 21, 2, 'W'); s.hline(55, 21, 3, 'W')   # registry stencil
        bolts(s, [(47, 8), (58, 8), (47, 22), (58, 22)])
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y)
        coupling(s, 3, y + 8, st)
        for k, cy in enumerate((y + 6, y + 12, y + 18)):                       # three steel capacitors
            cylh(s, 16, cy, 24, 5, 'LMSWE')
            s.vline(16, cy, 5, 'S'); s.vline(39, cy, 5, 'W')
            s.vline(29, cy, 5, 'E'); s.vline(30, cy, 5, 'm' if pw else 'W'); s.vline(31, cy, 5, 'E')
        bev(s, 42, y + 6, 19, 16, 'M', 'S', 'W')
        hatch(s, 46, y + 8, st)
        for vx in (45, 49, 53, 57): s.rect(vx, y + 19, 3, 1, 'D')
        s.hline(4, y + 25, 2, 'W'); s.hline(7, y + 25, 3, 'W'); s.hline(55, y + 25, 3, 'W'); s.hline(59, y + 25, 2, 'W')
        strip(s, st, STRIP_X, y + STRIP_DY)
        for k in range(5):                                                      # second accent: magenta pips
            on = pw and (k < st.lit or st.ready)
            s.rect(STRIP_X + 8 * k + 2, y + STRIP_DY + 4, 2, 1, 'm' if on else 'E')
    def hurt_out(self, s, st):
        crack(s, [(31, 4), (30, 8), (32, 11), (30, 14), (31, 17)])             # turret ring cracked
        crack(s, [(52, 6), (53, 9), (51, 12)])
        s.stamp(2, 5, FLAP); wire(s, [(10, 6), (12, 7), (14, 7)])
        spark(s, 10, 4, False) if st.i == 0 else spark(s, 56, 3, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 4), (30, 8), (32, 11), (30, 14), (31, 17), (33, 22)], [(52, 7), (53, 10), (51, 14)]],
                 dents=[(7, 17, 6, 5), (50, 14, 6, 4)], soots=[(22, 3, 1), (44, 5, 0), (5, 8, 2)],
                 wires_=[[(56, 6), (58, 9), (57, 12)]], sparks=[(26, 8), (56, 4)], flap=(2, 5))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        for k in (3, 4): s.rect(STRIP_X + 8 * k + 2, y + STRIP_DY + 4, 2, 1, 'E')
        crack(s, [(20, y + 6), (21, y + 10), (19, y + 14)])
        spark(s, 21, y + 12, False) if st.i == 1 else spark(s, 52, y + 14, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(25, y + 6), (24, y + 10), (26, y + 14), (24, y + 20)]); crack(s, [(46, y + 8), (49, y + 11), (48, y + 14)])
        wire(s, [(14, y + 19), (16, y + 22), (19, y + 23)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        lit = {'charge': i, 'on': 5, 'damaged': 3}.get(state, 0)
        for k in range(5):
            if k < lit or (state == 'charge' and i == 5): glow(g, ox + STRIP_X + 8 * k + 3, oy + y + STRIP_DY + 4.5, 3.5, (255, 79, 216), 0.45, 2.0)
        glow(g, ox + 12, oy + y + 14, 3, (107, 211, 74), 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 3.5, oy + 14, 4, (107, 211, 74), 0.5, 2.0)
        glow(g, ox + 49.5, oy + 1.5, 3, (60, 242, 255), 0.5, 2.0); glow(g, ox + 56.5, oy + 1.5, 3, (255, 79, 216), 0.5, 2.0)
    # ---- barrel
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 11 + o, 1, 6, 23, 'M', 'S', 'W')                                # rail coupling bridge
        b.rect(13 + o, 8, 3, 9, 'D'); b.hline(13 + o, 8, 3, 'K')
        for ry, ly in ((2, 3), (18, 19)):                                      # the twin rails
            cylh(b, 17 + o, ry, 25, 5, 'LMSWE')
            for bx in (21, 27, 33): bev(b, bx + o, ry - 1, 3, 7, 'L', 'M', 'S', cham=False); b.vline(bx + o + 2, ry - 1, 7, 'W')
            bev(b, 39 + o, ry - 1, 5, 7, 'S', 'E', 'D')
            lens(b, 41 + o, ly, 3, 3, st.fire)
        for x in range(17, 39):                                                # magenta trim on the inner faces
            if x not in (21, 22, 23, 27, 28, 29, 33, 34, 35): b.put(x + o, 7, 'm'); b.put(x + o, 17, 'm')
        breech(b, 12, 15)
    def bhurt(self, b, st):
        crack(b, [(22, 2), (23, 4), (22, 6)]); crack(b, [(30, 2), (31, 4), (30, 6)])
        move(b, 39, 17, 6, 7, 1, 4)                                            # lower emitter cap hangs by a wire
        wire(b, [(38, 21), (40, 23)]); b.put(40, 23, 'u')
        spark(b, 43, 24, False) if st.i == 0 else spark(b, 23, 4, False)
    def bbreak(self, b, st):
        for y in (2, 4, 6): b.erase(32, y)
        return cleave(b, lambda y: 33, 2, 3, rows=(0, 10))                     # the top rail snaps and droops into the fork
    def bwreck(self, b, st):
        wire(b, [(31, 4), (33, 6), (35, 7)])
        for (x, y) in ((30, 1), (31, 3), (29, 6)): b.put(x, y, 'K')
        crack(b, [(15, 3), (15, 8), (14, 12)])
    def bafter(self, b, st):
        if st.fire:
            for cy in (4, 20): stamp_flash(b, st, 43, cy, FLASH_S)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            for cy in (4, 20): fire_glow(g, ox, oy, i, 43, cy, scale=0.75)
        if state == 'damaged' and i == 0: glow(g, ox + 43, oy + 4.5, 4, (255, 80, 60), 0.4, 2.0)
        if state in ('idle', 'damaged'):
            glow(g, ox + 28, oy + 7.5, 5, (255, 79, 216), 0.18, 2.0, sx=2.8); glow(g, ox + 28, oy + 17.5, 5, (255, 79, 216), 0.18, 2.0, sx=2.8)

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


# ============================================================ PULSE MK1 / MK2
CH_A = [(0, -6), (5, -3), (5, 3), (0, 6), (-5, 3), (-5, -3)]     # chamber centres relative to the drum centre, clockwise
CH_B = [(3, -5), (6, 0), (3, 5), (-3, 5), (-6, 0), (-3, -5)]     # the drum indexed half a step
DRUM_N = [0, 2, 3, 4, 5, 6]                                       # chambers loaded per charge frame
class Pulse(Weapon):
    shroud = False
    blen, bwid = 52, 21
    bpivot = (6, 10)
    def outside(self, s, st):
        pw = st.powered
        gun_housing(s)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')                                   # left wing: plasma vent block
        for sx in (6, 9, 12):
            s.rect(sx, 8, 2, 14, 'D'); s.vline(sx, 8, 14, 'K'); s.vline(sx + 2, 8, 14, 'M')
            if self.shroud and pw:
                for fy in (11, 15, 19): s.put(sx + 1, fy, 'b')
        s.put(3, 13, 'a' if pw else 'E'); s.put(3, 14, 'a' if pw and (st.state != 'on' or st.i == 0) else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')                                  # right wing: plasma gauge
        s.rect(48, 9, 10, 6, 'D'); s.hline(48, 9, 10, 'K')
        for k in range(4): s.rect(49 + 2 * k, 11, 1, 3, ('a' if pw and k < 3 + (st.i % 2 if st.state == 'on' else 0) else 'E'))
        s.hline(48, 19, 3, 'W'); s.hline(52, 19, 2, 'W'); s.hline(55, 19, 3, 'W')   # registry stencil
        bolts(s, [(47, 8), (58, 8), (47, 22), (58, 22)])
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y)
        coupling(s, 3, y + 8, st, 'a')
        cx, cy = 29, y + 13
        chamfer_fill(s, cx - 9, cy - 9, 19, 19, 'S', 6); rim(s, 'S', 'M', 'W', (cx - 9, cy - 9, cx + 9, cy + 9))   # the revolving drum
        chamfer_fill(s, cx - 7, cy - 7, 15, 15, 'E', 5); rim(s, 'E', 'D', 'M', (cx - 7, cy - 7, cx + 7, cy + 7))
        chamfer_fill(s, cx - 2, cy - 2, 5, 5, 'M', 1); rim(s, 'M', 'L', 'S', (cx - 2, cy - 2, cx + 2, cy + 2)); s.put(cx, cy, 'E')
        if self.shroud:
            for (dx, dy) in ((0, -8), (0, 8), (-8, 0), (8, 0)): s.put(cx + dx, cy + dy, 'a' if pw else 'W')
        pat = CH_B if (st.charge and st.i % 2) or (st.fire and st.i == 0) else CH_A
        n = 6 if st.state == 'on' else {'charge': DRUM_N[st.i], 'damaged': 3}.get(st.state, 0)
        for k, (dx, dy) in enumerate(pat):
            x0, y0 = cx + dx - 1, cy + dy - 1
            for (qx, qy) in ((1, 0), (0, 1), (1, 1), (2, 1), (1, 2)):          # a round chamber: a plus of 3x3
                s.put(x0 + qx, y0 + qy, ('o' if (qx, qy) != (1, 1) else ('H' if st.ready else 'y')) if k < n and pw else 'D')
            if not (k < n and pw): s.put(x0 + 1, y0, 'K')
        hatch(s, 46, y + 8, st)
        s.hline(4, y + 25, 2, 'W'); s.hline(7, y + 25, 3, 'W'); s.hline(55, y + 25, 3, 'W'); s.hline(59, y + 25, 2, 'W')
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('a', 'u', 'y'))
    def hurt_out(self, s, st):
        crack(s, [(28, 5), (29, 8), (27, 11), (28, 14)])
        crack(s, [(50, 7), (52, 10), (50, 14)])
        s.stamp(2, 5, FLAP); wire(s, [(10, 6), (12, 7), (14, 7)])
        spark(s, 10, 4, False) if st.i == 0 else spark(s, 54, 8, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(28, 5), (29, 8), (27, 11), (28, 14), (30, 18), (29, 22)], [(50, 7), (52, 10), (50, 14)]],
                 dents=[(6, 17, 5, 5), (51, 16, 6, 4)], soots=[(21, 3, 2), (44, 6, 1), (4, 7, 0)],
                 wires_=[[(14, 6), (16, 9), (15, 12)]], sparks=[(35, 5), (8, 11)], flap=(2, 5))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(34, y + 6), (36, y + 9), (35, y + 12)])                              # the drum rim cracked
        s.stamp(31, y + 11, art("QQq\nqQQ\n.nq"))                                      # a bent casing jams a chamber
        spark(s, 36, y + 10, False) if st.i == 0 else spark(s, 50, y + 20, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(26, y + 5), (28, y + 9), (27, y + 13), (30, y + 17), (29, y + 21)]); crack(s, [(35, y + 9), (37, y + 13)])
        for (x, yy) in ((22, y + 24), (26, y + 23), (33, y + 24)): s.rect(x, yy, 2, 1, 'q')       # spilled casings
        wire(s, [(14, y + 18), (16, y + 21)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy; cx, cy = 29, y + 13
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, ready_rgb=(255, 190, 60), live_rgb=(255, 150, 40))
        pat = CH_B if (state == 'charge' and i % 2) or (state == 'fire' and i == 0) else CH_A
        n = 6 if state == 'on' else {'charge': DRUM_N[i], 'damaged': 3}.get(state, 0)
        for k, (dx, dy) in enumerate(pat):
            if k < n: glow(g, ox + cx + dx + 0.5, oy + cy + dy + 0.5, 5, (255, 190, 60), 0.6, 2.0)
        glow(g, ox + 3.5, oy + y + 13, 4, (255, 190, 60), 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 3.5, oy + 13.5, 4, (255, 190, 60), 0.5, 2.0)
        for k in range(3): glow(g, ox + 50 + 2 * k, oy + 12.5, 3.5, (255, 190, 60), 0.35, 2.0)
        if self.shroud:
            for sx in (6, 9, 12): glow(g, ox + sx + 1.5, oy + 15, 5, (79, 163, 255), 0.18, 2.0)
    # ---- barrel
    def barrel(self, b, st):
        o = -st.rc
        if self.shroud:
            cylh(b, 11 + o, 5, 4, 11)
            bev(b, 13 + o, 1, 18, 19, 'M', 'S', 'W')
            for fx in (16, 19, 22, 25):
                b.rect(fx + o, 3, 2, 15, 'D'); b.vline(fx + o, 3, 15, 'K')
                for fy in (6, 10, 14): b.put(fx + o + 1, fy, 'b')
            bolts(b, [(14 + o, 2), (14 + o, 18), (29 + o, 2), (29 + o, 18)])
            bev(b, 31 + o, 4, 8, 13, 'S', 'E', 'D'); sx0, sw, sy = 35, 3, 7
        else:
            cylh(b, 11 + o, 4, 17, 13)
            for bx in (15, 20): band(b, bx + o, 3, 15, 2, 'L', 'W')
            bev(b, 26 + o, 2, 11, 17, 'S', 'E', 'D'); bolts(b, [(28 + o, 3), (28 + o, 17)]); sx0, sw, sy = 32, 4, 6
        b.rect(sx0 + o, sy, sw, 9, 'D')
        if st.fire:
            b.rect(sx0 + o, sy, sw, 9, 'o'); b.rect(sx0 + o + 1, sy + 1, sw - 1, 7, 'y'); b.rect(sx0 + o + sw - 2, sy + 2, 2, 5, 'H')
        else: b.put(sx0 + o + sw - 1, sy + 4, 'a')
        breech(b, 10, 15)
    def bhurt(self, b, st):
        crack(b, [(20, 2), (22, 5), (21, 8)] if self.shroud else [(30, 3), (31, 7), (30, 11), (32, 15)])
        if self.shroud:
            move(b, 31, 4, 8, 13, 0, 2); wire(b, [(31, 17), (32, 19)])
        else:
            move(b, 26, 2, 11, 17, 0, 2); wire(b, [(26, 18), (27, 20)])
        spark(b, 35, 19, False) if st.i == 0 else spark(b, 21, 7, False)
    def bbreak(self, b, st):
        return cleave(b, lambda y: 24 if not self.shroud else 31, 2, 3)
    def bwreck(self, b, st):
        x0 = 22 if not self.shroud else 29
        for y in (6, 12): wire(b, [(x0, y), (x0 + 2, y + 1), (x0 + 3, y + 1)])
        crack(b, [(x0 + 6, 5), (x0 + 8, 9), (x0 + 7, 13)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 36 if not self.shroud else 38, 10)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 36 if not self.shroud else 38, 10, (255, 150, 40))
        if state == 'damaged' and i == 0: glow(g, ox + 33, oy + 10.5, 4, (255, 150, 40), 0.4, 2.0)

class PulseMk1(Pulse):
    id = 'pulse_mk1'; bmuzzle = (36, 10)
    out_notes = ('OUTSIDE half of the Pulse Mk1: turret ring, plasma vent block (amber lamps) and a plasma gauge. damaged: ring cracked, vent cover flapping; '
                 'disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Pulse Mk1: the revolving six-chamber drum IS the charge indicator: charge frame i loads (0,2,3,4,5,6) chambers and indexes the drum half a step '
             'on odd frames; frame 5 = ready (all lit, centre pixel white). Plus power coupling, repair hatch and an amber strip. fire: the drum is spent (empty chambers). '
             'damaged: drum rim cracked, a bent casing jams a chamber; disabled: drum split, casings spilled. Barrel layer pulse_mk1_barrel: stubby plasma barrel.')
class PulseMk2(Pulse):
    id = 'pulse_mk2'; shroud = True; bmuzzle = (38, 10)
    out_notes = 'OUTSIDE half of the Pulse Mk2: as the Mk1 with blue coolant glints in the vent block. Damage as the Mk1.'
    notes = ('INSIDE half of the Pulse Mk2: as the Mk1 plus amber ticks round the drum. Barrel layer pulse_mk2_barrel: the finned cooling shroud (blue coolant glints) '
             'over the barrel.')


# ============================================================ ARTEMIS MK1
def _missile():
    """24x7 missile, nose east: swept tail fins, amber warhead band, red ogive nose."""
    m = Spr(24, 7)
    for k, c in enumerate('HLMSW'): m.hline(3, 1 + k, 14, c)
    for r in range(1, 5): m.hline(13, r, 2, 'a')
    m.hline(13, 5, 2, 'u'); m.hline(13, 1, 2, 'y')
    for r, c in enumerate('orrrn'): m.hline(17, 1 + r, 3, c)
    for r, c in enumerate('orn'): m.hline(20, 2 + r, 2, c)
    m.put(22, 3, 'r')
    for y, c in ((2, 'D'), (3, 'E'), (4, 'D')): m.put(1, y, c); m.put(2, y, c)
    m.hline(2, 0, 3, 'S'); m.put(5, 0, 'M'); m.put(3, 1, 'S')
    m.hline(2, 6, 3, 'W'); m.put(5, 6, 'S'); m.put(3, 5, 'E')
    return m
MISSILE = _missile().rows()
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
NOSE_X = [None, 41, 35, 29, 23, 17]               # inside half: nose x of the missile sliding in from the chute, per charge frame

class Artemis(Weapon):
    id = 'artemis_mk1'
    blen, bwid = 58, 27
    bpivot = (6, 13)
    bmuzzle = (42, 6)
    out_notes = ('OUTSIDE half of the Artemis Mk1: turret ring with a loader hatch (orange lamps) and a sensor. damaged: ring cracked, cover flapping; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Artemis Mk1: the missile cradle with a feed chute on the right (the ammo rack sits beside it), power coupling, repair hatch and a lamp strip. '
             'charge: a missile slides in from the chute into the cradle (frame 5 = seated and ready, strip green); fire: the cradle is empty and the strip discharges. '
             'damaged: chute cracked, lamps dead, sparks; disabled: the missile is jammed half way in the chute. Barrel layer artemis_mk1_barrel: the twin-rail launcher head '
             'with one missile on the upper rail; fire: the missile leaves under power, then smoke.')
    def outside(self, s, st):
        pw = st.powered
        gun_housing(s)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')                                   # left wing: loader hatch
        bev(s, 5, 8, 12, 8, 'M', 'S', 'W', cham=False); s.hline(7, 12, 8, 'W'); s.put(6, 9, 'L'); s.put(15, 14, 'L')
        for k in range(3): s.rect(5 + 4 * k, 18, 3, 3, 'o' if pw and (k < 2 or st.i == 0 or st.state != 'on') else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')                                  # right wing: sensor
        s.rect(48, 9, 10, 6, 'D'); s.hline(48, 9, 10, 'K')
        s.put(50, 12, 'c' if pw else 'E'); s.put(51, 12, 'c' if pw else 'E'); s.rect(54, 11, 3, 2, 'o' if pw else 'E')
        s.hline(48, 19, 3, 'W'); s.hline(52, 19, 2, 'W'); s.hline(55, 19, 3, 'W')
        bolts(s, [(47, 8), (58, 8), (47, 22), (58, 22)])
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y)
        coupling(s, 3, y + 2, st, 'o')
        hatch(s, 3, y + 16, st, 9, 8)
        bev(s, 14, y + 5, 34, 15, 'W', 'E', 'D', cham=False)                   # the cradle
        s.hline(15, y + 6, 32, 'S'); s.hline(15, y + 18, 32, 'W')
        for bx in (22, 30, 38): s.vline(bx, y + 7, 11, 'E')
        bev(s, 48, y + 5, 15, 15, 'S', 'E', 'D')                              # feed chute toward the ammo rack
        s.rect(51, y + 8, 12, 9, 'D'); s.hline(51, y + 8, 12, 'K'); s.hline(51, y + 17, 12, 'M')
        for k in range(2): s.put(56 + 3 * k, y + 11, 'a'); s.put(57 + 3 * k, y + 12, 'a'); s.put(56 + 3 * k, y + 13, 'a') if False else None
        for k in range(2):
            for q, (dx, dy) in enumerate(((1, 0), (0, 1), (1, 2))): s.put(54 + 4 * k + dx, y + 11 + dy, 'a')
        nose = {'on': 17, 'off': 17, 'damaged': 17, 'charge': NOSE_X[st.i] if st.charge else None, 'disabled': 35}.get(st.state)
        if nose is not None:
            M = fliph(MISSILE)
            for j, r in enumerate(M):
                for i, c in enumerate(r):
                    x = nose + i
                    if c != '.' and 15 <= x <= 61 and not (x > 50 and False): s.put(x, y + 9 + j, c)
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('y', 'a', 'g'))
        s.hline(55, y + 25, 3, 'W'); s.hline(59, y + 25, 2, 'W')
    def hurt_out(self, s, st):
        crack(s, [(31, 4), (30, 8), (32, 11), (30, 14), (31, 18)])
        crack(s, [(8, 8), (9, 12), (7, 15)])
        s.stamp(2, 5, FLAP) if False else None
        s.stamp(46, 3, FLAP); wire(s, [(48, 6), (50, 8), (52, 8)])
        spark(s, 50, 2, False) if st.i == 0 else spark(s, 11, 13, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 4), (30, 8), (32, 11), (30, 14), (31, 18), (33, 23)], [(8, 8), (9, 12), (7, 15)]],
                 dents=[(46, 16, 6, 5), (6, 18, 5, 4)], soots=[(22, 3, 0), (45, 5, 2), (4, 7, 1)],
                 wires_=[[(14, 6), (16, 9), (15, 12)]], sparks=[(26, 7), (52, 6)], flap=(46, 3))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(50, y + 5), (52, y + 9), (51, y + 14)])
        spark(s, 52, y + 10, False) if st.i == 0 else spark(s, 10, y + 20, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(50, y + 5), (52, y + 9), (51, y + 14), (53, y + 18)]); crack(s, [(24, y + 7), (26, y + 11), (25, y + 16)])
        wire(s, [(14, y + 21), (17, y + 23), (20, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        glow(g, ox + 12, oy + y + 8, 3, (255, 138, 30), 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        for k in range(3): glow(g, ox + 6.5 + 4 * k, oy + 19.5, 3, (255, 138, 30), 0.5, 2.0)
        glow(g, ox + 55.5, oy + 12, 3, (255, 138, 30), 0.5, 2.0); glow(g, ox + 50.5, oy + 12.5, 3, (60, 242, 255), 0.4, 2.0)
    # ---- barrel
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 11 + o, 3, 5, 21, 'M', 'S', 'W')                               # coupling block
        for y0 in (3, 17):
            b.rect(15 + o, y0, 28, 7, 'W'); b.hline(15 + o, y0, 28, 'M'); b.hline(15 + o, y0 + 6, 28, 'E')
            bev(b, 41 + o, y0, 3, 7, 'S', 'E', 'D', cham=False)
        for bx in (20, 31): bev(b, bx + o, 3, 3, 21, 'M', 'S', 'W', cham=False)
        b.rect(17 + o, 19, 24, 2, 'D'); b.hline(17 + o, 20, 24, 'K')            # the empty lower rail: scorched groove
        tail = {'fire': (22, 34, None)}.get(st.state, (16,) * 3)[st.i if st.fire else 0]
        if tail is not None:
            for j, r in enumerate(MISSILE):
                for i, c in enumerate(r):
                    if c != '.': b.put(tail + o + i, 3 + j, c)
        if st.fire and st.i < 2:                                               # motor lit: flame behind the tail
            for k, c in enumerate('yyoooa'): b.put(tail + o - 1 - k, 6, c)
            for k, c in enumerate('oooa'): b.put(tail + o - 2 - k, 5, c); b.put(tail + o - 2 - k, 7, c)
        if st.fire and st.i == 2:
            b.stamp(22, 0, SMOKE[0]); b.stamp(32, 1, SMOKE[1]); b.stamp(38, 0, SMOKE[0])
        breech(b, 13, 15)
    def bhurt(self, b, st):
        move(b, 34, 2, 11, 9, 0, 2)                                            # upper rail kinked at the nose, missile with it
        crack(b, [(23, 3), (24, 6), (23, 9)]); crack(b, [(28, 17), (29, 20), (28, 23)])
        wire(b, [(32, 10), (33, 12), (35, 13)])
        spark(b, 36, 12, False) if st.i == 0 else spark(b, 24, 5, False)
    def bbreak(self, b, st):
        for y in (3, 5, 7, 9): b.erase(31, y)
        b = cleave(b, lambda y: 32, 2, 3, rows=(0, 11))                         # the upper rail snaps and droops into the fork
        m = Spr(self.blen, self.bwid); m.stamp(16, 3, MISSILE)
        mr = rotate(m, 22, 28, 6)                                               # the missile fell off and lies crooked across the fork
        for y in range(self.bwid):
            for x in range(self.blen):
                c = mr.get(x, y - 6)
                if c != '.' and x >= 17 and b.get(x, y) in ('.', 'W', 'E'): b.put(x, y, c)
        return b
    def bwreck(self, b, st):
        wire(b, [(30, 5), (32, 7), (34, 9)])
        crack(b, [(20, 4), (21, 8), (20, 12)])
    def bafter(self, b, st): pass
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            tail = (22, 34, 0)[i]
            if i < 2:
                glow(g, ox + tail - 5, oy + 6.5, (11, 9)[i], (255, 140, 40), 0.6, 2.0, sx=1.5)
                glow(g, ox + tail - 3, oy + 6.5, 4, (255, 235, 160), 0.7, 1.6)
            else: glow(g, ox + 34, oy + 6.5, 12, (255, 140, 40), 0.22, 2.0, sx=1.6)
        if state in ('idle',): glow(g, ox + 40, oy + 6.5, 4, (255, 90, 50), 0.35, 2.0)

# ============================================================ ION BLAST MK1
class IonBlast(Weapon):
    id = 'ion_blast_mk1'
    blen, bwid = 62, 23
    bpivot = (6, 11)
    bmuzzle = (49, 11)
    out_notes = 'OUTSIDE half of the Ion Blast: turret ring with a coil stack and an arc rod. damaged: ring cracked, a coil unwinding; disabled: scorched, dented, sparking.'
    notes = ('INSIDE half of the Ion Blast: three teal coil capacitors that light one after another as it charges (frame 5 = all three bright, strip cyan), power coupling, hatch. '
             'fire: coils and strip discharge in a white flash. damaged: one coil unwinding, a lamp dead, sparks; disabled: coils scorched dark, a casing split. '
             'Barrel layer ion_blast_mk1_barrel: a slim core tube wrapped in three teal coils with a cyan emitter tip.')
    def outside(self, s, st):
        pw = st.powered
        gun_housing(s)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')                                   # left wing: coil stack
        for cx in (5, 11):
            coil_v(s, cx, 8, 5, 14, pw)
        s.put(3, 13, 'c' if pw else 'E'); s.put(3, 14, 'c' if pw else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')                                  # right wing: arc rod
        s.rect(52, 2, 2, 5, 'S'); s.put(52, 2, 'L'); s.put(52, 1, 'c' if pw else 'E'); s.put(53, 1, 'b' if pw else 'E')
        s.rect(48, 9, 10, 6, 'D'); s.hline(48, 9, 10, 'K')
        for k in range(4): s.rect(49 + 2 * k, 11, 1, 3, 'b' if pw and (st.state != 'on' or (k + st.i) % 2 == 0 or True) else 'E')
        s.hline(48, 19, 3, 'W'); s.hline(52, 19, 2, 'W'); s.hline(55, 19, 3, 'W')
        bolts(s, [(47, 8), (58, 8), (47, 22), (58, 22)])
    def inside(self, s, st):
        y = self.iy
        housing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        for k in range(3):                                                      # coil capacitors light one after another
            lit = st.powered and (st.lit >= (1, 3, 5)[k]) and not st.fire
            coil_v(s, 17 + 11 * k, y + 5, 9, 17, lit)
            s.hline(16 + 11 * k, y + 5, 11, 'S'); s.hline(16 + 11 * k, y + 21, 11, 'W')
            if st.flash: s.rect(18 + 11 * k, y + 7, 7, 13, 'L'); s.vline(21 + 11 * k, y + 7, 13, 'H')
        hatch(s, 50, y + 8, st)
        s.hline(4, y + 25, 2, 'W'); s.hline(7, y + 25, 3, 'W'); s.hline(55, y + 25, 3, 'W'); s.hline(59, y + 25, 2, 'W')
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('b', 'b', 'c'))
    def hurt_out(self, s, st):
        crack(s, [(28, 5), (29, 8), (27, 11), (28, 15)])
        s.stamp(2, 5, FLAP); wire(s, [(10, 6), (12, 8), (11, 11), (10, 14)])                # a coil unwinding
        spark(s, 9, 14, False) if st.i == 0 else spark(s, 53, 3, False)
        s.erase(52, 1); s.put(53, 2, 'S')
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(28, 5), (29, 8), (27, 11), (28, 15), (30, 19), (29, 23)], [(10, 8), (11, 13), (9, 19)]],
                 dents=[(46, 16, 6, 5), (13, 17, 4, 4)], soots=[(21, 3, 1), (46, 6, 0), (4, 8, 2)],
                 wires_=[[(14, 7), (16, 10), (15, 13)]], sparks=[(36, 6), (12, 4)], flap=(2, 5))
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(31, y + 5), (33, y + 10), (32, y + 15)])
        wire(s, [(26, y + 21), (28, y + 23), (27, y + 25)])
        spark(s, 31, y + 12, False) if st.i == 0 else spark(s, 27, y + 25, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(31, y + 5), (33, y + 10), (32, y + 15), (34, y + 19)]); crack(s, [(42, y + 6), (44, y + 11)])
        wire(s, [(14, y + 19), (16, y + 22), (19, y + 23)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, ready_rgb=(60, 242, 255), live_rgb=(79, 163, 255))
        lit = {'charge': i, 'on': 5, 'damaged': 3}.get(state, 0)
        for k in range(3):
            if lit >= (1, 3, 5)[k] and state != 'fire': glow(g, ox + 21.5 + 11 * k, oy + y + 13.5, 9, (79, 200, 255), 0.35, 2.0)
        glow(g, ox + 12, oy + y + 14, 3, (60, 242, 255), 0.5, 2.0)
        if state == 'fire' and i == 0:
            for k in range(3): glow(g, ox + 21.5 + 11 * k, oy + y + 13.5, 10, (230, 250, 255), 0.4, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 3.5, oy + 14, 4, (60, 242, 255), 0.5, 2.0)
        for k in range(2): glow(g, ox + 7.5 + 6 * k, oy + 15, 6, (79, 200, 255), 0.22, 2.0)
        glow(g, ox + 52.5, oy + 1.5, 3, (60, 242, 255), 0.5, 2.0)
        for k in range(4): glow(g, ox + 49.5 + 2 * k, oy + 12.5, 3, (79, 163, 255), 0.3, 2.0)
    # ---- barrel
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 12 + o, 8, 36, 7, 'LMSWWEE')                                     # core tube
        for cx in (17, 26, 35): coil_h(b, cx + o, 2, 9, 19, True)
        bev(b, 44 + o, 6, 6, 11, 'S', 'E', 'D')                                  # emitter housing
        lens_c(b, 47 + o, 8, 3, 7, st.fire, ('b', 'c', 'c', 'H'))
        if not st.fire: b.put(49 + o, 11, 'b')
        breech(b, 11, 15)
    def bhurt(self, b, st):
        for k in range(3):                                                       # the middle coil unwinding
            b.put(28, 20 + k, 'b' if k % 2 == 0 else 'c')
        wire(b, [(27, 20), (29, 22)], 'c')
        crack(b, [(19, 2), (20, 6), (19, 10)])
        b.rect(34, 2, 2, 3, 'D'); b.put(35, 3, 'E')
        spark(b, 29, 21, False) if st.i == 0 else spark(b, 20, 5, False)
        for x in range(26, 34): b.put(x, 12, 'W') if x % 2 else None
    def bbreak(self, b, st):
        return cleave(b, lambda y: 25, 2, 3)
    def bwreck(self, b, st):
        for y in (9, 13): wire(b, [(23, y), (25, y + 1), (27, y + 1)])
        crack(b, [(36, 4), (37, 8), (36, 12), (38, 17)])
        b.rect(48, 9, 3, 5, 'D'); b.put(49, 10, 'S')
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 49, 11, sub={'o': 'b', 'y': 'c'})
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            fire_glow(g, ox, oy, i, 49, 11, (79, 200, 255), (230, 250, 255))
            for cx in (17, 26, 35): glow(g, ox + cx + 4.5, oy + 11.5, 9, (79, 200, 255), (0.4, 0.3, 0.2)[i], 2.0)
        if state == 'idle':
            for cx in (17, 26, 35): glow(g, ox + cx + 4.5, oy + 11.5, 8, (79, 200, 255), 0.15, 2.0)


def gold_trim(s, half):
    """gold line along the mounting flange (uniques)."""
    fy = 2 if half == 'in' else s.h - 3
    s.hline(3, fy, 58, 'a')
    for x in (4, 13, 50, 59): s.put(x, fy, 'y')
def cable(s, pts, w=2):
    """a thick power cable: dark with a lit edge, made of axis-aligned runs."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        xa, xb = sorted((x0, x1)); ya, yb = sorted((y0, y1))
        s.rect(xa, ya, xb - xa + w, yb - ya + w, 'D')
        if x0 == x1: s.vline(xa, ya, yb - ya + w, 'W')
        else: s.hline(xa, ya, xb - xa + w, 'W')

# ============================================================ LEECH LASER (unique)
class LeechLaser(Weapon):
    id = 'leech_laser'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 44, 19
    bpivot = (8, 9)
    bmuzzle = (31, 9)
    def trim(self, s, st, half): gold_trim(s, half)
    out_notes = ('OUTSIDE half of the Leech Laser (unique, gold trim): turret ring, the siphon coil (green and gold windings) and the power-tap clamp. '
                 'damaged: ring cracked, the coil unwinding, cover flapping; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Leech Laser (unique, gold trim): a glass siphon tank whose green fluid rises with the charge (frame 5 = full, strip green), the thick power-tap cable '
             'from the coupling, repair hatch. fire: the tank drains in a flash. damaged: tank glass cracked, cable frayed and sparking; disabled: tank dark and split, cable torn out. '
             'Barrel layer leech_laser_barrel: a laser barrel with the siphon coil wrapped round it (green and gold) and a power-tap cable looped under it.')
    def outside(self, s, st):
        pw = st.powered
        turret_seat(s, 32, 15)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')                                   # left wing: the siphon coil
        coil_v(s, 6, 8, 8, 14, pw, ('y', 'g', 'E'))
        s.hline(5, 8, 10, 'a'); s.hline(5, 21, 10, 'a'); s.hline(3, 6, 16, 'a')
        s.put(3, 13, 'g' if pw else 'E'); s.put(3, 14, 'g' if pw else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')                                  # right wing: the power-tap clamp
        s.rect(48, 9, 10, 8, 'D'); s.hline(48, 9, 10, 'K')
        for k in range(3): s.rect(49 + 3 * k, 11, 2, 4, 'g' if pw and (k < 2 or st.i == 0 or st.state != 'on') else 'E')
        s.hline(45, 6, 16, 'a'); bolts(s, [(47, 8), (58, 8), (47, 22), (58, 22)], 'y')
        cable(s, [(52, 17), (52, 21)], 2)
        turret_ring(s, 32, 15)
        for x in range(21, 44): s.put(x, 7, 'a') if x % 4 == 0 else None
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y)
        s.hline(3, y + 1, 58, 'a')
        coupling(s, 3, y + 8, st, 'g')
        bev(s, 17, y + 5, 22, 16, 'M', 'S', 'W')                              # the siphon tank
        s.hline(17, y + 5, 22, 'a'); s.hline(17, y + 20, 22, 'a')
        s.rect(19, y + 7, 18, 12, 'D'); s.hline(19, y + 7, 18, 'K')
        n = {'charge': st.i, 'on': 5, 'damaged': 4, 'off': 0}.get(st.state, 0)
        if st.flash: n = 5
        hgt = round(n / 5 * 12)
        if hgt and (pw or st.flash):
            s.rect(19, y + 19 - hgt, 18, hgt, 'g'); s.hline(19, y + 19 - hgt, 18, 'y')
            for (bx, by) in ((22, 12), (27, 15), (32, 11), (34, 16)):
                if y + by > y + 19 - hgt + 1: s.put(bx, y + by, 'H')
            if st.flash: s.rect(19, y + 7, 18, 12, 'L')
        s.vline(20, y + 7, 12, 'W') if not hgt else None
        cable(s, [(8, y + 20), (8, y + 22), (40, y + 22), (40, y + 17)], 2)          # the power-tap cable
        s.rect(40, y + 14, 3, 3, 'a'); s.put(41, y + 15, 'y')
        hatch(s, 46, y + 8, st)
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('a', 'a', 'g'))
    def hurt_out(self, s, st):
        crack(s, [(28, 5), (29, 8), (27, 11), (28, 14)])
        s.stamp(2, 5, FLAP) if False else None
        s.stamp(1, 3, FLAP); wire(s, [(8, 5), (9, 8), (8, 11)], 'g'); s.put(8, 12, 'g')      # the coil unwinding
        spark(s, 53, 22, False) if st.i == 0 else spark(s, 9, 12, False)
        crack(s, [(52, 8), (54, 11), (53, 15)])
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(28, 5), (29, 8), (27, 11), (28, 15), (30, 19), (29, 23)], [(10, 8), (11, 13), (9, 19)]],
                 dents=[(46, 17, 6, 5), (14, 17, 4, 4)], soots=[(21, 3, 0), (46, 6, 2), (4, 8, 1)],
                 wires_=[[(52, 17), (54, 21), (55, 26)], [(8, 6), (9, 11), (7, 14)]], sparks=[(30, 6), (53, 26)], flap=(1, 3))
    def hurt_in(self, s, st):
        y = self.iy
        crack(s, [(25, y + 5), (27, y + 9), (26, y + 14), (28, y + 19)])
        wire(s, [(24, y + 22), (26, y + 24)]); s.put(26, y + 22, 'D')
        dead_cells(s, st, y + STRIP_DY)
        spark(s, 26, y + 23, False) if st.i == 0 else spark(s, 27, y + 8, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(25, y + 5), (27, y + 9), (26, y + 14), (28, y + 19), (27, y + 22)]); crack(s, [(34, y + 7), (33, y + 12)])
        wire(s, [(24, y + 22), (26, y + 24), (30, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, live_rgb=(225, 161, 54))
        n = {'charge': i, 'on': 5, 'damaged': 4}.get(state, 0)
        if state == 'fire' and i == 0: n = 5
        if n: glow(g, ox + 28, oy + y + 19 - round(n / 5 * 12) / 2, 12, (107, 211, 74), 0.35, 2.0, sx=1.5)
        glow(g, ox + 12, oy + y + 14, 3, (107, 211, 74), 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 3.5, oy + 14, 4, (107, 211, 74), 0.5, 2.0)
        glow(g, ox + 10, oy + 15, 8, (107, 211, 74), 0.2, 2.0)
        for k in range(2): glow(g, ox + 50 + 3 * k, oy + 13, 3.5, (107, 211, 74), 0.4, 2.0)
    # ---- barrel
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 12 + o, 4, 18, 11)
        coil_h(b, 15 + o, 3, 11, 13, True, ('y', 'g', 'E'), 'a')               # the siphon coil, gold flanges
        bev(b, 26 + o, 3, 5, 13, 'S', 'E', 'D'); b.vline(26 + o, 3, 13, 'a')
        lens_c(b, 28 + o, 6, 3, 7, st.fire, ('g', 'g', 'y', 'H'))
        if not st.fire: b.put(30 + o, 9, 'g')
        wire(b, [(16 + o, 16), (18 + o, 17), (22 + o, 17), (25 + o, 16)], 'D'); wire(b, [(17 + o, 17), (21 + o, 18), (24 + o, 17)], 'W')   # power-tap cable looped under
        hub(b, 9)
        pod(b, 9, 0)                                                              # sensor pod: the turret aims itself
    def bhurt(self, b, st):
        b.rect(20, 3, 4, 13, '.'); b.rect(20, 3, 4, 1, 'a')                    # part of the coil torn open
        for k in range(4): b.put(21 + k, 14 + k % 2, 'g' if k % 2 == 0 else 'y')
        wire(b, [(20, 15), (22, 17), (25, 18)], 'g')
        crack(b, [(27, 4), (28, 8), (27, 12)]); b.put(30, 9, 'E')
        spark(b, 25, 18, False) if st.i == 0 else spark(b, 29, 6, False)
    def bbreak(self, b, st):
        return cleave(b, lambda y: 24, 2, 3)
    def bwreck(self, b, st):
        for k in range(5): b.put(22 + k, 16 + (k % 2), 'u')                        # the coil sprung open
        wire(b, [(25, 6), (27, 8), (29, 10)]); crack(b, [(29, 7), (30, 11), (29, 15)], 'K', 'S')
        b.put(30, 8, 'S'); b.put(31, 12, 'S')
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 31, 9, sub={'o': 'g', 'y': 'y'})
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 31, 9, (107, 211, 74), (230, 255, 200))
        if state == 'idle': glow(g, ox + 20, oy + 9.5, 8, (107, 211, 74), 0.22, 2.0, sx=1.5)
        if state != 'disabled': glow(g, ox + 10.5, oy + 1.5, 3, (60, 242, 255), 0.5, 2.0)

# ============================================================ BREACH HARPOON (unique)
def _harpoon_head():
    top = ["LL...........", "LML..........", ".LML.........", "..LMLL.......", "..SLMMLL.....", "..SSLMMMLL...", "SSSSSLMMMMMLL"]
    bot = [r for r in reversed(top[:-1])]
    sub = {'L': 'M', 'M': 'S', 'S': 'W'}
    return top + [''.join(sub.get(c, c) for c in r) for r in bot]
HEAD = _harpoon_head()
class BreachHarpoon(Weapon):
    id = 'breach_harpoon'
    blen, bwid = 66, 21
    bpivot = (6, 10)
    bmuzzle = (51, 10)
    def trim(self, s, st, half): gold_trim(s, half)
    out_notes = ('OUTSIDE half of the Breach Harpoon (unique, gold trim): turret ring with a hydraulic ram and the cable-guide pulley. '
                 'damaged: ring cracked, pulley cable frayed; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Breach Harpoon (unique, gold trim): the cable spool, which winds the rope back on as it charges (rope disc grows frame by frame, frame 5 = full, '
             'strip green; the spokes turn half a step on odd frames), power coupling, repair hatch. fire: the spool is empty and the strip discharges. '
             'damaged: spool flange cracked, rope fraying, sparks; disabled: spool jammed and dark, rope tangled. Barrel layer breach_harpoon_barrel: the heavy open trough with the '
             'harpoon (barbed head) loaded; fire: the harpoon flies, the cable pays out, steam.')
    def outside(self, s, st):
        pw = st.powered
        gun_housing(s)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')                                   # left wing: hydraulic rams
        for cx in (6, 11):
            cylv(s, cx, 8, 4, 14, 'LSWE'); s.hline(cx, 11, 4, 'a'); s.hline(cx, 18, 4, 'a')
        s.hline(3, 6, 16, 'a'); s.put(3, 13, 'g' if pw else 'E'); s.put(3, 14, 'g' if pw else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')                                  # right wing: cable-guide pulley
        chamfer_fill(s, 48, 9, 10, 10, 'S', 3); rim(s, 'S', 'M', 'W', (48, 9, 57, 18))
        chamfer_fill(s, 50, 11, 6, 6, 'q', 2); s.put(52, 13, 'L'); s.put(53, 14, 'a')
        s.hline(45, 6, 16, 'a'); bolts(s, [(47, 8), (58, 8), (47, 22), (58, 22)], 'y')
        turret_ring(s, 32, 15)
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing(s, y)
        s.hline(3, y + 1, 58, 'a')
        coupling(s, 3, y + 8, st, 'g')
        cx, cy = 30, y + 13
        chamfer_fill(s, cx - 9, cy - 9, 19, 19, 'S', 6); rim(s, 'S', 'M', 'W', (cx - 9, cy - 9, cx + 9, cy + 9))        # the spool
        chamfer_fill(s, cx - 8, cy - 8, 17, 17, 'E', 6)
        R = {'charge': 2 + st.i, 'on': 8, 'damaged': 8, 'off': 8, 'disabled': 7}.get(st.state, 2)
        for r in range(R, 1, -1): chamfer_fill(s, cx - r, cy - r, 2 * r + 1, 2 * r + 1, ('q', 'Q', 'q', 'n')[r % 4], max(1, r * 2 // 3))
        chamfer_fill(s, cx - 2, cy - 2, 5, 5, 'M', 1); rim(s, 'M', 'L', 'S', (cx - 2, cy - 2, cx + 2, cy + 2)); s.put(cx, cy, 'a')
        odd = (st.charge and st.i % 2) or (st.state == 'fire' and st.i == 1)
        for k in range(1, 9):                                                    # spokes: plus, or turned half a step
            for (dx, dy) in (((k, 0), (-k, 0), (0, k), (0, -k)) if not odd else ((k, k), (-k, -k), (k, -k), (-k, k))):
                if k > R: s.put(cx + dx, cy + dy, 'M')
        for (dx, dy) in ((0, -9), (0, 9), (-9, 0), (9, 0)): s.put(cx + dx, cy + dy, 'a')
        hatch(s, 46, y + 8, st)
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('a', 'a', 'g'))
    def hurt_out(self, s, st):
        crack(s, [(28, 5), (29, 8), (27, 11), (28, 15)])
        crack(s, [(50, 8), (52, 11), (51, 15)]); s.stamp(46, 3, FLAP); wire(s, [(48, 6), (50, 8)])
        wire(s, [(52, 17), (54, 20), (53, 23)], 'q')
        spark(s, 53, 23, False) if st.i == 0 else spark(s, 7, 12, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(28, 5), (29, 8), (27, 11), (28, 15), (30, 19), (29, 23)], [(50, 8), (52, 11), (51, 15)]],
                 dents=[(7, 17, 6, 5), (46, 17, 5, 4)], soots=[(21, 3, 2), (45, 6, 1), (4, 8, 0)],
                 wires_=[[(52, 18), (55, 21), (56, 25)]], sparks=[(34, 6), (56, 25)], flap=(46, 3))
    def hurt_in(self, s, st):
        y = self.iy
        crack(s, [(24, y + 5), (26, y + 9), (25, y + 13), (27, y + 17)])
        wire(s, [(38, y + 13), (40, y + 16), (39, y + 19)], 'q')
        dead_cells(s, st, y + STRIP_DY)
        spark(s, 39, y + 19, False) if st.i == 0 else spark(s, 26, y + 9, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(24, y + 5), (26, y + 9), (25, y + 13), (27, y + 17), (26, y + 21)]); crack(s, [(35, y + 7), (37, y + 12)])
        wire(s, [(20, y + 22), (24, y + 24), (30, y + 24)], 'q'); wire(s, [(36, y + 20), (38, y + 23)], 'q')
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, live_rgb=(225, 161, 54))
        glow(g, ox + 12, oy + y + 14, 3, (107, 211, 74), 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 3.5, oy + 14, 4, (107, 211, 74), 0.5, 2.0)
    # ---- barrel
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 11 + o, 3, 26, 15, 'M', 'S', 'W')                              # the heavy trough
        b.rect(14 + o, 6, 23, 9, 'D'); b.hline(14 + o, 6, 23, 'K')
        for bx in (17, 30): b.vline(bx + o, 3, 15, 'a'); b.vline(bx + o + 1, 3, 15, 'W')
        bev(b, 35 + o, 2, 4, 17, 'S', 'E', 'D'); b.vline(38 + o, 2, 17, 'a')
        hx = {'fire': (45, None, None)}.get(st.state, (39,))[st.i if st.fire else 0] if st.fire else 39
        if hx is not None:
            for k in range(hx - 25 + 14, hx + 1): pass
            for k in range(14, hx):                                              # the shaft
                for r, c in zip((9, 10, 11), 'MSW'): b.put(k + o if k < hx - 0 and not st.fire else k, r, c)
            for j, r in enumerate(HEAD):
                for i, c in enumerate(r):
                    if c != '.': b.put(hx + i + (0 if st.fire else o), 4 + j, c)
        if st.fire and st.i >= 1:                                                # the cable pays out
            for x in range(36, 66): b.put(x, 10, 'q'); b.put(x, 11, 'n') if x % 2 else b.put(x, 9, 'Q')
        if st.fire:
            for (x, yy) in ((40 + st.i * 2, 4), (44 + st.i * 2, 15), (50, 6 - st.i), (54, 14 + st.i)): b.stamp(x, yy, SMOKE[st.i % 2])
        breech(b, 10, 15)
    def bhurt(self, b, st):
        crack(b, [(20, 3), (22, 7), (21, 12), (23, 17)])
        for y in range(5, 8): b.erase(39, y)                                      # a barb bent over
        b.put(40, 4, 'L'); b.put(41, 4, 'M'); b.put(41, 3, 'L')
        b.rect(30, 3, 2, 15, '.'); b.rect(30, 3, 2, 1, 'a'); wire(b, [(30, 17), (31, 19)])   # a gold band hanging loose
        spark(b, 31, 19, False) if st.i == 0 else spark(b, 41, 4, False)
    def bbreak(self, b, st):
        b = cleave(b, lambda y: 30, 2, 3)
        return b
    def bwreck(self, b, st):
        for y in (8, 12): wire(b, [(29, y), (31, y + 1), (33, y + 1)], 'q')
        crack(b, [(20, 4), (21, 9), (20, 14)], 'K', 'S')
        for k in range(4): b.put(44 + k * 2, 14 + (k % 2), 'S')
    def bafter(self, b, st): pass
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            glow(g, ox + 42, oy + 10.5, (14, 12, 9)[i], (240, 245, 250), (0.45, 0.4, 0.3)[i], 2.0, sx=1.4)
            if i == 0: glow(g, ox + 48, oy + 10.5, 5, (255, 220, 150), 0.6, 1.6)


# ============================================================ LASER TURRET MK1 (the Concord Point Turret)
from comp_laser import Laser
class LaserTurret(Laser):
    id = 'laser_turret_mk1'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 42, 21
    bpivot = (8, 10)
    bmuzzle = (29, 10)
    out_notes = ('OUTSIDE half of the Laser Turret Mk1 (the Concord Point Turret, a TURRET): turret-ring base with swivel ticks, a compact power-cell block and a sensor dome. '
                 'damaged: ring and wing cracked, cover flapping; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Laser Turret Mk1 (a turret): copper cell bank, repair hatch, power coupling, 5-cell strip (frame 5 = ready); fire: the strip discharges. '
             'The rotating head laser_turret_mk1_barrel swivels in the ring: a compact round head, a short red-lensed barrel and a small sensor eye (it aims itself).')
    def outside(self, s, st):
        pw = st.powered
        turret_seat(s, 32, 15)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')                                   # left: power cells
        for cx in (6, 9, 12):
            s.rect(cx, 8, 2, 14, 'q'); s.vline(cx, 8, 14, 'Q'); s.vline(cx + 1, 8, 14, 'n')
        s.rect(3, 12, 1, 4, 'D'); s.put(3, 13, 'g' if pw else 'E'); s.put(3, 14, 'g' if pw else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')                                  # right: sensor dome
        s.stamp(50, 9, art("""
.KKKK.
KDDDDK
KDcDDK
KDDDDK
KDDDDK
.KKKK.
"""))
        if pw and (st.state != 'on' or st.i == 0): s.put(52, 12, 'c'); s.put(53, 11, 'c')
        else: s.put(52, 12, 'E')
        for hx in range(48, 58, 4):
            for k in range(3): s.put(hx + k, 18 + k, 'a'); s.put(hx + k + 1, 18 + k, 'D')
        bolts(s, [(47, 8), (58, 8), (47, 22)])
        turret_ring(s, 32, 15)
        for (x, y) in ((24, 8), (40, 8), (24, 22), (40, 22)): s.put(x, y, 'L')          # swivel ticks round the ring
    def hurt_out(self, s, st):
        crack(s, [(54, 6), (53, 9), (55, 11), (52, 14), (53, 17)])
        crack(s, [(24, 9), (26, 12), (25, 16), (28, 19)])
        s.stamp(2, 5, FLAP); wire(s, [(10, 6), (12, 7), (14, 7)])
        spark(s, 10, 4, False) if st.i == 0 else spark(s, 52, 13, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(24, 8), (26, 11), (25, 15), (28, 18), (27, 22)], [(52, 7), (53, 10), (51, 14), (54, 18)]],
                 dents=[(6, 16, 5, 6), (49, 17, 6, 4)], soots=[(20, 3, 0), (46, 5, 1), (8, 7, 2)],
                 wires_=[[(10, 6), (12, 8), (13, 11)]], sparks=[(30, 6), (12, 12)], flap=(2, 5))
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 12 + o, 5, 14, 11)
        for rx in (15, 20): bev(b, rx + o, 4, 3, 13, 'L', 'M', 'S', cham=False); b.vline(rx + o + 2, 4, 13, 'W'); b.hline(rx + o, 16, 3, 'W')
        bev(b, 24 + o, 4, 5, 13, 'S', 'E', 'D')
        lens(b, 26 + o, 7, 3, 7, st.fire)
        if not st.fire: b.put(28 + o, 10, 'r')
        hub(b, 10, 17)
        pod(b, 10, 0)
    def bhurt(self, b, st):
        b.rect(20, 4, 3, 13, '.'); b.rect(20, 4, 3, 1, 'S')
        wire(b, [(21, 5), (21, 6)]); wire(b, [(20, 16), (21, 18), (22, 19)])
        bev(b, 21, 17, 3, 3, 'L', 'M', 'S', cham=False)
        crack(b, [(25, 5), (26, 8), (25, 11), (27, 15)])
        b.put(28, 10, 'r' if st.i == 0 else 'E')
        spark(b, 23, 19, False) if st.i == 0 else spark(b, 26, 8, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 19, 2, 3)
    def bwreck(self, b, st):
        for y in (7, 13): wire(b, [(18, y), (20, y + 1), (22, y + 1)])
        crack(b, [(26, 8), (28, 11), (27, 14), (30, 16)], 'K', 'S')
        b.rect(29, 13, 3, 4, 'D'); b.put(30, 14, 'S')
    def bafter(self, b, st):
        if st.fire: b.stamp(29 - st.rc, 10 - len(FLASH_E[st.i]) // 2, FLASH_E[st.i])
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            fire_glow(g, ox, oy, i, 29, 10, scale=0.9)
        if state == 'damaged' and i == 0: glow(g, ox + 28, oy + 10.5, 4, (255, 80, 60), 0.4, 2.0)
        if state != 'disabled': glow(g, ox + 11.5, oy + 1.5, 3, (60, 242, 255), 0.5, 2.0)

ALL = [LaserMk2, PulseMk1, PulseMk2, Artemis, IonBlast, LeechLaser, BreachHarpoon, LaserTurret]
