"""Mire racial tech (docs/waves/racial_tech_1.md): wet green-teal housings, steel and brass pipes, red hand-wheels, steam valves, glass water gauges.
Weapons: mire_steam_lance (fixed), mire_bog_mortar (fixed), mire_mist_projector (turret). Components: mire_rain_shield, mire_wetwell_reactor, mire_spray_deck."""
import pal_races1                               # the three Mire greens (T t U) must exist before the sprites are drawn
from tech_kit import *

HT = ('U', 'T', 't'); HT2 = ('T', 't', 'E')
DK = {'U': 'S', 'T': 'W', 't': 'E', 'c': 'W', 'C': 'E', 'B': 'D', 'g': 'E'}      # dead tones for the Mire letters
STEAM = {'o': 'M', 'y': 'L'}                 # steam flash: white-grey puff
MIST = {'o': 'C', 'y': 'c'}                  # frost mist flash: cyan
BOG = {'o': 'T', 'y': 'g'}                   # bog flash: green slime
F_STEAM, F_MIST, F_BOG = flash_arts(STEAM), flash_arts(MIST), flash_arts(BOG)

class MireW(RW):
    HT = HT; FT = HT; CH = ('c', 'C', 'g'); DK = DK
    LIVE = RGB_['cyan']
    def flange_trim(self, s, st, half, y):
        for x in (4, 13, 50, 59): s.put(x, y + 2, 'a')
        s.hline(20, y + 2, 24, 'U' if half == 'in' else 'T')
        for x in range(22, 42, 6): s.put(x, y + 2, 'c' if st.powered else 'E')
    def rstrip(self, s, st, y0):
        """five glass water-gauge tubes: they fill with cyan water while charging and turn green when ready."""
        y = y0 + STRIP_DY
        recess(s, STRIP_X - 2, y - 1, 5 * 8 + 2, 7, 'D', 'K')
        for k in range(5):
            cx = STRIP_X + k * 8; on = st.powered and k < st.lit
            for r in range(5):
                if getattr(st, 'flash', False) and st.powered: c = 'H' if r < 2 else 'L'
                elif on and st.ready: c = 'g' if r > 0 else 'H'
                elif on: c = ('H', 'c', 'c', 'C', 'B')[r]
                else: c = 'E' if r else 'W'
                s.hline(cx, y + r, 6, c)
            s.put(cx, y, 'L'); s.put(cx + 5, y + 4, 'W')
            if on and not st.ready: s.put(cx + 3, y + 2, 'H')                # a bubble
    def valve_wall(self, s, x, y, st): pass

def tank(s, x, y, w, h, tones='UUTTTttE', bands=(4, -5)):
    """a vertical boiler tank: cylinder with brass bands, rounded ends."""
    cylv(s, x, y, w, h, tones)
    for r in (0, 1): s.put(x, y + r, '.') if r == 0 else None
    for b in bands:
        by = y + b if b >= 0 else y + h + b
        s.hline(x, by, w, 'y'); s.hline(x, by + 1, w, 'a'); s.hline(x, by + 2, w, 'u')
    for (cx, cy) in ((x, y), (x + w - 1, y), (x, y + h - 1), (x + w - 1, y + h - 1)): s.erase(cx, cy)

def boiler_h(s, x, y, w, h, st, level=0.6):
    """a horizontal steel boiler (inside), brass bands, a glass sight tube with the water level."""
    cylh(s, x, y, w, h, 'LMMSSSWE')
    for bx in (x + 3, x + w - 6):
        s.rect(bx, y - 1, 3, h + 2, 'a'); s.vline(bx, y - 1, h + 2, 'y'); s.vline(bx + 2, y - 1, h + 2, 'u')
    gx = x + w // 2 - 4
    s.rect(gx, y + 2, 8, h - 5, 'D'); s.hline(gx, y + 2, 8, 'K')
    wl = int(round((h - 5) * level))
    if st.powered: s.rect(gx + 1, y + 2 + (h - 5) - wl, 6, wl, 'c' if st.state != 'disabled' else 'E')
    s.put(gx + 1, y + 3, 'H')

class SteamLance(MireW):
    id = 'mire_steam_lance'; aim = 'fixed'
    blen, bwid = 58, 13
    bpivot = (6, 6)
    bmuzzle = (44, 6)
    out_notes = ('OUTSIDE half of the Mire Steam Lance (a FIXED gun, Mire teal): a forward-heavy teal housing with the barrel in a sleeve, a boiler tank with brass bands, a gauge and a red hand-wheel on the left, '
                 'three steel steam pipes with a puffing vent on the right. damaged: the vent has sprung a leak (a jet of steam), the tank seam is cracked, the hand-wheel is bent; '
                 'disabled: scorched, dented, the tank split and dripping, the hand-wheel off, never destroyed.')
    notes = ('INSIDE half of the Mire Steam Lance: a steel boiler with brass bands and a glass sight tube, a teal housing, repair hatch, power coupling and five glass water-gauge tubes that fill while charging '
             '(frame 5 = all green = ready); fire: the tubes flash white then empty. damaged: the boiler seam weeps steam, two tubes dead; disabled: boiler split, the sight glass cracked and dry. '
             'Barrel layer mire_steam_lance_barrel: a long teal lance tube with brass bands, side steam ports and a brass nozzle; fire: a white steam jet.')
    def outside(self, s, st):
        pw = st.powered
        self.rgun_housing(s)
        tank(s, 3, 7, 13, 22)                                                 # left: the boiler tank, gauge and hand-wheel
        s.rect(8, 3, 3, 4, 'S'); s.vline(8, 3, 4, 'L'); s.vline(10, 3, 4, 'W')
        wheel(s, 9, 2, 3, 'r', turn=0)
        dial(s, 6, 13, 1 if pw else 0)
        s.put(4, 19, 'c' if pw else 'E'); s.put(4, 20, 'c' if pw else 'E')
        bev(s, 46, 8, 15, 19, *HT2)                                           # right: the steam manifold
        for k, px_ in enumerate((48, 52, 56)):
            pipe_v(s, px_, 4, 3, 21, 'LSE', clamps=(10, 18))
            s.rect(px_ - 1, 12, 5, 2, 'a'); s.hline(px_ - 1, 12, 5, 'y')
        s.hline(47, 22, 13, 'D')
        if pw: puff(s, 53, 2, st.i * 2 + (0 if st.state == 'on' else 1))
        s.put(47, 25, 'c' if pw else 'E'); s.put(59, 25, 'c' if pw else 'E')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        boiler_h(s, 16, y + 6, 30, 12, st, 0.55 + (0.1 if st.charge else 0) * (st.i / 5))
        hatch(s, 49, y + 7, st, 10, 11)
        wheel(s, 52, y + 24, 3, 'r', turn=st.i % 2) if False else None
        self.rstrip(s, st, y)
        s.put(10, y + 3, 'c' if pw else 'E')
    def hurt_out(self, s, st):
        crack(s, [(9, 20), (8, 23), (10, 26)])                                # the tank seam
        jet(s, 58, 6, 6, 1, -1, st.i); jet(s, 58, 6, 4, 0, -1, st.i + 1)      # the sprung vent jets sideways
        s.rect(7, 0, 5, 3, '.')                                               # the hand-wheel is bent: one side gone
        wheel(s, 10, 2, 2, 'r', turn=1)
        spark(s, 14, 14, False) if st.i == 0 else None
        for k in range(3): s.put(5 + st.i, 27 + k % 2, 'c')
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(9, 16), (8, 20), (10, 24), (9, 28)], [(51, 8), (52, 12), (50, 16)]], dents=[(47, 20, 5, 4), (22, 4, 6, 4)],
                 soots=[(4, 8, 0), (47, 6, 1), (30, 12, 2)], wires_=[], sparks=[(14, 10), (56, 6)])
        s.rect(6, 0, 7, 6, '.')                                               # the hand-wheel is gone, a pipe stub left
        s.rect(8, 3, 3, 3, 'W')
        for k in range(4): s.put(3, 20 + k, 'c' if (k + st.i) % 2 else 'H')   # the tank weeps
        s.rect(2, 27, 6, 2, 'D')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        jet(s, 30, y + 6, 4, 0, -1, st.i); puff(s, 30, y + 3, 1 + st.i)
        crack(s, [(22, y + 7), (23, y + 10), (21, y + 14)])
        spark(s, 50, y + 20, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(24, y + 6), (26, y + 11), (25, y + 17)]); crack(s, [(40, y + 6), (38, y + 11), (40, y + 17)])
        s.rect(28, y + 8, 8, 6, 'D'); s.put(30, y + 12, 'E')
        wire(s, [(14, y + 20), (16, y + 23), (22, y + 24)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['cyan'], 0.5, 2.0)
        glow(g, ox + 32, oy + y + 13, 6, RGB_['cyan'], 0.25, 2.0, sx=1.8)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 4.5, oy + 19.5, 3, RGB_['cyan'], 0.5, 2.0)
        glow(g, ox + 53.5, oy + 3, 5, (244, 246, 248), 0.2 + 0.1 * i, 2.0)
    # ---- barrel
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 13 + o, 2, 29, 9, 'UUTTTtE')                                  # the lance tube
        for bx in (17, 27, 36):
            b.rect(bx + o, 1, 3, 11, 'a'); b.vline(bx + o, 1, 11, 'y'); b.vline(bx + o + 2, 1, 11, 'u'); rivet(b, bx + o + 1, 3); rivet(b, bx + o + 1, 8)
        for bx in (22, 31):                                                    # steam ports
            b.rect(bx + o, 0, 3, 2, 'D'); b.rect(bx + o, 11, 3, 2, 'D')
        bev(b, 40 + o, 1, 6, 11, 'y', 'a', 'u')                                # the brass nozzle
        b.rect(44 + o, 3, 2, 7, 'D'); b.put(44 + o, 4, 'E')
        if st.fire: b.rect(44 + o, 3, 2, 7, 'H')
        breech(b, 6, 13, *HT)
    def bhurt(self, b, st):
        crack(b, [(20, 2), (21, 5), (19, 9)]); b.put(23, 12, 'K')
        move(b, 41, 1, 6, 11, 0, 2)                                            # the nozzle sags
        jet(b, 31, 0, 5, 0, -1, st.i); jet(b, 22, 12, 3, 0, 1, st.i + 1)
        spark(b, 40, 4, False) if st.i == 0 else None
    def bbreak(self, b, st):
        return cleave(b, lambda y: 33, 2, 3)                                    # the tube snaps and droops at the middle band
    def bwreck(self, b, st):
        wire(b, [(33, 5), (35, 7), (36, 9)])
        crack(b, [(15, 2), (16, 6), (14, 10)], 'K', 'S')
        b.stamp(38, 7, art("aa\nua"))
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 46, 6, F_STEAM)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            fire_glow(g, ox, oy, i, 46, 6, rgb=(200, 230, 245), core=(244, 246, 248), scale=1.0)
        if state == 'idle': glow(g, ox + 45, oy + 6.5, 4, RGB_['cyan'], 0.25, 2.0)


# ============================================================ BOG MORTAR (fixed): a squat mortar fed from a bubbling slurry vat
class BogMortar(MireW):
    id = 'mire_bog_mortar'; aim = 'fixed'
    blen, bwid = 46, 19
    bpivot = (6, 9)
    bmuzzle = (34, 9)
    out_notes = ('OUTSIDE half of the Mire Bog Mortar (a FIXED gun): a teal housing, a round slurry vat with a bubbling green surface and brass band on the left, a steel feed drum with a hand-wheel and a feed pipe on the right. '
                 'damaged: a vat seam split and weeping green, the feed pipe cracked, bubbles gone sluggish; disabled: scorched, dented, the vat cracked and spilled, the hand-wheel off, never destroyed.')
    notes = ('INSIDE half of the Mire Bog Mortar: a glass slurry tank of green bog water with rising bubbles, a feed pipe, repair hatch, power coupling and the five water-gauge tubes (frame 5 = ready). '
             'fire: the tubes flash and the slurry sloshes. damaged: the tank leaks green drips, tubes dead; disabled: the tank is cracked and empty, slurry spilled. '
             'Barrel layer mire_bog_mortar_barrel: a short wide mortar tube with brass bands and a flared brass mouth rimmed with green slime that drips; fire: a green lob of slime.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.rgun_housing(s, bw=24)
        chamfer_fill(s, 2, 8, 17, 20, 'T', 4); rim(s, 'T', 'U', 't', (2, 8, 18, 27))      # the slurry vat
        chamfer_fill(s, 4, 10, 13, 6, 'E', 2); chamfer_fill(s, 5, 11, 11, 4, 'g' if pw else 'E', 1)
        if pw:
            for (bx, by) in ((7, 12), (12, 13), (14, 11)):
                s.put(bx + (i if bx == 12 else 0), by, 'H'); s.put(bx + (i if bx == 12 else 0), by - 1 + i, 'L')
        s.hline(3, 20, 15, 'y'); s.hline(3, 21, 15, 'a'); s.hline(3, 22, 15, 'u'); rivet(s, 5, 24); rivet(s, 12, 24)
        s.put(2, 18, 'c' if pw else 'E'); s.put(2, 19, 'c' if pw else 'E')
        cylv(s, 49, 9, 11, 19, 'LMMSSWE'); s.hline(49, 13, 11, 'a'); s.hline(49, 24, 11, 'a'); s.hline(49, 14, 11, 'u'); s.hline(49, 25, 11, 'u')
        wheel(s, 54, 6, 3, 'r', turn=i if pw else 0); s.rect(53, 7, 3, 2, 'S')
        pipe_h(s, 41, 19, 9, 3, 'LSE'); s.put(44, 19, 'a'); s.put(44, 20, 'a'); s.put(44, 21, 'a')
        dial(s, 52, 16, 2 if pw else 0)
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        bev(s, 15, y + 4, 28, 17, 'E', 'D', 'K', cham=False)                      # the glass slurry tank, boxed
        s.rect(17, y + 6, 24, 13, 'D')
        if pw:
            lvl = 8 + (1 if st.charge and st.i > 2 else 0)
            s.rect(17, y + 19 - lvl, 24, lvl, 'T'); s.hline(17, y + 19 - lvl, 24, 'g'); s.hline(17, y + 20 - lvl, 24, 'g' if i == 0 else 'T')
            for (bx, by) in ((20, 15), (27, 12), (34, 16), (37, 11)): s.put(bx, by + y - 4 - (i * 2 if bx % 2 else 0) + (0 if i else 1), 'H')
        s.vline(17, y + 6, 13, 'L'); s.vline(40, y + 6, 13, 'W')
        for bx in (21, 29, 37): s.rect(bx, y + 4, 2, 17, 'a'); s.vline(bx, y + 4, 17, 'y')
        pipe_h(s, 43, y + 12, 9, 3, 'LSE'); s.rect(50, y + 10, 2, 7, 'a')
        hatch(s, 52, y + 5, st, 8, 9)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        crack(s, [(10, 14), (9, 18), (11, 22), (10, 26)]); crack(s, [(46, 19), (45, 21)])
        for k in range(4): s.put(3, 22 + k, 'g' if (k + st.i) % 2 else 'T'); s.put(4, 23 + (k + st.i) % 3, 'g')
        s.rect(5, 11, 11, 4, 'E')
        jet(s, 47, 18, 4, 0, -1, st.i, ('g', 'T', 'T'))
        spark(s, 56, 12, False) if st.i == 0 else None
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(10, 10), (9, 16), (11, 22), (9, 28)], [(54, 12), (53, 18), (55, 24)]], dents=[(22, 4, 6, 4), (44, 22, 5, 3)],
                 soots=[(4, 7, 0), (49, 7, 1), (30, 10, 2)], wires_=[], sparks=[(14, 8), (57, 15)])
        s.rect(5, 11, 11, 4, 'D'); s.rect(50, 3, 8, 6, '.')
        s.rect(1, 28, 20, 2, 'E'); s.rect(3, 29, 6, 1, 'g')
        for k in range(3): s.put(2, 24 + k, 'g' if (k + st.i) % 2 else 'E')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        for k in range(4): s.put(41, y + 14 + (k * 2 + st.i) % 7, 'g')
        crack(s, [(33, y + 5), (32, y + 9), (34, y + 13)])
        spark(s, 54, y + 18, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        s.rect(17, y + 6, 24, 13, 'D'); s.rect(18, y + 16, 22, 3, 'E'); s.rect(22, y + 17, 6, 2, 'T')
        crack(s, [(27, y + 4), (28, y + 9), (26, y + 15)]); crack(s, [(36, y + 5), (35, y + 10)])
        wire(s, [(14, y + 22), (16, y + 25), (22, y + 25)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['cyan'], 0.5, 2.0)
        glow(g, ox + 29, oy + y + 14, 11, RGB_['green'], 0.3, 2.0, sx=1.6)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 10.5, oy + 13.5, 8, RGB_['green'], 0.35, 2.0, sx=1.2)
        glow(g, ox + 2.5, oy + 19, 3, RGB_['cyan'], 0.45, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 13 + o, 3, 19, 13, 'UUTTTttE')                                   # the squat tube
        for bx in (16, 26):
            b.rect(bx + o, 2, 3, 15, 'a'); b.vline(bx + o, 2, 15, 'y'); b.vline(bx + o + 2, 2, 15, 'u'); rivet(b, bx + o + 1, 4); rivet(b, bx + o + 1, 12)
        bev(b, 31 + o, 1, 6, 17, 'y', 'a', 'u')                                  # the flared brass mouth
        b.rect(34 + o, 4, 3, 11, 'D'); b.rect(34 + o, 4, 1, 11, 'T')
        for yy in (2, 3, 15, 16): b.put(35 + o, yy, 'g')                         # slime on the rim
        b.put(33 + o, 17, 'g'); b.put(33 + o, 18, 'T')
        if st.fire: b.rect(35 + o, 4, 2, 11, 'g'); b.rect(36 + o, 5, 1, 9, 'H')
        breech(b, 9, 15, *HT)
    def bhurt(self, b, st):
        crack(b, [(20, 3), (21, 8), (19, 12)]); b.rect(24, 8, 2, 4, 'D')
        move(b, 32, 1, 6, 17, 0, 2)
        for k in range(4): b.put(24, 16 + (k + st.i) % 3, 'g')
        spark(b, 29, 3, False) if st.i == 0 else None
    def bbreak(self, b, st): return cleave(b, lambda y: 25, 2, 3)
    def bwreck(self, b, st):
        b.rect(30, 12, 4, 3, 'g'); b.put(31, 13, 'E')
        crack(b, [(16, 3), (17, 9), (15, 14)], 'K', 'S'); b.stamp(33, 5, art("aa\nua"))
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 37, 9, F_BOG)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 37, 9, rgb=(107, 211, 74), core=(200, 255, 200), scale=1.0)
        if state == 'idle': glow(g, ox + 35, oy + 9.5, 5, RGB_['green'], 0.3, 2.0)

# ============================================================ MIST PROJECTOR (turret, tier 1)
class MistProjector(MireW):
    id = 'mire_mist_projector'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 42, 21
    bpivot = (8, 10)
    bmuzzle = (30, 10)
    out_notes = ('OUTSIDE half of the Mire Mist Projector (a TURRET): a teal turret seat, a glass-and-brass water tank on the left, a pump manifold with a hand-wheel on the right. '
                 'damaged: tank seam leaking, the manifold dripping and its wheel bent; disabled: scorched, dented, the tank cracked and dry, the wheel off.')
    notes = ('INSIDE half of the Mire Mist Projector: two upright water tanks (cyan, a bubble rising on the loop) and a steel pump block with a piston, power coupling and the five water-gauge tubes. '
             'damaged: a tank weeps and the pump stutters; disabled: tanks cracked and dry. The rotating head mire_mist_projector_barrel swivels in the ring: a teal head with a fan of three brass spray nozzles and a sensor eye.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.rturret_seat(s, 15)
        bev(s, 3, 6, 16, 18, *HT2)                                                # left: the water tank
        s.rect(5, 8, 12, 14, 'D'); s.hline(5, 8, 12, 'K')
        if pw: s.rect(6, 12, 10, 9, 'C'); s.hline(6, 12, 10, 'c'); s.put(8 + i * 4, 15, 'H'); s.put(11 - i * 3, 17, 'H')
        for bx in (7, 12): s.vline(bx, 8, 14, 'a')
        bev(s, 45, 6, 16, 18, *HT2)                                               # right: the pump manifold
        pipe_v(s, 48, 8, 3, 14, 'LSE', clamps=(12, 18)); pipe_v(s, 54, 8, 3, 14, 'LSE', clamps=(12, 18))
        wheel(s, 52, 3, 2, 'r', turn=i if pw else 0)
        s.put(58, 10, 'c' if pw else 'E'); s.put(58, 12, 'c' if pw else 'E')
        for (x, y) in ((24, 8), (40, 8), (24, 22), (40, 22)): s.put(x, y, 'L')
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'c')
        for k, tx in enumerate((16, 27)):                                         # two upright water tanks
            bev(s, tx, y + 4, 9, 17, 'M', 'S', 'W', cham=False)
            s.rect(tx + 2, y + 6, 5, 13, 'D')
            if pw: s.rect(tx + 2, y + 10, 5, 9, 'C'); s.hline(tx + 2, y + 10, 5, 'c'); s.put(tx + 3 + (i + k) % 3, y + 14 - 3 * ((i + k) % 2), 'H')
            s.hline(tx, y + 8, 9, 'a'); s.hline(tx, y + 17, 9, 'a')
        pipe_h(s, 25, y + 11, 3, 2, 'LE')
        bev(s, 39, y + 5, 22, 16, 'M', 'S', 'W')                                  # the pump
        s.rect(41, y + 7, 18, 4, 'D'); s.hline(41, y + 7, 18, 'K')
        s.rect(43 + (3 if pw and i else 0), y + 8, 6, 2, 'L')
        hatch(s, 43, y + 12, st, 14, 7)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        crack(s, [(8, 7), (9, 12), (7, 17)]); s.rect(6, 12, 10, 9, 'D')
        for k in range(3): s.put(4, 24 + k, 'c' if (k + st.i) % 2 else 'H')
        wheel(s, 52, 3, 2, 'r', turn=1); s.rect(49, 0, 2, 3, '.')
        jet(s, 51, 14, 4, 1, 0, st.i)
        spark(s, 22, 9, False) if st.i else None
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(24, 8), (26, 12), (25, 16), (28, 19)], [(8, 7), (9, 13), (7, 18)]], dents=[(46, 18, 6, 4), (6, 18, 5, 4)],
                 soots=[(20, 3, 0), (46, 5, 1), (8, 7, 2)], wires_=[], sparks=[(30, 6), (12, 10)])
        s.rect(6, 12, 10, 9, 'D'); s.rect(49, 0, 8, 5, '.')
        for k in range(3): s.put(4, 24 + k, 'c' if (k + st.i) % 2 else 'E')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        for k in range(3): s.put(20, y + 21 + (k * 2 + st.i) % 6, 'c')
        crack(s, [(31, y + 5), (32, y + 10), (30, y + 14)])
        spark(s, 50, y + 8, False) if st.i else spark(s, 12, y + 16, False)
    def wreck_in(self, s, st):
        y = self.iy
        s.rect(18, y + 6, 5, 13, 'D'); s.rect(29, y + 6, 5, 13, 'D')
        crack(s, [(20, y + 4), (21, y + 10), (19, y + 16)]); crack(s, [(46, y + 6), (49, y + 10), (47, y + 14)])
        wire(s, [(14, y + 22), (16, y + 25), (22, y + 25)])
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['cyan'], 0.5, 2.0)
        for tx in (20, 31): glow(g, ox + tx + .5, oy + y + 14, 6, RGB_['cyan'], 0.22, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 11, oy + 17, 7, RGB_['cyan'], 0.3, 2.0, sx=1.3)
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 12 + o, 4, 11, 13, *HT)                                           # the head body
        b.rect(14 + o, 7, 6, 7, 'D'); b.rect(15 + o, 8, 4, 5, 'T' if not st.fire else 'c')
        b.hline(12 + o, 9, 11, 'a'); b.hline(12 + o, 10, 11, 'u') if False else None
        bev(b, 23 + o, 3, 3, 15, 'L', 'M', 'S', cham=False)                      # the manifold bar
        for ny in (3, 9, 15):                                                    # three brass spray nozzles
            cylh(b, 26 + o, ny, 5, 4, 'yaau'); b.rect(30 + o, ny, 1, 4, 'D')
            if st.fire: b.rect(30 + o, ny + 1, 1, 2, 'H')
        hub(b, 10, 17, 'T', 'U', 't')
        pod(b, 10, 0)
    def bhurt(self, b, st):
        b.rect(26, 15, 5, 4, '.'); wire(b, [(25, 17), (27, 19), (29, 19)]); b.rect(28, 19, 3, 3, 'a')
        crack(b, [(15, 4), (16, 8), (15, 13)])
        for k in range(3): b.put(28, 4 + (k * 2 + st.i) % 7, 'c')
        spark(b, 30, 17, False) if st.i == 0 else None
    def bbreak(self, b, st): return cleave(b, lambda y: 25, 2, 3, rows=(2, 20))
    def bwreck(self, b, st):
        for y in (7, 13): wire(b, [(23, y), (25, y + 1), (27, y + 1)])
        crack(b, [(16, 5), (17, 9), (16, 14)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire:
            for ny in (3, 9, 15): stamp_flash(b, st, 31, ny + 2, F_MIST)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            for ny in (3, 9, 15): fire_glow(g, ox, oy, i, 31, ny + 2, rgb=(60, 242, 255), core=(244, 246, 248), scale=0.6)
        if state != 'disabled': glow(g, ox + 11.5, oy + 1.5, 3, RGB_['cyan'], 0.5, 2.0)

# ============================================================ components (shared look)
from lines_kit import LComp, bolts as lbolts, bolt as lbolt
from lines_kit import crack as lcrack
from lines_kit import line as lline

class MireC(LComp):
    dark = DK
    glow_pad = (10, 10, 10, 10)

def valve_block(s, x, y, st_on, i, turn=0, size=11):
    """a brass valve block with a red hand-wheel and a steam outlet."""
    bev(s, x, y, size, size, 'y', 'a', 'u')
    wheel(s, x + size // 2, y + size // 2, 3, 'r', turn=turn)
    s.put(x + 1, y + 1, 'L'); s.put(x + size - 2, y + size - 2, 'n')

class RainShield(MireC):
    id = 'mire_rain_shield'; cells = (4, 4)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    notes = ('Mire Rain Shield, 4x4: a teal housing with a brass hand-wheel valve in every corner and a round water-lens well in the middle, where a ripple spreads from a falling drop and rain streaks fall over it (the 4-frame loop). '
             'Off: still dull water, wheels at rest. Damaged: the upper-left valve has sprung a steam jet, the rim is cracked and the ripple stutters. '
             'Disabled: the well is drained and dark, a valve snapped off, the housing split.')
    DROPS = [(20, 20), (41, 24), (27, 40), (44, 42), (33, 17)]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 62, 62, 'T', 9); rim(s, 'T', 'U', 't')
        chamfer_fill(s, 4, 4, 56, 56, 't', 8); rim(s, 't', 'T', 'E', (4, 4, 59, 59))
        for k, (vx, vy) in enumerate(((5, 5), (48, 5), (5, 48), (48, 48))): valve_block(s, vx, vy, on, i, turn=(i + k) % 2 if on else 0)
        chamfer_fill(s, 11, 11, 42, 42, 'S', 14); rim(s, 'S', 'L', 'W', (11, 11, 52, 52))
        chamfer_fill(s, 14, 14, 36, 36, 'E', 12)
        chamfer_fill(s, 16, 16, 32, 32, 'B' if on else 'D', 11)
        for d in range(13, 52, 7): s.put(d, 12, 'W'); s.put(d, 51, 'W'); s.put(12, d, 'W'); s.put(51, d, 'W')
        if on:
            for r0, c in ((5, 'H'), (11, 'c'), (17, 'C')):
                r = (r0 + 3 * i) % 19 + 2
                if r < 16: ring(s, 32, 32, r - 1, r, c if r < 12 else 'C')
            chamfer_fill(s, 30, 30, 4, 4, 'c', 1); s.put(31, 31, 'H')
            for k, (dx, dy) in enumerate(self.DROPS):
                yy = dy + ((i + k) % 4) * 3 - 3
                s.put(dx, yy, 'H'); s.put(dx, yy - 1, 'c')
        else:
            for (x, y) in ((24, 28), (38, 36), (30, 24)): s.hline(x, y, 3, 'S')
        return s
    def hurt(self, s, i):
        lcrack(s, [(14, 24), (16, 28), (14, 33), (17, 38)], 'L')
        s.rect(48, 5, 11, 11, '.'); valve_block(s, 48, 6, False, 0, 1); s.rect(52, 4, 3, 3, '.')
        for k in range(5): s.put(53 + k - (i if k > 2 else 0), 4 - k // 2 + (k % 2), 'H' if (k + i) % 2 else 'L')
        for (x, y) in ((22, 30), (23, 31), (24, 32)): s.put(x, y, 'D')
        for (x, y) in ((18, 22), (19, 21)): s.put(x, y, 'K')
        if i: s.hline(28, 30, 8, 'c')
    def wreck(self, s):
        lcrack(s, [(3, 11), (7, 15), (6, 20), (11, 24), (13, 30)], 'M'); lcrack(s, [(50, 49), (54, 47), (57, 52), (60, 55)], 'M')
        chamfer_fill(s, 16, 16, 32, 32, 'D', 11); s.hline(20, 44, 20, 'E')
        s.rect(48, 5, 11, 11, '.'); s.stamp(50, 8, art("KKK\nKaK\nKuK")); s.rect(53, 12, 4, 3, 'g') if False else None
        s.stamp(6, 45, art("KKK\nKLL\nKLM"))
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        glow(g, ox + 32, oy + 32, 22, (79, 163, 255), 0.3 * k, 1.6)
        glow(g, ox + 32, oy + 32, 8, RGB_['cyan'], 0.35 * k, 1.8)
        for (vx, vy) in ((10, 10), (53, 10), (10, 53), (53, 53)):
            if flick is not None and (vx, vy) == (53, 10): continue
            glow(g, ox + vx, oy + vy, 4, RGB_['red'], 0.25 * k, 2.0)

class WetwellReactor(MireC):
    id = 'mire_wetwell_reactor'; cells = (4, 4)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    PULSE = [7, 8, 9, 8]
    notes = ('Mire Wetwell Reactor, 4x4: a teal casing round a round water well; the amber core glows under the water, bubbles rise and a steam puff leaves each corner vent in turn (the 4-frame loop), brass hand-wheel valves on the four pipes. '
             'Off: the core is dark under still water. Damaged: a feed pipe has burst and jets steam, the casing is cracked and the core stutters. '
             'Disabled: the well is drained, the dead core sits dry and cracked, a pipe snapped.')
    BUB = [[(29, 22), (36, 25), (24, 34), (40, 38), (31, 42)], [(30, 19), (35, 22), (25, 31), (41, 35), (32, 40)], [(31, 17), (36, 20), (26, 29), (40, 32), (30, 38)], [(30, 20), (34, 23), (24, 33), (41, 36), (32, 41)]]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 62, 62, 'T', 9); rim(s, 'T', 'U', 't')
        chamfer_fill(s, 4, 4, 56, 56, 't', 8)
        for (px_, py_) in ((29, 2), (29, 49)): pipe_v(s, px_, py_, 6, 13, 'LSE', clamps=(py_ + 4, py_ + 8))
        for (px_, py_) in ((2, 29), (49, 29)): pipe_h(s, px_, py_, 13, 6, 'LSE', clamps=(px_ + 4, px_ + 8))
        for k, (vx, vy) in enumerate(((6, 6), (47, 6), (6, 47), (47, 47))):
            bev(s, vx, vy, 11, 11, 'y', 'a', 'u'); wheel(s, vx + 5, vy + 5, 3, 'r', turn=(i + k) % 2 if on else 0)
            if on and (k + i) % 4 == 0: puff(s, vx + 5 + (4 if k % 2 else -4), vy + (0 if k < 2 else 11), i % 3 + 1)
        chamfer_fill(s, 12, 12, 40, 40, 'S', 14); rim(s, 'S', 'L', 'W', (12, 12, 51, 51))
        chamfer_fill(s, 15, 15, 34, 34, 'E', 12)
        chamfer_fill(s, 17, 17, 30, 30, 'B' if on else 'D', 10)
        if on:
            r = self.PULSE[i]
            ring(s, 32, 32, r + 2, r + 4, 'C'); ring(s, 32, 32, r + 4, r + 5, 'c')
            chamfer_fill(s, 32 - r, 32 - r, 2 * r, 2 * r, 'o', r // 2 + 1)
            chamfer_fill(s, 32 - r + 2, 32 - r + 2, 2 * r - 4, 2 * r - 4, 'y', r // 2)
            chamfer_fill(s, 32 - r + 3, 32 - r + 3, 2 * r - 6, 2 * r - 6, 'H', max(1, r // 2 - 1))
            for (x, y) in self.BUB[i]: s.put(x, y, 'H'); s.put(x + 1, y, 'L')
        else:
            chamfer_fill(s, 24, 24, 16, 16, 'E', 5); chamfer_fill(s, 27, 27, 10, 10, 'D', 3)
            for (x, y) in ((26, 26), (37, 26), (26, 37), (37, 37)): s.put(x, y, 'W')
        return s
    def hurt(self, s, i):
        s.rect(47, 29, 15, 6, '.'); s.stamp(47, 30, art("aaa\nuuu\nnnn")); s.stamp(58, 32, art("KK.\nKaK\n.KK"))   # the right pipe has burst
        for k in range(7): s.put(55 + (k % 2) + (i if k > 3 else 0), 28 - k, 'H' if (k + i) % 2 else 'L')
        lcrack(s, [(8, 18), (11, 22), (9, 27), (13, 31)], 'L')
        for (x, y) in ((22, 20), (23, 21), (24, 22)): s.put(x, y, 'K')
        if i: chamfer_fill(s, 31, 31, 3, 3, 'o', 1)
        lcrack(s, [(40, 52), (42, 55), (41, 58)], 'L')
    def wreck(self, s):
        chamfer_fill(s, 17, 17, 30, 30, 'D', 10); chamfer_fill(s, 24, 24, 16, 16, 'E', 5); chamfer_fill(s, 27, 27, 10, 10, 'K', 3)
        lcrack(s, [(3, 11), (7, 15), (6, 20), (11, 24)], 'M'); lcrack(s, [(46, 49), (50, 47), (53, 51), (57, 50)], 'M')
        s.rect(47, 29, 15, 6, '.'); s.stamp(47, 30, art("KKK\nKaK\nKuK")); s.stamp(6, 45, art("KKK\nKLL\nKLM"))
        s.hline(20, 44, 24, 'K'); s.hline(23, 45, 18, 'E')
    def glow(self, state, i, g, ox, oy, flick=None):
        r = self.PULSE[i]
        k = 1.0 if flick is None else (0.55 if flick else 0.85)
        glow(g, ox + 32, oy + 32, 24 + r, (255, 138, 30), 0.3 * k, 1.5)
        glow(g, ox + 32, oy + 32, 9 + r * 0.6, RGB_['cyan'], 0.3 * k, 1.8)
        glow(g, ox + 32, oy + 32, 5 + r * 0.7, RGB_['yellow'], 0.55 * k, 1.6)

class SprayDeck(MireC):
    id = 'mire_spray_deck'; cells = (2, 2)
    glow_pad = (6, 6, 6, 6)
    anims = [('on', 'on', 4, 8), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    notes = ('Mire Spray Deck, 2x2: a teal frame round a drain grate, four brass spray heads in the corners that throw arcs of water in turn onto a puddle in the middle (the 4-frame loop), a red hand-wheel in the middle of each edge. '
             'Off: a dry grate, heads dull. Damaged: one head hangs loose and sprays sideways, the frame is cracked. Disabled: the heads are snapped, the grate dark and dry.')
    HEADS = [(3, 3), (23, 3), (3, 23), (23, 23)]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        chamfer_fill(s, 0, 0, 32, 32, 'T', 4); rim(s, 'T', 'U', 't')
        chamfer_fill(s, 3, 3, 26, 26, 'E', 3)
        s.rect(5, 5, 22, 22, 'D')
        for d in range(5, 27, 4): s.vline(d, 5, 22, 'E'); s.hline(5, d, 22, 'E')
        if on:
            r = 3 + (i % 3)
            chamfer_fill(s, 16 - r, 16 - r, 2 * r, 2 * r, 'B', max(1, r // 2)); chamfer_fill(s, 16 - r + 1, 16 - r + 1, 2 * r - 2, 2 * r - 2, 'C', max(1, r // 2 - 1)) if r > 3 else None
            s.put(15, 15, 'H'); s.put(17 + i % 2, 16, 'c')
        else:
            chamfer_fill(s, 13, 13, 6, 6, 'E', 2)
        for k, (hx, hy) in enumerate(self.HEADS):
            bev(s, hx, hy, 6, 6, 'y', 'a', 'u'); s.rect(hx + 2, hy + 2, 2, 2, 'D' if not on else 'c')
            if on and (k + i) % 4 != 3:
                dx = 1 if hx < 16 else -1; dy = 1 if hy < 16 else -1
                for q in range(1, 5): s.put(hx + 3 + dx * (2 + q) + (0), hy + 3 + dy * (2 + q) - (q > 2) * 0, 'H' if (q + i) % 2 else 'c')
        for (wx, wy) in ((16, 1), (16, 30), (1, 16), (30, 16)): s.put(wx, wy, 'r'); s.put(wx - 1, wy, 'r') if wx in (1, 30) else s.put(wx, wy + (1 if wy == 1 else -1), 'r')
        return s
    def hurt(self, s, i):
        s.rect(21, 1, 10, 10, '.'); s.stamp(21, 4, art("aaaa\nuaau\n.nn.")); s.stamp(25, 7, art("KK\nKD"))
        for q in range(5): s.put(26 + q % 3, 8 + q, 'c' if (q + i) % 2 else 'H')
        lcrack(s, [(8, 1), (9, 3), (7, 5)], 'L')
        s.hline(10, 28, 8, 'K')
    def wreck(self, s):
        s.rect(1, 1, 10, 10, '.'); s.stamp(2, 5, art("KKK\nKaK")); s.rect(21, 21, 9, 9, '.'); s.stamp(23, 24, art("KK\nKu"))
        lcrack(s, [(14, 1), (15, 6), (13, 10), (15, 15)], 'M'); s.hline(8, 20, 14, 'K')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        glow(g, ox + 16, oy + 16, 8, RGB_['cyan'], 0.3 * k, 1.8)
        for (hx, hy) in self.HEADS: glow(g, ox + hx + 3, oy + hy + 3, 4, RGB_['cyan'], 0.3 * k, 2.0)

WEAPONS = [SteamLance, BogMortar, MistProjector]
COMPS = [RainShield, WetwellReactor, SprayDeck]
ALL = WEAPONS + COMPS
