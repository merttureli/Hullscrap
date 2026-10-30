"""Ion Drive: Halo, Corona and Zenith (engines_1.md). engine_neon_mk1 (Glimmer, lines_engine.py) stays as it is; every tier is built ON it (navy panels, crisp cyan edges, magenta pins, the glow carrying the light):
 Mk2 Halo     a ring of light round the spine (outside) and round the lens crystal (core), with magenta nodes the light runs round.
 Mk3 Corona   + crystal fins instead of the outriggers, and a crown of crystal spikes round the lens.
 Mk4 Zenith   (outside 4x3) four ion rings under a crystal emitter, bigger fins, a base block; the glow layer carries a floating crystal halo above the nozzle."""
import math
from lines_eng_base import *
from lines_engine import _Neon

_N1 = _Neon()

def shard(s, bx, by, h, w, lean=0, on=True, pin=False):
    """a crystal fin standing on (bx, by): facets lit from the top-left (bright, ridge, dark), the tip leaning `lean` px, a white tip when lit."""
    tn = ('c', 'C', 'B') if on else ('W', 'S', 'E')
    for k in range(h):
        y = by - k
        half = max(0, int(round(w / 2.0 * (1 - k / float(h)))))
        cx = bx + int(round(lean * k / float(h)))
        for x in range(cx - half, cx + half + 1):
            s.put(x, y, tn[0] if x < cx else (tn[1] if x == cx else tn[2]))
        if half == 0: s.put(cx, y, 'H' if on and k == h - 1 else tn[1])
    if pin: s.put(bx - 1, by - h // 2, 'm' if on else 'E')

def halo_ring(s, cx, cy, rx, ry, on, i, flat=False, dash=False, nodes=(0, 180)):
    """a thin ring of light (an ellipse): the near half in front, the far half only where the sky shows; magenta nodes at the given angles, a white glint that runs round."""
    n = int(2 * math.pi * max(rx, ry) * 1.7)
    for k in range(n):
        if dash and k % 6 > 3: continue
        t = 2 * math.pi * k / n
        x = int(round(cx + rx * math.cos(t))); y = int(round(cy + ry * math.sin(t)))
        front = flat or math.sin(t) >= -0.15
        if front: s.put(x, y, 'c' if on else 'W')
        elif s.get(x, y) == '.': s.put(x, y, 'B' if on else 'E')
        if on and not flat and math.sin(t) > 0.3 and s.get(x, y + 1) == '.': s.put(x, y + 1, 'B')
    for a in nodes:
        t = math.radians(a); x = int(round(cx + rx * math.cos(t))); y = int(round(cy + ry * math.sin(t)))
        s.put(x, y, 'm' if on else 'E')
    if on:
        for q in range(3):
            t = 2 * math.pi * (i / 3.0 + q / 3.0) + 0.5; x = int(round(cx + rx * math.cos(t))); y = int(round(cy + ry * math.sin(t)))
            if flat or math.sin(t) >= 0: s.put(x, y, 'H')

def ring_glow(g, cx, cy, rx, ry, rgb, a, n=16, r=3.0, i=0, sx=1.0):
    for k in range(n):
        t = 2 * math.pi * k / n
        glow(g, cx + rx * math.cos(t), cy + ry * math.sin(t), r, rgb, a * (1.0 if (k + i) % 4 else 1.5), 2.0, sx=sx)

def draw_ring(s, y, x0, x1, on, lit):
    w = x1 - x0 + 1
    s.rect(x0, y, w, 4, 'J'); s.hline(x0, y, w, 'j'); s.hline(x0, y + 3, w, 'I')
    s.hline(x0 + 1, y + 1, w - 2, 'N'); s.hline(x0 + 1, y + 2, w - 2, 'N')
    for x in range(x0 + 2, x1 - 1):
        s.put(x, y + 1, ('H' if (x + 1) % 4 == 0 else 'c') if lit else ('C' if on else 'E'))
        s.put(x, y + 2, 'C' if lit else ('B' if on else 'E'))
    s.put(x0, y + 1, 'c' if on else 'W'); s.put(x0, y + 2, 'm' if on else 'E'); s.put(x1, y + 1, 'c' if on else 'W'); s.put(x1, y + 2, 'm' if on else 'E')
    s.put(x0, y, 'L' if on else 'S'); s.put(x1, y + 3, 'W')

# ================================================================ Mk2: Halo
class Mk2(EngBase):
    id = 'engine_neon_mk2'; KIND = 'neon'
    pad_out = (12, 36, 12, 4)
    anchors_out = {'exhaust': (32, 1)}
    anchors_in = {'power_coupling': (32, 30), 'repair_hatch': (12, 29)}
    RING = (32, 23.5, 15, 3.2)
    notes = ('Lumen "Ion Drive: Halo", a hull mount (outward is up): the Glimmer ion rings and spine plus a ring of light round the spine (cyan, magenta nodes, a glint that runs round it) and a soft ring of light in the glow; '
             'inside the Glimmer core with a second ring of light round the lens crystal. '
             'Damaged: the middle ring has slipped out of line and cracked, the halo ring is broken and arcs jump the gap, the lens crystal is cracked and flickers. '
             'Disabled: the top ring snapped half off and hanging, the halo ring broken and dark, the lens shattered, every line dead.')
    def out(self, o, on, i):
        from_full(o, _N1.interior('on' if on else 'off', i), 0)
        cx, cy, rx, ry = self.RING
        halo_ring(o, cx, cy, rx, ry, on, i)
    def hurt_out(self, o, i):
        via_full(_N1, o, 0, 'hurt', i)
        cx, cy, rx, ry = self.RING
        for (x, y) in ((cx + 9, cy + 3), (cx + 10, cy + 3), (cx + 11, cy + 2), (cx - 12, cy + 2), (cx - 11, cy + 3)): o.erase(int(x), int(y))
        o.put(int(cx + 12), int(cy + 3), 'm' if i else 'H'); o.put(int(cx + 8 + 2 * i), int(cy + 5), 'c'); o.put(int(cx - 13), int(cy + 4 - i), 'H')
    def wreck_out(self, o):
        via_full(_N1, o, 0, 'wreck')
        cx, cy, rx, ry = self.RING
        for x in range(int(cx + 4), int(cx + 14)): o.erase(x, int(cy + 3)); o.erase(x, int(cy + 4))
        shift_rect(o, int(cx - 16), int(cx - 8), int(cy - 1), int(cy + 5), -2, 2); o.stamp(int(cx + 11), int(cy + 3), art("KK.\nKWK\n.KK"))
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        for kk, (y, x0, x1) in enumerate(_N1.RINGS):
            lit = kk == (2 - i) % 3
            if flick is not None and kk == 1: continue
            glow(g, ox + (x0 + x1) / 2 + .5, oy + y + 2.5, 16 if lit else 8, CYAN, (0.45 if lit else 0.18) * k, 2.0, sx=1.6)
        glow_xy(g, ox + 32, oy + 2, 26, 30, MAGENTA, 0.34 * k * (0.9 + 0.05 * i), 1.9)
        glow_xy(g, ox + 32, oy + 2, 15, 24, CYAN, 0.5 * k, 2.0)
        glow_xy(g, ox + 32, oy + 4, 7, 10, (210, 250, 255), 0.55 * k, 1.8)
        cx, cy, rx, ry = self.RING
        ring_glow(g, ox + cx + .5, oy + cy + .5, rx, ry, CYAN, 0.2 * k, n=14, r=3.2, i=i, sx=1.5)
    def core(self, c, on, i):
        t = Spr(64, 32); _N1.core(t, on, i); from_full(c, t, 0)
        halo_ring(c, 32, 11.5, 11.5, 9, on, i, flat=True, nodes=(90, 270))
    def hurt_core(self, c, i):
        via_full(_N1, c, 48, 'hurt', i)
        for (x, y) in ((22, 17), (23, 18), (24, 19)): c.erase(x, y)
        c.put(21, 18 + i, 'm' if i else 'H')
    def wreck_core(self, c):
        via_full(_N1, c, 48, 'wreck')
        for (x, y) in ((22, 17), (23, 18), (24, 19), (41, 5), (42, 6), (43, 8), (32, 21), (33, 21)): c.erase(x, y)
        crack(c, [(41, 4), (43, 8), (42, 12)], 'M')
    def glow_core(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        b = oy + 4
        glow(g, ox + 32, b + 11, 9, CYAN, 0.45 * k, 2.0); glow(g, ox + 32, b + 26, 5, CYAN, 0.35 * k, 2.0)
        for (x, y) in ((24, 5), (39, 5), (24, 18), (39, 18)): glow(g, ox + x + .5, b + y + .5, 3, MAGENTA, 0.45 * k, 2.0)
        ring_glow(g, ox + 32, b + 12, 11.5, 9, CYAN, 0.16 * k, n=14, r=2.6, i=i)

# ================================================================ Mk3: Corona
class Mk3(Mk2):
    id = 'engine_neon_mk3'
    anchors_in = {'power_coupling': (32, 30), 'repair_hatch': (12, 29)}
    notes = ('Lumen "Ion Drive: Corona", a hull mount (outward is up): the Halo spine and ring of light, with the outriggers replaced by crystal fins (cyan facets, a white tip, magenta pins) that fan out from the base; '
             'inside the Halo core with a crown of crystal spikes round the lens. '
             'Damaged: the middle ring has slipped and cracked, a crystal fin is snapped half off, arcs jump the gap, the lens is cracked and flickers. '
             'Disabled: the top ring snapped half off, both fin clusters broken and dark, the halo ring dead, the lens shattered.')
    FINS = ((8, 27, 14, 5, -1), (14, 27, 9, 4, 0), (3, 27, 9, 4, -1))
    def out(self, o, on, i):
        from_full(o, _N1.interior('on' if on else 'off', i), 0)
        for y in range(14, 32):
            for x in range(4, 18): o.erase(x, y)
            for x in range(46, 60): o.erase(x, y)
        for (bx, by, h, w, lean) in self.FINS:
            shard(o, bx, by, h, w, lean, on, pin=True); shard(o, 63 - bx, by, h, w, -lean, on, pin=True)
        cx, cy, rx, ry = self.RING
        halo_ring(o, cx, cy, rx, ry, on, i)
    def hurt_out(self, o, i):
        Mk2.hurt_out(self, o, i)
        for (x, y) in ((11, 17), (12, 18), (12, 19), (13, 19)): o.put(x, y, 'K')
        shift_rect(o, 4, 18, 12, 21, 1, 1); o.put(10 + i, 12, 'H'); crack(o, [(55, 20), (57, 24), (56, 27)], 'M')
    def wreck_out(self, o):
        Mk2.wreck_out(self, o)
        shift_rect(o, 3, 19, 13, 27, -2, 3); shift_rect(o, 45, 61, 16, 27, 3, 2)
        o.hline(5, 24, 9, 'K'); o.hline(49, 24, 9, 'K'); crack(o, [(10, 20), (12, 23), (9, 26)], 'M')
    def glow_out(self, g, ox, oy, i, flick=None):
        Mk2.glow_out(self, g, ox, oy, i, flick)
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        for (bx, by, h, w, lean) in self.FINS:
            for xx in (bx, 63 - bx): glow(g, ox + xx + .5, oy + by - h * 0.6, w * 1.6, CYAN, 0.3 * k, 2.0)
    def core(self, c, on, i):
        Mk2.core(self, c, on, i)
        # the corona: a crown of crystal spikes round the lens
        for (sx, sy, dx, dy) in ((20, 6, -1, -1), (43, 6, 1, -1), (20, 17, -1, 1), (43, 17, 1, 1), (19, 11, -1, 0), (44, 11, 1, 0)):
            for k in range(4):
                x, y = sx + dx * k, sy + dy * k
                c.put(x, y, ('H' if on and k == 3 else 'c') if on else 'W')
                if dx == 0 or k < 3: c.put(x + (1 if dx < 0 else -1 if dx > 0 else 0), y + (0 if dy == 0 else 0), 'C' if on else 'S') if k == 1 else None
    def hurt_core(self, c, i):
        Mk2.hurt_core(self, c, i)
        for (x, y) in ((43, 17), (44, 18), (45, 19)): c.erase(x, y)
    def wreck_core(self, c):
        Mk2.wreck_core(self, c)
        for (x, y) in ((20, 6), (19, 5), (43, 17), (44, 18)): c.erase(x, y)
    def glow_core(self, g, ox, oy, i, flick=None):
        Mk2.glow_core(self, g, ox, oy, i, flick)
        k = 1.0 if flick is None else 0.6
        b = oy + 4
        for (x, y) in ((17.5, 5.5), (46.5, 5.5), (17.5, 18.5), (46.5, 18.5), (16.5, 12), (47.5, 12)): glow(g, ox + x, b + y, 3.2, CYAN, 0.3 * k, 2.0)

# ================================================================ Mk4: Zenith
class Mk4(Mk3):
    id = 'engine_neon_mk4'; OUT_H = 48
    pad_out = (12, 46, 12, 4)
    RINGS4 = [(5, 5, 58), (12, 9, 54), (19, 13, 50), (26, 17, 46)]
    FINS4 = ((9, 43, 22, 6, -2), (15, 43, 15, 5, -1), (4, 43, 13, 4, -1))
    anchors_out = {'exhaust': (32, 1)}
    notes = ('Lumen "Ion Drive: Zenith", a hull mount (outward is up): the 4x3 housing: four ion rings (widest at the nozzle) under a crystal emitter, tall crystal fins on both flanks, a ring of light round the base of the spine, and a floating ring of crystal glints in the glow above the nozzle; '
             'inside the Corona core with a second, dashed ring of light round the lens. '
             'Damaged: the second ring has slipped out of line and cracked, the emitter crystal is chipped, a fin is snapped half off, arcs jump the gap, the lens is cracked and flickers. '
             'Disabled: the top ring snapped half off and hanging, the emitter broken, both fin clusters dead and broken, the lens shattered.')
    def lit(self, k, i): return (k == 0 and i == 0) or (k == 3 and i == 0) or (k == 1 and i == 1) or (k == 2 and i == 2)
    def out(self, o, on, i):
        # spine behind the rings, struts, rings, the base block, fins, the halo ring round the base, the emitter crystal
        h = 44 - 12
        navy_panel(o, 25, 12, 14, h)
        o.vline(27, 13, h - 2, 'c' if on else 'W'); o.vline(36, 13, h - 2, 'c' if on else 'W')
        o.rect(29, 13, 6, h - 2, 'N'); o.vline(29, 13, h - 2, 'B' if on else 'E'); o.vline(34, 13, h - 2, 'B' if on else 'E')
        for y in range(13, 13 + h - 2):
            if on and (y + 3 * (i % 3)) % 6 < 2: o.put(31, y, 'c'); o.put(32, y, 'c')
            elif on: o.put(31, y, 'C'); o.put(32, y, 'B')
            else: o.put(31, y, 'E'); o.put(32, y, 'E')
        for (ya, yb) in ((9, 12), (16, 19), (23, 26)):
            for x in (24, 38): o.rect(x, ya, 2, yb - ya, 'J')
        navy_panel(o, 14, 34, 36, 10); edge(o, 14, 34, 36, 10, 1, 'c' if on else 'W')
        o.rect(24, 36, 16, 6, 'N'); hollow(o, 24, 36, 16, 6, 'B' if on else 'E'); o.rect(27, 37, 10, 4, 'I')
        for x in (16, 47): o.put(x, 36, 'm' if on else 'E'); o.put(x, 41, 'm' if on else 'E')
        for k, (y, x0, x1) in enumerate(self.RINGS4): draw_ring(o, y, x0, x1, on, on and self.lit(k, i))
        for (bx, by, hh, w, lean) in self.FINS4:
            shard(o, bx, by, hh, w, lean, on, pin=True); shard(o, 63 - bx, by, hh, w, -lean, on, pin=True)
        halo_ring(o, 32, 39, 12, 2.6, on, i, nodes=(0, 180))
        shard(o, 32, 5, 7, 6, 0, on)
    def hurt_out(self, o, i):
        y, x0, x1 = self.RINGS4[1]
        o.rect(x0 - 2, y - 1, x1 - x0 + 5, 6, '.')
        xx0, xx1 = x0 + 3, x1 - 2
        o.rect(xx0, y + 1, xx1 - xx0 + 1, 4, 'J'); o.hline(xx0, y + 1, xx1 - xx0 + 1, 'j'); o.hline(xx0 + 1, y + 2, xx1 - xx0 - 1, 'N'); o.hline(xx0 + 1, y + 3, xx1 - xx0 - 1, 'N')
        for x in range(xx0 + 3, xx1 - 2): o.put(x, y + 2, 'B'); o.put(x, y + 3, 'N')
        crack(o, [(xx0 + 4, y + 1), (xx0 + 8, y + 3), (xx0 + 12, y + 2), (xx0 + 15, y + 4)], 'M')
        for (x, yy) in ((xx0 - 1, y + 2), (xx1 + 2, y + 3)): o.put(x, yy, 'm' if i else 'H')
        for (x, yy) in ((xx0 + 6 + 10 * i, y - 1), (xx0 + 7 + 10 * i, y - 2), (xx0 + 8 + 10 * i, y - 2)): o.put(x, yy, 'm' if not i else 'c')
        for (x, yy) in ((31, 0), (32, 0), (33, 1)): o.erase(x, yy)
        for (x, yy) in ((10, 30), (11, 31), (11, 32), (12, 32)): o.put(x, yy, 'K')
        shift_rect(o, 3, 18, 28, 36, 1, 1); crack(o, [(54, 28), (56, 33), (55, 38)], 'M')
        for (x, yy) in ((40, 38), (41, 38), (42, 39), (21, 39), (22, 39)): o.erase(x, yy)
        o.put(43, 39 + i, 'm' if i else 'H'); o.put(19, 40 - i, 'H')
    def wreck_out(self, o):
        shift_rect(o, 3, 60, 5, 9, -6, 2)
        y0, a0, b0 = self.RINGS4[0]; crack(o, [(14, y0 + 3), (17, y0 + 4), (20, y0 + 6)], 'M'); o.stamp(40, y0 + 4, art("KKK.\nKJIK\n.KKK"))
        shift_rect(o, 8, 56, 12, 16, 2, 0); o.stamp(44, 16, art("KK.\nKSM\n.KK"))
        y2, a2, b2 = self.RINGS4[2]; crack(o, [(a2 + 12, y2 + 2), (a2 + 14, y2 + 5)], 'M')
        for x in range(28, 36):
            for y in range(0, 5): o.erase(x, y)
        o.stamp(29, 3, art("KKK.\nKSMK\n.KKK"))
        shift_rect(o, 3, 20, 20, 40, -2, 3); shift_rect(o, 44, 61, 20, 40, 3, 2); o.hline(6, 40, 10, 'K'); o.hline(50, 40, 9, 'K')
        for x in range(36, 46): o.erase(x, 38); o.erase(x, 39)
        o.stamp(40, 41, art("KK.\nKWK\n.KK"))
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        for kk, (y, x0, x1) in enumerate(self.RINGS4):
            lit = self.lit(kk, i)
            if flick is not None and kk == 1: continue
            glow(g, ox + (x0 + x1) / 2 + .5, oy + y + 2.5, 16 if lit else 8, CYAN, (0.45 if lit else 0.18) * k, 2.0, sx=1.7)
        glow_xy(g, ox + 32, oy + 4, 28, 36, MAGENTA, 0.3 * k * (0.9 + 0.05 * i), 1.9)
        glow_xy(g, ox + 32, oy + 4, 16, 28, CYAN, 0.5 * k, 2.0)
        glow_xy(g, ox + 32, oy + 5, 8, 12, (210, 250, 255), 0.55 * k, 1.8)
        ring_glow(g, ox + 32.5, oy + 39.5, 12, 2.6, CYAN, 0.22 * k, n=12, r=3.0, i=i, sx=1.4)
        for (bx, by, hh, w, lean) in self.FINS4:
            for xx in (bx, 63 - bx): glow(g, ox + xx + .5, oy + by - hh * 0.55, w * 1.7, CYAN, 0.3 * k, 2.0)
        # the floating crystal halo: a ring of crystal glints hanging above the nozzle, turning a little every frame
        hy = oy - 12
        n = 10
        for q in range(n):
            t = 2 * math.pi * (q + i / 3.0) / n
            x, y = ox + 32 + 25 * math.cos(t), hy + 5 * math.sin(t)
            near = math.sin(t) > 0
            a = (0.55 if near else 0.3) * k * (1.4 if (q + i) % 3 == 0 else 1.0)
            glow(g, x, y, 4.2 if near else 3.2, (210, 250, 255), a, 2.0)
            glow(g, x, y, 7.5, CYAN, 0.28 * k, 2.0, sx=0.8)
            if near or (q + i) % 3 == 0:
                for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1), (0, 2), (0, -2)): g.over(int(x) + dx, int(y) + dy, (255, 255, 255, int(150 * k * a)))
        ring_glow(g, ox + 32, hy, 25, 5, CYAN, 0.12 * k, n=28, r=2.2, i=i)
    def core(self, c, on, i):
        Mk3.core(self, c, on, i)
        halo_ring(c, 32, 11.5, 14, 11, on, i + 1, flat=True, dash=True, nodes=(45, 135, 225, 315))
    def hurt_core(self, c, i):
        Mk3.hurt_core(self, c, i)
        for (x, y) in ((45, 9), (46, 10), (45, 20)): c.erase(x, y)
    def wreck_core(self, c):
        Mk3.wreck_core(self, c)
        for (x, y) in ((45, 9), (46, 10), (45, 20), (19, 3), (20, 2)): c.erase(x, y)
    def glow_core(self, g, ox, oy, i, flick=None):
        Mk3.glow_core(self, g, ox, oy, i, flick)
        k = 1.0 if flick is None else 0.6
        ring_glow(g, ox + 32, oy + 4 + 12, 14, 11, CYAN, 0.12 * k, n=14, r=2.4, i=i)

ALL = [Mk2(), Mk3(), Mk4()]
