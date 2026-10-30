"""Reactors, 4x4: Mk2 (Concord), Rustbucket (Scrap), Prism Core (Neon)."""
from lines_kit import *
from comp_new import pipe_v, pipe_h, lamp

def crack(s, pts, hi='L'):
    for (a, b) in zip(pts, pts[1:]): line(s, a[0], a[1], b[0], b[1], 'K')
    for (x, y) in pts[1:-1:2]:
        if s.get(x + 1, y) not in ('.', 'K'): s.put(x + 1, y, hi)

# ============================================================ REACTOR MK2 (standard)
class ReactorMk2(LComp):
    id = 'reactor_mk2'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    notes = ('Concord Mk2: Mk1 plus a second (outer) ring whose 8 amber lamps chase around it, and a bigger, hotter core. '
             'Damaged: the upper-right capacitor is split open and sparking, the left pipe has slipped its flange and weeps, the outer ring has a chipped gap, the core stutters. '
             'Disabled: dead core, the casing split corner to corner, the capacitor blown out.')
    DMG = (1, 3)
    PULSE = [8, 9, 10, 9]
    LAMPS = [(17, 20), (21, 16), (46, 20), (42, 16), (17, 43), (21, 47), (46, 43), (42, 47)]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 61, 61, 'S', 8); rim(s, 'S', 'M', 'W')
        chamfer_fill(s, 5, 5, 53, 53, 'W', 7)
        for d in range(5, 58, 8): s.put(d, 31, 'E'); s.put(31, d, 'E')
        # second ring, under the pipes: 2px steel ring with a recessed channel
        chamfer_fill(s, 13, 13, 38, 38, 'S', 11); chamfer_fill(s, 15, 15, 34, 34, 'W', 10)
        rim(s, 'S', 'L', 'E', (13, 13, 50, 50))
        for k, (lx, ly) in enumerate(self.LAMPS):
            lit = on and ((k % 4) == i or (k % 4) == (i + 1) % 4 and False)
            for (dx, dy) in ((0, 0), (1, 0)): s.put(lx + dx, ly + dy, 'y' if lit and dx == 0 else ('o' if lit else 'E'))
        pipe_v(s, 29, 2, 13, (6, 11)); pipe_v(s, 29, 49, 13, (51, 56))
        pipe_h(s, 2, 29, 13, (6, 11)); pipe_h(s, 49, 29, 13, (51, 56))
        for (bx, by) in ((6, 6), (46, 6), (6, 46), (46, 46)):
            bev(s, bx, by, 12, 12, 'M', 'S', 'W')
            s.rect(bx + 2, by + 7, 8, 1, 'D'); s.rect(bx + 2, by + 9, 8, 1, 'D')
            lamp(s, bx + 3, by + 3, 'g', on)
            s.put(bx + 8, by + 3, 'L'); s.put(bx + 8, by + 4, 'S')
        stencil(s, 7, 14, 'L', 0); stencil(s, 55, 49, 'L', 1)           # registry marks
        chamfer_fill(s, 16, 16, 32, 32, 'M', 9); rim(s, 'M', 'L', 'S', (16, 16, 47, 47))
        chamfer_fill(s, 19, 19, 26, 26, 'E', 7)
        chamfer_fill(s, 21, 21, 22, 22, 'D', 6)
        for (x, y) in ((31, 17), (32, 17), (31, 46), (32, 46), (17, 31), (17, 32), (46, 31), (46, 32), (22, 21), (41, 21), (22, 42), (41, 42)):
            s.put(x, y, 'H' if (x + y) % 2 else 'L')
        if on:
            r = self.PULSE[i]
            chamfer_fill(s, 32 - r, 32 - r, 2 * r, 2 * r, 'o', r // 2 + 1)
            chamfer_fill(s, 32 - r + 2, 32 - r + 2, 2 * r - 4, 2 * r - 4, 'y', r // 2)
            chamfer_fill(s, 32 - r + 3, 32 - r + 3, 2 * r - 6, 2 * r - 6, 'H', max(1, r // 2 - 1))
            for (x, y) in ((24, 24), (39, 24), (24, 39), (39, 39)): s.put(x, y, 'u')
        else:
            for (x, y) in ((26, 26), (37, 26), (26, 37), (37, 37), (31, 26), (26, 31), (37, 32), (32, 37)): s.rect(x, y, 2, 2, 'E')
            s.put(24, 23, 'W'); s.put(25, 23, 'W'); s.put(23, 24, 'W')
        return s
    def hurt(self, s, i):
        # upper-right capacitor split open: a black seam, the lid hanging, bare wire and a spark
        bev(s, 46, 6, 12, 12, 'S', 'E', 'D')
        for (x, y) in ((47, 7), (48, 8), (49, 9), (50, 10), (51, 12), (52, 13), (53, 14), (54, 15)): s.put(x, y, 'K')
        s.rect(52, 6, 6, 4, 'D'); s.hline(52, 6, 6, 'K'); s.hline(52, 9, 6, 'W')
        s.put(54, 8, 'r'); s.put(55, 7, 'a'); s.put(56, 8, 'a')
        s.stamp(55, 12, art(".KK\nKDD\n.KL"))                               # loose corner of the lid
        for (x, y) in ((50, 9), (53, 11)): s.put(x, y, 'H' if i else 'y')
        s.put(58, 10 + i, 'y'); s.put(57, 12 - i, 'H' if i else 'y')
        # left pipe slipped its flange: a gap, offset ends, a weeping seam
        s.rect(7, 29, 3, 6, '.'); s.rect(6, 31, 2, 5, 'q'); s.vline(6, 31, 5, 'Q')
        for (x, y) in ((8, 29), (9, 28), (9, 35), (8, 36)): s.put(x, y, 'L' if i else 'M')
        s.put(8, 37 + i, 'L'); s.put(8, 39 + 2 * i, 'M')
        # outer ring chipped (upper-left diagonal)
        for (x, y) in ((17, 20), (18, 20), (18, 19), (19, 19), (19, 18), (20, 17), (20, 18), (18, 21)): s.put(x, y, 'K')
        for (x, y) in ((16, 22), (21, 16)): s.put(x, y, 'D')
        # scorched deck, cracked bottom-right block
        stamp_on(s, 38, 17, SCORCH_S)
        for (x, y) in ((11, 41), (12, 42), (11, 43)): s.put(x, y, 'D')
        crack(s, [(47, 47), (49, 50), (48, 52), (51, 55)])
        # core stutter
        if i == 1:
            for (x, y) in ((32, 32), (33, 32), (32, 33), (33, 33)): s.put(x, y, 'o')
    def wreck(self, s):
        # casing split corner to corner, capacitor blown out, ring broken
        crack(s, [(3, 11), (7, 14), (6, 18), (11, 21), (13, 26), (18, 28)])
        crack(s, [(46, 49), (50, 47), (53, 51), (57, 50), (60, 54)])
        bev(s, 46, 6, 12, 12, 'S', 'D', 'K')
        s.rect(48, 8, 8, 8, 'K'); s.stamp(47, 7, SCORCH_L); stamp_on(s, 52, 12, SCORCH_S)
        s.put(53, 10, 'a'); s.put(50, 14, 'r')
        for (x, y) in ((17, 20), (18, 20), (18, 19), (19, 19), (19, 18), (20, 17), (20, 18)): s.put(x, y, 'K')
        s.stamp(36, 38, art("KKKK.\nKDDDK\n.KDKK")); stamp_on(s, 24, 38, SCORCH_S)
        s.stamp(6, 45, art("KKK\nKLL\nKLM")); s.put(8, 47, 'S')              # bolt popped out of its seat
    def glow(self, state, i, g, ox, oy, flick=None):
        r = self.PULSE[i]
        k = 1.0 if flick is None else (0.55 if flick else 0.85)
        glow(g, ox + 32, oy + 32, 24 + r * 1.5, ORANGE, (0.34 + 0.03 * r) * k, 1.4)
        glow(g, ox + 32, oy + 32, 5 + r * 0.8, YEL, 0.6 * k, 1.6)
        for (bx, by) in ((6, 6), (46, 6), (6, 46), (46, 46)):
            if flick is not None and (bx, by) == (46, 6): continue
            glow(g, ox + bx + 4, oy + by + 4, 5, GREEN, 0.5 * k, 2.0)
        if flick is None:
            for j, (lx, ly) in enumerate(self.LAMPS):
                if j % 4 == i: glow(g, ox + lx + 1, oy + ly + .5, 4.5, ORANGE, 0.6, 2.0)
        else:
            glow(g, ox + 55, oy + 8, 6, YEL, 0.5 if flick else 0.25, 2.0)       # the spark

# ============================================================ RUSTBUCKET REACTOR (scrap)
class ReactorScrap(LComp):
    id = 'reactor_scrap_mk1'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)]
    notes = ('Scrapper Clans: a patched pressure vessel, mismatched plates, hazard tape, a leaking pipe (steam puffs and a falling drip on the loop), a flickering amber core in a window with a rust patch over one corner. '
             'Damaged: the vessel patch has popped its bolts and hangs, the core hiccups, wire ends spit sparks, the drip becomes a stream. '
             'Disabled: dead core, the vessel split open along the weld with the patch plate fallen off, a dark leak pool.')
    DMG = (1, 3)
    FL = [(7, 0, 0), (5, 1, 0), (8, -1, 1), (6, 0, 1)]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 61, 61, 'W', 8)
        plate(s, 2, 2, 29, 28, 'S'); plate(s, 30, 2, 32, 24, 'u'); plate(s, 2, 29, 24, 33, 'M'); plate(s, 25, 26, 37, 36, 'S')
        weld(s, 29, 4, 20, True)                                        # seam between the top plates
        weld(s, 27, 52, 14)                                             # seam on the lower plate
        s.rect(3, 31, 2, 1, 'W')
        # lower-left: tape, rusty sheet, scrawled stencil
        hazard(s, 3, 57, 22, 4)
        s.rect(7, 47, 12, 8, 'q'); s.hline(7, 47, 12, 'Q'); s.hline(7, 54, 12, 'n'); bolts(s, [(8, 48), (16, 48)])
        s.put(11, 51, 'a' if on else 'n'); s.put(12, 51, 'a' if on else 'n'); s.put(13, 51, 'a' if on and i % 2 == 0 else 'n')
        # pressure vessel
        chamfer_fill(s, 14, 14, 36, 36, 'D', 11); chamfer_fill(s, 15, 15, 34, 34, 'S', 10); rim(s, 'S', 'M', 'W', (15, 15, 48, 48))
        chamfer_fill(s, 18, 18, 28, 28, 'W', 8); rim(s, 'W', 'S', 'E', (18, 18, 45, 45))
        for x in range(21, 44, 4): s.put(x, 16, 'L'); s.put(x + 1, 47, 'W')
        for y in range(21, 44, 4): s.put(16, y, 'L'); s.put(47, y + 1, 'W')
        chamfer_fill(s, 21, 21, 22, 22, 'D', 7); edge(s, 21, 21, 22, 22, 7, 'E')
        weld(s, 19, 44, 26)                                             # band welded round the base
        # the core, flickering, off-centre wobble
        if on:
            r, dx, dy = self.FL[i]
            cx, cy = 32 + dx, 32 + dy
            chamfer_fill(s, cx - r, cy - r, 2 * r, 2 * r, 'o', r // 2 + 1)
            chamfer_fill(s, cx - r + 2, cy - r + 2, 2 * r - 4, 2 * r - 4, 'y', max(1, r // 2 - 1))
            if r >= 6: s.rect(cx - 1, cy - 1, 2, 2, 'H')
            for (x, y) in ((24, 24), (39, 39), (24, 39)): s.put(x, y, 'u')
        else:
            for (x, y) in ((26, 26), (37, 26), (26, 37), (31, 31), (32, 32)): s.rect(x, y, 2, 2, 'E')
        # rust patch bolted over the window's upper-right corner
        s.rect(36, 18, 11, 9, 'u'); s.hline(36, 18, 11, 'Q'); s.vline(36, 18, 9, 'Q'); s.hline(36, 26, 11, 'n'); s.vline(46, 18, 9, 'n')
        bolts(s, [(38, 20), (43, 20), (38, 23), (43, 23)])
        s.put(39, 22, 'q'); s.put(40, 22, 'q'); s.put(41, 25, 'n')
        # pipes: leaky one on top (taped joint), a clamped one on the left, a cable on the right
        pipe_v(s, 21, 2, 13, (4,)); hazard(s, 20, 8, 8, 4)
        for (x, y) in ((22, 11), (23, 11), (24, 11)): s.put(x, y, 'K')
        pipe_h(s, 2, 37, 13, (5,)); s.rect(8, 36, 3, 8, 'u'); s.vline(8, 36, 8, 'Q'); s.vline(10, 36, 8, 'n'); s.put(9, 38, 'L'); s.put(9, 41, 'L')
        for k, (c, y) in enumerate((('r', 29), ('a', 31), ('n', 33))): s.hline(50, y, 11, c)
        s.rect(55, 27, 3, 8, 'E'); s.vline(55, 27, 8, 'S'); s.put(56, 28, 'L'); s.put(56, 33, 'L')
        s.put(61, 29, 'r'); s.put(61, 30, 'D')
        # corner kit: barrel, cell, taped block, lamp plate, all different
        circle(s, 10.5, 10.5, 5.4, 'n'); circle(s, 10.5, 10.5, 4.4, 'u'); circle(s, 10, 10, 2.6, 'Q'); circle(s, 10.5, 10.5, 1.4, 'q'); s.put(9, 9, 'L')
        bev(s, 46, 5, 13, 11, 'M', 'S', 'W'); s.rect(48, 10, 9, 1, 'D'); s.rect(48, 12, 9, 1, 'D'); s.put(49, 7, 'a' if on else 'n'); s.put(50, 7, 'a' if on else 'n'); bolts(s, [(55, 6)])
        bev(s, 46, 47, 14, 12, 'L', 'M', 'S'); bolts(s, [(48, 49), (56, 49)]); s.hline(50, 54, 6, 'D')
        for k, c in enumerate(('a', 'o')): s.rect(50 + 3 * k, 52, 2, 1, c if on else 'n')
        # wire loop hanging from the barrel
        line(s, 16, 12, 19, 14, 'r'); line(s, 19, 14, 19, 17, 'r'); s.put(19, 18, 'a')
        # steam and the drip (leak between the tape and the pipe end)
        steam = [[(28, 9), (29, 8)], [(29, 7), (30, 6), (28, 7)], [(30, 5), (31, 4), (29, 5)], [(31, 3), (28, 5)]][i]
        for k, (x, y) in enumerate(steam): s.put(x, y, 'L' if k == 0 else 'M')
        if on:
            dy = [12, 14, 16, 18][i]
            s.put(20, dy, 'H'); s.put(20, dy - 1, 'L')
            s.hline(18, 19, 4, 'D') if i == 3 else None
        s.hline(16, 20, 5, 'D'); s.put(17, 20, 'E')                      # the stain the drip leaves
        stamp_on(s, 3, 22, art("u.\nuu\n.u\n.u"))                         # rust runs under a bolt
        stamp_on(s, 53, 12, art("u.\n.u\nuu"))
        clip(s, 1, 1, 61, 61, 8)
        return s
    def hurt(self, s, i):
        # the vessel patch pops its bolts and hangs by the lower ones
        s.rect(36, 18, 11, 9, '.'); s.rect(21, 21, 22, 22, 'D')
        chamfer_fill(s, 21, 21, 22, 22, 'D', 7); edge(s, 21, 21, 22, 22, 7, 'E')
        s.rect(36, 24, 11, 4, 'u'); s.hline(36, 24, 11, 'Q'); s.hline(36, 27, 11, 'n'); bolts(s, [(38, 25), (43, 25)])
        s.rect(37, 19, 9, 3, 'K'); s.hline(37, 22, 9, 'n'); s.put(41, 20, 'a' if i else 'o')
        for (x, y) in ((36, 18), (37, 17), (46, 19), (47, 20)): s.put(x, y, 'L')
        # drip becomes a stream, puddle spreading
        s.rect(20, 12, 2, 7, 'H' if i else 'L'); s.put(20, 19, 'L'); s.hline(15, 20, 8, 'D'); s.hline(16, 21, 6, 'E')
        # wire ends spit
        s.put(61, 28 + i, 'y'); s.put(60, 27 - i, 'H'); s.put(61, 31, 'a' if i else 'y')
        s.stamp(9, 24, art("DD.\nKKD\n.KK")); crack(s, [(3, 49), (5, 52), (8, 51), (10, 54)])
        if i == 1:
            for (x, y) in ((31, 31), (32, 31), (31, 32), (32, 32)): s.put(x, y, 'o')
        else:
            for (x, y) in ((28, 28), (35, 28), (28, 35), (35, 35)): s.put(x, y, 'D')
    def wreck(self, s):
        # the vessel split along its weld; patch plate fallen off, leaving a ragged hole; a dark pool
        s.rect(36, 18, 11, 9, '.'); s.rect(36, 18, 11, 9, 'K')
        for (x, y) in ((36, 18), (46, 18), (36, 26), (46, 26), (37, 19)): s.put(x, y, 'D')
        crack(s, [(15, 30), (19, 31), (21, 34), (26, 35), (28, 39), (33, 40), (36, 44), (41, 44), (46, 49)])
        crack(s, [(23, 17), (24, 21), (22, 24), (24, 27)])
        s.stamp(46, 28, art("KKKK.\nKLMSK\nKSSWK\n.KKKK")); s.stamp(8, 31, SCORCH_L)  # the fallen patch plate, bolts still in it
        s.rect(46, 29, 3, 2, 'u')
        s.stamp(15, 17, art("..KKKK.\n.KDDDDK\nKDDDDDDK\n.KDDDKK.")); s.hline(16, 21, 8, 'D')
        s.rect(54, 28, 7, 2, 'n'); s.rect(54, 31, 7, 2, 'E')
    def glow(self, state, i, g, ox, oy, flick=None):
        r, dx, dy = self.FL[i]
        k = 1.0 if flick is None else (0.5 if flick else 0.8)
        if flick == 1: r = 5
        glow(g, ox + 32 + dx, oy + 32 + dy, 18 + r * 1.2, ORANGE, (0.30 + 0.03 * r) * k, 1.5)
        glow(g, ox + 32 + dx, oy + 32 + dy, 4 + r * 0.7, YEL, 0.5 * k, 1.6)
        for (lx, ly) in ((49.5, 7.5), (51, 51.5), (54, 52.5)):
            glow(g, ox + lx, oy + ly, 4, AMBER, 0.5 if (flick is None and (i + int(lx)) % 2) or flick == 0 else 0.3, 2.0)

# ============================================================ PRISM CORE (neon)
OCT_TONES = ['H', 'c', 'C', 'B', 'B', 'B', 'C', 'c']
class ReactorNeon(LComp):
    id = 'reactor_neon_mk1'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    notes = ('Lumen: a faceted crystal core in a dark navy frame with 1px cyan edge lines. The on loop rotates the light round the 8 facets (two facets per frame). '
             'Damaged: a crack runs through the crystal, one facet is chipped dark, the upper-right accumulator has lost its crystal, edge lines flicker. '
             'Disabled: the crystal is dull and fractured with a missing facet, shards on the frame, every edge line dead.')
    DMG = (0, 2)
    def crystal_map(self, tone_of):
        pass
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 61, 61, 'J', 8); rim(s, 'J', 'j', 'I')
        chamfer_fill(s, 4, 4, 55, 55, 'I', 7)
        edge(s, 4, 4, 55, 55, 7, 'c' if on else 'W')
        for (x, y) in ((12, 12), (51, 12), (12, 51), (51, 51)): s.put(x, y, 'm' if on else 'E')
        for (x, y) in ((31, 6), (32, 6), (31, 57), (32, 57), (6, 31), (6, 32), (57, 31), (57, 32)): s.put(x, y, 'N')
        # conduit arms from the frame to the crystal housing, with energy running inward
        for k, (ax, ay, w, h) in enumerate(((29, 5, 6, 10), (29, 49, 6, 10), (5, 29, 10, 6), (49, 29, 10, 6))):
            s.rect(ax, ay, w, h, 'J'); s.rect(ax + (1 if w == 6 else 0), ay + (1 if h == 6 else 0), w - (2 if w == 6 else 0), h - (2 if h == 6 else 0), 'N')
            for t in range(10):
                x = ax + 2 + (0 if w == 6 else t) if w == 6 else ax + t
                y = ay + t if w == 6 else ay + 2
                if w == 6: x = ax + 2; y = ay + t
                else: x = ax + t; y = ay + 2
                if k in (1, 3): t2 = 9 - t
                else: t2 = t
                lit = on and (t2 + 2 * i) % 5 < 2
                s.put(x, y, 'c' if lit else ('C' if on else 'W')); s.put(x + (1 if w == 6 else 0), y + (0 if w == 6 else 1), 'B' if on else 'E')
        # corner accumulators: dark socket + small crystal + magenta pin
        for (bx, by) in ((6, 6), (46, 6), (6, 46), (46, 46)):
            bev(s, bx, by, 12, 12, 'j', 'J', 'I'); s.rect(bx + 2, by + 2, 8, 8, 'N'); hollow(s, bx + 2, by + 2, 8, 8, 'B' if on else 'E')
            crystal(s, bx + 4, by + 3, ".11.\n1021\n1221\n.33.\n.33.", ['H' if on else 'M', 'c' if on else 'E', 'C' if on else 'W', 'B' if on else 'E'] if True else [])
            s.put(bx + 9, by + 2, 'm' if on and i % 2 == 0 else ('P' if on else 'E'))
        # crystal housing
        chamfer_fill(s, 14, 14, 36, 36, 'J', 11); rim(s, 'J', 'j', 'I', (14, 14, 49, 49))
        chamfer_fill(s, 16, 16, 32, 32, 'N', 10)
        edge(s, 16, 16, 32, 32, 10, 'c' if on else 'W')
        # the crystal: 8 facets round a table, light rotating by two facets per frame
        for y in range(18, 46):
            for x in range(18, 46):
                dx, dy = x + .5 - 32, y + .5 - 32
                ax, ay = abs(dx), abs(dy)
                if ax > 14 or ay > 14 or ax + ay > 20: continue
                k = octant(dx, dy)
                if on:
                    tone = OCT_TONES[(k - 2 * i) % 8]
                else:
                    tone = ('W', 'S', 'W', 'E')[k % 4]
                if ax <= 5 and ay <= 5 and ax + ay <= 8:               # table
                    tone = {'H': 'H', 'c': 'H', 'C': 'c', 'B': 'C'}[tone] if on else 'S'
                s.put(x, y, tone)
        for t in range(-14, 15):                                       # seams along the diagonals
            pass
        for (x, y) in [(32 + d, 32 + d) for d in range(-14, -5)] + [(31 + d, 32 - d - 1 + 1) for d in range(-14, -5)]: pass
        for d in range(6, 14):
            for (x, y) in ((32 + d, 32 + d), (31 - d, 31 - d), (32 + d, 31 - d), (31 - d, 32 + d)):
                if abs(x + .5 - 32) + abs(y + .5 - 32) <= 20: s.put(x, y, 'B' if on else 'E')
        for (x, y) in ((22, 22), (41, 22), (22, 41), (41, 41)): s.put(x, y, 'H' if on else 'M')
        return s
    def hurt(self, s, i):
        crack(s, [(24, 23), (27, 27), (26, 31), (30, 34), (31, 39), (35, 43)], 'H')
        for (x, y) in ((38, 22), (39, 22), (39, 23), (40, 23), (40, 24), (38, 23)): s.put(x, y, 'N')
        # upper-right accumulator has lost its crystal; a shard rests on the frame
        s.rect(48, 8, 8, 8, 'N'); hollow(s, 48, 8, 8, 8, 'E')
        s.stamp(52, 12, art("..K..\n.KcK.\nKCBBK\n.KKK."))
        for (x, y) in ((50, 10), (53, 9)): s.put(x, y, 'H' if i else 'c')
        s.put(54 + i, 7, 'H'); s.put(55, 9 - i, 'c')
        # edge line flickers out in places
        for (x, y) in ((4, 24), (4, 25), (4, 26), (24, 4), (25, 4), (59, 40), (59, 41)): s.put(x, y, 'B' if i else 'N')
        stamp_on(s, 40, 41, SCORCH_S)
        if i == 1:
            for (x, y) in ((33, 29), (34, 29), (35, 30), (34, 28), (30, 36), (31, 36)): s.put(x, y, 'B')
    def wreck(self, s):
        crack(s, [(19, 19), (23, 23), (22, 27), (27, 30), (26, 35), (31, 36), (33, 41), (38, 45)], 'M')
        crack(s, [(44, 22), (40, 26), (41, 29)], 'M')
        s.stamp(36, 22, art(".KKK.\nKNNNK\nKNKKK\n.KK..")); s.stamp(26, 32, art("KKKK\nKNNK\nKKNK"))
        for (bx, by) in ((46, 6),):
            s.rect(bx + 2, by + 2, 8, 8, 'N'); hollow(s, bx + 2, by + 2, 8, 8, 'E'); s.stamp(bx + 5, by + 6, art(".KK.\nKSMK\n.KK."))
        s.stamp(8, 43, art("KK.\nKMS\nKSK")); s.stamp(52, 36, art(".KK\nKSM\nKK."))   # shards
        stamp_on(s, 11, 43, SCORCH_S); stamp_on(s, 40, 41, SCORCH_S)
        for (x, y) in ((12, 12), (51, 12), (12, 51), (51, 51)): s.put(x, y, 'E')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        lit = [(32, 22), (42, 32), (32, 42), (22, 32)]
        glow(g, ox + 32, oy + 32, 24, CYAN, 0.28 * k, 1.5)
        glow(g, ox + 32, oy + 32, 9, (200, 250, 255), 0.5 * k, 1.8)
        cx, cy = {0: (32, 21), 1: (43, 21), 2: (43, 32), 3: (43, 43)}.get(i % 4, (32, 32))
        ang = [(33, 20), (44, 31), (31, 44), (20, 33)][i % 4]
        glow(g, ox + ang[0], oy + ang[1], 9, CYAN, 0.5 * k, 1.8)
        for (bx, by) in ((6, 6), (46, 6), (6, 46), (46, 46)):
            if flick is not None and (bx, by) == (46, 6): continue
            glow(g, ox + bx + 6, oy + by + 6, 6, CYAN, 0.35 * k, 2.0)
        for (x, y) in ((12, 12), (51, 12), (12, 51), (51, 51)): glow(g, ox + x + .5, oy + y + .5, 3.2, MAGENTA, 0.5 * k, 2.0)

ALL = [ReactorMk2, ReactorScrap, ReactorNeon]
