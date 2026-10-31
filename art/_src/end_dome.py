"""haven_settle / haven_lure: Halcyon's gardens under the glass dome (the same view; the lure is subtly wrong)."""
import math
from ill import *

CX, BASE_Y, RX, RY, HD = 160, 108, 205, 26, 150     # the dome: a half ellipsoid seen from inside, base ellipse centre, radii, apex height

def dome_pt(phi, e):
    p, a = math.radians(phi), math.radians(e)
    return CX + RX * math.cos(a) * math.cos(p), BASE_Y - HD * math.sin(a) - RY * math.cos(a) * math.sin(p)

RIBS = [24, 36, 48, 60, 72, 84, 96, 108, 120, 132, 144, 156]
RINGS = [14, 30, 46, 62, 76, 86]

def sky(im, wrong=False):
    # deep space: navy down to a lighter navy at the base, a diagonal nebula, stars, the far sun
    im.vgrad(0, 0, 320, 96, ['N', 'N', 'I', 'J'], 0, 1, sharp=0.8)
    for y in range(0, 100):
        for x in range(320):
            n = fbm01(x / 46.0, y / 38.0, 7, 4)
            band = math.exp(-(((y + x * 0.35) - 74) / 34.0) ** 2)
            v = (n - 0.34) * 2.4 * band
            if v > 0.05:
                col = pick(min(1.0, v), (['.', 'I', 'J', 'Z', 'V'] if not wrong else ['.', 'I', 'J', 'B', 'C']), x, y)
                im.put(x, y, col)
    return im

def stars(im, gl, f, wrong=False):
    r = Lcg(5)
    for k in range(300):
        x, y = r.below(320), r.below(88)
        t = r.below(10)
        ph = r.below(4)
        c = 'W' if t < 4 else 'S' if t < 7 else 'M' if t < 9 else r.pick(['k', 'i', 'y', 'a', 'z'])
        if wrong: c = 'x' if t < 6 else 'M'
        tw = (f + ph) % 4 == 0 and r.below(4) == 0 or ((not wrong) and t == 9 and (f + ph) % 4 == 0)
        if t >= 8 and (f + ph) % 4 in (0, 1): c = lighten(c)
        im.put(x, y, c)
        if t == 9 and (f + ph) % 4 == 0 and not wrong:
            for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)): im.put(x + dx, y + dy, 'x' if c != 'y' else 'Y')
            gl.blob(x, y, 4, 'z', 40, 1.5)

def sun(im, gl, f, wrong=False):
    sx, sy = 52, 19
    ramp = ['H', 'H', 'z', 'y', 'y', 'Y', 'a', 'T', 'u', '.'] if not wrong else ['H', 'z', 'i', 'C', 'B', 'I', '.', '.']
    im.rgrad(sx, sy, 32, ramp, sharp=0.9)
    disc = ellipse_cells(sx, sy, 5, 5)
    im.fill(disc, 'H'); im.fill(grow(disc, 1) - disc, 'y' if not wrong else 'z')
    for k in range(1, 15):                                  # flare spikes
        c = 'H' if k < 4 else 'y' if k < 8 else 'a'
        if wrong: c = 'z' if k < 5 else 'i'
        if k < (14 if f % 2 == 0 else 11): im.put(sx + 6 + k, sy, c); im.put(sx - 6 - k, sy, c)
        if k < 9: im.put(sx, sy + 6 + k, c); im.put(sx, sy - 6 - k, c)
    gl.blob(sx, sy, 40, 'y' if not wrong else 'i', 110, 2.0)
    gl.blob(sx, sy, 14, 'H', 150, 1.5)

def gate_ring(im, gl, f, wrong=False):
    gx, gy = 262, 34
    cells = ring_cells(gx, gy, 10, 10, 2)
    im.shade(cells, ['E', 'W', 'S', 'M', 'L'], gx, gy, 10, 10)
    im.outline(cells, 'K')
    inner = ellipse_cells(gx, gy, 8, 8)
    im.fill(inner, 'N')
    for (x, y) in inner:
        v = fbm01(x / 4.0 + f * 0.25, y / 4.0, 3, 2)
        im.put(x, y, pick(v * 0.8, ['N', 'B', 'C', 'c'], x, y))
    for (dx, dy) in ((0, -12), (0, 11), (-12, 0), (11, 0)):  # little pylons
        im.rect(gx + dx - 1, gy + dy - 1, 3, 3, 'S'); im.put(gx + dx - 1, gy + dy - 1, 'L')
    lit = 'c' if f % 2 == 0 else 'z'
    im.put(gx, gy - 11, lit); im.put(gx, gy + 11, 'c')
    gl.blob(gx, gy, 18, 'c', 70, 2.0)

def dome(im, gl, f, wrong=False):
    # latitude rings (far halves)
    for e in RINGS:
        pts = [dome_pt(p, e) for p in range(0, 181, 2)]
        for (a, b) in zip(pts, pts[1:]):
            im.tline(a[0], a[1], b[0], b[1], 'S', 2)
            im.line(a[0], a[1] - 1, b[0], b[1] - 1, 'M')
            im.line(a[0], a[1] + 1, b[0], b[1] + 1, 'E')
    # meridian ribs
    for ph in RIBS:
        pts = [dome_pt(ph, e) for e in range(0, 91, 2)]
        for (a, b) in zip(pts, pts[1:]):
            im.tline(a[0], a[1], b[0], b[1], 'W', 3)
            im.line(a[0] - 1, a[1], b[0] - 1, b[1], 'M')
            im.line(a[0] + 1, a[1], b[0] + 1, b[1], 'E')
    # base ring: a stone-and-steel band
    pts = [dome_pt(p, 0) for p in range(0, 181, 2)]
    for (a, b) in zip(pts, pts[1:]):
        for k in range(0, 9):
            col = 'M' if k == 0 else 'S' if k < 2 else 'W' if k < 5 else 'E' if k < 8 else 'K'
            im.line(a[0], a[1] + k, b[0], b[1] + k, col)

# ------------------------------------------------------------------ the garden
def wall_y(x):
    """y of the far base ring at screen x (its top edge)."""
    c = (x - CX) / float(RX)
    c = max(-1.0, min(1.0, c))
    return BASE_Y - RY * math.sqrt(1 - c * c)

def lawn(im, wrong=False):
    # far hills, terraces, the stream bank, the middle lawn and the foreground: bands with wavy top edges, flat tones, tufts for texture
    def edge(y0, a1, p1, a2, p2, ph=0.0): return lambda x: y0 + a1 * math.sin(x / p1 + ph) + a2 * math.sin(x / p2 + ph * 2.3)
    layers = [   # (top edge, ramp dark->light)
        (edge(97, 3, 21, 1.5, 9, 0.3), ['I', 'J', 'A', 'O']),            # far hills, bluish with distance
        (edge(106, 3, 17, 1.5, 7, 1.0), ['A', 'O', 'O', 'R']),           # first terrace
        (edge(118, 2, 13, 1.0, 6, 2.0), ['A', 'O', 'R', 'R']),           # bank
        (edge(131, 1.5, 19, 1.0, 8, 0.7), ['A', 'O', 'R', 'R']),         # mid lawn
        (edge(149, 2, 25, 1.0, 9, 1.9), ['A', 'O', 'O', 'R']),           # near lawn
    ]
    for li, (fn, ramp) in enumerate(layers):
        for x in range(320):
            top = int(round(fn(x)))
            for y in range(top, 180):
                t = (y - top) / (26.0 if li < 4 else 44.0)
                v = max(0.0, min(1.0, 0.12 + t * 0.62 + (fbm01(x / 30.0, y / 12.0, 20 + li, 2) - 0.5) * 0.5))
                im.put(x, y, pick(v, ramp, x, y, 2.4))
        for x in range(320):
            top = int(round(fn(x)))
            im.put(x, top, 'A' if li else 'N')
    # grass tufts: short strokes, darker below and lighter on top (light from the top-left)
    r = Lcg(99)
    for k in range(520):
        x, y = r.below(320), r.rng(104, 179)
        if im.get(x, y) not in ('O', 'R', 'A', 'U'): continue
        c = im.get(x, y)
        sz = 1 + (y - 100) // 28
        for j in range(sz): im.put(x, y - j, lighten(c) if j == sz - 1 else c)
        if r.below(2): im.put(x + 1, y, darken(c))

def river(im, f, wrong=False):
    # a stream that crosses the middle ground from left to right, under the bridge at x~188
    def cy(x): return 124 + 3 * math.sin(x / 38.0 + 0.8)
    cells = set()
    for x in range(320):
        c = cy(x)
        wd = 4 + 1.5 * math.sin(x / 21.0)
        for y in range(int(c - wd), int(c + wd) + 1): cells.add((x, y))
    for (x, y) in cells:
        t = (y - (cy(x) - 5)) / 10.0
        v = max(0.0, min(1.0, t + (fbm01(x / 9.0, y / 3.0, 41, 2) - 0.5) * 0.6))
        im.put(x, y, pick(0.12 + v * 0.8, ['J', 'B', 'C', 'C', 'i'], x, y, 2.2))
    # ripples (they slide along the stream: 4 frames)
    r = Lcg(77)
    for k in range(34):
        x = (r.below(320) + f * 2 * (1 if k % 2 else -1)) % 320
        y = int(cy(x)) + r.rng(-2, 2)
        if (x, y) in cells:
            im.hline(x, y, r.rng(2, 4), 'z' if k % 3 == 0 else 'i')
    # banks: stones and reeds
    for (x, y) in grow(cells, 1) - cells:
        if im.get(x, y) in ('O', 'R', 'U', 'A'): im.put(x, y, 'q' if (x * 7 + y * 3) % 5 else 'Q')
    for x in range(0, 320, 3):
        if (x * 13) % 7 < 3:
            yb = int(cy(x) - 6 - 1.5 * math.sin(x / 21.0))
            im.vline(x, yb - 2, 3, 'U'); im.put(x, yb - 3, 'g')
    return cells, cy

def canopy(im, cx, cy, rx, ry, seed, n=8, ramp=('A', 'O', 'R', 'U', 'g'), sharp=1.5, gl=None):
    r = Lcg(seed)
    blobs = []
    for i in range(n):
        bx = cx + (r.f() - 0.5) * rx * 1.25
        by = cy + (r.f() - 0.5) * ry * 1.05
        blobs.append((by + r.f(), bx, 0.42 + 0.32 * r.f()))
    blobs.sort()
    allc = set()
    for (by, bx, br) in blobs:
        rxb, ryb = rx * br, ry * br
        cells = ellipse_cells(bx, by, rxb, ryb)
        allc |= cells
        im.shade(cells, list(ramp), bx - rxb * 0.12, by - ryb * 0.12, rxb * 1.05, ryb * 1.05, light=(-0.5, -0.7), sharp=sharp, bias=-0.2)
        # leaf flecks on the lit side
        for k in range(int(rxb * ryb / 14)):
            lx, ly = bx + (r.f() - 0.8) * rxb * 1.1, by + (r.f() - 0.85) * ryb
            if (int(lx), int(ly)) in cells:
                im.put(int(lx), int(ly), ramp[3] if r.below(3) else ramp[4])
    return allc

def tree(im, x, ybase, h, seed, wide=1.0, f=0, sway=1):
    """trunk + clumpy canopy; ybase is where the trunk meets the lawn."""
    r = Lcg(seed)
    tw = max(2, int(h * 0.09))
    th = int(h * 0.55)
    # trunk, lit on the left
    for j in range(th):
        w = tw + (1 if j > th - 4 else 0)
        for i in range(w):
            c = 'Q' if i == 0 else 'q' if i < w - 1 else 'n'
            im.put(x - tw // 2 + i - (1 if j > th - 4 else 0), ybase - j, c)
    sh = ellipse_cells(x + 3, ybase, h * 0.38 * wide, max(2, h * 0.07))
    im.dither(sh, None, 'A', 0.55)
    cc = canopy(im, x + (f % 2) * sway * 0, ybase - th - h * 0.2, h * 0.5 * wide, h * 0.38, seed + 3, n=int(6 + h / 14))
    return cc

def cottage(im, gl, x, y, w, h, wall='s', roof='T', seed=1, lit=True, f=0, wrong=False):
    """a round-roofed cottage; (x, y) is the bottom-left corner."""
    r = Lcg(seed)
    body = rect_cells(x, y - h, w, h)
    for (i, j) in body:
        t = (i - x) / float(max(1, w - 1))
        c = 'Y' if t < 0.25 else wall if t < 0.7 else 'Q'
        if j >= y - 2: c = 'v' if t < 0.7 else 'q'
        im.put(i, j, c)
    # roof: a shingled dome that overhangs
    rh = max(4, int(w * 0.45))
    rc = ellipse_cells(x + w / 2.0, y - h, w / 2.0 + 2, rh) - rect_cells(x - 4, y - h + 1, w + 10, rh + 4)
    im.shade(rc, [roof_dark(roof), 'u', roof, 'Y'] if roof == 'T' else ['n', 'q', 'Q', 'Y'], x + w * 0.35, y - h - 1, w / 2.0 + 2, rh, light=(-0.5, -0.5), sharp=1.3)
    for k in range(2, rh, 2):
        for i in range(x - 1, x + w + 2):
            if (i + k) % 4 == 0 and (i, y - h - k) in rc: im.put(i, y - h - k, roof_dark(roof))
    im.hline(x - 2, y - h, w + 4, 'u'); im.hline(x - 2, y - h + 1, w + 4, 'n')
    # door and window
    dx = x + w // 2 - 1 + r.below(2)
    im.rect(dx, y - 6, 3, 6, 'n'); im.put(dx, y - 6, 'q'); im.put(dx + 2, y - 4, 'a')
    if w >= 16:
        for wx in (x + 2, x + w - 5):
            im.rect(wx, y - h + 4, 3, 3, ('z' if wrong else 'y') if lit else 'W'); im.hline(wx - 1, y - h + 7, 5, 'u'); im.vline(wx + 1, y - h + 4, 3, 'i' if wrong else 'a')
            if lit: gl.blob(wx + 1, y - h + 5, 7, 'i' if wrong else 'y', 95, 2.0)
    elif lit:
        im.rect(x + 2, y - h + 3, 2, 2, 'z' if wrong else 'y'); gl.blob(x + 3, y - h + 4, 6, 'i' if wrong else 'y', 85, 2.0)
    # chimney with a thread of smoke
    cx = x + w - 4
    im.rect(cx, y - h - rh - 1, 2, 3, 'W'); im.put(cx, y - h - rh - 1, 'M')

def roof_dark(c): return {'T': 'u', 'u': 'n', 'Q': 'q', 'a': 'u'}.get(c, 'n')

def path(im, f):
    def xc(y): t = (y - 126) / 54.0; return 196 - 66 * t * t
    def wd(y): return 5 + 17 * ((y - 126) / 54.0)
    cells = set()
    for y in range(126, 180):
        for x in range(int(xc(y) - wd(y)), int(xc(y) + wd(y)) + 1): cells.add((x, y))
    for (x, y) in cells:
        v = 0.5 + (fbm01(x / 9.0, y / 5.0, 61, 2) - 0.5) * 0.5 - (y - 126) / 180.0 * 0.1 - (0.12 if x > xc(y) + wd(y) * 0.4 else 0)
        im.put(x, y, pick(v, ['q', 'Q', 's', 'Y'], x, y, 2.6))
    for (x, y) in grow(cells, 1) - cells:
        if im.get(x, y) in ('O', 'R', 'U', 'A', 'g'): im.put(x, y, 'q' if (x + y) % 3 else 'n')
    return cells, xc

def bridge(im, x, y):
    # a small arched stone bridge over the stream at (x, y) deck level
    deck = rect_cells(x - 14, y - 4, 28, 5)
    im.fill(deck, 'M')
    im.hline(x - 14, y - 4, 28, 'L'); im.hline(x - 14, y, 28, 'W')
    arch = ellipse_cells(x, y + 1, 8, 5) & rect_cells(x - 9, y + 1, 18, 8)
    im.fill(arch, 'D'); im.fill(shrink(arch, 1) & rect_cells(x - 9, y + 3, 18, 6), 'K')
    for k in range(-14, 14, 4): im.vline(x + k, y - 7, 3, 'S'); im.put(x + k, y - 8, 'M')
    im.hline(x - 14, y - 7, 28, 'W'); im.hline(x - 14, y - 8, 28, 'M')

def mast(im, gl, x, yb, h, f, wrong=False):
    """the Lantern: a slim mast with a ring dish and a caged lamp at the top that pulses (the broadcast)."""
    top = yb - h
    for j in range(h):
        im.put(x - 1, yb - j, 'M'); im.put(x, yb - j, 'S'); im.put(x + 1, yb - j, 'E')
    for j in range(6, h, 12):                                  # guy collars
        im.hline(x - 2, yb - j, 5, 'W'); im.put(x - 2, yb - j, 'L')
    im.rect(x - 4, yb - 3, 9, 3, 'W'); im.hline(x - 4, yb - 3, 9, 'M'); im.hline(x - 4, yb - 1, 9, 'E')
    dish = ring_cells(x, top + 12, 8, 3, 1)                    # the ring
    im.fill(dish, 'S'); im.fill({(a_, b_) for (a_, b_) in dish if b_ < top + 12}, 'L')
    # the lantern cage
    cage = rect_cells(x - 3, top - 9, 7, 9)
    lit = ['H', 'y', 'H', 'y'][f % 4] if not wrong else 'z'
    for (i, j) in cage: im.put(i, j, lit if abs(i - x) < 3 and 0 < j - (top - 9) < 8 else 'W')
    im.fill({(i, j) for (i, j) in cage if (i - x) in (-3, 3) or j in (top - 9, top - 1)}, 'W')
    im.vline(x, top - 8, 7, 'Y' if not wrong else 'i')
    im.hline(x - 4, top - 10, 9, 'S'); im.hline(x - 3, top - 11, 7, 'M'); im.put(x, top - 12, 'M')
    im.put(x - 3, top - 9, 'L')
    gl.blob(x, top - 5, 22 if f % 2 == 0 else 18, 'y' if not wrong else 'i', 170, 1.7)
    gl.blob(x, top - 5, 9, 'H', 120, 1.3)
    gl.blob(x, top + 12, 11, 'z', 40, 1.5)

def lamps(im, gl, f, strings, wrong=False):
    for (pts) in strings:
        for (a, b) in zip(pts, pts[1:]):
            n = int(max(abs(b[0] - a[0]), 1) / 8) + 1
            sag = abs(b[0] - a[0]) * 0.16
            prev = a
            for k in range(1, 41):
                t = k / 40.0
                px_, py_ = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t + sag * 4 * t * (1 - t)
                im.line(prev[0], prev[1], px_, py_, 'W'); prev = (px_, py_)
            for k in range(1, n):
                t = k / float(n)
                lx, ly = int(a[0] + (b[0] - a[0]) * t), int(a[1] + (b[1] - a[1]) * t + sag * 4 * t * (1 - t))
                on = (k + f) % 2 == 0
                c1 = 'y' if on else 'a'
                if wrong: c1 = 'z' if on else 'i'
                im.put(lx, ly + 1, c1); im.put(lx, ly + 2, 'a' if not wrong else 'k')
                gl.blob(lx, ly + 1, 6 if on else 4, 'y' if not wrong else 'i', 110 if on else 70, 1.8)

def ship(im, gl, x, y, f, wrong=False):
    """the little ship, docked on its pad: (x, y) is the pad level under the nose; it faces left. 64 wide."""
    # pad
    pad = ellipse_cells(x + 34, y + 2, 40, 7)
    im.shade(pad, ['K', 'E', 'W', 'S', 'M'], x + 30, y - 2, 42, 9, sharp=1.2)
    im.outline(pad, 'K')
    for k in range(10):                                   # pad markings
        a = math.radians(k * 36)
        im.put(int(x + 34 + 31 * math.cos(a)), int(y + 2 + 4.8 * math.sin(a)), 'a' if k % 2 == 0 else 'y')
    gl.blob(x + 4, y + 3, 6, 'y', 60, 1.5)
    # legs
    for lx in (x + 12, x + 33, x + 54):
        im.vline(lx, y - 7, 8, 'W'); im.vline(lx - 1, y - 7, 8, 'M'); im.hline(lx - 2, y + 1, 5, 'E'); im.put(lx - 2, y + 1, 'S')
    # hull
    hull = poly_cells([(x, y - 14), (x + 6, y - 22), (x + 16, y - 27), (x + 36, y - 29), (x + 54, y - 27), (x + 63, y - 21), (x + 65, y - 13), (x + 60, y - 8), (x + 10, y - 7), (x + 3, y - 9)])
    for (i, j) in hull:
        t = (j - (y - 29)) / 22.0
        u = (i - x) / 65.0
        v = t * 0.82
        im.put(i, j, pick(1 - v * 1.05 + (0.08 if u < 0.3 else 0), ['E', 'W', 'S', 'M', 'L'], i, j, 2.6))
    im.outline(hull, 'K')
    # panel seams
    for sx in (x + 17, x + 34, x + 50): im.vline(sx, y - 27, 19, 'E')
    im.hline(x + 6, y - 15, 56, 'E')
    # scrap plating: rust patches, a bolted-on repair plate, hazard tape at the tail
    for (px_, py_, pw, ph, c1) in ((x + 19, y - 26, 14, 8, 'u'), (x + 37, y - 20, 12, 10, 'u'), (x + 6, y - 20, 9, 8, 'T')):
        for j in range(ph):
            for i in range(pw):
                if hull and (px_ + i, py_ + j) in hull:
                    t = (j / float(ph))
                    im.put(px_ + i, py_ + j, 'T' if (j == 0 and c1 == 'u') else c1 if t < 0.7 else 'n')
        for (bx, by) in ((px_ + 1, py_ + 1), (px_ + pw - 2, py_ + 1), (px_ + 1, py_ + ph - 2), (px_ + pw - 2, py_ + ph - 2)):
            if (bx, by) in hull: im.put(bx, by, 'M')
    for k in range(0, 10):
        im.vline(x + 55 + k, y - 15, 7, 'a' if (k // 2) % 2 == 0 else 'K')
    im.hline(x + 55, y - 15, 10, 'K')
    # the canopy: a glass bubble with the cabin light on
    can = ellipse_cells(x + 12, y - 19, 9, 6) & rect_cells(x, y - 30, 40, 11)
    im.fill(can, 'N')
    im.shade(can, ['J', 'B', 'k', 'i'], x + 10, y - 17, 9, 6, sharp=1.1)
    im.hline(x + 5, y - 21, 3, 'z')
    im.fill(ellipse_cells(x + 13, y - 18, 2, 2), 'z' if wrong else 'y')
    im.outline(can, 'K')
    if not wrong: gl.blob(x + 13, y - 18, 11, 'y', 120, 1.6)
    # engines: two nozzle drums on the tail, idling
    for ey in (y - 22, y - 13):
        im.rect(x + 63, ey, 5, 6, 'W'); im.vline(x + 63, ey, 6, 'S'); im.vline(x + 67, ey, 6, 'E'); im.hline(x + 63, ey, 5, 'M'); im.hline(x + 63, ey + 5, 5, 'K')
        flick = 'o' if f % 2 == 0 else 'y'
        if not wrong:
            im.hline(x + 68, ey + 2, 2 if f % 2 == 0 else 1, flick); im.put(x + 68, ey + 3, 'o')
            gl.blob(x + 69, ey + 3, 7, 'o', 90, 1.6)
    # antenna and a running lamp
    im.vline(x + 40, y - 36, 7, 'M'); im.put(x + 40, y - 37, 'S')
    lit = ('r' if f % 2 == 0 else 'a') if not wrong else 'W'
    im.put(x + 40, y - 38, lit)
    if not wrong: gl.blob(x + 40, y - 38, 6, 'r' if f % 2 == 0 else 'o', 100 if f % 2 == 0 else 60, 1.8)
    # gangway: a ramp from the belly to the pad
    im.poly([(x + 20, y - 8), (x + 28, y - 8), (x + 30, y), (x + 14, y)], 'W')
    im.line(x + 20, y - 8, x + 14, y, 'M'); im.hline(x + 14, y, 16, 'E')
    for k in range(3): im.hline(x + 18 - k * 2 + 3, y - 6 + k * 3, 8, 'S')
    # a mooring rope from the nose to a bollard
    im.rect(x - 9, y - 4, 3, 5, 'E'); im.put(x - 9, y - 4, 'M')
    im.line(x + 1, y - 12, x - 8, y - 4, 'Q')

KID_OUT = {'r': ('r', 'u'), 'b': ('b', 'B'), 'a': ('a', 'u'), 'p': ('p', 'P'), 'g': ('g', 'R'), 'V': ('V', 'Z'), 'c': ('c', 'C'), 'y': ('y', 'a'), 'm': ('m', 'P')}
def kid(im, x, y, h, outfit, hair, f, phase=0, pose='run', skin=('s', 'v'), shadow=True):
    """a child, feet at (x, y): a big head, short legs. poses: run (legs and arms swing), cheer (arms up), still."""
    hh = max(4, int(round(h * 0.36)))
    th = max(3, int(round(h * 0.30)))
    lh = max(2, h - hh - th)
    k = (f + phase) % 2
    yb = y + (-1 if (pose == 'run' and k) else 0)
    tw = 3 if h < 12 else 5 if h >= 16 else 4
    tx0 = x - tw // 2
    if shadow: im.dither(ellipse_cells(x + 2, y + 1, h * 0.42, 1.6), None, 'A', 0.7)
    hy = yb - h + hh / 2.0
    head = ellipse_cells(x + 0.5, hy, max(2.0, hh * 0.56), hh / 2.0)
    torso = rect_cells(tx0, yb - lh - th, tw, th)
    arms, hands, legs = set(), set(), set()
    sy = yb - lh - th + 1
    lw = 2 if h >= 17 else 1
    if pose == 'cheer':
        for sgn in (-1, 1):
            ax = (tx0 - 1) if sgn < 0 else (tx0 + tw)
            for t in range(0, 4): arms.add((ax + sgn * (t // 2), sy - t))
            hands.add((ax + sgn * 2, sy - 4))
    elif pose == 'run':
        for sgn in (-1, 1):
            ax = (tx0 - 1) if sgn < 0 else (tx0 + tw)
            sw = (1 if k else -1) * sgn
            for t in range(0, 3): arms.add((ax + (sw if t > 0 else 0), sy + t))
            hands.add((ax + sw, sy + 3))
    else:
        for sgn in (-1, 1):
            ax = (tx0 - 1) if sgn < 0 else (tx0 + tw)
            arms.add((ax, sy)); arms.add((ax, sy + 1)); hands.add((ax, sy + 2))
    for sgn in (-1, 1):
        step = ((1 if k else -1) * sgn if pose == 'run' else 0)
        lx = x + (sgn * 1 if tw % 2 else (0 if sgn > 0 else -1))
        for t in range(lh):
            off = step if t >= lh // 2 else 0
            for w in range(lw): legs.add((lx + off + (w if sgn > 0 else -w), yb - lh + t))
    sil = head | torso | arms | hands | legs
    im.outline(sil, 'K', diag=True)
    base, dark = KID_OUT.get(outfit, (outfit, outfit))
    for (i, j) in legs: im.put(i, j, 'W' if j < yb - 1 else 'n')
    for (i, j) in torso: im.put(i, j, lighten(base) if i == tx0 else base)
    im.hline(tx0, yb - lh - 1, tw, dark)
    for (i, j) in arms: im.put(i, j, base)
    for (i, j) in hands: im.put(i, j, skin[0])
    for (i, j) in head: im.put(i, j, skin[0] if i < x else skin[0])
    top = int(round(hy - hh / 2.0))
    for (i, j) in head:
        if j <= top + 1 or (j <= top + 2 and (i < x - 1 or i > x + 1) and hh >= 5): im.put(i, j, hair)
    for (i, j) in head:
        if i > x + 1 and j > top + 1: im.put(i, j, skin[1])
    if hh >= 5: im.put(x, int(round(hy)) + 1, 'K'); im.put(x + 2, int(round(hy)) + 1, 'K')
    return sil

def flowers(im, f, seed, region, n=30):
    r = Lcg(seed)
    (x0, y0, x1, y1) = region
    cols = ['m', 'y', 'Y', 'p', 'z', 'X', 'w', 'y', 'z']
    for k in range(n):
        x, y = r.rng(x0, x1), r.rng(y0, y1)
        if im.get(x, y) not in ('R', 'U', 'O', 'g', 'A'): continue
        c = r.pick(cols)
        sw = 1 if (f % 2 and k % 3 == 0) else 0
        im.put(x, y + 1, 'O'); im.put(x, y + 2, 'A')
        im.put(x + sw, y, c)
        if r.below(2): im.put(x - 1 + sw, y, lighten(c)); im.put(x + 1 + sw, y, c)
        if r.below(3) == 0: im.put(x + sw, y - 1, c)

def ivy(im, gl, f, wrong=False):
    """strands of ivy climbing the base ring and planter vines hanging from the first ring."""
    r = Lcg(404)
    for x in range(0, 320, 3):
        if r.below(3) == 0: continue
        y0 = int(wall_y(x)) + 8
        ln = r.rng(6, 16)
        px_ = x
        for j in range(ln):
            px_ += r.rng(-1, 1) if j % 2 == 0 else 0
            c = 'O' if j < ln - 2 else 'R'
            im.put(px_, y0 - j, c)
            if j % 3 == 1:
                im.put(px_ - 1, y0 - j, 'R'); im.put(px_ + 1, y0 - j, 'U' if (x + j) % 2 else 'R')
            if j > 5 and r.below(7) == 0: im.put(px_ + 1, y0 - j - 1, ['m', 'y', 'z', 'Y'][r.below(4)])
    for x in range(8, 320, 17):                       # hanging planters on the first ring
        ph = math.degrees(math.acos(max(-1, min(1, (x - CX) / float(RX * math.cos(math.radians(RINGS[0]))))))) if abs(x - CX) < RX * math.cos(math.radians(RINGS[0])) else None
        if ph is None: continue
        px_, py_ = dome_pt(ph, RINGS[0])
        px_, py_ = int(px_), int(py_) + 2
        ln = r.rng(7, 15)
        for j in range(ln):
            im.put(px_ + (1 if j % 4 == 2 else 0), py_ + j, 'O' if j % 3 else 'R')
            if j % 2 == 1: im.put(px_ - 1, py_ + j, 'R'); im.put(px_ + 1, py_ + j, 'U')
        if (x // 17) % 2 == 0: im.put(px_, py_ + ln, ['m', 'y', 'z'][(x // 17) % 3])

def leaf(im, cx, cy, ln, wd, ang, ramp, f=0):
    """a broad leaf lying along `ang` degrees from (cx, cy) (its base): rhombus outline, shaded, with a lighter midrib."""
    a = math.radians(ang); ux, uy = math.cos(a), math.sin(a); vx, vy = -uy, ux
    pts = []
    for t, w in ((0, 0), (0.25, 0.75), (0.55, 1.0), (0.85, 0.55), (1.0, 0)):
        pts.append((cx + ux * ln * t + vx * wd * w * 0.5, cy + uy * ln * t + vy * wd * w * 0.5))
    for t, w in ((0.85, 0.55), (0.55, 1.0), (0.25, 0.75)):
        pts.append((cx + ux * ln * t - vx * wd * w * 0.5, cy + uy * ln * t - vy * wd * w * 0.5))
    cells = poly_cells(pts)
    mx, my = cx + ux * ln * 0.5, cy + uy * ln * 0.5
    im.shade(cells, ramp, mx - 2, my - 3, ln * 0.55, wd * 0.9, light=(-0.5, -0.7), sharp=1.8)
    for k in range(int(ln)):
        im.put(int(cx + ux * k), int(cy + uy * k), ramp[-2])
    return cells

def foreground(im, f):
    # big dark leaves frame the bottom corners (they are close to us, so they are dark and out of the light)
    D = ['A', 'A', 'O', 'R']
    for (cx, cy, ln, wd, ang) in ((-4, 182, 62, 24, -62), (8, 186, 58, 22, -30), (-6, 190, 50, 20, -88), (326, 182, 64, 24, -118), (312, 188, 56, 22, -150), (324, 190, 50, 20, -92)):
        leaf(im, cx, cy, ln, wd, ang, D)

def kite(im, gl, f, x, y, hx, hy, wrong=False):
    sway = [0, 1, 0, -1][f % 4]
    d = ellipse_cells(0, 0, 1, 1)
    top = [(x, y - 7), (x + 5, y), (x, y + 6), (x - 5, y)]
    cells = poly_cells(top)
    for (i, j) in cells:
        im.put(i, j, 'r' if (i < x and j < y) or (i >= x and j >= y) else 'y')
    im.outline(cells, 'K')
    im.vline(x, y - 6, 12, 'H'); im.hline(x - 4, y, 9, 'H')
    # tail
    for k in range(1, 12):
        tx = x + int(math.sin((k + f * 1.5) * 0.9) * 2.0) + sway
        im.put(tx, y + 6 + k, 'm' if k % 3 == 0 else 'L')
    # string to the hand: a gentle curve
    n = 60
    prev = (x, y + 7)
    for t in range(1, n + 1):
        u = t / float(n)
        px_ = x + (hx - x) * u + math.sin(u * 3.14159) * (3 + sway)
        py_ = y + 7 + (hy - y - 7) * u
        im.line(prev[0], prev[1], px_, py_, 'M'); prev = (px_, py_)
    gl.blob(x, y, 8, 'y', 50, 1.6)

def butterfly(im, x, y, f, c1, c2):
    if f % 2 == 0:
        im.put(x - 1, y - 1, c1); im.put(x + 1, y - 1, c1); im.put(x, y, 'K'); im.put(x - 1, y, c2); im.put(x + 1, y, c2)
    else:
        im.put(x - 1, y, c1); im.put(x + 1, y, c1); im.put(x, y, 'K'); im.put(x - 1, y + 1, c2); im.put(x + 1, y + 1, c2)

def rays(im, gl, f, wrong=False):
    sx, sy = 52, 19
    spec = ((28, 4.0, 0.9), (38, 2.4, 0.7), (47, 5.0, 0.8), (58, 2.8, 0.65), (69, 4.2, 0.7), (18, 2.2, 0.55))
    for y in range(86, 180):
        for x in range(320):
            c = im.get(x, y)
            if c in ('K',): continue
            ang = math.degrees(math.atan2(y - sy, x - sx))
            best = 0.0
            for (a, w, it) in spec:
                d = abs(ang - a)
                if d < w: best = max(best, (1 - d / w) * it)
            dist = math.hypot(x - sx, y - sy)
            best *= max(0.35, 1.1 - dist / 320.0)
            if best > 0.05 and best * 0.9 > bay(x, y):
                im.put(x, y, lighten(c, 1 if best < 0.55 else 2))
    # drifting motes in the shafts: each lives 3 of the 4 frames and floats a little
    r = Lcg(1212)
    for k in range(60):
        ang = math.radians(r.rng(16, 70)); dist = r.rng(90, 230)
        x = sx + math.cos(ang) * dist; y = sy + math.sin(ang) * dist
        ph = r.below(4); t = (f + ph) % 4
        if t == 3 or y < 90 or y > 176: continue
        mx, my = int(x + t * 1), int(y + t * 0.5 + (1 if k % 2 else 0) * (t % 2))
        im.put(mx, my, 'y' if k % 3 else 'H')
        gl.blob(mx, my, 3, 'y', 70, 1.2)

def vignette(im, wrong=False):
    for y in range(84, 180):
        for x in range(320):
            c = im.get(x, y)
            v = ((x - 170) / 205.0) ** 2 + ((y - 124) / 82.0) ** 2
            if v < 0.55: continue
            amt = (v - 0.55) * 1.15
            if amt * 0.85 > bay(x, y): c = darken(c, 1 if amt < 1.2 else 2); im.put(x, y, c)

def distant_village(im, gl, f):
    for (x, y, c) in ((12, 99, 'Z'), (30, 100, 'd'), (63, 97, 'Z'), (80, 99, 'd'), (118, 101, 'Z'), (152, 99, 'd'), (214, 100, 'Z'), (252, 99, 'd'), (276, 101, 'Z'), (302, 99, 'd')):
        im.rect(x, y, 5, 3, 'J'); im.hline(x - 1, y - 1, 7, c); im.put(x + 1, y - 2, c); im.put(x + 2, y - 2, c); im.put(x + 3, y - 2, c)
        im.put(x + 1, y + 1, 'y' if (x + f) % 3 else 'a')
        gl.blob(x + 1, y + 1, 4, 'y', 55, 1.5)

def hollow(im, gl, f, x, y, L, th, ang, seed, lights=11):
    """a Hollow hull seen through the glass: a long, wrong silhouette (spindle, too many fins, a ring), a pale rim and a row of lights that blink all together."""
    r = Lcg(seed)
    a = math.radians(ang); ux, uy = math.cos(a), math.sin(a); vx, vy = -uy, ux
    pts_top, pts_bot = [], []
    n = 14
    for k in range(n + 1):
        t = k / float(n)
        w = th * (0.25 + 0.75 * math.sin(math.pi * min(1, t * 1.05))) * (1 + (0.35 if k % 3 == 1 else 0))
        pts_top.append((x + ux * L * t + vx * w, y + uy * L * t + vy * w))
        pts_bot.append((x + ux * L * t - vx * w * 0.8, y + uy * L * t - vy * w * 0.8))
    body = poly_cells(pts_top + pts_bot[::-1])
    im.fill(body, 'K')
    for k in range(2, n - 1, 2):                                        # fins that are too many and too regular
        t = k / float(n)
        bx, by = x + ux * L * t, y + uy * L * t
        fin = [(bx + vx * th * 0.7, by + vy * th * 0.7), (bx + vx * th * 1.9 + ux * 3, by + vy * th * 1.9 + uy * 3), (bx + vx * th * 0.7 + ux * 5, by + vy * th * 0.7 + uy * 5)]
        im.fill(poly_cells(fin), 'K'); body |= poly_cells(fin)
    rr = int(th * 1.6)
    ring = ring_cells(x + ux * L * 0.18, y + uy * L * 0.18, rr * 0.55, rr, 1)
    im.fill(ring, 'K')
    # a pale rim on the side facing the sun (top-left) and the eleven lights
    for (i, j) in body:
        if (i + 1, j + 1) not in body and (i - 1, j - 1) in body: pass
        if (i - 1, j - 1) not in body or (i, j - 1) not in body: im.put(i, j, 'x' if (i + j) % 3 else 'j')
    for k in range(lights):
        t = 0.2 + 0.7 * k / float(lights - 1)
        lx, ly = int(x + ux * L * t), int(y + uy * L * t + 1)
        on = f % 2 == 0
        im.put(lx, ly, 'z' if on else 'x')
        if on: gl.blob(lx, ly, 4, 'i', 90, 1.5)
    gl.blob(x + ux * L * 0.5, y + uy * L * 0.5, L * 0.5, 'C', 10, 1.0, squash=0.18)

def render(f=0, wrong=False):
    im, gl = Ill(), Glow()
    sky(im, wrong); stars(im, gl, f, wrong); sun(im, gl, f, wrong); gate_ring(im, gl, f, wrong)
    if wrong:                                                            # the Hollow, outside the glass: big, slow, and not drifting like anything real
        hollow(im, gl, f, 138, 52, 150, 5, -7, 31)
        hollow(im, gl, f, 214, 22, 96, 4, 4, 32, lights=11)
        hollow(im, gl, f, 12, 70, 70, 3, -14, 33, lights=7)
    dome(im, gl, f, wrong)
    for x in range(320):
        for y in range(int(wall_y(x)) + 9, 180): im.put(x, y, 'O')
    lawn(im, wrong)
    distant_village(im, gl, f)
    ivy(im, gl, f, wrong)
    cells, cy = river(im, 0 if wrong else f, wrong)
    cottage(im, gl, 96, 112, 16, 9, seed=3, f=f, wrong=wrong)
    cottage(im, gl, 126, 113, 12, 8, wall='Y', seed=4, f=f, wrong=wrong)
    cottage(im, gl, 232, 110, 14, 8, wall='Y', seed=5, f=f, wrong=wrong)
    tree(im, 210, 112, 22, 23)
    tree(im, 150, 111, 18, 24)
    mast(im, gl, 178, 112, 44, f, wrong)
    bridge(im, 196, 126)
    pcells, xc = path(im, f)
    tree(im, 56, 140, 58, 21)
    tree(im, 296, 140, 40, 22)
    ship(im, gl, 206, 150, f, wrong)
    lamps(im, gl, f, [[(178, 66), (140, 84), (96, 96)], [(178, 66), (206, 86), (236, 98)], [(178, 66), (118, 86), (70, 94)], [(178, 66), (260, 82), (292, 98)]], wrong)
    flowers(im, 0 if wrong else f, 31, (0, 152, 319, 179), 60)
    flowers(im, 0 if wrong else f, 32, (0, 134, 319, 150), 28)
    if not wrong:
        kid(im, 118, 176, 19, 'r', 'n', f, 0, 'cheer')
        kid(im, 144, 166, 15, 'b', 'q', f, 1, 'run')
        kid(im, 168, 148, 11, 'p', 'Y', f, 0, 'run')
        kid(im, 258 - 14, 154, 11, 'a', 'n', f, 1, 'cheer')
        kid(im, 268 - 14, 156, 9, 'g', 'u', f, 0, 'still')
        kite(im, gl, f, 104, 70, 113, 156)
        butterfly(im, 140 + (f % 2), 148 - (f // 2), f, 'y', 'a'); butterfly(im, 236 - (f % 2), 138, f, 'm', 'P'); butterfly(im, 92 + f, 142, f, 'z', 'i')
        rays(im, gl, f, wrong)
    else:                                                                # five children in a row, facing us, all the same, all still, shadows toward the light
        for k, x in enumerate((104, 122, 140, 158, 176)):
            kid(im, x, 172, 15, 'b', 'n', 0, 0, 'still', shadow=False)
            im.dither(ellipse_cells(x - 4, 170, 6, 1.4), None, 'A', 0.7)
    foreground(im, f)
    vignette(im, wrong)
    for x in range(0, 320, 2): gl.blob(x, wall_y(x) - 1, 9, 'a' if not wrong else 'i', 26, 1.2)
    return im, gl

def render_wrong(f=0): return render(f, True)
