"""Tractor Beam turrets Mk1 / Mk2 (hull mounts, turret format): inside = capacitor and coil bank with a charge strip; outside = ring base with a coil block and a sensor;
the swivelling head is a flared emitter (a stack of copper coil rings round a lens, mint when it pulls). `fire` = the beam is on (3 head frames: the rings light up one by one
and wavefronts leave the lens), there is no recoil. The beam strip itself is art/projectiles/tractor_beam.png."""
from mnt import *
from comp_salvage import MINT, coil_seg

class Tractor(Mount):
    aim = 'turret'; has_barrel = True; line = 'standard'
    cells = (4, 2); pivot = (32, 15)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('charge', 'charge', 6, 0), ('fire', 'fire', 2, 12), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    banims = [('idle', 'idle', 1, 0), ('fire', 'fire', 3, 10), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    tier = 1
    blen, bwid = 36, 23
    @property
    def cy(self): return (self.bwid - 1) // 2
    bpivot = (9, 11); bmuzzle = (33, 11)
    bpad = 10
    bnotes = ('Rotating emitter head, drawn pointing UP. Turn it about anchors.pivot placed on pivot_on_base of <id>_out; it swivels in its ring and aims itself (turret). '
              'fire = the beam is on: 3 frames, the coil rings light mint one by one and wavefronts leave the lens (no recoil). damaged: a ring bent off, cracked, sparking; disabled: a ring snapped, dark.')
    def inside(self, s, st):
        y = self.iy
        housing(s, y)
        coupling(s, 3, y + 8, st)
        for cx in (16, 21, 26, 31, 36)[: 4 + self.tier - 1]:                                  # the coil bank: copper windings
            cylv(s, cx, y + 6, 4, 15, 'YTun')
            for cy_ in range(y + 8, y + 20, 3): s.hline(cx, cy_, 4, 'n')
        for cy_ in (y + 9, y + 17): s.hline(15, cy_, 5 * (4 + self.tier - 1) + 2, 'S'); s.hline(15, cy_ + 1, 5 * (4 + self.tier - 1) + 2, 'W')
        bev(s, 42 + (5 if self.tier > 1 else 0), y + 6, 19 - (5 if self.tier > 1 else 0), 16, 'M', 'S', 'W')
        hatch(s, 46 + (4 if self.tier > 1 else 0), y + 8, st, 11 - (4 if self.tier > 1 else 0), 9)
        for vx in (45, 49, 53, 57): s.rect(vx, y + 19, 3, 1, 'D')
        s.hline(4, y + 25, 2, 'W'); s.hline(7, y + 25, 3, 'W'); s.hline(55, y + 25, 3, 'W')
        strip(s, st, STRIP_X, y + STRIP_DY, cols=('a', 'y', 'h'))
        if st.state == 'fire' and st.powered:
            for k in range(5): s.put(STRIP_X + 8 * k + 2, y + STRIP_DY + 2, 'h' if (k + st.i) % 2 else 'H')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY); crack(s, [(23, y + 6), (24, y + 10), (22, y + 14)])
        spark(s, 24, y + 9, False) if st.i == 1 else spark(s, 56, y + 14, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(23, y + 6), (24, y + 10), (22, y + 14), (25, y + 18)]); crack(s, [(48, y + 8), (51, y + 11), (50, y + 14)])
        wire(s, [(14, y + 19), (16, y + 22), (19, y + 23)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        strip_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, ready_rgb=MINT, live_rgb=(255, 210, 58))
        if state in ('fire', 'on', 'charge'): glow(g, ox + 12, oy + y + 14, 3, MINT, 0.4, 2.0)
        if state == 'fire':
            for k in range(4 + self.tier - 1): glow(g, ox + 18 + 5 * k, oy + y + 13, 5, MINT, 0.22 + 0.08 * ((k + i) % 2), 2.0)
    # ---- outside
    def outside(self, s, st):
        pw = st.powered
        turret_seat(s, 32, 15)
        bev(s, 3, 6, 16, 18, 'M', 'S', 'W')                                                  # left: the coil canister
        for cx in (6, 9, 12): cylv(s, cx, 8, 2, 14, 'YTun') if False else (s.rect(cx, 8, 2, 14, 'T'), s.vline(cx, 8, 14, 'Y'), s.vline(cx + 1, 8, 14, 'u'))
        for cy_ in (11, 15, 19): s.hline(5, cy_, 10, 'n')
        s.rect(3, 12, 1, 4, 'D'); s.put(3, 13, 'h' if pw else 'E'); s.put(3, 14, 'h' if pw else 'E')
        bev(s, 45, 6, 16, 18, 'M', 'S', 'W')                                                 # right: a sensor
        s.stamp(50, 9, art("""
.KKKK.
KDDDDK
KDhDDK
KDDDDK
KDDDDK
.KKKK.
"""))
        if pw and (st.state != 'on' or st.i == 0): s.put(52, 12, 'h'); s.put(53, 11, 'h')
        else: s.put(52, 12, 'E')
        for hx in range(48, 58, 4):
            for k in range(3): s.put(hx + k, 18 + k, 'a'); s.put(hx + k + 1, 18 + k, 'D')
        bolts(s, [(47, 8), (58, 8), (47, 22)])
        turret_ring(s, 32, 15)
        for (x, y) in ((24, 8), (40, 8), (24, 22), (40, 22)): s.put(x, y, 'L')
        if self.tier > 1:
            s.hline(20, 4, 24, 'M'); s.hline(20, 5, 24, 'S')
            for x in (24, 32, 40): s.put(x, 4, 'h' if pw else 'E')
    def hurt_out(self, s, st):
        crack(s, [(54, 6), (53, 9), (55, 11), (52, 14), (53, 17)]); crack(s, [(24, 9), (26, 12), (25, 16), (28, 19)])
        s.stamp(2, 5, FLAP); wire(s, [(10, 6), (12, 7), (14, 7)])
        spark(s, 10, 4, False) if st.i == 0 else spark(s, 52, 13, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(24, 8), (26, 11), (25, 15), (28, 18), (27, 22)], [(52, 7), (53, 10), (51, 14), (54, 18)]],
                 dents=[(6, 16, 5, 6), (49, 17, 6, 4)], soots=[(20, 3, 0), (46, 5, 1), (8, 7, 2)], wires_=[[(10, 6), (12, 8), (13, 11)]], sparks=[(30, 6), (12, 12)], flap=(2, 5))
    def out_glow(self, state, i, g, ox, oy):
        if state != 'disabled':
            glow(g, ox + 3.5, oy + 13.5, 4, MINT, 0.5, 2.0)
            glow(g, ox + 52.5, oy + self.cy + 0.5, 5, MINT, 0.35, 2.0)
    # ---- the emitter head (east-pointing canvas): a hub in the ring, a boom, flared coil rings round a lens
    def barrel(self, b, st):
        cy = self.cy; n = 3 + self.tier - 1; fire = st.fire; k = st.i + 1 if fire else 0
        hub(b, cy, 17)
        b.hline(14, cy - 1, 8 + 5 * (n - 1), 'M'); b.hline(14, cy, 8 + 5 * (n - 1), 'S'); b.hline(14, cy + 1, 8 + 5 * (n - 1), 'W')      # the axial rod
        for q in range(n):
            x = 17 + 5 * q; hh = 4 + 2 * q + (1 if self.tier > 1 else 0)                                         # rings flare outward
            lit = fire and q < k
            for yy in range(cy - hh, cy + hh + 1):
                tone = 'Y' if yy < cy - hh + 2 else ('u' if yy > cy + hh - 2 else 'T')
                if lit: tone = 'h' if abs(yy - cy) < hh - 1 else 'H'
                b.put(x, yy, tone); b.put(x + 1, yy, 'n' if not lit else 'h'); b.put(x + 2, yy, 'u' if not lit else 'C')
            b.put(x, cy - hh, 'L'); b.put(x, cy + hh, 'W'); b.put(x + 1, cy - hh, 'L'); b.put(x + 1, cy + hh, 'W')
        tx = 17 + 5 * (n - 1) + 4
        b.rect(tx, cy - 2, 3, 5, 'S'); b.hline(tx, cy - 2, 3, 'M')
        lens_c(b, tx + 1, cy - 1, 2, 3, fire or st.state == 'idle', ('C', 'h', 'h', 'H')) if fire or st.state == 'idle' else lens_c(b, tx + 1, cy - 1, 2, 3, False, None)
        pod(b, 10, 0, 'h') if self.tier == 1 else (pod(b, 10, 0, 'h'), pod(b, 10, self.bwid - 4, 'c'))
    def bafter(self, b, st):
        if st.fire:
            tx = 17 + 5 * (3 + self.tier - 2) + 8
            for q, (r_, a_) in enumerate(((2, 'h'), (4, 'h'), (6, 'C'))):                                         # wavefronts leaving the lens, getting wider
                if q <= st.i:
                    x0 = tx + 1 + q * 2
                    for yy in range(-r_, r_ + 1):
                        if abs(yy) > r_ - 1 or q == 0: b.put(x0 + int(abs(yy) * 0.25), self.cy + yy, a_)
    def bhurt(self, b, st):
        n = 3 + self.tier - 1
        x = 17 + 5 * (n - 1); hh = 4 + 2 * (n - 1) + (1 if self.tier > 1 else 0)
        b.rect(x, self.cy - hh, 3, 2 * hh + 1, '.'); b.rect(x, self.cy - hh, 3, 2, 'u')
        wire(b, [(x + 1, self.cy - hh + 2), (x + 2, self.cy - hh + 4)]); wire(b, [(x, self.cy + hh - 1), (x + 1, self.cy + hh + 2)])
        bev(b, x + 1, self.cy + hh + 2, 3, 3, 'L', 'M', 'S', cham=False)
        crack(b, [(20, 8), (21, 11), (20, 14)])
        b.rect(x + 7, self.cy - 1, 3, 3, 'E')
        spark(b, x + 2, self.cy + hh + 4, False) if st.i == 0 else spark(b, x - 3, self.cy - hh + 1, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 17 + 5 * (2 + self.tier - 1) - 1, 2, 3)
    def bwreck(self, b, st):
        n = 3 + self.tier - 1; x = 17 + 5 * (n - 1)
        for y in (7, 15): wire(b, [(x - 2, y), (x, y + 1), (x + 2, y + 1)])
        crack(b, [(20, 6), (21, 11), (20, 16)], 'K', 'S')
    def bglow(self, state, i, g, ox, oy):
        n = 3 + self.tier - 1
        if state == 'fire':
            for q in range(n):
                if q <= i: glow(g, ox + 18.5 + 5 * q, oy + self.cy + 0.5, 6 + q, MINT, 0.45, 2.0)
            glow(g, ox + 17 + 5 * (n - 1) + 9, oy + self.cy + 0.5, 7 + 2 * i, MINT, 0.5, 2.0, sx=1.4)
        elif state == 'idle': glow(g, ox + 17 + 5 * (n - 1) + 5, oy + self.cy + 0.5, 3, MINT, 0.45, 2.0)
        if state == 'damaged' and i == 0: glow(g, ox + 17 + 5 * (n - 1) + 5, oy + self.cy + 0.5, 4, (255, 80, 60), 0.4, 2.0)

class TractorMk1(Tractor):
    id = 'tractor_mk1'; tier = 1
    notes = ('INSIDE half of the Tractor Beam Mk1 (a turret): a bank of four copper coils, a repair hatch, power coupling and a 5-cell charge strip (frame 5 = ready, mint). '
             'fire: the beam is on, the strip pulses. The head tractor_mk1_barrel swivels in the ring. Hold Q: pulls debris within 300 px toward the nearest intake.')
    out_notes = ('OUTSIDE half of the Tractor Beam Mk1 (a TURRET): turret-ring base, a copper coil canister and a mint sensor. damaged: ring and wing cracked, cover flapping; disabled: scorched, dented, sparking.')
class TractorMk2(Tractor):
    id = 'tractor_mk2'; tier = 2
    blen, bwid = 41, 27
    bpivot = (9, 13); bmuzzle = (38, 13)
    notes = ('INSIDE half of the Tractor Beam Mk2 (a turret): five coils, a smaller hatch, the 5-cell mint strip. Hold Q: pulls debris within 450 px.')
    out_notes = ('OUTSIDE half of the Tractor Beam Mk2 (a TURRET): the Mk1 base with a mint-lit crown bar across the top; the head has four flared rings and twin pods.')
    def barrel(self, b, st):
        Tractor.barrel(self, b, st)

ALL = [TractorMk1, TractorMk2]
