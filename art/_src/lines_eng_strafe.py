"""Strafe Jets Mk1-3 (engines_1.md): compact, 2x2 cells outside and inside, mounted on the side walls for A/D strafe.
Two small bells angled slightly outward (so the exhaust leaves a little to each side), a small core with a spinning gyro. Same Concord steel and orange exhaust as the Thruster ladder:
 Mk1 plain jets on a plate.  Mk2 + amber collar rings, a coolant canister between the jets, an amber ring round the gyro.
 Mk3 + a third, straight micro-nozzle between the jets, a wider bell, a second small gyro and a cable harness in the core."""
import math
from lines_eng_base import *

JETS = ((9, 5), (22, 26))                         # (base centre x, mouth centre x) of the left and right jet

def tjet(s, cbase, ctop, ytop, ybase, on, i, ring=False, wide=0, flick=0):
    """a small stepped bell leaning from its base centre to its mouth centre; the lean is the 'angled slightly outward'."""
    H = ybase - ytop
    prof = (9 + wide, 7 + wide, 5 + wide)
    cut1, cut2 = 4, 9
    for k in range(H):
        y = ytop + k
        w = prof[0] if k < cut1 else (prof[1] if k < cut2 else prof[2])
        cc = ctop + int(round((cbase - ctop) * k / float(H - 1)))
        x0 = cc - w // 2
        T = col_tones(w)
        for q in range(w): s.put(x0 + q, y, T[q])
        if k in (cut1, cut2): s.hline(x0, y, w, 'E')
        if k == cut2 + 6 or k == cut2 + 10: s.hline(x0, y, w, 'M'); s.hline(x0, y + 1, w, 'W')
    # mouth
    w0 = prof[0]; x0 = ctop - w0 // 2
    s.hline(x0 + 2, ytop, w0 - 4, 'D'); s.hline(x0 + 2, ytop + 1, w0 - 4, 'D')
    s.put(x0 + 1, ytop, 'M'); s.put(x0 + 1, ytop + 1, 'L'); s.put(x0 + w0 - 2, ytop, 'W'); s.put(x0 + w0 - 2, ytop + 1, 'M')
    s.put(x0 + 1, ytop + 3, 'L'); s.put(x0 + w0 - 2, ytop + 3, 'L')
    if on:
        fl = [0, 1, 0][(i + flick) % 3]
        s.hline(x0 + 2 + fl, ytop, w0 - 4 - 2 * fl, 'o'); s.hline(x0 + 2, ytop + 1, w0 - 4, 'o'); s.hline(x0 + 3 + fl, ytop + 1, max(0, w0 - 6 - 2 * fl), 'y')
        s.put(x0 + w0 // 2, ytop + 1, 'H')
    else: s.hline(x0 + 3, ytop + 1, w0 - 6, 'E')
    if ring:                                       # the amber collar ring: the Mk2 accent
        y = ytop + 6; cc = ctop + int(round((cbase - ctop) * 6 / float(H - 1))); w = prof[1]; xr = cc - w // 2
        s.hline(xr, y, w, 'a'); s.hline(xr, y + 1, w, 'u'); s.put(xr, y, 'y'); s.put(xr + 1, y, 'y')

def plume_tilt(g, x, y, dx, length, r0, a, i=0):
    """a soft exhaust plume leaving (x, y) upward, drifting dx px sideways over its length."""
    n = int(length / 3)
    for t in range(n):
        f = t / float(n)
        glow(g, x + dx * f, y - t * 3, r0 * (1 - 0.45 * f) + 1.5, ORANGE, a * (1 - f) ** 1.3, 2.0)
    glow(g, x, y + 1, r0 * 0.7, (255, 214, 90), a * 0.9, 1.7)

def gyro(s, cx, cy, r, on, i, accent=None, dead=False):
    circle(s, cx, cy, r, 'E'); ring(s, cx, cy, r - 1.4, r, 'S'); circle(s, cx, cy, r - 1.4, 'D')
    ang = (i % 3) * math.pi / 3 if on else math.pi / 6
    L = r - 2.2
    for q in range(-int(L * 2), int(L * 2) + 1):
        t = q / 2.0; x = cx + t * math.cos(ang); y = cy + t * math.sin(ang)
        s.put(int(math.floor(x)), int(math.floor(y)), 'L' if on else 'W'); s.put(int(math.floor(x)), int(math.floor(y)) + 1, 'M' if on else 'E')
    circle(s, cx, cy, 1.5, 'y' if on else 'E'); s.put(int(cx) - 1, int(cy) - 1, 'H' if on else 'W')
    if accent: ring(s, cx, cy, r, r + 1.3, accent)

class StrafeBase(EngBase):
    W = 32; OUT_H = 32; KIND = 'std'; DMG = (0, 2)
    pad_out = (8, 34, 8, 4); pad_in = (8, 6, 8, 8)
    TIER = 1
    anchors_out = {'exhaust_left': (5, 3), 'exhaust_right': (26, 3)}
    anchors_in = {'power_coupling': (21, 31), 'repair_hatch': (8, 31)}
    def wide(self): return 1 if self.TIER == 3 else 0
    def out(self, o, on, i):
        bev(o, 1, 24, 30, 8, 'M', 'S', 'W')
        for x in (4, 15, 16, 27): o.put(x, 26, 'L')
        if self.TIER == 2:                                    # a coolant canister between the jets
            T = col_tones(6, 'LMSSWE')
            for y in range(13, 25):
                for q in range(6): o.put(13 + q, y, T[q])
            o.hline(14, 12, 4, 'M'); o.hline(13, 17, 6, 'a'); o.hline(13, 18, 6, 'u'); o.put(15, 21, 'E'); o.put(15, 22, 'L')
        if self.TIER == 3:                                    # a straight micro-nozzle between the jets
            bell_gen(o, 12, 8, [(10, 13, 0), (14, 17, 1), (18, 21, 2)], 25, on, i, bands=(), neck_tones='LMSSWE')
            o.hline(13, 14, 6, 'a'); o.hline(13, 15, 6, 'u')
        o.rect(11, 22, 10, 2, 'q'); o.hline(11, 22, 10, 'Q'); o.hline(11, 23, 10, 'n')           # the feed pipe between the jets
        for n, (cb, ct) in enumerate(JETS):
            tjet(o, cb, ct, 3, 25, on, i, ring=self.TIER >= 2, wide=self.wide(), flick=n)
    def hurt_out(self, o, i):
        x0 = JETS[0][1] - (9 + self.wide()) // 2; c2 = JETS[1][1]
        for (x, y) in ((x0, 3), (x0 + 1, 3), (x0, 4), (x0 + 1, 4), (x0, 5), (x0 + 1, 5), (x0, 6)): o.erase(x, y)                    # a bite out of the left lip
        for (x, y) in ((x0 + 2, 4), (x0 + 2, 5), (x0 + 1, 6)): o.put(x, y, 'W')
        o.stamp(10, 5, art("KKKK.\nKLMSK\n.KSWK\n..KKK")); o.put(9, 6, 'S'); o.put(9, 7, 'W')                                        # the lip hanging by a corner
        for (x, y) in ((x0 + 1 + i, 2), (x0 + 2, 1 + i)): o.put(x, y, 'y' if i else 'H')
        shift_rect(o, 17, 32, 0, 12, 1, 0); o.hline(c2 - 3, 12, 9, 'K')                                                            # the right bell is bent at the neck
        crack(o, [(c2 + 1, 14), (c2 + 2, 17), (c2, 20), (c2 + 1, 23)], 'M')
        if i == 1: o.hline(c2 - 1, 3, 5, 'D'); o.hline(c2, 4, 3, 'o')
        stamp_on(o, 4, 25, SCORCH_S); stamp_on(o, 22, 26, SCORCH_S)
    def wreck_out(self, o):
        shift_rect(o, 0, 14, 0, 14, -2, 1); shift_rect(o, 18, 32, 0, 14, 2, 1)
        for xx in (JETS[0][0] - 4, JETS[1][0] - 4): o.hline(xx, 14, 9, 'K'); crack(o, [(xx + 3, 17), (xx + 5, 20), (xx + 3, 23)], 'M')
        o.stamp(0, 8, art("KKK.\nKLSK\n.KWK")); o.put(29, 12, 'K'); stamp_on(o, 13, 22, SCORCH_S)
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.9)
        inten = [0.8, 1.0, 0.9][i % 3]
        for n, (cb, ct) in enumerate(JETS):
            k2 = 0.8 if (flick is not None and n == 0) else (0.55 if flick == 1 and n == 1 else 1.0)
            plume_tilt(g, ox + ct + .5, oy + 3, (-4 if n == 0 else 4), 30, 5.0 + self.wide(), 0.6 * inten * k * k2, i)
        if self.TIER == 3:
            glow_xy(g, ox + 16, oy + 10.5, 5, 14, ORANGE, 0.5 * inten * k * (0.5 if flick == 1 else 1.0), 2.0)
    def core(self, c, on, i):
        t = self.TIER
        bev(c, 1, 1, 30, 30, 'M', 'S', 'W')
        for x0 in (5, 20):                                                  # tube stubs in from the wall
            c.rect(x0, 0, 7, 3, 'S'); c.vline(x0, 0, 3, 'L'); c.vline(x0 + 6, 0, 3, 'W'); c.hline(x0 - 1, 3, 9, 'M'); c.hline(x0 - 1, 4, 9, 'W')
        bev(c, 3, 6, 15, 15, 'W', 'E', 'D')
        gyro(c, 10.5, 13.5, 5.6, on, i, accent='a' if t >= 2 else None)
        bev(c, 19, 6, 11, 9, 'W', 'E', 'D')
        for q, (cl, x) in enumerate((('g', 21), ('g', 24), ('a', 27))):
            col = cl if on and q < 3 else 'W'
            for (xx, yy) in ((x, 8), (x + 1, 8), (x, 9), (x + 1, 9)): c.put(xx, yy, col)
            if on and cl == 'g': c.put(x, 8, 'H')
        bars = [[2, 3, 2], [3, 2, 3], [2, 3, 3]][i % 3] if on else [1, 1, 1]
        for bx, hh in zip((21, 24, 27), bars):
            for r in range(hh): c.put(bx, 13 - r, 'c' if on else 'E')
        if t < 3:
            bev(c, 19, 16, 11, 5, 'W', 'E', 'D'); c.hline(21, 18, 7, 'D'); c.hline(21, 19, 7, 'W')
        else:                                                               # a second, smaller gyro
            bev(c, 19, 16, 11, 7, 'W', 'E', 'D'); gyro(c, 24.5, 19.5, 2.9, on, i + 1)
        bev(c, 3, 23, 12, 7, 'L', 'M', 'S'); hollow(c, 5, 25, 8, 3, 'W'); c.hline(6, 26, 5, 'a'); c.put(6, 26, 'y')
        bev(c, 16, 23, 10, 7, 'W', 'E', 'D'); circle(c, 21, 26.5, 2.6, 'D'); ring(c, 21, 26.5, 1.8, 2.8, 'g' if on else 'W'); c.put(20, 25, 'E')
        bev(c, 27, 23, 4, 7, 'W', 'E', 'D')
        for vy in (24, 26, 28): c.put(28, vy, 'o' if on and (vy // 2 + i) % 3 == 0 else 'D'); c.put(29, vy, 'D')
        if t >= 2:
            for x in (2, 29): c.put(x, 2, 'L')
        if t == 3:                                                          # a cable harness between the upper and lower rows
            c.hline(2, 21, 28, 'q'); c.hline(2, 22, 28, 'n')
            for x in range(5, 29, 7): c.put(x, 21, 'Q'); c.put(x + 1, 21, 'Q')
        c.put(15, 28, 'a' if on else 'W')
    def hurt_core(self, c, i):
        crack(c, [(7, 9), (10, 12), (9, 16), (12, 18)], 'M')
        for (x, y) in ((9, 12), (10, 12), (9, 13), (10, 13)): c.put(x, y, 'D')
        c.put(11 - i, 14, 'W')
        for (x, y) in ((3, 8), (4, 8)): c.put(x, y, 'r')
        for q, x in enumerate((21, 24)): c.rect(x, 8, 2, 2, 'r' if q else 'W')
        stamp_on(c, 20, 24, SCORCH_S); stamp_on(c, 5, 24, SCORCH_S)
        c.put(26 + 2 * i, 20, 'y'); c.put(25, 19 - i, 'H'); c.put(14, 22 + i, 'y')
        crack(c, [(4, 25), (7, 27), (6, 29)], 'M')
    def wreck_core(self, c):
        c.stamp(6, 10, art(".KKKKKK.\nKDDDDDDK\nKDDKDDDK\nKDDDDKDK\n.KKKKKK.")); crack(c, [(5, 8), (8, 12), (7, 17), (11, 19)], 'M')
        c.stamp(4, 24, art("KKKKKKKK\nKDDDDDDK\nKDDKDDDK\n.KKKKKK.")); c.stamp(12, 27, art("KK.\nKSK\n.KK"))
        stamp_on(c, 17, 23, SCORCH_L); c.put(3, 8, 'r'); c.put(4, 8, 'E')
        crack(c, [(25, 4), (27, 9), (26, 13)], 'M')
    def glow_core(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.9)
        b = oy + 4
        if flick != 1: glow(g, ox + 11, b + 14, 7, ORANGE, [0.4, 0.55, 0.45][i % 3] * k, 2.0)
        for (lx, rgb) in ((21, GREEN), (24, GREEN), (27, AMBER)):
            if flick is not None and lx > 22: rgb = RED
            glow(g, ox + lx + 1, b + 9, 3.6, rgb, 0.5 * k, 2.0)
        glow(g, ox + 21, b + 27, 5, GREEN, 0.4 * k, 2.0)
        if self.TIER >= 2: glow(g, ox + 10.5, b + 13.5, 8.5, AMBER, 0.16 * k, 2.0)
        if self.TIER == 3: glow(g, ox + 25, b + 20, 4, ORANGE, 0.3 * k, 2.0)

class Mk1(StrafeBase):
    id = 'strafe_jets_mk1'; TIER = 1
    notes = ('Concord Strafe Jets Mk1, a small hull mount (outward is up; mount it on a side wall for A/D strafe): a pair of small steel bells angled slightly outward on a plate with a feed pipe between them, '
             'and inside a compact core with a spinning gyro, a lamp panel, a repair hatch and a green-ringed power coupling. '
             'Damaged: the left bell lip dented and hanging, the right bell cracked and sputtering, the gyro glass cracked and stalling, lamps red, sparks. '
             'Disabled: both bells bent over at the neck, the gyro dead and cracked, the hatch popped.')
class Mk2(StrafeBase):
    id = 'strafe_jets_mk2'; TIER = 2
    notes = ('Concord Strafe Jets Mk2, a small hull mount (outward is up; mount it on a side wall for A/D strafe): Mk1 plus an amber collar ring on each bell, a coolant canister between the jets, and inside an amber ring round the gyro. '
             'Damaged: the left bell lip dented and hanging, the right bell cracked and sputtering, the gyro glass cracked and stalling, lamps red, sparks. '
             'Disabled: both bells bent over at the neck, the gyro dead and cracked, the hatch popped.')
class Mk3(StrafeBase):
    id = 'strafe_jets_mk3'; TIER = 3
    notes = ('Concord Strafe Jets Mk3, a small hull mount (outward is up; mount it on a side wall for A/D strafe): wider ringed bells angled outward with a straight micro-nozzle between them, '
             'and inside the Mk2 core with a second, smaller gyro and a cable harness. '
             'Damaged: the left bell lip dented and hanging, the right bell cracked and sputtering, the gyro glass cracked and stalling, lamps red, sparks. '
             'Disabled: both bells bent over at the neck, the micro-nozzle snapped, the gyro dead and cracked, the hatch popped.')
    anchors_out = {'exhaust_left': (5, 3), 'exhaust_right': (26, 3), 'exhaust_mid': (16, 10)}

ALL = [Mk1(), Mk2(), Mk3()]
