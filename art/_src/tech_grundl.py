"""Grundl racial tech (docs/waves/racial_tech_1.md): freight-hauler metal. Huge, heavy, riveted plates with rows of big rivets, corrugated panels, rust streaks, amber stencils and hanging chains with hooks.
Weapons: grundl_slug_mortar (fixed), grundl_grapple_harpoon (fixed), grundl_barge_flak (turret). Components: grundl_hauler_thrusters (engine, two halves), grundl_freight_shield, grundl_cargo_deck."""
from tech_kit import *
from lines_kit import LComp, crack as lcrack, line as lline, circle as lcircle, ring as lring
from lines_eng_base import EngBase, Half2
from comp_base import stamp_on, SCORCH_S, SCORCH_L
from comp_w_scrap import FLASH_BIG

HT = ('S', 'W', 'E'); HT2 = ('W', 'E', 'D')                        # dark gunmetal: heavier and dirtier than the Concord steel
DK = {'a': 'u', 'y': 'a', 'g': 'E', 'b': 'E', 'c': 'E'}
SLUG = {'o': 'o', 'y': 'y'}

def corrugate(s, x, y, w, h, hi='M', mid='S', lo='W'):
    """a corrugated freight panel: vertical ribs, light on the left of each, dark on the right."""
    for k in range(w):
        c = hi if k % 3 == 0 else (mid if k % 3 == 1 else lo)
        s.vline(x + k, y, h, c)
    s.hline(x, y, w, 'E'); s.hline(x, y + h - 1, w, 'E')

def amber_band(s, x, y, w, h=4, on=True, tag=0):
    """the amber freight-company band with dark stencil marks."""
    s.rect(x, y, w, h, 'a' if on else 'u'); s.hline(x, y, w, 'y' if on else 'a'); s.hline(x, y + h - 1, w, 'u' if on else 'n')
    for k in range(3, w - 3, 5): s.put(x + k, y + 1, 'n'); s.put(x + k + 1, y + 2 if h > 3 else y + 1, 'n'); s.put(x + k + 2, y + 1, 'n') if (k + tag) % 2 else None

def rust_streak(s, x, y, n, c='u'):
    for k in range(n): s.put(x + (k % 2), y + k, c if k % 3 else 'Q')

class GrundlW(RW):
    HT = HT; FT = HT; CH = ('y', 'a', 'g'); DK = DK
    def flange_trim(self, s, st, half, y):
        for x in (4, 13, 50, 59): s.put(x, y + 2, 'L'); s.put(x + 1, y + 2, 'M')
        for x in range(8, 58, 8): s.put(x, y + 1, 'E'); s.put(x, y + 3, 'E')
        amber_band(s, 24, y + 1, 16, 3, st.powered)
    def rhousing(self, s, y0, col=True):
        super().rhousing(s, y0, col)
        rivet_row(s, 4, y0 + 3, 14, 4); rivet_row(s, 4, y0 + 27, 14, 4)
        rust_streak(s, 8, y0 + 4, 8); rust_streak(s, 55, y0 + 8, 7)
    def ggun(self, s, bw=30, cy=12):
        x0, top = self.rgun_housing(s, cy, bw, 26)
        rivet_row(s, x0 + 3, top + 17, 6, 4); rivet_row(s, 8, 29, 12, 4)
        rust_streak(s, x0 + 4, top + 8, 7); rust_streak(s, x0 + bw - 6, top + 10, 6)
        bev(s, x0 + bw - 10, top + 14, 7, 8, 'Q', 'u', 'n', cham=False); rivet(s, x0 + bw - 9, top + 15); rivet(s, x0 + bw - 6, top + 19)
        return x0, top

# ============================================================ SLUG MORTAR (fixed, huge)
class SlugMortar(GrundlW):
    id = 'grundl_slug_mortar'; aim = 'fixed'
    blen, bwid = 58, 27
    bpivot = (7, 13)
    bmuzzle = (42, 13)
    out_notes = ('OUTSIDE half of the Grundl Slug Mortar (a FIXED gun, freight metal): a very wide riveted housing, a rack of two fat slugs on the left that a chain holds, a corrugated plate and a hoist arm with a swaying chain and hook on the right, amber stencils and rust streaks. '
                 'damaged: the chain is snapped and a slug loose, the hoist bent; disabled: scorched, dented, plates sprung, the rack empty, never destroyed.')
    notes = ('INSIDE half of the Grundl Slug Mortar: a heavy breech block with a round slug in it, a ribbed feed chute to the right (the ammo rack sits beside it), a big hatch with rivets, power coupling and five amber lamps. '
             'charge: a slug rolls in from the chute (frame 5 = seated and ready, lamps green); fire: the breech is empty. damaged: a lamp dead, the chute dented and leaking, sparks; disabled: a slug jammed half-way in the chute. '
             'Barrel layer grundl_slug_mortar_barrel: a massive banded barrel with rows of big rivets and a heavy muzzle ring; fire: a huge flash and recoil.')
    NOSE = [None, 44, 38, 32, 26, 20]
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.ggun(s)
        bev(s, 2, 6, 17, 21, *HT2)                                                  # left: the slug rack
        for sy in (8, 17):
            lcircle(s, 10, sy + 4, 4.4, 'u'); lcircle(s, 10, sy + 4, 3.4, 'Q'); s.put(8, sy + 2, 'a'); s.put(9, sy + 2, 'y'); s.hline(6, sy + 4, 8, 'n')
        chain(s, [(4, 8), (4, 14), (5, 18)]); chain(s, [(16, 8), (16, 14), (15, 18)])
        rivet_row(s, 3, 24, 4, 4)
        bev(s, 45, 6, 17, 21, *HT2); corrugate(s, 47, 8, 13, 10)                    # right: a corrugated plate and a hoist
        sway = (0, 1)[i] if pw else 0
        thick(s, 55, 18, 55, 12, 2, 'M', 'L', 'W'); thick(s, 55, 12, 49, 10, 2, 'M', 'L', 'W')
        chain(s, [(49, 11), (49 + sway, 15), (49, 19)]); s.rect(48, 19, 3, 2, 'a'); s.put(48, 21, 'L'); s.put(50, 21, 'L')
        amber_band(s, 46, 22, 15, 3, pw)
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        self.rhousing(s, y)
        coupling(s, 3, y + 2, st, 'y'); hatch(s, 3, y + 16, st, 9, 8)
        bev(s, 14, y + 5, 34, 15, 'W', 'E', 'D', cham=False)                         # the breech
        s.hline(15, y + 6, 32, 'S'); s.hline(15, y + 18, 32, 'W'); rivet_row(s, 16, y + 7, 8, 4)
        for bx in (22, 30, 38): s.vline(bx, y + 9, 8, 'E')
        bev(s, 48, y + 5, 15, 15, 'S', 'E', 'D')                                     # the feed chute
        s.rect(51, y + 8, 12, 9, 'D'); s.hline(51, y + 8, 12, 'K'); s.hline(51, y + 17, 12, 'M')
        for k in range(2): s.put(55 + 4 * k, y + 12, 'a'); s.put(56 + 4 * k, y + 12, 'y')
        nose = {'on': 17, 'off': 17, 'damaged': 17, 'charge': self.NOSE[st.i] if st.charge else None, 'disabled': 35}.get(st.state)
        if nose is not None:
            for dx in range(9):                                                      # the slug: a fat round shell
                for dy in range(9):
                    if (dx - 4) ** 2 + (dy - 4) ** 2 <= 17 and 15 <= nose + dx <= 61: s.put(nose + dx, y + 7 + dy, 'u' if dx + dy > 9 else ('Q' if dx + dy > 6 else 'y'))
            s.put(nose + 3, y + 9, 'H') if 15 <= nose + 3 <= 61 else None
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        s.rect(3, 7, 3, 12, '.'); chain(s, [(4, 8), (4, 12)]); chain(s, [(7, 20), (9, 24), (7, 26)])
        s.put(5 + st.i, 14, 'M')
        s.rect(46, 4, 16, 5, '.'); thick(s, 55, 18, 55, 14, 2, 'M', 'L', 'W'); thick(s, 55, 14, 60, 11, 2, 'M', 'L', 'W')
        crack(s, [(31, 4), (30, 8), (32, 11), (30, 14)]); spark(s, 52, 9, False) if st.i else spark(s, 14, 6, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 4), (30, 8), (32, 11), (30, 14), (31, 19)], [(52, 8), (53, 12), (51, 16)]], dents=[(46, 20, 6, 4), (6, 20, 6, 3)],
                 soots=[(22, 3, 0), (46, 5, 1), (4, 8, 2)], wires_=[], sparks=[(24, 8), (54, 6)])
        s.rect(3, 7, 15, 17, 'E'); chain(s, [(5, 8), (7, 14), (6, 22)], 'W', 'E', 'D'); s.rect(5, 24, 7, 3, 'n')
        s.rect(46, 4, 16, 5, '.')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(50, y + 5), (52, y + 9), (51, y + 14)]); dent(s, 55, y + 17, 5, 3)
        for k in range(3): s.put(58, y + 20 + (k * 2 + st.i) % 5, 'o')
        spark(s, 52, y + 10, False) if st.i == 0 else spark(s, 10, y + 20, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(50, y + 5), (52, y + 9), (51, y + 14), (53, y + 18)]); crack(s, [(24, y + 7), (26, y + 11), (25, y + 16)])
        wire(s, [(14, y + 21), (17, y + 23), (20, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 8, 3, RGB_['yellow'], 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 53, oy + 23.5, 4, RGB_['amber'], 0.3, 2.0, sx=2.5)
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 14 + o, 3, 24, 21, 'LMMSSSSSWWEE')                                  # the massive barrel
        for bx in (17, 25, 33):
            b.rect(bx + o, 1, 4, 25, 'W'); b.vline(bx + o, 1, 25, 'M'); b.vline(bx + o + 3, 1, 25, 'E')
            rivet(b, bx + o + 1, 3, True); rivet(b, bx + o + 1, 22, True); rivet(b, bx + o + 1, 12, True)
        rust_streak(b, 21 + o, 5, 8); rust_streak(b, 29 + o, 14, 7)
        bev(b, 38 + o, 0, 7, 27, 'M', 'S', 'W'); b.rect(42 + o, 5, 3, 17, 'D'); b.rect(42 + o, 5, 1, 17, 'E')   # the heavy muzzle ring
        rivet(b, 39 + o, 2, True); rivet(b, 39 + o, 23, True)
        if st.fire: b.rect(43 + o, 6, 2, 15, 'o'); b.rect(44 + o, 8, 1, 11, 'H')
        breech(b, 13, 25, *HT)
    def bhurt(self, b, st):
        crack(b, [(20, 4), (21, 12), (19, 20)]); b.rect(25, 1, 4, 3, '.'); chain(b, [(26, 3), (27, 6)])
        move(b, 38, 0, 7, 27, 0, 2); spark(b, 33, 4, False) if st.i == 0 else spark(b, 22, 25, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 32, 2, 3)
    def bwreck(self, b, st):
        b.stamp(36, 10, art("uQ\nnu")); chain(b, [(31, 8), (33, 12), (32, 16)], 'W', 'E', 'D'); crack(b, [(17, 3), (18, 12), (16, 22)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 46, 13, FLASH_BIG)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 46, 13, scale=1.25)
        if state == 'idle': glow(g, ox + 43, oy + 13.5, 5, RGB_['orange'], 0.2, 2.0)

# ============================================================ GRAPPLE HARPOON (fixed)
HARPOON = art("""
.....KK.........
....KMMK........
...KLMSSK.......
..KLMSSSSKKKKKKK
.KLMSSWWWWWWWWWK
..KLMSSSSKKKKKKK
...KLMSSK.......
....KMMK........
.....KK.........
""")
class GrappleHarpoon(GrundlW):
    id = 'grundl_grapple_harpoon'; aim = 'fixed'
    blen, bwid = 60, 19
    bpivot = (6, 9)
    bmuzzle = (44, 9)
    out_notes = ('OUTSIDE half of the Grundl Grapple Harpoon (a FIXED gun, freight metal): a riveted housing with a chain winch drum on the left whose chain coils turn on the loop and a heavy pulley and counterweight on the right, with amber stencils. '
                 'damaged: the chain has jumped the pulley and hangs, the drum is dented; disabled: scorched, dented, the chain snapped and coiled on the deck, never destroyed.')
    notes = ('INSIDE half of the Grundl Grapple Harpoon: a big chain winch drum that winds more chain as it charges (frame 5 = wound and ready, lamps green), a geared motor, hatch with rivets, power coupling and five amber lamps. '
             'fire: the drum is empty and spinning. damaged: the chain has slipped and hangs loose, lamps dead; disabled: the drum jammed, the chain snapped. '
             'Barrel layer grundl_grapple_harpoon_barrel: a long banded launch tube with a barbed harpoon head loaded and its chain running back; fire: the harpoon leaves on its chain.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.ggun(s)
        bev(s, 2, 6, 17, 21, *HT2)                                                  # left: the winch drum
        cylv(s, 5, 8, 11, 17, 'LMSSSWE'); 
        for k in range(8): s.hline(5, 10 + k * 2 + (i if pw else 0) % 2, 11, 'W' if k % 2 else 'E')
        s.rect(4, 7, 13, 2, 'E'); s.rect(4, 24, 13, 2, 'E'); rivet(s, 5, 7); rivet(s, 14, 24)
        chain(s, [(16, 14), (18, 18), (21, 22)])
        bev(s, 45, 6, 17, 21, *HT2)                                                 # right: pulley and counterweight
        lcircle(s, 53, 13, 5, 'M'); lcircle(s, 53, 13, 3.4, 'D'); lcircle(s, 53, 13, 1.5, 'L')
        for k in range(8): a = math.radians(k * 45 + (i * 22 if pw else 0)); s.put(int(round(53 + 4.4 * math.cos(a))), int(round(13 + 4.4 * math.sin(a))), 'L')
        chain(s, [(48, 13), (48, 20)]); bev(s, 46, 20, 5, 5, 'S', 'W', 'E', cham=False)
        amber_band(s, 46, 24, 15, 3, pw)
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'y')
        bev(s, 15, y + 4, 31, 17, 'W', 'E', 'D', cham=False)                          # the winch drum, side on
        wound = {'charge': st.i, 'on': 5, 'damaged': 5, 'off': 5, 'disabled': 2, 'fire': 0}.get(st.state, 5)
        cylh(s, 17, y + 6, 27, 13, 'LMSSSWEE')
        for k in range(27):
            if k % 3 == 0 and k < 4 + wound * 5: s.vline(17 + k, y + 6, 13, 'W'); s.vline(18 + k, y + 6, 13, 'M')
        s.rect(15, y + 5, 3, 15, 'E'); s.rect(44, y + 5, 3, 15, 'E'); rivet(s, 15, y + 7); rivet(s, 44, y + 17)
        lcircle(s, 56, y + 12, 4, 'S'); lcircle(s, 56, y + 12, 2, 'D')                # the motor gear
        for k in range(8): a = math.radians(k * 45 + (i * 20 if pw and st.state != 'off' else 0)); s.put(int(round(56 + 5 * math.cos(a))), int(round(y + 12 + 5 * math.sin(a))), 'M')
        hatch(s, 3, y + 16, st, 9, 8)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        chain(s, [(16, 14), (19, 18), (21, 24), (19, 28)]); dent(s, 6, 12, 8, 5)
        s.rect(49, 12, 3, 9, '.'); chain(s, [(50, 14), (51, 19)]); crack(s, [(53, 7), (52, 11), (54, 16)])
        spark(s, 52, 9, False) if st.i else spark(s, 14, 6, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(31, 4), (30, 8), (32, 11), (30, 14)], [(53, 8), (52, 12), (54, 17)]], dents=[(46, 20, 6, 4), (5, 20, 7, 4)],
                 soots=[(22, 3, 0), (46, 5, 1), (4, 8, 2)], wires_=[], sparks=[(24, 8), (54, 6)])
        s.rect(4, 8, 13, 17, 'E'); chain(s, [(6, 12), (10, 16), (7, 20), (12, 24)], 'W', 'E', 'D')
        s.rect(52, 8, 8, 10, 'E'); lcircle(s, 53, 13, 3, 'E')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        chain(s, [(44, y + 12), (47, y + 16), (46, y + 21), (44, y + 24)]); dent(s, 22, y + 8, 6, 4)
        spark(s, 56, y + 8, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(30, y + 6), (31, y + 12), (29, y + 18)]); chain(s, [(44, y + 12), (48, y + 18), (44, y + 23)], 'W', 'E', 'D')
        s.rect(51, y + 8, 10, 9, 'D'); wire(s, [(14, y + 22), (17, y + 24), (22, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['yellow'], 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy): glow(g, ox + 53, oy + 25.5, 4, RGB_['amber'], 0.3, 2.0, sx=2.5)
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 13 + o, 3, 26, 13, 'LMMSSSWE')
        for bx in (17, 27):
            b.rect(bx + o, 2, 3, 15, 'W'); b.vline(bx + o, 2, 15, 'M'); rivet(b, bx + o + 1, 3, True); rivet(b, bx + o + 1, 13, True)
        bev(b, 38 + o, 1, 4, 17, 'M', 'S', 'W'); b.rect(40 + o, 5, 2, 9, 'D')
        tail = {'fire': (26, 40, None)}.get(st.state, (30,) * 3)[st.i if st.fire else 0]
        if tail is not None:
            for j, r in enumerate(HARPOON):
                for k, c in enumerate(r):
                    if c != '.' and tail + o + k < b.w - 1: b.put(tail + o + k, 5 + j, c)
            if st.fire: chain(b, [(14 + o, 9), (tail + o - 1, 9)], 'M', 'W', 'E')
        else:
            chain(b, [(14 + o, 9), (46 + o, 9)], 'M', 'W', 'E')
        breech(b, 9, 17, *HT)
    def bhurt(self, b, st):
        crack(b, [(19, 3), (20, 9), (18, 15)]); move(b, 38, 1, 4, 17, 0, 2); b.rect(27, 2, 3, 3, '.'); chain(b, [(28, 4), (29, 8)])
        spark(b, 36, 4, False) if st.i == 0 else spark(b, 22, 17, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 33, 2, 3)
    def bwreck(self, b, st):
        chain(b, [(31, 8), (33, 12), (31, 16)], 'W', 'E', 'D'); b.stamp(36, 9, art("MS\nWE")); crack(b, [(16, 3), (17, 9), (15, 15)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire and st.i == 0: stamp_flash(b, st, 44, 9, FLASH_BIG)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire' and i == 0: fire_glow(g, ox, oy, i, 44, 9, scale=0.8)
        if state == 'idle': glow(g, ox + 40, oy + 9.5, 3, RGB_['amber'], 0.25, 2.0)

# ============================================================ BARGE FLAK (turret)
class BargeFlak(GrundlW):
    id = 'grundl_barge_flak'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 46, 27
    bpivot = (8, 13)
    bmuzzle = (34, 13)
    out_notes = ('OUTSIDE half of the Grundl Barge Flak (a TURRET, freight metal): a wide riveted seat, a big ammo drum with a chain belt on the left and a corrugated plate with an amber stencil on the right. '
                 'damaged: the belt has jumped and hangs, a plate sprung; disabled: scorched, dented, the belt snapped, never destroyed.')
    notes = ('INSIDE half of the Grundl Barge Flak: a huge ammo drum with a ribbed feed chute to the right (the ammo rack sits beside it), a heavy gear, hatch, power coupling and five amber lamps. '
             'damaged: the drum dented and the belt slipping; disabled: the drum jammed with a round stuck. The rotating head grundl_barge_flak_barrel swivels in the ring: four fat banded barrels in a riveted cradle with a drum feeding a chain belt, and a sensor lamp; fire: the barrels flash in turn.')
    TUBES = ((2, 'LMSWE'), (8, 'LMSWE'), (14, 'LMSWE'), (20, 'LMSWE'))
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.rturret_seat(s, 15)
        rivet_row(s, 8, 28, 12, 4)
        bev(s, 2, 6, 17, 20, *HT2)
        lcircle(s, 10, 15, 6.4, 'M'); lcircle(s, 10, 15, 5.4, 'W'); lcircle(s, 10, 15, 3, 'E')
        for k in range(8): a = math.radians(k * 45); s.put(int(round(10 + 4.4 * math.cos(a))), int(round(15 + 4.4 * math.sin(a))), 'L')
        s.put(8, 13, 'a'); s.put(9, 13, 'y')
        chain(s, [(15, 18), (18, 21), (22, 21)])
        bev(s, 45, 6, 17, 20, *HT2); corrugate(s, 47, 8, 13, 8); amber_band(s, 46, 20, 15, 4, pw)
        for (x, y) in ((24, 8), (40, 8), (24, 22), (40, 22)): s.put(x, y, 'L')
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'y')
        lcircle(s, 27, y + 12, 8.4, 'M'); lcircle(s, 27, y + 12, 7.4, 'W'); lcircle(s, 27, y + 12, 4, 'E')                # the ammo drum
        for k in range(8): a = math.radians(k * 45 + (i * 11 if pw else 0)); s.put(int(round(27 + 5.6 * math.cos(a))), int(round(y + 12 + 5.6 * math.sin(a))), 'a' if k % 2 else 'y')
        bev(s, 38, y + 5, 25, 15, 'S', 'E', 'D')
        s.rect(41, y + 8, 22, 9, 'D'); s.hline(41, y + 8, 22, 'K'); s.hline(41, y + 17, 22, 'M')
        for k in range(4): s.put(45 + 5 * k, y + 12, 'a'); s.put(46 + 5 * k, y + 12, 'y')
        hatch(s, 3, y + 16, st, 9, 8) if False else None
        rivet_row(s, 16, y + 3, 6, 4)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        s.rect(3, 7, 15, 18, 'E'); lcircle(s, 10, 15, 6.4, 'M'); lcircle(s, 10, 15, 3, 'E'); dent(s, 5, 9, 6, 4)
        chain(s, [(15, 18), (17, 24), (15, 28)]); s.rect(46, 7, 3, 12, '.')
        crack(s, [(53, 8), (52, 12), (54, 17)]); spark(s, 52, 9, False) if st.i else spark(s, 14, 8, False)
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(24, 8), (26, 12), (25, 16)], [(53, 7), (52, 12), (54, 18)]], dents=[(46, 20, 6, 4), (5, 20, 7, 4)],
                 soots=[(20, 3, 0), (46, 5, 1), (4, 8, 2)], wires_=[], sparks=[(30, 6), (12, 10)])
        s.rect(3, 7, 15, 18, 'E'); chain(s, [(6, 10), (10, 16), (7, 22)], 'W', 'E', 'D'); s.rect(46, 6, 3, 14, '.')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        dent(s, 22, y + 5, 7, 5); chain(s, [(36, y + 12), (38, y + 17), (36, y + 22)])
        spark(s, 56, y + 6, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(24, y + 5), (27, y + 12), (25, y + 19)]); lcircle(s, 27, y + 12, 3, 'K'); s.put(27, y + 12, 'a')
        wire(s, [(14, y + 22), (17, y + 24), (22, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['yellow'], 0.5, 2.0)
    def out_glow(self, state, i, g, ox, oy): glow(g, ox + 53, oy + 22, 4, RGB_['amber'], 0.3, 2.0, sx=2.5)
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 12 + o, 1, 5, 25, 'M', 'S', 'W')                                          # the cradle
        for k, (ty, tones) in enumerate(self.TUBES):                                     # four fat barrels
            off = o - (2 if st.fire and st.i == 0 and k in (1, 3) else 0)
            cylh(b, 17 + off, ty + 1, 15, 5, tones)
            b.rect(30 + off, ty, 4, 7, 'W'); b.vline(30 + off, ty, 7, 'M'); b.rect(32 + off, ty + 2, 2, 3, 'D')
            if st.fire and st.i == k % 3: b.rect(32 + off, ty + 2, 2, 3, 'o'); b.put(33 + off, ty + 3, 'H')
        for bx in (21, 26): b.rect(bx + o, 0, 2, 27, 'W'); b.vline(bx + o, 0, 27, 'M'); rivet(b, bx + o, 1); rivet(b, bx + o, 24)
        hazard(b, 23 + o, 0, 2, 27)
        hub(b, 13, 17, 'S', 'M', 'W')
        eye(b, 11, 0, 'y')
    def bhurt(self, b, st):
        b.rect(21, 8, 2, 8, '.'); crack(b, [(17, 2), (18, 9), (16, 16)]); move(b, 30, 14, 4, 7, 0, 2)
        spark(b, 32, 8, False) if st.i == 0 else spark(b, 24, 24, False)
    def bbreak(self, b, st): return cleave(b, lambda y: 27, 2, 3, rows=(2, 25))
    def bwreck(self, b, st):
        b.stamp(32, 6, art("MS\nWE")); crack(b, [(17, 3), (18, 12), (16, 22)], 'K', 'S'); chain(b, [(26, 10), (29, 14), (27, 19)], 'W', 'E', 'D')
    def bafter(self, b, st):
        if st.fire:
            for k, (ty, _) in enumerate(self.TUBES):
                if st.i == k % 3: stamp_flash(b, st, 34, ty + 3, FLASH_S)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            for k, (ty, _) in enumerate(self.TUBES):
                if i == k % 3: fire_glow(g, ox, oy, i, 34, ty + 3, scale=0.6)
        if state != 'disabled': glow(g, ox + 12.5, oy + 1.5, 3, RGB_['yellow'], 0.5, 2.0)
FLASH_S = [art("..o......\n.oyo.....\noyHyoo...\nyHHHHyo..\noyHyoo...\n.oyo.....\n..o......"), art(".o.......\noyo......\nyHyoo....\noyo......\n.o......."), art(".o.....\noyo....\n.o.....")]

# ============================================================ components
class GrundlC(LComp):
    dark = DK
    glow_pad = (10, 10, 10, 10)

def freight_frame(s, x, y, w, h, cham=6):
    chamfer_fill(s, x, y, w, h, 'S', cham); rim(s, 'S', 'M', 'W', (x, y, x + w - 1, y + h - 1))
    for k in range(x + 5, x + w - 5, 7): s.put(k, y + 2, 'L'); s.put(k + 1, y + 3, 'E'); s.put(k, y + h - 4, 'L'); s.put(k + 1, y + h - 3, 'E')

class FreightShield(GrundlC):
    id = 'grundl_freight_shield'; cells = (4, 4)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    notes = ('Grundl Freight Shield, 4x4: a riveted steel frame with corrugated side panels and amber stencil bands, round a blue shield disc held in a cage of heavy bars; four fuel-cell lamps along the bottom (the cells the crew restock) light blue one by one on the 4-frame loop and a chain hangs slack from each top corner. '
             'Off: a dull disc and dark cells. Damaged: a cage bar bent, a chain snapped, a cell dark, the disc stuttering. Disabled: the disc dead, the cage twisted, a plate sprung.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        freight_frame(s, 1, 1, 62, 62, 7)
        corrugate(s, 3, 12, 8, 36); corrugate(s, 53, 12, 8, 36)
        rivet_row(s, 4, 4, 14, 4); rivet_row(s, 4, 58, 14, 4)
        amber_band(s, 14, 5, 36, 4, on); amber_band(s, 14, 55, 36, 4, on, 1)
        chamfer_fill(s, 12, 11, 40, 36, 'E', 10); rim(s, 'E', 'S', 'D', (12, 11, 51, 46))                   # the cage
        chamfer_fill(s, 15, 14, 34, 30, 'D', 9)
        lcircle(s, 32, 29, 12, 'B' if on else 'E'); lcircle(s, 32, 29, 10, 'b' if on else 'W'); lcircle(s, 32, 29, 6, 'c' if on else 'S')
        if on:
            lcircle(s, 32, 29, 3, 'H'); s.put(28, 25, 'H'); s.put(29, 25, 'H')
            lring(s, 32, 29, 12 + (i % 2), 13 + (i % 2), 'c') if False else None
        for bx in (19, 26, 38, 45): s.vline(bx, 14, 30, 'S' if bx < 32 else 'W'); s.vline(bx + 1, 14, 30, 'M' if bx < 32 else 'E')
        s.hline(15, 29, 34, 'S'); s.hline(15, 30, 34, 'W')
        for k in range(4):                                                                       # the fuel-cell lamps
            cx = 14 + k * 9; lit = on and k <= (i + 1) % 4 + 0
            bev(s, cx, 47, 8, 6, 'M', 'S', 'W', cham=False); s.rect(cx + 2, 48, 4, 4, ('c' if lit else 'D')); s.put(cx + 2, 48, 'H' if lit else 'E')
        chain(s, [(7, 9), (7, 16), (8, 22)]); chain(s, [(56, 9), (56, 16), (55, 22)])
        return s
    def hurt(self, s, i):
        for (x, y) in ((22, 20), (23, 21), (24, 22)): s.put(x, y, 'K')
        s.rect(26, 14, 3, 30, '.'); lline(s, 26, 14, 28, 30, 'S'); lline(s, 27, 14, 29, 30, 'M'); lline(s, 28, 30, 25, 44, 'S')
        s.rect(54, 10, 5, 14, 'S'); chain(s, [(56, 10), (57, 14)])
        lcrack(s, [(3, 14), (6, 19), (4, 24), (8, 28)], 'L'); s.stamp(42, 40, art("KKKK.\nKDDDK\n.KDKK"))
        s.rect(41, 48, 8, 4, 'E'); spark(s, 52, 13, False) if i else None
    def wreck(self, s):
        lcrack(s, [(3, 11), (7, 15), (6, 20), (11, 24), (13, 30)], 'M'); lcrack(s, [(50, 49), (54, 47), (57, 52), (60, 55)], 'M')
        lcircle(s, 32, 29, 11, 'D'); lcircle(s, 32, 29, 6, 'E'); s.rect(26, 14, 3, 30, 'E'); lline(s, 38, 14, 36, 44, 'W')
        s.rect(10, 47, 38, 6, 'E'); s.stamp(42, 40, art("KKKK.\nKDDDK\n.KDKK")); s.stamp(6, 45, art("KKK\nKLL\nKLM"))
        chain(s, [(7, 9), (9, 15), (6, 22)], 'W', 'E', 'D')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        glow(g, ox + 32, oy + 29, 24, (79, 163, 255), 0.3 * k, 1.5)
        glow(g, ox + 32, oy + 29, 8, (200, 235, 255), 0.4 * k, 1.8)
        for j in range(4):
            if (i + 1) % 4 >= j: glow(g, ox + 18 + j * 9, oy + 50, 4, RGB_['cyan'], 0.45 * k, 2.0)

class CargoDeck(GrundlC):
    id = 'grundl_cargo_deck'; cells = (4, 4)
    anims = [('on', 'on', 4, 5), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    notes = ('Grundl Cargo Deck, 4x4: a top-down freight hold: hazard-striped lane edges, a stack of crates (brown wood and steel containers with amber stripes), a rack of big shells at the right, a loading hoist whose chain and hook swing on the 4-frame loop, a blinking amber lamp. '
             'Off: dim, the hook at rest. Damaged: a crate toppled and split, the chain bent, a lamp dead. Disabled: crates spilled and dark, the hoist hanging snapped.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        freight_frame(s, 1, 1, 62, 62, 7)
        chamfer_fill(s, 4, 4, 56, 56, 'W', 5)
        for x in range(8, 58, 8): s.vline(x, 5, 54, 'E')
        for y in range(8, 58, 8): s.hline(5, y, 54, 'E')
        hazard(s, 5, 5, 54, 3); hazard(s, 5, 56, 54, 3)
        for (cx, cy, w, h, kind) in ((6, 10, 16, 14, 'w'), (6, 26, 16, 12, 's'), (24, 10, 14, 10, 's'), (24, 22, 14, 14, 'w')):         # crates
            if kind == 'w': bev(s, cx, cy, w, h, 'Q', 'q', 'n', cham=False); s.hline(cx + 1, cy + h // 2, w - 2, 'n'); s.vline(cx + w // 2, cy + 1, h - 2, 'n')
            else: bev(s, cx, cy, w, h, 'M', 'S', 'W', cham=False); corrugate(s, cx + 2, cy + 2, w - 4, h - 4); amber_band(s, cx + 1, cy + h - 5, w - 2, 3, on)
            rivet(s, cx + 1, cy + 1); rivet(s, cx + w - 3, cy + h - 3)
        for k in range(4):                                                                           # a rack of big shells
            sy = 10 + k * 8; lcircle(s, 51, sy + 3, 3.4, 'u'); lcircle(s, 51, sy + 3, 2.4, 'Q'); s.put(50, sy + 2, 'y')
        bev(s, 45, 8, 12, 34, 'S', 'W', 'E', cham=False) if False else None
        hx = 38 + [0, 2, 3, 1][i] if on else 38
        s.hline(4, 44, 56, 'M'); s.hline(4, 45, 56, 'W')                                              # the hoist rail
        bev(s, hx - 3, 43, 7, 4, 'L', 'M', 'S', cham=False)
        chain(s, [(hx, 47), (hx + (1 if on else 0), 51), (hx, 55)]); s.rect(hx - 2, 55, 5, 3, 'a'); s.put(hx - 2, 57, 'L'); s.put(hx + 2, 57, 'L')
        s.put(8, 60, 'y' if on and i % 2 else 'E'); s.put(9, 60, 'a' if on else 'E'); s.put(56, 60, 'g' if on else 'E')
        return s
    def hurt(self, s, i):
        s.rect(24, 22, 14, 14, 'W'); fillpoly(s, [(24, 28), (34, 24), (38, 32), (28, 36)], 'q'); s.hline(26, 30, 8, 'n'); lcrack(s, [(27, 27), (31, 31), (30, 35)], 'K')
        chain(s, [(38, 47), (42, 52), (40, 56)]); s.put(56, 60, 'E')
        lcrack(s, [(3, 14), (6, 19), (4, 24)], 'L'); s.stamp(8, 50, art("qqq\nnqq")); spark(s, 41, 55, False) if i else None
    def wreck(self, s):
        lcrack(s, [(3, 11), (7, 15), (6, 20), (11, 24), (13, 30)], 'M'); lcrack(s, [(50, 49), (54, 47), (57, 52), (60, 55)], 'M')
        s.rect(24, 22, 14, 14, 'D'); s.stamp(26, 26, art("KKKK\nKqqK\nKnqK")); s.rect(6, 10, 16, 14, 'D'); s.stamp(8, 14, art("KKK\nKnK"))
        chain(s, [(38, 47), (42, 52), (36, 58)], 'W', 'E', 'D'); s.stamp(42, 40, art("KKKK.\nKDDDK\n.KDKK"))
        for k in range(4): s.put(48 + k * 2, 30 + k % 3, 'n')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        if i % 2: glow(g, ox + 8.5, oy + 60.5, 5, RGB_['amber'], 0.5 * k, 2.0)
        glow(g, ox + 40 + [0, 2, 3, 1][i], oy + 56, 5, RGB_['amber'], 0.2 * k, 2.0)

# ============================================================ HAULER THRUSTERS (engine, two halves)
class HaulerThrusters(EngBase):
    id = 'grundl_hauler_thrusters'; KIND = 'scrap'; DMG = (1, 2)
    pad_out = (10, 36, 10, 4)
    anchors_out = {'exhaust_left': (18, 2), 'exhaust_right': (46, 2)}
    anchors_in = {'power_coupling': (56, 29), 'repair_hatch': (10, 29)}
    dark = DK
    notes = ('Grundl Hauler Thrusters, a hull mount (outward is up): two enormous steel bells with rows of big rivets and amber stencil bands, bolted to a heavy riveted base and flanked by strapped fuel cells with chains; the exhaust is a thick orange roar. '
             'Inside a core with a rack of three fuel cells (amber labels, valves), a big gear and a ribbed manifold. '
             'Damaged: the left bell has a split seam and sputters, a fuel-cell strap snapped and the cell sags, the chain hangs, sparks at the coupling. Disabled: the left bell broken off, the right bent over, the cells fallen, the core dark.')
    def out(self, o, on, i):
        from lines_eng_base import bell_gen
        for (x0, w0, secs) in ((10, 23, [(1, 5, 0), (6, 10, 2), (11, 16, 3), (17, 22, 4)]), (34, 23, [(1, 5, 0), (6, 10, 2), (11, 16, 3), (17, 22, 4)])):
            bell_gen(o, x0, w0, secs, 28, on, i, bands=())
        for x0 in (10, 34):
            rivet_row(o, x0 + 4, 6, 7, 3); rivet_row(o, x0 + 6, 13, 5, 3)
            amber_band(o, x0 + 7, 17, 9, 3, on)
        for (cx, side) in ((2, 0), (59, 1)):                                              # strapped fuel cells on the flanks
            cylv(o, cx, 12, 5, 16, 'LMSSE' if side == 0 else 'LMSWE'); o.hline(cx, 15, 5, 'a'); o.hline(cx, 24, 5, 'a'); o.hline(cx, 16, 5, 'u'); o.hline(cx, 25, 5, 'u')
        chain(o, [(7, 12), (8, 17), (9, 21)]); chain(o, [(58, 12), (57, 17), (56, 22)])
        for x in (3, 7, 12, 52, 57, 61): o.put(x, 27, 'L')
    def hurt_out(self, o, i):
        o.rect(8, 2, 27, 26, '.')
        from lines_eng_base import bell_gen
        bell_gen(o, 12, 21, [(8, 11, 0), (12, 16, 2), (17, 21, 3)], 28, True, i + 1, bands=())
        lcrack(o, [(21, 12), (20, 18), (22, 24)], 'L'); jet(o, 14, 14, 4, -1, 0, i)
        rivet_row(o, 16, 14, 4, 3); amber_band(o, 17, 20, 9, 3, True)
        o.rect(0, 12, 8, 17, '.'); cylv(o, 2, 15, 5, 13, 'LMSSE'); lline(o, 2, 15, 6, 19, 'u'); chain(o, [(7, 12), (7, 20), (5, 27)])
        spark(o, 55, 6, False) if i else spark(o, 28, 5, False)
    def wreck_out(self, o):
        o.rect(8, 0, 28, 14, '.'); o.stamp(11, 14, art("KSSSSSSSSSK\nKEEEEEEEEEK")); o.stamp(14, 6, art("KKKK.\nKMSSK\nKSEEK\n.KKKK"))
        for k in range(6): o.put(40 + k * 2, 12 + k, 'W'); o.put(41 + k * 2, 12 + k, 'E')
        o.rect(0, 12, 8, 16, '.'); o.stamp(2, 24, art("KKKKK\nKLMSK")); chain(o, [(10, 24), (14, 27), (20, 26)], 'W', 'E', 'D')
        lcrack(o, [(46, 14), (48, 19), (46, 25)], 'M')
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        glow_xy(g, ox + 21.5, oy + 4, 14, 34, (255, 138, 30), 0.45 * k * (0.9 + 0.05 * i), 1.9)
        glow_xy(g, ox + 45.5, oy + 4, 14, 34, (255, 138, 30), 0.45 * k * (0.9 + 0.05 * (2 - i)), 1.9)
        for x0 in (10, 34): glow(g, ox + x0 + 11.5, oy + 18.5, 6, RGB_['amber'], 0.25 * k, 2.0, sx=1.5)
    def core(self, c, on, i):
        bev(c, 2, 2, 60, 29, 'M', 'S', 'W'); rivet_row(c, 4, 4, 14, 4); rivet_row(c, 4, 26, 14, 4)
        for k, cx in enumerate((6, 21, 36)):                                                # the fuel-cell rack
            cylv(c, cx, 7, 12, 17, 'LMSSSWE'); c.hline(cx, 10, 12, 'a'); c.hline(cx, 11, 12, 'u'); c.hline(cx, 20, 12, 'a'); c.hline(cx, 21, 12, 'u')
            c.rect(cx + 4, 13, 4, 5, 'D'); c.put(cx + 5, 15, 'g' if on and (i + k) % 3 else ('E' if not on else 'y'))
            c.rect(cx + 4, 4, 4, 3, 'W'); c.put(cx + 5, 4, 'L')
        lcircle(c, 54, 14, 6, 'M'); lcircle(c, 54, 14, 4, 'D'); lcircle(c, 54, 14, 1.8, 'L')
        for k in range(10): a = math.radians(k * 36 + (i * 18 if on else 0)); c.put(int(round(54 + 7 * math.cos(a))), int(round(14 + 7 * math.sin(a))), 'S')
        amber_band(c, 4, 24, 16, 3, on)
        rust_streak(c, 20, 5, 4); rust_streak(c, 46, 6, 5)
    def hurt_core(self, c, i):
        c.rect(21, 7, 12, 17, 'W'); lline(c, 21, 7, 33, 24, 'E'); dent(c, 22, 8, 6, 5); jet(c, 26, 7, 4, 0, -1, i)
        c.rect(36, 6, 12, 18, 'S'); lline(c, 37, 9, 45, 12, 'u'); spark(c, 56, 6, False) if i else spark(c, 14, 6, False)
        lcrack(c, [(8, 8), (9, 13), (7, 18)], 'L')
    def wreck_core(self, c):
        c.rect(6, 7, 12, 17, 'D'); c.rect(21, 7, 12, 17, 'D'); c.rect(36, 7, 12, 17, 'D')
        lcrack(c, [(8, 8), (9, 13), (7, 18)], 'M'); lcrack(c, [(40, 8), (42, 14), (39, 19)], 'M'); chain(c, [(20, 22), (24, 26), (30, 25)], 'W', 'E', 'D')
        c.rect(48, 8, 12, 12, 'E'); c.stamp(52, 14, art("KK\nKK"))
    def glow_core(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        b = oy + 4
        for j, cx in enumerate((12, 27, 42)):
            if (i + j) % 3: glow(g, ox + cx, b + 17, 4, RGB_['green'], 0.35 * k, 2.0)
        glow(g, ox + 10, b + 25.5, 5, RGB_['amber'], 0.25 * k, 2.0, sx=2.5)

WEAPONS = [SlugMortar, GrappleHarpoon, BargeFlak]
COMPS = [FreightShield, CargoDeck, Half2(HaulerThrusters(), 'core'), Half2(HaulerThrusters(), 'out')]
ALL = WEAPONS + COMPS
