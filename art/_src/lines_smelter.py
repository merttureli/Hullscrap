"""Smelters (data/packs/processing_1, family `smelter`, manned): the Slag Pot (scrap, 3x3), the Concord Smelter Mk1-Mk3 (standard, 4x3)
and the Plasma Forge (neon, 4x3). Plain components drawn top-down (no mount), lit from the top-left like every other system.
Family colour: molten metal, a white-hot to crimson ramp (H ) y o r ( e) that only ever means "this is liquid metal".
The `on` loop is the working loop (the game plays `on` while the part has power): the melt swirls and pulses, the feed shifts,
the pour runs, the console counts. Every smelter has an operator console (it is manned): a screen and two lamps.
Ladder: Mk1 one big crucible in an induction coil; Mk2 a second crucible and cooling pipe everywhere; Mk3 three crucibles,
armoured corners, heat-sink fins, the paint burnt off round the coils. Preview: python3 parts_art.py --sheet out.png."""
import math
import pal_guns                        # the beam crimson '(' and the pale straw ')' (registered by build_all; RGB only here)
from lines_kit import *
from comp_new import lamp

HOT = RGB['o']; WHITEHOT = RGB[')']; MOLTEN = RGB['o']; MAG = RGB['m']        # glow hues: palette colours only

def _lit(dx, dy, r):
    """which side of a disc a pixel is on, for top-left light: 1 lit, -1 shade, 0 middle."""
    d = (dx + dy) / max(1.0, r)
    return 1 if d < -0.45 else (-1 if d > 0.45 else 0)

def disc_lit(s, cx, cy, r0, r1, hi, mid, lo):
    """a ring (r0 < d <= r1) shaded by the light: hi top-left, lo bottom-right."""
    for y in range(int(cy - r1 - 1), int(cy + r1 + 2)):
        for x in range(int(cx - r1 - 1), int(cx + r1 + 2)):
            dx, dy = x + .5 - cx, y + .5 - cy
            d = (dx * dx + dy * dy) ** .5
            if r0 < d <= r1: s.put(x, y, {1: hi, 0: mid, -1: lo}[_lit(dx, dy, d)])

def melt(s, cx, cy, r, on, i, crust=5, seed=0):
    """the melt seen from above, a stirred pot rather than a radiant core: a ring of dark slag crust plates (ember brown, glowing red
    edges) drifting round the rim on orange cracks, and a yellow pool in the middle where the coil stirs it, with a pale ripple.
    The crust turns one quarter of a plate per frame, so the 4-frame loop is seamless. Off: a cold grey slag cake with a rusty skin."""
    if not on:
        circle(s, cx, cy, r, 'E'); circle(s, cx + .4, cy + .4, r - 1.2, 'W')
        for k in range(crust):
            a = seed + k * 2 * math.pi / crust
            s.put(int(cx - .5 + math.cos(a) * (r - 2)), int(cy - .5 + math.sin(a) * (r - 2)), 'e' if k % 2 else 'E')
        s.put(int(cx + r * .3), int(cy + r * .35), 'S')
        return
    inner = max(1.6, r * .5)
    per = 2 * math.pi / crust
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            dx, dy = x + .5 - cx, y + .5 - cy
            d = (dx * dx + dy * dy) ** .5
            if d > r: continue
            if d <= inner:
                c = 'y'
            else:
                a = (math.atan2(dy, dx) - seed - i * per / 4) % per / per         # where in its plate's span this pixel is
                if a < .62 and d > inner + .9: c = 'e' if (a > .12 and a < .5 and d < r - .7) else '('
                else: c = 'o'
                if d > r - .8 and dx + dy < 0 and c == 'o': c = 'r'               # the lip's shadow on the far edge
            s.put(x, y, c)
    rx, ry = [(-1, -1), (0, -1), (0, 0), (-1, 0)][i % 4]                     # a pale ripple in the stirred middle
    s.put(int(cx - .5 + rx), int(cy - .5 + ry), ')'); s.put(int(cx + .5 + rx), int(cy - .5 + ry), ')')
    if r >= 6: s.put(int(cx - .5 + rx), int(cy + .5 + ry), 'H')

CRACKS = [[(0, 0), (3, -2), (6, -3), (7, -6)], [(0, 0), (-2, -4), (-2, -7)], [(0, 0), (-4, 1), (-7, 3)], [(0, 0), (2, 4), (2, 7)],
          [(3, -2), (5, 1), (8, 1)], [(-2, -4), (-5, -5)], [(2, 4), (5, 5)], [(-4, 1), (-5, 5)]]

def slag(s, cx, cy, r, on, i):
    """an unstirred pot under a fire (the Slag Pot): a dark slag crust over the whole surface, glowing cracks running out from a hot
    middle that brighten in turn, and a bubble breaking through somewhere new each frame. Off: a cold grey cake."""
    circle(s, cx, cy, r, 'e' if on else 'E')
    for (dx, dy, c) in ((-5, -2, 'n'), (4, -5, 'n'), (-3, 5, 'q'), (5, 3, 'n'), (-6, -5, 'q'), (1, -7, 'n'), (6, -1, 'q')):
        s.put(int(cx + dx), int(cy + dy), c if on else ('W' if c == 'q' else 'D'))
    for k, pts in enumerate(CRACKS):
        for (a, b) in zip(pts, pts[1:]):
            for (ox, oy) in ((1, 0), (0, 1)):
                line(s, int(cx + a[0] + ox), int(cy + a[1] + oy), int(cx + b[0] + ox), int(cy + b[1] + oy), '(' if on else 'D')
    for k, pts in enumerate(CRACKS):
        c = ('y' if (k + i) % 3 == 0 else 'o') if on else 'W'
        for (a, b) in zip(pts, pts[1:]): line(s, int(cx + a[0]), int(cy + a[1]), int(cx + b[0]), int(cy + b[1]), c)
    if on:
        circle(s, cx + .5, cy + .5, 2.4, 'y'); s.put(int(cx), int(cy), ')'); s.put(int(cx) + 1, int(cy), ')'); s.put(int(cx), int(cy) - 1, 'H')
        bx, by = [(4, -4), (-4, 3), (3, 3), (-3, -2)][i % 4]
        bx, by = int(cx + bx), int(cy + by)
        for (x, y) in ((bx, by - 1), (bx - 1, by), (bx + 1, by), (bx, by + 1)): s.put(x, y, 'y')
        s.put(bx, by, 'H')
    else:
        circle(s, cx + .5, cy + .5, 2.4, 'W')

def crucible(s, cx, cy, r, on, i, seed=0, coil=2, crust=5, spout=None, trunnions='v'):
    """a tilting crucible in its induction coil, from above: two copper turns round a thick ceramic pot whose inner face is dark on
    the top-left (in its own shadow) and pale on the bottom-right, the melt, a pour spout notch on side `spout` ('e', 's', 'w'),
    and the two trunnion pins it tilts on ('h' left and right, 'v' top and bottom, None). r = the melt radius; `coil` turns (0-2): the outer
    edge is r + 6 with two, r + 4 with one."""
    for sg in ((-1, 1) if trunnions else ()):                      # the yoke pins it tilts on (on the axis across the pour)
        if trunnions == 'v':
            y0 = int(cy + sg * (r + 2 + 2 * coil)) - (3 if sg < 0 else 0)
            s.rect(int(cx) - 2, y0, 4, 4, 'S'); s.vline(int(cx) - 2, y0, 4, 'M'); s.vline(int(cx) + 1, y0, 4, 'W'); s.put(int(cx) - 1, y0 + (0 if sg < 0 else 3), 'L')
        else:
            x0 = int(cx + sg * (r + 2 + 2 * coil)) - (3 if sg < 0 else 0)
            s.rect(x0, int(cy) - 2, 4, 4, 'S'); s.hline(x0, int(cy) - 2, 4, 'M'); s.hline(x0, int(cy) + 1, 4, 'W'); s.put(x0 + (0 if sg < 0 else 3), int(cy) - 1, 'L')
    if coil:
        for y in range(int(cy - r - 7), int(cy + r + 8)):
            for x in range(int(cx - r - 7), int(cx + r + 8)):
                dx, dy = x + .5 - cx, y + .5 - cy
                d = (dx * dx + dy * dy) ** .5
                lit = (dx + dy) / max(1.0, d)
                if coil == 2 and r + 4.4 < d <= r + 6: s.put(x, y, 'y' if lit < -1.25 else ('a' if lit < -0.2 else ('u' if lit < 0.9 else 'n')))
                elif coil == 2 and r + 3.6 < d <= r + 4.4: s.put(x, y, 'n')
                elif coil == 2 and r + 2.6 < d <= r + 3.6: s.put(x, y, 'a' if lit < -0.6 else ('u' if lit < 0.8 else 'n'))
                elif coil == 1 and r + 2.6 < d <= r + 4: s.put(x, y, 'y' if lit < -1.25 else ('a' if lit < -0.2 else ('u' if lit < 0.9 else 'n')))
    for y in range(int(cy - r - 3), int(cy + r + 4)):                  # the pot: outer face lit top-left, inner face lit bottom-right
        for x in range(int(cx - r - 3), int(cx + r + 4)):
            dx, dy = x + .5 - cx, y + .5 - cy
            d = (dx * dx + dy * dy) ** .5
            lit = (dx + dy) / max(1.0, d)
            if r + 1.6 < d <= r + 2.6: s.put(x, y, 'L' if lit < -0.5 else ('M' if lit < 0.6 else 'S'))
            elif r + .6 < d <= r + 1.6: s.put(x, y, 'M' if lit < -0.3 else 'L')
            elif r < d <= r + .6: s.put(x, y, 'E' if lit < 0.3 else 'S')
    if spout:
        dx, dy = {'e': (1, 0), 's': (0, 1), 'w': (-1, 0)}[spout]
        for t in range(0, 5):                                         # a V notch in the lip, the melt running out along it
            px, py = int(cx + dx * (r + t)), int(cy + dy * (r + t))
            w = 2 if t < 3 else 1
            for q in range(-w, w + 1):
                qx, qy = (px, py + q) if dx else (px + q, py)
                edge = abs(q) == w
                s.put(qx, qy, ('M' if q < 0 else 'S') if edge else (('o' if t % 2 else 'y') if on else 'E'))
    melt(s, cx, cy, r, on, i, crust, seed)

def ingot(s, x, y, w, h, tones=('L', 'M', 'S', 'W')):
    """a bar from above: a chamfered block, its top face lighter, a lit top-left edge, a dark bottom-right edge."""
    hi, mid, lo, sh = tones
    s.hline(x + 1, y, w - 2, hi)
    for yy in range(y + 1, y + h - 1): s.hline(x, yy, w, mid); s.put(x, yy, hi); s.put(x + w - 1, yy, lo)
    s.hline(x + 1, y + h - 1, w - 2, sh)
    if w > 5 and h > 3: s.hline(x + 2, y + 1, w - 4, hi)

def mould(s, x, y, w, h, state):
    """an ingot mould: 'pour' liquid running in, 'warm' / 'dull' a cooling bar (it fades frame to frame), 'cold' finished steel, 'empty'."""
    recess(s, x, y, w, h, 'D', 'K')
    if state == 'pour':
        s.rect(x + 1, y + 1, w - 2, h - 2, 'o'); s.hline(x + 1, y + 1, w - 2, 'r'); s.hline(x + 2, y + h // 2, w - 4, 'y'); s.put(x + 2, y + h // 2, ')')
    elif state in ('warm', 'dull'):
        ingot(s, x + 1, y + 1, w - 2, h - 2, ('o', 'e', 'n', 'n') if state == 'warm' else ('(', 'q', 'n', 'n'))
    elif state == 'cold':
        ingot(s, x + 1, y + 1, w - 2, h - 2)

def console(s, x, y, on, i, w=20, kind='std'):
    """the operator's console (every smelter is manned): a screen with a temperature trace and two lamps."""
    if kind == 'neon':
        bev(s, x, y, w, 10, 'j', 'J', 'I')
    else:
        bev(s, x, y, w, 10, 'W', 'E', 'D')
    recess(s, x + 2, y + 2, w - 8, 6, 'N' if kind == 'neon' else 'D', 'K')
    sw = w - 10
    for k in range(sw):                                             # the trace: temperature (std), the song (neon)
        if kind == 'neon':
            h = int(round(1.5 + 1.4 * math.sin((k + i * 2) * 0.9)))
            c = 'c' if on else 'E'
        else:
            h = [2, 3, 3, 2, 3, 4, 3, 3, 4, 3, 2, 3][(k + i) % 12] if on else 1
            c = 'g' if h < 4 else 'a'
            if not on: c = 'E'
        s.put(x + 3 + k, y + 7 - h, c)
    lamp(s, x + w - 4, y + 2, 'm' if kind == 'neon' else 'g', on)
    lamp(s, x + w - 4, y + 6, 'c' if kind == 'neon' else 'a', on and i % 2 == 0)

def vents(s, x, y, w, on, i, h=10):
    """a hot vent grille: dark slots, every third one glowing in turn."""
    bev(s, x, y, w, h, 'W', 'E', 'D')
    for k, vy in enumerate(range(y + 2, y + h - 2, 2)):
        s.hline(x + 2, vy, w - 4, 'D'); s.hline(x + 2, vy + 1, w - 4, 'o' if on and (k + i) % 3 == 0 else 'W')

def steel_pipe_h(s, x, y, w, bands=()):
    """a 3px cooling pipe (steel, blue coolant bands)."""
    s.hline(x, y, w, 'L'); s.hline(x, y + 1, w, 'S'); s.hline(x, y + 2, w, 'W')
    for b in bands: s.put(b, y, 'b'); s.put(b, y + 1, 'b'); s.put(b + 1, y, 'b'); s.put(b + 1, y + 1, 'E')

def steel_pipe_v(s, x, y, h, bands=()):
    s.vline(x, y, h, 'L'); s.vline(x + 1, y, h, 'S'); s.vline(x + 2, y, h, 'W')
    for b in bands: s.put(x, b, 'b'); s.put(x + 1, b, 'b'); s.put(x, b + 1, 'b'); s.put(x + 1, b + 1, 'E')

def elbow(s, x, y):
    """a pipe joint: a little flange block."""
    s.rect(x, y, 4, 4, 'S'); s.hline(x, y, 4, 'M'); s.vline(x, y, 4, 'M'); s.hline(x, y + 3, 4, 'E'); s.vline(x + 3, y, 4, 'E'); s.put(x + 1, y + 1, 'L')

SCRAP = [("MLM\nSWW", 0, 0), ("uQ\nnu", 5, 1), ("aK\nKa", 1, 4), ("SM\nWS", 5, 5), ("L", 3, 6), ("q", 7, 3)]

def scrap_bits(s, x, y, w, h, i, seed=0):
    """loose scrap in a hopper: a plate, a rusty curl, a bit of hazard plate, a pipe end, a bolt, each nudged toward the throat in turn
    (the feed settles one piece per frame)."""
    cx, cy = (w - 1) / 2, (h - 1) / 2
    for k, (rows, dx, dy) in enumerate(SCRAP):
        if (k + seed) % 4 == i % 4:
            dx += (1 if dx < cx else -1); dy += (1 if dy < cy else -1)
        for j, row in enumerate(rows.split('\n')):
            for q, c in enumerate(row):
                if 0 <= dx + q < w and 0 <= dy + j < h: s.put(x + dx + q, y + dy + j, c)

def drum(s, x, y, w, h, on, band='a'):
    """a capacitor drum lying on its side, seen from above: a cylinder lit along its top rows, end caps, a copper band and a lamp."""
    chamfer_tones(s, x, y, w, h, 1, ['L', 'M', 'M', 'S', 'S', 'W', 'W', 'E', 'E'][:h] if h <= 9 else col_tones(h, 'LMMSSWWEE'))
    s.vline(x, y + 1, h - 2, 'S'); s.vline(x + w - 1, y + 1, h - 2, 'E')
    s.vline(x + 3, y, h, band); s.vline(x + 4, y, h, 'u' if band == 'a' else band)
    s.put(x + 3, y, 'y' if band == 'a' else band); s.put(x + w - 3, y + h // 2, 'a' if on else 'W'); s.put(x + w - 3, y + h // 2 + 1, 'u' if on else 'E')

def funnel(s, x, y, w, h, rim=('L', 'M', 'S'), faces=('E', 'W', 'M', 'S'), throat='K'):
    """a square funnel seen from above: a bevelled rim, four sloping inner faces (top, left, bottom, right) meeting at the throat."""
    bev(s, x, y, w, h, *rim)
    x0, y0, x1, y1 = x + 1, y + 1, x + w - 2, y + h - 2
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    for yy in range(y0, y1 + 1):
        for xx in range(x0, x1 + 1):
            dx, dy = (xx - cx) / max(1, (x1 - x0) / 2), (yy - cy) / max(1, (y1 - y0) / 2)
            if abs(dx) < .3 and abs(dy) < .3: c = throat
            elif dy <= -abs(dx): c = faces[0]
            elif dx <= -abs(dy): c = faces[1]
            elif dy >= abs(dx): c = faces[2]
            else: c = faces[3]
            s.put(xx, yy, c)

# ============================================================ the Concord smelter ladder (standard, 4x3)
class _Smelter(LComp):
    """the Concord frame shared by Mk1-Mk3 (64x48): the hopper (top-left) and the console under it, the coupling bottom-left, the crucible
    well across the top, and the casting line along the bottom: moulds slide right two px a frame (one mould pitch per loop) under the
    spouts; a mould is liquid under a spout, then cools red, dull and grey as it moves right, and leaves as a steel bar."""
    cells = (4, 3)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    dark = {'(': 'n', ')': 'q', 'e': 'n'}
    POTS = []                                    # (cx, cy, melt r)
    LINE = (16, 32, 46, 13)                      # the casting line: x, y, w, h
    WELL = (16, 3, 46, 28)
    PITCH = 8
    def housing(self, s):
        bev(s, 1, 1, 62, 46, 'M', 'S', 'W')
        for (x, y) in ((3, 2), (60, 2), (3, 45), (60, 45)): s.put(x, y, 'L')
    def well(self, s):
        recess(s, *self.WELL, 'E', 'K')
        x, y, w, h = self.WELL
        for (px, py) in ((x + 2, y + 2), (x + w - 3, y + 2)): s.put(px, py, 'W')
    def hopper(self, s, i, on, x=3, y=3, w=11, h=12):
        """the feed hopper: a square funnel from above (its inner faces dark on the top and left, lit on the bottom and right, as a
        hollow is under top-left light) with scrap settling toward the dark throat."""
        funnel(s, x, y, w, h)
        scrap_bits(s, x + 1, y + 1, w - 2, h - 2, i if on else 0)
    def side(self, s, on, i):
        """the left column under the hopper: the operator's console (a temperature bar and two lamps) and the power coupling."""
        bev(s, 3, 17, 11, 16, 'W', 'E', 'D')
        recess(s, 5, 19, 7, 9, 'D', 'K')
        lvl = [5, 6, 7, 6][i % 4] if on else 0
        for k in range(7):
            c = ('g' if k < 4 else ('a' if k < 6 else 'r')) if k < lvl else 'E'
            s.hline(6, 26 - k, 2, c); s.put(9, 26 - k, 'E' if k % 2 else 'W')
        lamp(s, 5, 30, 'g', on); lamp(s, 9, 30, 'a', on and i % 2 == 0)
        bev(s, 3, 35, 11, 10, 'W', 'E', 'D'); circle(s, 8.5, 40, 3.2, 'D'); ring(s, 8.5, 40, 2.2, 3.4, 'g' if on else 'W')
        s.put(7, 39, 'E'); s.put(9, 39, 'E'); s.put(8, 41, 'E')
    def line_(self, s, on, i):
        x, y, w, h = self.LINE
        bev(s, x, y, w, h, 'M', 'S', 'W')
        s.rect(x + 1, y + 2, w - 2, h - 4, 'D'); s.hline(x + 1, y + 2, w - 2, 'K')
        for rx in range(x + 3, x + w - 2, 4): s.put(rx, y + h - 2, 'E')            # rollers under the moulds
        spouts = [int(p[0]) for p in self.POTS]
        off = (2 * i) if on else 0
        m = Spr(s.w, s.h)
        for k in range(-1, w // self.PITCH + 2):
            mx = x + 1 + k * self.PITCH + off
            st = 'empty'
            if on:
                past = [mx - sp for sp in spouts if mx - sp > -self.PITCH]
                d = min(past) if past else None
                if d is None: st = 'empty'
                elif d <= 1: st = 'pour'
                elif d <= 8: st = 'warm'
                elif d <= 16: st = 'dull'
                else: st = 'cold'
            else:
                st = 'cold' if k % 2 else 'empty'
            mould(m, mx, y + 3, self.PITCH - 1, h - 6, st)
        for yy in range(y + 3, y + h - 3):
            for xx in range(x + 1, x + w - 1):
                if m.g[yy][xx] != '.': s.g[yy][xx] = m.g[yy][xx]
        for sp in spouts:                                                         # the pour falling from each spout into the line
            for yy in range(y - 4, y + 4):
                s.put(sp, yy, ('y' if (yy + i) % 2 else ')') if on else 'E'); s.put(sp + 1, yy, 'o' if on else 'D')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 48)
        self.housing(s)
        self.well(s)
        self.hopper(s, i, on)
        self.side(s, on, i)
        self.body(s, on, i)
        self.line_(s, on, i)
        return s
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.6 if flick else 0.85)
        pulse = [0.9, 1.0, 0.85, 0.75][i % 4]
        x, y, w, h = self.LINE
        for (cx, cy, r) in self.POTS:
            glow(g, ox + cx, oy + cy, r + 10, MOLTEN, 0.36 * pulse * k, 1.6)
            glow(g, ox + cx, oy + cy, r * .7, WHITEHOT, 0.38 * pulse * k, 1.6)
            glow(g, ox + cx + 1, oy + y + 6, 6, HOT, 0.55 * k, 1.8, sx=1.3)       # the mould under the spout
            if cx + 12 < x + w - 4: glow(g, ox + cx + 12, oy + y + 6, 5, MOLTEN, 0.18 * k, 2.0, sx=1.6)    # the bar cooling past it
        glow(g, ox + 6.5, oy + 31, 3, GREEN, 0.45 * k, 2.0)
        if i % 2 == 0: glow(g, ox + 10.5, oy + 31, 3, AMBER, 0.45 * k, 2.0)
        self.glow_more(g, ox, oy, i, flick, k)
    def glow_more(self, g, ox, oy, i, flick, k): pass

class SmelterMk1(_Smelter):
    id = 'smelter_mk1'
    notes = ('Concord Smelter Mk1 (standard, 4x3, manned): one big tilting crucible in a two-turn copper induction coil, hung on two trunnion pins in a dark well; '
             'a feed hopper top-left with scrap in it and a chute over the lip; the operator console under it (a temperature bar, green and amber lamps) and the power coupling; '
             'an induction supply (two capacitor drums on copper bus bars) right of the crucible; the spout pours down into the casting line along the bottom. '
             'The on loop is the working loop: the slag crust drifts round the stirred yellow middle, the feed settles, and the moulds slide right one pitch per loop '
             '(liquid under the spout, then red, dull and grey steel). '
             'Damaged: the outer coil turn has burnt through and arcs at the break, the crucible lip is cracked and weeps a molten dribble into the well, the console bar '
             'jumps to red. Disabled: the melt has set into a cracked grey cake, the coil is snapped and blackened, the chute hangs off, the line is cold and still.')
    POTS = [(32, 16, 7)]
    def body(self, s, on, i):
        cx, cy, r = self.POTS[0]
        # the induction supply, right: two capacitor drums on copper bus bars into the coil
        for (dx, dy) in ((49, 5), (49, 15)):
            drum(s, dx, dy, 11, 8, on)
        for by in (8, 18): s.rect(45, by, 4, 2, 'a'); s.hline(45, by + 1, 4, 'u')
        stencil(s, 50, 26, 'L', 0); stencil(s, 55, 26, 'L', 1)
        # the chute from the hopper over the lip
        s.rect(14, 6, 10, 4, 'S'); s.hline(14, 6, 10, 'L'); s.hline(14, 9, 10, 'W'); s.vline(23, 6, 4, 'E')
        s.hline(14, 7, 9, 'M'); s.put(22, 8, 'D'); s.put(23, 8, 'D')
        crucible(s, cx, cy, r, on, i, seed=0.6, crust=5, spout='s', trunnions='h')
        if on: s.put(24, 10 + i % 2, 'M')                                    # a bit dropping in
    def hurt(self, s, i):
        cx, cy, r = self.POTS[0]
        for (x, y) in ((40, 4), (41, 4), (42, 5), (41, 5)): s.put(x, y, 'K')        # the outer coil turn burnt through, top-right
        s.put(43, 3, 'y' if i else 'H'); s.put(39, 2 + i, 'H'); s.put(44, 5 - i, 'y')
        stamp_on(s, 37, 2, SCORCH_S)
        crack(s, [(25, 19), (23, 22), (25, 24)], 'M')                              # the lip cracked: molten weeps into the well
        s.put(23, 23, 'o'); s.put(22, 24, 'o'); s.put(22, 25, 'r'); s.hline(20, 27, 3, 'r' if i else '('); s.put(21, 26, 'o')
        for k in range(3): s.hline(6, 20 + k, 2, 'r')                           # the console bar jumps to red
        s.put(5, 30, 'r'); s.put(6, 30, 'r')
    def wreck(self, s):
        cx, cy, r = self.POTS[0]
        crack(s, [(cx - 5, cy - 3), (cx - 1, cy), (cx + 2, cy - 1), (cx + 5, cy + 3)], 'M')
        crack(s, [(cx - 1, cy), (cx, cy + 4)], 'M')
        for (x, y) in ((40, 4), (41, 4), (42, 5), (41, 5), (43, 6), (42, 6)): s.put(x, y, 'K')
        stamp_on(s, 36, 2, SCORCH_L); stamp_on(s, 18, 22, SCORCH_S)
        shift_rect(s, 14, 24, 6, 10, 0, 3); s.hline(14, 6, 10, 'K')                 # the chute has dropped off its bracket
        crack(s, [(50, 6), (53, 9), (52, 12)], 'M'); stamp_on(s, 28, 35, SCORCH_S)
    def glow_more(self, g, ox, oy, i, flick, k):
        if flick is not None: glow(g, ox + 42, oy + 4, 5, YEL, 0.6 if flick else 0.35, 2.0)

class SmelterMk2(_Smelter):
    id = 'smelter_mk2'
    notes = ('Concord Smelter Mk2 (standard, 4x3, manned): the Mk1 frame (hopper, console, coupling, casting line) with two crucibles, each in one copper coil turn, '
             'fed by a long chute off the hopper, and a great deal of cooling pipe: a steel loop with blue coolant bands runs down the right edge, along under the crucibles '
             'and up between them. Two spouts pour into the line. '
             'Damaged: the pipe between the crucibles has split and vents coolant steam, the right crucible lip is cracked and dribbles, the console bar reads red. '
             'Disabled: both melts set into cracked grey cakes, the split pipe hangs open, the chute sags, the line is cold.')
    POTS = [(27, 16, 5), (48, 16, 5)]
    def body(self, s, on, i):
        # the cooling loop: right edge, under the crucibles, up between them
        steel_pipe_h(s, 17, 28, 44, bands=(29, 46)); steel_pipe_v(s, 58, 4, 26, bands=(10, 20)); steel_pipe_v(s, 36, 6, 23, bands=(14,))
        elbow(s, 57, 27); elbow(s, 35, 27); elbow(s, 57, 3); elbow(s, 35, 5)
        for (cx, cy, r) in self.POTS:
            crucible(s, cx, cy, r, on, i, seed=0.3 + cx * .1, crust=4, spout='s', coil=1, trunnions=None)
        # the feed chute: along the top from the hopper, a drop over each crucible
        s.rect(14, 3, 41, 4, 'S'); s.hline(14, 3, 41, 'L'); s.hline(14, 6, 41, 'W'); s.vline(54, 3, 4, 'E')
        s.hline(14, 4, 40, 'M')
        for (cx, cy, r) in self.POTS:
            s.rect(cx - 1, 5, 3, 2, 'D'); s.put(cx, 5, 'K')
            if on: s.put(cx, 7 + (i + cx) % 2, 'M')
        stencil(s, 17, 26, 'L', 0); stencil(s, 50, 26, 'L', 2)
    def hurt(self, s, i):
        s.rect(36, 13, 3, 2, 'K'); s.put(35, 12 - i, 'L'); s.put(39, 11, 'M' if i else 'L'); s.put(37, 10 - i, 'H'); s.put(34, 10 + i, 'M')   # the split pipe vents steam
        crack(s, [(52, 19), (54, 21), (53, 23)], 'M'); s.put(54, 22, 'o'); s.put(55, 23, 'r' if i else 'o'); s.put(55, 24, 'r')
        for k in range(3): s.hline(6, 20 + k, 2, 'r')
        s.put(5, 30, 'r'); s.put(6, 30, 'r')
    def wreck(self, s):
        for (cx, cy, r) in self.POTS:
            crack(s, [(cx - 3, cy - 2), (cx, cy), (cx + 3, cy + 1)], 'M')
        s.rect(36, 13, 3, 3, 'K'); s.stamp(39, 13, art("KK.\nKSK\n.KK"))
        shift_rect(s, 30, 55, 3, 7, 0, 2); s.hline(30, 3, 25, 'K')
        stamp_on(s, 44, 7, SCORCH_S); stamp_on(s, 20, 20, SCORCH_S)
    def glow_more(self, g, ox, oy, i, flick, k):
        if flick is not None: glow(g, ox + 37, oy + 11, 4, RGB['L'], 0.4 if flick else 0.25, 2.0)

class SmelterMk3(_Smelter):
    id = 'smelter_mk3'
    notes = ('Concord Smelter Mk3 (standard, 4x3, manned): three crucibles on one frame in a zig-zag (two at the back, one forward), each in a copper coil; a feed conveyor across '
             'the top from the hopper with a drop to each; heat-sink fin stacks either side of the forward crucible; armoured, bolted corners; the paint burnt off round the '
             'coils (bare steel and brown scorch). Three spouts pour into the casting line. '
             'Damaged: a fin stack is bent and glowing, the forward crucible lip is cracked and dribbles, the left coil arcs, the console bar reads red. '
             'Disabled: three cold cracked cakes, the fin stack collapsed, the feed conveyor broken and sagging, the line dead.')
    POTS = [(24, 12, 4), (38.5, 20, 4), (53, 12, 4)]
    def housing(self, s):
        _Smelter.housing(self, s)
        for (x, y) in ((1, 1), (56, 1), (1, 41), (56, 41)):                     # armoured corners
            bev(s, x, y, 7, 6, 'L', 'M', 'S', cham=False); bolt(s, x + 2, y + 2)
        for (x, y) in ((15, 1), (30, 1), (44, 46), (20, 46), (62, 20)):          # the paint burnt off the frame
            s.put(x, y, 'q'); s.put(x + 1, y, 'n') if x < 62 else s.put(x, y + 1, 'n')
    def body(self, s, on, i):
        # heat-sink fins either side of the forward crucible
        for x0 in (17, 47):
            bev(s, x0, 22, 13, 8, 'W', 'E', 'D')
            for fy in range(23, 29, 2): s.hline(x0 + 1, fy, 11, 'M'); s.hline(x0 + 1, fy + 1, 11, 'D')
            s.put(x0 + 1, 23, 'L')
        for (cx, cy, r) in self.POTS:
            crucible(s, cx, cy, r, on, i, seed=cx * .07, crust=3, spout='s', coil=1, trunnions=None)
        # the burnt paint round the coils
        for (x, y) in ((17, 5), (31, 5), (45, 6), (60, 9), (30, 27), (46, 19)): stamp_on(s, x, y, art("qn\n.q"))
        # the feed conveyor across the top, a drop to each crucible
        s.rect(14, 2, 47, 4, 'S'); s.hline(14, 2, 47, 'L'); s.hline(14, 5, 47, 'W')
        for x in range(15, 60, 3): s.put(x + (i % 3 if on else 0), 3, 'E')
        for (bx, c) in ((19, 'u'), (33, 'M'), (45, 'Q'), (56, 'S')):
            s.put(bx + (i if on else 0), 4, c)
        for (cx, cy, r) in self.POTS:
            s.put(int(cx), 6, 'D'); s.put(int(cx) - 1, 6, 'D')
        s.rect(37, 6, 3, 8, 'S'); s.vline(37, 6, 8, 'L'); s.vline(39, 6, 8, 'W')       # the drop to the forward crucible
        if on: s.put(38, 7 + 2 * (i % 3), 'M')
    def hurt(self, s, i):
        for fy in range(23, 29, 2): s.hline(48, fy, 11, 'r' if (fy + i) % 4 == 1 else 'n')         # the right fin stack bent and glowing
        crack(s, [(47, 22), (51, 26), (50, 29)], 'M')
        crack(s, [(42, 24), (44, 26), (43, 28)], 'M'); s.put(44, 27, 'o'); s.put(45, 28, 'r' if i else 'o')
        s.put(16, 9 + i, 'y'); s.put(17, 7, 'H' if i else 'y'); stamp_on(s, 15, 8, SCORCH_S)
        for k in range(3): s.hline(6, 20 + k, 2, 'r')
        s.put(5, 30, 'r'); s.put(6, 30, 'r')
    def wreck(self, s):
        for (cx, cy, r) in self.POTS:
            crack(s, [(int(cx) - 3, int(cy) - 1), (int(cx), int(cy)), (int(cx) + 2, int(cy) + 2)], 'M')
        s.rect(48, 23, 11, 6, 'D'); s.stamp(48, 24, art("KKKKKKKKKKK\nKSWKSWKKSWK\n.KKK.KKKKK."))
        shift_rect(s, 40, 61, 2, 6, 0, 2); s.hline(40, 2, 21, 'K')
        stamp_on(s, 26, 6, SCORCH_L); stamp_on(s, 34, 26, SCORCH_S)
    def glow_more(self, g, ox, oy, i, flick, k):
        if flick is not None:
            glow(g, ox + 16.5, oy + 8.5, 4, YEL, 0.5 if flick else 0.3, 2.0)
            glow(g, ox + 53, oy + 26, 7, MOLTEN, 0.35, 2.0, sx=1.5)

# ============================================================ SLAG POT (scrap, 3x3)
class SlagPot(LComp):
    id = 'smelter_scrap_mk1'; cells = (3, 3)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 5), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    dark = {'(': 'n', ')': 'q', 'e': 'n'}
    notes = ('Scrapper Clans "Slag Pot" (scrap, 3x3, manned): a riveted iron cauldron on four stubby legs, no frame round it. Scrap goes in the top: a rusty hopper top-right '
             'tips into it, and a half-melted hazard-striped hull plate and a pipe end are still sinking in the slag. A welded rust patch on its side, a hand wheel on the left '
             'that tips it (the operator\'s post) and a cracked gauge with an amber lamp; a pour lip bottom-right dribbles into a rusty ingot tray with hazard tape. '
             'The on loop: the crust drifts, bubbles pop in turn, the plate bobs, a drop falls from the lip, the fresh ingot dims, and the fire under it flickers on the floor (glow). '
             'Damaged: the side has split above a leg and molten weeps onto the floor, the patch plate hangs by one bolt, the gauge needle is pinned in the red. '
             'Disabled: a cold grey cake with the plate stuck in it, the back-left leg snapped and its foot lying loose, the patch fallen off onto the floor, the tray kicked askew.')
    C = (22, 21); R = 15; MR = 9
    def legs(self, s, broken=False):
        cx, cy = self.C
        for k, (dx, dy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
            if broken and k == 2: continue
            fx, fy = int(cx + dx * 12.5) - 2, int(cy + dy * 12.5) - 2
            thick(s, int(cx + dx * 9), int(cy + dy * 9), fx + 2, fy + 2, 3, 'W', 'S', 'E')
            s.rect(fx, fy, 5, 4, 'W'); s.hline(fx, fy, 5, 'S'); s.hline(fx, fy + 3, 5, 'E'); s.put(fx + 1, fy + 1, 'M')
    def pot(self, s, on, i):
        cx, cy = self.C; R, MR = self.R, self.MR
        for y in range(cy - R - 1, cy + R + 2):
            for x in range(cx - R - 1, cx + R + 2):
                dx, dy = x + .5 - cx, y + .5 - cy
                d = (dx * dx + dy * dy) ** .5
                if d > R: continue
                lit = (dx + dy) / max(1.0, d)
                if d > MR + 2.6:                                                  # the iron belly, lit top-left
                    c = 'M' if lit < -1.0 else ('S' if lit < -0.2 else ('W' if lit < 0.8 else 'E'))
                    if d > R - .9: c = 'S' if lit < -0.6 else ('W' if lit < 0.5 else 'E')
                elif d > MR + 1.4: c = 'L' if lit < -0.4 else ('M' if lit < 0.6 else 'S')    # the rolled rim
                elif d > MR + .5: c = 'D' if lit < 0.2 else 'W'                  # the inner wall, dark on the far side
                else: continue
                s.put(x, y, c)
        for k in range(12):                                                       # rivets round the belly
            a = k * math.pi / 6 + .2
            bx, by = int(cx - .5 + math.cos(a) * (R - 2.4)), int(cy - .5 + math.sin(a) * (R - 2.4))
            s.put(bx, by, 'L' if math.cos(a) + math.sin(a) < 0 else 'M'); s.put(bx + 1, by + 1, 'E')
        # a welded rust patch on the lower left of the belly, a rust run under it
        for (x, y) in [(x, y) for y in range(28, 34) for x in range(9, 16)]:
            if s.get(x, y) in 'MSWE' and ((x + .5 - cx) ** 2 + (y + .5 - cy) ** 2) ** .5 > MR + 3: s.put(x, y, 'u')
        s.hline(10, 28, 5, 'Q'); s.put(9, 29, 'Q'); bolts(s, [(10, 30), (13, 29)]); weld(s, 15, 28, 5, True)
        stamp_on(s, 31, 10, art("u.\nuu\n.u")); stamp_on(s, 34, 26, art(".u\nu.\nu."))
        slag(s, cx, cy, MR, on, i)
        # the scrap still sinking: a corner of hull plate with its hazard stripe, and a pipe end, glowing red where they meet the melt
        bob = (i % 2) if on else 0
        s.stamp(14, 13 + bob, art("""
            .DDDD.
            DLMMSD
            DaKaKD
            DMSSWD
            .D..D."""))
        for x in range(13, 21): s.put(x, 18 + bob, 'r' if on else 'D')
        s.stamp(26, 24 - bob, art("""
            DDD
            DMD
            DWD""")); s.put(26, 27 - bob, 'r' if on else 'D'); s.put(28, 27 - bob, 'r' if on else 'D')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(48, 48)
        cx, cy = self.C
        self.legs(s)
        # the ingot tray, bottom-right, and the lip dribbling into it
        bev(s, 31, 35, 15, 11, 'Q', 'u', 'n'); hazard(s, 32, 44, 13, 1)
        s.rect(33, 37, 11, 6, 'n')
        ingot(s, 34, 38, 5, 4, ('r', '(', 'e', 'n') if on and i % 2 == 0 else (('(', 'e', 'n', 'n') if on else ('L', 'M', 'S', 'W')))
        ingot(s, 39, 38, 5, 4)
        self.pot(s, on, i)
        thick(s, 32, 32, 35, 35, 3, 'S', 'M', 'E')                                # the pour lip
        if on:
            s.put(34, 34, 'o'); s.put(35, 35, 'y'); s.put(36, 36 + i % 2, 'o')
        # the hopper top-right, tipped toward the rim
        funnel(s, 36, 1, 10, 10, rim=('Q', 'u', 'n'), faces=('n', 'q', 'Q', 'u'), throat='K')
        scrap_bits(s, 37, 2, 8, 8, i if on else 0, seed=2)
        hazard(s, 36, 1, 10, 1)
        thick(s, 37, 10, 33, 13, 3, 'S', 'M', 'E')
        # the hand wheel that tips it (left), and its axle into the belly
        s.rect(7, 20, 2, 2, 'S')
        s.stamp(0, 16, art("""
            ..MSSW..
            .M.S..W.
            M..S...E
            SSSLSSSE
            S..S...E
            .W.S..E.
            ..WEEE..""")); s.stamp(0, 15, art("uQ\nnu"))
        # the gauge on a stalk, bottom-left, and its lamp
        circle(s, 6, 40, 4.2, 'E'); circle(s, 6, 40, 3.2, 'L'); s.put(4, 38, 'H')
        line(s, 6, 40, 8 if on else 4, 38 + (i % 2 if on else 3), 'r'); s.put(6, 40, 'K')
        s.put(3, 41, 'g'); s.put(9, 41, 'r')
        lamp(s, 11, 44, 'a', on and i % 2 == 0)
        return s
    def hurt(self, s, i):
        cx, cy = self.C
        crack(s, [(11, 12), (9, 15), (10, 17)], 'M')                             # the belly split over the back-left leg
        s.put(8, 15, 'o'); s.put(7, 16, 'o'); s.put(7, 17, 'r'); s.put(6, 17, 'o' if i else 'r'); s.hline(4, 18, 3, 'r'); s.put(5, 18, 'o')
        s.rect(9, 28, 7, 6, 'D'); s.stamp(10, 32, art("KKKKKKK\nKQuuuuK\nKuuuunK\n.KKKKK."))     # the patch hangs by one bolt
        line(s, 6, 40, 9, 39, 'r'); s.put(9, 39, 'r')
        s.put(13, 24 + i, 'y'); s.put(12, 23, 'H' if i else 'y')
    def wreck(self, s):
        cx, cy = self.C
        crack(s, [(15, 18), (19, 21), (24, 20), (27, 24)], 'M'); crack(s, [(21, 15), (22, 19)], 'M')
        s.rect(9, 28, 7, 6, 'K'); s.rect(10, 29, 5, 4, 'D')                      # the patch fell off: a dark hole, the plate on the floor by the wheel
        s.stamp(0, 26, art(".KKKKK\nKQuuuK\nKunnnK\nKKKKK."))
        for y in range(2, 12):                                                    # the back-left leg snapped: its foot lies loose in the corner
            for x in range(2, 13):
                if ((x + .5 - cx) ** 2 + (y + .5 - cy) ** 2) ** .5 > self.R + .5: s.erase(x, y)
        s.stamp(9, 9, art("KK\nKW")); s.stamp(1, 4, art(".KKKK\nKWSWK\nKEWEK\n.KKK."))
        stamp_on(s, 18, 27, SCORCH_L); stamp_on(s, 30, 12, SCORCH_S)
        shift_rect(s, 31, 47, 35, 47, 1, 1)                                       # the tray kicked askew
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.6 if flick else 0.85)
        cx, cy = self.C
        f = [1.0, 0.8, 0.95, 0.7][i % 4]
        glow(g, ox + cx, oy + cy + 1, self.R + 8, RGB['o'], 0.26 * f * k, 1.2)      # the fire under it, on the floor
        glow(g, ox + cx, oy + cy, self.MR + 4, MOLTEN, 0.4 * f * k, 1.6)
        glow(g, ox + cx, oy + cy, self.MR * .6, WHITEHOT, 0.3 * f * k, 1.6)
        glow(g, ox + 36.5, oy + 40, 4, HOT, (0.45 if i % 2 == 0 else 0.3) * k, 2.0)
        glow(g, ox + 35, oy + 35, 3, HOT, 0.5 * k, 2.0)
        if i % 2 == 0: glow(g, ox + 12, oy + 45, 3, AMBER, 0.5 * k, 2.0)
        if flick is not None: glow(g, ox + 6, oy + 17, 5, MOLTEN, 0.6, 1.8)

# ============================================================ PLASMA FORGE (neon, 4x3)
class PlasmaForge(_Smelter):
    id = 'smelter_neon_mk1'
    notes = ('Lumen "Plasma Forge" (neon, 4x3, manned): the smelter frame in navy panels with 1px cyan edges. A glass bottle holds a magenta arc that spins round a crystal '
             'electrode (two bright arc heads chase round the ring, 4 frames); tuning-fork resonators either side hum (their tines spread and close: it sings); '
             'a crystal hopper top-left feeds silicon shards in; the console screen draws the song as a cyan wave; a capacitor bank with magenta charge lamps on the right; '
             'the line along the bottom carries new glass lattice (white-magenta hot, then cyan, then set). '
             'Damaged: the bottle is cracked and the arc leaks out through it in a stray tendril, one resonator is bent and silent, the wave is jagged. '
             'Disabled: the bottle shattered and dark, the electrode dull, every edge line dead, shards in the line.')
    POTS = [(32, 16, 0)]
    dark = {'(': 'n', ')': 'q', 'e': 'n'}
    def housing(self, s):
        bev(s, 1, 1, 62, 46, 'j', 'J', 'I')
        for (x, y) in ((3, 2), (60, 2), (3, 45), (60, 45)): s.put(x, y, 'm')
    def hopper(self, s, i, on, x=3, y=3, w=11, h=12):
        funnel(s, x, y, w, h, rim=('j', 'J', 'I'), faces=('N', 'I', 'J', 'j'), throat='N')
        for k, (dx, dy) in enumerate(((2, 2), (6, 3), (3, 6), (7, 7), (5, 5))):
            yy = dy + (1 if on and (k + i) % 4 == 0 else 0)
            crystal(s, x + dx, y + yy, "01\n12", ['H' if on else 'M', 'c' if on else 'S', 'C' if on else 'W'])
    def side(self, s, on, i):
        bev(s, 3, 17, 11, 16, 'I', 'J', 'N')
        recess(s, 5, 19, 7, 9, 'N', 'K')
        for k in range(7):                                                       # the song, a cyan wave
            h = int(round(3.5 + 2.6 * math.sin((k + 2 * i) * 0.9))) if on else 4
            s.put(5 + k, 20 + (7 - h) if k < 7 else 20, 'c' if on else 'E')
        s.hline(5, 19, 7, 'K')
        lamp(s, 5, 30, 'm', on); lamp(s, 9, 30, 'c', on and i % 2 == 0)
        bev(s, 3, 35, 11, 10, 'I', 'J', 'N'); circle(s, 8.5, 40, 3.2, 'N'); ring(s, 8.5, 40, 2.2, 3.4, 'c' if on else 'W')
    def line_(self, s, on, i):
        x, y, w, h = self.LINE
        bev(s, x, y, w, h, 'j', 'J', 'I')
        s.rect(x + 1, y + 2, w - 2, h - 4, 'N'); s.hline(x + 1, y + 2, w - 2, 'K')
        off = (2 * i) if on else 0
        sp = int(self.POTS[0][0])
        for k in range(-1, w // self.PITCH + 2):
            mx = x + 1 + k * self.PITCH + off
            d = mx - sp
            st = ('empty' if d <= -self.PITCH else ('hot' if d <= 1 else ('warm' if d <= 9 else 'set'))) if on else ('set' if k % 2 else 'empty')
            for yy in range(y + 3, y + h - 3):
                for xx in range(mx, mx + self.PITCH - 1):
                    if not (x + 1 <= xx < x + w - 1): continue
                    gx, gy = (xx - mx) % 3 == 1, (yy - y - 3) % 3 == 1
                    if st == 'empty': c = 'I' if (gx and gy) else 'N'
                    elif st == 'hot': c = 'H' if (gx or gy) else 'm'
                    elif st == 'warm': c = 'H' if (gx and gy) else ('c' if (gx or gy) else 'C')
                    else: c = 'c' if (gx and gy) else ('C' if (gx or gy) else 'B')
                    s.put(xx, yy, c)
        for yy in range(y - 4, y + 4):                                            # the drawn glass falling from the bottle's nozzle
            s.put(sp, yy, ('m' if (yy + i) % 2 else 'H') if on else 'E'); s.put(sp + 1, yy, 'P' if on else 'N')
    def well(self, s):
        x, y, w, h = self.WELL
        s.rect(x, y, w, h, 'I'); s.hline(x, y, w, 'N'); s.vline(x, y, h, 'N'); s.hline(x, y + h - 1, w, 'j'); s.vline(x + w - 1, y, h, 'j')
        for (px, py) in ((x + 2, y + 2), (x + w - 3, y + 2), (x + 2, y + h - 3), (x + w - 3, y + h - 3)): s.put(px, py, 'c')
    def body(self, s, on, i):
        cx, cy = 32, 16
        # the capacitor bank, right: three cells with magenta charge lamps
        for k, dy in enumerate((5, 12, 19)):
            bev(s, 51, dy, 10, 6, 'j', 'J', 'I'); s.hline(52, dy + 2, 8, 'N')
            for q in range(3): s.put(53 + 2 * q, dy + 2, 'm' if on and q <= (i + k) % 3 else 'P' if on else 'E')
        # tuning-fork resonators either side of the bottle: the tines spread and close as it sings
        for (fx, sg) in ((17, 1), (46, 1)):
            spread = (1 if i % 2 else 0) if on else 0
            s.rect(fx, 22, 3, 6, 'J'); s.vline(fx, 22, 6, 'j'); s.hline(fx, 27, 3, 'I')
            s.vline(fx - spread, 13, 9, 'c' if on else 'S'); s.vline(fx + 2 + spread, 13, 9, 'c' if on else 'S')
            s.hline(fx - spread, 21, 3 + 2 * spread, 'C' if on else 'W')
        # the bottle: a navy collar with four clamps, glass round a vacuum, the arc ring, the electrode
        disc_lit(s, cx, cy, 11, 12.4, 'j', 'J', 'I')
        for (dx, dy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            bx, by = int(cx + dx * 8.6) - 1, int(cy + dy * 8.6) - 1
            s.rect(bx, by, 3, 3, 'j'); s.put(bx + 1, by + 1, 'm' if on else 'P'); s.put(bx + 2, by + 2, 'I')
        disc_lit(s, cx, cy, 9.6, 11, 'H', 'c', 'C')
        disc_lit(s, cx, cy, 8.8, 9.6, 'B', 'C', 'c')
        circle(s, cx, cy, 8.8, 'N')
        per = math.pi
        for y2 in range(cy - 9, cy + 10):
            for x2 in range(cx - 9, cx + 10):
                dx, dy = x2 + .5 - cx, y2 + .5 - cy
                d = (dx * dx + dy * dy) ** .5
                if 5.6 < d <= 7.2:
                    if not on: s.put(x2, y2, 'I'); continue
                    a = (math.atan2(dy, dx) - i * per / 4) % per / per
                    s.put(x2, y2, 'H' if a < .1 else ('m' if a < .28 else ('P' if a < .5 else 'I')))
        if on:                                                                    # tendrils from the electrode to the arc heads
            for sg in (1, -1):
                a = i * per / 4 + .15
                tx, ty = cx + sg * math.cos(a) * 6, cy + sg * math.sin(a) * 6
                line(s, int(cx - .5 + sg * .5), int(cy - .5 + sg * .5), int(tx), int(ty), 'm')
        crystal(s, cx - 2, cy - 2, ".01.\n0112\n1122\n.22.", ['H', 'c', 'C'] if on else ['M', 'S', 'W'])
        s.put(cx - 7, cy - 8, 'H'); s.put(cx - 8, cy - 7, 'H'); s.put(cx - 6, cy - 9, 'c')     # the glass's highlight
        s.rect(31, 27, 4, 3, 'J'); s.hline(31, 27, 4, 'j')                        # the nozzle under the bottle
    def hurt(self, s, i):
        crack(s, [(41, 8), (39, 11), (41, 13)], 'H')
        line(s, 40, 12, 44 + i, 9 - i, 'm'); s.put(45, 8 - i, 'H')               # the arc leaks out through the crack
        s.vline(46, 13, 9, 'W'); s.vline(48, 13, 9, 'W'); s.put(47, 14, 'K')     # the right resonator bent and silent
        for k in range(7): s.put(5 + k, 21 + (k * 3) % 5, 'r')
    def wreck(self, s):
        crack(s, [(23, 10), (27, 14), (26, 19), (30, 22)], 'M'); crack(s, [(38, 7), (36, 12), (40, 16), (38, 22)], 'M')
        s.stamp(27, 9, art(".KK.\nKNNK\n.KK.")); s.stamp(36, 18, art("KK.\nKNK\n.KK"))
        s.stamp(45, 36, art("KK.\nKSK\n.KK")); s.stamp(22, 38, art(".KK\nKSK"))
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.6 if flick else 0.85)
        cx, cy = 32, 16
        glow(g, ox + cx, oy + cy, 18, MAG, 0.3 * k, 1.5)
        glow(g, ox + cx, oy + cy, 8, RGB['H'], 0.45 * k, 1.7)
        for sg in (1, -1):
            a = i * math.pi / 4
            glow(g, ox + cx + sg * math.cos(a) * 6.4, oy + cy + sg * math.sin(a) * 6.4, 4, RGB['H'], 0.5 * k, 1.8)
        x, y, w, h = self.LINE
        glow(g, ox + cx + 1, oy + y + 6, 6, MAG, 0.45 * k, 1.8, sx=1.3)
        glow(g, ox + cx + 12, oy + y + 6, 6, CYAN, 0.3 * k, 2.0, sx=1.5)
        for fx in (18, 47): glow(g, ox + fx, oy + 17, 4, CYAN, (0.35 if i % 2 else 0.2) * k, 2.0)
        glow(g, ox + 6.5, oy + 31, 3, MAG, 0.45 * k, 2.0)
        if i % 2 == 0: glow(g, ox + 10.5, oy + 31, 3, CYAN, 0.45 * k, 2.0)
        glow(g, ox + 8.5, oy + 23, 5, CYAN, 0.25 * k, 2.0)
        if flick is not None: glow(g, ox + 44, oy + 9, 5, MAG, 0.6 if flick else 0.35, 2.0)

ALL = [SlagPot, SmelterMk1, SmelterMk2, SmelterMk3, PlasmaForge]
