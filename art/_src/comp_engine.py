"""Engine Mk1, 4x2 cells. Nozzles on the WEST end at rotation 0 (thrust pushes the ship east)."""
from comp_base import *

class Engine(Comp):
    id = 'engine_mk1'; cells = (4, 2)
    glow_pad = (16, 8, 8, 8)
    anims = [('on', 'on', 3, 8), ('off', 'off', 1, 0), ('damaged', 'damaged', 3, 8), ('disabled', 'disabled', 1, 0)]
    anchors = {'exhaust_upper': (1, 7), 'exhaust_lower': (1, 22)}
    notes = 'Nozzles face west (left) at rot 0. Glow loop: hot nozzle bloom, hatch and lamps.'
    scorch = [(29, 17, 'L'), (6, 3, 'S'), (52, 20, 'S')]
    loose = (39, 7)
    cracks = [(26, 9, 'A'), (8, 18, 'B'), (44, 17, 'A')]

    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 32)
        def bell(y0):
            segs = [(1, 3, 0, 11), (4, 8, 1, 9), (9, 14, 2, 7), (15, 19, 3, 5)]
            for x0, x1, inset, rows in segs:
                tones = {11: 'LLMMSSSWWEE', 9: 'LMMSSSWWE', 7: 'MMSSSWE', 5: 'MSSWE'}[rows]
                for r in range(rows): s.hline(x0, y0 + inset + r, x1 - x0 + 1, tones[r])
            for bx, a, b in ((7, 1, 9), (13, 2, 8), (18, 3, 7)):
                for r in range(a, b): s.put(bx, y0 + r, 'E' if r > 3 else 'W')
            s.vline(3, y0, 11, 'L'); s.put(3, y0 + 10, 'M')
            for r in range(2, 9): s.put(1, y0 + r, 'D'); s.put(2, y0 + r, 'D')
            s.put(1, y0 + 1, 'M'); s.put(2, y0 + 1, 'L'); s.put(1, y0 + 9, 'W'); s.put(2, y0 + 9, 'M')
            if on:     # hot core, flickers over 3 frames
                lo, hi = [(3, 8), (2, 9), (3, 8)][i]
                for r in range(lo, hi): s.put(1, y0 + r, 'o')
                for r in range(lo + 1, hi - 1): s.put(2, y0 + r, 'y')
                s.put(2, y0 + 5, 'H'); s.put(1, y0 + 5, 'y' if i == 1 else 'o')
                if i == 2: s.put(2, y0 + 4, 'H')
            else:
                for r in range(3, 8): s.put(1, y0 + r, 'E')
                s.put(2, y0 + 5, 'W')
        bell(2); bell(17)
        s.rect(10, 13, 4, 4, 'q'); s.vline(10, 13, 4, 'Q'); s.vline(13, 13, 4, 'n')
        s.hline(9, 14, 6, 'M'); s.hline(9, 15, 6, 'W')
        bev(s, 20, 2, 5, 26, 'M', 'S', 'W', cham=False)
        for y in (7, 14, 15, 22): s.hline(20, y, 5, 'E')
        for y in (4, 25): s.put(22, y, 'L')
        bev(s, 25, 2, 26, 26, 'M', 'S', 'W')
        for py in (4, 23):
            s.rect(27, py, 22, 3, 'q'); s.hline(27, py, 22, 'Q'); s.hline(27, py + 2, 22, 'n')
            for cx in (30, 38, 46): s.vline(cx, py - 1, 5, 'M'); s.vline(cx + 1, py - 1, 5, 'W')
        recess(s, 27, 8, 22, 14, 'E', 'K')
        s.stamp(33, 10, art("""
..KKKKKK..
.KEEEEEEK.
KEESSSSEEK
KESDDDDSEK
KESDSSDSEK
KESDSSDSEK
KESDDDDSEK
KEESSSSEEK
.KEEEEEEK.
..KKKKKK..
"""))
        if on:
            for (x, y) in ((36, 14), (37, 14), (36, 15), (37, 15)): s.put(x, y, 'y' if (x + y + i) % 2 else 'H')
            for (x, y) in ((35, 14), (38, 14), (35, 15), (38, 15), (36, 13), (37, 13), (36, 16), (37, 16)): s.put(x, y, 'o')
        else:
            for (x, y) in ((36, 14), (37, 15)): s.put(x, y, 'E')
            for (x, y) in ((37, 14), (36, 15)): s.put(x, y, 'W')
        for vy in (10, 12, 14, 16, 18): s.hline(44, vy, 3, 'D'); s.hline(44, vy + 1, 3, 'W')
        for vx in (29, 31): s.vline(vx, 10, 10, 'D')
        for (x, y) in ((27, 3), (48, 3), (27, 26), (48, 26)): s.put(x, y, 'L')
        bev(s, 51, 4, 10, 22, 'W', 'E', 'D')
        s.put(52, 5, 'M')
        for k, (c, y) in enumerate([('g', 7), ('g', 11), ('a', 15), ('r', 19)]):
            lit = on and k < 3
            col = c if lit else 'W'
            s.hline(53, y, 3, 'D')
            for (x, yy) in ((54, y + 1), (55, y + 1), (54, y + 2), (55, y + 2)): s.put(x, yy, col)
            if lit and c == 'g': s.put(54, y + 1, 'H')
        recess(s, 56, 7, 4, 8, 'D', 'K')
        bars = [[3, 5, 2], [4, 3, 3], [2, 5, 4]][i] if on else [1, 1, 1]
        for bx, hh in zip((57, 58, 59), bars):
            for r in range(hh): s.put(bx, 13 - r, 'c' if on else 'E')
        for yy in (17, 19, 21): s.hline(56, yy, 4, 'W')
        s.put(57, 23, 'a' if on else 'W')
        s.rect(49, 13, 2, 3, 'q'); s.hline(49, 13, 2, 'Q'); s.hline(49, 15, 2, 'n')
        return s

    def glow(self, state, i, g, ox, oy):
        inten, rad, hub = [(0.78, 13.0, 0.35), (1.0, 15.0, 0.55), (0.88, 14.0, 0.45)][i]
        for cy in (7, 22):
            glow(g, ox + 1, oy + cy + 0.5, rad, (255, 138, 30), 0.55 * inten, 2.2, sx=1.25)
            glow(g, ox + 1, oy + cy + 0.5, rad * 0.45, (255, 214, 90), 0.5 * inten, 1.6, sx=1.1)
        glow(g, ox + 37, oy + 15, 8, (255, 138, 30), hub, 2.0)
        for (lx, ly, rgb) in ((54.5, 8.5, (107, 211, 74)), (54.5, 12.5, (107, 211, 74)), (54.5, 16.5, (225, 161, 54))):
            glow(g, ox + lx, oy + ly, 4.5, rgb, 0.55, 2.0)
