"""Basalt tech (docs/waves/racial_tech_1.md): rough stone housings with glowing magma seams. Dark basalt (S/W/E), cold seams n/D, lit seams r/o/y,
iron fittings (steel tones) where stone meets machinery, light grey pumice (M/L) for the flak. Chipped edges, nothing perfectly square.
Weapons: basalt_magma_spitter, basalt_quarry_driver, basalt_pumice_flak. Components: basalt_vacuum_forge (reactor), basalt_stonehide_bay and
basalt_gravity_anchor (utilities). Projectile art: glowing slag, rock shards."""
from techa_kit import *

# ------------------------------------------------------------------ basalt vocabulary
def stone_cyl(b, x, y, w, h, ramp='SSWWWEE'):
    """a horizontal stone cylinder (barrel tube): ramp light to dark, a few dark specks."""
    cylh(b, x, y, w, h, ramp)
    for i in range(w):
        for j in (1, h - 2):
            if hsh(x + i, y + j, 9) % 11 == 0: b.put(x + i, y + j, 'E')

def iron_ring(b, x, y, h, w=3):
    """an iron collar round a barrel (vertical on the east canvas)."""
    b.vline(x, y, h, 'M')
    for k in range(1, w - 1): b.vline(x + k, y, h, 'S')
    b.vline(x + w - 1, y, h, 'W')
    b.put(x + 1, y + 1, 'L'); b.put(x + 1, y + h - 2, 'L')

def breech_stone(b, cy, w=15, hh=None):
    """the stone breech: a rough block with an iron gimbal pin and a cuff where the barrel enters the sleeve."""
    hh = hh or w
    stone(b, 1, cy - hh // 2, 11, hh, 4)
    chamfer_fill(b, 4, cy - 2, 5, 5, 'S', 1); rim(b, 'S', 'L', 'W', (4, cy - 2, 8, cy + 2)); b.put(6, cy, 'E')
    iron_ring(b, 11, cy - hh // 2 - 1, hh + 2, 3)

def vent_slots(s, x, y, n, h, on, gap=4, i=0):
    """room-vent slots: dark slits with a dull ember at the bottom."""
    for k in range(n):
        xx = x + k * gap
        s.rect(xx, y, 2, h, 'D'); s.vline(xx, y, h, 'K'); s.vline(xx + 2, y, h, 'M')
        s.put(xx + 1, y + h - 1, 'o' if on and (k + i) % 2 == 0 else ('r' if on else 'E'))

def pore(s, x, y, tone='E'):
    s.put(x, y, tone)

def pumice_ball(s, x, y):
    """a light porous pumice rock, 5x5."""
    chamfer_fill(s, x, y, 5, 5, 'M', 1); rim(s, 'M', 'L', 'S', (x, y, x + 4, y + 4))
    s.put(x + 2, y + 2, 'E'); s.put(x + 3, y + 3, 'W')

def slag_blob(s, x, y, big=True):
    """a drop of glowing slag."""
    if big: s.stamp(x, y, art(".oo.\noyyo\noyHo\n.or."))
    else: s.stamp(x, y, art(".o.\noyo\n.r."))

class StoneMount:
    """basalt hull mounts: the flange that overhangs the wall is stone too, with a cold seam and a few rivets."""
    def trim(self, s, st, half):
        fy = 0 if half == 'in' else s.h - 5
        stone(s, 1, fy, 62, 5, 70 + (half == 'in'), specks=False)
        for x in (6, 16, 47, 57): s.put(x, fy + 2, 'L')
        if half == 'in': magma(s, [(24, fy + 3), (30, fy + 2), (36, fy + 3)], st.powered, st.i)
        else: magma(s, [(24, fy + 1), (30, fy + 2), (36, fy + 1)], st.powered, st.i)

# ============================================================ MAGMA SPITTER
class MagmaSpitter(StoneMount, Weapon):
    id = 'basalt_magma_spitter'
    blen, bwid = 48, 19
    bpivot = (6, 9)
    bmuzzle = (37, 9)
    out_notes = ('OUTSIDE half of the Basalt Magma Spitter: a chipped basalt block with a spout sleeve, a bank of room-vent slots (it dumps its breech air) on the left and a slag cistern '
                 'with a magma gauge on the right, lit seams between. damaged: a stone corner cracked and leaking magma, the cistern lid hanging, sparks; disabled: cold seams, chunks knocked off, dented, sparking.')
    notes = ('INSIDE half of the Basalt Magma Spitter: a stone crucible whose magma level rises with the charge (frame 5 = brim full and white-hot, strip yellow), power coupling in an iron socket, '
             'stone repair hatch, five magma slits. fire: the crucible flashes white and drains. damaged: the crucible rim cracked and weeping magma, two slits dead, a drip; '
             'disabled: cold crust in the pot, the rim split, a chunk fallen. Barrel layer basalt_magma_spitter_barrel: a thick stone tube flaring into a volcano mouth full of glowing slag; '
             'fire: a glob of slag leaves the mouth.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        mat(s, 6, 20, 52, 12, STONE)                                            # base pad
        stone(s, 19, 2, 26, 26, 1, seams=[((22, 22), (27, 24))])                 # the block
        stone(s, 22, 1, 20, 8, 2)
        s.rect(26, 2, 12, 6, 'D'); s.hline(26, 2, 12, 'K')                       # the spout channel
        mat(s, 18, 9, 28, 5, ('L', 'M', 'S'), cham=False); s.put(32, 12, 'L'); s.put(33, 13, 'W')   # gimbal collar (iron)
        for x in (21, 42): s.put(x, 11, 'L')
        stone(s, 3, 9, 16, 15, 3)                                                # left wing: room vents
        vent_slots(s, 6, 11, 3, 11, pw, 4, i)
        stone(s, 45, 4, 16, 20, 5)                                               # right wing: the slag cistern
        s.rect(48, 7, 10, 11, 'D'); s.hline(48, 7, 10, 'K')
        for r, c in enumerate('yooooorr'):                                          # magma level in the gauge window
            if pw: s.hline(49, 9 + r, 8, c)
        if pw and i == 0 and st.state == 'on': s.put(52, 9, 'H')
        s.hline(48, 19, 3, 'W'); s.hline(52, 19, 2, 'W'); s.hline(55, 19, 3, 'W')
        magma(s, [(19, 18), (24, 20), (24, 26)], pw, i); magma(s, [(44, 17), (40, 21), (41, 27)], pw, i + 1)
        magma(s, [(11, 24), (8, 27), (15, 29)], pw, i + 2)
        for (x, y) in ((22, 5), (41, 5), (22, 26), (41, 26)): s.put(x, y, 'L')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        stone(s, 2, y + 1, 60, 30, 7)
        cable_stub(s, 3, y + 8, st, 'o')
        cx, cy = 30, y + 13
        chamfer_fill(s, cx - 10, cy - 10, 21, 21, 'S', 7); rim(s, 'S', 'M', 'W', (cx - 10, cy - 10, cx + 10, cy + 10))       # the crucible
        chamfer_fill(s, cx - 8, cy - 8, 17, 17, 'E', 6)
        pot = Spr(64, 36); circle(pot, cx + .5, cy + .5, 7.2, 'X')
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 5 if st.i == 0 else 0
        level = round(n / 5 * 14)
        for yy in range(36):
            for xx in range(64):
                if pot.g[yy][xx] != 'X': continue
                top = cy + 7 - level
                if st.state == 'fire' and st.i == 0: s.put(xx, yy, 'H' if (xx + yy) % 3 else 'L')
                elif level and yy >= top and pw: s.put(xx, yy, 'y' if yy == top else ('o' if (xx + yy) % 7 else 'y') if yy < top + 3 else ('r' if yy > cy + 4 and (xx + yy) % 3 == 0 else 'o'))
                else: s.put(xx, yy, 'D')
        if level and pw and st.state != 'fire':
            for (dx, dy) in ((-3, -2), (2, -4), (4, 1)):
                if cy + dy > cy + 7 - level + 1: s.put(cx + dx, cy + dy, 'H')
        for (dx, dy) in ((0, -9), (0, 9), (-9, 0), (9, 0)): s.put(cx + dx, cy + dy, 'L')
        s.hline(cx - 3, cy + 10, 7, 'o' if pw and n else 'E')                      # spout trough into the barrel feed
        hatch_k(s, 46, y + 8, STONE_D, 11, 9, 'o')
        slits(s, st, STRIP_X, y + STRIP_DY)
        for (x, yy) in ((8, 3), (55, 3)): s.put(x, y + yy, 'L')
        magma(s, [(2, y + 21), (7, y + 24), (11, y + 22)], pw, st.i)
        magma(s, [(60, y + 14), (56, y + 18), (58, y + 22)], pw, st.i + 2)
    def hurt_out(self, s, st):
        magma_crack(s, [(44, 3), (42, 7), (44, 11), (41, 15)], st.i)
        s.stamp(46, 3, FLAP); wire(s, [(48, 6), (50, 8)])
        s.hline(3, 6, 6, 'K'); chip(s, 3, 7, 2, 2)
        magma_crack(s, [(11, 22), (12, 26), (10, 29)], st.i + 1)
        hurt_pair(s, st, (9, 4), (54, 22))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(28, 3), (27, 8), (30, 12), (28, 17), (30, 22), (29, 27)], [(50, 8), (52, 12), (50, 16)]],
                 dents=[(6, 15, 6, 4), (49, 21, 6, 4)], soots=[(22, 3, 1), (45, 5, 0), (4, 8, 2)],
                 wires_=[[(14, 22), (12, 26), (10, 28)]], sparks=[(35, 6), (8, 12)], flap=(46, 3))
        fallen_chunk(s, 14, 26)
    def hurt_in(self, s, st):
        y = self.iy
        dead_slits(s, st, y + STRIP_DY)
        magma_crack(s, [(37, y + 4), (39, y + 8), (38, y + 11)], st.i)
        s.put(39, y + 15 + 2 * st.i, 'o'); s.put(39, y + 14, 'r')
        hurt_pair(s, st, (25, y + 6), (50, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(24, y + 4), (26, y + 9), (25, y + 13), (28, y + 18), (27, y + 22)])
        crack(s, [(37, y + 5), (36, y + 10), (38, y + 14)])
        fallen_chunk(s, 41, y + 22); wire(s, [(14, y + 18), (16, y + 21)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy; cx, cy = 30, y + 13
        slits_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        n = {'charge': i, 'on': 5, 'damaged': 4}.get(state, 0)
        if state == 'fire' and i == 0: n = 5
        if n: glow(g, ox + cx + .5, oy + cy + 7 - round(n / 5 * 14) / 2, 11, ORANGE, 0.22 + 0.05 * n, 1.8)
        glow(g, ox + 12, oy + y + 14, 3, ORANGE, 0.5, 2.0)
        if state != 'off': glow(g, ox + 8, oy + y + 24, 8, ORANGE, 0.12, 2.0, sx=2)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 53, oy + 14.5, 7, ORANGE, 0.4, 1.8)
        for (x, y) in ((22, 22), (41, 22), (10, 27)): glow(g, ox + x, oy + y, 5, ORANGE, 0.28, 2.0)
        for k in range(3): glow(g, ox + 7 + 4 * k, oy + 21, 3, ORANGE, 0.3, 2.0)
    # ---- barrel (east-pointing canvas 48x19: breech | tube | volcano mouth)
    def barrel(self, b, st):
        o = -st.rc
        breech_stone(b, 9, 15)
        stone_cyl(b, 13 + o, 4, 16, 11)
        iron_ring(b, 17 + o, 3, 13, 2)
        for (x0, x1, y0, y1) in ((27, 29, 3, 15), (30, 32, 2, 16), (33, 37, 1, 17)):       # the flare
            cylh(b, x0 + o, y0, x1 - x0 + 1, y1 - y0 + 1, 'SSWWWEE')
        b.vline(33 + o, 1, 17, 'E'); b.vline(30 + o, 2, 15, 'E')
        b.rect(34 + o, 3, 4, 13, 'D')                                              # the mouth
        full = st.fire or st.state == 'idle'
        if full:
            hot = 'H' if st.fire else 'y'
            b.rect(35 + o, 4, 3, 11, 'o'); b.rect(36 + o, 5, 2, 9, hot if st.fire else 'y'); b.vline(34 + o, 5, 9, 'r')
            if not st.fire: b.put(37 + o, 6, 'H'); b.put(36 + o, 11, 'H')
        magma(b, [(20 + o, 5), (25 + o, 5)], True, st.i) if st.state == 'idle' else None
        if st.state == 'idle': b.put(36 + o, 17, 'o'); b.put(36 + o, 18, 'y')
        for (x, y) in ((15, 6), (23, 12), (28, 5)): b.put(x + o, y, 'M')
    def bhurt(self, b, st):
        magma_crack(b, [(21, 4), (22, 8), (21, 11), (23, 14)], st.i)
        move(b, 30, 2, 8, 6, 0, -1)
        b.stamp(24, 15, art("oo\nyo")) if st.i == 0 else b.stamp(25, 16, art("o\ny"))
        hurt_pair(b, st, (32, 17), (16, 5)) if False else None
        spark(b, 36, 2, False) if st.i == 0 else spark(b, 20, 3, False)
    def bbreak(self, b, st):
        return cleave(b, lambda y: 27, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(19, 4), (21, 8), (20, 12), (22, 15)], 'K', 'S')
        wire(b, [(26, 7), (28, 9)]); wire(b, [(26, 12), (28, 13)])
        for (x, y) in ((33, 6), (35, 10)): b.put(x, y, 'K')
    def bafter(self, b, st):
        if st.fire:
            stamp_flash(b, st, 38, 9)
            for (x, y) in ((43 + 2 * st.i, 4), (44, 14 - st.i)): b.stamp(x, y, art(".o.\noyo\n.o."))
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 38, 9)
        if state in ('idle', 'damaged'): glow(g, ox + 36, oy + 9.5, 7, ORANGE, 0.45 if state == 'idle' else 0.25, 1.8)
        if state == 'damaged' and i == 0: glow(g, ox + 21, oy + 8, 5, ORANGE, 0.3, 2.0)

# ============================================================ QUARRY DRIVER
class QuarryDriver(StoneMount, Weapon):
    id = 'basalt_quarry_driver'
    blen, bwid = 72, 25
    bpivot = (6, 12)
    bmuzzle = (56, 12)
    out_notes = ('OUTSIDE half of the Basalt Quarry Driver: a massive basalt block strapped with iron bands, flame vents on both shoulders (the room vents on fire) and a magma-lit pressure gauge. '
                 'damaged: a band sprung, a stone corner cracked and weeping magma; disabled: scorched, a slab knocked off, dented, sparking.')
    notes = ('INSIDE half of the Basalt Quarry Driver: a hydraulic ram whose piston head draws back as it charges (frame 5 = fully drawn, spring glowing, strip yellow), a round rock slug waiting in the cradle, '
             'iron-strapped stone housing, power coupling, hatch. fire: the piston slams forward and the cradle is empty. damaged: the ram cylinder cracked and leaking magma, slits dead; '
             'disabled: the piston jammed half way, a slug cracked in two. Barrel layer basalt_quarry_driver_barrel: a long thick stone barrel with three iron collars; fire: the slug leaves in a flash and the breech vents flame.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        mat(s, 4, 20, 56, 12, STONE)
        stone(s, 17, 2, 30, 26, 11, seams=[((20, 24), (26, 22))])
        stone(s, 21, 1, 22, 8, 12)
        s.rect(26, 2, 12, 6, 'D'); s.hline(26, 2, 12, 'K')
        mat(s, 16, 9, 32, 5, ('L', 'M', 'S'), cham=False); s.put(32, 12, 'L'); s.put(33, 13, 'W')
        for bx in (21, 40):                                                       # iron straps round the block
            s.vline(bx, 14, 14, 'M'); s.vline(bx + 1, 14, 14, 'S'); s.vline(bx + 2, 14, 14, 'W'); s.put(bx + 1, 17, 'L'); s.put(bx + 1, 24, 'L')
        stone(s, 2, 5, 15, 19, 13)                                                # left shoulder: flame vents
        for k in range(3):
            s.rect(5 + 4 * k, 8, 2, 12, 'D'); s.vline(5 + 4 * k, 8, 12, 'K')
            if pw: s.put(6 + 4 * k, 18, 'r'); s.put(6 + 4 * k, 19, 'o' if (k + i) % 2 else 'r')
        stone(s, 47, 5, 15, 19, 14)                                               # right shoulder: the pressure gauge
        chamfer_fill(s, 50, 8, 9, 9, 'E', 3); rim(s, 'E', 'D', 'M', (50, 8, 58, 16))
        s.put(54, 12, 'L')
        for (dx, dy) in ((0, -3), (2, -2), (3, 0)): s.put(54 + dx, 12 + dy, 'o' if pw else 'W')
        s.hline(50, 19, 3, 'W'); s.hline(54, 19, 2, 'W'); s.hline(57, 19, 2, 'W')
        magma(s, [(17, 17), (20, 21), (19, 27)], pw, i); magma(s, [(46, 17), (43, 22), (45, 27)], pw, i + 1)
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        stone(s, 2, y + 1, 60, 30, 21)
        cable_stub(s, 3, y + 8, st, 'o')
        # the ram: a horizontal cylinder with the piston head that draws back with the charge
        cylh(s, 15, y + 6, 26, 14, 'MSSWWEE'); s.vline(15, y + 6, 14, 'S'); s.vline(40, y + 6, 14, 'E')
        s.rect(17, y + 9, 22, 8, 'D'); s.hline(17, y + 9, 22, 'K')
        n = {'charge': st.i, 'on': 5, 'damaged': 5}.get(st.state, 0)
        if st.state == 'fire': n = 0 if st.i == 1 else 0
        head = 36 - n * 3 if st.state != 'disabled' else 28                           # piston head x: drawn back (left) as charge grows
        if st.state == 'fire' and st.i == 0: head = 36
        s.rect(17, y + 12, max(1, head - 17), 2, 'M')                                # the rod
        bev(s, head - 1, y + 10, 5, 6, 'L', 'M', 'S', cham=False)
        if pw and n >= 1:
            for k in range(n): s.put(18 + 3 * k, y + 10, 'o'); s.put(18 + 3 * k, y + 15, 'o')
            if n == 5: s.put(head + 2, y + 12, 'H')
        # the cradle with a rock slug
        mat(s, 43, y + 6, 17, 14, STONE_D)
        s.rect(46, y + 9, 11, 8, 'D')
        if st.state in ('on', 'damaged', 'off') or (st.charge and st.i == 5) or st.state == 'disabled':
            chamfer_fill(s, 47, y + 10, 9, 6, 'W', 2); rim(s, 'W', 'S', 'E', (47, y + 10, 55, y + 15))
            if pw: magma(s, [(49, y + 11), (51, y + 13), (53, y + 12)], True, st.i)
        hatch_k(s, 46, y + 21, STONE_D, 11, 8, 'o') if False else None
        slits(s, st, STRIP_X, y + STRIP_DY)
        magma(s, [(2, y + 20), (7, y + 22)], pw, st.i)
    def hurt_out(self, s, st):
        magma_crack(s, [(46, 3), (44, 8), (46, 12), (43, 16)], st.i)
        s.vline(22, 14, 8, 'D'); s.put(23, 17, 'K'); move(s, 21, 22, 3, 6, 2, 1)       # a strap sprung
        magma_crack(s, [(9, 7), (8, 12), (10, 17)], st.i + 1)
        hurt_pair(s, st, (7, 4), (55, 20))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(27, 3), (26, 8), (29, 12), (27, 17), (29, 22), (28, 27)], [(52, 7), (54, 12)]],
                 dents=[(6, 11, 6, 4), (50, 20, 7, 4)], soots=[(21, 3, 1), (45, 5, 0), (4, 8, 2)],
                 wires_=[[(12, 22), (10, 26), (8, 28)]], sparks=[(34, 6), (9, 10)])
        fallen_chunk(s, 14, 26)
    def hurt_in(self, s, st):
        y = self.iy
        dead_slits(s, st, y + STRIP_DY)
        magma_crack(s, [(27, y + 6), (28, y + 10), (26, y + 14), (28, y + 19)], st.i)
        s.put(29, y + 21 + st.i, 'o')
        hurt_pair(s, st, (34, y + 8), (52, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(22, y + 6), (24, y + 10), (23, y + 14), (25, y + 19)]); crack(s, [(48, y + 10), (51, y + 13), (53, y + 15)])
        fallen_chunk(s, 30, y + 22); wire(s, [(14, y + 22), (18, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        slits_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        n = {'charge': i, 'on': 5, 'damaged': 5}.get(state, 0)
        for k in range(n): glow(g, ox + 18.5 + 3 * k, oy + y + 10.5, 3, ORANGE, 0.4, 2.0)
        if state in ('on', 'damaged') or (state == 'charge' and i == 5): glow(g, ox + 51, oy + y + 13, 6, ORANGE, 0.4, 2.0)
        glow(g, ox + 12, oy + y + 14, 3, ORANGE, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        for k in range(3): glow(g, ox + 6 + 4 * k, oy + 19, 3.5, ORANGE, 0.35, 2.0)
        glow(g, ox + 57, oy + 11, 3, ORANGE, 0.4, 2.0)
        for (x, y) in ((19, 24), (44, 24)): glow(g, ox + x, oy + y, 5, ORANGE, 0.25, 2.0)
    # ---- barrel (east canvas 72x25)
    def barrel(self, b, st):
        o = -st.rc
        breech_stone(b, 12, 21, 21)
        for yy in (0, 22): b.hline(5, yy, 6, 'D')
        stone_cyl(b, 13 + o, 3, 44, 19, 'SSWWWWEEE')
        for bx in (19, 31, 43): iron_ring(b, bx + o, 2, 21, 3)
        for (x, y) in ((24, 6), (36, 17), (28, 12), (48, 8)): b.put(x + o, y, 'E')
        magma(b, [(22 + o, 5), (30 + o, 5), (42 + o, 5)], True, st.i) if st.state == 'idle' else magma(b, [(22 + o, 5), (30 + o, 5), (42 + o, 5)], st.fire, st.i)
        bev(b, 53 + o, 1, 6, 23, 'M', 'S', 'W'); b.vline(55 + o, 1, 23, 'W')              # the muzzle ring
        b.rect(55 + o, 6, 4, 13, 'D')
        if st.fire: b.rect(56 + o, 7, 3, 11, 'o'); b.rect(57 + o, 8, 2, 9, 'H')
        else: b.rect(57 + o, 8, 2, 9, 'r'); b.rect(58 + o, 10, 1, 5, 'o')
    def bhurt(self, b, st):
        magma_crack(b, [(25, 3), (27, 8), (25, 13), (27, 18), (26, 22)], st.i)
        move(b, 43, 2, 3, 21, 1, 2)
        spark(b, 47, 24 if False else 2, False) if st.i == 0 else spark(b, 24, 2, False)
    def bbreak(self, b, st):
        return cleave(b, lambda y: 38, 3, 3)
    def bwreck(self, b, st):
        crack(b, [(22, 3), (24, 9), (22, 14), (25, 21)], 'K', 'S')
        wire(b, [(37, 8), (40, 10)]); wire(b, [(37, 15), (40, 16)])
    def bafter(self, b, st):
        if st.fire:
            stamp_flash(b, st, 59, 12)
            for k in range(3): b.stamp(6 - k + st.i, 0 if k == 0 else 20 + k, art(".o.\noyo\n.o.")) if False else None
            for (x, y) in ((6, 0), (10, 0), (6, 22), (10, 22)): b.stamp(x, y - 1 if y == 0 else y, art("o\ny")) if False else b.put(x, y, 'y')
            for (x, y) in ((7, 0), (11, 0), (7, 22), (11, 22)): b.put(x, y, 'o')
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            fire_glow(g, ox, oy, i, 59, 12, scale=1.25)
            for x in (6, 10): glow(g, ox + x, oy + 1, 4, ORANGE, 0.5, 2.0); glow(g, ox + x, oy + 23, 4, ORANGE, 0.5, 2.0)
        if state in ('idle', 'damaged'): glow(g, ox + 57, oy + 12.5, 6, ORANGE, 0.35, 1.8)

# ============================================================ PUMICE FLAK (turret)
class PumiceFlak(StoneMount, Weapon):
    id = 'basalt_pumice_flak'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 46, 21
    bpivot = (9, 10)
    bmuzzle = (33, 10)
    out_notes = ('OUTSIDE half of the Basalt Pumice Flak (a TURRET): a stone ring seat, a pumice hopper on the left and an iron valve wheel with a gunner hatch on the right (it is run airless). '
                 'damaged: ring cracked and weeping magma, hopper lid hanging; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Basalt Pumice Flak: a feed rail where pumice rocks roll in one by one as it charges (frame 5 = five rocks loaded, strip yellow), power coupling, stone hatch. '
             'fire: the rail is empty and the strip flashes. damaged: the rail cracked, a rock jammed, slits dead; disabled: rocks spilled, rail snapped. Barrel layer basalt_pumice_flak_barrel: '
             'a porous grey pumice dome head with a short fat mortar mouth and a gunner slit (no sensor: a crew member aims it, in vacuum).')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        mat(s, 6, 19, 52, 13, STONE)
        stone(s, 18, 2, 28, 24, 31)
        turret_ring(s, 32, 15, 25)
        for (x, y) in ((20, 12), (43, 12), (32, 4), (32, 26)): s.put(x, y, 'L')
        stone(s, 3, 6, 16, 18, 33)                                                # left wing: pumice hopper
        s.rect(6, 9, 10, 9, 'D'); s.hline(6, 9, 10, 'K')
        for (dx, dy) in ((1, 5), (4, 4), (7, 5), (2, 2), (5, 1)):
            pumice_ball(s, 6 + dx, 9 + dy) if dy >= 4 else None
        pumice_ball(s, 7, 9 + 4); pumice_ball(s, 11, 9 + 4)
        s.hline(5, 19, 12, 'W'); s.put(5, 20, 'o' if pw else 'E'); s.put(16, 20, 'o' if pw else 'E')
        stone(s, 45, 6, 16, 18, 35)                                               # right wing: valve wheel, hatch
        chamfer_fill(s, 48, 8, 11, 11, 'S', 3); rim(s, 'S', 'M', 'W', (48, 8, 58, 18))
        for k in range(-4, 5, 2): s.put(53 + k, 13, 'L' if k else 'W'); s.put(53, 13 + k, 'M')
        s.put(53, 13, 'a'); s.put(53, 12, 'L')
        s.hline(47, 20, 3, 'W'); s.hline(51, 20, 2, 'W'); s.hline(54, 20, 3, 'W')
        magma(s, [(18, 20), (22, 24), (21, 28)], pw, i); magma(s, [(45, 20), (41, 24), (43, 29)], pw, i + 1)
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        stone(s, 2, y + 1, 60, 30, 41)
        cable_stub(s, 3, y + 8, st, 'o')
        mat(s, 14, y + 8, 33, 11, STONE_D, cham=False)                             # the feed rail
        s.rect(15, y + 11, 31, 5, 'D'); s.hline(15, y + 11, 31, 'K'); s.hline(15, y + 15, 31, 'W')
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 0
        for k in range(5):
            if k < n and pw or (st.state == 'disabled' and k in (0, 2)):
                pumice_ball(s, 16 + 6 * k, y + 10)
        if pw and st.state == 'fire' and st.i == 0:
            s.rect(15, y + 12, 31, 3, 'L')
        hatch_k(s, 49, y + 8, STONE_D, 11, 9, 'o')
        slits(s, st, STRIP_X, y + STRIP_DY)
        for (x, yy) in ((8, 3), (55, 3)): s.put(x, y + yy, 'L')
        magma(s, [(2, y + 21), (7, y + 24)], pw, st.i); magma(s, [(60, y + 20), (56, y + 24)], pw, st.i + 1)
    def hurt_out(self, s, st):
        magma_crack(s, [(31, 3), (30, 7), (32, 10)], st.i)
        magma_crack(s, [(47, 10), (50, 14), (48, 18)], st.i + 1)
        s.stamp(2, 3, FLAP); wire(s, [(8, 7), (10, 9)])
        hurt_pair(s, st, (9, 5), (54, 22))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 3), (30, 8), (32, 12), (30, 17), (31, 22)], [(50, 9), (52, 14), (50, 18)]],
                 dents=[(7, 19, 6, 4), (50, 20, 6, 3)], soots=[(21, 3, 1), (44, 5, 0), (4, 8, 2)],
                 wires_=[[(12, 21), (10, 25), (8, 27)]], sparks=[(35, 6), (8, 12)], flap=(2, 3))
        fallen_chunk(s, 14, 27)
    def hurt_in(self, s, st):
        y = self.iy
        dead_slits(s, st, y + STRIP_DY)
        crack(s, [(24, y + 8), (26, y + 12), (25, y + 18)]); s.stamp(33, y + 12, art("QQq\nqQQ\n.nq"))
        hurt_pair(s, st, (36, y + 9), (52, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(20, y + 8), (22, y + 13), (21, y + 18)]); crack(s, [(36, y + 8), (38, y + 14)])
        fallen_chunk(s, 40, y + 22); wire(s, [(14, y + 20), (18, y + 23)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        slits_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        glow(g, ox + 12, oy + y + 14, 3, ORANGE, 0.5, 2.0)
        if state != 'off': glow(g, ox + 5, oy + y + 22, 6, ORANGE, 0.12, 2.0, sx=2)
    def out_glow(self, state, i, g, ox, oy):
        for (x, y) in ((20, 22), (43, 24)): glow(g, ox + x, oy + y, 5, ORANGE, 0.28, 2.0)
        glow(g, ox + 10, oy + 20.5, 7, ORANGE, 0.22, 2.0, sx=1.5)
    # ---- barrel (east canvas 46x21: a pumice dome, a fat mortar mouth)
    def barrel(self, b, st):
        o = -st.rc
        chamfer_fill(b, 1, 2, 17, 17, 'M', 5); rim(b, 'M', 'L', 'S', (1, 2, 17, 18))                # the dome
        for (x, y) in ((4, 6), (7, 4), (9, 9), (6, 13), (11, 15), (13, 6), (12, 11), (4, 10), (8, 16)): b.put(x, y, 'E' if (x + y) % 2 else 'W')
        b.put(9, 10, 'L'); b.put(10, 10, 'W'); b.put(9, 9, 'M')
        b.rect(11, 8, 4, 5, 'D') if False else None
        cylh(b, 16 + o, 6, 14, 9, 'MSSWWEE')                                       # short fat barrel (lighter stone)
        for (x, y) in ((19, 8), (24, 11), (22, 13)): b.put(x + o, y, 'E')
        iron_ring(b, 20 + o, 5, 11, 2)
        for (x0, x1, y0, y1) in ((29, 31, 4, 16), (32, 34, 3, 17)): cylh(b, x0 + o, y0, x1 - x0 + 1, y1 - y0 + 1, 'MSSWWEE')
        b.rect(32 + o, 5, 3, 11, 'D')
        if st.fire: b.rect(33 + o, 6, 2, 9, 'o'); b.rect(34 + o, 7, 1, 7, 'H')
        else: b.put(33 + o, 10, 'r'); b.put(34 + o, 10, 'o')
        b.hline(11, 9, 5, 'D'); b.hline(11, 10, 5, 'D'); b.put(15, 9, 'o' if st.state == 'idle' else 'E')    # gunner slit
        for (x, y) in ((6, 4), (6, 16)): b.put(x, y, 'L')
    def bhurt(self, b, st):
        crack(b, [(4, 4), (7, 8), (6, 12)], 'K', 'S'); magma_crack(b, [(20, 6), (22, 10), (21, 14)], st.i)
        move(b, 29, 4, 6, 13, 0, 1)
        spark(b, 35, 5, False) if st.i == 0 else spark(b, 12, 3, False)
    def bbreak(self, b, st):
        return cleave(b, lambda y: 28, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(4, 4), (7, 8), (6, 13), (9, 17)], 'K', 'S'); wire(b, [(25, 8), (27, 10)])
    def bafter(self, b, st):
        if st.fire:
            stamp_flash(b, st, 35, 10, FLASH_S)
            for (x, y) in ((40 + st.i * 2, 6), (41 + st.i, 14)):
                if x < 46: b.put(x, y, 'M')
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 35, 10, scale=0.8)
        if state == 'idle': glow(g, ox + 34, oy + 10.5, 4, ORANGE, 0.3, 2.0)

# art 'FLAP' (a cover hanging off a corner) comes from wbase's namespace? defined in comp_w_std; reuse the same shape here
FLAP = art("""
....SSM.
..SSMMS.
SSMMSS..
""")
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

WEAPONS = [MagmaSpitter, QuarryDriver, PumiceFlak]


# ================================================================== COMPONENTS
from lines_shield import seg_ring

class VacuumForge(LK.LComp):
    id = 'basalt_vacuum_forge'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    PULSE = [11, 12, 13, 12]
    VENTS = [(3, 3), (49, 3), (3, 49), (49, 49)]
    notes = ('Basalt "Vacuum Forge" reactor: a rough stone octagon round a crucible of white-hot magma (the core breathes over the 4-frame loop), four chimney vents in the corners (it vents its room: '
             'ember glow at the bottom of every slot) joined to the crucible by magma veins, iron couplings north/east/south/west. '
             'Damaged: the crucible lip has a chunk broken out and magma runs over the stone, the north-west chimney is snapped and leaning, the core stutters. '
             'Disabled: the magma gone to dark crust, the octagon split through, a chimney collapsed, rubble.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 62, 62, 'W', 8); rim(s, 'W', 'S', 'E')
        speckle(s, 2, 2, 61, 61, 5)
        for (a, b) in (((6, 20), (12, 26)), ((50, 38), (56, 44)), ((22, 56), (28, 59)), ((40, 6), (36, 10))): line(s, a[0], a[1], b[0], b[1], 'D')
        for (vx, vy) in self.VENTS:                                               # corner chimneys
            stone(s, vx, vy, 12, 12, vx + vy)
            for k in range(3):
                s.rect(vx + 2 + 3 * k, vy + 2, 2, 8, 'D'); s.vline(vx + 2 + 3 * k, vy + 2, 8, 'K')
                s.put(vx + 3 + 3 * k, vy + 9, ('o' if (k + i) % 2 else 'y') if on else 'E')
        for (x, y, w, h) in ((26, 2, 12, 5), (26, 57, 12, 5), (2, 26, 5, 12), (57, 26, 5, 12)):     # iron couplings
            mat(s, x, y, w, h, ('M', 'S', 'W'), cham=False)
            s.rect(x + w // 2 - 1, y + h // 2 - 1, 2, 2, 'D')
        for (a, b, c) in (((15, 15), (24, 23), 0), ((48, 15), (40, 23), 1), ((15, 48), (24, 41), 2), ((48, 48), (40, 41), 3)):     # veins
            magma(s, [a, b], on, i + c)
        circle(s, 32, 32, 20, 'M'); circle(s, 32, 32, 19, 'S'); ring(s, 32, 32, 17, 19, 'E')     # the crucible lip
        for y in range(11, 54):
            for x in range(11, 54):
                if s.get(x, y) == 'S' and (x - 32) + (y - 32) < -17: s.put(x, y, 'M')
        circle(s, 32, 32, 16, 'D')
        if on:
            r = self.PULSE[i]
            circle(s, 32, 32, r, 'r'); circle(s, 32, 32, r - 1.5, 'o'); circle(s, 32, 32, r - 5, 'y'); circle(s, 32, 32, max(2, r - 8), 'H')
            for (dx, dy) in ((-6, -3), (5, -7), (7, 4), (-4, 7)): s.put(32 + dx + (i % 2), 32 + dy, 'y')
        else:
            circle(s, 32, 32, 13, 'n'); circle(s, 32, 32, 10, 'D')
            for (a, b) in (((24, 28), (31, 34)), ((38, 26), (34, 32)), ((27, 38), (33, 35))): line(s, a[0], a[1], b[0], b[1], 'E')
            for (x, y) in ((28, 30), (36, 36)): s.put(x, y, 'r')
        for (x, y) in ((32, 13), (32, 50), (13, 32), (50, 32)): s.put(x, y, 'L')
        return s
    def hurt(self, s, i):
        for (x, y) in ((44, 20), (45, 20), (45, 21), (46, 21), (46, 22), (45, 22), (44, 21)): s.erase(x, y)              # a chunk out of the lip
        for (x, y) in ((43, 19), (44, 19), (46, 20), (47, 21)): s.put(x, y, 'K')
        magma_crack(s, [(46, 23), (49, 27), (48, 32), (51, 36)], i)
        for (x, y) in ((47, 24), (48, 25), (49, 24)): s.put(x, y, 'o' if (x + i) % 2 else 'y')
        move(s, 3, 3, 12, 6, -1, 2); s.hline(2, 8, 11, 'K'); s.put(5, 2 + i, 'o'); s.put(6, 1, 'y')                      # the NW chimney snapped, leaning
        s.stamp(15, 2, art("KKK.\nKSMK\n.KWK")); 
        if i == 1:
            for (x, y) in ((32, 32), (33, 32), (32, 33), (33, 33)): s.put(x, y, 'o')
        spark(s, 52 if i == 0 else 14, 12 if i == 0 else 52, False)
    def wreck(self, s):
        crack(s, [(3, 14), (9, 20), (13, 27), (20, 32), (22, 40), (30, 46), (31, 52), (38, 58)], 'K')
        crack(s, [(58, 8), (52, 14), (49, 22)], 'K')
        s.rect(5, 5, 9, 6, 'K'); s.stamp(6, 6, art("DD.D\n.DDK")); s.stamp(14, 9, art("KKK\nKSK\n.KK"))
        s.stamp(36, 40, art("KKKK.\nKDDDK\n.KDKK")); fallen_chunk(s, 52, 52); fallen_chunk(s, 8, 52)
        for (x, y) in ((32, 31), (33, 32), (31, 33)): s.put(x, y, 'r')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.85)
        r = self.PULSE[i]
        glow(g, ox + 32, oy + 32, 24 + r, ORANGE, (0.3 + 0.02 * r) * k, 1.4)
        glow(g, ox + 32, oy + 32, 7 + r * 0.6, YEL, 0.55 * k, 1.6)
        for (vx, vy) in self.VENTS: glow(g, ox + vx + 6, oy + vy + 9, 6, ORANGE, 0.4 * k, 2.0)
        for (x, y) in ((19, 19), (44, 19), (19, 44), (44, 44)): glow(g, ox + x, oy + y, 6, ORANGE, 0.3 * k, 2.0)
        if flick is not None: glow(g, ox + 47, oy + 24, 6, YEL, 0.5 if flick else 0.25, 2.0)

class StonehideBay(LK.LComp):
    id = 'basalt_stonehide_bay'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    DMG = (0, 1)
    notes = ('Basalt "Stonehide Plating Bay": a stone cradle with a pale polished slab lying between two iron presses; on loop (2): the presses close on the slab and a magma seam runs along it, then they open. '
             'A stack of finished plates sits in the corner. Damaged: a press arm bent, the slab chipped with a crack leaking light, sparks. Disabled: presses jammed open, the slab split, plates scattered, cold seams.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        stone(s, 1, 1, 30, 30, 61)
        s.rect(4, 4, 24, 14, 'D'); s.hline(4, 4, 24, 'K')                         # the work bay
        close = 1 if (on and i == 1) else 0
        mat(s, 10, 6, 12, 10, ('L', 'M', 'S'), cham=False); s.put(11, 7, 'H'); s.put(20, 14, 'W')       # the pale slab
        if on: magma(s, [(11, 11), (15, 11 + close), (20, 11)], True, i)
        mat(s, 5 + close * 2, 5, 4, 12, STEEL, cham=False); s.vline(5 + close * 2, 5, 12, 'L')        # the presses
        mat(s, 23 - close * 2, 5, 4, 12, STEEL, cham=False)
        for yy in (7, 13): s.put(6 + close * 2, yy, 'W'); s.put(24 - close * 2, yy, 'W')
        for k in range(3):                                                         # finished plates stacked
            mat(s, 4 + k, 21 - k * 0, 10, 3, ('M', 'S', 'W'), cham=False) if False else None
        for k in range(3): mat(s, 4 + (k % 2), 20 + 3 * k - (1 if k == 0 else 0), 11, 3, ('L', 'M', 'S'), cham=False)
        s.put(17, 24, 'g' if on and i == 0 else ('y' if on else 'E')); s.put(17, 26, 'y' if on else 'E')
        for (x, y) in ((22, 21), (25, 21), (22, 25), (25, 25)): s.rect(x, y, 2, 2, 'D')
        s.put(23, 22, 'o' if on else 'E')
        if on: s.put(26, 26, 'o')
        return s
    def hurt(self, s, i):
        move(s, 24, 5, 4, 12, 1, 1 + i); s.vline(26, 16, 2, 'K')
        crack(s, [(15, 6), (16, 9), (14, 12), (16, 15)], 'K'); s.put(15, 9, 'o' if i else 'y'); s.put(16, 12, 'o')
        spark(s, 24, 18 if i == 0 else 4, False)
    def wreck(self, s):
        crack(s, [(15, 6), (16, 9), (14, 12), (16, 15)], 'K'); crack(s, [(9, 20), (12, 23), (14, 27)], 'K')
        move(s, 23, 5, 4, 12, 3, 0); s.vline(24, 5, 12, 'K'); fallen_chunk(s, 6, 25); fallen_chunk(s, 20, 24)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.6 if flick else 0.9)
        if state == 'on':
            glow(g, ox + 16, oy + 11, 9, ORANGE, (0.2 + 0.2 * i) * k, 2.0, sx=1.4)
        glow(g, ox + 23.5, oy + 22.5, 3, ORANGE, 0.5 * k, 2.0)

class GravityAnchor(LK.LComp):
    id = 'basalt_gravity_anchor'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 4, 4), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    DMG = (0, 2)
    notes = ('Basalt "Gravity Anchor": a squat stone block with four iron intake grilles (it pulls air from the rooms next to it) round a ring of heavy iron holding a dark gravity core. '
             'On loop (4): the ring segments turn, the core pulses cyan and pale motes drift in toward it through the grilles. Damaged: one intake grille torn off, the ring chipped and out of true, the core flickering. '
             'Disabled: the core dark and cold, the ring split, the block cracked, a grille hanging.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        stone(s, 1, 1, 30, 30, 71)
        for (x, y, w, h) in ((12, 2, 8, 4), (12, 26, 8, 4), (2, 12, 4, 8), (26, 12, 4, 8)):      # intake grilles
            mat(s, x, y, w, h, ('S', 'W', 'E'), cham=False)
            if w > h:
                for k in range(3): s.hline(x + 1, y + 1, w - 2, 'D') if k == 0 else None
                for xx in range(x + 2, x + w - 1, 2): s.vline(xx, y + 1, h - 2, 'D')
            else:
                for yy in range(y + 2, y + h - 1, 2): s.hline(x + 1, yy, w - 2, 'D')
        circle(s, 16, 16, 10.5, 'M'); circle(s, 16, 16, 9.5, 'S'); ring(s, 16, 16, 8, 9.5, 'E')
        for y in range(5, 28):
            for x in range(5, 28):
                if s.get(x, y) == 'S' and (x - 16) + (y - 16) < -7: s.put(x, y, 'M')
        circle(s, 16, 16, 7.5, 'D')
        if on:
            seg_ring(s, 16, 16, 5.6, 7.4, 4, .55, i * 22.5, 'B', 'c')
            br = (3, 4, 4, 3)[i]
            circle(s, 16, 16, br, 'C'); circle(s, 16, 16, br - 1.5, 'c'); circle(s, 16, 16, max(1, br - 3), 'H')
            for k, (dx, dy) in enumerate(((0, -12), (12, 0), (0, 12), (-12, 0))):         # motes drifting inward
                t = (i + k) % 4
                px, py = 16 + dx - (dx // 12) * t * 1, 16 + dy - (dy // 12) * t * 1
                s.put(px, py, 'L')
        else:
            circle(s, 16, 16, 3, 'E'); circle(s, 16, 16, 1.5, 'W')
        for (x, y) in ((4, 4), (27, 4), (4, 27), (27, 27)): s.put(x, y, 'L')
        return s
    def hurt(self, s, i):
        s.rect(12, 26, 8, 4, '.'); s.stamp(10 + i, 27, art("KKKKK\nKSWWK\n.KKK."))
        crack(s, [(22, 8), (24, 12), (22, 15)], 'K'); crack(s, [(9, 22), (11, 25), (10, 28)], 'K')
        if i == 1:
            for (x, y) in ((15, 15), (16, 15), (15, 16), (16, 16)): s.put(x, y, 'E')
        spark(s, 11, 25 if i == 0 else 7, False)
    def wreck(self, s):
        crack(s, [(4, 4), (9, 9), (12, 14), (16, 16), (20, 22), (27, 27)], 'K'); crack(s, [(27, 4), (22, 9), (19, 13)], 'K')
        s.stamp(4, 25, art("KKKK\nKSWK\n.KWK")); fallen_chunk(s, 22, 24)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.5 if flick else 0.8)
        br = (3, 4, 4, 3)[i]
        glow(g, ox + 16, oy + 16, 11 + br, CYAN, 0.3 * k, 1.6)
        glow(g, ox + 16, oy + 16, 3 + br, WHITE, 0.4 * k, 1.8)

COMPONENTS = [VacuumForge, StonehideBay, GravityAnchor]


# ================================================================== PROJECTILES AND IMPACTS (glowing slag, rock shards)
def _slag():
    head = art("""
..oooo..
.oyyyyo.
oyHHHHyo
oyHHHHyo
oyyHHyyo
.oyyyyo.
.orooro.
..orro..
""")
    tails = [art("""
...or...
...oo...
..r.o...
...r....
........
........
"""), art("""
..oro...
...oo...
...r.o..
....r...
...r....
........
"""), art("""
...or...
..o.o...
...oo...
..r.....
....r...
...r....
"""), art("""
..ro....
...oo...
...or...
....r...
...r.o..
........
""")]
    out = []
    for k, t in enumerate(tails):
        s = Spr(8, 14); s.stamp(0, 0, head); s.stamp(0, 8, t)
        if k % 2: s.put(3, 2, 'y'); s.put(4, 3, 'y')
        out.append(s)
    return out

def _slag_impact():
    f = []
    s = Spr(16, 16); disc(s, 8, 8, 5.5, 'r'); disc(s, 8, 8, 4.5, 'o'); disc(s, 8, 8, 3, 'y'); disc(s, 8, 8, 1.5, 'H')
    for (x, y) in ((8, 1), (8, 14), (1, 8), (14, 8)): s.put(x, y, 'o')
    f.append(s)
    s = Spr(16, 16); rays(s, 8, 8, 8, 5, 8, 'yoo', 0.2); disc(s, 8, 8, 4, 'o'); disc(s, 8, 8, 2.5, 'y'); disc(s, 8, 8, 1, 'H'); dots(s, 8, 8, 5, 8, 'r', 0.55)
    f.append(s)
    s = Spr(16, 16); disc(s, 8, 8, 3.5, 'r'); disc(s, 8, 8, 2.5, 'o'); s.put(7, 7, 'y'); s.put(8, 8, 'y')
    rays(s, 8, 8, 8, 6, 7, 'oo', 0.2); dots(s, 8, 8, 5, 6, 'r', 0.3); dots(s, 8, 8, 7, 8, 'o', 0.6, 2)
    f.append(s)
    s = Spr(16, 16); disc(s, 8, 8, 3, 'r'); disc(s, 8, 8, 1.8, 'o'); dots(s, 8, 8, 6, 6, 'r', 0.3); dots(s, 8, 8, 4, 4, 'n', 0.9)
    f.append(s)
    return f

def _slug():
    body = art("""
...KKKK...
..KEWSWK..
.KEWSMSWK.
.KESSSSWK.
KEWSSoSWWK
KEWSoyoSWK
.KEWSoSWK.
.KEWWSWEK.
..KEWWEK..
...KKKK...
""")
    out = []
    for k in range(3):
        s = Spr(10, 20); s.stamp(0, 0, body)
        cx = [(4, 5), (5, 6), (4, 4)][k]
        for (x, y) in ((4, 5), (5, 5), (4, 4), (5, 6)): s.put(x, y, 'o' if k != 1 else 'y')
        s.put(cx[0], cx[1], 'H') if k == 2 else None
        tail = [("..o..r..o.", ".r..o.r...", "....y.....", "..r....r..", "..........", "..........", "..........", "..........", "..........", ".........."),
                ("...o.r.o..", "..r..o...r", "..o..y..r.", "....r.....", "..o.......", "..........", "..........", "..........", "..........", ".........."),
                (".o...r..o.", "...o...r..", ".r..y..o..", "..r....r..", "....o.....", "..........", "..........", "..........", "..........", "..........")][k]
        for j, row in enumerate(tail):
            for i, c in enumerate(row):
                if c != '.': s.put(i, 10 + j, c)
        out.append(s)
    return out

def _slug_impact():
    f = []
    s = Spr(24, 24); disc(s, 12, 12, 8, 'o'); disc(s, 12, 12, 6.5, 'y'); disc(s, 12, 12, 4, 'H'); rays(s, 12, 12, 8, 7, 11, 'yo', 0.4)
    f.append(s)
    s = Spr(24, 24); disc(s, 12, 12, 5, 'o'); disc(s, 12, 12, 3, 'y'); disc(s, 12, 12, 1.5, 'H')
    for k, (dx, dy) in enumerate(((7, -2), (5, 6), (-3, 7), (-8, 2), (-6, -6), (1, -9), (9, 5), (-9, -1))):
        shard(s, 12 + dx, 12 + dy, 'M' if k % 2 else 'S', 'W' if k % 2 else 'E')
    rays(s, 12, 12, 8, 8, 10, 'oy', 0.4)
    f.append(s)
    s = Spr(24, 24); ring(s, 12, 12, 5, 7, 'W'); disc(s, 12, 12, 3.5, 'r'); disc(s, 12, 12, 2, 'o')
    for k, (dx, dy) in enumerate(((10, -4), (7, 9), (-5, 10), (-11, 3), (-9, -9), (2, -11), (11, 6), (-11, -2))):
        shard(s, 12 + dx, 12 + dy, 'S', 'E') if k % 2 else shard(s, 12 + dx, 12 + dy, 'M', 'W')
    dots(s, 12, 12, 9, 8, 'o', 0.2)
    f.append(s)
    s = Spr(24, 24); ring(s, 12, 12, 6, 9, 'E'); ring(s, 12, 12, 8, 9, 'D'); disc(s, 12, 12, 2, 'r')
    for (dx, dy) in ((11, -5), (8, 9), (-6, 11), (-11, 3)): s.put(12 + dx, 12 + dy, 'W')
    dots(s, 12, 12, 5, 6, 'W', 0.1); dots(s, 12, 12, 3, 4, 'r', 0.5)
    f.append(s)
    return f

def _pumice():
    """a light porous rock, 8x8, tumbling (the pores move), with a puff of grey smoke behind it: 8 wide x 15 tall."""
    base = ["..MLLM..", ".MLMMSW.", "MLMMSSSW", "MMSMSSWE", "MSSSMSWE", ".SSSSWWE", "..SWWEE.", "...EE..."]
    pores = [[(2, 2), (5, 3), (3, 5), (6, 5)], [(3, 2), (6, 3), (2, 4), (5, 6)], [(2, 3), (4, 2), (6, 4), (3, 6)], [(5, 2), (2, 4), (4, 5), (6, 6)]]
    smoke = [art("""
..L..L..
.LML....
..L..L..
.L...M..
"""), art("""
.L..L...
..LML..L
.L...L..
...L..M.
"""), art("""
..L...L.
.L.ML...
...L..L.
.M..L...
"""), art("""
.L...L..
..LM..L.
.L..L...
..M...L.
""")]
    out = []
    for k in range(4):
        s = Spr(8, 15)
        s.stamp(0, 0, base)
        for (x, y) in pores[k]: s.put(x, y, 'E')
        for (x, y) in ((1, 1 + k % 2), (3, 4 - k % 2)): s.put(x + k % 2, y, 'H') if s.get(x + k % 2, y) == 'L' else None
        for j, row in enumerate(smoke[k]):
            for i, c in enumerate(row):
                if c != '.': s.put(i, 9 + j, c)
        out.append(s)
    return out

def _pumice_impact():
    f = []
    s = Spr(20, 20); disc(s, 10, 10, 6.5, 'o'); disc(s, 10, 10, 5, 'y'); disc(s, 10, 10, 3, 'H'); rays(s, 10, 10, 8, 6, 9, 'yo', 0.3)
    f.append(s)
    s = Spr(20, 20); ring(s, 10, 10, 4, 7, 'L'); disc(s, 10, 10, 4, 'o'); disc(s, 10, 10, 2, 'y')
    for k, (dx, dy) in enumerate(((7, -3), (4, 7), (-5, 6), (-8, 0), (-5, -7), (2, -8))): s.rect(10 + dx, 10 + dy, 2, 2, 'M' if k % 2 else 'L')
    rays(s, 10, 10, 8, 7, 9, 'o', 0.1)
    f.append(s)
    s = Spr(20, 20); ring(s, 10, 10, 6, 9, 'M'); ring(s, 10, 10, 8, 9, 'S'); disc(s, 10, 10, 2.5, 'r'); disc(s, 10, 10, 1.5, 'o')
    for (dx, dy) in ((9, -4), (6, 8), (-7, 7), (-9, 2), (-6, -8)): s.put(10 + dx, 10 + dy, 'M')
    dots(s, 10, 10, 5, 6, 'o', 0.4)
    f.append(s)
    s = Spr(20, 20); ring(s, 10, 10, 7, 9, 'S'); dots(s, 10, 10, 8, 12, 'L', 0.2, 2); dots(s, 10, 10, 4, 5, 'r', 0.3)
    f.append(s)
    return f

PROJECTILES = [
    Proj('basalt_magma_spitter', _slag(), _slag_impact(), (4, 3), (4, 13), fps=12, ifps=12, pad=5, ipad=5, bands=((1.5, 120), (3.5, 60), (5.0, 26)),
         notes='A glob of glowing slag, 8x14: a yellow-white core in an orange skin with a red rim, and a tail of drips (4 frames, 12 fps; the core flutters). Head anchor is the glob centre.',
         inotes='The slag splats: a bright disc, a spatter of droplets, a cooling puddle, embers (4 frames).'),
    Proj('basalt_quarry_driver', _slug(), _slug_impact(), (5, 5), (5, 11), fps=10, ifps=12, pad=4, ipad=6, src='HyoraA',
         notes='A huge rock slug, 10x20: a dark chipped stone ball with a glowing crack that turns over 3 frames, and a trail of embers. Pierces 3 targets: play the impact at every hit.',
         inotes='The slug shatters: a white-orange flash, then rock shards fly out with sparks, then a settling dust ring (4 frames, 24x24).'),
    Proj('basalt_pumice_flak', _pumice(), _pumice_impact(), (4, 4), (4, 9), fps=12, ifps=14, pad=3, ipad=4, src='HyoraA',
         notes='A pale pumice rock, 8x15 with its smoke, tumbling over 4 frames (the pores move), a puff of grey smoke behind it. Splash flak: explode it at the target or when its time is up.',
         inotes='The rock bursts into a fiery puff with grey chips and a smoke ring (4 frames, 20x20).'),
]
