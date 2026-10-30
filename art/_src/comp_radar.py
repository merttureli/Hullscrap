"""Radars (hull mounts): an inside console with a sweep animation on its screen, an outside 2x2 turntable base, and the dish as the rotating `_barrel`
part, drawn pointing UP (the game spins it; `aim` is "spin"). radar_mk1..mk3 (standard), listening_horn_scrap (scrap), lumen_eye_neon (neon)."""
from mnt import *
from lines_kit import navy_panel, crystal
from comp_salvage import pull_glow

class Radar(Mount):
    aim = "spin"; has_barrel = True
    cells = (2, 2); pivot = (16, 15)
    blen, bwid = 26, 25
    bpivot = (6, 12); bmuzzle = (24, 12)
    bpad = 8
    glow_pad = (8, 8, 8, 8)
    out_anims = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 2, 3)]
    banims = [('idle', 'idle', 2, 3), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    SW = 8
    @property
    def anims(self): return [('on', 'on', self.SW, 8), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    bnotes = ('Rotating dish, drawn pointing UP; turn it about anchors.pivot placed on pivot_on_base of <id>_out. It spins continuously (`aim: spin`; sweep speed is the game\'s). '
              'idle: 2 frames (a blinking lamp); damaged: bent and cracked, sparking; disabled: broken and dark (it stops turning).')
    DISH_W = 25
    # ---- the outside base: a 2x2 turntable the dish turns on
    def base(self, s, st): raise NotImplementedError
    def outside(self, s, st): self.base(s, st)
    def bglow(self, state, i, g, ox, oy): pass

    # ---- shared inside console pieces
    def console_frame(self, s, y0, st, line_, W):
        housing_w(s, y0, W, line_)
    def sweep_state(self, st):
        """frame index for the sweep, or None for a dead scope."""
        if st.state in ('on',): return st.i
        if st.state == 'damaged': return (0, 5)[st.i]
        return None
    def hurt_scope(self, s, x, y, w, h, st):
        """a damaged scope: a rolling glitch band, dead pixels."""
        gy = y + 3 + (st.i * 5) % (h - 6)
        s.hline(x + 1, gy, w - 2, 'E'); s.hline(x + 1, gy + 1, w - 2, 'I' if self.line == 'neon' else 'D')
        s.put(x + 3, y + h - 4, 'K'); s.put(x + w - 5, y + 4, 'K')

# ------------------------------------------------------------------ dish drawings (east-pointing scratch canvas)
def bowl(b, cy, hh, xr0, depth, xap, ribs=0, line_='standard', lit=True):
    """a parabolic reflector seen from the side, opening to the east: a lit rear skin, a dark inside with range-ring arcs, a bright aperture rim."""
    for y in range(cy - hh, cy + hh + 1):
        dy = (y - cy) / float(hh)
        xr = xr0 + int(round(depth * dy * dy))
        for x in range(xr, xap + 1):
            d = x - xr
            if d == 0: c = 'L' if y <= cy else 'M'
            elif d == 1: c = 'M' if y <= cy else 'S'
            elif d in (4, 8): c = 'W'
            else: c = 'D' if d < 3 else 'E' if d < 9 else 'D'
            b.put(x, y, c)
        b.put(xap, y, 'L'); b.put(xap - 1, y, 'M') if xap - xr > 3 else None
    for k in range(ribs):
        yy = cy - hh + int((k + 1) * (2 * hh) / (ribs + 1.0))
        dy = (yy - cy) / float(hh); xr = xr0 + int(round(depth * dy * dy))
        line(b, xr0 + 2, cy, xap - 2, yy, 'W')

def feed(b, cy, x0, x1, lamp, on, forks=0):
    b.hline(x0, cy - 1, x1 - x0, 'M'); b.hline(x0, cy, x1 - x0, 'S')
    bev(b, x1 - 1, cy - 2, 4, 5, 'L', 'M', 'S', cham=False)
    b.put(x1 + 2, cy, lamp if on else 'E')

# ------------------------------------------------------------------ Radar Mk1 / Mk2 (standard)
class RadarMk1(Radar):
    id = 'radar_mk1'; line = 'standard'; tier = 1
    notes = ('INSIDE half of the Radar Mk1 (standard, 2x2): a small console with a round scope. on: the sweep line turns one step per frame (8 frames) with a fading trail and blips that light as it passes; '
             'damaged: glitch band and dead pixels, the sweep stutters; disabled: a dead, dark screen. Range 6,000 px: shows "contact" and the bearing.')
    out_notes = ('OUTSIDE half of the Radar Mk1 (standard, 2x2): a turntable base with a slip ring and a lamp; the dish (radar_mk1_barrel) turns on it. '
                 'damaged: ring cracked, a cover flapping, sparks; disabled: scorched, dented, dish stopped.')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing_w(s, y, 32, 'standard')
        scope(s, 6, y + 4, 20, 20, self.sweep_state(st), self.SW, 'standard', pw)
        if st.state == 'damaged': self.hurt_scope(s, 6, y + 4, 20, 20, st)
        for k in range(3): s.rect(6 + k * 6, y + 26, 4, 2, ('g', 'a', 'g')[k] if pw and (k != 2 or st.state != 'damaged') else 'E')
        s.put(27, y + 7, 'L'); s.put(27, y + 11, 'L'); s.put(27, y + 15, 'L')
        s.rect(3, y + 5, 2, 8, 'q'); s.put(3, y + 5, 'Q'); s.put(2, y + 8, 'n')           # cable stub to the left
    def hurt_in(self, s, st):
        y = self.iy
        crack(s, [(24, y + 5), (22, y + 10), (25, y + 15)])
        spark(s, 26, y + 22, False) if st.i == 0 else spark(s, 5, y + 20, False)
        s.rect(18, y + 26, 4, 2, 'E')
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(10, y + 5), (14, y + 12), (12, y + 18), (16, y + 23)]); crack(s, [(22, y + 6), (20, y + 12)])
        wire(s, [(4, y + 22), (8, y + 25), (12, y + 27)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        if state in ('on', 'damaged'):
            glow(g, ox + 16, oy + y + 14, 11, (107, 211, 74), 0.26 if state == 'on' else 0.16, 2.0)
            for k in range(3):
                if state == 'on' or k < 2: glow(g, ox + 7.5 + k * 6, oy + y + 27, 3, (107, 211, 74) if k != 1 else (255, 190, 60), 0.45, 2.0)
    def base(self, s, st):
        pw = st.powered; i = st.i
        bev(s, 3, 18, 26, 13, 'M', 'S', 'W')                                                # plinth
        turret_ring(s, 16, 15, 21)
        circle(s, 16, 15, 5.2, 'D'); circle(s, 15.5, 14.5, 3.6, 'E')                        # the slip ring well the dish hub sits in
        bolts(s, [(5, 24), (25, 24)]); s.hline(7, 28, 3, 'W'); s.hline(11, 28, 2, 'W')
        s.put(26, 20, 'g' if pw and i == 0 else ('a' if pw else 'E'))
    def hurt_out(self, s, st):
        crack(s, [(9, 9), (11, 13), (9, 17)]); s.stamp(21, 20, FLAP)
        spark(s, 25, 9, False) if st.i == 0 else spark(s, 7, 22, False)
        s.put(26, 20, 'E')
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(9, 7), (12, 11), (10, 15), (13, 20)], [(23, 9), (21, 14)]], dents=[(4, 21, 6, 4), (21, 22, 6, 4)], soots=[(8, 2, 0), (20, 3, 2)],
                 wires_=[[(24, 14), (27, 17), (26, 22)]], sparks=[(16, 9), (10, 22)])
    def barrel(self, b, st):
        i = st.i
        bowl(b, 12, 12, 8, 6, 15)
        for (x0, y0, x1, y1) in ((15, 1, 22, 10), (15, 23, 22, 14)): line(b, x0, y0, x1, y1, 'W')
        feed(b, 12, 9, 22, 'g', True)
        b.put(24, 12, 'g' if i == 0 else 'H')
        circle(b, 6.5, 12.5, 4.4, 'S'); circle(b, 6.0, 12.0, 3.3, 'M'); b.put(6, 12, 'E'); b.put(5, 11, 'L')
    def bhurt(self, b, st):
        for (x, y) in ((17, 4), (18, 5), (19, 6)): b.erase(x, y)                              # one strut torn off, hanging
        b.stamp(17, 17, art("WW.\n.WW\n..W"))
        crack(b, [(12, 2), (11, 7), (13, 10)], 'K', 'M'); b.rect(22, 11, 4, 3, '.')
        b.put(22, 13, 'S'); b.put(23, 14, 'S'); b.put(24, 15, 'W')                            # the feed horn sags
        spark(b, 20, 9, False) if st.i == 0 else spark(b, 14, 20, False)
    def bbreak(self, b, st):
        return cleave(b, lambda y: 14, 0, 3) if False else b
    def bwreck(self, b, st):
        crack(b, [(12, 1), (11, 7), (13, 12), (11, 18), (13, 23)], 'K', 'S')
        b.rect(14, 8, 3, 9, '.'); b.rect(22, 11, 4, 3, '.')
        wire(b, [(12, 12), (15, 14), (19, 16), (21, 19)], 'S', 'W')
    def bglow(self, state, i, g, ox, oy):
        if state != 'disabled': glow(g, ox + 24.5, oy + 12.5, 3, (107, 211, 74), 0.5 if i == 0 else 0.3, 2.0)

class RadarMk2(RadarMk1):
    id = 'radar_mk2'; tier = 2; cells = (4, 2)
    blen, bwid = 30, 31
    bpivot = (7, 15); bmuzzle = (28, 15)
    notes = ('INSIDE half of the Radar Mk2 (standard, 4x2): a wide console: a big round scope with range rings, a bar-graph readout and a keypad. on: the sweep line turns one step per frame (8 frames); '
             'damaged / disabled as Mk1. Range 10,000 px and it identifies the type.')
    out_notes = ('OUTSIDE half of the Radar Mk2 (standard, 2x2 turntable): heavier base with a blue-lit slip ring; the big ribbed dish with a forked feed (radar_mk2_barrel) turns on it.')
    @property
    def out_cells(self): return (2, 2)
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing_w(s, y, 64, 'standard')
        coupling(s, 3, y + 8, st)
        scope(s, 17, y + 3, 26, 22, self.sweep_state(st), self.SW, 'standard', pw, blips=((0.6, 0.28), (0.3, 0.7), (0.78, 0.66), (0.45, 0.45)))
        if st.state == 'damaged': self.hurt_scope(s, 17, y + 3, 26, 22, st)
        bev(s, 47, y + 3, 14, 12, 'M', 'S', 'W')                                                  # bar-graph readout
        for k in range(4):
            hgt = 2 + ((k * 3 + (st.i if st.state == 'on' else 0)) % 6)
            if pw: s.rect(49 + k * 3, y + 13 - hgt, 2, hgt, 'g' if hgt < 6 else 'a')
        bev(s, 47, y + 17, 14, 8, 'M', 'S', 'W')                                                  # keypad
        for k in range(6): s.rect(49 + (k % 3) * 4, y + 19 + (k // 3) * 3, 3, 2, 'W'); s.put(49 + (k % 3) * 4, y + 19 + (k // 3) * 3, 'L')
        for k in range(5): s.rect(5 + k * 2, y + 26, 1, 2, ('g' if pw and (k + (st.i if st.state == 'on' else 0)) % 5 < 3 else 'E'))
        s.hline(4, y + 29, 2, 'W'); s.hline(7, y + 29, 3, 'W')
    def hurt_in(self, s, st):
        y = self.iy
        crack(s, [(40, y + 4), (37, y + 9), (40, y + 15)]); s.rect(52, y + 6, 3, 6, 'E'); dent(s, 48, y + 18, 6, 3)
        spark(s, 44, y + 22, False) if st.i == 0 else spark(s, 12, y + 24, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(24, y + 3), (28, y + 10), (25, y + 17), (29, y + 24)]); crack(s, [(50, y + 4), (53, y + 10)])
        wire(s, [(14, y + 22), (18, y + 26), (24, y + 27)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        if state in ('on', 'damaged'):
            glow(g, ox + 30, oy + y + 14, 15, (107, 211, 74), 0.26 if state == 'on' else 0.16, 2.0, sx=1.2)
            for k in range(5):
                if (k + i) % 5 < 3 and state == 'on': glow(g, ox + 5.5 + k * 2, oy + y + 27, 2, (107, 211, 74), 0.4, 2.0)
    def base(self, s, st):
        pw = st.powered; i = st.i
        bev(s, 2, 17, 28, 14, 'M', 'S', 'W')
        turret_ring(s, 16, 15, 23)
        circle(s, 16, 15, 5.8, 'D'); circle(s, 15.5, 14.5, 4.2, 'E')
        for (x, y) in ((6, 9), (25, 9), (6, 21), (25, 21)): s.put(x, y, 'b' if pw else 'E')       # blue-lit slip ring studs
        bolts(s, [(4, 24), (26, 24)]); s.hline(8, 28, 3, 'W'); s.hline(12, 28, 3, 'W')
        s.put(28, 19, 'g' if pw and i == 0 else ('a' if pw else 'E')); s.put(3, 19, 'g' if pw and i == 1 else ('a' if pw else 'E'))
    def barrel(self, b, st):
        i = st.i
        bowl(b, 15, 15, 9, 8, 18, ribs=5)
        for (x0, y0, x1, y1) in ((18, 1, 25, 10), (18, 29, 25, 20)): line(b, x0, y0, x1, y1, 'W')
        feed(b, 12, 11, 25, 'g', True); feed(b, 18, 11, 25, 'c', True)
        b.hline(25, 13, 1, 'W'); b.vline(25, 13, 4, 'S')
        b.put(27, 12, 'g' if i == 0 else 'H'); b.put(27, 18, 'c' if i == 1 else 'H')
        circle(b, 7.5, 15.5, 5.2, 'S'); circle(b, 7.0, 15.0, 4.0, 'M'); b.put(7, 15, 'E'); b.put(6, 14, 'L')
    def bhurt(self, b, st):
        for (x, y) in ((20, 4), (21, 5), (22, 6)): b.erase(x, y)
        b.stamp(20, 22, art("WW.\n.WW\n..W"))
        crack(b, [(14, 3), (12, 9), (15, 13)], 'K', 'M'); crack(b, [(16, 20), (13, 25)], 'K', 'M')
        b.rect(25, 11, 4, 3, '.'); b.put(25, 15, 'S'); b.put(26, 16, 'S')
        spark(b, 22, 9, False) if st.i == 0 else spark(b, 17, 24, False)
    def bwreck(self, b, st):
        crack(b, [(14, 1), (12, 8), (15, 15), (12, 22), (14, 29)], 'K', 'S')
        b.rect(17, 10, 3, 11, '.'); b.rect(25, 11, 4, 8, '.')
        wire(b, [(14, 15), (18, 17), (22, 20), (24, 24)], 'S', 'W')
    def bglow(self, state, i, g, ox, oy):
        if state != 'disabled':
            glow(g, ox + 27.5, oy + 12.5, 3, (107, 211, 74), 0.5 if i == 0 else 0.3, 2.0)
            glow(g, ox + 27.5, oy + 18.5, 3, (60, 242, 255), 0.5 if i == 1 else 0.3, 2.0)

# ------------------------------------------------------------------ Radar Mk3: a phased array that sees hidden contacts
class RadarMk3(RadarMk2):
    id = 'radar_mk3'; tier = 3
    blen, bwid = 28, 35
    bpivot = (7, 17); bmuzzle = (26, 17)
    notes = ('INSIDE half of the Radar Mk3 (standard, 4x2): the Mk2 console plus a spectrum strip and a red "hidden contact" lamp that blinks when the array sees something running dark. on: 8-frame sweep; damaged / disabled as Mk1. Range 16,000 px, sees hidden contacts.')
    out_notes = ('OUTSIDE half of the Radar Mk3 (standard, 2x2 turntable): an armoured base with two lamps; the phased-array face on a boom (radar_mk3_barrel) turns on it.')
    def inside(self, s, st):
        RadarMk2.inside(self, s, st)
        y = self.iy; pw = st.powered
        s.rect(5, y + 17, 9, 6, 'D'); s.hline(5, y + 17, 9, 'K')
        for k in range(5):
            hgt = 1 + ((k * 2 + (st.i if st.state == 'on' else 0) * 2) % 5)
            if pw: s.rect(6 + k * 2, y + 22 - hgt, 1, hgt, 'c')
        s.rect(5, y + 14, 2, 2, ('r' if pw and st.state == 'on' and st.i % 4 < 2 else 'E')) if pw else s.rect(5, y + 14, 2, 2, 'E')
    def glow(self, state, i, g, ox, oy):
        RadarMk2.glow(self, state, i, g, ox, oy)
        if state == 'on' and i % 4 < 2: glow(g, ox + 6, oy + self.iy + 15, 3, (224, 65, 59), 0.5, 2.0)
    def base(self, s, st):
        RadarMk2.base(self, s, st)
        s.rect(13, 27, 6, 2, 'D'); s.hline(13, 27, 6, 'K'); s.put(14, 28, 'g' if st.powered else 'E'); s.put(17, 28, 'a' if st.powered else 'E')
        s.hline(3, 18, 4, 'L'); s.hline(25, 18, 4, 'L')
    def barrel(self, b, st):
        i = st.i
        # the phased-array face: a long plate across the pointing direction, hex cells and a lit emitter row
        bev(b, 15, 1, 6, 33, 'M', 'S', 'W', cham=True)
        for y in range(3, 32, 3):
            for x in (16, 18):
                b.rect(x + (1 if (y // 3) % 2 else 0), y, 2, 2, 'E')
        b.vline(20, 2, 31, 'c' if True else 'S')
        for y in range(3, 32, 4): b.put(20, y, 'H' if (y // 4 + i) % 2 == 0 else 'c')
        b.hline(15, 1, 6, 'L'); b.hline(15, 33, 6, 'W')
        # boom from the hub to the array, braced, with two small side dishes
        b.rect(9, 16, 7, 3, 'S'); b.hline(9, 16, 7, 'M'); b.hline(9, 18, 7, 'W')
        line(b, 11, 17, 16, 5, 'W'); line(b, 11, 17, 16, 29, 'W')
        circle(b, 24.5, 6.5, 2.2, 'S'); circle(b, 24, 6, 1.4, 'M'); circle(b, 24.5, 28.5, 2.2, 'S'); circle(b, 24, 28, 1.4, 'M')
        b.hline(21, 6, 3, 'W'); b.hline(21, 28, 3, 'W')
        circle(b, 7.5, 17.5, 5.2, 'S'); circle(b, 7.0, 17.0, 4.0, 'M'); b.put(7, 17, 'E'); b.put(6, 16, 'L')
    def bhurt(self, b, st):
        crack(b, [(16, 5), (18, 10), (16, 15)], 'K', 'M'); b.rect(17, 19, 3, 5, 'E'); b.vline(20, 19, 5, 'W')
        for (x, y) in ((24, 5), (25, 6)): b.erase(x, y)
        wire(b, [(23, 7), (24, 9), (23, 12)], 'S', 'W')
        spark(b, 22, 11, False) if st.i == 0 else spark(b, 19, 26, False)
    def bwreck(self, b, st):
        crack(b, [(16, 2), (18, 9), (16, 17), (19, 25), (17, 32)], 'K', 'S')
        b.rect(21, 12, 5, 11, '.'); b.rect(22, 3, 4, 7, '.')
        wire(b, [(16, 17), (20, 19), (23, 22)], 'S', 'W')
    def bglow(self, state, i, g, ox, oy):
        if state != 'disabled':
            for y in range(3, 32, 4):
                if (y // 4 + i) % 2 == 0: glow(g, ox + 20.5, oy + y + 0.5, 3, (60, 242, 255), 0.28, 2.0)

# ------------------------------------------------------------------ Listening Horn (scrap)
class ListeningHorn(Radar):
    id = 'listening_horn_scrap'; line = 'scrap'
    blen, bwid = 26, 25
    bpivot = (6, 12); bmuzzle = (24, 12)
    notes = ('INSIDE half of the Listening Horn (scrap, 2x2): a crude amber scope in a rusty frame with a speaker grille and a patch plate. on: the sweep line crawls round (8 frames); '
             'damaged: glitch band, a lamp dead, a loose wire; disabled: a dead, cracked screen. Range 5,000 px, no power.')
    out_notes = ('OUTSIDE half of the Listening Horn (scrap, 2x2): a welded drum stand with hazard tape and guy bolts; the riveted horn (listening_horn_scrap_barrel) turns on top.')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing_w(s, y, 32, 'scrap')
        s.hline(3, y + 2, 26, 'S'); bolts(s, [(4, y + 3), (26, y + 3)])
        scope(s, 5, y + 4, 17, 17, self.sweep_state(st), self.SW, 'scrap', True)
        if st.state == 'damaged': self.hurt_scope(s, 5, y + 4, 17, 17, st)
        bev(s, 24, y + 4, 5, 13, 'S', 'W', 'E', cham=False)
        for k in range(4): s.hline(25, y + 6 + k * 3, 3, 'D')                                        # the speaker grille
        plate(s, 23, y + 19, 6, 8, 'r', bolt=False); weld(s, 22, y + 18, 5)
        lamp(s, 5, y + 24, 'a', pw and st.state != 'damaged'); lamp(s, 10, y + 24, 'o', pw and st.state == 'on' and st.i % 4 < 2)
        hazard(s, 14, y + 26, 8, 2)
        s.hline(4, y + 29, 2, 'W')
    def hurt_in(self, s, st):
        y = self.iy
        crack(s, [(20, y + 5), (18, y + 10), (20, y + 14)]); dent(s, 24, y + 18, 5, 4)
        wire(s, [(7, y + 22), (8, y + 26), (6, y + 29)])
        spark(s, 23, y + 24, False) if st.i == 0 else spark(s, 12, y + 22, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(10, y + 4), (13, y + 11), (11, y + 17)]); crack(s, [(25, y + 5), (26, y + 12)])
        wire(s, [(4, y + 22), (8, y + 26), (13, y + 28)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        if state in ('on', 'damaged'):
            glow(g, ox + 13.5, oy + y + 12.5, 9, (255, 190, 60), 0.22 if state == 'on' else 0.14, 2.0)
            if state == 'on': glow(g, ox + 5.5, oy + y + 24.5, 3, (255, 190, 60), 0.45, 2.0)
            if state == 'on' and i % 4 < 2: glow(g, ox + 10.5, oy + y + 24.5, 3, (255, 138, 30), 0.45, 2.0)
    def base(self, s, st):
        i = st.i
        bev(s, 4, 17, 24, 14, 'S', 'W', 'E')                                                          # a welded drum stand
        for yy in (20, 25): s.hline(5, yy, 22, 'D')
        hazard(s, 4, 26, 24, 4)
        plate(s, 5, 18, 8, 6, 'r', bolt=False); weld(s, 15, 19, 9, False)
        scrap_ring(s, 16, 14, 20)
        circle(s, 16, 14, 4.8, 'D'); circle(s, 15.5, 13.5, 3.3, 'E')
        for (x, y) in ((3, 10), (28, 10)): s.vline(x, y, 8, 'q'); s.put(x, y, 'Q')                  # guy rods
        s.put(26, 21, 'a' if i == 0 else 'o')
        junk(s, 21, 21, 2)
    def hurt_out(self, s, st):
        crack(s, [(10, 8), (12, 12), (10, 16)]); s.stamp(20, 19, FLAP)
        for k in range(4): s.put(8 + k, 27 + (k % 2), 'a' if k % 2 else 'D')
        spark(s, 26, 9, False) if st.i == 0 else spark(s, 6, 20, False)
        s.put(26, 21, 'E')
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(10, 7), (12, 11), (10, 16), (13, 21)], [(23, 9), (21, 15)]], dents=[(5, 22, 7, 4), (21, 22, 6, 4)], soots=[(8, 3, 0), (19, 2, 2)],
                 wires_=[[(3, 11), (5, 15), (4, 20)]], sparks=[(16, 9), (24, 18)])
    def barrel(self, b, st):
        i = st.i
        # a riveted horn: segments flaring from the hub (x=6) to the mouth (x=22), rust, steel and a strip of tape
        segs = [(8, 11, 5, 'S'), (11, 13, 8, 'W'), (14, 15, 12, 'u'), (17, 17, 16, 'S'), (20, 19, 20, 'W'), (22, 20, 24, 'M')]
        for (x0, x1, hw, col) in ((8, 10, 4, 'S'), (11, 13, 6, 'W'), (14, 16, 8, 'u'), (17, 19, 10, 'S'), (20, 22, 11, 'W')):
            for x in range(x0, x1 + 1):
                hw_ = hw + (x - x0) * 0.5
                for y in range(int(12 - hw_), int(12 + hw_) + 1):
                    d = abs(y - 12) / max(hw_, 1)
                    tone = {'S': ('M', 'S', 'W'), 'W': ('S', 'W', 'E'), 'u': ('Q', 'u', 'n')}[col][0 if y < 12 - hw_ * 0.4 else 2 if y > 12 + hw_ * 0.4 else 1]
                    b.put(x, y, tone)
            b.vline(x1, int(12 - hw - (x1 - x0) * 0.5), int(2 * hw + (x1 - x0)) + 1, 'L' if col != 'u' else 'Q')
        for y in range(3, 22): b.put(16 if abs(y - 12) < 8 else 17, y, 'a' if (y // 2) % 2 == 0 else 'D') if abs(y - 12) < 8 else None
        b.vline(23, 0, 25, 'S'); b.vline(24, 0, 25, 'W'); b.put(23, 0, 'L')                                # the lip of the mouth
        b.rect(21, 3, 2, 19, 'D'); b.put(22, 12, 'E')
        weld(b, 11, 9, 3, True); weld(b, 19, 5, 3, True)
        wire(b, [(12, 4), (16, 1), (22, 0)], 'u', 'n')                                                    # a lashing wire
        b.put(24, 5, 'a' if i == 0 else 'o')
        circle(b, 6.5, 12.5, 4.4, 'W'); circle(b, 6.0, 12.0, 3.3, 'S'); b.put(6, 12, 'E'); b.put(5, 11, 'L')
    def bhurt(self, b, st):
        for y in range(2, 8): b.erase(23, y); b.erase(24, y)                                              # the mouth lip is bent in
        b.stamp(21, 4, art("SS\nWS\n.W"))
        crack(b, [(14, 8), (15, 13), (14, 18)]); crack(b, [(18, 6), (19, 10)])
        b.stamp(19, 20, art(".uu\nuQu\nnn."))
        spark(b, 22, 22, False) if st.i == 0 else spark(b, 13, 5, False)
    def bwreck(self, b, st):
        crack(b, [(13, 4), (14, 10), (13, 16), (15, 22)], 'K', 'S'); crack(b, [(19, 6), (20, 12), (19, 18)], 'K', 'S')
        b.rect(21, 14, 4, 8, '.'); b.rect(22, 3, 3, 5, '.')
        wire(b, [(12, 12), (16, 14), (20, 17)], 'u', 'n')
    def bglow(self, state, i, g, ox, oy):
        if state != 'disabled': glow(g, ox + 24.5, oy + 5.5, 3, (255, 190, 60), 0.5 if i == 0 else 0.3, 2.0)

# ------------------------------------------------------------------ Lumen Eye (neon)
class LumenEye(RadarMk2):
    id = 'lumen_eye_neon'; line = 'neon'
    blen, bwid = 28, 31
    bpivot = (7, 15); bmuzzle = (26, 15)
    notes = ('INSIDE half of the Lumen Eye (neon, 4x2): a navy console with a cyan scope, a magenta iris readout and crystal lamps. on: the cyan sweep turns round (8 frames); '
             'damaged: glitch band, the iris flickering; disabled: a dead column. Range 14,000 px, identifies the type; ion-weak.')
    out_notes = ('OUTSIDE half of the Lumen Eye (neon, 2x2): a navy pedestal with a cyan slip ring and a crystal gem; the eye (lumen_eye_neon_barrel) turns on it.')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        housing_w(s, y, 64, 'neon')
        coupling(s, 3, y + 8, st, 'c')
        scope(s, 17, y + 3, 26, 22, self.sweep_state(st), self.SW, 'neon', pw, blips=((0.6, 0.28), (0.3, 0.7), (0.78, 0.66)))
        if st.state == 'damaged': self.hurt_scope(s, 17, y + 3, 26, 22, st)
        navy_panel(s, 47, y + 3, 14, 12)                                                          # the iris readout
        if pw:
            circle(s, 54, y + 9, 3.5, 'C'); circle(s, 54, y + 9, 2.4, 'c'); s.put(54, y + 9, 'm' if st.state != 'damaged' or st.i == 0 else 'P'); s.put(55, y + 8, 'H')
        navy_panel(s, 47, y + 17, 14, 8)
        for k in range(4): s.rect(49 + k * 3, y + 19, 2, 4, 'c' if pw and (k + (st.i if st.state == 'on' else 0)) % 4 < 2 else 'N')
        for k in range(5): s.rect(5 + k * 2, y + 26, 1, 2, 'c' if pw and (k + (st.i if st.state == 'on' else 0)) % 5 < 3 else 'N')
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        if state in ('on', 'damaged'):
            glow(g, ox + 30, oy + y + 14, 15, (60, 242, 255), 0.28 if state == 'on' else 0.16, 2.0, sx=1.2)
            glow(g, ox + 54, oy + y + 9, 5, (255, 79, 216), 0.4 if state == 'on' else 0.25, 2.0)
    def base(self, s, st):
        pw = st.powered; i = st.i
        bev(s, 3, 17, 26, 14, 'W', 'E', 'D')
        s.hline(4, 18, 24, 'c' if pw else 'W'); s.hline(4, 29, 24, 'c' if pw else 'W')
        turret_ring(s, 16, 15, 23, 'W', 'E', 'D', 'N')
        circle(s, 16, 15, 5.8, 'N'); circle(s, 15.5, 14.5, 4.2, 'I')
        for k in range(8):
            a = 2 * math.pi * k / 8.0
            s.put(int(16 + 9.5 * math.cos(a)), int(15 + 9.5 * math.sin(a)), 'c' if pw else 'W')
        crystal(s, 3, 22, """
.0.
010
012
.2.
""", ('c', 'C', 'B') if pw else ('M', 'S', 'W'))
        crystal(s, 26, 22, """
.0.
010
012
.2.
""", ('m', 'P', 'N') if pw else ('M', 'S', 'W'))
    def hurt_out(self, s, st):
        crack(s, [(9, 9), (11, 13), (9, 18)], 'K', 'c'); s.erase(3, 22); s.erase(3, 23)
        spark(s, 25, 9, False) if st.i == 0 else spark(s, 7, 22, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(9, 7), (12, 11), (10, 15), (13, 20)], [(23, 9), (21, 14)]], dents=[(4, 21, 6, 4), (21, 22, 6, 4)], soots=[(8, 2, 0), (20, 3, 2)],
                 wires_=[[(24, 14), (27, 17), (26, 22)]], sparks=[(16, 9), (10, 22)])
    def barrel(self, b, st):
        i = st.i
        # an eye: a navy almond across the pointing direction, a cyan iris glancing forward with a magenta pupil, crystal fins swept back
        for y in range(0, 31):
            dy = (y - 15) / 15.0
            hw = int(round(6 * math.sqrt(max(0.0, 1 - dy * dy))))
            xc = 14 - int(round(abs(dy) * 0))
            for x in range(xc - hw, xc + hw + 1):
                b.put(x, y, 'J' if x > xc - hw + 1 else 'j')
            if hw: b.put(xc - hw, y, 'c'); b.put(xc + hw, y, 'c')
        b.put(14, 0, 'c'); b.put(14, 30, 'c')
        circle(b, 17.5, 15.5, 6.3, 'C'); circle(b, 17.5, 15.5, 5.4, 'c'); circle(b, 18, 16, 4.0, 'C')            # iris
        for (x, y, c_) in ((15, 12, 'H'), (16, 11, 'c'), (19, 12, 'c')): b.put(x, y, c_)
        circle(b, 18.5, 15.5, 2.2, 'm'); b.put(18, 15, 'H'); b.put(19, 16, 'P')                                    # pupil
        crystal(b, 5, 3, """
.00..
0011.
.012.
..22.
""", ('c', 'C', 'B')); crystal(b, 5, 24, """
..22.
.012.
0011.
.00..
""", ('c', 'C', 'B'))
        b.hline(9, 14, 3, 'j'); b.hline(9, 16, 3, 'J')
        circle(b, 7.5, 15.5, 5.2, 'J'); circle(b, 7.0, 15.0, 4.0, 'j'); b.put(7, 15, 'N'); b.put(6, 14, 'c')
        b.put(25, 15, 'c' if i == 0 else 'H')
    def bhurt(self, b, st):
        crack(b, [(14, 3), (13, 9), (15, 13)], 'K', 'c'); b.rect(5, 3, 5, 4, '.'); b.put(6, 6, 'B'); b.put(7, 7, 'C')
        b.put(18, 15, 'P' if st.i == 0 else 'N'); b.put(19, 16, 'N') if st.i else None
        spark(b, 20, 8, False) if st.i == 0 else spark(b, 12, 23, False)
    def bwreck(self, b, st):
        crack(b, [(14, 1), (13, 8), (16, 15), (13, 22), (14, 29)], 'K', 'M'); b.rect(5, 24, 5, 4, '.'); b.rect(19, 11, 5, 9, '.')
        wire(b, [(14, 15), (18, 18), (21, 22)], 'm', 'P')
    def bglow(self, state, i, g, ox, oy):
        if state != 'disabled':
            glow(g, ox + 18, oy + 15.5, 9, (60, 242, 255), 0.30 if state == 'idle' else 0.18, 2.0)
            glow(g, ox + 18.5, oy + 15.5, 4, (255, 79, 216), 0.5 if i == 0 else 0.35, 2.0)

ALL = [RadarMk1, RadarMk2, RadarMk3, ListeningHorn, LumenEye]
