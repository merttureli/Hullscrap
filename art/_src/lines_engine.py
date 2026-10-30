"""Engines, 4x5 cells (64x80), hull mounts (CONTENT 4f): they straddle the wall. At rotation 0 OUTWARD IS UP.
 rows 0-1 (y 0..31)  OUTSIDE, in space: the nozzle(s) pointing up; the exhaust glow runs out ABOVE the frame
 row  2   (y 32..47) the WALL COLLAR: an armoured ring through the hull, wall art either side
 rows 3-4 (y 48..79) INSIDE, on the floor: the engine core, a power coupling, a repair hatch, core glow
Mk1 and Mk2 (Concord), Kickjet (Scrap), Ion Drive (Neon)."""
from lines_kit import *

W_, H_ = 64, 80
ORIENT = 'rotation 0: outward is UP. Nozzles at the top (outside), wall collar in the middle row, engine core at the bottom (inside, on floor)'
MOUNT = {'outside': 2, 'wall': 1, 'inside': 2}
RING10 = art("""
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
""")
TURB8 = art("""
..KKKK..
.KEEEEK.
KESSSSEK
KESDDSEK
KESDDSEK
KESSSSEK
.KEEEEK.
..KKKK..
""")

def lit_turbine(s, tx, ty, size, on, i):
    c = size // 2 - 1
    if on:
        for (x, y) in ((tx + c, ty + c), (tx + c + 1, ty + c), (tx + c, ty + c + 1), (tx + c + 1, ty + c + 1)): s.put(x, y, 'y' if (x + y + i) % 2 else 'H')
        for (dx, dy) in ((-1, -1), (2, -1), (-1, 2), (2, 2), (-1, 0), (2, 1), (0, -1), (1, 2)): s.put(tx + c + dx, ty + c + dy, 'o')
    else:
        s.put(tx + c, ty + c, 'E'); s.put(tx + c + 1, ty + c + 1, 'E')

class Mount(LComp):
    cells = (4, 5)
    mount = MOUNT
    orientation = ORIENT
    anims = [('on', 'on', 3, 8), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 8), ('disabled', 'disabled', 1, 0)]
    glow_pad = (10, 32, 10, 8)
    DMG = (0, 2)

# ============================================================ standard: Mk1 and Mk2
def bell_up(s, x0, on, i, collar=False):
    """15px bell pointing UP (mouth y1, x0..x0+14), 9px neck tube down to the wall (y31)."""
    for y0, y1, inset in ((1, 5, 0), (6, 11, 1), (12, 17, 2), (18, 23, 3)):
        wd = 15 - 2 * inset
        T = col_tones(wd)
        for y in range(y0, y1 + 1):
            for k in range(wd): s.put(x0 + inset + k, y, T[k])
    for y, inset in ((6, 1), (12, 2), (18, 3)): s.hline(x0 + inset, y, 15 - 2 * inset, 'E')
    for y in (9, 15, 21): s.put(x0 + 7, y, 'E')
    # neck tube into the wall collar
    T = col_tones(9, 'LMSSSWWE')
    for y in range(24, 32):
        for k in range(9): s.put(x0 + 3 + k, y, T[k])
    for y in (26, 30): s.hline(x0 + 2, y, 11, 'M'); s.hline(x0 + 2, y + 1, 11, 'W')
    # mouth
    s.hline(x0 + 2, 1, 11, 'D'); s.hline(x0 + 2, 2, 11, 'D')
    s.put(x0 + 1, 1, 'M'); s.put(x0 + 1, 2, 'L'); s.put(x0 + 13, 1, 'W'); s.put(x0 + 13, 2, 'M')
    if on:
        fl = [0, 1, 0][i % 3]
        s.hline(x0 + 2 + fl, 1, 11 - 2 * fl, 'o')
        s.hline(x0 + 2, 2, 11, 'o'); s.hline(x0 + 4 + fl, 2, 7 - 2 * fl, 'y'); s.put(x0 + 7, 2, 'H'); s.put(x0 + 6 + (i % 2), 2, 'H')
    else:
        s.hline(x0 + 4, 2, 7, 'E'); s.put(x0 + 7, 1, 'W')
    for (x, y) in ((x0 + 2, 8), (x0 + 12, 8)): s.put(x, y, 'L')
    if collar:                                          # amber collar ring: the Mk2 accent
        s.hline(x0 + 1, 9, 13, 'a'); s.put(x0 + 1, 9, 'y'); s.put(x0 + 2, 9, 'y'); s.hline(x0 + 1, 10, 13, 'u'); s.put(x0 + 12, 9, 'u'); s.put(x0 + 13, 9, 'u')

def collar_ring(s, cx, w=21, tone='steel'):
    """armoured ring through the wall: chamfered flange with bolts and a dark sleeve for the tube."""
    x0 = cx - w // 2
    bev(s, x0, 33, w, 14, 'L', 'M', 'S'); s.hline(x0 + 1, 45, w - 2, 'W')
    for (bx, by) in ((x0 + 2, 35), (x0 + w - 4, 35), (x0 + 2, 43), (x0 + w - 4, 43)): bolt(s, bx, by)
    s.rect(cx - 4, 36, 9, 8, 'E'); s.vline(cx - 4, 36, 8, 'S'); s.vline(cx + 4, 36, 8, 'D'); s.hline(cx - 3, 36, 7, 'W')
    s.hline(x0 + 1, 40, w - 2, 'a') if tone == 'amber' else None

class _Std(Mount):
    id = '?'
    TWIN = False
    BELLS = (11, 39)
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(W_, H_)
        # outside: the nacelle plate, the two bells and the manifold between them
        bev(s, 5, 26, 54, 6, 'M', 'S', 'W')
        for x in (8, 55): s.put(x, 28, 'L')
        s.rect(26, 13, 12, 4, 'q'); s.hline(26, 13, 12, 'Q'); s.hline(26, 16, 12, 'n')
        for fx in (28, 35): s.vline(fx, 12, 6, 'M'); s.vline(fx + 1, 12, 6, 'W')
        s.rect(30, 17, 4, 9, 'E'); s.vline(30, 17, 9, 'S')
        for x0 in self.BELLS: bell_up(s, x0, on, i, collar=self.TWIN)
        # the wall and its collars
        wall_band(s)
        for x0 in self.BELLS: collar_ring(s, x0 + 7, 21, 'amber' if self.TWIN else 'steel')
        # inside: the core
        ins = Spr(64, 32)
        self.core(ins, on, i)
        s.stamp(0, 48, ins.rows())
        return s
    def core(self, s, on, i):
        bev(s, 1, 1, 62, 30, 'M', 'S', 'W')
        for x0 in self.BELLS:                                  # tube stubs coming in through the collar
            s.rect(x0 + 3, 0, 9, 3, 'S'); s.vline(x0 + 3, 0, 3, 'L'); s.vline(x0 + 11, 0, 3, 'W'); s.hline(x0 + 2, 3, 11, 'M'); s.hline(x0 + 2, 4, 11, 'W')
        # lamp panel with display and bars
        bev(s, 3, 6, 17, 12, 'W', 'E', 'D'); s.hline(5, 7, 13, 'D')
        for k, (c, x) in enumerate((('g', 5), ('g', 8), ('a', 11), ('r', 14))):
            col = c if on and k < 3 else 'W'
            for (xx, yy) in ((x, 8), (x + 1, 8), (x, 9), (x + 1, 9)): s.put(xx, yy, col)
            if on and c == 'g': s.put(x, 8, 'H')
        recess(s, 5, 11, 13, 6, 'D', 'K')
        bars = [[3, 4, 2, 4], [4, 3, 3, 2], [2, 4, 4, 3]][i % 3] if on else [1, 1, 1, 1]
        for bx, hh in zip((7, 9, 11, 13), bars):
            for r in range(hh): s.put(bx, 15 - r, 'c' if on else 'E')
        # hatch with the turbine(s)
        if self.TWIN:
            recess(s, 21, 6, 22, 12, 'E', 'K')
            for tx in (23, 33): s.stamp(tx, 8, TURB8); lit_turbine(s, tx, 8, 8, on, i)
        else:
            recess(s, 23, 6, 18, 12, 'E', 'K')
            s.stamp(27, 7, RING10); lit_turbine(s, 27, 7, 10, on, i)
        for vy in range(8, 16, 2): s.put(24, vy, 'D'); s.put(39, vy, 'D')
        if self.TWIN:
            for vy in range(8, 16, 2): s.put(22, vy, 'D'); s.put(41, vy, 'D')
            stencil(s, 28, 4, 'L', 0)
        # feed pipes and vents (right)
        s.rect(44, 6, 17, 3, 'q'); s.hline(44, 6, 17, 'Q'); s.hline(44, 8, 17, 'n')
        for fx in (48, 54, 59): s.vline(fx, 5, 5, 'M'); s.vline(fx + 1, 5, 5, 'W')
        for vy in (11, 14): s.hline(46, vy, 13, 'D'); s.hline(46, vy + 1, 13, 'W')
        # repair hatch (lower left)
        bev(s, 5, 20, 17, 10, 'L', 'M', 'S'); hollow(s, 8, 22, 11, 6, 'W'); s.hline(10, 25, 7, 'a' if on or True else 'W'); s.put(10, 25, 'y')
        for (x, y) in ((7, 22), (19, 22), (7, 27), (19, 27)): s.put(x, y, 'L')
        # power coupling (lower centre): a socket ringed in power green, where a cable plugs in
        bev(s, 26, 20, 12, 10, 'W', 'E', 'D')
        circle(s, 32, 25, 3.6, 'D'); ring(s, 32, 25, 2.6, 4.2, 'g' if on else 'W'); s.put(31, 24, 'E'); s.put(33, 24, 'E'); s.put(32, 26, 'E')
        s.put(27, 21, 'a' if on else 'W'); s.put(36, 21, 'a' if on else 'W')
        # lower right: glowing vent grille
        bev(s, 42, 20, 19, 10, 'W', 'E', 'D')
        for vy in (22, 24, 26, 28): s.hline(44, vy, 15, 'D'); s.hline(44, vy + 1, 15, 'o' if on and (vy // 2 + i) % 3 == 0 else 'W')
        for (x, y) in ((3, 2), (60, 2), (3, 28), (60, 28)): s.put(x, y, 'L')
        s.put(23, 29, 'a' if on else 'W'); s.put(24, 29, 'a' if on else 'W')
    def hurt(self, s, i):
        x0 = self.BELLS[0]
        for (x, y) in ((x0, 1), (x0, 2), (x0 + 1, 2), (x0, 3), (x0 + 1, 3), (x0 + 1, 1)): s.erase(x, y)             # left bell lip dented in
        for (x, y) in ((x0 + 1, 4), (x0 + 2, 3), (x0 + 2, 4)): s.put(x, y, 'W')
        s.stamp(x0 - 6, 3, art("KKKK.\nKLMSK\n.KSWK\n..KKK")); s.put(x0 - 2, 6, 'S')                              # the lip, hanging off by a corner
        x1 = self.BELLS[1]
        crack(s, [(x1 + 5, 6), (x1 + 7, 10), (x1 + 5, 14), (x1 + 8, 19)], 'M')                                    # right bell cracked
        if i == 1: s.hline(x1 + 2, 1, 11, 'D'); s.hline(x1 + 5, 2, 5, 'o')                                         # it sputters
        stamp_on(s, 14, 36, SCORCH_S); stamp_on(s, 42, 38, SCORCH_S)                                                # collar scorched
        crack(s, [(48, 49), (50, 52), (49, 54)], 'M') if False else None
        # core sparks: stalled turbine, cracked hatch, red lamps, sparks at the coupling
        if self.TWIN:
            s.stamp(33, 56, TURB8); s.rect(36, 59, 2, 2, 'D'); crack(s, [(34, 57), (36, 59), (37, 61), (38, 63)], 'M')
        else:
            if i == 1: s.stamp(27, 55, RING10)
            crack(s, [(28, 56), (31, 59), (30, 61), (33, 64)], 'M')
        stamp_on(s, 36, 60, SCORCH_S); stamp_on(s, 25, 58, SCORCH_S)
        s.put(41, 55 + 2 * i, 'y'); s.put(40, 54 + i, 'H'); s.put(34 + 3 * i, 66, 'y'); s.put(31, 68 - 2 * i, 'H' if i else 'y')
        for (x, y) in ((11, 56), (14, 56)): s.rect(x, y, 2, 2, 'r')
        s.hline(45, 71, 13, 'D'); s.hline(45, 73, 13, 'D')
    def wreck(self, s):
        # a snapped nozzle: the left bell is broken off at the neck, its top half lying beside the stump; the right bell bent over
        x0, x1 = self.BELLS
        shift_rect(s, x0 - 1, x0 + 16, 0, 19, -3, 1)                                    # left nozzle bent over at the neck
        shift_rect(s, x1 - 1, x1 + 16, 0, 19, 3, 1)                                     # right nozzle bent the other way
        for xx in (x0 - 3, x1 + 3):
            s.hline(xx + 2, 19, 11, 'K'); crack(s, [(xx + 5, 21), (xx + 7, 24), (xx + 5, 28)], 'M'); crack(s, [(xx + 4, 4), (xx + 7, 8), (xx + 5, 12)], 'M')
        s.stamp(x0 - 9, 10, art("KKK.\nKLSK\n.KWK")); s.put(x1 + 18, 12, 'K')
        for x in range(29, 35):                                                       # manifold snapped
            for y in range(13, 17): s.erase(x, y)
        s.stamp(26, 12, art("KKK\nKQK\nKnK\nKKK")); s.stamp(34, 14, art("KK.\nKqK\nKKK"))
        # dead core: turbines out, hatch popped off, coupling blackened
        if self.TWIN: s.stamp(26, 56, art(".KKK.\nKDDDK\n.KKK.")); s.stamp(35, 56, art(".KKK.\nKDDDK\n.KKK."))
        else: s.stamp(29, 57, art(".KKKK.\nKDDDDK\nKDDDDK\n.KKKK."))
        s.stamp(6, 69, art("KKKKKKKK\nKDDDDDDK\nKDDKDDDK\n.KKKKKK.")); s.stamp(15, 72, art("KK.\nKSK\n.KK"))
        stamp_on(s, 27, 69, SCORCH_L); s.put(11, 56, 'r'); s.put(14, 56, 'E')
        crack(s, [(2, 58), (6, 61), (5, 65), (10, 68)], 'M')
        for (x, y) in ((31, 73), (32, 74)): s.put(x, y, 'K')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.9)
        inten, hub = [(0.8, 0.35), (1.0, 0.55), (0.9, 0.45)][i % 3]
        for n, x0 in enumerate(self.BELLS):
            if flick is not None and n == 0: k2 = 0.8
            elif flick == 1 and n == 1: k2 = 0.55
            else: k2 = 1.0
            glow_xy(g, ox + x0 + 7.5, oy + 1.5, 11, 28, ORANGE, 0.6 * inten * k * k2, 2.0)
            glow_xy(g, ox + x0 + 7.5, oy + 1.5, 6, 13, (255, 214, 90), 0.55 * inten * k * k2, 1.7)
        if self.TWIN:
            for tx in (23, 33):
                if flick == 1 and tx == 33: continue
                glow(g, ox + tx + 4, oy + 60, 7, ORANGE, hub * 1.1 * k, 2.0)
        else:
            glow(g, ox + 32, oy + 60, 9, ORANGE, hub * k, 2.0)
        for (lx, ly, rgb) in ((6, 56.5, GREEN), (9, 56.5, GREEN), (12, 56.5, AMBER)):
            if flick is not None and lx > 7: rgb = RED
            glow(g, ox + lx + 1, oy + ly + 1, 4.5, rgb, 0.55 * k, 2.0)
        glow(g, ox + 32, oy + 73, 6, GREEN, 0.4 * k, 2.0)                                  # the power coupling
        for vy in (70, 72, 74, 76):
            if (vy // 2 + i) % 3 == 0 and flick is None: glow(g, ox + 51, oy + vy + 1, 7, ORANGE, 0.3, 2.0, sx=1.8)

class _Mk1(_Std):
    id = 'engine_mk1'
    notes = ('Concord Mk1, a hull mount (outward is up): twin bells outside, an armoured wall collar, and inside a core with lamp panel and bars, a hatch with one turbine, feed pipes, a repair hatch, a green-ringed power coupling and a glowing vent grille. '
             'Damaged: the left bell lip is dented in and hanging, the right bell cracked and sputtering, the collar scorched, the turbine stalls, hatch cracked and sparking, lamps red. '
             'Disabled: the left nozzle snapped off at the neck, the right bent over, manifold snapped, wall collar cracked, the core dead with its repair hatch popped.')
class _Mk2(_Std):
    id = 'engine_mk2'; TWIN = True
    notes = ('Concord Mk2, a hull mount (outward is up): Mk1 plus an amber collar ring on each bell and each wall collar, and a wider hatch with two lit turbines, registry stencil. '
             'Damaged: the left bell lip is dented in and hanging, the right bell cracked and sputtering, the second turbine stalled and cracked, sparks at the hatch and coupling, lamps red. '
             'Disabled: the left nozzle snapped off at the neck, the right bent over, wall collar cracked, both turbines dead, repair hatch popped.')

# ============================================================ KICKJET (scrap)
def chamfer_tones_h(s, x, y, w, h, tones):
    """vertical cylinder: tone per column, chamfered ends."""
    for k in range(w):
        inset = max(0, 3 - k, 3 - (w - 1 - k))
        s.vline(x + k, y + inset, h - 2 * inset, tones[k])

class _Scrap(Mount):
    id = 'engine_scrap_mk1'
    glow_pad = (10, 34, 10, 8)
    anims = [('on', 'on', 3, 8), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 2)
    notes = ('Scrapper Clans "Kickjet", a hull mount (outward is up): ONE oversized dented bell outside with a rust patch, a rusty fuel tank strapped on beside it, a patched mismatched wall collar with hazard tape, '
             'and inside a squat motor block with a taped control box, warm lamps, a patched repair hatch and a taped power coupling. The jet flickers unevenly. '
             'Damaged: the lower strap snapped and the tank sags and weeps fuel, the bell patch lost a bolt and the dent is on fire, the core sparks. '
             'Disabled: the bell broken off its neck and lying beside it, the tank slid off and split, the collar cracked, the core dead.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(W_, H_)
        # outside: bracket + oversized bell (centre x=27, mouth 30 wide at the top) + strapped tank
        plate(s, 2, 14, 9, 17, 'u'); hazard(s, 2, 22, 9, 3); bolts(s, [(3, 28)])
        for y0, y1, inset in ((1, 6, 0), (7, 12, 3), (13, 18, 6), (19, 24, 9)):
            wd = 30 - 2 * inset
            T = col_tones(wd, 'LLLMMMMSSSSSSSWWWWWEEE')
            for y in range(y0, y1 + 1):
                for k in range(wd): s.put(12 + inset + k, y, T[k])
        for y, inset in ((7, 3), (13, 6), (19, 9)): s.hline(12 + inset, y, 30 - 2 * inset, 'E')
        for y in (10, 16): 
            for x in (22, 32): s.put(x, y, 'E')
        for y in range(25, 32):                                       # neck plate
            s.hline(21, y, 12, 'S'); s.put(21, y, 'M'); s.put(32, y, 'W')
        s.hline(21, 28, 12, 'E'); weld(s, 21, 26, 12)
        s.hline(14, 1, 26, 'D'); s.hline(14, 2, 26, 'D')
        s.put(13, 1, 'M'); s.put(13, 2, 'L'); s.put(40, 1, 'W'); s.put(40, 2, 'M')
        if on:
            lo, hi = [(17, 37), (20, 34), (15, 39)][i]                        # the jet is ragged and unsteady
            s.hline(lo, 1, hi - lo, 'o'); s.hline(lo + 1, 2, hi - lo - 2, 'o'); s.hline(lo + 4, 2, hi - lo - 8, 'y')
            s.put(26, 2, 'H'); s.put(27, 2, 'H'); s.put(lo + 3 + 5 * i, 1, 'D'); s.put(hi - 6 - 3 * i, 1, 'D')
        else: s.hline(19, 2, 16, 'E')
        bolts(s, [(14, 4), (38, 4), (19, 9), (33, 9), (24, 15)])
        weld(s, 14, 5, 6, False) if False else None
        # dent bites the left side, rust patch on the right
        for (x, y) in ((15, 8), (15, 9), (16, 9), (15, 10), (16, 10), (17, 10)): s.erase(x, y)
        for (x, y) in ((16, 8), (17, 9), (18, 10), (17, 11), (18, 11), (19, 11)): s.put(x, y, 'D')
        for (x, y) in ((17, 8), (18, 9), (19, 10)): s.put(x, y, 'W')
        s.rect(31, 3, 9, 6, 'u'); s.hline(31, 3, 9, 'Q'); s.vline(31, 3, 6, 'Q'); s.hline(31, 8, 9, 'n'); s.vline(39, 3, 6, 'n')
        bolts(s, [(32, 4), (36, 4)]); s.put(35, 7, 'q'); s.put(36, 6, 'q')
        # tank: vertical, strapped on, off-colour rust with grey heads
        chamfer_tones_h(s, 45, 3, 13, 28, 'QQuuuuqqqnnnn')
        for y in list(range(3, 7)) + list(range(27, 31)):
            for x in range(45, 58):
                if s.get(x, y) != '.': s.put(x, y, 'M' if x < 49 else ('S' if x < 54 else 'W'))
        s.hline(46, 7, 11, 'E'); s.hline(46, 26, 11, 'E')
        for sy in (11, 21):
            s.rect(44, sy, 15, 3, 'E'); s.hline(44, sy, 15, 'S'); s.put(45, sy + 1, 'L'); s.put(56, sy + 1, 'L')
        circle(s, 51, 16, 1.8, 'E'); circle(s, 51, 16, 1.1, 'M'); s.put(50, 15, 'L'); s.put(52, 17, 'a')
        stamp_on(s, 54, 13, art("n.\nnn\n.n\n.n")); stamp_on(s, 47, 18, art("u.\n.u"))
        line(s, 44, 17, 41, 17, 'q'); s.put(42, 16, 'Q')
        # the wall + a mismatched, patched collar
        wall_band(s)
        plate(s, 12, 33, 16, 14, 'S'); plate(s, 27, 33, 16, 14, 'u')
        s.rect(21, 37, 12, 6, 'E'); s.vline(21, 37, 6, 'S'); s.vline(32, 37, 6, 'D')
        hazard(s, 12, 44, 16, 3); weld(s, 28, 35, 14); stamp_on(s, 36, 40, art("n.\nn.\n.n"))
        plate(s, 45, 34, 13, 12, 'M', False); bolts(s, [(46, 35), (54, 35)])        # a spare plate welded to the wall
        # inside: the core
        ins = Spr(64, 32)
        self.core(ins, on, i)
        s.stamp(0, 48, ins.rows())
        return s
    def core(self, s, on, i):
        plate(s, 14, 1, 14, 18, 'M', False); plate(s, 27, 1, 16, 18, 'S', False); weld(s, 27, 3, 15, True)
        bolts(s, [(15, 2), (40, 2), (15, 14), (40, 14)])
        s.rect(21, 0, 12, 3, 'S'); s.vline(21, 0, 3, 'M'); s.vline(32, 0, 3, 'W')
        for y in range(5, 12, 2): s.hline(17, y, 8, 'D')
        s.hline(17, 4, 8, 'E')
        s.rect(31, 7, 9, 5, 'D'); s.hline(31, 7, 9, 'K')
        for (x, y) in ((32, 8), (35, 8), (38, 8), (32, 9), (35, 9), (38, 9)): s.put(x, y, 'a' if on and (x + i) % 2 == 0 else 'n')
        # control box on the left: taped, warm lamps, loose wire
        bev(s, 1, 2, 11, 21, 'W', 'E', 'D'); hazard(s, 1, 5, 11, 3)
        for k, y in enumerate((11, 15, 19)): s.rect(5, y, 2, 2, 'a' if on and (k + i) % 3 else ('o' if on else 'W'))
        for (x, y) in ((2, 3), (9, 3), (2, 21), (9, 21)): s.put(x, y, 'L')
        line(s, 11, 20, 12, 24, 'r'); s.put(12, 25, 'a' if on and i == 1 else 'r')
        # repair hatch: a patched rust plate with a hinge
        bev(s, 14, 21, 15, 9, 'Q', 'u', 'n'); bolts(s, [(15, 22), (25, 22)]); s.hline(18, 25, 7, 'D'); s.put(18, 26, 'E'); s.put(24, 26, 'L'); s.hline(18, 27, 7, 'n')
        # power coupling: a taped socket, green ring gone dull and warm
        bev(s, 31, 21, 13, 9, 'W', 'E', 'D'); circle(s, 37, 25.5, 3.2, 'D'); ring(s, 37, 25.5, 2.4, 3.8, 'g' if on and i % 3 != 1 else 'W')
        hazard(s, 31, 28, 13, 2); s.put(33, 22, 'a' if on else 'W')
        # glowing grille, lower right + a lamp plate
        bev(s, 46, 2, 15, 10, 'M', 'S', 'W'); bolts(s, [(48, 3), (57, 3)]); s.hline(49, 7, 9, 'D'); s.hline(49, 9, 9, 'D')
        bev(s, 46, 14, 15, 15, 'W', 'E', 'D')
        for vy in (16, 19, 22, 25): s.hline(48, vy, 11, 'D'); s.hline(48, vy + 1, 11, 'o' if on and (vy // 3 + i) % 3 == 0 else 'W')
    def hurt(self, s, i):
        # lower strap snapped: the tank sags away, gap, strap end hanging; fuel weeps; patch lost a bolt; the dent is on fire
        s.rect(44, 21, 15, 3, '.'); s.rect(44, 21, 3, 3, 'E'); s.stamp(47, 22, art("KKK\nKEK\nKSK\nKLK\n.K.")); s.put(47, 26, 'L')
        s.vline(44, 7, 18, 'K'); s.vline(43, 9, 14, 'D')
        s.put(52, 19 + i, 'a'); s.put(52, 22 + i, 'a'); s.vline(47, 27 + i, 3, 'a')
        s.put(36, 4, 'K'); s.put(37, 4, 'D')
        fl = [[(17, 9), (18, 8), (17, 7)], [(18, 9), (18, 6), (19, 7)]][i]
        for (x, y) in fl: s.put(x, y, 'o')
        s.put(18, 9, 'y'); s.put(17, 10, 'o')
        crack(s, [(24, 13), (26, 17), (25, 21)], 'M')
        stamp_on(s, 14, 36, SCORCH_S); stamp_on(s, 36, 38, SCORCH_S)
        s.put(32 + 3 * i, 66, 'y'); s.put(38, 65 - i, 'H'); s.put(12, 72, 'y' if i else 'H')
        for (x, y) in ((17, 60), (20, 60)): s.put(x, y, 'D')
    def wreck(self, s):
        # the bell is broken off at the neck and lies beside it; the tank slid off its straps and split
        shift_rect(s, 11, 43, 0, 15, -5, 1)                                            # the bell is bent over to one side at the neck
        s.hline(20, 15, 14, 'K'); crack(s, [(27, 17), (29, 21), (26, 24)], 'M'); s.stamp(26, 10, art("KKK.\nKDDK\n.KDK"))
        shift_rect(s, 44, 59, 3, 31, 0, 3)                                             # the tank slid down on its straps and hangs crooked
        crack(s, [(46, 14), (49, 17), (53, 16), (56, 20)], 'S'); s.vline(47, 25, 4, 'a'); s.stamp(6, 8, art("KKK.\nKSMK\n.KSK"))
        # dead core: lamps out, grille dark, hatch burst open, socket scorched
        s.stamp(15, 69, art("KKKKKKKKKKKK\nKDDDDDKDDDDK\nKDDKDDDDDKDK\n.KKKKKKKKKK.")); s.stamp(26, 74, art("KK.\nKSK\n.KK"))
        stamp_on(s, 32, 70, SCORCH_L); s.put(12, 73, 'r'); crack(s, [(3, 62), (7, 66), (6, 70)], 'M')
        for y in range(60, 66): s.hline(32, y, 9, 'D') if y == 60 else None
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        inten = [0.8, 1.0, 0.85][i % 3]
        glow_xy(g, ox + 27, oy + 1.5, 19, 30, ORANGE, 0.62 * inten * k, 2.0)
        glow_xy(g, ox + 27, oy + 1.5, 10, 14, (255, 214, 90), 0.5 * inten * k, 1.7)
        for y in (59.5, 63.5, 67.5): glow(g, ox + 6, oy + y + .5, 4, AMBER, 0.5 * k, 2.0)
        for (x, y) in ((33.5, 56.5), (36.5, 56.5), (39.5, 56.5)): glow(g, ox + x, oy + y, 4, ORANGE, 0.4 * k, 2.0)
        glow(g, ox + 37, oy + 73.5, 5, GREEN, 0.3 * k, 2.0)
        for vy in (64, 67, 70, 73):
            if (vy // 3 + i) % 3 == 0: glow(g, ox + 53.5, oy + vy + 1, 7, ORANGE, 0.3 * k, 2.0, sx=1.5)
        if flick is not None: glow(g, ox + 18, oy + 8, 5.5, ORANGE, 0.55 if flick else 0.4, 1.8)

# ============================================================ ION DRIVE (neon)
class _Neon(Mount):
    id = 'engine_neon_mk1'
    glow_pad = (12, 36, 12, 8)
    DMG = (0, 2)
    RINGS = [(16, 17, 46), (9, 10, 53), (2, 6, 57)]     # y, x0, x1: ion rings, narrow at the wall, wide at the nozzle (top)
    notes = ('Lumen "Ion Drive", a hull mount (outward is up): a stack of three ion rings outside, widest at the nozzle on top, the light running up them (cyan lit core, magenta pins) and a cyan glow with a magenta halo streaming out above; '
             'a navy collar with cyan edge lines; inside a slim navy core with a lens crystal accumulator, a display, a repair hatch and a cyan-ringed power coupling. '
             'Damaged: the middle ring has slipped out of line and cracked, arcs jump the gap, the lens crystal is cracked and flickers. '
             'Disabled: the top ring snapped half off and hanging, the collar cracked, the lens shattered, every line dead.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(W_, H_)
        # outside: spine up from the wall, outriggers, three ion rings
        navy_panel(s, 25, 10, 14, 22)
        s.vline(27, 11, 20, 'c' if on else 'W'); s.vline(36, 11, 20, 'c' if on else 'W')
        s.rect(29, 11, 6, 20, 'N'); s.vline(29, 11, 20, 'B' if on else 'E'); s.vline(34, 11, 20, 'B' if on else 'E')
        for y in range(11, 31):
            if on and (y + 3 * (i % 3)) % 6 < 2: s.put(31, y, 'c'); s.put(32, y, 'c')
            elif on: s.put(31, y, 'C'); s.put(32, y, 'B')
            else: s.put(31, y, 'E'); s.put(32, y, 'E')
        for (x0, x1) in ((6, 15), (48, 57)):                           # outriggers
            navy_panel(s, x0, 19, 10, 13); s.vline(x0 + 2, 21, 9, 'c' if on else 'W'); s.vline(x0 + 7, 21, 9, 'c' if on else 'W') if False else None
            s.rect(x0 + 3, 21, 4, 9, 'N'); s.put(x0 + 4, 23, 'm' if on else 'E'); s.put(x0 + 5, 26, 'm' if on else 'E')
        for k, (y, x0, x1) in enumerate(self.RINGS):
            lit = on and k == (2 - i) % 3                              # the light runs up toward the nozzle
            w = x1 - x0 + 1
            s.rect(x0, y, w, 4, 'J'); s.hline(x0, y, w, 'j'); s.hline(x0, y + 3, w, 'I')
            s.hline(x0 + 1, y + 1, w - 2, 'N'); s.hline(x0 + 1, y + 2, w - 2, 'N')
            for x in range(x0 + 2, x1 - 1):
                s.put(x, y + 1, ('H' if (x + 1) % 4 == 0 else 'c') if lit else ('C' if on else 'E'))
                s.put(x, y + 2, 'C' if lit else ('B' if on else 'E'))
            s.put(x0, y + 1, 'c' if on else 'W'); s.put(x0, y + 2, 'm' if on else 'E'); s.put(x1, y + 1, 'c' if on else 'W'); s.put(x1, y + 2, 'm' if on else 'E')
            s.put(x0, y, 'L' if on else 'S'); s.put(x1, y + 3, 'W')
        for (x, y) in ((13, 6), (50, 6)): pass
        for x in (24, 38):                                              # struts joining the rings
            for (ya, yb) in ((6, 9), (13, 16)): s.rect(x, ya + 1 if ya == 6 else ya, 2, yb - ya if ya == 6 else yb - ya, 'J')
        s.hline(25, 10, 14, 'j')
        # wall + navy collar with cyan edge lines
        wall_band(s)
        navy_panel(s, 18, 33, 28, 14); edge(s, 18, 33, 28, 14, 1, 'c' if on else 'W')
        s.rect(26, 36, 12, 8, 'N'); hollow(s, 26, 36, 12, 8, 'B' if on else 'E'); s.rect(29, 37, 6, 6, 'I')
        for (x, y) in ((20, 35), (43, 35), (20, 44), (43, 44)): s.put(x, y, 'm' if on else 'E')
        ins = Spr(64, 32)
        self.core(ins, on, i)
        s.stamp(0, 48, ins.rows())
        return s
    def core(self, s, on, i):
        navy_panel(s, 1, 1, 62, 30)
        s.rect(26, 0, 12, 3, 'J'); s.vline(26, 0, 3, 'j'); s.vline(37, 0, 3, 'I')
        # lens crystal accumulator, centre
        chamfer_fill(s, 22, 4, 20, 16, 'N', 3); edge(s, 22, 4, 20, 16, 3, 'c' if on else 'W')
        crystal(s, 27, 6, "..11..\n.1221.\n123321\n123441\n123441\n123321\n.1221.\n..11..", ['K', 'B' if on else 'E', 'C' if on else 'W', 'c' if on else 'S', 'H' if on else 'M'])
        if on: s.put(29 + i % 2, 9, 'H')
        for (x, y) in ((24, 5), (39, 5), (24, 18), (39, 18)): s.put(x, y, 'm' if on else 'E')
        # display, left
        navy_panel(s, 3, 4, 16, 14); s.rect(5, 6, 12, 8, 'N'); hollow(s, 5, 6, 12, 8, 'B' if on else 'E')
        for k, bh in enumerate([[3, 5, 2, 4], [4, 2, 5, 3], [2, 4, 3, 5]][i % 3] if on else [1, 1, 1, 1]):
            for r in range(bh): s.put(7 + 2 * k, 13 - r, 'c' if on else 'E')
        for k in range(3): s.put(6 + 4 * k, 15, 'm' if on and k == i % 3 else ('P' if on else 'E'))
        # lines of light along the core (right), conduit
        navy_panel(s, 45, 4, 16, 14)
        for k in range(4): s.hline(47, 6 + 3 * k, 12, 'B' if on else 'E'); s.hline(47 + (k * 3 + 2 * i) % 8, 6 + 3 * k, 3, 'c' if on else 'E')
        # repair hatch: navy plate with a cyan outline and a small handle
        navy_panel(s, 4, 21, 16, 9); hollow(s, 6, 23, 12, 5, 'c' if on else 'W'); s.hline(10, 25, 4, 'm' if on else 'E')
        # power coupling: a cyan-ringed port with a magenta pin
        navy_panel(s, 26, 22, 12, 8); circle(s, 32, 26, 3.0, 'N'); ring(s, 32, 26, 2.0, 3.4, 'c' if on else 'W'); s.put(32, 26, 'm' if on else 'E'); s.put(31, 25, 'E') if False else None
        # lower right: light vents
        navy_panel(s, 44, 21, 17, 9)
        for k in range(4): s.hline(46, 23 + 2 * (k // 2) + (k % 2) * 0, 13, 'N') if False else None
        for vy in (23, 26): s.hline(46, vy, 13, 'N'); s.hline(46, vy + 1, 13, 'B' if on else 'E')
        if on: s.hline(47 + (i * 4) % 9, 24, 3, 'c'); s.hline(55 - (i * 4) % 9, 27, 3, 'c')
    def hurt(self, s, i):
        y, x0, x1 = self.RINGS[1]
        s.rect(x0 - 2, y - 1, x1 - x0 + 5, 6, '.')
        xx0 = x0 + 3; xx1 = x1 - 2
        s.rect(xx0, y + 1, xx1 - xx0 + 1, 4, 'J'); s.hline(xx0, y + 1, xx1 - xx0 + 1, 'j'); s.hline(xx0 + 1, y + 2, xx1 - xx0 - 1, 'N'); s.hline(xx0 + 1, y + 3, xx1 - xx0 - 1, 'N')
        for x in range(xx0 + 3, xx1 - 2): s.put(x, y + 2, 'B'); s.put(x, y + 3, 'N')
        crack(s, [(xx0 + 4, y + 1), (xx0 + 8, y + 3), (xx0 + 12, y + 2), (xx0 + 15, y + 4)], 'M')
        for (x, yy) in ((xx0 - 1, y + 2), (xx1 + 2, y + 3)): s.put(x, yy, 'm' if i else 'H')
        for (x, yy) in ((xx0 + 6 + 10 * i, y - 1), (xx0 + 7 + 10 * i, y - 2), (xx0 + 8 + 10 * i, y - 2)): s.put(x, yy, 'm' if not i else 'c')
        s.stamp(46, y - 3, art("KKKK\nK..K"))
        crack(s, [(27, 54), (29, 56), (28, 58), (31, 60), (32, 63)], 'H')                                       # lens cracked
        for (x, yy) in ((31, 55), (32, 55), (32, 56)): s.put(x, yy, 'N')
        if i == 1:
            for (x, yy) in ((28, 57), (29, 57), (28, 58)): s.put(x, yy, 'B')
        for (x, yy) in ((27, 33), (27, 34), (36, 40), (36, 41)): s.put(x, yy, 'B' if i else 'N')
        stamp_on(s, 12, 66, SCORCH_S); stamp_on(s, 46, 38, SCORCH_S)
        for (x, yy) in ((30, 70), (33 + 3 * i, 72)): s.put(x, yy, 'H' if i else 'm')
    def wreck(self, s):
        shift_rect(s, 3, 60, 1, 7, -6, 2)                                              # the top ring is bent down on one side
        y0, a0, b0 = self.RINGS[2]; crack(s, [(14, y0 + 3), (17, y0 + 4), (20, y0 + 6)], 'M'); s.stamp(40, y0 + 4, art("KKK.\nKJIK\n.KKK"))
        shift_rect(s, 8, 56, 9, 14, 2, 0); s.stamp(44, 16, art("KK.\nKSM\n.KK"))
        y2, a2, b2 = self.RINGS[1]; crack(s, [(a2 + 12, y2 + 2), (a2 + 14, y2 + 5)], 'M')
        s.stamp(26, 55, art("KKKKKKK\nKNNNNNK\nKNKKKKK\n.KNNNK.")); s.stamp(31, 60, art("KK.KK\nKNKNK\n.KKK."))
        for (x, yy) in ((20, 35), (43, 35), (20, 44), (43, 44), (24, 52), (39, 52), (24, 65), (39, 65)): s.put(x, yy, 'E')
        s.stamp(8, 73, art("KK.\nKSM\n.KK")); stamp_on(s, 10, 66, SCORCH_S); stamp_on(s, 48, 66, SCORCH_L)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        for kk, (y, x0, x1) in enumerate(self.RINGS):
            lit = kk == (2 - i) % 3
            if flick is not None and kk == 1: continue
            glow(g, ox + (x0 + x1) / 2 + .5, oy + y + 2.5, 16 if lit else 8, CYAN, (0.45 if lit else 0.18) * k, 2.0, sx=1.6)
        glow_xy(g, ox + 32, oy + 2, 26, 30, MAGENTA, 0.34 * k * (0.9 + 0.05 * i), 1.9)
        glow_xy(g, ox + 32, oy + 2, 15, 24, CYAN, 0.5 * k, 2.0)
        glow_xy(g, ox + 32, oy + 4, 7, 10, (210, 250, 255), 0.55 * k, 1.8)
        glow(g, ox + 32, oy + 59, 9, CYAN, 0.45 * k, 2.0)
        glow(g, ox + 32, oy + 74, 5, CYAN, 0.35 * k, 2.0)
        for (x, y) in ((24, 53), (39, 53), (24, 66), (39, 66)): glow(g, ox + x + .5, oy + y + .5, 3, MAGENTA, 0.45 * k, 2.0)


# ============================================================ the two halves (owner: engines are split so hulls can be any thickness)
def _crop(g, x0, y0, w, h):
    n = Rgba(w, h)
    for y in range(h):
        if 0 <= y0 + y < g.h:
            for x in range(w): n.p[y][x] = list(g.p[y0 + y][x])
    return n

FLANGE = {'std': ('L', 'M', 'S'), 'scrap': None, 'neon': None}
def flange(s, y, h, kind):
    """a 4-5px plate where the half meets the wall."""
    if kind == 'std':
        bev(s, 1, y, 62, h, 'L', 'M', 'S')
        for x in (4, 30, 58): s.put(x, y + h // 2, 'L')
    elif kind == 'scrap':
        s.rect(1, y, 31, h, 'S'); s.hline(1, y, 31, 'M'); s.rect(32, y, 31, h, 'u'); s.hline(32, y, 31, 'Q'); s.hline(1, y + h - 1, 62, 'n')
        bolts(s, [(4, y + 1), (28, y + 1), (36, y + 1), (58, y + 1)])
        s.put(32, y, 'K'); s.vline(32, y, h, 'K')
    else:
        s.rect(1, y, 62, h, 'J'); s.hline(1, y, 62, 'j'); s.hline(1, y + h - 1, 62, 'I'); s.hline(3, y + h // 2, 58, 'c')
        for x in (6, 31, 57): s.put(x, y + h // 2, 'm')

class _Half(LComp):
    def __init__(self, full, part):
        self.full, self.part = full, part
        self.kind = 'std' if isinstance(full, _Std) else 'scrap' if isinstance(full, _Scrap) else 'neon'
        self.id = full.id + ('_out' if part == 'out' else '')
        self.cells = (4, 2); self.DMG = full.DMG
        self.anims = list(full.anims)
        self.orientation = ORIENT_OUT if part == 'out' else ORIENT_IN
        self.notes = full.notes + (' THIS FILE: the OUTSIDE half (nozzles, in space against the outer wall face; its bottom 4px are the flange onto the wall). It is never destroyed, only disabled (bent, dead, fixable).' if part == 'out'
                                    else ' THIS FILE: the INSIDE half (core, power coupling, repair hatch; its top 4px overhang the inner wall face as a flange).')
        if part == 'out':
            self.glow_pad = (10, full.glow_pad[1], 10, 4); self._h = 32; self.offset = None
            self.anchors = {'exhaust_left': (13, 1), 'exhaust_right': (50, 1)} if self.kind == 'std' else {'exhaust': (27 if self.kind == 'scrap' else 32, 1)}
        else:
            self.glow_pad = (10, 6, 10, 8); self._h = 36; self.offset = (0, -4)
            self.anchors = {'power_coupling': {'std': (32, 29), 'scrap': (37, 29), 'neon': (32, 30)}[self.kind], 'repair_hatch': {'std': (13, 29), 'scrap': (21, 29), 'neon': (12, 29)}[self.kind]}
        self.extra = {'mount': {'part': 'outside' if part == 'out' else 'inside', 'faces': 'rotation 0: outward is up'}}
    @property
    def h(self): return self._h
    def build(self, state, i):
        f = self.full
        if state == 'damaged': s = f.interior('on', f.DMG[i]).copy(); f.hurt(s, i)
        elif state == 'disabled':
            s = f.interior('off', 0).copy(); dm = dict(DARK); dm.update(f.dark or {}); s = s.sub(dm); f.wreck(s)
        else: s = f.interior(state, i).copy()
        if self.part == 'out':
            o = Spr(64, 32)
            for y in range(32):
                for x in range(64): o.g[y][x] = s.g[y][x]
            flange(o, 28, 4, self.kind)
            return o
        o = Spr(64, 36)
        for y in range(32):
            for x in range(64): o.g[y + 4][x] = s.g[48 + y][x]
        flange(o, 0, 5, self.kind)
        return o
    def frame(self, state, i):
        s = self.build(state, i); outline_all(s); return drop_shadow(s)
    def glow_frame(self, state, i):
        g = self.full.glow_frame(state, i)
        l, t, r, b = self.full.glow_pad
        if self.part == 'out': return _crop(g, 0, 0, 64 + 20, t + 32 + 4)
        return _crop(g, 0, t + 44 - 6, 64 + 20, 6 + 36 + 8)

ORIENT_OUT = 'outside half: rotation 0, outward is UP: nozzles point up into space; the exhaust glow overhangs above the frame (see glow.offset); the bottom 4px are the flange onto the outer wall face'
ORIENT_IN = 'inside half: rotation 0, outward is UP: the core sits on the floor with its top 4px overhanging the inner wall face (see offset); cable plugs into the power coupling'
FULLS = [_Mk1(), _Mk2(), _Scrap(), _Neon()]
ALL = []
for _f in FULLS: ALL += [_Half(_f, 'core'), _Half(_f, 'out')]
