"""Concord Thruster Mk3, Mk4, Mk5 (engines_1.md). Mk1 and Mk2 are lines_engine.py and stay as they are; every tier here is built ON TOP of the one below
(same steel ramp, same bells, amber accents), so the ladder reads as one family:
 Mk2 amber collar rings, two turbines.  Mk3 + a third (vernier) nozzle, two coolant drums, a coolant pump and a cable harness in the core.
 Mk4 (outside 4x3) heavy bells with heat-sink fins on a reinforced collar, a bigger vernier; core with fin sinks and armour corners.
 Mk5 three full bells (the middle one tallest) and the Concord gold registry band."""
from lines_eng_base import *
from lines_engine import bell_up, collar_ring, TURB8, RING10, lit_turbine, _Mk2, _Std

_M2 = _Mk2()

def fins(s, x0, w0, y0, y1, step=3):
    """heat-sink fins round a neck: thin wide plates every `step` rows, lit on top, dark underneath."""
    for y in range(y0, y1, step):
        s.hline(x0 + 1, y, w0 - 2, 'M'); s.hline(x0 + 1, y + 1, w0 - 2, 'W')
        s.put(x0 + 1, y, 'L'); s.put(x0 + 2, y, 'L'); s.put(x0 + w0 - 2, y + 1, 'E'); s.put(x0 + 1, y + 1, 'S')

def ring_a(s, x, y, w, gold=False):
    """the amber collar ring: the Mk2 accent (gold = brighter, the Mk5 registry colour)."""
    s.hline(x, y, w, 'a'); s.hline(x, y + 1, w, 'u')
    s.put(x, y, 'y'); s.put(x + 1, y, 'y'); s.put(x + w - 1, y, 'u'); s.put(x + w - 2, y, 'u')
    if gold: s.put(x + 4, y, 'y'); s.put(x + w - 5, y, 'y')

def registry_band(s, x, y, w):
    """the Concord gold registry band: a 4px gold strip with a dark stencil."""
    s.rect(x, y, w, 4, 'a'); s.hline(x, y, w, 'y'); s.hline(x, y + 3, w, 'u')
    for q, k in enumerate(range(4, w - 6, 7)):
        stencil(s, x + k, y + 1, 'n', q); stencil(s, x + k + 1, y + 2, 'n', q + 2)
    s.put(x, y, 'L'); s.put(x + w - 1, y + 3, 'n')

def pump_unit(c, on, i):
    """the coolant pump that replaces the feed pipes in the core: a pressure gauge and a banded drum (x 44..61, y 4..17)."""
    c.rect(44, 4, 18, 15, 'S'); bev(c, 44, 4, 17, 14, 'W', 'E', 'D')
    circle(c, 50, 10, 3.6, 'M'); circle(c, 50, 10, 2.9, 'D'); ring(c, 50, 10, 2.9, 3.6, 'L')
    for (x, y) in ((48, 7), (52, 7), (47, 11), (53, 11)): c.put(x, y, 'W')
    nx, ny = [(52, 8), (51, 8), (52, 9)][i % 3] if on else (48, 11)
    line(c, 50, 10, nx, ny, 'r' if on else 'W'); c.put(50, 10, 'H' if on else 'L')
    T = col_tones(5, 'LMSWE')
    for y in range(6, 16):
        for q in range(5): c.put(55 + q, y, T[q])
    c.hline(55, 5, 5, 'M'); c.hline(55, 16, 5, 'W')
    for yy in (8, 13): c.hline(55, yy, 5, 'a' if on else 'W'); c.hline(55, yy + 1, 5, 'u' if on else 'E')
    c.put(57, 11, 'g' if on and i != 1 else 'W')

def harness(c, on):
    """a cable harness along the middle of the core: a brown cable with clamps and two live wires."""
    c.hline(2, 18, 60, 'q'); c.hline(2, 19, 60, 'n')
    for x in range(6, 60, 9): c.put(x, 18, 'Q'); c.put(x + 1, 18, 'Q'); c.put(x, 19, 'M')
    for x in (20, 44): c.put(x, 18, 'r' if on else 'q')

# ================================================================ Mk3
class Mk3(EngBase):
    id = 'engine_mk3'; KIND = 'std'
    anchors_out = {'exhaust_left': (13, 1), 'exhaust_right': (50, 1), 'exhaust_mid': (32, 9)}
    anchors_in = {'power_coupling': (32, 29), 'repair_hatch': (13, 29)}
    notes = ('Concord Thruster Mk3, a hull mount (outward is up): the Mk2 twin amber-ringed bells plus a third, smaller vernier nozzle between them, a coolant drum with a pipe on each flank, '
             'and inside the Mk2 core plus a coolant pump (gauge and drum) in place of the feed pipes and a cable harness across the middle. '
             'Damaged: the left bell lip dented and hanging, the right bell cracked and sputtering, the vernier bent over and weeping coolant, a drum cracked; the pump gauge reads red, sparks at the hatch and coupling. '
             'Disabled: the left nozzle snapped off at the neck, the right bent over, the vernier broken off, a drum split; the core dead with its repair hatch popped.')
    def out(self, o, on, i):
        from_full(o, _M2.interior('on' if on else 'off', i), 0)
        # a third nozzle between the bells: it sits in front of the manifold
        bell_gen(o, 28, 9, [(8, 11, 0), (12, 15, 1), (16, 19, 2)], 28, on, i, bands=(22, 25))
        ring_a(o, 29, 12, 7)
        o.rect(26, 24, 12, 3, 'S'); o.hline(26, 24, 12, 'M'); o.hline(26, 26, 12, 'W')
        # coolant drums on the flanks, piped into the bell necks
        for (x0, flip) in ((2, False), (55, True)):
            T = col_tones(7, 'LMSSWEE')
            for y in range(13, 26):
                for q in range(7): o.put(x0 + q, y, T[q])
            o.hline(x0 + 1, 12, 5, 'M'); o.hline(x0 + 1, 26, 5, 'W')
            ring_a(o, x0, 16, 7); o.put(x0 + 3, 21, 'E'); o.put(x0 + 3, 22, 'L')
            px = x0 + 7 if not flip else x0 - 4
            o.rect(px, 21, 4, 2, 'q'); o.hline(px, 21, 4, 'Q'); o.hline(px, 22, 4, 'n')
    def hurt_out(self, o, i):
        via_full(_M2, o, 0, 'hurt', i)
        shift_rect(o, 27, 38, 7, 22, 1, 0); o.stamp(27, 6, art("KKK.\nKLSK\n.KWK")); crack(o, [(31, 13), (33, 16), (32, 20)], 'M')       # the vernier is knocked askew
        crack(o, [(5, 15), (7, 19), (5, 23)], 'M'); o.put(3 + i, 11 - i, 'H'); o.put(5 - i, 9, 'L'); o.put(4, 7 - 2 * i, 'L')                     # left drum cracked, steam
    def wreck_out(self, o):
        via_full(_M2, o, 0, 'wreck')
        shift_rect(o, 27, 38, 7, 24, 2, 2); o.hline(28, 24, 9, 'K'); crack(o, [(31, 22), (33, 25), (31, 27)], 'M')                              # the vernier snapped and hanging
        o.stamp(4, 12, art("KKKKKK.\nKDDDDDK\n.KSKDK.")); crack(o, [(58, 14), (60, 19), (58, 24)], 'M'); stamp_on(o, 56, 18, SCORCH_S)         # one drum split, one cracked
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.9)
        inten, hub = [(0.8, 0.35), (1.0, 0.55), (0.9, 0.45)][i % 3]
        for n, x0 in enumerate((11, 39)):
            k2 = 0.8 if (flick is not None and n == 0) else (0.55 if flick == 1 and n == 1 else 1.0)
            glow_xy(g, ox + x0 + 7.5, oy + 1.5, 11, 28, ORANGE, 0.6 * inten * k * k2, 2.0)
            glow_xy(g, ox + x0 + 7.5, oy + 1.5, 6, 13, (255, 214, 90), 0.55 * inten * k * k2, 1.7)
        k3 = 0.5 if flick == 1 else 1.0
        glow_xy(g, ox + 32.5, oy + 8.5, 6, 18, ORANGE, 0.55 * inten * k * k3, 2.0)
        glow_xy(g, ox + 32.5, oy + 8.5, 3, 8, (255, 214, 90), 0.5 * inten * k * k3, 1.7)
    def core(self, c, on, i):
        t = Spr(64, 32); _M2.core(t, on, i); from_full(c, t, 0)
        pump_unit(c, on, i); harness(c, on)
    def hurt_core(self, c, i):
        via_full(_M2, c, 48, 'hurt', i)
        c.put(50, 10, 'D'); line(c, 50, 10, 48, 13, 'r'); crack(c, [(46, 7), (48, 9), (47, 12), (49, 14)], 'M')
        c.put(57, 11, 'r'); c.put(56, 6 + i, 'y'); c.put(46, 15, 'H' if i else 'y')
    def wreck_core(self, c):
        via_full(_M2, c, 48, 'wreck')
        c.stamp(47, 7, art("KKKKKKK\nKDDDDDK\nKDDKDDK\n.KKKKK.")); c.stamp(56, 8, art("KK.\nKDK\n.KK"))
        stamp_on(c, 52, 8, SCORCH_L); crack(c, [(46, 17), (49, 18), (50, 19)], 'M')
    def glow_core(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.9)
        _, hub = [(0.8, 0.35), (1.0, 0.55), (0.9, 0.45)][i % 3]
        b = oy + 4
        for tx in (23, 33):
            if flick == 1 and tx == 33: continue
            glow(g, ox + tx + 4, b + 12, 7, ORANGE, hub * 1.1 * k, 2.0)
        for (lx, ly, rgb) in ((6, 8.5, GREEN), (9, 8.5, GREEN), (12, 8.5, AMBER)):
            if flick is not None and lx > 7: rgb = RED
            glow(g, ox + lx + 1, b + ly + 1, 4.5, rgb, 0.55 * k, 2.0)
        glow(g, ox + 32, b + 25, 6, GREEN, 0.4 * k, 2.0)
        glow(g, ox + 57.5, b + 11.5, 3.5, GREEN if flick is None else RED, 0.45 * k, 2.0)
        glow(g, ox + 50, b + 10, 5, AMBER if flick is None else RED, 0.25 * k, 2.0)
        for vy in (22, 24, 26, 28):
            if (vy // 2 + i) % 3 == 0 and flick is None: glow(g, ox + 51, b + vy + 1, 7, ORANGE, 0.3, 2.0, sx=1.8)


# ================================================================ Mk4 and Mk5: the 4x3 nozzle housing
class Heavy(EngBase):
    """heavy twin bells (17 wide) with heat-sink fins on a reinforced collar plate, and a middle nozzle that grows: a vernier (Mk4), a full bell (Mk5)."""
    KIND = 'std'; OUT_H = 48; TIER = 4
    pad_out = (10, 38, 10, 4)
    SIDES = (4, 44)
    def dy(self): return 0 if self.TIER == 4 else 4
    def secs(self, dy): return [(1 + dy, 5 + dy, 0), (6 + dy, 11 + dy, 1), (12 + dy, 17 + dy, 2), (18 + dy, 23 + dy, 3)]
    def centre(self):
        return (25, 15, self.secs(0)) if self.TIER == 5 else (27, 11, [(10, 13, 0), (14, 18, 1), (19, 23, 2)])
    def out(self, o, on, i):
        dy = self.dy(); gold = self.TIER == 5
        # behind: the bells, the middle nozzle and its feed manifold
        o.rect(23, 28 + dy, 18, 4, 'q'); o.hline(23, 28 + dy, 18, 'Q'); o.hline(23, 31 + dy, 18, 'n')
        for x0 in self.SIDES:
            bell_gen(o, x0, 17, self.secs(dy), 34, on, i, bands=())
            ring_a(o, x0 + 1, 9 + dy, 15, gold); ring_a(o, x0 + 2, 15 + dy, 13, gold)
            fins(o, x0, 17, 25 + dy, 34)
        cx0, cw, csecs = self.centre()
        bell_gen(o, cx0, cw, csecs, 34, on, i, bands=())
        ring_a(o, cx0 + 1, csecs[1][0] + 3 if self.TIER == 5 else 14, cw - 2, gold)
        if self.TIER == 5: ring_a(o, cx0 + 2, 15, cw - 4, True)
        fins(o, cx0, cw, 26 if self.TIER == 4 else 25, 34)
        # the reinforced collar plate and the nacelle plate under it
        bev(o, 5, 33, 54, 6, 'L', 'M', 'S'); bev(o, 2, 39, 60, 5, 'M', 'S', 'W')
        for x in (8, 20, 31, 32, 43, 55): o.put(x, 35, 'L'); o.put(x, 36, 'E') if x in (31, 32) else None
        for x in (7, 56): o.put(x, 41, 'L')
        if gold: registry_band(o, 7, 34, 50)
        else: o.hline(7, 36, 50, 'a'); o.hline(7, 37, 50, 'u')
    def hurt_out(self, o, i):
        dy = self.dy(); x0, x1 = self.SIDES
        for (x, y) in ((x0, 1 + dy), (x0, 2 + dy), (x0 + 1, 2 + dy), (x0, 3 + dy), (x0 + 1, 3 + dy), (x0 + 1, 1 + dy)): o.erase(x, y)             # left bell lip dented in
        for (x, y) in ((x0 + 1, 4 + dy), (x0 + 2, 3 + dy), (x0 + 2, 4 + dy)): o.put(x, y, 'W')
        o.stamp(x0 - 4, 3 + dy, art("KKKK.\nKLMSK\n.KSWK\n..KKK")); o.put(x0 - 1, 7 + dy, 'S')
        crack(o, [(x1 + 8, 6 + dy), (x1 + 10, 11 + dy), (x1 + 8, 16 + dy), (x1 + 11, 22 + dy)], 'M')                                      # right bell cracked
        if i == 1: o.hline(x1 + 2, 1 + dy, 13, 'D'); o.hline(x1 + 6, 2 + dy, 5, 'o')                                                        # it sputters
        for y in (26 + dy, 29 + dy): o.erase(x1 + 15, y); o.erase(x1 + 14, y + 1)                                                          # a fin torn off
        stamp_on(o, 14, 35, SCORCH_S); stamp_on(o, 42, 38, SCORCH_S)
        cx0, cw, cs = self.centre()
        crack(o, [(cx0 + cw // 2 + 1, cs[0][1] + 2), (cx0 + cw // 2 - 1, cs[1][1] + 2), (cx0 + cw // 2 + 1, cs[2][1] + 3)], 'M')
        o.put(cx0 + 1, 3 + dy + 7 * (self.TIER == 4), 'y' if i else 'H'); o.put(x1 + 14 - i, 5, 'L')
    def wreck_out(self, o):
        dy = self.dy(); x0, x1 = self.SIDES
        shift_rect(o, x0 - 1, x0 + 18, 0, 20 + dy, -3, 1)                                      # left nozzle bent over at the neck
        shift_rect(o, x1 - 1, x1 + 18, 0, 20 + dy, 3, 1)                                       # right nozzle bent the other way
        for xx in (x0 - 3, x1 + 3):
            o.hline(xx + 2, 20 + dy, 13, 'K'); crack(o, [(xx + 7, 22 + dy), (xx + 9, 25 + dy), (xx + 7, 29 + dy)], 'M'); crack(o, [(xx + 5, 5), (xx + 9, 9), (xx + 6, 13)], 'M')
        o.stamp(x0 - 4, 14 + dy, art("KKK.\nKLSK\n.KWK"))
        cx0, cw, cs = self.centre()
        yb = cs[-1][1] + 1
        shift_rect(o, cx0 - 1, cx0 + cw + 1, 0, yb, 2, 2); o.hline(cx0 + 1, yb + 1, cw - 2, 'K'); crack(o, [(cx0 + 4, yb + 3), (cx0 + 6, yb + 6), (cx0 + 4, yb + 9)], 'M')
        for y in (26 + dy, 29 + dy): o.erase(x1 + 15, y); o.erase(x1 + 14, y + 1); o.erase(x0 + 1, y); o.erase(x0 + 2, y + 1)
        crack(o, [(10, 36), (13, 39), (11, 42)], 'M'); stamp_on(o, 40, 36, SCORCH_L)
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.9)
        inten, hub = [(0.8, 0.35), (1.0, 0.55), (0.9, 0.45)][i % 3]
        dy = self.dy()
        for n, x0 in enumerate(self.SIDES):
            k2 = 0.8 if (flick is not None and n == 0) else (0.55 if flick == 1 and n == 1 else 1.0)
            glow_xy(g, ox + x0 + 8.5, oy + 1.5 + dy, 12, 32, ORANGE, 0.62 * inten * k * k2, 2.0)
            glow_xy(g, ox + x0 + 8.5, oy + 1.5 + dy, 7, 15, (255, 214, 90), 0.55 * inten * k * k2, 1.7)
        cx0, cw, cs = self.centre()
        k3 = 0.5 if flick == 1 else 1.0
        glow_xy(g, ox + cx0 + cw / 2, oy + cs[0][0] + 0.5, cw * 0.7, 32 if self.TIER == 5 else 20, ORANGE, 0.62 * inten * k * k3, 2.0)
        glow_xy(g, ox + cx0 + cw / 2, oy + cs[0][0] + 0.5, cw * 0.4, 15 if self.TIER == 5 else 9, (255, 214, 90), 0.55 * inten * k * k3, 1.7)

    def core(self, c, on, i):
        Mk3.core(self, c, on, i)
        gold = self.TIER == 5
        a, b = ('y', 'a') if gold else ('a', 'a')
        # reinforced hatch frame in the accent colour, armour corner plates
        c.hline(20, 5, 24, a); c.hline(20, 18, 24, 'u'); c.vline(20, 5, 14, a); c.vline(43, 5, 14, 'u')
        for (x, y, dx, dy) in ((2, 2, 1, 1), (61, 2, -1, 1), (2, 29, 1, -1), (61, 29, -1, -1)):
            c.put(x, y, 'L'); c.put(x + dx, y, 'M'); c.put(x, y + dy, 'M')
        # the vent grille becomes a heat-sink: vertical fins, hot at the tips
        bev(c, 42, 20, 19, 10, 'W', 'E', 'D')
        for q, x in enumerate(range(44, 59, 3)):
            c.vline(x, 22, 6, 'M'); c.vline(x + 1, 22, 6, 'S'); c.vline(x + 2, 22, 6, 'E')
            if on and (q + i) % 3 == 0: c.vline(x, 22, 2, 'o'); c.put(x + 1, 22, 'y')
            elif on: c.put(x, 22, 'a')
    def hurt_core(self, c, i):
        Mk3.hurt_core(self, c, i)
        shift_rect(c, 44, 59, 22, 28, 0, 1 + i); crack(c, [(48, 22), (50, 25), (49, 28)], 'K'); c.put(53, 21 + i, 'y'); c.put(46, 21, 'H' if i else 'y')
        if self.TIER == 5: stamp_on(c, 6, 1, SCORCH_S); stamp_on(c, 48, 2, SCORCH_S)
    def wreck_core(self, c):
        Mk3.wreck_core(self, c)
        shift_rect(c, 43, 60, 21, 29, 1, 1); crack(c, [(47, 21), (50, 25), (48, 28)], 'K'); crack(c, [(55, 22), (57, 26)], 'K')
    def glow_core(self, g, ox, oy, i, flick=None):
        Mk3.glow_core(self, g, ox, oy, i, flick)
        k = 1.0 if flick is None else 0.7
        for q, x in enumerate(range(44, 59, 3)):
            if (q + i) % 3 == 0 and flick is None: glow(g, ox + x + 1.5, oy + 4 + 23, 6, ORANGE, 0.4 * k, 2.0, sx=1.4)
    def flange_in(self, c):
        if self.TIER == 5:
            bev(c, 1, 0, 62, 5, 'y', 'a', 'u')
            for x in (4, 30, 58): c.put(x, 2, 'L')
            for q in range(8, 56, 9): stencil(c, q, 2, 'n', q // 9)

class Mk4(Heavy):
    id = 'engine_mk4'; TIER = 4
    anchors_out = {'exhaust_left': (12, 1), 'exhaust_right': (52, 1), 'exhaust_mid': (32, 10)}
    anchors_in = {'power_coupling': (32, 29), 'repair_hatch': (13, 29)}
    notes = ('Concord Thruster Mk4, a hull mount (outward is up): the 4x3 nozzle housing: two heavy bells with heat-sink fins on a reinforced collar plate with an amber stripe, a taller middle nozzle between them; '
             'inside the Mk3 core with an amber-framed hatch, armour corner plates and a finned heat sink in place of the vent grille. '
             'Damaged: the left bell lip dented and hanging, the right bell cracked and sputtering, a fin torn off, the middle nozzle cracked, sparks. '
             'Disabled: both bells bent over at the neck, the middle nozzle snapped, the fins gone, the collar cracked.')

class Mk5(Heavy):
    id = 'engine_mk5'; TIER = 5
    anchors_out = {'exhaust_left': (12, 4), 'exhaust_right': (52, 4), 'exhaust_mid': (32, 1)}
    anchors_in = {'power_coupling': (32, 29), 'repair_hatch': (13, 29)}
    notes = ('Concord Thruster Mk5, a hull mount (outward is up): the 4x3 nozzle housing with three full bells (the middle one tallest), gold collar rings, heat-sink fins and the Concord gold registry band across the reinforced collar; '
             'inside the Mk4 core with a gold-framed hatch and a gold registry band along the wall flange. '
             'Damaged: the left bell lip dented and hanging, the right bell cracked and sputtering, a fin torn off, the middle bell cracked, sparks. '
             'Disabled: all three bells bent or snapped, the fins gone, the collar cracked (the gold band scorched).')

ALL = [Mk3(), Mk4(), Mk5()]
