"""Laser Mk1, 4x5 cells, hull mount: outside (turret seat, power cells, sensor), wall collar, inside (cell bank, hatch, charge strip).
Two layers: this mount and the ribbed-barrel head (`barrel`, drawn pointing up, pivot at the turret ring centre)."""
from wbase import *

FLAP = art("""
....SSM.
..SSMMS.
SSMMSS..
""")

class Laser(Weapon):
    id = 'laser_mk1'
    blen, bwid = 56, 19
    pivot = (32, 12)
    bpivot = (6, 9)
    bmuzzle = (41, 9)
    out_notes = ('OUTSIDE half of the Laser Mk1 (a FIXED gun): a forward-heavy housing with the barrel in a sleeve and gimbal collar, copper power cells, sensor dome and antenna; the bottom flange overhangs the outer wall face. '
                 'damaged: antenna bent, wing and ring cracked, cover flapping; disabled: scorched and dented, ring cracked, sparking (2 frames), never destroyed.')
    notes = ('INSIDE half of the Laser Mk1 (hull mount, outward = up; the top flange overhangs the inner wall face, see offset): cell bank, repair hatch, power coupling, 5-cell charge strip. '
             'charge: frame round(fraction*5); frame 5 = ready (all green); fire: the strip discharges (flash, then dark). '
             'damaged: last cells dead, a cell cracked, sparks; disabled: dark, cracked. The rotating head is laser_mk1_barrel (idle, fire, damaged, disabled).')

    # ---------------------------------------------------------------- mount: outside
    def outside(self, s, st):
        pw = st.powered
        gun_housing(s)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')                                   # left wing: power cells
        for cx in (5, 8, 11):
            s.rect(cx, 8, 2, 14, 'q'); s.vline(cx, 8, 14, 'Q'); s.vline(cx + 1, 8, 14, 'n')
        s.rect(3, 12, 1, 4, 'D'); s.put(3, 13, 'g' if pw else 'E'); s.put(3, 14, 'g' if pw else 'E')
        for cy in (8, 20): s.rect(14, cy, 3, 2, 'q'); s.hline(14, cy, 3, 'Q')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')                                  # right wing: sensor and decals
        s.rect(52, 2, 4, 4, 'W'); s.put(52, 2, 'M'); s.put(52, 3, 'M'); s.put(53, 1, 'c' if pw else 'E')
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
    # ---------------------------------------------------------------- mount: inside
    def inside(self, s, st):
        y = self.iy
        housing(s, y)
        coupling(s, 3, y + 8, st)
        for cx in (16, 22, 28, 34):                                            # the cell bank
            cylv(s, cx, y + 6, 5, 15, 'QQqqn')
        for cy in (y + 9, y + 17): s.hline(15, cy, 24, 'S'); s.hline(15, cy + 1, 24, 'W')
        bev(s, 42, y + 6, 19, 16, 'M', 'S', 'W')                               # breech block
        hatch(s, 46, y + 8, st)
        for vx in (45, 49, 53, 57): s.rect(vx, y + 19, 3, 1, 'D')
        s.hline(4, y + 25, 2, 'W'); s.hline(7, y + 25, 3, 'W'); s.hline(55, y + 25, 3, 'W'); s.hline(59, y + 25, 2, 'W')    # registry stencil
        strip(s, st, STRIP_X, y + STRIP_DY)
    # ---------------------------------------------------------------- mount: damage
    def hurt_out(self, s, st):
        s.erase(53, 1); s.put(54, 1, 'S'); s.put(55, 1, 'W'); s.put(56, 2, 'S')           # antenna bent over
        crack(s, [(54, 6), (53, 9), (55, 11), (52, 14), (53, 17), (51, 20)])               # right wing and dome cracked
        crack(s, [(24, 9), (26, 12), (25, 16), (28, 19)])                                   # turret ring cracked
        s.stamp(2, 5, FLAP)                                                                 # the wing cover flaps on one corner
        wire(s, [(10, 6), (12, 7), (14, 7)])
        spark(s, 10, 4, False) if st.i == 0 else spark(s, 52, 13, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(24, 8), (26, 11), (25, 15), (28, 18), (27, 22)], [(52, 7), (53, 10), (51, 14), (54, 18)]],
                 dents=[(6, 16, 5, 6), (49, 17, 6, 4)], soots=[(20, 3, 0), (46, 5, 1), (8, 7, 2)],
                 wires_=[[(10, 6), (12, 8), (13, 11)]], sparks=[(30, 6), (12, 12)], flap=(2, 5))
        s.put(52, 3, 'E'); s.erase(53, 1)
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(23, y + 6), (24, y + 10), (22, y + 14)])                                 # a cell cracked
        spark(s, 24, y + 9, False) if st.i == 1 else spark(s, 56, y + 14, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(23, y + 6), (24, y + 10), (22, y + 14), (25, y + 18)])
        crack(s, [(48, y + 8), (51, y + 11), (50, y + 14)])
        wire(s, [(14, y + 19), (16, y + 22), (19, y + 23)])

    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        glow(g, ox + 12, oy + y + 14, 3, (107, 211, 74), 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 3.5, oy + 14, 4, (107, 211, 74), 0.5, 2.0)
        glow(g, ox + 52.5, oy + 11.5, 5, (60, 242, 255), 0.35, 2.0)

    # ---------------------------------------------------------------- barrel (east-pointing scratch canvas)
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 13 + o, 4, 28, 11)
        for rx in (18, 23, 28, 33):
            bev(b, rx + o, 3, 3, 13, 'L', 'M', 'S', cham=False)
            b.vline(rx + o + 2, 3, 13, 'W'); b.hline(rx + o, 15, 3, 'W')
        bev(b, 37 + o, 3, 5, 13, 'S', 'E', 'D')
        lens(b, 39 + o, 6, 3, 7, st.fire)
        if not st.fire: b.put(41 + o, 9, 'r')
        breech(b, 9, 15)
    def bhurt(self, b, st):
        b.rect(28, 3, 3, 13, '.'); b.rect(28, 3, 3, 1, 'S')                                # one ring torn off ...
        wire(b, [(29, 4), (29, 5)]); wire(b, [(28, 15), (29, 17), (30, 18)])
        bev(b, 29, 16, 3, 3, 'L', 'M', 'S', cham=False)                                    # ... and swinging by its wire
        crack(b, [(37, 4), (39, 7), (38, 10), (40, 14)])
        b.put(41, 9, 'r' if st.i == 0 else 'E')
        spark(b, 31, 17, False) if st.i == 0 else spark(b, 39, 8, False)
    def bbreak(self, b, st):
        return cleave(b, lambda y: 25, 2, 3)
    def bwreck(self, b, st):
        for y in (6, 12): wire(b, [(25, y), (27, y + 1), (29, y + 1)])
        crack(b, [(38, 7), (40, 10), (39, 13), (42, 15)], 'K', 'S')
        b.rect(42, 12, 3, 4, 'D'); b.put(43, 13, 'S'); b.put(44, 15, 'S')
        wire(b, [(27, 18), (27, 20)])
    def bafter(self, b, st):
        if st.fire: b.stamp(41 - st.rc, 9 - len(FLASH_E[st.i]) // 2, FLASH_E[st.i])
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            rc = (2, 1, 0)[i]
            glow(g, ox + 44 - rc, oy + 9.5, (16, 11, 8)[i], (255, 130, 50), (0.65, 0.5, 0.35)[i], 2.0, sx=1.3)
            glow(g, ox + 43 - rc, oy + 9.5, (8, 5, 3)[i], (255, 235, 160), (0.75, 0.55, 0.4)[i], 1.6)
        if state == 'damaged' and i == 0: glow(g, ox + 41, oy + 9.5, 4, (255, 80, 60), 0.4, 2.0)
