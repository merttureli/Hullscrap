"""Four base parts a player can own that drew as placeholders (owner playtest, 2026-11-06):
 battering_bow        ram, scrap, 4x2: a wedge of welded girders pointing UP (outward at rotation 0), ram-plate armour, hazard-taped head, two latch claws
 inertial_dampener    utility, standard, 2x2: a heavy mass hung on four spring dampers, its field ring pulsing
 reactor_scrap_kettle reactor, scrap, 4x4: Ma's Kettle, a big dented kettle on a stove plate with the amber core boiling behind a porthole in its lid
 afterburner          engine, standard, tier 2: a hull mount, the inside half (4x2: the air intake that eats the room's air, the console, the fuel tank)
                      and the outside half (4x2: one big reheat can with an iris of petals; the plume has shock diamonds)
Same pipeline as the lines modules (LComp / Half2, comp_base.export). Preview: python3 parts_art.py --sheet out.png."""
import math
import pal_guns                        # ')' pale straw (RGB only here; build_all registers it)
from lines_kit import *
from comp_new import lamp
from lines_eng_base import EngBase, Half2, bell_gen
from lines_eng_std import ring_a
from lines_smelter import disc_lit

AIR = RGB['L']                         # glow hues: palette colours only

# ============================================================ BATTERING BOW (ram, scrap, 4x2)
def girder(s, x0, y0, x1, y1, tone='S'):
    """a welded I-beam from above, 4px wide: the lit flange, the web and the shaded flange (rust tone 'u' for a salvaged one)."""
    hi, mid, lo = {'S': ('M', 'S', 'E'), 'u': ('Q', 'u', 'n'), 'W': ('S', 'W', 'D')}[tone]
    thick(s, x0, y0, x1, y1, 4, mid, hi, lo)
    n = max(abs(x1 - x0), abs(y1 - y0))
    for k in range(3, n - 2, 5):                                        # rivets along the web
        s.put(x0 + (x1 - x0) * k // n, y0 + (y1 - y0) * k // n, 'L' if tone == 'S' else 'Q')

class BatteringBow(LComp):
    id = 'battering_bow'; cells = (4, 2)
    glow_pad = (6, 6, 6, 6)
    anims = [('on', 'on', 2, 2), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (0, 1)
    orientation = 'rotation 0: the ram faces UP (place it on the hull edge and turn it outward, as a mount)'
    notes = ('Scrapper "Battering Bow" (ram, scrap, 4x2): a wedge of welded girders pointing UP: a heavy base beam bolted along the bottom, two raking girders (one steel, one '
             'rust) and a king post meeting at a battered ram head; dark ram-plate armour with big bolt heads fills the wedge (the walls_ram plating); the head carries the '
             'amber-and-black hazard tape on its leading edge, as ram plating does, and two hooked latch claws (it latches on to what it hits), drawn by a chain from a '
             'winch at the base. The nose is a solid steel point. Unpowered: the on loop is only its amber lamp blinking. '
             'Damaged: the left claw bent back, a weld on the rust girder cracked open, the head dented deeper and scorched. '
             'Disabled: the head knocked askew, the rust girder snapped at its weld, the right claw broken off and lying on the plate, the chain slack.')
    APEX = 31.5
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 32)
        ax = self.APEX
        # the wedge's armour plate: a triangle under the raking girders, ram plating's gunmetal and bolt heads
        for y in range(3, 31):
            hw = 1.5 + (y - 3) * 1.12
            for x in range(int(ax - hw), int(ax + hw) + 1):
                if 1 <= x <= 62: s.put(x, y, 'W')
        s.hline(16, 20, 32, 'E'); s.vline(23, 20, 7, 'E'); s.vline(40, 20, 7, 'E')                 # plate seams
        for (bx, by) in ((19, 22), (42, 22), (11, 26), (50, 26), (27, 15), (34, 15)):
            s.stamp(bx, by, art("EEE\nEHE\nEEE"))
        stamp_on(s, 24, 22, art(".KK.\nKEEM\n.MM."))                                          # a dent
        # the base beam, two raking girders (steel and rust) and the king post
        s.rect(1, 26, 62, 5, 'S'); s.hline(1, 26, 62, 'M'); s.hline(1, 28, 62, 'W'); s.hline(1, 29, 62, 'E'); s.hline(1, 30, 62, 'D')
        bolts(s, [(4, 27), (16, 27), (46, 27), (57, 27)])
        girder(s, 4, 27, 27, 6, 'S'); girder(s, 59, 27, 36, 6, 'u'); girder(s, 31, 26, 31, 12, 'W')
        for (x, y) in ((5, 24), (55, 24), (29, 24), (33, 24)): weld(s, x, y, 4)
        # the winch at the base and its chain up the king post to the nose
        s.rect(26, 21, 12, 6, 'E'); s.hline(26, 21, 12, 'S'); s.hline(26, 26, 12, 'D'); s.put(26, 22, 'M')
        for x in range(27, 37, 2): s.put(x, 23, 'M'); s.put(x, 24, 'W')
        for y in range(12, 21, 2): s.put(32, y, 'M'); s.put(32, y + 1, 'E'); s.put(33, y, 'W')
        # the nose cap: a solid steel point with the hazard tape along both leading edges
        for y in range(0, 12):
            hw = 1 + y * 1.12
            for x in range(int(ax - hw), int(ax + hw) + 1):
                dx = x + .5 - ax
                edge = hw - abs(dx)
                if edge < 3.2: c = 'a' if ((x + (y if dx < 0 else -y)) // 2) % 2 == 0 else 'K'
                else: c = 'M' if dx < -2 else ('S' if dx < 3 else 'W')
                s.put(x, y, c)
        for x in range(int(ax - 13), int(ax + 14)): s.put(x, 12, 'E' if s.get(x, 12) != '.' else '.')
        s.put(int(ax) - 1, 0, 'y'); s.put(int(ax), 0, 'y')
        s.stamp(29, 7, art("EEE\nEHE\nEEE"))
        lamp(s, 31, 4, 'a', on and i == 0)
        # two latch claws either side of the nose, hooked forward
        s.stamp(15, 4, art(".LM.\nLM..\nMS..\nSW..\n.SWE"))
        s.stamp(45, 4, art(".ML.\n..ML\n..SM\n..WS\nEWS."))
        for (x0, x1) in ((18, 22), (42, 46)): s.hline(x0, 8, x1 - x0, 'M'); s.hline(x0, 9, x1 - x0, 'W')     # the claws' brackets on the nose
        return s
    def hurt(self, s, i):
        s.rect(15, 4, 4, 5, '.'); s.stamp(13, 7, art("LMS.\n.MSW\n..WE"))               # the left claw bent back
        for (x, y) in ((47, 19), (48, 19), (48, 20), (49, 20)): s.put(x, y, 'K')       # a weld on the rust girder cracked open
        s.put(50, 18 + i, 'y'); s.put(46, 21 - i, 'H' if i else 'y')
        stamp_on(s, 23, 7, SCORCH_S); stamp_on(s, 33, 8, art(".KKK.\nKEEEM\n.MMM."))
    def wreck(self, s):
        shift_rect(s, 18, 46, 0, 12, 2, 1)                                             # the nose knocked askew
        s.rect(46, 17, 5, 4, '.'); s.stamp(46, 17, art("K..KK\nKK.KD\n.K..K"))          # the rust girder snapped at its weld
        shift_rect(s, 49, 62, 8, 18, 1, 1)
        s.rect(46, 4, 5, 6, '.'); s.stamp(9, 21, art(".KKK.\nKLMSK\n.KSWK\n..KK."))     # the right claw broken off, lying on the plate
        for y in range(13, 22, 2): s.put(30 + (y % 4 == 1), y, 'E')
        stamp_on(s, 14, 12, SCORCH_L)
    def glow(self, state, i, g, ox, oy, flick=None):
        if (i == 0 and flick is None) or flick == 1:
            glow(g, ox + 32, oy + 5, 4.5, AMBER, 0.55, 2.0)
        if flick is not None: glow(g, ox + 49, oy + 19, 3.5, YEL, 0.5, 2.0)

# ============================================================ INERTIAL DAMPENER (utility, standard, 2x2)
class InertialDampener(LComp):
    id = 'inertial_dampener'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (0, 2)
    notes = ('Concord Inertial Dampener (utility, standard, 2x2): a heavy round mass hung in a clean square frame on four spring dampers (a piston and a coil each, bolted '
             'to the corners); the mass carries a ring of blue field lamps and the field ring round it pulses out (glow), the springs breathe a pixel in and out. '
             'Registry stencil, a green power lamp. '
             'Damaged: the lower-right damper has snapped and the mass has sagged a pixel toward it, the field ring stutters. '
             'Disabled: two dampers broken, the mass down on the frame with a cracked hub, the field dark.')
    MASS = (15.5, 15.5)
    def damper(self, s, x0, y0, x1, y1, squeeze, broken=False):
        """a spring damper from a corner bracket (x0, y0) to the mass (x1, y1): a piston rod and a coil."""
        s.rect(x0 - 2, y0 - 2, 4, 4, 'M'); s.put(x0 - 2, y0 - 2, 'L'); s.put(x0 + 1, y0 + 1, 'S'); s.put(x0 - 1, y0 - 1, 'E')
        n = max(abs(x1 - x0), abs(y1 - y0))
        for k in range(1, n):
            x, y = x0 + (x1 - x0) * k // n, y0 + (y1 - y0) * k // n
            if broken and k > n // 2: break
            if k % 2 == squeeze % 2: s.put(x, y, 'L'); s.put(x + 1, y, 'E') if x1 > x0 else s.put(x - 1, y, 'E')
            else: s.put(x, y, 'S')
    def interior(self, state, i, sag=(0, 0), broken=()):
        on = state == 'on'
        s = Spr(32, 32)
        bev(s, 1, 1, 30, 30, 'M', 'S', 'W')
        recess(s, 3, 3, 26, 26, 'E', 'K')
        stencil(s, 5, 27, 'L', 2)
        sq = i % 2 if on else 0
        mx, my = self.MASS[0] + sag[0], self.MASS[1] + sag[1]
        for k, (cx, cy) in enumerate(((6, 6), (25, 6), (6, 25), (25, 25))):
            self.damper(s, cx, cy, int(mx + (-5 if cx < 16 else 5)), int(my + (-5 if cy < 16 else 5)), sq + k, k in broken)
        # the mass: a heavy disc, its field-lamp ring and the hub
        disc_lit(s, mx, my, 0, 7.6, 'M', 'S', 'W')
        disc_lit(s, mx, my, 6.6, 7.6, 'L', 'S', 'E')
        for k in range(8):
            a = k * math.pi / 4 + math.pi / 8
            lx, ly = int(mx - .5 + math.cos(a) * 5.2), int(my - .5 + math.sin(a) * 5.2)
            s.put(lx, ly, ('b' if (k + i) % 4 != 0 else 'H') if on else 'W')
        circle(s, mx, my, 2.6, 'W'); circle(s, mx - .3, my - .3, 1.6, 'S'); s.put(int(mx) - 1, int(my) - 1, 'L')
        s.put(26, 27, 'g' if on else 'W'); s.put(27, 27, 'g' if on else 'W')
        return s
    def frame(self, state, i):
        if state == 'damaged':
            s = self.interior('on', self.DMG[i], sag=(1, 1), broken=(3,)).copy()
            for k in range(8):
                a = k * math.pi / 4 + math.pi / 8
                if (k + i) % 3 == 0: s.put(int(16.5 - .5 + math.cos(a) * 5.2), int(16.5 - .5 + math.sin(a) * 5.2), 'E')
            s.put(23 + i, 23, 'y'); s.put(22, 24 - i, 'H')
        elif state == 'disabled':
            s = self.interior('off', 0, sag=(2, 2), broken=(1, 3)).copy()
            dm = dict(DARK); s = s.sub(dm)
            crack(s, [(15, 14), (17, 17), (19, 18)], 'M'); stamp_on(s, 8, 20, SCORCH_S)
        else:
            s = self.interior(state, i)
        s = s.copy(); outline_all(s); s = drop_shadow(s)
        return s
    def glow(self, state, i, g, ox, oy, flick=None):
        mx, my = self.MASS
        k = 1.0 if flick is None else (0.4 if flick else 0.75)
        if flick is not None: mx += 1; my += 1
        r = [9, 11, 13, 15][i % 4]                                         # the field ring spreading out
        for y in range(g.h):
            for x in range(g.w):
                d = ((x + .5 - ox - mx) ** 2 + (y + .5 - oy - my) ** 2) ** .5
                a = max(0.0, 1 - abs(d - r) / 2.2) * (0.42 - 0.05 * (i % 4)) * k
                if a > 0.02: g.over(x, y, BLUE + (int(255 * a),))
        glow(g, ox + mx, oy + my, 8, BLUE, 0.3 * k, 1.8)
        glow(g, ox + 27, oy + 27.5, 3, GREEN, 0.45, 2.0)

# ============================================================ MA'S KETTLE (reactor, scrap, 4x4)
class ScrapKettle(LComp):
    id = 'reactor_scrap_kettle'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    dark = {'(': 'n', ')': 'q', 'e': 'n'}
    notes = ('Scrapper "Ma\'s Kettle" (reactor, scrap, 4x4, unique): Ma Gantry\'s own reactor, a big dented copper kettle on a patched stove plate. The amber core boils '
             'behind a caged porthole in the lid (bubbles rise, the lid rattles a pixel), the spout puffs steam, the handle arches over it wrapped in red rag; a bolted '
             'steel patch over an old dent, hazard tape on the plate, a power cable out of the back, and a mug of tea on the corner of the plate. '
             'Damaged: the spout has split and steam jets sideways, the rag on the handle is smouldering, a dent glows where the core is too close, the lid rattles hard. '
             'Disabled: the core dead behind cracked glass, the lid knocked half off, the spout broken off and lying on the plate, the mug knocked over.')
    C = (27, 35); R = 20
    def interior(self, state, i, lid=0):
        on = state == 'on'
        s = Spr(64, 64)
        cx, cy = self.C; R = self.R
        # the stove plate: mismatched salvaged steel plates, a hazard strip, bolts
        chamfer_fill(s, 1, 1, 61, 61, 'E', 7)
        plate(s, 2, 2, 30, 26, 'W'); plate(s, 31, 2, 30, 30, 'S'); plate(s, 2, 27, 24, 34, 'S'); plate(s, 25, 31, 36, 30, 'W')
        hazard(s, 30, 57, 28, 4)
        # the power cable out of the back (top), clamped
        s.rect(41, 1, 6, 9, 'q'); s.vline(41, 1, 9, 'Q'); s.vline(46, 1, 9, 'n'); s.rect(40, 4, 8, 2, 'S'); s.hline(40, 4, 8, 'M')
        # the spout: out of the right side, rising and tapering to a whistle cap
        for k in range(15):
            x = 44 + k; yc = 41 - k * 0.55; w = 7 - k * 0.3
            y0, y1 = int(yc - w / 2), int(yc + w / 2)
            for y in range(y0, y1 + 1): s.put(x, y, 'a' if y == y0 else ('n' if y == y1 else ('u' if y > y0 + 1 else 'Q')))
        s.rect(58, 31, 3, 4, 'S'); s.hline(58, 31, 3, 'L'); s.put(60, 34, 'E')
        if on:
            puff = [[(59, 29), (60, 28)], [(60, 26), (59, 25), (61, 27)], [(60, 23), (61, 22), (59, 24)], [(61, 20), (60, 21)]][i % 4]
            for k, (x, y) in enumerate(puff): s.put(x, y, 'H' if k == 0 else 'L')
        # the kettle: a copper dome lit top-left, rivets round its foot
        for y in range(cy - R - 1, cy + R + 2):
            for x in range(cx - R - 1, cx + R + 2):
                dx, dy = x + .5 - cx, y + .5 - cy
                d = (dx * dx + dy * dy) ** .5
                if d > R: continue
                h = ((dx + 7) ** 2 + (dy + 7) ** 2) ** .5
                c = 'y' if h < 2.5 else ('a' if h < 9 else ('u' if h < 21 else ('q' if h < 29 else 'n')))
                if d > R - 1.2: c = 'u' if dx + dy < -8 else ('q' if dx + dy < 10 else 'n')
                s.put(x, y, c)
        for k in range(16):
            a = k * math.pi / 8
            bx, by = int(cx - .5 + math.cos(a) * (R - 2.5)), int(cy - .5 + math.sin(a) * (R - 2.5))
            s.put(bx, by, 'y' if math.cos(a) + math.sin(a) < -.5 else ('a' if math.cos(a) + math.sin(a) < .5 else 'n'))
        # a steel patch bolted over an old dent, lower left
        bev(s, 12, 43, 10, 8, 'L', 'M', 'S', cham=False); bolts(s, [(13, 44), (19, 44), (13, 48), (19, 48)]); s.hline(15, 47, 4, 'S')
        # the lid: a steel rim and a porthole on the boiling core, a knob on a bridge
        lx, ly = cx + (lid if on else 0), cy + 2
        disc_lit(s, lx, ly, 8.4, 10, 'L', 'M', 'S')
        disc_lit(s, lx, ly, 7.4, 8.4, 'E', 'W', 'S')
        if on:
            circle(s, lx, ly, 7.4, 'o'); circle(s, lx - .4, ly - .4, 5.4, 'y'); circle(s, lx - 1, ly - 1, 2.6, ')')
            for k, (bx, by) in enumerate(((-3, 3), (2, 2), (-1, -1), (3, -3), (-4, -2))):
                byy = ly + by - ((i + k) % 4)
                if (bx ** 2 + (byy - ly) ** 2) ** .5 < 6.4: s.put(int(lx + bx), int(byy), 'H' if k % 2 else 'o')
        else:
            circle(s, lx, ly, 7.4, 'D'); circle(s, lx - .5, ly - .5, 5, 'E'); s.put(int(lx) - 3, int(ly) - 3, 'W')
        s.vline(int(lx) - 1, int(ly) - 8, 17, 'M'); s.vline(int(lx), int(ly) - 8, 17, 'S')
        circle(s, lx - .5, ly - .5, 2.2, 'M'); circle(s, lx - .8, ly - .8, 1.3, 'L'); s.put(int(lx), int(ly), 'S')
        for (bx, by) in ((-7, -4), (6, -4), (-7, 4), (6, 4)): s.put(int(lx + bx), int(ly + by), 'L')
        # the handle: a raised bar across the back of the kettle, its shadow on the copper, a red rag wound round its middle
        for x in range(10, 45):
            s.put(x, 21, 'L'); s.put(x, 22, 'S'); s.put(x, 23, 'W')
            if s.get(x, 25) in 'yauqn': s.put(x, 25, 'n'); s.put(x, 26, 'q') if s.get(x, 26) in 'ya' else None
        for (x0, x1) in ((9, 12), (42, 45)):
            s.rect(x0, 20, x1 - x0 + 1, 5, 'S'); s.hline(x0, 20, x1 - x0 + 1, 'L'); s.hline(x0, 24, x1 - x0 + 1, 'E'); s.put(x0 + 1, 22, 'L')
        for x in range(22, 33):
            s.put(x, 21, 'p' if x % 3 == 0 else 'r'); s.put(x, 22, 'r'); s.put(x, 23, 'e' if x % 2 else 'r')
        # the mug of tea, bottom-left corner of the plate
        disc_lit(s, 7.5, 53.5, 2.6, 3.9, 'H', 'L', 'M'); circle(s, 7.5, 53.5, 2.6, 'q'); s.put(6, 52, 'Q'); s.put(7, 52, 'Q')
        s.rect(11, 52, 2, 3, 'L'); s.put(12, 54, 'M')
        if on: s.put(7, 48 - i % 2, 'M'); s.put(8, 47 - i % 2, 'L'); s.put(7, 46 - i % 2, 'M')
        # a lamp plate, top-left
        bev(s, 4, 4, 11, 9, 'M', 'S', 'W'); s.rect(6, 6, 2, 2, 'a' if on else 'n'); s.rect(10, 6, 2, 2, 'g' if on and i % 2 == 0 else 'W')
        s.hline(6, 10, 7, 'D')
        clip(s, 1, 1, 61, 61, 7)
        return s
    def frame(self, state, i):
        if state == 'damaged':
            s = self.interior('on', self.DMG[i], lid=(1 if i else -1)).copy(); self.hurt(s, i)
        elif state == 'disabled':
            s = self.interior('off', 0).copy(); dm = dict(DARK); dm.update(self.dark); s = s.sub(dm); self.wreck(s)
        else:
            s = self.interior(state, i, lid=(0, 1, 0, -1)[i % 4] if state == 'on' else 0)
        s = s.copy(); outline_all(s); return drop_shadow(s)
    def hurt(self, s, i):
        for (x, y) in ((50, 35), (51, 35), (50, 36)): s.put(x, y, 'K')                   # the spout split: steam jets sideways
        for k in range(4): s.put(50 + k, 33 - k - i, 'H' if k < 2 else 'L')
        for x in range(22, 33, 2): s.put(x, 20 - (x + i) % 2, 'o'); s.put(x + 1, 20, 'y' if i else 'o')   # the rag smoulders
        s.put(26, 18, 'L'); s.put(28, 17 - i, 'M')
        for (x, y) in ((38, 47), (39, 46), (39, 47), (40, 47)): s.put(x, y, 'o' if i else 'r')   # a dent glows
        crack(s, [(37, 45), (39, 47), (41, 46)], 'y')
    def wreck(self, s):
        cx, cy = self.C
        crack(s, [(cx - 5, cy - 4), (cx - 2, cy - 1), (cx - 3, cy + 2), (cx + 1, cy + 4)], 'M')
        crack(s, [(cx + 13, cy + 5), (cx + 15, cy + 9), (cx + 13, cy + 12)], 'M')
        s.rect(46, 28, 16, 12, '.'); s.rect(44, 35, 3, 6, 'K')                          # the spout broken off, lying on the plate
        s.stamp(46, 51, art(".KKKKKK.\nKqquuuQK\nKnqquuuK\n.KKKKKK."))
        s.rect(3, 49, 11, 9, 'S'); s.stamp(2, 50, art(".KKK..\nKLLLK.\nKMqqMK\n.KKqqq"))  # the mug knocked over, tea spilt
        stamp_on(s, 31, 26, SCORCH_L); stamp_on(s, 12, 30, SCORCH_S)
    def glow(self, state, i, g, ox, oy, flick=None):
        cx, cy = self.C
        k = 1.0 if flick is None else (0.55 if flick else 0.8)
        f = [1.0, 0.85, 0.95, 0.8][i % 4]
        glow(g, ox + cx, oy + cy + 2, 26, ORANGE, 0.3 * f * k, 1.4)
        glow(g, ox + cx - .5, oy + cy + 1.5, 8, YEL, 0.55 * f * k, 1.6)
        glow(g, ox + 7, oy + 7, 4, AMBER, 0.45 * k, 2.0)
        if i % 2 == 0: glow(g, ox + 11, oy + 7, 3.5, GREEN, 0.4 * k, 2.0)
        if flick is not None:
            glow(g, ox + 27, oy + 20, 6, ORANGE, 0.5 if flick else 0.35, 1.8)
            glow(g, ox + 39, oy + 46.5, 5, ORANGE, 0.45 if flick else 0.3, 1.8)

# ============================================================ AFTERBURNER (engine, standard, tier 2, 4x2 + 4x2)
HELMET = """
.aaaaa.
aaKKKaa
aKHHHKa
aKccHKa
aKKKKKa
.aaaaa."""

class Afterburner(EngBase):
    id = 'afterburner'; KIND = 'std'
    pad_out = (12, 40, 12, 4)
    anchors_out = {'exhaust': (32, 1)}
    anchors_in = {'power_coupling': (51, 29), 'repair_hatch': (51, 18)}
    notes = ('Concord Afterburner (engine, standard, tier 2, unique), a hull mount (outward is up). OUTSIDE: one big reheat can on the Concord nacelle plate, its tail '
             'heat-tinted in straw and brown bands, an amber Mk2 collar ring, a ring of fuel injectors under the mouth and an iris of petals round it; the exhaust '
             'plume (glow) is long, with shock diamonds. INSIDE: the air intake that burns the engine room\'s air: a big louvred fan cowl whose blades turn, with the '
             'room air drawn toward it (pale dashes); the manned console (a throttle lever and a screen), a warning plate with a helmet (man it in a suit), a fuel tank '
             'on its feed line, the repair hatch and the power coupling. '
             'Damaged: two petals blown off the iris and the can cracked and sputtering; inside, a fan blade gone (the fan wobbles), the tank weeps fuel, the console red. '
             'Disabled: the can bent over and scorched, the iris jammed; inside the fan dead with its cowl split, the tank split, the console dark.')
    def out(self, o, on, i):
        bev(o, 5, 23, 54, 5, 'M', 'S', 'W')                                   # the nacelle plate
        for x in (8, 55): o.put(x, 25, 'L')
        # side struts bracing the can
        for (x0, x1) in ((9, 19), (54, 44)):
            line(o, x0, 23, x1, 12, 'S'); line(o, x0 + (1 if x1 > x0 else -1), 23, x1 + (1 if x1 > x0 else -1), 12, 'W')
        # the can: a wide tube to the mouth
        T = col_tones(22, 'LLMMSSSSSWWWEE')
        for y in range(5, 24):
            for q in range(22): o.put(21 + q, y, T[q])
        for (y, c, c2) in ((6, 'Q', 'q'), (8, 'q', 'n')):                     # heat-tinted bands near the mouth
            o.hline(21, y, 22, c); o.hline(21, y + 1, 22, c2)
        ring_a(o, 21, 15, 22)
        for x in range(23, 42, 3): o.put(x, 19, 'D'); o.put(x, 20, 'L')         # seam rivets
        # the injector ring under the mouth
        for x in range(22, 43, 3): o.put(x, 11, 'a' if on and (x // 3 + i) % 2 else ('u' if on else 'W'))
        # the iris: petals round a wide mouth
        for k, x in enumerate(range(18, 46, 4)):                              # the petals overlap like scales, lit ones and shaded ones in turn
            hi, mid, lo = ('L', 'M', 'S') if k % 2 == 0 else ('M', 'S', 'W')
            o.rect(x, 1, 4, 4, mid); o.hline(x, 1, 3, hi); o.vline(x + 3, 1, 4, lo); o.put(x, 4, 'E' if k % 2 else lo)
        o.hline(18, 0, 28, 'E')
        o.hline(21, 2, 22, 'D'); o.hline(21, 3, 22, 'D')
        if on:
            fl = [0, 1, 0][i % 3]
            o.hline(21 + fl, 2, 22 - 2 * fl, 'o'); o.hline(22, 3, 20, 'o'); o.hline(24 + fl, 3, 16 - 2 * fl, 'y')
            for x in (31, 32): o.put(x, 3, 'H')
            o.put(26 + 2 * (i % 3), 2, 'H'); o.put(37 - 2 * (i % 3), 2, 'y')
        else:
            o.hline(24, 3, 16, 'E')
    def hurt_out(self, o, i):
        for x in (18, 19, 20, 21, 42, 43, 44, 45): o.erase(x, 1); o.erase(x, 2)
        o.put(18, 3, 'W'); o.put(45, 3, 'W')
        crack(o, [(28, 6), (30, 10), (28, 14), (31, 18)], 'M')
        if i == 1: o.hline(24, 3, 16, 'D'); o.hline(28, 3, 6, 'o')
        stamp_on(o, 36, 16, SCORCH_S)
    def wreck_out(self, o):
        shift_rect(o, 17, 47, 0, 12, 3, 1)
        o.hline(21, 12, 22, 'K'); crack(o, [(24, 13), (26, 17), (24, 21)], 'M')
        stamp_on(o, 30, 6, SCORCH_L); stamp_on(o, 22, 14, SCORCH_S)
    def glow_out(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        inten = [0.85, 1.0, 0.92][i % 3]
        glow_xy(g, ox + 32, oy + 2, 16, 36, ORANGE, 0.55 * inten * k, 1.8)
        glow_xy(g, ox + 32, oy + 2, 8, 22, YEL, 0.55 * inten * k, 1.6)
        if flick is None:                                                     # shock diamonds marching up the plume
            for n, dy in enumerate((9, 18, 27)):
                d = dy + 3 * (i % 3)
                glow_xy(g, ox + 32, oy + 2 - d, 3.2, 4.2, RGB[')'], (0.75 - 0.18 * n) * inten, 1.2)
        for x in range(22, 43, 6): glow(g, ox + x + .5, oy + 11.5, 2.5, AMBER, 0.35 * k, 2.0)
    def core(self, c, on, i):
        bev(c, 1, 1, 62, 30, 'M', 'S', 'W')
        # the console (left): a screen with the burn trace and a throttle lever
        bev(c, 3, 3, 15, 12, 'W', 'E', 'D'); recess(c, 5, 5, 8, 6, 'D', 'K')
        for q in range(6):
            h = [1, 2, 2, 3, 3, 4][(q + i) % 6] if on else 1
            c.put(6 + q, 10 - h, 'a' if h > 2 else 'g')
        c.rect(14, 5, 2, 8, 'D'); c.rect(14, 5 + (2 if on else 6), 2, 2, 'r' if on else 'W'); c.put(14, 5 + (2 if on else 6), 'L')
        # the helmet warning plate: man it in a suit
        c.stamp(4, 17, HELMET)
        c.put(13, 18, 'L'); c.put(15, 18, 'L'); c.hline(13, 21, 4, 'D')
        # the air intake (centre): a louvred cowl round a big fan whose blades turn
        bev(c, 19, 2, 25, 27, 'L', 'M', 'S')
        circle(c, 31.5, 15, 11.2, 'K'); circle(c, 31.5, 15, 10.4, 'E')
        ang0 = (i % 3) * (math.pi / 9) if on else 0.2
        for b in range(6):
            a = ang0 + b * math.pi / 3
            for t in range(2, 10):
                x, y = 31.5 + math.cos(a) * t, 15 + math.sin(a) * t
                c.put(int(x), int(y), 'M' if t < 7 else 'S')
                x2, y2 = 31.5 + math.cos(a + .25) * t, 15 + math.sin(a + .25) * t
                c.put(int(x2), int(y2), 'S' if t < 7 else 'W')
        circle(c, 31.5, 15, 2.8, 'W'); circle(c, 31, 14.5, 1.8, 'M'); c.put(30, 13, 'L')
        for y in range(5, 26, 4): c.hline(20, y, 3, 'W'); c.hline(41, y, 3, 'W')       # louvres on the cowl's sides
        if on:                                                                # the room's air drawn in
            for (x0, y0, dx, dy) in ((4, 26, 1, 0), (16, 29, 1, -1), (58, 4, -1, 0)):
                p = i % 3
                c.put(x0 + dx * p * 2, y0 + dy * p, 'L'); c.put(x0 + dx * (p * 2 + 1), y0 + dy * p, 'H')
        # the fuel tank and its feed line (right)
        chamfer_tones(c, 46, 3, 15, 8, 1, ['L', 'M', 'M', 'S', 'S', 'W', 'W', 'E'])
        c.vline(49, 3, 8, 'a'); c.vline(50, 3, 8, 'u'); c.vline(57, 3, 8, 'a'); c.vline(58, 3, 8, 'u')
        c.rect(52, 5, 3, 3, 'D'); c.put(53, 6, 'r' if on else 'W')
        c.rect(44, 11, 2, 7, 'q'); c.vline(44, 11, 7, 'Q')
        # the repair hatch and the power coupling (lower right)
        bev(c, 46, 13, 15, 6, 'L', 'M', 'S'); c.hline(49, 15, 9, 'a'); c.put(49, 15, 'y')
        bev(c, 46, 21, 15, 9, 'W', 'E', 'D')
        circle(c, 51.5, 25.5, 3.4, 'D'); ring(c, 51.5, 25.5, 2.4, 3.8, 'g' if on else 'W'); c.put(51, 25, 'E')
        c.put(57, 23, 'a' if on else 'W'); c.put(57, 27, 'a' if on and i % 2 else 'W')
        for (x, y) in ((3, 28), (60, 28)): c.put(x, y, 'L')
        stencil(c, 4, 26, 'L', 1)
    def hurt_core(self, c, i):
        for t in range(3, 10): c.put(int(31.5 + math.cos(1.0) * t), int(15 + math.sin(1.0) * t), 'E')    # a blade gone
        c.put(33 + i, 21, 'y'); c.put(35, 20 - i, 'H')
        c.put(53, 11, 'a'); c.put(53, 12 + i, 'a'); c.vline(54, 12, 2 + i, 'u')                          # the tank weeps
        for q in range(6): c.put(6 + q, 6 + (q * 2 + i) % 4, 'r')
    def wreck_core(self, c):
        crack(c, [(22, 4), (25, 9), (23, 14), (26, 20)], 'M'); crack(c, [(38, 18), (40, 22), (39, 27)], 'M')
        c.stamp(27, 11, art(".KKK.\nKDDDK\n.KKK."))
        c.stamp(47, 4, art("KKKKK\nKDDKK\n.KKK.")); stamp_on(c, 50, 6, SCORCH_S); stamp_on(c, 28, 20, SCORCH_L)
    def glow_core(self, g, ox, oy, i, flick=None):
        k = 1.0 if flick is None else (0.65 if flick else 0.85)
        b = oy + 4
        glow(g, ox + 52, b + 26, 6, GREEN, 0.4 * k, 2.0)
        glow(g, ox + 9, b + 8, 6, GREEN if flick is None else RED, 0.3 * k, 2.0)
        glow(g, ox + 7.5, b + 20.5, 5, AMBER, 0.35 * k, 2.0)
        glow(g, ox + 15, b + 8, 3, RED, 0.4 * k, 2.0)
        glow(g, ox + 31.5, b + 15, 13, AIR, (0.12 + 0.04 * (i % 3)) * k, 1.6)

_AB = Afterburner()
ALL = [BatteringBow, InertialDampener, ScrapKettle, Half2(_AB, 'core'), Half2(_AB, 'out')]
