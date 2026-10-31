"""Emberkin tech (docs/waves/racial_tech_1.md): brass and fire. Dark gunmetal bodies (W/E/D), brass fittings (y/a/u, shade n), navy enamel inlays (J/I) as in the Emberkin
crew's colours, rounded pots, tubes and domes, flame vents with a pilot flame that flickers (2-3 frames), and fire colours (r/o/y/H) as the light.
Weapons: emberkin_pyre_lance, emberkin_cinder_mortar, emberkin_flare_turret. Components: emberkin_pyre_drive (engine), emberkin_furnace_core (reactor),
emberkin_hearth_shield (shield). Projectile art: fire plumes, embers."""
from techa_kit import *
from lines_shield import ShieldBase, seg_ring, BR

# ------------------------------------------------------------------ emberkin vocabulary
GUN = ('W', 'E', 'D')

def brass_cyl_v(s, x, y, w, h):
    """a vertical brass cylinder."""
    ramp = 'yyaaauun'
    for k, c in enumerate(ramp_rows(w, ramp)): s.vline(x + k, y, h, c)

def brass_band(s, x, y, w, h=2):
    s.hline(x, y, w, 'y'); s.hline(x, y + h - 1, w, 'u')
    for k in range(h - 2): s.hline(x, y + 1 + k, w, 'a')

def brass_band_v(b, x, y, h, w=2):
    """a brass collar across a horizontal barrel (east canvas)."""
    b.vline(x, y, h, 'y')
    for k in range(1, w): b.vline(x + k, y, h, 'u')
    b.put(x, y, 'a'); b.put(x, y + h - 1, 'a')

def brass_cylh(b, x, y, w, h):
    cylh(b, x, y, w, h, 'yyaaauun')

def navy(s, x, y, w, h):
    """a navy enamel inlay panel with a lit top edge."""
    s.rect(x, y, w, h, 'J'); s.hline(x, y, w, 'j'); s.hline(x, y + h - 1, w, 'I')

class BrassMount:
    """brass-trimmed flange (a gold line with rivets), as the uniques have it."""
    def trim(self, s, st, half):
        fy = 2 if half == 'in' else s.h - 3
        s.hline(3, fy, 58, 'a')
        for x in (4, 13, 50, 59): s.put(x, fy, 'y')
        for x in range(8, 56, 6): s.put(x, fy, 'u')

def vent_stack(s, x, y, w, h, on, i, k=0):
    """a brass flame-vent stack standing on (x, y): a tube with a flared lip; the pilot flame burns on top when powered."""
    brass_cyl_v(s, x, y - h, w, h)
    s.hline(x - 1, y - h, w + 2, 'y'); s.hline(x - 1, y - h + 1, w + 2, 'u')
    s.hline(x - 1, y - h // 2, w + 2, 'u')
    if on:
        flame(s, x + (w - 3) // 2 if w >= 3 else x, y - h - 1, 5 + (i + k) % 2, 3, i + k)

# ============================================================ PYRE LANCE
class PyreLance(BrassMount, Weapon):
    id = 'emberkin_pyre_lance'
    blen, bwid = 74, 17
    bpivot = (6, 8)
    bmuzzle = (59, 8)
    out_notes = ('OUTSIDE half of the Emberkin Pyre Lance: a gunmetal block with a brass sleeve, a riveted brass boiler on the left (pressure gauge, navy enamel plate) and two flame-vent stacks on the right '
                 'whose pilot flames flicker. damaged: boiler seam split and leaking fire, a stack bent over, sparks; disabled: pilots out, scorched, dented, sparking.')
    notes = ('INSIDE half of the Emberkin Pyre Lance: a brass boiler drum above a firebox whose flames climb with the charge (frame 5 = tall white-tipped flames, strip yellow), power coupling, brass hatch, '
             'a pipe to the right. fire: the firebox flashes white and the flames drop. damaged: the boiler seam cracked and weeping steam-fire, two lamps dead; disabled: cold firebox, the drum split, a pipe hanging. '
             'Barrel layer emberkin_pyre_lance_barrel: a long slim brass lance with cooling rings, a flared burner nozzle and a pilot flame; fire: a roaring jet.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        mat(s, 6, 20, 52, 12, GUN)
        mat(s, 19, 2, 26, 26, GUN); mat(s, 22, 1, 20, 8, GUN)
        s.rect(26, 2, 12, 6, 'D'); s.hline(26, 2, 12, 'K')
        brass_band(s, 18, 9, 28, 5); s.put(32, 11, 'L'); s.put(33, 12, 'W')
        for x in (21, 42): s.put(x, 11, 'y')
        mat(s, 3, 6, 16, 18, GUN)                                                 # left: the boiler
        brass_cyl_v(s, 5, 8, 12, 14)
        for yy in (11, 18): s.hline(5, yy, 12, 'u'); s.hline(5, yy + 1, 12, 'y')
        gauge(s, 11, 14, 2, pw, i % 2)
        navy(s, 5, 20, 12, 2)
        mat(s, 45, 8, 16, 16, GUN)                                                # right: two flame-vent stacks
        vent_stack(s, 48, 22, 4, 9, pw, i, 0); vent_stack(s, 55, 22, 4, 9, pw, i, 1)
        s.hline(47, 22, 14, 'u')
        s.hline(24, 20, 3, 'W'); s.hline(28, 20, 2, 'W'); s.hline(31, 20, 3, 'W')
        for (x, y) in ((22, 5), (41, 5), (22, 26), (41, 26)): s.put(x, y, 'y')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        mat(s, 2, y + 1, 60, 30, GUN)
        s.hline(3, y + 1, 58, 'a')
        cable_stub(s, 3, y + 8, st, 'o', GUN)
        mat(s, 15, y + 5, 28, 7, BRASS, cham=True)                                # boiler drum
        for bx in (21, 30, 38): s.vline(bx, y + 5, 7, 'u')
        s.put(17, y + 7, 'H'); s.put(40, y + 8, 'L')
        mat(s, 15, y + 13, 28, 12, GUN_L := ('S', 'W', 'E'))                      # firebox
        s.rect(17, y + 15, 24, 8, 'D'); s.hline(17, y + 15, 24, 'K'); s.hline(17, y + 23, 24, 'M')
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 5 if st.i == 0 else 0
        for k in range(8):
            fx = 18 + 3 * k
            if st.state == 'fire' and st.i == 0: s.rect(17, y + 15, 24, 8, 'L'); break
            if pw and n: flame(s, fx, y + 22, 2 + (n * 5) // 5 + (k + st.i) % 2, 3 if k % 2 == 0 else 2, k + st.i, hot=(n == 5))
        pipe_h(s, 43, y + 8, 18, 3, 'a')
        hatch_k(s, 46, y + 14, BRASS, 11, 9, 'o')
        slits(s, st, STRIP_X, y + STRIP_DY, cold=('E', 'D'), lit=('o', 'y'), hot=('y', 'H'), base=('D', 'K'))
        navy(s, 4, y + 21, 8, 3) if False else None
    def hurt_out(self, s, st):
        crack(s, [(8, 8), (9, 12), (7, 16), (8, 20)]); s.put(8, 13, 'o' if st.i else 'y'); s.put(9, 15, 'o')
        move(s, 55, 8, 5, 15, 2, 1); s.hline(56, 12, 3, 'K')
        s.stamp(46, 3, FLAP); wire(s, [(48, 6), (50, 8)])
        crack(s, [(31, 4), (30, 8), (32, 11)])
        hurt_pair(s, st, (9, 5), (53, 20))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 4), (30, 8), (32, 11), (30, 14), (31, 17), (33, 22)], [(8, 8), (9, 12), (7, 16), (8, 20)]],
                 dents=[(8, 17, 6, 4), (50, 14, 6, 4)], soots=[(22, 3, 1), (45, 8, 0), (4, 8, 2)],
                 wires_=[[(56, 6), (58, 9), (57, 12)]], sparks=[(26, 8), (56, 4)], flap=(46, 3))
    def hurt_in(self, s, st):
        y = self.iy
        dead_slits(s, st, y + STRIP_DY)
        crack(s, [(24, y + 5), (26, y + 8), (25, y + 11)]); s.put(26, y + 8, 'o'); s.put(26, y + 12, 'o' if st.i else 'y'); s.put(26, y + 13, 'r')
        hurt_pair(s, st, (50, y + 13), (35, y + 6))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(28, y + 5), (30, y + 8), (28, y + 11)]); crack(s, [(22, y + 14), (24, y + 18), (23, y + 24)])
        wire(s, [(46, y + 8), (50, y + 12), (52, y + 14)]); s.stamp(40, y + 19, art("KKK.\nKQqK\n.KKK"))
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        slits_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY, live=ORANGE, ready=YEL)
        n = {'charge': i, 'on': 5, 'damaged': 4}.get(state, 0)
        if state == 'fire' and i == 0: n = 5
        if n: glow(g, ox + 29, oy + y + 20 - n, 11, ORANGE, 0.12 + 0.07 * n, 1.8, sx=1.6)
        glow(g, ox + 12, oy + y + 14, 3, ORANGE, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 11, oy + 14, 4, ORANGE, 0.3, 2.0)
        for x in (49.5, 56.5): glow(g, ox + x, oy + 8.5, 6, ORANGE, 0.55, 1.8)
    # ---- barrel (east canvas 74x17: breech | slim brass lance | burner nozzle)
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 1, 1, 11, 15, 'y', 'a', 'u'); b.rect(4, 6, 5, 5, 'D'); b.put(6, 8, 'L'); b.put(7, 9, 'W')
        brass_band_v(b, 11, 0, 17, 3)
        brass_cylh(b, 14 + o, 4, 40, 9)
        for bx in (20, 28, 36, 44): brass_band_v(b, bx + o, 3, 11, 2)
        for (x, y) in ((24, 6), (32, 10), (40, 7)): b.put(x + o, y, 'u')
        bev(b, 54 + o, 2, 6, 13, 'y', 'a', 'u')                                    # the burner nozzle: a flared cup
        b.rect(58 + o, 4, 3, 9, 'D')
        if st.fire: b.rect(58 + o, 4, 3, 9, 'o'); b.rect(59 + o, 5, 2, 7, 'H')
        else: b.put(59 + o, 8, 'o'); b.put(60 + o, 8, 'y')
    def bhurt(self, b, st):
        crack(b, [(26, 4), (27, 8), (25, 12)]); b.put(27, 8, 'o' if st.i else 'y')
        move(b, 54, 2, 6, 13, 0, 2); b.put(57, 15, 'o')
        spark(b, 58, 1, False) if st.i == 0 else spark(b, 24, 3, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 40, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(25, 4), (27, 8), (25, 12)], 'K', 'S'); wire(b, [(39, 7), (42, 9)])
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 62, 8, sub=None)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 62, 8, scale=1.1)
        if state in ('idle', 'damaged'): glow(g, ox + 60, oy + 8.5, 4, ORANGE, 0.45, 1.8)

# ============================================================ CINDER MORTAR
class CinderMortar(BrassMount, Weapon):
    id = 'emberkin_cinder_mortar'
    blen, bwid = 58, 23
    bpivot = (6, 11)
    bmuzzle = (38, 11)
    out_notes = ('OUTSIDE half of the Emberkin Cinder Mortar: a gunmetal block with a big brass coal funnel on the left (glowing cinders heaped in it) and a riveted pressure tank with a gauge on the right; '
                 'a vent on the block spits a flame (15% of shots flash back into the room). damaged: funnel dented and spilling cinders, tank seam sparking; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Emberkin Cinder Mortar: a coal hopper that fills with glowing cinders as it charges (frame 5 = heaped and white-hot, strip yellow) above a firing pan, power coupling, brass hatch. '
             'fire: the pan flashes and the hopper empties (a flashback puff at the hatch). damaged: the hopper cracked, embers falling out, lamps dead; disabled: cold ash, the hopper split. '
             'Barrel layer emberkin_cinder_mortar_barrel: a short fat brass mortar with a wide funnel mouth full of embers.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        mat(s, 6, 20, 52, 12, GUN)
        mat(s, 19, 2, 26, 26, GUN); mat(s, 22, 1, 20, 8, GUN)
        s.rect(26, 2, 12, 6, 'D'); s.hline(26, 2, 12, 'K')
        brass_band(s, 18, 9, 28, 5); s.put(32, 11, 'L'); s.put(33, 12, 'W')
        for x in (21, 42): s.put(x, 11, 'y')
        mat(s, 3, 8, 16, 16, GUN)                                                 # left: coal funnel
        s.stamp(4, 5, art("""
.KKKKKKKKKKKK.
KyyaaaaaaaaauK
.KyaaaaaaaauK.
..KyaaaaaauK..
...KuuuuuuK...
"""))
        for (x, y) in ((6, 6), (8, 5), (10, 6), (12, 5), (9, 7)): s.put(x, y, 'o' if pw else 'u')
        for (x, y) in ((7, 6), (11, 5)): s.put(x, y, 'y' if pw else 'n')
        brass_cyl_v(s, 8, 10, 6, 12); s.hline(7, 15, 8, 'u')
        mat(s, 45, 6, 16, 18, GUN)                                                # right: pressure tank
        mat(s, 47, 9, 12, 12, BRASS); chamfer_fill(s, 47, 9, 12, 12, 'a', 3); rim(s, 'a', 'y', 'u', (47, 9, 58, 20))
        gauge(s, 53, 14, 2, pw, i % 3)
        s.hline(49, 19, 8, 'u')
        vent_stack(s, 25, 28, 3, 5, pw, i, 0)
        s.hline(24, 20, 3, 'W'); s.hline(28, 20, 2, 'W'); s.hline(31, 20, 3, 'W')
        for (x, y) in ((22, 5), (41, 5), (22, 26), (41, 26)): s.put(x, y, 'y')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        mat(s, 2, y + 1, 60, 30, GUN); s.hline(3, y + 1, 58, 'a')
        cable_stub(s, 3, y + 8, st, 'o', GUN)
        s.stamp(15, y + 4, art("""
.KKKKKKKKKKKKKKKKKKKKKKKKKKK.
KyaaaaaaaaaaaaaaaaaaaaaaaaaauK
.KyaDDDDDDDDDDDDDDDDDDDDDDauK.
..KyaDDDDDDDDDDDDDDDDDDDDauK..
...KuaDDDDDDDDDDDDDDDDDDauK...
....KuuaDDDDDDDDDDDDDDauuK....
"""))
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 5 if st.i == 0 else 0
        for r in range(n):                                                         # cinders heaped up from the bottom of the hopper
            yy = y + 9 - r + 0
            wd = 20 - r * 2 + (r == 0) * 2
            for q in range(wd):
                x = 22 + q + r
                if pw or st.state == 'fire': s.put(x, y + 9 - (r if r < 3 else 3) - (r - 3 if r > 3 else 0) * 0, 'o' if (q + r) % 3 else 'y') if False else None
        for q in range(22):
            h = [0, 1, 1, 2, 2, 3][min(n, 5)] if q % 3 else [0, 1, 2, 2, 3, 4][min(n, 5)]
            for r in range(h + (1 if n else 0)):
                if (pw or st.state == 'fire') and n:
                    c = 'H' if (st.state == 'fire' and st.i == 0) else ('y' if (r == h and (q + st.i) % 2) else ('o' if r else 'r'))
                    s.put(18 + q + 1, y + 9 - r, c)
        mat(s, 17, y + 12, 28, 9, ('S', 'W', 'E'))                                # the firing pan
        s.rect(19, y + 14, 24, 5, 'D'); s.hline(19, y + 18, 24, 'M')
        if pw and n: s.hline(21, y + 17, 20, 'r'); s.hline(23, y + 16, 16, 'o' if st.state != 'fire' else 'H')
        pipe_h(s, 45, y + 6, 16, 3, 'a')
        hatch_k(s, 46, y + 12, BRASS, 11, 9, 'o')
        slits(s, st, STRIP_X, y + STRIP_DY)
        if st.state == 'fire' and st.i == 0: flame(s, 47, y + 12, 5, 3, 0)
    def hurt_out(self, s, st):
        for (x, y) in ((4, 5), (5, 5), (4, 6), (5, 6), (4, 7)): s.erase(x, y)
        s.put(3, 9 + st.i, 'o'); s.put(3, 11, 'y')
        crack(s, [(55, 10), (53, 14), (55, 18)]); s.stamp(46, 3, FLAP); wire(s, [(48, 6), (50, 8)])
        hurt_pair(s, st, (12, 4), (57, 20))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 4), (30, 8), (32, 11), (30, 14), (31, 17), (33, 22)], [(54, 10), (52, 14), (54, 18)]],
                 dents=[(6, 17, 6, 5), (50, 20, 6, 3)], soots=[(22, 3, 1), (45, 6, 0), (4, 8, 2)],
                 wires_=[[(14, 8), (12, 12), (14, 16)]], sparks=[(26, 8), (56, 4)], flap=(46, 3))
    def hurt_in(self, s, st):
        y = self.iy
        dead_slits(s, st, y + STRIP_DY)
        crack(s, [(25, y + 5), (26, y + 8), (24, y + 10)]); s.put(26, y + 11, 'o'); s.put(26, y + 14 + 2 * st.i, 'o'); s.put(26, y + 13, 'r')
        hurt_pair(s, st, (50, y + 15), (36, y + 14))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(30, y + 5), (29, y + 8), (31, y + 11)]); crack(s, [(24, y + 12), (26, y + 17), (24, y + 20)])
        wire(s, [(46, y + 6), (50, y + 9), (52, y + 12)]); s.stamp(40, y + 21, art("KKK.\nKQqK\n.KKK"))
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        slits_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        n = {'charge': i, 'on': 5, 'damaged': 4}.get(state, 0)
        if state == 'fire' and i == 0: n = 5
        if n: glow(g, ox + 30, oy + y + 7, 12, ORANGE, 0.1 + 0.06 * n, 1.8, sx=1.5); glow(g, ox + 30, oy + y + 16, 9, ORANGE, 0.1 + 0.03 * n, 1.8, sx=1.8)
        glow(g, ox + 12, oy + y + 14, 3, ORANGE, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 10, oy + 6, 6, ORANGE, 0.5, 1.8, sx=1.4)
        glow(g, ox + 26, oy + 24, 5, ORANGE, 0.5, 1.8)
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 1, 3, 11, 17, 'y', 'a', 'u'); b.rect(4, 8, 5, 5, 'D'); b.put(6, 10, 'L'); b.put(7, 11, 'W')
        brass_band_v(b, 11, 2, 19, 3)
        brass_cylh(b, 14 + o, 5, 14, 13)
        brass_band_v(b, 19 + o, 4, 15, 2)
        for (x0, x1, y0, y1) in ((28, 30, 3, 19), (31, 33, 1, 21), (34, 38, 0, 22)): brass_cylh(b, x0 + o, y0, x1 - x0 + 1, y1 - y0 + 1)   # the funnel flare
        b.vline(31 + o, 1, 21, 'u'); b.vline(34 + o, 0, 23, 'u')
        b.rect(35 + o, 3, 4, 17, 'D')
        for k in range(5): b.put(36 + o + (k % 2), 5 + 3 * k, 'o' if st.state != 'disabled' else 'u')
        if st.fire: b.rect(35 + o, 4, 4, 15, 'o'); b.rect(36 + o, 5, 3, 13, 'H')
        else:
            for (x, y) in ((36, 7), (37, 11), (36, 15)): b.put(x + o, y, 'y')
    def bhurt(self, b, st):
        crack(b, [(21, 5), (22, 10), (21, 15)]); b.put(22, 10, 'o' if st.i else 'y')
        move(b, 31, 1, 8, 21, 0, 2); b.stamp(34, 22, art("o\ny")) if False else b.put(35, 22, 'o')
        spark(b, 37, 1, False) if st.i == 0 else spark(b, 20, 4, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 30, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(21, 5), (22, 10), (20, 16)], 'K', 'S'); wire(b, [(24, 9), (27, 11)])
    def bafter(self, b, st):
        if st.fire:
            stamp_flash(b, st, 40, 11)
            for (x, y) in ((46 + 2 * st.i, 5), (47, 17 - st.i)): b.stamp(x, y, art(".o.\noyo\n.o."))
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 40, 11, scale=1.0)
        if state in ('idle', 'damaged'): glow(g, ox + 37, oy + 11.5, 6, ORANGE, 0.4, 1.8)

# ============================================================ FLARE TURRET
class FlareTurret(BrassMount, Weapon):
    id = 'emberkin_flare_turret'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 46, 21
    bpivot = (9, 10)
    bmuzzle = (33, 10)
    out_notes = ('OUTSIDE half of the Emberkin Flare Turret (a TURRET): a brass-ringed seat, a rack of heat-sink fins on the left that glow as it overheats, and a navy-enamelled magazine hatch on the right with a lamp. '
                 'damaged: ring cracked, a fin bent, sparks; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Emberkin Flare Turret: a magazine rack where flare cartridges (brass casings, coloured caps) slide into the chamber one by one as it charges (frame 5 = five loaded, strip yellow), '
             'power coupling, brass hatch. fire: the chamber flashes and the rack is empty. damaged: a cartridge jammed crooked, the rack cracked, lamps dead; disabled: cartridges spilled, rack bent. '
             'Barrel layer emberkin_flare_turret_barrel: a brass dome head with a short flare gun, a flared muzzle and a small heat-sink fin stack.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        mat(s, 6, 19, 52, 13, GUN)
        mat(s, 18, 2, 28, 24, GUN)
        turret_ring(s, 32, 15, 25, 'y', 'a', 'u', 'D')
        for (x, y) in ((32, 4), (32, 26), (20, 15), (44, 15)): s.put(x, y, 'H')
        mat(s, 3, 6, 16, 18, GUN)                                                 # left: heat-sink fins
        for k in range(6):
            s.rect(5 + 2 * k, 8, 1, 13, 'M' if k % 2 else 'S'); s.rect(6 + 2 * k, 8, 1, 13, 'D')
        for k in range(6): s.put(6 + 2 * k, 9 + (i + k) % 2 * 0, 'o' if pw else 'E'); s.put(6 + 2 * k, 20, 'o' if pw and (k + i) % 2 else ('r' if pw else 'E'))
        brass_band(s, 4, 7, 14, 1)
        mat(s, 45, 6, 16, 18, GUN)                                                # right: magazine hatch
        navy(s, 47, 9, 12, 9); s.hline(47, 13, 12, 'I'); s.put(53, 11, 'y'); s.put(54, 11, 'y')
        for k in range(3): s.put(49 + 4 * k, 16, 'a' if pw else 'W')
        s.rect(55, 20, 3, 2, 'o' if pw and i == 0 else ('a' if pw else 'E'))
        s.hline(47, 20, 3, 'W'); s.hline(51, 20, 2, 'W')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        mat(s, 2, y + 1, 60, 30, GUN); s.hline(3, y + 1, 58, 'a')
        cable_stub(s, 3, y + 8, st, 'o', GUN)
        mat(s, 14, y + 6, 33, 14, ('S', 'W', 'E'), cham=False)                    # magazine rack
        s.rect(15, y + 9, 31, 8, 'D'); s.hline(15, y + 9, 31, 'K'); s.hline(15, y + 16, 31, 'W')
        n = {'charge': st.i, 'on': 5, 'damaged': 4}.get(st.state, 0)
        if st.state == 'fire': n = 0
        caps = ['r', 'o', 'y', 'o', 'r']
        for k in range(5):
            if k < n and pw or (st.state == 'disabled' and k in (1, 3)):
                x = 17 + 6 * k + (1 if st.state == 'disabled' else 0)
                s.rect(x, y + 10, 4, 6, 'a'); s.vline(x, y + 10, 6, 'y'); s.vline(x + 3, y + 10, 6, 'u'); s.rect(x, y + 10, 4, 2, caps[k] if pw else 'u')
        if st.state == 'fire' and st.i == 0: s.rect(15, y + 10, 31, 6, 'L')
        hatch_k(s, 49, y + 8, BRASS, 11, 9, 'o')
        slits(s, st, STRIP_X, y + STRIP_DY)
    def hurt_out(self, s, st):
        crack(s, [(31, 3), (30, 7), (32, 10)]); move(s, 15, 8, 3, 13, 1, 1) if False else s.vline(13, 9, 6, 'K')
        s.stamp(2, 3, FLAP); wire(s, [(8, 7), (10, 9)]); crack(s, [(52, 10), (54, 14)])
        hurt_pair(s, st, (9, 5), (54, 22))
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 3), (30, 8), (32, 12), (30, 17), (31, 22)], [(52, 9), (54, 14), (52, 18)]],
                 dents=[(7, 19, 6, 4), (50, 20, 6, 3)], soots=[(21, 3, 1), (44, 5, 0), (4, 8, 2)],
                 wires_=[[(12, 21), (10, 25)]], sparks=[(35, 6), (8, 12)], flap=(2, 3))
    def hurt_in(self, s, st):
        y = self.iy
        dead_slits(s, st, y + STRIP_DY)
        crack(s, [(25, y + 6), (27, y + 10), (26, y + 15)]); s.stamp(34, y + 11, art("QQq\nqQQ\n.nq"))
        hurt_pair(s, st, (38, y + 8), (52, y + 22))
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(22, y + 6), (24, y + 11), (23, y + 15)]); crack(s, [(36, y + 7), (38, y + 13)])
        wire(s, [(14, y + 20), (18, y + 23)]); s.stamp(30, y + 22, art("KKK.\nKQqK\n.KKK"))
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        slits_glow(g, ox, oy, state, i, STRIP_X, y + STRIP_DY)
        n = {'charge': i, 'on': 5, 'damaged': 4}.get(state, 0)
        for k in range(n): glow(g, ox + 19 + 6 * k, oy + y + 11, 3.5, ORANGE, 0.4, 2.0)
        glow(g, ox + 12, oy + y + 14, 3, ORANGE, 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 11, oy + 15, 7, ORANGE, 0.25 + 0.1 * (i % 2), 2.0, sx=1.3)
    def barrel(self, b, st):
        o = -st.rc
        chamfer_fill(b, 1, 2, 17, 17, 'a', 5); rim(b, 'a', 'y', 'u', (1, 2, 17, 18))                 # brass dome
        b.put(9, 10, 'H'); b.put(10, 10, 'y'); b.put(9, 9, 'y')
        for (x, y) in ((5, 6), (13, 6), (5, 14), (13, 14)): b.put(x, y, 'u')
        for k in range(4): b.vline(11 + 2 * k, 1, 2, 'D') if False else None
        for k in range(4):                                                         # the fin stack on top of the head
            b.vline(5 + 3 * k, 0, 2, 'M'); b.put(5 + 3 * k, 0, 'o' if st.state != 'disabled' and (k + st.i) % 2 == 0 else 'S')
        brass_cylh(b, 16 + o, 6, 12, 9)
        brass_band_v(b, 21 + o, 5, 11, 2)
        for (x0, x1, y0, y1) in ((28, 30, 4, 16), (31, 33, 3, 17)): brass_cylh(b, x0 + o, y0, x1 - x0 + 1, y1 - y0 + 1)
        b.rect(32 + o, 5, 3, 11, 'D')
        if st.fire: b.rect(32 + o, 5, 3, 11, 'o'); b.rect(33 + o, 6, 2, 9, 'H')
        else: b.put(33 + o, 10, 'y')
        eye(b, 6, 15, 'o') if False else None
    def bhurt(self, b, st):
        crack(b, [(5, 6), (8, 9), (7, 13)], 'K', 'S'); move(b, 5, 0, 3, 2, 1, 1)
        move(b, 28, 4, 6, 13, 0, 1)
        spark(b, 35, 4, False) if st.i == 0 else spark(b, 12, 2, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 28, 2, 3)
    def bwreck(self, b, st):
        crack(b, [(5, 5), (8, 9), (7, 14), (10, 17)], 'K', 'S'); wire(b, [(24, 8), (27, 10)])
    def bafter(self, b, st):
        if st.fire:
            stamp_flash(b, st, 36, 10, FLASH_S)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 36, 10, scale=0.9)
        if state != 'disabled':
            for k in range(4): glow(g, ox + 5 + 3 * k, oy + 1.5, 3, ORANGE, 0.3 if (k + i) % 2 == 0 else 0.15, 2.0)

FLAP = art("""
....SSM.
..SSMMS.
SSMMSS..
""")
FLASH_S = [art("""
.oy.......
.yHyoo....
oyHHHyyo..
yHHHHHHyyo
oyHHHyyo..
.yHyoo....
.oy.......
"""), art("""
.o.......
oyyo.....
yHHyoo...
oyyo.....
.o.......
"""), art("""
.o....
oyo...
yHyo..
oyo...
.o....
""")]
WEAPONS = [PyreLance, CinderMortar, FlareTurret]


# ================================================================== COMPONENTS
from lines_shield import arc, TIPS, CORN, PYL
from lines_eng_base import ANIMS

class PyreDrive(EngBase):
    id = 'emberkin_pyre_drive'; KIND = 'std'; DMG = (1, 2)
    pad_out = (10, 34, 10, 4)
    anchors_out = {'exhaust': (32, 8)}
    anchors_in = {'power_coupling': (33, 29), 'repair_hatch': (13, 29)}
    notes = ('Emberkin "Pyre Drive" (thrust x1.5, hot), a hull mount (outward is up): outside, one big brass bell breathing a real flame (hard flame tongues over the mouth, 3-frame flicker) with two small '
             'pilot nozzles; a brass collar through the wall; inside, a brass furnace core with a flame window, three pressure gauges, a hatch and a power coupling. '
             'Damaged: the bell lip dented and a side pilot burning crooked, the gauges cracked, sparks at the coupling. Disabled: the flame out, the bell split and slumped, the furnace dark.')
    def flange_out(self, o):
        o.hline(3, 29, 58, 'a')
        for x in (4, 13, 50, 59): o.put(x, 29, 'y')
    def flange_in(self, c):
        c.hline(3, 2, 58, 'a')
        for x in (4, 13, 50, 59): c.put(x, 2, 'y')
    def out(self, o, on, i):
        # side pilot nozzles
        for x0 in (5, 52):
            brass_cyl_v(o, x0, 17, 7, 11); o.hline(x0 - 1, 17, 9, 'y'); o.hline(x0 - 1, 18, 9, 'u'); o.hline(x0 + 1, 17, 5, 'D')
            if on: flame(o, x0 + 2, 16, 4 + (i % 2), 3, i + x0)
        # the big bell
        for (y0, y1, x0, x1) in ((9, 13, 16, 47), (14, 19, 18, 45), (20, 25, 21, 42), (26, 28, 25, 38)):
            for x in range(x0, x1 + 1):
                k = (x - x0) / max(1, x1 - x0)
                o.vline(x, y0, y1 - y0 + 1, 'y' if k < 0.12 else ('a' if k < 0.55 else ('u' if k < 0.88 else 'n')))
        for y in (14, 20, 26): o.hline(17 if y == 14 else 20, y, 28 if y == 14 else 23 if y == 20 else 14, 'u'); 
        o.hline(14, 9, 36, 'u') if False else None
        for (x, y) in ((20, 11), (43, 11), (24, 17), (39, 17), (31, 22)): o.put(x, y, 'H' if (x + y) % 2 else 'y')
        o.hline(15, 8, 34, 'y'); o.hline(15, 9, 34, 'u')                               # the lip
        o.rect(19, 9, 26, 2, 'D')
        if on:
            flame_mass(o, 19, 44, 8, 8, i, 0.6)
            o.hline(19, 9, 26, 'o'); o.hline(22, 9, 20, 'y'); o.hline(28, 9, 8, 'H')
        else:
            o.hline(21, 9, 22, 'E'); o.hline(25, 9, 14, 'W')
        brass_band(o, 15, 14, 34, 1) if False else None
        o.rect(28, 26, 8, 2, 'D')
    def core(self, c, on, i):
        mat(c, 1, 1, 62, 30, GUN); c.hline(1, 1, 62, 'M') if False else None
        c.rect(28, 0, 8, 3, 'a'); c.vline(28, 0, 3, 'y'); c.vline(35, 0, 3, 'u'); c.hline(27, 3, 10, 'y'); c.hline(27, 4, 10, 'u')       # the tube stub through the collar
        recess(c, 4, 7, 22, 14, 'D', 'K')                                              # the furnace window
        c.hline(3, 6, 24, 'y'); c.hline(3, 21, 24, 'u'); c.vline(3, 6, 16, 'y'); c.vline(26, 6, 16, 'u')
        if on: flame_mass(c, 5, 24, 20, 9, i, 0.5)
        else:
            for x in range(6, 24, 3): c.put(x, 19, 'n'); c.put(x + 1, 18, 'E')
        for k, gx in enumerate((38, 47, 56)):                                         # gauges
            gauge(c, gx, 11, 3, on, (i + k) % 4 if on else 0)
        c.hline(33, 17, 28, 'u'); c.hline(33, 18, 28, 'y')
        for bx in (36, 45, 54): c.vline(bx, 17, 2, 'M')
        pipe_h(c, 28, 24, 33, 2, 'a', False)
        # lower: repair hatch (left) and power coupling (centre)
        mat(c, 5, 22, 17, 8, BRASS); hollow(c, 8, 24, 11, 4, 'u'); c.put(10, 26, 'y' if on else 'u')
        for (x, y) in ((7, 24), (19, 24)): c.put(x, y, 'L')
        mat(c, 27, 21, 12, 9, DIRON)
        circle(c, 33, 26, 3.4, 'D'); ring(c, 33, 26, 2.4, 4.0, 'g' if on else 'W')
        for vy in (22, 25, 28): c.hline(44, vy, 15, 'D')
        for q, x in enumerate((46, 50, 54, 58)): c.put(x, 29, 'o' if on and (q + i) % 2 else ('r' if on else 'E'))
    def hurt_out(self, o, i):
        for (x, y) in ((16, 8), (17, 8), (16, 9), (17, 9), (16, 10), (18, 8)): o.erase(x, y)
        o.stamp(8, 4, art("KKKK.\nKyaaK\n.KuK.")) if False else None
        crack(o, [(30, 13), (32, 17), (31, 21), (33, 25)], 'M')
        o.stamp(1, 12, art("KKKK.\nKyaaK\n.KuuK"))
        crack(o, [(55, 20), (56, 24)], 'M')
        o.put(40 + i, 6, 'o'); o.put(41, 5 - i, 'y')
    def wreck_out(self, o):
        shift_rect(o, 14, 52, 7, 29, 0, 2); o.hline(15, 9, 34, 'K')
        crack(o, [(22, 12), (26, 16), (25, 22), (29, 27)], 'M'); crack(o, [(40, 11), (38, 17), (41, 24)], 'M')
        o.stamp(4, 20, art("KKK.\nKyuK\n.KKK")); o.stamp(54, 22, art("KK.\nKuK"))
        for (x, y) in ((28, 20), (35, 21)): o.put(x, y, 'K')
    def hurt_core(self, c, i):
        crack(c, [(14, 7), (13, 11), (15, 15), (12, 20)], 'M'); c.put(14, 11, 'o' if i else 'y')
        gauge(c, 47, 11, 3, False, 0); crack(c, [(46, 9), (48, 12)], 'K')
        spark(c, 33, 25, False) if i == 0 else spark(c, 56, 20, False)
        for q in (1, 3): c.rect(44 + 4 * q + 2, 29, 1, 1, 'E')
    def wreck_core(self, c):
        crack(c, [(14, 7), (13, 11), (15, 15), (12, 20)], 'M'); crack(c, [(35, 5), (37, 13), (40, 20), (38, 28)], 'M')
        c.stamp(41, 6, art("KKKK.\nKDDDK\n.KDKK")); wire(c, [(30, 22), (33, 26), (36, 27)], 'u')
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        inten = [0.8, 1.0, 0.9][i % 3]
        glow_xy(g, ox + 32, oy + 4, 22, 34, ORANGE, 0.55 * inten * k, 1.8)
        glow_xy(g, ox + 32, oy + 5, 11, 15, YEL, 0.5 * inten * k, 1.6)
        for x0 in (7, 54): glow(g, ox + x0, oy + 14, 7, ORANGE, 0.45 * inten * k, 1.8)
    def glow_core(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        b = oy + 4
        glow(g, ox + 15, b + 14, 12, ORANGE, 0.45 * k, 1.8, sx=1.3)
        glow(g, ox + 33.5, b + 26.5, 4, GREEN, 0.4 * k, 2.0)
        for q, x in enumerate((46, 50, 54, 58)):
            if (q + i) % 2: glow(g, ox + x + .5, b + 29.5, 3.5, ORANGE, 0.4 * k, 2.0)

class FurnaceCore(LK.LComp):
    id = 'emberkin_furnace_core'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    notes = ('Emberkin "Furnace Core" reactor: a gunmetal body in a riveted brass frame round a big arched furnace door full of live flame (4-frame flicker), four brass corner stacks with pilot lights chasing round, '
             'navy enamel plates north and south, pressure gauges east and west, and feed pipes. '
             'Damaged: the door ring dented with fire spilling out of the crack, the NE stack leaning and burning crooked, a gauge cracked. Disabled: cold ash in the door, the door buckled, a stack fallen, soot streaks.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 62, 62, 'W', 6); rim(s, 'W', 'S', 'E')
        chamfer_fill(s, 4, 4, 56, 56, 'E', 5)
        for t in range(2, 62, 6): s.put(t, 2, 'y'); s.put(t, 61, 'u'); s.put(2, t, 'y'); s.put(61, t, 'u')
        for (x, y, w, h) in ((22, 5, 20, 5), (22, 54, 20, 5)): navy(s, x, y, w, h); s.hline(x + 2, y + 2, w - 4, 'y' if on else 'W')
        for (cx, cy) in ((8, 32), (56, 32)): gauge(s, cx, cy, 4, on, (i + (cx > 30)) % 4 if on else 0)
        for (x, y) in ((8, 8), (49, 8), (8, 49), (49, 49)):                         # corner stacks
            mat(s, x, y, 8, 8, BRASS); s.rect(x + 2, y + 2, 4, 4, 'D')
            k = ((x > 30) + 2 * (y > 30))
            lit = on and (k + i) % 4 == 0
            if on: s.put(x + 3, y + 3, 'o'); s.put(x + 4, y + 4, 'y' if lit else 'r'); s.put(x + 3, y + 4, 'y' if lit else 'o')
            s.put(x + 1, y + 1, 'H')
        for (a, b) in (((15, 12), (22, 18)), ((48, 12), (41, 18)), ((15, 52), (22, 46)), ((48, 52), (41, 46))): line(s, a[0], a[1], b[0], b[1], 'a'); line(s, a[0], a[1] + 1, b[0], b[1] + 1, 'u')
        circle(s, 32, 32, 20, 'u'); circle(s, 32, 32, 19, 'a'); circle(s, 32, 32, 18, 'y'); ring(s, 32, 32, 16, 17.5, 'a')       # the furnace door: brass ring
        for y in range(10, 54):
            for x in range(10, 54):
                if s.get(x, y) == 'y' and (x - 32) + (y - 32) > 8: s.put(x, y, 'a')
        for (x, y) in ((32, 13), (32, 50), (13, 32), (50, 32), (19, 19), (44, 19), (19, 44), (44, 44)): s.put(x, y, 'H')
        circle(s, 32, 32, 15, 'D')
        if on:
            win = Spr(64, 64); circle(win, 32, 32, 14.4, 'X')
            tmp = Spr(64, 64)
            flame_mass(tmp, 18, 46, 46, 22 + (i % 2), i, 0.55)
            flame_mass(tmp, 24, 40, 46, 26 - (i % 2) * 2, i + 1, 0.8)
            for yy in range(64):
                for xx in range(64):
                    if win.g[yy][xx] == 'X' and tmp.g[yy][xx] != '.': s.g[yy][xx] = tmp.g[yy][xx]
        else:
            for (x, y) in ((24, 40), (30, 43), (38, 41), (33, 38), (28, 36)): s.rect(x, y, 3, 2, 'E')
            for (x, y) in ((26, 42), (35, 40)): s.put(x, y, 'r')
        return s
    def hurt(self, s, i):
        for (x, y) in ((48, 22), (49, 22), (49, 23), (50, 23), (50, 24), (49, 24)): s.erase(x, y)
        crack(s, [(48, 25), (45, 29), (47, 33)], 'K')
        for (x, y) in ((50, 24), (51, 25), (50, 26)): s.put(x, y, 'o' if (x + y + i) % 2 else 'y')
        move(s, 49, 8, 8, 8, 2, 1 + i); s.put(53, 7 - i, 'o'); s.put(54, 6, 'y')
        gauge(s, 8, 32, 4, False, 0); crack(s, [(6, 30), (9, 33)], 'K')
        spark(s, 55, 14, False) if i == 0 else spark(s, 12, 20, False)
    def wreck(self, s):
        crack(s, [(3, 10), (8, 15), (12, 20), (14, 27)], 'K'); crack(s, [(60, 50), (54, 54), (50, 59)], 'K')
        s.stamp(47, 6, art("KKKKK.\nKaayyK\n.KuuKK")); s.stamp(10, 14, art("KKK\nKSK\n.KK"))
        for (a, b) in (((22, 10), (26, 18)), ((40, 8), (38, 20)), ((12, 40), (16, 52))): line(s, a[0], a[1], b[0], b[1], 'D')
        s.stamp(36, 40, art("KKKK.\nKDDDK\n.KDKK")); fallen_chunk(s, 50, 52)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.85)
        glow(g, ox + 32, oy + 36, 26, ORANGE, (0.3 + 0.03 * (i % 2)) * k, 1.4)
        glow(g, ox + 32, oy + 40, 12, YEL, 0.35 * k, 1.6)
        for (x, y) in ((12, 12), (53, 12), (12, 53), (53, 53)):
            kk = (x > 30) + 2 * (y > 30)
            glow(g, ox + x, oy + y, 6 if (kk + i) % 4 == 0 else 4, ORANGE, 0.5 * k, 2.0)
        if flick is not None: glow(g, ox + 50, oy + 24, 5, YEL, 0.5 if flick else 0.25, 2.0)

class HearthShield(ShieldBase):
    id = 'emberkin_hearth_shield'
    DMG = (3, 6)
    GLOW = BLUE
    notes = ('Emberkin "Hearth Shield" (+1 layer while the room is hot): a gunmetal frame with a brass ring and four brass pylons topped with flame lamps, and in the middle a brass hearth bowl with a live flame '
             'under the dome. On loop (8): blue emitter segments turn round the hearth, arcs crawl between the pylons, the pylon flames take turns, the hearth flame flickers. hit (3): flare and ripple. recharge (4): the rings spin up. '
             'Damaged: the brass ring cracked, the west pylon dead, a flap hangs off the lower-right corner. Disabled: the bowl cold and split, the west pylon smashed, casing split.')
    def static(self, s, on):
        chamfer_fill(s, 1, 1, 61, 61, 'W', 6); rim(s, 'W', 'S', 'E')
        chamfer_fill(s, 4, 4, 55, 55, 'E', 5)
        circle(s, 32, 32, 26, 'u'); circle(s, 32, 32, 25, 'a'); ring(s, 32, 32, 22, 24, 'u')
        for y in range(5, 60):
            for x in range(5, 60):
                if s.get(x, y) == 'a' and (x - 32) + (y - 32) < -14: s.put(x, y, 'y')
        circle(s, 32, 32, 21.5, 'W'); circle(s, 32, 32, 20, 'E')
        for (x, y, w, h) in PYL:
            mat(s, x, y, w, h, BRASS); s.rect(x + w // 2 - 2, y + h // 2 - 2, 4, 4, 'D')
        for (x, y) in ((8, 8), (55, 8), (8, 55), (55, 55)): s.put(x, y, 'y')
        circle(s, 32, 32, 10, 'u'); circle(s, 32, 32, 9, 'a'); circle(s, 32, 32, 7.5, 'D')       # the hearth bowl
        for (x, y) in ((24, 24), (40, 24), (24, 40), (40, 40)): s.put(x, y, 'y')
        if not on:
            circle(s, 32, 32, 5, 'E'); s.put(30, 31, 'W'); s.put(33, 34, 'n'); s.put(34, 30, 'n')
            for (x, y, w, h) in PYL: s.put(x + w // 2 - 1, y + h // 2 - 1, 'W')
    def dyn(self, s, i, spin=1.0, dim=False, rj=0):
        hot = (i // 2) % 4
        for k, (x, y, w, h) in enumerate(PYL):
            cx, cy = x + w // 2 - 2, y + h // 2 - 2
            s.rect(cx, cy, 4, 4, 'o'); s.put(cx + 3, cy + 3, 'r')
            if k == hot and not dim: s.put(cx, cy, 'y'); s.put(cx + 1, cy, 'H'); s.put(cx, cy + 1, 'y'); s.put(cx + 1, cy + 1, 'y')
            else: s.put(cx, cy, 'y' if not dim else 'o'); s.put(cx + 1, cy + 1, 'o')
        seg_ring(s, 32, 32, 14.5, 17.4, 8, .56, i * 5.625 * spin, 'b' if not dim else 'W', 'c' if not dim else 'M')
        seg_ring(s, 32, 32, 11.2, 13.2, 6, .55, -i * 7.5 * spin, 'c' if not dim else 'S', 'H' if not dim else 'M', -1)
        if not dim:
            def clip(x, y): return (x - 31.5) ** 2 + (y - 31.5) ** 2 < 7.2 ** 2
            flame_mass(s, 26, 37, 38, 9 + (BR[i % 8] - 4), i, 0.7, clip=clip)
        else:
            def clip(x, y): return (x - 31.5) ** 2 + (y - 31.5) ** 2 < 7.2 ** 2
            flame_mass(s, 28, 35, 38, 3 + rj * 2, rj, 0.8, clip=clip)
        if not dim:
            for k in range(4): arc(s, TIPS[k], CORN[k], TIPS[(k + 1) % 4], i, k, 'b', 'c', 'H')
        else: arc(s, TIPS[rj % 4], CORN[rj % 4], TIPS[(rj + 1) % 4], rj, 0, 'b', 'c', 'H', nframes=4)
    def glow_extra(self, g, ox, oy, i, k, flick=None):
        glow(g, ox + 32, oy + 32, 10, ORANGE, 0.5 * k, 1.8)
        for kk, (x, y) in enumerate(((32, 5), (55, 32), (32, 59), (9, 32))):
            if flick is not None and kk == 3: continue
            hot = kk == (i // 2) % 4
            glow(g, ox + x, oy + y, 7 if hot else 4.5, ORANGE, (0.6 if hot else 0.35) * k, 2.0)
    def hurt(self, s, i):
        crack(s, [(23, 21), (26, 25), (25, 29), (30, 32), (31, 37), (36, 41)], 'y')
        s.rect(3, 29, 9, 6, 'D'); hollow(s, 3, 29, 9, 6, 'K'); s.put(6, 31, 'W'); s.put(5, 32, 'M'); s.put(8, 30 - i, 'o')
        s.stamp(46, 44, art("KKKK..\nKSMSK.\nKWSMSK\n.KKSWK\n...KKK")); s.stamp(54, 46, art(".K\nKD"))
        for (x, y) in ((17, 21), (18, 21), (18, 20), (19, 20)): s.put(x, y, 'K')
        stamp_on(s, 44, 12, SCORCH_S)
        s.put(30 + 5 * i, 28, 'y'); s.put(37, 33 - i, 'H' if i else 'y')
    def wreck(self, s):
        s.stamp(21, 21, art("..KKKKKKKK..\n.KDDKDDDDDK.\nKDDDDKDDDDDK\nKDKDDDDKDDDK\nKDDDKDDDDKDK\nKDDKDDKDDDDK\n.KDDDDDDKDK.\n..KKKKKKKK.."))
        crack(s, [(3, 4), (8, 8), (12, 14), (17, 19)]); crack(s, [(60, 60), (55, 55), (49, 52), (44, 48)])
        s.rect(3, 29, 9, 6, 'K'); s.stamp(4, 30, art("DD.D\n.DDK")); s.stamp(8, 33, art("K.K\nKSK"))
        s.stamp(46, 44, art("KKKK..\nKSWSK.\nKWSWSK\n.KKSWK")); stamp_on(s, 40, 12, SCORCH_L)

COMPONENTS = [Half2(PyreDrive(), 'core'), Half2(PyreDrive(), 'out'), FurnaceCore, HearthShield]


# ================================================================== PROJECTILES AND IMPACTS (fire plumes, embers)
def _fire_beam():
    """8 wide x 16 tall flame stream that tiles along y: ragged edges, a white core, embers; the ragged phase moves per frame."""
    out = []
    for f in range(3):
        t = Spr(8, 16)
        for y in range(16):
            hw = 3.2 + 0.9 * math.sin(2 * math.pi * (2 * y + 5 * f) / 16) + 0.5 * math.sin(2 * math.pi * (3 * y + 7 * f) / 16)
            for x in range(8):
                d = abs(x - 3.5)
                if d > hw: continue
                c = 'H' if d < 1.0 else ('y' if d < 2.0 else ('o' if d < 3.0 else 'r'))
                t.put(x, y, c)
        for (x, y) in (((1 + 3 * f) % 8, 3 + 5 * f), ((6 + 2 * f) % 8, 11 - 3 * f)): 
            if t.get(x, y) == '.': t.put(x, y, 'y')
        out.append(t)
    return out

def _fire_impact():
    f = []
    s = Spr(20, 20); disc(s, 10, 10, 7, 'o'); disc(s, 10, 10, 5.5, 'y'); disc(s, 10, 10, 3, 'H'); rays(s, 10, 10, 10, 7, 9, 'yo', 0.1)
    f.append(s)
    s = Spr(20, 20)
    for k, (dx, dy, h) in enumerate(((-5, 3, 6), (-2, 4, 9), (2, 4, 8), (5, 3, 5), (0, 5, 11))): flame(s, 10 + dx - 1, 14 - 0 + (0 if k != 4 else 1), h, 3, k)
    disc(s, 10, 14, 3.5, 'o'); disc(s, 10, 14, 2, 'y'); dots(s, 10, 10, 8, 8, 'y', 0.3)
    f.append(s)
    s = Spr(20, 20)
    for k, (dx, h) in enumerate(((-4, 5), (0, 7), (4, 4))): flame(s, 10 + dx - 1, 15, h, 3, k + 1)
    disc(s, 10, 15, 2.5, 'r'); dots(s, 10, 11, 8, 10, 'o', 0.2); dots(s, 10, 11, 6, 6, 'y', 0.6)
    f.append(s)
    s = Spr(20, 20); flame(s, 9, 15, 3, 3, 2); dots(s, 10, 13, 5, 6, 'r', 0.4); dots(s, 10, 12, 7, 8, 'o', 0.1, 2); s.put(10, 14, 'o')
    f.append(s)
    return f

def _cinder():
    out = []
    for k in range(4):
        s = Spr(9, 18)
        s.stamp(1, 0, art("""
..oooo..
.oyyyyo.
oyHHyyyo
oyyyyoyo
oyynyyyo
.oyyyyo.
..orro..
"""))
        for (x, y) in ((3, 3), (6, 4)): s.put(x + 1, y + 0, 'n') if k % 2 == 0 else s.put(x + 1, y + 1, 'n')
        tmp = Spr(9, 12); flame(tmp, 3, 11, 9 + (k % 2), 3, k); flame(tmp, 1, 11, 6 - (k % 3), 3, k + 1) ; flame(tmp, 5, 11, 5 + (k % 2), 3, k + 2)
        tmp = flipv(tmp)
        for yy in range(12):
            for xx in range(9):
                if tmp.g[yy][xx] != '.' and s.g[7 + yy - 1 if False else 6 + yy][xx] == '.' and 6 + yy < 18: s.g[6 + yy][xx] = tmp.g[yy][xx]
        for (x, y) in (((k * 3) % 9, 13 + (k % 2)), ((k * 5 + 2) % 9, 16)): s.put(x, y, 'y')
        out.append(s)
    return out

def _cinder_impact():
    f = []
    s = Spr(24, 24); disc(s, 12, 12, 8, 'o'); disc(s, 12, 12, 6.5, 'y'); disc(s, 12, 12, 4, 'H'); rays(s, 12, 12, 10, 8, 11, 'yo', 0.2)
    f.append(s)
    s = Spr(24, 24); disc(s, 12, 17, 7, 'r'); disc(s, 12, 17, 6, 'o'); disc(s, 12, 17, 3.5, 'y')
    for (dx, h, i) in ((-6, 8, 0), (-3, 12, 1), (0, 15, 2), (3, 11, 0), (6, 7, 1)): flame(s, 12 + dx - 1, 16, h, 3, i)
    dots(s, 12, 11, 10, 10, 'y', 0.2, 2)
    f.append(s)
    s = Spr(24, 24); disc(s, 12, 19, 5, 'r'); disc(s, 12, 19, 3.5, 'o')
    for (dx, h, i) in ((-5, 6, 1), (-1, 10, 2), (3, 8, 0)): flame(s, 12 + dx - 1, 19, h, 3, i)
    dots(s, 12, 11, 11, 12, 'o', 0.1, 2); dots(s, 12, 12, 8, 8, 'y', 0.7)
    f.append(s)
    s = Spr(24, 24); flame(s, 8, 20, 4, 3, 0); flame(s, 14, 20, 3, 3, 1); disc(s, 12, 21, 3, 'r'); dots(s, 12, 14, 8, 8, 'r', 0.2); dots(s, 12, 13, 5, 5, 'o', 0.5)
    f.append(s)
    return f

def _flare():
    out = []
    star = [art("""
...y...
...y...
..yHy..
yyHHHyy
..yHy..
...y...
...y...
"""), art("""
.......
..y.y..
...H...
.yHHHy.
...H...
..y.y..
......."""), art("""
...o...
...y...
..yHy..
ooyHyoo
..yHy..
...y...
...o...
""")]
    for k in range(3):
        s = Spr(7, 17); s.stamp(0, 0, star[k])
        tail = [("...o...", "..ror..", "..r.r.."), ("...y...", "...o...", "..o.r.."), ("..ror..", "...o...", "...r...")][k]
        for j, row in enumerate(tail):
            for i, c in enumerate(row):
                if c != '.': s.put(i, 8 + j, c)
        for (x, y) in (((k * 2 + 1) % 7, 12 + k), ((k * 3 + 4) % 7, 14)): s.put(x, y, 'o' if k != 1 else 'y')
        out.append(s)
    return out

def _flare_impact():
    f = []
    s = Spr(16, 16); disc(s, 8, 8, 4, 'H'); rays(s, 8, 8, 8, 4, 7, 'Hyo', 0.0); rays(s, 8, 8, 8, 4, 6, 'yo', 0.39)
    f.append(s)
    s = Spr(16, 16); disc(s, 8, 8, 2.5, 'H'); rays(s, 8, 8, 8, 3, 7, 'yo', 0.2); ring(s, 8, 8, 5, 6.2, 'y')
    f.append(s)
    s = Spr(16, 16); disc(s, 8, 8, 1.5, 'y'); dots(s, 8, 8, 6, 8, 'o', 0.2); dots(s, 8, 8, 4, 6, 'y', 0.5, 2)
    f.append(s)
    return f

PROJECTILES = [
    Proj('emberkin_pyre_lance', _fire_beam(), _fire_impact(), (4, 0), (4, 15), fps=12, ifps=12, pad=5, ipad=5, tile=True, bands=((1.5, 100), (3.2, 50), (5.0, 22)),
         notes='A stream of flame, 8 wide x 16 tall, tiling along y (joins seamlessly, glow too): red edge, orange body, yellow band, white core, ragged edges that crawl over 3 flicker frames. Draw it from the lance to the hit.',
         inotes='Where the lance lands: a white-yellow flash, then flame tongues standing up with embers and a trail of small fires (4 frames, 20x20); it sets fires.'),
    Proj('emberkin_cinder_mortar', _cinder(), _cinder_impact(), (5, 3), (5, 17), fps=12, ifps=10, pad=4, ipad=5, bands=((1.5, 110), (3.2, 54), (5.0, 24)),
         notes='An incendiary cinder shell, 9x18: a glowing coal ball with dark clinker flecks and a flame plume streaming behind it with embers (4 frames).',
         inotes='A fireball: flash, a boiling flame ball with tongues, falling embers, small fires left burning (4 frames, 24x24).'),
    Proj('emberkin_flare_turret', _flare(), _flare_impact(), (3, 3), (3, 11), fps=14, ifps=14, pad=5, ipad=5, bands=((2.0, 120), (4.0, 64), (6.5, 28)),
         notes='A signal flare, 7x17: a white-yellow four-pointed star that pulses over 3 frames, trailing orange sparks. Its glow is deliberately large: it blinds.',
         inotes='A blinding burst: a white disc with long rays, a ring, fading sparkles (3 frames, 16x16).'),
]
