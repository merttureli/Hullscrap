"""Wheezer O2 (Scrap)."""
from lines_kit import *
from comp_new import DISC, fan_blades, lamp
from compose import rotate

# ============================================================ WHEEZER O2 (scrap) 2x4
_BLADES = {}
def blades(missing=False, ang=0.0):
    key = (missing, ang)
    if key not in _BLADES:
        b = fan_blades()
        for y in range(0, 5):                                  # the top blade is bent: its tip is gone
            for x in range(8, 14): b.erase(x, y)
        if missing:                                            # ... or the opposite blade is gone altogether
            for y in range(12, 21):
                for x in range(7, 14): b.erase(x, y)
        _BLADES[key] = rotate(b, ang, 10, 10) if ang else b
    return _BLADES[key]

def draw_fan(s, ang, off, on, missing=False, dead=False):
    recess(s, 4, 4, 24, 24, 'E', 'K')
    disc = Spr(21, 21)
    for y, (x0, x1) in enumerate(DISC): disc.hline(x0, y, x1 - x0 + 1, 'D')
    disc.stamp(0, 0, blades(missing, ang).rows())
    disc.stamp(8, 8, art(".WWW.\nWLLWE\nWLEWE\nWWWWE\n.EEE."))
    s.stamp(6 + off[0], 6 + off[1], disc.rows())
    if dead:
        for (x, y) in ((6, 6), (7, 7)): pass
    for (x, y) in ((5, 5), (26, 5), (5, 26), (26, 26)): s.put(x, y, 'L')
    # bent guard bar across the well, torn off at one end
    for (a, b) in (((5, 14), (11, 14)), ((11, 14), (14, 17)), ((14, 17), (20, 17)), ((20, 17), (23, 14)), ((23, 14), (27, 14))): line(s, a[0], a[1], b[0], b[1], 'S')
    for (x, y) in ((6, 15), (7, 15), (12, 15), (13, 16), (21, 15), (22, 15)): s.put(x, y, 'D')
    s.stamp(4, 8, art("uu.\nu..")); s.stamp(23, 22, art(".u\nuu"))

class OxygenScrap(LComp):
    id = 'oxygen_scrap_mk1'; cells = (2, 4)
    anims = [('on', 'on', 4, 10), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    notes = ('Scrapper Clans "Wheezer": a wobbling fan (off-centre, one blade bent) behind a bent guard bar, a rust-patched duct with a hazard-taped joint that drips and wheezes a puff on the loop, one grey and one rusty tank with a faded green O2 band, amber lamps. '
             'Damaged: a blade has snapped off and the fan staggers, the duct patch has popped a bolt and gushes, lamps flicker red, a spark at the tank valve. '
             'Disabled: the fan is stopped with a blade hanging, the duct has pulled apart, the rusty tank has burst a seam, lamps dead.')
    DMG = (1, 3)
    WOB = [(0, 0), (1, 0), (0, 1), (-1, 0)]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 64)
        plate(s, 1, 1, 30, 34, 'M', False); plate(s, 1, 34, 30, 28, 'S', False)
        weld(s, 3, 33, 26)
        bolts(s, [(2, 2), (28, 2), (2, 36), (28, 36), (2, 58), (28, 58)])
        draw_fan(s, [0, 22.5, 45, 67.5][i] if on else 12, self.WOB[i] if on else (0, 0), on)
        for k, (x, c) in enumerate(((6, 'a'), (11, 'a'), (16, 'o'))): lamp(s, x, 36, c, on and (k != 2 or i % 2 == 0))
        for x in range(21, 28, 2): s.vline(x, 36, 3, 'D')
        # left tank: tidy grey bottle with a faded green O2 band; right tank: rusty, shorter, taped neck
        tx = 3
        for k in range(10): s.vline(tx + k, 42, 18, 'LMMSSSSWWE'[k])
        for k in range(2, 8): s.put(tx + k, 41, 'LMMSSSSWWE'[k]); s.put(tx + k, 60, 'LMMSSSSWWE'[k])
        s.rect(tx + 3, 39, 4, 2, 'E'); s.put(tx + 4, 39, 'W')
        s.hline(tx, 49, 10, 'g'); s.hline(tx, 50, 10, 'g'); s.put(tx + 1, 49, 'H'); s.hline(tx + 5, 50, 5, 'u')
        tx = 19
        for k in range(10): s.vline(tx + k, 44, 14, 'QQuuuuqqnn'[k])
        for k in range(2, 8): s.put(tx + k, 43, 'QQuuuuqqnn'[k]); s.put(tx + k, 58, 'QQuuuuqqnn'[k])
        hazard(s, tx + 1, 40, 8, 3); s.rect(tx + 3, 38, 4, 2, 'E')
        s.hline(tx, 50, 10, 'n'); s.put(tx + 3, 47, 'L'); s.put(tx + 6, 53, 'S')
        # the duct: ribbed, a rust patch over a split, taped joint
        s.rect(14, 38, 4, 21, 'S'); s.vline(14, 38, 21, 'M'); s.vline(17, 38, 21, 'W')
        for y in range(39, 58, 3): s.hline(14, y, 4, 'E'); s.hline(14, y + 1, 4, 'L') if False else None
        s.rect(13, 45, 6, 7, 'u'); s.hline(13, 45, 6, 'Q'); s.vline(13, 45, 7, 'Q'); s.hline(13, 51, 6, 'n'); s.vline(18, 45, 7, 'n')
        bolts(s, [(14, 46)]); s.put(17, 47, 'L'); s.put(14, 50, 'L'); s.put(17, 50, 'S')
        hazard(s, 13, 54, 6, 3)
        s.rect(13, 59, 6, 2, 'E'); s.hline(13, 59, 6, 'S')
        # drip + wheeze puff
        if on:
            dy = [52, 55, 58, 60][i]
            s.put(12, dy, 'H' if i < 3 else 'M'); s.put(12, dy - 1, 'L')
            if i % 2: s.put(19, 44, 'L'); s.put(20, 43, 'M'); s.put(20, 45, 'M')
        s.hline(8, 61, 6, 'D'); s.put(9, 61, 'E')
        stamp_on(s, 24, 14, art("u.\n.u\n.u")); stamp_on(s, 2, 60, art("u.\nuu"))
        s.put(26, 61, 'a'); s.put(25, 61, 'a'); s.put(23, 61, 'a')            # clan tally marks
        return s
    def hurt(self, s, i):
        draw_fan(s, 20 + 14 * i, (1, -1) if i else (-1, 1), True, missing=True)       # a blade snapped off; it staggers
        s.stamp(23, 9, art("KK.\nKLK\n.KK")); s.put(24, 11, 'S')                          # the blade lodged against the well
        # duct patch popped: split, gushing
        s.rect(13, 45, 6, 7, 'D'); s.vline(13, 45, 7, 'K'); s.vline(18, 45, 7, 'K')
        s.rect(13, 45, 6, 3, 'u'); s.hline(13, 45, 6, 'Q'); bolts(s, [(14, 46)])
        for (x, y) in ((15, 49), (16, 50), (14, 51)): s.put(x, y, 'K')
        for (x, y) in ((19 + i, 49), (20, 48 - i), (21 - i, 50), (19, 47)): s.put(x, y, 'L' if i else 'M')
        s.put(12, 53 + 3 * i, 'H')
        for (k, x) in enumerate((6, 11, 16)): s.rect(x, 37, 2, 1, 'r' if (k + i) % 2 else 'D')
        s.put(8, 40 + i, 'y'); s.put(9, 39, 'H' if i else 'y')                              # spark at the tank valve
        crack(s, [(21, 52), (23, 55), (22, 57)], 'M')
    def wreck(self, s):
        draw_fan(s, 12, (0, 1), False, missing=True, dead=True)
        s.sub({}) 
        for y in range(44, 53):                                                            # duct pulled apart
            for x in range(13, 19): s.erase(x, y)
        s.stamp(13, 42, art("KKKKKK\nKSMSEK\n.KEKK.")); s.stamp(12, 52, art("K.KK.K\nKSEESK\nKKKKKK"))
        s.stamp(15, 47, art("..K.\n.KMK\n..K.")); s.put(10, 52, 'D'); s.put(11, 52, 'D')
        crack(s, [(20, 46), (24, 49), (22, 52), (25, 56)], 'M'); s.stamp(21, 52, art("KK.\nKDK\n.KK"))   # rusty tank splits
        s.stamp(7, 7, art("KKK.\nKLMK\n.KSK")); s.stamp(22, 15, art("K.KK\nKSSK"))                        # bent bar, blade hanging
        s.rect(8, 60, 10, 2, 'D'); s.hline(9, 61, 8, 'K')                                                  # leak pool
        for (x, y) in ((6, 36), (11, 36), (16, 36)): s.rect(x, y + 1, 2, 1, 'E')
        stamp_on(s, 4, 22, SCORCH_S)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else 0.7
        for kk, (x, c) in enumerate(((6, AMBER), (11, AMBER), (16, ORANGE))):
            if flick is not None: c = RED
            if kk == 2 and flick is None and i % 2: continue
            glow(g, ox + x + 1, oy + 37, 4.5, c, 0.55 * k, 2.0)
        glow(g, ox + 16, oy + 16, 12, GREEN, 0.10 * k, 2.0)               # a faint green breath over the fan
        if flick is not None: glow(g, ox + 9, oy + 40, 4, YEL, 0.5 if flick else 0.2, 2.0)


ALL = [OxygenScrap]
