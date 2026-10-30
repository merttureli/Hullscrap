"""New Mk1 systems: reactor, oxygen generator, shield, helm, radiator, bed."""
from comp_base import *
from compose import rotate

GREEN, AMBER, BLUE, CYAN, ORANGE, YEL = (107, 211, 74), (225, 161, 54), (79, 163, 255), (60, 242, 255), (255, 138, 30), (255, 210, 58)

def pipe_v(s, x, y, h, flanges=()):
    s.rect(x, y, 6, h, 'q'); s.vline(x, y, h, 'Q'); s.vline(x + 1, y, h, 'Q'); s.vline(x + 5, y, h, 'n')
    for fy in flanges: s.hline(x - 1, fy, 8, 'M'); s.hline(x - 1, fy + 1, 8, 'W')
def pipe_h(s, x, y, w, flanges=()):
    s.rect(x, y, w, 6, 'q'); s.hline(x, y, w, 'Q'); s.hline(x, y + 1, w, 'Q'); s.hline(x, y + 5, w, 'n')
    for fx in flanges: s.vline(fx, y - 1, 8, 'M'); s.vline(fx + 1, y - 1, 8, 'W')
def lamp(s, x, y, c, on):
    s.rect(x - 1, y - 1, 4, 4, 'D'); s.rect(x, y, 2, 2, c if on else 'W')
    if on: s.put(x, y, 'H')

# ============================================================ REACTOR 4x4
class Reactor(Comp):
    id = 'reactor_mk1'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 4, 6), ('disabled', 'disabled', 1, 0)]
    notes = 'Core pulse loop (4 frames). Pipes run to all four sides, so it reads the same at any rotation.'
    scorch = [(38, 17, 'L'), (11, 41, 'S'), (50, 30, 'S')]
    loose = (45, 45)
    cracks = [(20, 22, 'A'), (36, 40, 'B'), (8, 9, 'A'), (44, 20, 'B')]
    PULSE = [7, 8, 9, 8]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 61, 61, 'S', 8); rim(s, 'S', 'M', 'W')
        chamfer_fill(s, 5, 5, 53, 53, 'W', 7)
        for d in range(5, 58, 8): s.put(d, 31, 'E'); s.put(31, d, 'E')      # deck plate rivets
        pipe_v(s, 29, 2, 13, (6, 11)); pipe_v(s, 29, 49, 13, (51, 56))
        pipe_h(s, 2, 29, 13, (6, 11)); pipe_h(s, 49, 29, 13, (51, 56))
        for (bx, by) in ((6, 6), (46, 6), (6, 46), (46, 46)):                # capacitor blocks
            bev(s, bx, by, 12, 12, 'M', 'S', 'W')
            s.rect(bx + 2, by + 7, 8, 1, 'D'); s.rect(bx + 2, by + 9, 8, 1, 'D')
            lamp(s, bx + 3, by + 3, 'g', on)
            s.put(bx + 8, by + 3, 'L'); s.put(bx + 8, by + 4, 'S')
        chamfer_fill(s, 16, 16, 32, 32, 'M', 9); rim(s, 'M', 'L', 'S', (16, 16, 47, 47))
        chamfer_fill(s, 19, 19, 26, 26, 'E', 7)
        chamfer_fill(s, 21, 21, 22, 22, 'D', 6)
        for (x, y) in ((31, 17), (32, 17), (31, 46), (32, 46), (17, 31), (17, 32), (46, 31), (46, 32),
                       (22, 21), (41, 21), (22, 42), (41, 42)):
            s.put(x, y, 'H' if (x + y) % 2 else 'L')
        if on:
            r = self.PULSE[i]
            chamfer_fill(s, 32 - r, 32 - r, 2 * r, 2 * r, 'o', r // 2 + 1)
            chamfer_fill(s, 32 - r + 2, 32 - r + 2, 2 * r - 4, 2 * r - 4, 'y', r // 2)
            chamfer_fill(s, 32 - r + 4, 32 - r + 4, 2 * r - 8, 2 * r - 8, 'H', max(1, r // 2 - 1))
            for (x, y) in ((24, 24), (39, 24), (24, 39), (39, 39)): s.put(x, y, 'u')
        else:
            for (x, y) in ((26, 26), (37, 26), (26, 37), (37, 37), (31, 26), (26, 31), (37, 32), (32, 37)):
                s.rect(x, y, 2, 2, 'E')
            s.put(24, 23, 'W'); s.put(25, 23, 'W'); s.put(23, 24, 'W')
        return s
    def glow(self, state, i, g, ox, oy):
        r = self.PULSE[i]
        glow(g, ox + 32, oy + 32, 22 + r * 1.5, ORANGE, 0.30 + 0.03 * r, 1.4)
        glow(g, ox + 32, oy + 32, 4 + r * 0.8, YEL, 0.55, 1.6)
        for (bx, by) in ((6, 6), (46, 6), (6, 46), (46, 46)): glow(g, ox + bx + 4, oy + by + 4, 5, GREEN, 0.5, 2.0)

# ============================================================ OXYGEN GENERATOR 2x4
DISC = [(7, 13), (5, 15), (3, 17), (2, 18), (2, 18), (1, 19), (1, 19)] + [(0, 20)] * 7 + [(1, 19), (1, 19), (2, 18), (2, 18), (3, 17), (5, 15), (7, 13)]
BLADE_ROWS = {1: (11, 13), 2: (10, 13), 3: (9, 12), 4: (9, 11), 5: (9, 11), 6: (9, 11), 7: (9, 11), 8: (9, 11)}
def fan_blades():
    b = Spr(21, 21)
    for y, (x0, x1) in BLADE_ROWS.items():
        for x in range(x0, x1 + 1): b.put(x, y, 'M')
        b.put(x0, y, 'L'); b.put(x1, y, 'S')
    out = Spr(21, 21)
    for q in range(4):                       # four blades = quarter turns of the hand-drawn one
        out.stamp(0, 0, rotate(b, 90 * q, 10, 10).rows())
    return out
class OxygenGen(Comp):
    id = 'oxygen_gen'; cells = (2, 4)
    anims = [('on', 'on', 4, 12), ('off', 'off', 1, 0), ('damaged', 'damaged', 4, 6), ('disabled', 'disabled', 1, 0)]
    notes = 'Fan spin loop (4 frames = a quarter turn of a 4-blade fan). Lamps on the glow layer.'
    scorch = [(14, 7, 'L'), (4, 50, 'S')]
    loose = (18, 35)
    cracks = [(5, 11, 'A'), (19, 46, 'B'), (9, 34, 'A')]
    BLADES = None
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 64)
        bev(s, 1, 1, 30, 61, 'M', 'S', 'W')
        recess(s, 3, 3, 26, 26, 'E', 'K')
        disc = Spr(21, 21)
        for y, (x0, x1) in enumerate(DISC): disc.hline(x0, y, x1 - x0 + 1, 'D')
        if OxygenGen.BLADES is None:
            bl = fan_blades(); OxygenGen.BLADES = [rotate(bl, a, 10, 10) for a in (0, 22.5, 45, 67.5)]
        disc.stamp(0, 0, OxygenGen.BLADES[i if on else 0].rows())
        disc.stamp(8, 8, art("""
.WWW.
WLLWE
WLEWE
WWWWE
.EEE.
"""))
        s.stamp(6, 6, disc.rows())
        for (x, y) in ((4, 4), (27, 4), (4, 27), (27, 27)): s.put(x, y, 'L')          # guard screws
        s.hline(6, 16, 21, 'W') if False else None
        for k, (x, c) in enumerate(((6, 'g'), (11, 'g'), (16, 'a'))): lamp(s, x, 31, c, on and (k < 2 or i % 2 == 0))
        for x in range(21, 28, 2): s.vline(x, 30, 3, 'D')
        for tx in (4, 18):                                                               # O2 tanks
            tones = 'LMMSSSSWWE'
            for k in range(10): s.vline(tx + k, 37, 20, tones[k])
            for k in range(2, 8): s.put(tx + k, 36, tones[k]); s.put(tx + k, 57, tones[k])
            s.hline(tx, 42, 10, 'H'); s.hline(tx, 43, 10, 'M'); s.put(tx + 9, 42, 'S')
            s.rect(tx + 3, 34, 4, 2, 'E'); s.put(tx + 4, 34, 'W')
        s.rect(14, 38, 4, 18, 'q'); s.vline(14, 38, 18, 'Q'); s.vline(17, 38, 18, 'n')
        s.stamp(14, 45, art("""
.rr.
rKKr
rKKr
.rr.
"""))
        return s
    def glow(self, state, i, g, ox, oy):
        for k, (x, c) in enumerate(((6, GREEN), (11, GREEN), (16, AMBER))):
            if k < 2 or i % 2 == 0: glow(g, ox + x + 1, oy + 32, 4.5, c, 0.55, 2.0)

# ============================================================ SHIELD 4x4
class Shield(Comp):
    id = 'shield_mk1'; cells = (4, 4)
    glow_pad = (12, 12, 12, 12)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 4, 6), ('disabled', 'disabled', 1, 0)]
    notes = 'Emitter pulse loop (4 frames): a ring rises out of the dome while the pylon crystals take turns.'
    scorch = [(10, 39, 'L'), (45, 13, 'S'), (36, 50, 'S')]
    loose = (41, 38)
    cracks = [(22, 23, 'A'), (44, 44, 'B'), (6, 8, 'A'), (30, 36, 'B')]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 61, 61, 'S', 6); rim(s, 'S', 'M', 'W')
        chamfer_fill(s, 4, 4, 55, 55, 'E', 5)
        chamfer_fill(s, 9, 9, 45, 45, 'W', 4); rim(s, 'W', 'S', 'E', (9, 9, 53, 53))      # conduit ring
        chamfer_fill(s, 13, 13, 37, 37, 'E', 4)
        if on:
            for k, (x, y) in enumerate(((11, 31), (31, 11), (52, 31), (31, 52))):
                for d in (-6, 6): s.put(x if y in (31,) and False else x, y, 'b')
            for t in range(13, 50, 3):
                s.put(t, 11, 'b' if (t // 3 + i) % 4 else 'c'); s.put(t, 52, 'b' if (t // 3 + i + 2) % 4 else 'c')
                s.put(11, t, 'b' if (t // 3 + i + 1) % 4 else 'c'); s.put(52, t, 'b' if (t // 3 + i + 3) % 4 else 'c')
        pyl = [(26, 1, 12, 9), (26, 54, 12, 9), (1, 26, 9, 12), (54, 26, 9, 12)]
        for k, (x, y, w, h) in enumerate(pyl):
            bev(s, x, y, w, h, 'L', 'M', 'S')
            cx, cy = x + w // 2 - 2, y + h // 2 - 2
            s.rect(cx, cy, 4, 4, 'D')
            if on:
                hot = (k == i)
                s.rect(cx, cy, 4, 4, 'b'); s.put(cx, cy, 'c' if hot else 'b'); s.put(cx + 1, cy, 'H' if hot else 'c')
                s.put(cx, cy + 1, 'c'); s.put(cx + 3, cy + 3, 'E')
            else:
                s.put(cx + 1, cy + 1, 'W')
        chamfer_fill(s, 20, 20, 24, 24, 'E', 7)                                           # the dome
        if on:
            chamfer_fill(s, 21, 21, 22, 22, 'b', 6)
            chamfer_fill(s, 23, 23, 10, 10, 'c', 3)
            for (x, y) in ((25, 25), (26, 25), (25, 26)): s.put(x, y, 'H')
            r = (3, 6, 9, 11)[i]
            for t in range(-r, r + 1):                                                    # pulse ring
                for (x, y) in ((32 + t, 32 - r), (32 + t, 31 + r), (32 - r, 32 + t), (31 + r, 32 + t)):
                    if 21 <= x <= 42 and 21 <= y <= 42 and abs(t) < r - r // 3: s.put(x, y, 'H' if i < 2 else 'c')
        else:
            chamfer_fill(s, 21, 21, 22, 22, 'W', 6)
            chamfer_fill(s, 23, 23, 10, 10, 'S', 3)
            s.put(25, 25, 'M'); s.put(26, 25, 'M')
        return s
    def glow(self, state, i, g, ox, oy):
        glow(g, ox + 32, oy + 32, 26 + 2 * i, BLUE, 0.30 + 0.05 * (i % 3), 1.4)
        glow(g, ox + 32, oy + 32, 8, CYAN, 0.35, 1.8)
        for k, (x, y) in enumerate(((32, 5), (32, 58), (5, 32), (58, 32))):
            glow(g, ox + x, oy + y, 7 if k == i else 4.5, BLUE, 0.6 if k == i else 0.4, 2.0)

# ============================================================ HELM 2x2
class Helm(Comp):
    id = 'helm'; cells = (2, 2)
    anims = [('on', 'on', 2, 4), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    anchors = {'seat': (15, 22)}
    notes = 'Console at the top, pilot seat below it: a crew member manning it stands on "seat" facing up. Screen flicker loop (2 frames).'
    scorch = [(3, 11, 'S'), (20, 17, 'S')]
    loose = (20, 1)
    cracks = [(6, 3, 'A'), (14, 20, 'B')]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        bev(s, 1, 1, 30, 14, 'M', 'S', 'W')
        recess(s, 3, 2, 26, 9, 'D', 'K')
        if on:                                                                          # nav display
            s.hline(5, 7, 22, 'E')
            for x in range(5, 27, 4): s.put(x, 4, 'E'); s.put(x, 8, 'E')
            for x in range(5, 27):
                yy = 6 + ((x + i) // 3) % 2
                s.put(x, yy, 'c')
            bx = 10 + 6 * i
            s.put(bx, 4, 'g'); s.put(bx + 1, 4, 'g'); s.put(bx, 5, 'g')
            s.put(22, 5 - i, 'r') if i == 0 else s.put(21, 4, 'a')
            if i == 1:
                s.hline(5, 3 + 2 * i, 22, 'E')                                           # scanline roll
        else:
            s.put(5, 3, 'W'); s.put(6, 3, 'W'); s.put(5, 4, 'E')
        for k, (x, c) in enumerate(((5, 'a'), (8, 'g'), (11, 'g'))):
            s.rect(x, 12, 2, 1, c if on else 'W')
        s.rect(15, 11, 3, 3, 'E'); s.put(15, 11, 'L'); s.put(16, 11, 'M')          # flight stick
        for x in (21, 24, 27): s.rect(x, 12, 2, 1, 'D')
        # pilot seat (faces up, toward the console)
        for ax in (7, 22):                                                              # armrests
            s.rect(ax, 18, 3, 8, 'E'); s.vline(ax, 18, 8, 'W'); s.hline(ax, 18, 3, 'W'); s.put(ax + 1, 18, 'S')
        chamfer_fill(s, 10, 17, 12, 10, 'q', 2); rim(s, 'q', 'Q', 'n', (10, 17, 21, 26))  # cushion
        s.hline(12, 22, 8, 'n'); s.vline(15, 18, 4, 'n'); s.vline(16, 23, 3, 'n')         # stitching
        s.put(12, 18, 'Q'); s.put(13, 18, 'Q')
        chamfer_fill(s, 9, 26, 14, 5, 'S', 2); rim(s, 'S', 'M', 'W', (9, 26, 22, 30))      # backrest
        s.hline(12, 28, 8, 'E')
        return s
    def glow(self, state, i, g, ox, oy):
        glow(g, ox + 16, oy + 6.5, 13, CYAN, 0.30 if i == 0 else 0.22, 2.0, sx=1.4)
        for (x, c) in ((6, AMBER), (9, GREEN), (12, GREEN)): glow(g, ox + x, oy + 12.5, 3, c, 0.45, 2.0)

# ============================================================ RADIATOR 2x2
class Radiator(Comp):
    id = 'radiator'; cells = (2, 2)
    anims = [('on', 'on', 3, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 3, 6), ('disabled', 'disabled', 1, 0)]
    notes = 'Heat shimmer loop (3 frames): hot pixels climb the fins.'
    scorch = [(17, 9, 'S'), (4, 18, 'S')]
    loose = (19, 18)
    cracks = [(5, 8, 'A'), (16, 15, 'B')]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        bev(s, 1, 1, 30, 30, 'M', 'S', 'W')
        pipe_h(s, 3, 2, 26, (7, 23)) if False else None
        for y in (3, 25):
            s.rect(3, y, 26, 4, 'q'); s.hline(3, y, 26, 'Q'); s.hline(3, y + 3, 26, 'n')
            for fx in (6, 15, 24): s.vline(fx, y - 1, 6, 'M'); s.vline(fx + 1, y - 1, 6, 'W')
        recess(s, 3, 7, 26, 18, 'D', 'K')
        for k, x in enumerate(range(5, 28, 2)):                                       # fins
            s.vline(x, 8, 16, 'S'); s.put(x, 8, 'L'); s.put(x, 9, 'M'); s.put(x, 23, 'W')
            if on:
                for hy in range(8, 24):
                    if (hy + 2 * i + 3 * k) % 6 == 0: s.put(x, hy, 'o')
                    elif (hy + 2 * i + 3 * k) % 6 == 1: s.put(x, hy, 'u')
        lamp(s, 3, 28, 'g', on) if False else None
        s.rect(27, 28, 2, 1, 'g' if on else 'W')
        return s
    def glow(self, state, i, g, ox, oy):
        for k, x in enumerate(range(5, 28, 4)):
            glow(g, ox + x, oy + 16 - 3 * ((i + k) % 3) + 3, 6, ORANGE, 0.22, 2.0)
        glow(g, ox + 28, oy + 28.5, 3, GREEN, 0.45, 2.0)

# ============================================================ BED 2x4
class Bed(Comp):
    id = 'bed'; cells = (2, 4)
    anims = [('on', 'on', 1, 0), ('off', 'on', 1, 0), ('damaged', 'damaged', 1, 0), ('disabled', 'disabled', 1, 0)]
    anchors = {'pillow': (15, 9)}
    notes = 'Head end at the top. Needs no power, so on and off are the same frame.'
    scorch = [(18, 36, 'L'), (5, 18, 'S')]
    loose = (3, 49)
    cracks = [(6, 30, 'A'), (17, 46, 'B')]
    def interior(self, state, i):
        s = Spr(32, 64)
        bev(s, 1, 1, 30, 61, 'M', 'S', 'W')
        s.rect(3, 3, 26, 57, 'L'); rim(s, 'L', 'H', 'M', (3, 3, 28, 59))            # mattress
        s.rect(6, 5, 20, 9, 'H'); s.hline(6, 13, 20, 'M'); s.vline(25, 5, 9, 'M')   # pillow
        s.hline(9, 9, 14, 'L'); s.put(6, 5, 'L'); s.put(25, 5, 'L')
        s.rect(3, 26, 26, 34, 'q')                                                      # blanket
        s.vline(3, 26, 34, 'Q'); s.vline(27, 26, 34, 'n'); s.vline(28, 26, 34, 'n')     # drape shading
        s.rect(3, 23, 26, 3, 'H'); s.hline(3, 25, 26, 'M'); s.hline(3, 26, 26, 'n')      # turned-down sheet
        for y in (45, 46, 50):
            s.hline(4, y, 23, 'Q'); s.put(27, y, 'q')                                  # woven stripes
        for (x, y) in ((8, 32), (9, 33), (10, 34), (19, 38), (20, 39), (13, 55), (14, 56)):
            s.put(x, y, 'n')                                                            # creases
        for (x, y) in ((8, 31), (19, 37), (13, 54)): s.put(x, y, 'Q')
        s.rect(1, 61, 30, 1, 'W')
        return s

ALL = [Reactor, OxygenGen, Shield, Helm, Radiator, Bed]
