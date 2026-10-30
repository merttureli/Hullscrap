"""Long-Burn Drive Mk1-3 (engines_1.md): an explorer's engine. A long narrow bell, fuel drums on the flanks and a big pale-blue exhaust in the glow;
inside, a fuel-efficiency gauge. Same Concord steel as the Thruster ladder, but the light is pale blue (shield blue + white) instead of orange.
 Mk1 a slender bell, two fuel drums with a level window, a dial gauge in the core.
 Mk2 + pale-blue collar rings on the bell, regenerative cooling tubes along it, a second dial and a blue ring round the gauge.
 Mk3 + a flared nozzle extension at the mouth, a second pair of drums, the coolant pump and a cable harness in the core."""
import math
from lines_eng_base import *
from lines_engine import _Mk1, chamfer_tones_h
from lines_eng_std import pump_unit, harness

_M1 = _Mk1()
PALE = (190, 225, 255)
HOT = ('b', 'L', 'H')                           # the lit mouth: shield blue, pale steel-white, white

def drum(s, x0, w, y0, y1, on, i, bands=(1,), window=True):
    """a fuel drum: a steel cylinder with flat caps and a valve on top, pale-blue bands, a sight gauge with the fuel level."""
    T = col_tones(w, 'LMSSSWWEE')
    for y in range(y0, y1):
        inset = 1 if y in (y0, y1 - 1) else 0
        for q in range(inset, w - inset): s.put(x0 + q, y, T[q])
    s.hline(x0, y0 + 2, w, 'E'); s.hline(x0, y1 - 3, w, 'E')
    s.rect(x0 + w // 2 - 1, y0 - 2, 3, 2, 'S'); s.put(x0 + w // 2 - 1, y0 - 2, 'L'); s.put(x0 + w // 2 + 1, y0 - 1, 'W')
    for q, by in enumerate(bands):
        y = y0 + 4 + 5 * by; s.hline(x0, y, w, 'b' if on else 'W'); s.hline(x0, y + 1, w, 'E'); s.put(x0, y, 'H' if on else 'L')
    if window:
        wx = x0 + w // 2 - 1; wy = y1 - 12
        s.rect(wx, wy, 3, 8, 'D'); s.hline(wx, wy, 3, 'K')
        lvl = [5, 6, 5][i % 3] if on else 3
        for k in range(lvl): s.put(wx + 1, wy + 7 - k, 'b' if on else 'E')

def pipe(s, x, y, w):
    s.rect(x, y, w, 2, 'q'); s.hline(x, y, w, 'Q'); s.hline(x, y + 1, w, 'n')

def blue_ring(s, x, y, w):
    s.hline(x, y, w, 'b'); s.hline(x, y + 1, w, 'E'); s.put(x, y, 'H'); s.put(x + 1, y, 'H')

def blue_turbine(s, tx, ty, size, on, i):
    """lit_turbine in pale blue: the hub and the sparks round it."""
    c = size // 2 - 1
    if on:
        for (x, y) in ((tx + c, ty + c), (tx + c + 1, ty + c), (tx + c, ty + c + 1), (tx + c + 1, ty + c + 1)): s.put(x, y, 'L' if (x + y + i) % 2 else 'H')
        for (dx, dy) in ((-1, -1), (2, -1), (-1, 2), (2, 2), (-1, 0), (2, 1), (0, -1), (1, 2)): s.put(tx + c + dx, ty + c + dy, 'b')
    else:
        s.put(tx + c, ty + c, 'E'); s.put(tx + c + 1, ty + c + 1, 'E')

def dial(s, cx, cy, r, on, i, ring_c=None):
    """the fuel-efficiency gauge: a round dial, a red-amber-green arc, a white needle that sits in the green and trembles."""
    circle(s, cx, cy, r, 'E'); ring(s, cx, cy, r - 1.3, r, 'M'); circle(s, cx, cy, r - 1.3, 'D')
    if ring_c: ring(s, cx, cy, r, r + 1.3, ring_c)
    arc = ('r', 'r', 'a', 'a', 'g', 'g', 'g')
    for q, col in enumerate(arc):
        t = math.radians(200 + q * 23.3)               # from lower left over the top to lower right
        x = cx + (r - 2.4) * math.cos(t); y = cy + (r - 2.4) * math.sin(t)
        s.put(int(math.floor(x)), int(math.floor(y)), col if on else 'W')
    for q in range(8):
        t = math.radians(200 + q * 20.0 + 3)
        x = cx + (r - 1.6) * math.cos(t); y = cy + (r - 1.6) * math.sin(t)
        s.put(int(math.floor(x)), int(math.floor(y)), 'L' if on else 'S') if q % 2 == 0 else None
    ang = math.radians([-52, -44, -48][i % 3]) if on else math.radians(160)
    for q in range(0, int((r - 2.5) * 2) + 1):
        t = q / 2.0; x = cx + t * math.cos(ang); y = cy + t * math.sin(ang)
        s.put(int(math.floor(x)), int(math.floor(y)), 'H' if on else 'L')
    circle(s, cx, cy, 1.2, 'S'); s.put(int(cx) - 1, int(cy) - 1, 'L')

def plume(g, ox, oy, cx, y, w, ln, a, i=0):
    """the big pale-blue exhaust: a long wide soft column, shield blue at the edge, white-blue in the core, with a faint flare round the mouth."""
    glow_xy(g, ox + cx, oy + y, w * 2.0, ln, (79, 163, 255), 0.42 * a, 2.0)
    glow_xy(g, ox + cx, oy + y, w * 1.3, ln * 0.82, PALE, 0.5 * a, 1.9)
    glow_xy(g, ox + cx, oy + y, w * 0.65, ln * 0.5, (235, 245, 255), 0.6 * a, 1.7)
    glow(g, ox + cx, oy + y + 1, w * 1.4, (190, 225, 255), 0.35 * a, 2.0, sx=1.2)

class LongBase(EngBase):
    KIND = 'std'; DMG = (0, 2); TIER = 1
    pad_out = (12, 54, 12, 4)
    anchors_out = {'exhaust': (32, 1)}
    anchors_in = {'power_coupling': (32, 29), 'repair_hatch': (13, 29), 'gauge': (16, 17)}
    BX = 27
    def out(self, o, on, i):
        t = self.TIER
        bev(o, 3, 26, 58, 6, 'M', 'S', 'W')
        for x in (6, 31, 32, 57): o.put(x, 28, 'L')
        if t < 3:
            for x0 in (10, 45): drum(o, x0, 9, 8, 27, on, i, bands=(1,) if t == 1 else (0, 1))
            pipe(o, 19, 22, 9); pipe(o, 37, 22, 9)
        else:
            for x0 in (12, 44): drum(o, x0, 8, 10, 27, on, i, bands=(1,))
            for x0 in (3, 53): drum(o, x0, 8, 15, 27, on, i, bands=(0,), window=False)
            pipe(o, 20, 22, 9); pipe(o, 35, 22, 9); pipe(o, 11, 24, 2); pipe(o, 51, 24, 2)
        if t == 3:
            bell_gen(o, 25, 15, [(1, 3, 0), (4, 9, 2), (10, 15, 3), (16, 21, 4), (22, 25, 5)], 28, on, i, bands=(), neck=5, hot=HOT)
            o.hline(26, 4, 13, 'W')
        else:
            bell_gen(o, 27, 11, [(1, 6, 0), (7, 12, 1), (13, 18, 2), (19, 24, 3)], 28, on, i, bands=(), hot=HOT)
        o.hline(28, 25, 8, 'M'); o.hline(28, 26, 8, 'W')
        if t >= 2:
            for (y, w, inset) in ((8, 9, 1), (14, 7, 2)): blue_ring(o, 27 + inset, y if t == 2 else y + 2, w)
            for (xl, xr, ya) in ((24, 38, 9), (25, 37, 15), (26, 36, 20)):          # regenerative cooling tubes up both flanks
                o.vline(xl - 1, ya, 7, 'S'); o.vline(xl, ya, 7, 'M'); o.vline(xr, ya, 7, 'W'); o.vline(xr + 1, ya, 7, 'E')
            o.hline(24, 8, 4, 'S'); o.hline(37, 8, 4, 'S'); o.put(24, 8, 'M')
            if t == 3:
                for y in (12, 18): o.hline(30, y, 5, 'D')
    def hurt_out(self, o, i):
        bx = 25 if self.TIER == 3 else 27; bw = 15 if self.TIER == 3 else 11
        for (x, y) in ((bx, 1), (bx, 2), (bx + 1, 2), (bx, 3), (bx + 1, 3), (bx + 1, 1)): o.erase(x, y)             # the lip dented in
        for (x, y) in ((bx + 1, 4), (bx + 2, 3), (bx + 2, 4)): o.put(x, y, 'W')
        o.stamp(bx - 6, 3, art("KKKK.\nKLMSK\n.KSWK\n..KKK")); o.put(bx - 2, 6, 'S')
        crack(o, [(bx + bw - 3, 7), (bx + bw - 4, 11), (bx + bw - 3, 15), (bx + bw - 5, 20)], 'M')                   # the bell cracked
        if i == 1: o.hline(bx + 2, 1, bw - 4, 'D'); o.hline(bx + 4, 2, bw - 8, 'b')                                 # it sputters
        d = 45
        crack(o, [(d + 3, 11), (d + 5, 15), (d + 3, 19), (d + 5, 23)], 'M'); o.put(d + 4, 24 + i, 'b'); o.put(d + 4, 27, 'b')   # the right drum weeps pale fuel
        o.put(d + 6, 8 - i, 'L'); o.put(d + 2, 6, 'H')
        stamp_on(o, 14, 27, SCORCH_S); stamp_on(o, 44, 28, SCORCH_S)
        if self.TIER >= 2: o.put(bx - 3, 12, 'K'); o.put(bx - 3, 13, 'D'); o.erase(bx - 3, 11)
    def wreck_out(self, o):
        bx = 25 if self.TIER == 3 else 27; bw = 15 if self.TIER == 3 else 11
        shift_rect(o, bx - 4, bx + bw + 4, 0, 20, -3, 1)                                                              # the bell bent over at the neck
        o.hline(bx - 2, 20, bw + 2, 'K'); crack(o, [(bx + 2, 22), (bx + 4, 25), (bx + 3, 28)], 'M'); crack(o, [(bx + 1, 5), (bx + 4, 9), (bx + 2, 13)], 'M')
        o.stamp(bx + bw + 3, 14, art("KKK.\nKLSK\n.KWK"))
        shift_rect(o, 44, 56, 6, 28, 2, 2); crack(o, [(47, 14), (50, 18), (49, 24)], 'M'); o.stamp(55, 8, art("KKK.\nKSMK\n.KSK"))
        shift_rect(o, 8, 21, 6, 28, 0, 2); crack(o, [(11, 14), (14, 20)], 'M')
        for y in range(21, 24): o.erase(36, y); o.erase(37, y)
        stamp_on(o, 20, 28, SCORCH_L)
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.9)
        a = [0.8, 1.0, 0.9][i % 3] * k
        plume(g, ox, oy, 32.5, 1.5, 9.5 if self.TIER == 3 else 8, 50 if self.TIER == 3 else 46, a * (0.6 if flick == 1 else 1.0), i)
    def core(self, c, on, i):
        t = self.TIER
        # the Concord Mk1 core skeleton, its fire lights turned pale blue
        tmp = Spr(64, 32); _M1.core(tmp, on, i)
        tmp = tmp.sub({'o': 'b', 'y': 'L'})
        from_full(c, tmp, 0)
        # replace the lamp panel with the fuel gauge
        c.rect(3, 5, 19, 14, 'S'); bev(c, 3, 5, 19, 14, 'W', 'E', 'D')
        dial(c, 12.0, 12.0, 5.7, on, i, ring_c='b' if t >= 2 else None)
        # level lamps beside the dial
        for q, (cl, y) in enumerate((('g', 7), ('g', 10), ('a', 13), ('r', 16))):
            c.rect(19, y, 2, 2, cl if on and q < 3 else 'W')
        if t == 3:                                                          # the coolant pump replaces the feed pipes, a harness across the middle
            pump_unit(c, on, i); harness(c, on)
            c.rect(29, 6, 1, 1, 'E')
        elif t == 2:                                                        # a second, small dial where the feed pipes were
            c.rect(44, 4, 18, 15, 'S'); bev(c, 44, 4, 17, 14, 'W', 'E', 'D')
            dial(c, 51.0, 11.0, 4.4, on, i + 1)
            for y in (6, 8): c.hline(57, y, 3, 'D'); c.hline(57, y + 1, 3, 'b' if on else 'E')
    def hurt_core(self, c, i):
        crack(c, [(7, 7), (11, 10), (10, 14), (14, 17)], 'M')
        for (x, y) in ((10, 11), (11, 11), (10, 12)): c.put(x, y, 'D')
        c.put(12, 12 - i, 'r'); c.put(8, 15, 'W')
        for (x, y) in ((19, 7), (19, 10)): c.rect(x, y, 2, 2, 'r')
        stamp_on(c, 36, 20, SCORCH_S); stamp_on(c, 25, 21, SCORCH_S)
        c.put(41, 6 + 2 * i, 'y'); c.put(40, 5 + i, 'H'); c.put(34 + 3 * i, 18, 'y'); c.put(31, 20 - 2 * i, 'H' if i else 'y')
        crack(c, [(28, 8), (31, 11), (30, 13), (33, 16)], 'M')
    def wreck_core(self, c):
        c.stamp(6, 6, art("KKKKKKKKKKK\nKDDDDDDDDDK\nKDDDDDKDDDK\nKDDKDDDDDDK\n.KKKKKKKKK.")); c.stamp(8, 11, art("KK.KK\nKDKDK\n.KKK."))
        crack(c, [(5, 6), (9, 10), (8, 14), (13, 17)], 'M')
        c.stamp(29, 8, art(".KKKK.\nKDDDDK\nKDDDDK\n.KKKK."))
        c.stamp(6, 21, art("KKKKKKKK\nKDDDDDDK\nKDDKDDDK\n.KKKKKK.")); c.stamp(15, 24, art("KK.\nKSK\n.KK"))
        stamp_on(c, 27, 21, SCORCH_L)
        crack(c, [(2, 10), (6, 13)], 'M')
    def glow_core(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.9)
        b = oy + 4
        glow(g, ox + 12, b + 12, 7, GREEN if flick is None else RED, 0.28 * k, 2.0)
        for (lx, ly, rgb) in ((19.5, 7.5, GREEN), (19.5, 10.5, GREEN), (19.5, 13.5, AMBER), (19.5, 16.5, RED)):
            if flick is not None and ly > 9: rgb = RED
            if ly < 16: glow(g, ox + lx + .5, b + ly + .5, 3.4, rgb, 0.5 * k, 2.0)
        if flick != 1: glow(g, ox + 32, b + 12, 9, (79, 163, 255), [0.35, 0.5, 0.4][i % 3] * k, 2.0)
        glow(g, ox + 32, b + 25, 6, GREEN, 0.4 * k, 2.0)
        for vy in (22, 24, 26, 28):
            if (vy // 2 + i) % 3 == 0 and flick is None: glow(g, ox + 51, b + vy + 1, 7, (79, 163, 255), 0.3, 2.0, sx=1.8)
        if self.TIER == 3: glow(g, ox + 57.5, b + 11.5, 3.5, GREEN if flick is None else RED, 0.4 * k, 2.0)
        if self.TIER == 2: glow(g, ox + 51, b + 11, 5, GREEN if flick is None else RED, 0.2 * k, 2.0)

class Mk1(LongBase):
    id = 'longburn_mk1'; TIER = 1
    notes = ('Concord Long-Burn Drive Mk1, a hull mount (outward is up): a long slender bell on a plate, a fuel drum with a level window on each side piped into the bell base, a pale-blue exhaust; '
             'inside the Concord core with its lights pale blue and a big fuel-efficiency dial (red, amber and green arc, a trembling needle) with level lamps. '
             'Damaged: the bell lip dented and hanging, the bell cracked and sputtering, the right drum cracked and weeping pale fuel, the dial glass cracked and its needle stuck, lamps red, sparks. '
             'Disabled: the bell bent over at the neck, a drum split and slid off, the dial dead and cracked, the repair hatch popped.')
class Mk2(LongBase):
    id = 'longburn_mk2'; TIER = 2
    notes = ('Concord Long-Burn Drive Mk2, a hull mount (outward is up): Mk1 plus pale-blue collar rings on the bell, regenerative cooling tubes up both flanks, a second band on each drum; '
             'inside a blue ring round the fuel-efficiency dial and a second small dial where the feed pipes were. '
             'Damaged: the bell lip dented and hanging, the bell cracked and sputtering, a cooling tube kinked, the right drum weeping pale fuel, the dial glass cracked, lamps red, sparks. '
             'Disabled: the bell bent over at the neck, a drum split and slid off, a cooling tube snapped, the dials dead, the repair hatch popped.')
class Mk3(LongBase):
    id = 'longburn_mk3'; TIER = 3; BX = 25
    notes = ('Concord Long-Burn Drive Mk3, a hull mount (outward is up): a longer bell with a flared nozzle extension at the mouth, blue rings and cooling tubes, four fuel drums (two each side) with cabling between them; '
             'inside the Mk2 dial plus the coolant pump and a cable harness. '
             'Damaged: the skirt lip dented and hanging, the bell cracked and sputtering, a cooling tube kinked, the right drum weeping pale fuel, the dial glass cracked, lamps red, sparks. '
             'Disabled: the bell bent over at the neck, a drum split and slid off, a cooling tube snapped, the dial dead, the repair hatch popped.')

ALL = [Mk1(), Mk2(), Mk3()]
