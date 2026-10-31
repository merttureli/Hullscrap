"""Sporeling racial tech (docs/waves/racial_tech_1.md): grown, not built. Cream and brown fungal housings with rust spots and gill lines, violet spore sacs, bioluminescent green,
a few scavenged steel brackets. Weapons: sporeling_spore_cannon (fixed), sporeling_rot_pod (fixed missile), sporeling_pollen_turret (turret).
Components: sporeling_bloom_reactor, sporeling_mycelium_shield, sporeling_garden_bay."""
import pal_races1                               # the Mire greens (T t U) are used for leaves
from tech_kit import *
from lines_kit import LComp, crack as lcrack, line as lline

HT = ('f', 'Q', 'q'); HT2 = ('Q', 'q', 'n')
DK = {'f': 'Q', 'Q': 'q', 'q': 'n', 'n': 'D', 'V': 'E', 'X': 'W', 'Z': 'D', 'p': 'q', 'g': 'E', 's': 'q', 'a': 'u', 'm': 'E'}     # withered: browner and greyer
SPORE = {'o': 'g', 'y': 'y'}
POLLEN = {'o': 'a', 'y': 'y'}
POD = {'o': 'V', 'y': 'p'}
F_SPORE, F_POLLEN, F_POD = flash_arts(SPORE), flash_arts(POLLEN), flash_arts(POD)

def organic(s, x, y, w, h, tones=HT, ch=4, spots=True, fibre=True):
    """a grown lump: rounded, light top-left, with rust spots and a fibre grain."""
    chamfer_fill(s, x, y, w, h, tones[1], ch); rim(s, tones[1], tones[0], tones[2], (x, y, x + w - 1, y + h - 1))
    if fibre:
        for k in range(x + 3, x + w - 3, 5):
            for j in range(y + 3 + (k % 3), y + h - 4, 7): s.put(k, j, tones[2]); s.put(k, j + 1, tones[2])
    if spots:
        for k, (sx, sy) in enumerate(((x + 4, y + 3), (x + w - 6, y + 4), (x + w // 2, y + h - 5))):
            if s.get(sx, sy) == tones[1]: s.put(sx, sy, 'u'); s.put(sx + 1, sy, 'u'); s.put(sx, sy + 1, 'Q' if tones[1] == 'q' else 'u')

def gills(s, x, y, w, h, c='n', c2='q'):
    """gill lines: thin vertical dark ribs under a cap."""
    for k in range(0, w, 2): s.vline(x + k, y, h, c if k % 4 == 0 else c2)

def cap(s, cx, y, w, h, tones=('f', 's', 'Q'), spots=True):
    """a mushroom cap seen from the side: a half-ellipse, cream, rust spots, gills along its lip."""
    for j in range(h):
        t = (j + 0.5) / h; half = int(round(w / 2 * math.sqrt(max(0.0, 1 - (1 - t) ** 2))))
        for x in range(cx - half, cx + half + 1): s.put(x, y + j, tones[0] if (x - cx) < -half * 0.2 and j < h * 0.6 else (tones[1] if x - cx < half * 0.5 else tones[2]))
    s.hline(cx - w // 2 + 1, y + h, w - 2, 'q')
    if spots:
        for (dx, dy) in ((-w // 4, h // 2), (w // 5, h // 3), (0, h - 2)): s.put(cx + dx, y + dy, 'u'); s.put(cx + dx + 1, y + dy, 'u')

class SporeW(RW):
    HT = HT; FT = HT; CH = ('p', 'm', 'g'); DK = DK
    LIVE = (255, 79, 216); READY = RGB_['green']
    def flange_trim(self, s, st, half, y):
        for x in (4, 13, 50, 59): s.put(x, y + 2, 'u')
        s.hline(18, y + 2, 28, 'q')
        for x in range(20, 44, 5): s.put(x, y + 2, 'u')
    def ogun_housing(self, s, cy=12, bw=26, bh=26, out_h=32):
        """fixed gun, outside, grown: rounded block, a sleeve like a stalk, a gimbal collar (pin at (32, cy))."""
        hi, mid, lo = self.HT
        x0 = 32 - bw // 2; top = cy - 10
        organic(s, 6, cy + 8, 52, out_h - cy - 8, hi_t(self), 3, False)
        organic(s, x0, top, bw, bh, self.HT, 5)
        sw = bw - 4
        organic(s, 32 - sw // 2, top - 1, sw, 8, self.HT, 2, False, False)
        s.rect(32 - (sw - 8) // 2, top, sw - 8, 6, 'D'); s.hline(32 - (sw - 8) // 2, top, sw - 8, 'K')
        bev(s, x0 - 1, cy - 3, bw + 2, 5, 'M', 'S', 'W', cham=False)                   # a scavenged steel collar, the one hard part
        s.put(32, cy, 'L'); s.put(33, cy + 1, 'W'); s.put(31, cy, 'M')
        gills(s, x0 + 4, cy + 6, bw - 8, 6, 'n', 'q')
        return x0, top
    def oturret_seat(self, s, cy=15, d=25):
        organic(s, 6, cy + 4, 52, 32 - cy - 4, self.HT, 3, False)
        turret_ring(s, 32, cy, d, 'Q', 'q', 'n', 'D')
    def rstrip(self, s, st, y0):
        """five spore sacs along the bottom: dim brown when empty, violet and swelling while charging, glowing green when ready."""
        y = y0 + STRIP_DY
        recess(s, STRIP_X - 2, y - 1, 5 * 8 + 2, 7, 'n', 'K')
        for k in range(5):
            cx = STRIP_X + k * 8; on = st.powered and k < st.lit
            if getattr(st, 'flash', False) and st.powered: tn = ('H', 'L', 'M')
            elif on and st.ready: tn = ('y', 'g', 'g')
            elif on: tn = ('X', 'V', 'Z')
            else: tn = ('q', 'q', 'n')
            chamfer_fill(s, cx, y, 6, 5, tn[1], 1); s.hline(cx + 1, y, 3, tn[0]); s.hline(cx + 1, y + 4, 4, tn[2])
            if on: s.put(cx + 1, y + 1, 'H')

def hi_t(w): return w.HT

# ============================================================ SPORE CANNON (fixed)
class SporeCannon(SporeW):
    id = 'sporeling_spore_cannon'; aim = 'fixed'
    blen, bwid = 58, 17
    bpivot = (6, 8)
    bmuzzle = (42, 8)
    out_notes = ('OUTSIDE half of the Sporeling Spore Cannon (a FIXED gun, grown): a rounded cream-and-brown housing with the barrel in a stalk-like sleeve, a cluster of three violet spore sacs that bob on the left, '
                 'a gill vent on the right with a drifting puff of yellow spores. damaged: a sac has burst and weeps, the vent is torn and puffs unevenly; disabled: scorched, withered, the sacs shrivelled and dark, never destroyed.')
    notes = ('INSIDE half of the Sporeling Spore Cannon: a big violet spore chamber with green spores drifting in it, fibrous feed roots, a steel repair hatch, power coupling and five spore sacs that swell violet while charging and glow green when ready. '
             'fire: the sacs flash white then deflate. damaged: the chamber has a split and leaks, two sacs withered; disabled: the chamber collapsed and dry, withered. '
             'Barrel layer sporeling_spore_cannon_barrel: a fleshy ringed tube with a flared spotted bell mouth that puffs spores; fire: a green-yellow spore burst.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.ogun_housing(s)
        for (sx, sy, w, h) in ((3, 17, 9, 10), (10, 10, 8, 9), (3, 7, 8, 8)):                # the spore sacs
            sac(s, sx, sy - (i if pw and sx != 10 else 0), w, h, ('X', 'V', 'Z') if pw else ('W', 'S', 'E'))
        s.hline(12, 21, 5, 'Q'); s.hline(12, 22, 5, 'q'); s.vline(14, 12, 9, 'q')
        organic(s, 46, 8, 14, 19, HT2, 4)                                                  # the gill vent
        gills(s, 49, 12, 8, 10, 'n', 'q')
        s.hline(48, 11, 10, 'f')
        if pw:
            for k in range(4): s.put(51 + (k * 2 + i) % 5, 6 - k - i, 'y' if (k + i) % 2 else 'g')
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'g')
        organic(s, 16, y + 4, 32, 17, ('Q', 'q', 'n'), 6, False)                           # the chamber
        sac(s, 19, y + 6, 26, 13, ('X', 'V', 'Z') if pw else ('W', 'S', 'E'), 'H')
        if pw:
            for k, (dx, dy) in enumerate(((24, 12), (30, 10), (36, 14), (40, 11), (28, 15))): s.put(dx, y + dy + ((i + k) % 3) - 1, 'g'); s.put(dx + 1, y + dy + ((i + k) % 3) - 1, 'y')
        for fx in (13, 49): lline(s, fx, y + 12, fx + 3, y + 8, 'q'); lline(s, fx, y + 13, fx + 3, y + 9, 'Q')
        hatch(s, 51, y + 6, st, 9, 10)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        s.rect(3, 7, 8, 8, '.'); sac(s, 3, 9, 8, 6, ('W', 'S', 'E'))                           # one sac has burst and sagged
        for k in range(4): s.put(5, 15 + (k * 2 + st.i) % 7, 'V' if k % 2 else 'X')
        crack(s, [(52, 12), (53, 16), (51, 21)]); s.put(55, 9, '.'); s.put(56, 10, '.')
        s.put(50 + st.i * 3, 4, 'y')
        spark(s, 34, 9, False) if st.i else None
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(24, 6), (26, 11), (24, 16)], [(52, 10), (53, 16), (51, 22)]], dents=[(46, 22, 6, 4), (22, 4, 6, 4)],
                 soots=[(4, 6, 0), (48, 5, 1), (30, 12, 2)], wires_=[], sparks=[(14, 10), (54, 6)])
        for (sx, sy, w, h) in ((3, 19, 9, 8), (10, 14, 8, 6)): s.rect(sx, sy - 6, w, h + 6, '.'); sac(s, sx, sy, w, h, ('S', 'E', 'D'), None)
        for k in range(3): s.put(6, 26 + k, 'V' if (k + st.i) % 2 else 'E')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(30, y + 6), (31, y + 11), (29, y + 17)]); s.rect(29, y + 11, 3, 2, 'D')
        for k in range(4): s.put(31, y + 18 + (k * 2 + st.i) % 7, 'g' if k % 2 else 'V')
        spark(s, 56, y + 20, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        s.rect(19, y + 6, 26, 13, 'D'); sac(s, 19, y + 12, 26, 7, ('S', 'E', 'D'), None)
        crack(s, [(28, y + 5), (30, y + 10), (27, y + 16)]); crack(s, [(38, y + 5), (36, y + 11)])
        wire(s, [(14, y + 20), (16, y + 23), (22, y + 24)], 'q', 'n')
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['green'], 0.5, 2.0)
        glow(g, ox + 32, oy + y + 13, 14, RGB_['violet'], 0.28, 2.0, sx=1.5)
        for k in range(3): glow(g, ox + 24 + 6 * k + .5, oy + y + 12, 3, RGB_['green'], 0.3, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 8, oy + 15, 9, RGB_['violet'], 0.3, 2.0, sx=1.2)
        glow(g, ox + 53, oy + 4, 6, RGB_['yellow'], 0.2 + 0.1 * i, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        cylh(b, 13 + o, 3, 22, 11, 'fQQqqqn')                                              # the fleshy tube
        for bx in (17, 24, 31):
            b.rect(bx + o, 2, 2, 13, 'q'); b.vline(bx + o, 2, 13, 'Q'); b.vline(bx + o + 1, 2, 13, 'n')
        for (bx, by) in ((20, 5), (28, 10), (34, 6)): b.put(bx + o, by, 'u'); b.put(bx + o + 1, by, 'u')
        cap(b.__class__ and b, 0, 0, 0, 0) if False else None
        organic(b, 35 + o, 0, 9, 17, ('f', 's', 'Q'), 3, True, False)                      # the flared bell mouth
        b.rect(40 + o, 4, 4, 9, 'D'); b.rect(40 + o, 4, 1, 9, 'Z')
        for (bx, by) in ((43, 2), (43, 14), (42, 16)): b.put(bx + o, by, 'y')
        if st.fire: b.rect(41 + o, 4, 3, 9, 'g'); b.rect(43 + o, 6, 1, 5, 'H')
        breech(b, 8, 15, *HT)
    def bhurt(self, b, st):
        b.rect(24, 2, 2, 13, '.'); b.rect(24, 2, 2, 1, 'q'); wire(b, [(25, 3), (25, 5)], 'q', 'n')
        crack(b, [(18, 3), (19, 7), (17, 11)]); move(b, 36, 0, 9, 17, 0, 2)
        for k in range(4): b.put(30, 14 + (k + st.i) % 3, 'V')
        spark(b, 40, 3, False) if st.i == 0 else None
    def bbreak(self, b, st): return cleave(b, lambda y: 27, 2, 3)
    def bwreck(self, b, st):
        b.rect(34, 9, 4, 4, 'V'); b.put(35, 10, 'E')
        crack(b, [(16, 3), (17, 8), (15, 13)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 44, 8, F_SPORE)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 44, 8, rgb=(107, 211, 74), core=(255, 235, 160), scale=1.0)
        if state == 'idle': glow(g, ox + 42, oy + 8.5, 5, RGB_['green'], 0.25, 2.0)

# ============================================================ ROT POD (fixed, missile): a pod launcher with a feed root to the rack
PODART = art("""
..KKKK...
.KuVVVQK.
KVVXXVVuK
KVXVVVVVK
KVVVuVVVK
KVVVVVVuK
.KnVVVnK.
..KKKK...
""")
class RotPod(SporeW):
    id = 'sporeling_rot_pod'; aim = 'fixed'
    blen, bwid = 58, 21
    bpivot = (6, 10)
    bmuzzle = (42, 10)
    out_notes = ('OUTSIDE half of the Sporeling Rot Pod (a FIXED launcher, grown): a rounded housing, a swollen pod nursery on the left that bulges on the loop and a root-like loader on the right with a lit amber bud. '
                 'damaged: the nursery has split and oozes, a root is torn; disabled: scorched, shrivelled, the nursery collapsed, never destroyed.')
    notes = ('INSIDE half of the Sporeling Rot Pod: the pod cradle with a feed root to the right (the ammo rack sits beside it), power coupling, repair hatch and five spore sacs. '
             'charge: a rot pod rolls in from the root into the cradle (frame 5 = seated and ready); fire: the cradle is empty. damaged: root cracked, sacs withered; disabled: a pod stuck half-way in the root. '
             'Barrel layer sporeling_rot_pod_barrel: a cradle of two curved fingers holding a violet rot pod; fire: the pod leaves, a spore puff follows.')
    NOSE = [None, 44, 38, 32, 26, 20]
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.ogun_housing(s)
        organic(s, 3, 7 - (i if pw else 0), 15, 21 + (i if pw else 0), HT2, 6)                 # the pod nursery
        sac(s, 6, 11 - (i if pw else 0), 9, 8, ('X', 'V', 'Z') if pw else ('W', 'S', 'E')); sac(s, 8, 20, 7, 6, ('X', 'V', 'Z') if pw else ('W', 'S', 'E'))
        organic(s, 45, 7, 16, 20, HT2, 5)                                                       # the loader
        s.rect(49, 11, 8, 6, 'D'); s.hline(49, 11, 8, 'K'); s.hline(49, 17, 8, 'Q')
        for k in range(3): s.put(51 + 2 * k, 14, 'a' if pw and (k + i) % 3 else 'E'); s.put(51 + 2 * k, 13, 'a' if pw and (k + i) % 3 else 'E')
        gills(s, 48, 19, 10, 5, 'n', 'q')
    def inside(self, s, st):
        y = self.iy; pw = st.powered
        self.rhousing(s, y)
        coupling(s, 3, y + 2, st, 'g')
        hatch(s, 3, y + 16, st, 9, 8)
        organic(s, 14, y + 5, 34, 15, ('q', 'n', 'D'), 4, False, False)                      # the cradle
        s.hline(15, y + 6, 32, 'Q'); s.hline(15, y + 18, 32, 'q')
        organic(s, 48, y + 5, 15, 15, ('Q', 'q', 'n'), 4, False)                              # the feed root toward the rack
        s.rect(51, y + 8, 12, 9, 'D'); s.hline(51, y + 8, 12, 'K'); s.hline(51, y + 17, 12, 'Q')
        for k in range(2): s.put(55 + 4 * k, y + 12, 'V'); s.put(56 + 4 * k, y + 12, 'X')
        nose = {'on': 17, 'off': 17, 'damaged': 17, 'charge': self.NOSE[st.i] if st.charge else None, 'disabled': 35}.get(st.state)
        if nose is not None and nose < 60:
            for j, r in enumerate(PODART):
                for k, c in enumerate(r[::-1]):
                    x = nose - 9 + k + 9
                    if c != '.' and 15 <= x <= 61: s.put(x - 9, y + 8 + j, c)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        crack(s, [(9, 8), (8, 13), (10, 18)]); s.rect(6, 14, 5, 3, 'D')
        for k in range(4): s.put(10, 24 + (k * 2 + st.i) % 6, 'V' if k % 2 else 'X')
        s.rect(53, 4, 8, 3, '.'); s.stamp(54, 3, art("qq.\n.qQ"))
        spark(s, 52, 12, False) if st.i else None
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(10, 8), (9, 14), (11, 20), (9, 27)], [(53, 8), (52, 13), (54, 19)]], dents=[(46, 22, 6, 4), (22, 4, 6, 4)],
                 soots=[(5, 6, 0), (48, 5, 1), (30, 12, 2)], wires_=[], sparks=[(14, 10), (55, 6)])
        s.rect(3, 7, 15, 10, '.'); organic(s, 3, 17, 15, 11, ('S', 'E', 'D'), 4, False)
        for k in range(3): s.put(7, 24 + k, 'V' if (k + st.i) % 2 else 'E')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(50, y + 5), (52, y + 9), (51, y + 14)])
        for k in range(3): s.put(56, y + 18 + (k * 2 + st.i) % 5, 'V')
        spark(s, 52, y + 10, False) if st.i == 0 else spark(s, 10, y + 20, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(50, y + 5), (52, y + 9), (51, y + 14), (53, y + 18)]); crack(s, [(24, y + 7), (26, y + 11), (25, y + 16)])
        wire(s, [(14, y + 21), (17, y + 23), (20, y + 24)], 'q', 'n')
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 8, 3, RGB_['green'], 0.5, 2.0)
        glow(g, ox + 56, oy + y + 12, 5, RGB_['violet'], 0.3, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 10, oy + 16, 9, RGB_['violet'], 0.3, 2.0, sx=1.2)
        glow(g, ox + 52, oy + 13.5, 6, RGB_['amber'], 0.35, 2.0, sx=1.5)
    def barrel(self, b, st):
        o = -st.rc
        bev(b, 11 + o, 3, 5, 15, 'Q', 'q', 'n')                                              # the root collar
        for fy, flip in ((3, 1), (15, -1)):                                                   # two curved fingers
            for k in range(26):
                yy = fy + (0 if k < 18 else flip * (k - 18) // 2)
                b.put(16 + k + o, yy, 'f' if k % 5 else 'Q'); b.put(16 + k + o, yy + 1, 'Q'); b.put(16 + k + o, yy + 2, 'q')
        tail = {'fire': (22, 34, None)}.get(st.state, (17,) * 3)[st.i if st.fire else 0]
        if tail is not None:
            for j, r in enumerate(PODART):
                for k, c in enumerate(r):
                    if c != '.': b.put(tail + o + k, 6 + j, c)
        if st.fire and st.i == 2:
            b.stamp(22, 6, SMOKE[0], {'L': 'g', 'M': 'g', 'S': 'V'}) if False else None
        breech(b, 10, 15, *HT)
    def bhurt(self, b, st):
        move(b, 34, 2, 9, 7, 0, 2); crack(b, [(22, 3), (23, 5)]); wire(b, [(30, 9), (31, 11), (33, 12)], 'q', 'n')
        for k in range(3): b.put(26, 17 + (k + st.i) % 3, 'V')
        spark(b, 36, 12, False) if st.i == 0 else None
    def bbreak(self, b, st):
        for y in (3, 4, 5): b.erase(31, y)
        return cleave(b, lambda y: 32, 2, 3, rows=(0, 8))
    def bwreck(self, b, st):
        b.rect(24, 8, 6, 5, 'V'); b.put(26, 9, 'E'); wire(b, [(30, 5), (32, 7), (34, 9)], 'q', 'n')
        crack(b, [(20, 3), (21, 8), (20, 12)])
    def bafter(self, b, st):
        if st.fire and st.i == 2:
            for (x, y) in ((40, 10), (42, 8), (43, 12), (45, 10), (38, 7)): b.put(x, y, 'g'); b.put(x + 1, y, 'y')
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire':
            tail = (22, 34, 0)[i]
            if i < 2: glow(g, ox + tail + 4, oy + 10, (9, 8)[i], RGB_['violet'], 0.5, 2.0, sx=1.4); glow(g, ox + tail - 2, oy + 10, 4, RGB_['green'], 0.5, 1.8)
            else: glow(g, ox + 40, oy + 10, 9, RGB_['green'], 0.25, 2.0, sx=1.4)
        if state == 'idle': glow(g, ox + 21, oy + 10, 5, RGB_['violet'], 0.3, 2.0)
SMOKE = [art(".LL..\nLMML.\n.LMSL\n..LL.")]

# ============================================================ POLLEN TURRET (turret, tier 1)
class PollenTurret(SporeW):
    id = 'sporeling_pollen_turret'; aim = 'turret'
    pivot = (32, 15)
    blen, bwid = 42, 23
    bpivot = (8, 11)
    bmuzzle = (30, 11)
    out_notes = ('OUTSIDE half of the Sporeling Pollen Turret (a TURRET, grown): a rounded seat, a pink flower bud on the left that opens a little on the loop and a pollen sac cluster with a gill vent on the right. '
                 'damaged: the bud is torn and drooping, the sacs leak; disabled: scorched, wilted, the bud brown and closed, never destroyed.')
    notes = ('INSIDE half of the Sporeling Pollen Turret: a pollen bellows (cream sac that breathes), two yellow pollen jars, a fibrous feed root, power coupling and five spore sacs. '
             'damaged: a jar has cracked and spilt, sacs withered; disabled: the bellows collapsed. The rotating head sporeling_pollen_turret_barrel: a flower head, pink petals round a yellow stamen nozzle, with a sensor eye on a stalk; fire: a yellow pollen cloud.')
    def outside(self, s, st):
        pw = st.powered; i = st.i
        self.oturret_seat(s, 15)
        organic(s, 3, 7, 16, 18, HT2, 5)
        o = i if pw else 0                                                                      # the bud opens one pixel
        fillpoly(s, [(11, 5 - o), (5, 14), (11, 24), (17, 14)], 'p' if pw else 'q'); fillpoly(s, [(11, 5 - o), (11, 24), (17, 14)], 'm' if pw else 'n')
        s.put(9, 10, 'H') if pw else None; s.vline(11, 8, 12, 'P' if pw else 'n')
        organic(s, 45, 6, 16, 18, HT2, 5)
        sac(s, 47, 9, 6, 8, ('y', 'a', 'u'), 'H'); sac(s, 54, 12, 5, 7, ('y', 'a', 'u'), 'H')
        gills(s, 47, 19, 12, 4, 'n', 'q')
        if pw: s.put(51 + i * 2, 5, 'y'); s.put(55 - i, 3, 'y')
        for (x, y) in ((24, 8), (40, 8), (24, 22), (40, 22)): s.put(x, y, 'f')
    def inside(self, s, st):
        y = self.iy; pw = st.powered; i = st.i
        self.rhousing(s, y)
        coupling(s, 3, y + 8, st, 'g')
        sac(s, 16, y + 4, 14, 17 - (i if pw else 0), ('f', 'f', 'Q'), 'H')                      # the pollen bellows
        for k, jx in enumerate((33, 41)):                                                       # pollen jars
            bev(s, jx, y + 6, 7, 13, 'M', 'S', 'W', cham=False); s.rect(jx + 1, y + 9, 5, 9, 'D')
            if pw: s.rect(jx + 1, y + 11, 5, 7, 'a'); s.hline(jx + 1, y + 11, 5, 'y')
        hatch(s, 50, y + 7, st, 10, 11)
        self.rstrip(s, st, y)
    def hurt_out(self, s, st):
        s.rect(3, 4, 17, 11, '.'); fillpoly(s, [(8, 9), (5, 16), (11, 24), (17, 16), (13, 12)], 'q'); s.put(11, 8, 'q'); s.put(12, 9, 'n')
        for k in range(3): s.put(9, 24 + (k * 2 + st.i) % 5, 'p')
        crack(s, [(52, 7), (53, 12), (51, 17)])
        for k in range(3): s.put(58, 13 + (k + st.i) % 6, 'y')
        spark(s, 28, 9, False) if st.i else None
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(24, 8), (26, 12), (25, 16)], [(52, 7), (53, 12), (51, 17)]], dents=[(46, 20, 6, 3), (6, 20, 5, 4)],
                 soots=[(20, 3, 0), (46, 5, 1), (8, 7, 2)], wires_=[], sparks=[(30, 6), (12, 10)])
        s.rect(3, 4, 17, 14, '.'); fillpoly(s, [(8, 12), (5, 20), (11, 25), (17, 20), (14, 14)], 'n')
    def hurt_in(self, s, st):
        y = self.iy
        dead_cells(s, st, y + STRIP_DY)
        crack(s, [(43, y + 6), (44, y + 11), (42, y + 16)])
        for k in range(3): s.put(43, y + 19 + (k * 2 + st.i) % 5, 'y')
        spark(s, 54, y + 18, False) if st.i else spark(s, 10, y + 18, False)
    def wreck_in(self, s, st):
        y = self.iy
        s.rect(16, y + 4, 14, 8, '.'); sac(s, 16, y + 12, 14, 9, ('S', 'E', 'D'), None)
        crack(s, [(35, y + 6), (36, y + 11), (34, y + 16)]); crack(s, [(44, y + 6), (45, y + 12)])
        wire(s, [(14, y + 22), (16, y + 25), (22, y + 25)], 'q', 'n')
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        self.rstrip_glow(g, ox, oy, state, i, y)
        glow(g, ox + 12, oy + y + 14, 3, RGB_['green'], 0.5, 2.0)
        for jx in (36, 44): glow(g, ox + jx, oy + y + 14, 6, RGB_['yellow'], 0.25, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        glow(g, ox + 11, oy + 14, 8, RGB_['magenta'], 0.25, 2.0)
        glow(g, ox + 52, oy + 13, 7, RGB_['yellow'], 0.25, 2.0)
    def barrel(self, b, st):
        o = -st.rc
        for k in range(8):                                                                     # petals fanned round the nozzle
            ang = math.radians(-60 + k * 17)
            tx, ty = 20 + o + math.cos(ang) * 11, 11 + math.sin(ang) * 10
            fillpoly(b, [(14 + o, 11), (18 + o + math.cos(ang - 0.5) * 6, 11 + math.sin(ang - 0.5) * 6), (tx, ty), (18 + o + math.cos(ang + 0.5) * 6, 11 + math.sin(ang + 0.5) * 6)], 'p' if k % 2 else 'm')
        bev(b, 17 + o, 8, 9, 7, 'f', 's', 'Q')
        cylh(b, 24 + o, 9, 7, 5, 'yaau'); b.rect(30 + o, 9, 1, 5, 'D')
        if st.fire: b.rect(30 + o, 10, 1, 3, 'H')
        hub(b, 11, 17, 'Q', 'f', 'q')
        eye(b, 11, 0, 'g'); b.put(12, 3, 'q'); b.put(12, 4, 'Q')
    def bhurt(self, b, st):
        b.rect(17, 0, 12, 4, '.'); b.rect(26, 16, 6, 6, '.'); wire(b, [(25, 15), (27, 18)], 'q', 'n')
        for k in range(3): b.put(27, 17 + (k + st.i) % 4, 'y')
        crack(b, [(18, 8), (19, 12), (17, 15)]); spark(b, 28, 4, False) if st.i == 0 else None
    def bbreak(self, b, st): return cleave(b, lambda y: 25, 2, 3, rows=(2, 22))
    def bwreck(self, b, st):
        for y in (9, 14): wire(b, [(23, y), (25, y + 1), (27, y + 1)], 'q', 'n')
        b.rect(17, 0, 14, 6, '.'); crack(b, [(18, 8), (19, 12), (17, 15)], 'K', 'S')
    def bafter(self, b, st):
        if st.fire: stamp_flash(b, st, 31, 11, F_POLLEN)
    def bglow(self, state, i, g, ox, oy):
        if state == 'fire': fire_glow(g, ox, oy, i, 31, 11, rgb=(255, 210, 58), core=(255, 245, 200), scale=0.9)
        if state != 'disabled': glow(g, ox + 12.5, oy + 1.5, 3, RGB_['green'], 0.5, 2.0)

# ============================================================ components
class SporeC(LComp):
    dark = DK
    glow_pad = (10, 10, 10, 10)

def petal(s, cx, cy, ang, r0, r1, w, tones):
    """a petal: a kite from radius r0 to r1 along angle ang (degrees, 0 = up, clockwise), width w; tone by how much it faces the top-left light."""
    a = math.radians(ang); ux, uy = math.sin(a), -math.cos(a); vx, vy = -uy, ux
    mid = (r0 + r1) * 0.5
    pts = [(cx + ux * r0, cy + uy * r0), (cx + ux * mid + vx * w, cy + uy * mid + vy * w), (cx + ux * r1, cy + uy * r1), (cx + ux * mid - vx * w, cy + uy * mid - vy * w)]
    lit = -(ux + uy) / 1.414                                  # 1 facing up-left
    fillpoly(s, pts, tones[0] if lit > 0.35 else (tones[2] if lit < -0.35 else tones[1]))
    fillpoly(s, [pts[0], pts[1], pts[2]], tones[1] if lit > 0.35 else (tones[2] if lit < -0.35 else tones[1])) if False else None
    s.put(int(round(cx + ux * (r1 - 1))), int(round(cy + uy * (r1 - 1))), 'H' if tones[0] in ('p', 'f') else tones[0])

class BloomReactor(SporeC):
    id = 'sporeling_bloom_reactor'; cells = (4, 4)
    anims = [('on', 'on', 4, 5), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    OPEN = [0, 2, 3, 1]
    notes = ('Sporeling Bloom Reactor, 4x4: a brown, root-veined basin round a flower that blooms around a glowing amber core: eight cream-and-pink petals that open and close on the 4-frame loop, spore specks drifting up. '
             'Off: the bloom is a closed bud over a dark core. Damaged: two petals torn and drooping, the basin cracked and weeping, the core stuttering. '
             'Disabled: withered brown petals, a dead dry core, the basin split.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 62, 62, 'q', 10); rim(s, 'q', 'Q', 'n')
        for a in (0, 90, 180, 270):                                                           # root veins to the corners
            for k in range(8, 28): 
                a_ = math.radians(a + 45); s.put(int(32 + math.sin(a_) * (k + 6) + (k % 3 == 0)), int(32 - math.cos(a_) * (k + 6)), 'Q')
        for (cx, cy) in ((8, 8), (55, 8), (8, 55), (55, 55)): sac(s, cx - 4, cy - 4, 9, 9, ('X', 'V', 'Z') if on else ('S', 'E', 'D'), 'H' if on else None)
        chamfer_fill(s, 12, 12, 40, 40, 'n', 14); rim(s, 'n', 'q', 'D', (12, 12, 51, 51))
        ext = 7 + (self.OPEN[i] if on else -4)
        for k in range(8):
            a = k * 45 + 22
            if on: petal(s, 32, 32, a, 5, 14 + self.OPEN[i] * 1.5 + (k % 2), 4.5, ('f', 'p', 'm') if k % 2 else ('f', 's', 'p'))
            else: petal(s, 32, 32, a, 4, 9, 3.2, ('Q', 'q', 'n'))
        if on:
            r = 4 + (i % 2) + (1 if i == 2 else 0)
            chamfer_fill(s, 32 - r, 32 - r, 2 * r, 2 * r, 'o', r // 2 + 1); chamfer_fill(s, 32 - r + 1, 32 - r + 1, 2 * r - 2, 2 * r - 2, 'y', max(1, r // 2)); s.put(31, 31, 'H'); s.put(32, 31, 'H')
            for k, (dx, dy) in enumerate(((-12, -16), (14, -13), (-16, 12), (17, 15), (3, -20))): s.put(32 + dx, 32 + dy - ((i + k) % 4) * 2, 'g' if k % 2 else 'y')
        else:
            chamfer_fill(s, 28, 28, 8, 8, 'E', 3); s.put(30, 30, 'W')
        return s
    def hurt(self, s, i):
        for (x, y, w, h) in ((14, 18, 9, 7), (40, 36, 10, 8)): s.rect(x, y, w, h, 'n'); lcrack(s, [(x, y), (x + 3, y + 4), (x + 1, y + h)], 'Q')
        s.stamp(22, 20, art("qqq\n.qn\n..n")); s.stamp(40, 38, art("qqq\n.qn\n..n"))
        lcrack(s, [(3, 14), (6, 19), (4, 24), (9, 28)], 'Q')
        for k in range(4): s.put(8, 58 + k % 2, 'V') if False else None
        for k in range(5): s.put(55, 20 + (k * 3 + i * 2) % 14, 'V' if k % 2 else 'X')
        if i: chamfer_fill(s, 30, 30, 4, 4, 'o', 1)
    def wreck(self, s):
        chamfer_fill(s, 12, 12, 40, 40, 'D', 14); chamfer_fill(s, 24, 24, 16, 16, 'E', 5); chamfer_fill(s, 28, 28, 8, 8, 'K', 3)
        for k in range(8): petal(s, 32, 32, k * 45 + 22, 4, 9 + (k % 3), 2.8, ('q', 'n', 'D'))
        lcrack(s, [(3, 11), (7, 15), (6, 20), (11, 24)], 'Q'); lcrack(s, [(46, 49), (50, 47), (53, 51), (57, 50)], 'Q')
        s.stamp(6, 45, art("KKK\nKqq\nKqn"))
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.85)
        glow(g, ox + 32, oy + 32, 26, (255, 138, 30), 0.3 * k, 1.5)
        glow(g, ox + 32, oy + 32, 8, RGB_['yellow'], 0.6 * k, 1.6)
        for (cx, cy) in ((8, 8), (55, 8), (8, 55), (55, 55)): glow(g, ox + cx, oy + cy, 6, RGB_['violet'], 0.3 * k, 2.0)

class MyceliumShield(SporeC):
    id = 'sporeling_mycelium_shield'; cells = (4, 4)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    notes = ('Sporeling Mycelium Shield, 4x4: a brown basin holding a web of pale mycelium threads that run from a spotted mushroom cap in the middle out to eight blue-glowing nodes; light pulses outward along the threads on the 4-frame loop. '
             'Off: the web is dull and the nodes dark. Damaged: threads snapped, a node burst and oozing, the pulse stutters. Disabled: the web is withered and brown, the cap collapsed.')
    NODES = [(32 + int(round(21 * math.sin(math.radians(a)))), 32 - int(round(21 * math.cos(math.radians(a))))) for a in range(0, 360, 45)]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 62, 62, 'q', 10); rim(s, 'q', 'Q', 'n')
        chamfer_fill(s, 5, 5, 54, 54, 'n', 9)
        for k, (nx, ny) in enumerate(self.NODES):                                              # spokes
            lline(s, 32, 32, nx, ny, 'Q' if on else 'q'); lline(s, 33, 32, nx + 1, ny, 'f' if on and k % 2 == 0 else 'Q') if on else None
        for a in range(8):                                                                    # the ring joining the nodes
            (x0, y0), (x1, y1) = self.NODES[a], self.NODES[(a + 1) % 8]
            lline(s, x0, y0, x1, y1, 'Q' if on else 'q')
        for r in (7, 14):
            for a in range(0, 360, 6): s.put(int(round(32 + r * math.sin(math.radians(a)))), int(round(32 - r * math.cos(math.radians(a)))), 'q')
        for k, (nx, ny) in enumerate(self.NODES):
            c = ('H', 'c', 'b') if on and (k + i) % 4 != 3 else (('c', 'b', 'C') if on else ('W', 'S', 'E'))
            chamfer_fill(s, nx - 3, ny - 3, 7, 7, c[2], 2); chamfer_fill(s, nx - 2, ny - 2, 5, 5, c[1], 1); s.put(nx - 1, ny - 1, c[0]); s.put(nx, ny - 1, c[0])
        if on:                                                                                 # a pulse travels out along the spokes
            for d in ((6 + i * 4), (10 + i * 4)):
                for k, (nx, ny) in enumerate(self.NODES):
                    t = d / 21.0
                    if t <= 1.0: s.put(int(round(32 + (nx - 32) * t)), int(round(32 + (ny - 32) * t)), 'H' if d == 6 + i * 4 else 'c')
        cap(s, 32, 26, 16, 7, ('f', 's', 'Q'), True)
        s.rect(30, 33, 5, 3, 'Q'); s.hline(30, 35, 5, 'q'); s.hline(25, 33, 15, 'q')
        return s
    def hurt(self, s, i):
        for (x, y) in ((24, 30), (25, 28), (26, 26)): s.put(x, y, 'K')
        s.rect(46, 36, 8, 8, 'n'); lcrack(s, [(46, 36), (49, 40), (47, 44)], 'Q')
        for k in range(4): s.put(50, 44 + (k * 2 + i) % 7, 'c' if k % 2 else 'b')
        lcrack(s, [(3, 14), (6, 19), (4, 24)], 'Q')
        s.rect(12, 14, 6, 6, 'n'); s.stamp(12, 14, art("qq.\n.qq"))
    def wreck(self, s):
        for (nx, ny) in self.NODES: chamfer_fill(s, nx - 3, ny - 3, 7, 7, 'D', 2); s.put(nx, ny, 'E')
        cap(s, 32, 28, 16, 5, ('Q', 'q', 'n'), False)
        lcrack(s, [(3, 11), (7, 15), (6, 20), (11, 24), (13, 30)], 'Q'); lcrack(s, [(50, 49), (54, 47), (57, 52), (60, 55)], 'Q')
        s.stamp(6, 45, art("KKK\nKqq\nKqn"))
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        glow(g, ox + 32, oy + 32, 24, (79, 163, 255), 0.18 * k, 1.6)
        for j, (nx, ny) in enumerate(self.NODES):
            if flick is not None and j == 3: continue
            glow(g, ox + nx + .5, oy + ny + .5, 6, (79, 163, 255), (0.5 if (j + i) % 4 != 3 else 0.25) * k, 2.0)

class GardenBay(SporeC):
    id = 'sporeling_garden_bay'; cells = (2, 2)
    glow_pad = (6, 6, 6, 6)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    notes = ('Sporeling Garden Bay, 2x2: a brown planter tray under a grow lamp, with two spotted mushrooms and a leafy green sprout that sway on the 4-frame loop while tiny oxygen bubbles rise. '
             'Off: the lamp is out and the plants droop pale. Damaged: the lamp flickers and hangs by one corner, a mushroom has toppled, the leaves browned. Disabled: withered brown stalks in cracked soil.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        chamfer_fill(s, 0, 0, 32, 32, 'q', 4); rim(s, 'q', 'Q', 'n')
        s.rect(3, 22, 26, 7, 'n'); s.hline(3, 22, 26, 'q')
        for x in range(4, 28, 3): s.put(x, 24 + (x % 2), 'q'); s.put(x + 1, 26, 'q')
        bev(s, 4, 3, 24, 4, 'M', 'S', 'W', cham=False)                                        # the grow lamp
        s.rect(7, 4, 18, 2, 'y' if on else 'E')
        sway = [0, 1, 0, -1][i] if on else 0
        for (mx, h) in ((9, 8), (22, 6)):                                                     # mushrooms
            s.rect(mx, 22 - h + 2, 3, h, 'f'); s.vline(mx + 2, 22 - h + 2, h, 'Q')
            cap(s, mx + 1 + sway, 22 - h - 2, 10 if mx < 15 else 8, 5, ('f', 's', 'Q') if on else ('Q', 'q', 'n'))
        for k, (lx, ly) in enumerate(((15, 21), (16, 17), (14, 13))):                         # the sprout
            s.rect(lx + sway * (k > 0), ly, 2, 5, 'g' if on else 'q')
            lline(s, lx - 3 + sway, ly - 1 + k, lx + sway, ly + 2, 'g' if on else 'q'); lline(s, lx + 5 + sway, ly - 1 + k, lx + 1 + sway, ly + 2, 'T' if on else 'n')
        if on:
            for k, (bx, by) in enumerate(((6, 18), (13, 14), (20, 16), (26, 12))): s.put(bx, by - ((i + k) % 4) * 3, 'H'); s.put(bx + 1, by - ((i + k) % 4) * 3 + 1, 'L')
        return s
    def hurt(self, s, i):
        s.rect(22, 8, 9, 6, '.'); s.hline(22, 18 + i, 5, 'f'); s.put(26, 20, 'u')
        s.rect(4, 3, 24, 4, '.'); bev(s, 4, 3 + i, 20, 3, 'M', 'S', 'W', cham=False); lline(s, 24, 5, 27, 8, 'q')
        s.rect(7, 5 + i, 14, 1, 'y' if i == 0 else 'E')
        for (x, y) in ((14, 14), (15, 16), (14, 18)): s.put(x, y, 'u')
        spark(s, 25, 6, False) if i else None
    def wreck(self, s):
        s.rect(4, 3, 24, 4, '.'); s.stamp(6, 5, art("MMMMS\nWEEEW")); s.stamp(20, 8, art("qq\nnq"))
        s.rect(3, 22, 26, 7, 'n'); s.hline(8, 25, 6, 'K'); s.hline(18, 27, 6, 'K')
        for x in (9, 15, 22): s.vline(x, 14, 8, 'n'); s.put(x - 1, 13, 'n'); s.put(x + 1, 14, 'n')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        glow(g, ox + 16, oy + 6, 14, RGB_['yellow'], 0.3 * k, 1.8, sx=1.3)
        glow(g, ox + 16, oy + 16, 9, RGB_['green'], 0.2 * k, 2.0)

WEAPONS = [SporeCannon, RotPod, PollenTurret]
COMPS = [BloomReactor, MyceliumShield, GardenBay]
ALL = WEAPONS + COMPS
