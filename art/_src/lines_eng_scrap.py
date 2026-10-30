"""Kickjet Deluxe, Double Kick and Thunderknuckle (engines_1.md). Engine_scrap_mk1 (lines_engine.py) stays as it is; every tier is built on its look:
rust, hazard tape, bolt heads, weld seams, mismatched plates, a flame that never burns evenly. More patches, more tape and more mismatched nozzles per tier:
 Mk2 Kickjet Deluxe: the Kickjet bell and tank plus a rusty stovepipe nozzle where the bracket was, a racing stripe of tape and more patches.
 Mk3 Double Kick: two big mismatched bells (a dented grey one, a rust one), a small tank, a weld joining them.
 Mk4 Thunderknuckle (outside 4x3): four mismatched nozzles welded into a fist on a taped, patched palm."""
from lines_eng_base import *
from lines_engine import _Scrap, chamfer_tones_h

_S1 = _Scrap()
GREY = 'LLLMMMMSSSSSSSWWWWWEEE'
RUST = 'QQQQuuuuuuqqqqnnn'
DUSK = 'MMMSSSSWWWWEEE'

def kick_bell(s, x0, w0, y0, step, on, i, tones=GREY, sh=6, nsec=4, y_end=32, shr=(3, 6, 1), seam='E'):
    """a Kickjet bell: oversized stepped cone, seams, bolts, a neck plate to y_end; the jet is ragged (shr = how far each frame pulls in)."""
    for k in range(nsec):
        a = y0 + k * sh; inset = k * step; wd = w0 - 2 * inset
        T = col_tones(wd, tones)
        for y in range(a, a + sh):
            for q in range(wd): s.put(x0 + inset + q, y, T[q])
        if k: s.hline(x0 + inset, a, wd, seam)
    ni = (nsec - 1) * step; nw = w0 - 2 * ni; nx = x0 + ni; ny = y0 + nsec * sh
    for y in range(ny, y_end):
        s.hline(nx, y, nw, 'S'); s.put(nx, y, 'M'); s.put(nx + nw - 1, y, 'W')
    s.hline(nx, ny + 3, nw, 'E'); weld(s, nx, ny + 1, nw)
    s.hline(x0 + 2, y0, w0 - 4, 'D'); s.hline(x0 + 2, y0 + 1, w0 - 4, 'D')
    s.put(x0 + 1, y0, 'M'); s.put(x0 + 1, y0 + 1, 'L'); s.put(x0 + w0 - 2, y0, 'W'); s.put(x0 + w0 - 2, y0 + 1, 'M')
    bolts(s, [(x0 + 2, y0 + 3), (x0 + w0 - 4, y0 + 3)])
    if nsec > 1 and w0 > 20: bolts(s, [(x0 + 7, y0 + 8), (x0 + w0 - 9, y0 + 8)])
    m0, mw = x0 + 2, w0 - 4
    if on:
        sk = [max(1, int(round(v * w0 / 30.0))) for v in shr][i % 3]
        lo, hi = m0 + sk, m0 + mw - sk
        s.hline(lo, y0, hi - lo, 'o'); s.hline(lo + 1, y0 + 1, hi - lo - 2, 'o'); s.hline(lo + 4, y0 + 1, max(0, hi - lo - 8), 'y')
        c = x0 + w0 // 2
        s.put(c - 1, y0 + 1, 'H'); s.put(c, y0 + 1, 'H'); s.put(lo + 3 + 4 * i, y0, 'D'); s.put(hi - 5 - 2 * i, y0, 'D')
    else: s.hline(x0 + 5, y0 + 1, w0 - 10, 'E')

def dent(s, x, y):
    """the Kickjet's dent: a bite out of the left side with a dark crease."""
    for (dx, dy) in ((0, 0), (0, 1), (1, 1), (0, 2), (1, 2), (2, 2)): s.erase(x + dx, y + dy)
    for (dx, dy) in ((1, 0), (2, 1), (3, 2), (2, 3), (3, 3), (4, 3)): s.put(x + dx, y + dy, 'D')
    for (dx, dy) in ((2, 0), (3, 1), (4, 2)): s.put(x + dx, y + dy, 'W')

def rust_patch(s, x, y, w, h, tone='u'):
    hi, mid, lo = ('Q', 'u', 'n') if tone == 'u' else ('M', 'S', 'W')
    s.rect(x, y, w, h, mid); s.hline(x, y, w, hi); s.vline(x, y, h, hi); s.hline(x, y + h - 1, w, lo); s.vline(x + w - 1, y, h, lo)
    bolts(s, [(x + 1, y + 1), (x + w - 3, y + 1)]) if w >= 7 else s.put(x + 1, y + 1, 'L')

def pipe_nozzle(s, x0, w, y0, y1, on, i, tones=RUST, flame=1, rim='S'):
    """a stovepipe nozzle: a rusty tube with a grey rim, tape round the middle and a small ragged flame."""
    T = col_tones(w, tones)
    for y in range(y0 + 2, y1):
        for q in range(w): s.put(x0 + q, y, T[q])
    s.hline(x0 - 1, y0, w + 2, rim); s.hline(x0 - 1, y0 + 1, w + 2, 'M' if rim == 'S' else 'S'); s.put(x0 - 1, y0, 'L'); s.hline(x0 - 1, y0 + 2, w + 2, 'E')
    s.hline(x0 + 1, y0, w - 2, 'D'); s.hline(x0 + 1, y0 + 1, w - 2, 'D')
    hazard(s, x0, y0 + 9, w, 3)
    s.put(x0 + 1, y0 + 4, 'L'); s.put(x0 + w - 2, y0 + 4, 'L'); weld(s, x0, y0 + 14, w)
    if on:
        sk = [1, 2, 0][(i + flame) % 3]
        s.hline(x0 + 1 + sk, y0, w - 2 - 2 * sk, 'o'); s.hline(x0 + 2 + sk, y0 + 1, max(0, w - 4 - 2 * sk), 'y')
        s.put(x0 + w // 2, y0 + 1, 'H')
    else: s.hline(x0 + 2, y0 + 1, w - 4, 'E')

def tank(s, x0, w, y0, y1):
    """the rusty strapped fuel tank, grey heads, a weeping valve."""
    chamfer_tones_h(s, x0, y0, w, y1 - y0, col_tones(w, 'QQuuuuqqqnnnn'))
    for y in list(range(y0, y0 + 4)) + list(range(y1 - 4, y1)):
        for x in range(x0, x0 + w):
            if s.get(x, y) != '.': s.put(x, y, 'M' if x < x0 + w // 3 else ('S' if x < x0 + 2 * w // 3 + 1 else 'W'))
    s.hline(x0 + 1, y0 + 4, w - 2, 'E'); s.hline(x0 + 1, y1 - 5, w - 2, 'E')
    for sy in (y0 + 8, y1 - 10):
        s.rect(x0 - 1, sy, w + 2, 3, 'E'); s.hline(x0 - 1, sy, w + 2, 'S'); s.put(x0, sy + 1, 'L'); s.put(x0 + w - 1, sy + 1, 'L')
    circle(s, x0 + w // 2, (y0 + y1) // 2 - 1, 1.8, 'E'); circle(s, x0 + w // 2, (y0 + y1) // 2 - 1, 1.1, 'M'); s.put(x0 + w // 2 - 1, (y0 + y1) // 2 - 2, 'L')

def scrap_core_glow(g, ox, oy, i, flick, extra=()):
    k = 1.0 if flick is None else (0.65 if flick else 0.85)
    b = oy + 4
    for y in (11.5, 15.5, 19.5): glow(g, ox + 6, b + y + .5, 4, AMBER, 0.5 * k, 2.0)
    for (x, y) in ((33.5, 8.5), (36.5, 8.5), (39.5, 8.5)): glow(g, ox + x, b + y, 4, ORANGE, 0.4 * k, 2.0)
    glow(g, ox + 37, b + 25.5, 5, GREEN, 0.3 * k, 2.0)
    for vy in (16, 19, 22, 25):
        if (vy // 3 + i) % 3 == 0: glow(g, ox + 53.5, b + vy + 1, 7, ORANGE, 0.3 * k, 2.0, sx=1.5)
    for (x, y, r, rgb, a) in extra: glow(g, ox + x, b + y, r, rgb, a * k, 2.0)

# ================================================================ Mk2: Kickjet Deluxe
class Mk2(EngBase):
    id = 'engine_scrap_mk2'; KIND = 'scrap'; DMG = (1, 2)
    pad_out = (10, 34, 10, 4)
    anchors_out = {'exhaust': (27, 1), 'exhaust_small': (6, 10)}
    anchors_in = {'power_coupling': (37, 29), 'repair_hatch': (21, 29)}
    notes = ('Scrapper Clans "Kickjet Deluxe", a hull mount (outward is up): the Kickjet bell and strapped tank plus a rusty stovepipe nozzle with its own small flame where the bracket was, a racing stripe of hazard tape round the bell and more patches; '
             'inside the Kickjet core plus a taped spare plate, a second lamp row and a rusty feed pipe. '
             'Damaged: the lower tank strap snapped and the tank sags and weeps fuel, the dent is on fire, the stovepipe is bent over and sputtering, sparks in the core. '
             'Disabled: the bell broken off its neck, the stovepipe snapped, the tank slid off and split, the core dead.')
    def out(self, o, on, i):
        from_full(o, _S1.interior('on' if on else 'off', i), 0)
        for y in range(10, 32):
            for x in range(0, 12): o.erase(x, y)
        pipe_nozzle(o, 2, 9, 9, 31, on, i)
        o.hline(11, 25, 2, 'K'); weld(o, 11, 22, 2, True)
        hazard(o, 19, 14, 17, 2); rust_patch(o, 15, 20, 6, 5, 'S')                       # a racing stripe and a mismatched grey patch on the bell
    def hurt_out(self, o, i):
        S = _S1
        f = Spr(64, 80); f.stamp(0, 0, o.rows()); S.hurt(f, i); from_full(o, f, 0)
        shift_rect(o, 0, 12, 8, 21, -1, 0); o.stamp(1, 19, art("KKKKK\nKDDDK\n.KDK.")); o.put(7 - i, 7, 'o'); o.put(6 + i, 5, 'y'); o.put(5, 6 - i, 'o')         # the stovepipe is bent and on fire
    def wreck_out(self, o):
        f = Spr(64, 80); f.stamp(0, 0, o.rows()); _S1.wreck(f); from_full(o, f, 0)
        shift_rect(o, 0, 12, 8, 24, -1, 3); o.hline(2, 24, 9, 'K'); crack(o, [(4, 26), (6, 29), (4, 31)], 'M'); o.stamp(0, 5, art("KKKK.\nKSDK.\n.KKKK"))
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        inten = [0.8, 1.0, 0.85][i % 3]
        glow_xy(g, ox + 27, oy + 1.5, 19, 30, ORANGE, 0.62 * inten * k, 2.0)
        glow_xy(g, ox + 27, oy + 1.5, 10, 14, (255, 214, 90), 0.5 * inten * k, 1.7)
        glow_xy(g, ox + 6.5, oy + 9.5, 7, 17, ORANGE, 0.5 * [1.0, 0.7, 0.9][i % 3] * k, 2.0)
        if flick is not None: glow(g, ox + 18, oy + 8, 5.5, ORANGE, 0.55 if flick else 0.4, 1.8)
    def core(self, c, on, i):
        t = Spr(64, 32); _S1.core(t, on, i); from_full(c, t, 0)
        hazard(c, 14, 21, 15, 2)                                          # tape over the repair hatch lip
        rust_patch(c, 46, 3, 15, 8, 'S')                                  # a mismatched grey patch on the lamp plate
        c.rect(48, 6, 8, 2, 'D'); c.put(57, 6, 'a' if on and i != 1 else 'n')
        line(c, 11, 8, 14, 12, 'r'); c.put(14, 13, 'a' if on and i == 2 else 'r')
        c.hline(13, 30, 31, 'q'); c.hline(13, 31, 31, 'n')                  # a rusty feed pipe along the bottom
        for x in (17, 29, 41): c.put(x, 30, 'L'); c.put(x + 1, 30, 'Q')
        for q, x in enumerate((3, 6, 9)): c.put(x, 25, 'a' if on and (q + i) % 3 else ('o' if on else 'W'))
    def hurt_core(self, c, i):
        f = Spr(64, 80); f.stamp(0, 48, c.rows()); _S1.hurt(f, i); from_full(c, f, 48)
    def wreck_core(self, c):
        f = Spr(64, 80); f.stamp(0, 48, c.rows()); _S1.wreck(f); from_full(c, f, 48)
        crack(c, [(48, 4), (52, 8), (50, 11)], 'M')
    def glow_core(self, g, ox, oy, i, flick=None):
        scrap_core_glow(g, ox, oy, i, flick, extra=[(3.5, 25.5, 3, AMBER, 0.4), (6.5, 25.5, 3, AMBER, 0.4), (9.5, 25.5, 3, AMBER, 0.4)])


def box_nozzle(s, x0, w, y0, y1, on, i, flame=0):
    """a boxy steel nozzle, riveted from plate: square mouth, seams, bolts."""
    T = col_tones(w, 'LMMMSSSSWWWEE')
    for y in range(y0, y1):
        for q in range(w): s.put(x0 + q, y, T[q])
    for y in range(y0 + 7, y1, 7): s.hline(x0, y, w, 'E'); s.hline(x0, y + 1, w, 'W')
    s.hline(x0 - 1, y0, w + 2, 'M'); s.hline(x0 - 1, y0 + 1, w + 2, 'S'); s.put(x0 - 1, y0, 'L'); s.hline(x0 - 1, y0 + 2, w + 2, 'E')
    s.hline(x0 + 1, y0, w - 2, 'D'); s.hline(x0 + 1, y0 + 1, w - 2, 'D')
    bolts(s, [(x0 + 1, y0 + 4), (x0 + w - 3, y0 + 4)])
    if on:
        sk = [2, 0, 1][(i + flame) % 3]
        s.hline(x0 + 1 + sk, y0, w - 2 - 2 * sk, 'o'); s.hline(x0 + 2 + sk, y0 + 1, max(0, w - 4 - 2 * sk), 'y'); s.put(x0 + w // 2, y0 + 1, 'H')
    else: s.hline(x0 + 2, y0 + 1, w - 4, 'E')

def tape_hang(s, x, y, n, i=0):
    """a strip of hazard tape coming loose and hanging."""
    for k in range(n): s.put(x + (k + i) // 4, y + k, 'a' if (k // 2) % 2 == 0 else 'K')

# ================================================================ Mk3: Double Kick
class Mk3(Mk2):
    id = 'engine_scrap_mk3'
    DMG = (1, 2)
    anchors_out = {'exhaust_left': (14, 1), 'exhaust_right': (41, 5)}
    notes = ('Scrapper Clans "Double Kick", a hull mount (outward is up): two big mismatched bells welded side by side, a dented grey one and a rust one with a grey patch, a welded cross plate with tape, and a small strapped tank; '
             'inside the Kickjet core with a second ribbed motor, taped hatches, a rusty feed pipe and wires between the boxes. '
             'Damaged: the dent is on fire, the rust bell lost a patch bolt and its flame sputters, the tank strap is snapped and it weeps fuel, sparks in the core. '
             'Disabled: both bells bent over at their necks, the weld between them cracked, the tank slid off and split, the core dead.')
    def out(self, o, on, i):
        kick_bell(o, 1, 28, 1, 3, on, i, GREY)
        kick_bell(o, 30, 22, 5, 2, on, (i + 1) % 3, RUST, sh=5, shr=(2, 5, 1))
        dent(o, 2, 8); rust_patch(o, 19, 3, 8, 6); rust_patch(o, 33, 9, 7, 5, 'S')
        plate(o, 19, 22, 19, 5, 'u'); hazard(o, 19, 27, 19, 2); weld(o, 29, 11, 11, True)
        tank(o, 53, 9, 8, 31)
        line(o, 51, 20, 38, 24, 'q'); o.put(45, 22, 'Q')
        hazard(o, 11, 17, 8, 2)
    def hurt_out(self, o, i):
        fl = [[(4, 9), (5, 8), (4, 7)], [(5, 9), (5, 6), (6, 7)]][i]
        for (x, y) in fl: o.put(x, y, 'o')
        o.put(5, 9, 'y'); o.put(4, 10, 'o')
        o.put(34, 10, 'K'); o.put(35, 10, 'D'); o.put(34 + 2 * i, 4, 'H')
        crack(o, [(12, 13), (14, 17), (13, 21)], 'M')
        o.rect(52, 21, 11, 3, '.'); o.rect(52, 21, 3, 3, 'E'); o.stamp(55, 22, art("KKK\nKEK\nKSK\nKLK\n.K.")); o.put(55, 27, 'L')
        o.vline(53, 12, 9, 'K'); o.put(58, 19 + i, 'a'); o.put(58, 22 + i, 'a'); o.vline(56, 27 + i, 3, 'a')
        stamp_on(o, 22, 23, SCORCH_S); crack(o, [(40, 12), (42, 16), (41, 21)], 'M')
    def wreck_out(self, o):
        shift_rect(o, 0, 29, 0, 15, -3, 1); o.hline(7, 15, 14, 'K'); crack(o, [(12, 17), (14, 21), (11, 24)], 'M'); o.stamp(0, 12, art("KKK.\nKDDK\n.KDK"))
        shift_rect(o, 30, 52, 0, 17, 3, 1); o.hline(34, 17, 12, 'K'); crack(o, [(41, 19), (43, 23), (40, 26)], 'M'); crack(o, [(38, 12), (40, 18)], 'M')
        crack(o, [(29, 14), (30, 20), (29, 26)], 'K')
        shift_rect(o, 52, 64, 3, 31, 0, 3); crack(o, [(55, 14), (58, 17), (61, 16), (62, 20)], 'S'); o.vline(56, 25, 4, 'a'); o.stamp(51, 6, art("KKK.\nKSMK\n.KSK"))
        o.stamp(31, 3, art("KKK.\nKSDK\n.KKK"))
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        inten = [0.8, 1.0, 0.85][i % 3]; inten2 = [1.0, 0.8, 0.9][i % 3]
        glow_xy(g, ox + 15, oy + 1.5, 17, 30, ORANGE, 0.6 * inten * k, 2.0); glow_xy(g, ox + 15, oy + 1.5, 9, 14, (255, 214, 90), 0.5 * inten * k, 1.7)
        k2 = 0.55 if flick == 1 else 1.0
        glow_xy(g, ox + 41, oy + 5.5, 15, 28, ORANGE, 0.55 * inten2 * k * k2, 2.0); glow_xy(g, ox + 41, oy + 5.5, 8, 13, (255, 214, 90), 0.45 * inten2 * k * k2, 1.7)
        if flick is not None: glow(g, ox + 5, oy + 8, 5.5, ORANGE, 0.55 if flick else 0.4, 1.8)
    def core(self, c, on, i):
        Mk2.core(self, c, on, i)
        # a second motor: ribbed housing with a rust end cap, wired to the control box
        bev(c, 46, 2, 15, 10, 'M', 'S', 'W'); c.rect(46, 2, 3, 10, 'u'); c.vline(46, 2, 10, 'Q'); c.vline(48, 3, 8, 'n')
        for x in range(50, 59, 2): c.vline(x, 3, 8, 'E'); c.vline(x + 1, 3, 8, 'M')
        bolts(c, [(47, 3), (47, 9)]); c.put(59, 4, 'a' if on and i != 1 else 'n'); c.put(59, 6, 'r' if on else 'n')
        wire(c, [(46, 12), (43, 15), (40, 19)], 'r'); c.put(40, 19, 'a' if on and i == 0 else 'r')
        hazard(c, 46, 12, 15, 2)
    def hurt_core(self, c, i):
        Mk2.hurt_core(self, c, i)
        crack(c, [(52, 4), (55, 7), (54, 10)], 'K'); c.put(57, 2 + i, 'y'); c.put(55, 1, 'H' if i else 'y')
    def wreck_core(self, c):
        Mk2.wreck_core(self, c)
        c.stamp(47, 3, art("KKKKKKKKKK\nKDDKDDDDDK\n.KKKKKKKK.")); crack(c, [(50, 3), (53, 8), (51, 11)], 'M')
    def glow_core(self, g, ox, oy, i, flick=None):
        Mk2.glow_core(self, g, ox, oy, i, flick)
        k = 1.0 if flick is None else 0.6
        glow(g, ox + 59.5, oy + 4 + 4.5, 3, AMBER, 0.4 * k, 2.0)

# ================================================================ Mk4: Thunderknuckle
FIST = art("""
.a.a.a.a.
aaaaaaaaa
anaanaana
aaaaaaaaa
.aaaaaaa.
..aaaaa..
""")
class Mk4(Mk3):
    id = 'engine_scrap_mk4'; OUT_H = 48
    pad_out = (10, 38, 10, 4)
    anchors_out = {'exhaust_1': (8, 10), 'exhaust_2': (23, 3), 'exhaust_3': (38, 6), 'exhaust_4': (53, 12)}
    notes = ('Scrapper Clans "Thunderknuckle", a hull mount (outward is up): the 4x3 housing: four mismatched nozzles welded into a fist (a grey pipe, a rust cone, a steel box, a taped stovepipe at different heights) on a palm of mismatched bolted plates with a weld across the top and a band of hazard tape; '
             'inside the Kickjet core with a crude painted fist, two motors, heavy tape and patches. '
             'Damaged: the stovepipe is bent and sputters, the box nozzle is cracked, tape is peeling off the palm, a plate lost its bolts, sparks. '
             'Disabled: the stovepipe snapped off, the cone bent over, the pipe hanging off its weld, the palm plates split, the core dead.')
    def out(self, o, on, i):
        # four knuckles, welded: a grey pipe, a rust cone, a steel box, a taped stovepipe
        pipe_nozzle(o, 3, 11, 10, 33, on, i, DUSK, 0)
        kick_bell(o, 16, 15, 3, 1, on, i + 1, RUST, sh=5, shr=(2, 4, 1), y_end=33)
        box_nozzle(o, 32, 14, 6, 33, on, i + 2)
        pipe_nozzle(o, 47, 13, 12, 33, on, i, 'QQuuuuuqqqqnn', 2)
        for x in (15, 31, 46): weld(o, x, 18, 14, True)
        plate(o, 13, 24, 5, 8, 'M', False); plate(o, 29, 26, 5, 6, 'u', False)
        # the palm: three mismatched plates, tape, a weld bead along the top
        plate(o, 1, 33, 21, 11, 'S'); plate(o, 22, 33, 20, 11, 'u'); plate(o, 42, 33, 21, 11, 'M')
        hazard(o, 2, 40, 60, 3); weld(o, 3, 31, 57); weld(o, 21, 34, 9, True); weld(o, 41, 34, 9, True)
        rust_patch(o, 25, 35, 8, 4, 'S'); o.put(50, 36, 'D'); o.hline(46, 36, 3, 'D')
    def hurt_out(self, o, i):
        o.erase(57, 12); o.erase(58, 12); o.erase(58, 13); o.stamp(54, 10, art("KKK.\nKLMK\n.KSK")); shift_rect(o, 47, 61, 11, 24, 1, 0)
        if i == 1: o.hline(49, 12, 9, 'D'); o.hline(50, 13, 6, 'D')
        crack(o, [(38, 10), (40, 15), (38, 20), (41, 26)], 'M'); o.put(35, 9, 'K'); o.put(35 + i, 3, 'H')
        for (x, y) in ((6, 14), (7, 14), (6, 13)): o.put(x, y, 'o' if i else 'y')
        o.put(6, 15, 'y'); o.put(5, 15, 'o')
        tape_hang(o, 30, 41, 6, i); tape_hang(o, 11, 41, 4, 1 - i)
        stamp_on(o, 25, 37, SCORCH_S); stamp_on(o, 52, 38, SCORCH_S); o.put(45, 37, 'K'); o.put(46, 37, 'D')
        crack(o, [(19, 8), (21, 13), (20, 18)], 'M')
    def wreck_out(self, o):
        shift_rect(o, 46, 62, 0, 24, 2, 2); o.hline(48, 24, 12, 'K'); crack(o, [(54, 26), (56, 30)], 'M'); o.stamp(58, 12, art("KKK\nKSK\nKKK"))
        shift_rect(o, 15, 31, 0, 18, -2, 1); o.hline(17, 18, 11, 'K'); crack(o, [(22, 20), (24, 24), (21, 28)], 'M')
        shift_rect(o, 2, 15, 0, 22, -1, 3); o.hline(4, 22, 9, 'K'); o.stamp(2, 9, art("KKKK\nKSDK\n.KKK"))
        crack(o, [(36, 8), (38, 13), (36, 19), (39, 25)], 'M'); crack(o, [(21, 34), (23, 38), (21, 42)], 'M'); crack(o, [(44, 35), (46, 39)], 'M'); stamp_on(o, 26, 36, SCORCH_L)
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        for n, (x, y, rx, ry) in enumerate(((8.5, 10.5, 9, 24), (23.5, 3.5, 12, 30), (39, 6.5, 11, 28), (53.5, 12.5, 10, 22))):
            q = [0.8, 1.0, 0.85, 0.9][(n + i) % 4]
            k2 = 0.5 if (flick == 1 and n == 3) else (0.8 if flick is not None and n == 1 else 1.0)
            glow_xy(g, ox + x, oy + y, rx, ry, ORANGE, 0.55 * q * k * k2, 2.0); glow_xy(g, ox + x, oy + y, rx * 0.5, ry * 0.47, (255, 214, 90), 0.45 * q * k * k2, 1.7)
    def core(self, c, on, i):
        Mk3.core(self, c, on, i)
        c.rect(16, 4, 10, 9, 'M'); c.stamp(16, 6, FIST, sub={'a': 'a' if on else 'u'})
        hazard(c, 1, 24, 11, 2); hazard(c, 31, 14, 12, 2)
        rust_patch(c, 29, 2, 6, 4, 'S')
        for q, x in enumerate((15, 21)): c.put(x, 14, 'L')
    def hurt_core(self, c, i):
        Mk3.hurt_core(self, c, i)
        tape_hang(c, 4, 25, 4, i)
    def wreck_core(self, c):
        Mk3.wreck_core(self, c)
        crack(c, [(17, 3), (20, 8), (18, 13)], 'K')
    def glow_core(self, g, ox, oy, i, flick=None):
        Mk3.glow_core(self, g, ox, oy, i, flick)

ALL = [Mk2(), Mk3(), Mk4()]
