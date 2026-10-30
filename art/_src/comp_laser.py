"""Laser Mk1, 4x2 cells, barrel pointing EAST at rotation 0."""
from comp_base import *

CELL_X = [19, 23, 27, 31, 35]
FLASH = [art("""
...o..
..oyo.
.oyyyo
.yHHyo
yHHHHy
HHHHHH
HHHHHH
yHHHHy
.yHHyo
.oyyyo
..oyo.
...o..
"""), art("""
......
......
...o..
..oyo.
.oyHyo
oyHHHy
oyHHHy
.oyHyo
..oyo.
...o..
......
......
""")]

class Laser(Comp):
    id = 'laser_mk1'; cells = (4, 2)
    glow_pad = (8, 8, 24, 8)
    anims = [('on', 'ready', 1, 0), ('off', 'off', 1, 0), ('charge', 'charge', 6, 0), ('fire', 'fire', 2, 12),
             ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    anchors = {'muzzle': (63, 15)}
    notes = ('Barrel points east (right) at rot 0. charge: pick frame round(fraction*5); frame 5 = ready (all cells green, lens lit). '
             'fire plays once (flash + afterglow). on = the ready frame.')
    scorch = [(26, 3, 'S'), (45, 19, 'L')]
    loose = (16, 15)
    cracks = [(22, 6, 'A'), (4, 11, 'B'), (47, 11, 'A')]

    def frame(self, state, i):
        if state == 'damaged':        # damaged: ready frame with damage, lens flickering
            self._dmg_i = i
        return Comp.frame(self, state, i)

    def interior(self, state, i):
        powered = state != 'off'
        lit = {'charge': i, 'ready': 5, 'on': 5}.get(state, 0)
        ready = state in ('ready', 'on') or (state == 'charge' and i == 5)
        fire = state == 'fire'
        if state == 'on' and getattr(self, '_dmg_i', 0) == 1: ready = False     # damaged flicker frame
        s = Spr(64, 32)
        bev(s, 1, 6, 14, 20, 'M', 'S', 'W')
        for cx in (4, 7, 10):
            s.rect(cx, 8, 2, 16, 'q'); s.vline(cx, 8, 16, 'Q'); s.vline(cx + 1, 8, 16, 'n')
        s.rect(2, 14, 1, 4, 'D'); s.put(2, 15, 'g' if powered else 'E'); s.put(2, 16, 'g' if powered else 'E')
        bev(s, 14, 4, 27, 24, 'M', 'S', 'W')
        hollow(s, 16, 6, 23, 20, 'W')
        for vx in (20, 27, 34): s.rect(vx, 7, 4, 2, 'D')
        for (x, y) in ((17, 7), (37, 7), (17, 24), (37, 24)): s.put(x, y, 'L')
        recess(s, 18, 12, 19, 8, 'D', 'K')
        for k, cx in enumerate(CELL_X):
            on = k < lit and not fire
            for r in range(4):
                if ready and on: c = 'g'
                elif on: c = 'y' if r < 2 else 'a'
                else: c = 'E' if r > 0 else 'W'
                s.hline(cx, 14 + r, 3, c)
            if on: s.put(cx, 14, 'H')
        s.stamp(19, 21, art("""
.KKKK.
KDDDDK
KDcDDK
KDDDDK
KDDDDK
.KKKK.
"""))
        if powered: s.put(21, 23, 'c'); s.put(22, 22, 'c')
        else: s.put(21, 23, 'E')
        for hx in range(27, 38, 4):
            for k in range(3): s.put(hx + k, 21 + k, 'a'); s.put(hx + k + 1, 21 + k, 'D')
        s.rect(26, 2, 5, 2, 'W'); s.put(28, 1, 'c' if powered else 'E'); s.put(27, 2, 'M'); s.put(26, 2, 'M')
        for cy in (8, 23): s.rect(12, cy, 3, 2, 'q'); s.hline(12, cy, 3, 'Q')
        bev(s, 41, 7, 4, 4, 'W', 'E', 'D', cham=False); bev(s, 41, 21, 4, 4, 'W', 'E', 'D', cham=False)
        tones = 'LMMSSSSWWE'
        for r in range(10): s.hline(41, 11 + r, 16, tones[r])
        for rx in (44, 49, 54):
            bev(s, rx, 9, 3, 14, 'L', 'M', 'S', cham=False)
            s.vline(rx + 2, 9, 14, 'W'); s.hline(rx, 22, 3, 'W')
        bev(s, 56, 9, 5, 14, 'S', 'E', 'D')
        s.rect(58, 12, 3, 8, 'D')
        if ready or fire:
            s.rect(58, 12, 3, 8, 'r'); s.rect(59, 13, 2, 6, 'o'); s.rect(60, 14, 1, 4, 'y'); s.put(60, 15, 'H'); s.put(60, 16, 'H')
        else:
            s.rect(58, 13, 3, 6, 'E'); s.put(58, 13, 'W'); s.put(59, 13, 'W')
        return s

    def after(self, state, i, s):
        if state == 'fire': s.stamp(58, 10, FLASH[i])
        return s

    def glow(self, state, i, g, ox, oy):
        lit = {'charge': i, 'ready': 5, 'damaged': 5}.get(state, 0)
        ready = state in ('ready', 'damaged') or (state == 'charge' and i == 5)
        if state == 'damaged' and i == 1: ready = False
        for j in range(lit if state != 'fire' else 0):
            glow(g, ox + CELL_X[j] + 1.5, oy + 15.5, 5.0, (107, 211, 74) if ready else (255, 210, 58), 0.55, 2.0)
        glow(g, ox + 2.5, oy + 16, 4, (107, 211, 74), 0.5, 2.0)
        if ready: glow(g, ox + 60, oy + 16, 11, (255, 80, 60), 0.6, 2.0)
        if state == 'fire':
            r = (22, 14)[i]
            glow(g, ox + 62, oy + 15.5, r, (255, 130, 50), 0.6 if i == 0 else 0.4, 2.0, sx=1.25)
            glow(g, ox + 62, oy + 15.5, r / 2, (255, 235, 160), 0.7 if i == 0 else 0.4, 1.6)
