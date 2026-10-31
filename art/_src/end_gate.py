"""wayout_concord / wayout_clans / wayout_lumen: a restarted Dead Gate seen face-on, three ways. Concord: a lattice of calm light, ringed by neat rows of ships.
Clans: wrapped in scrap scaffolding, ships pouring out in a burst. Lumen: a crystal ring opening onto somewhere that cannot be."""
import math
from ill import *
from scene_common import *
from ships_td import *

GX, GY = 160, 90

def polar(cx, cy, r, deg): a = math.radians(deg); return cx + r * math.cos(a), cy + r * math.sin(a)

def torus(im, cx, cy, rin, rout, ramp, light=(-0.55, -0.62), sharp=1.8):
    lx, ly = light; lz = math.sqrt(1 - lx * lx - ly * ly)
    cells = ring_cells(cx, cy, rout, rout, rout - rin)
    n = len(ramp)
    for (x, y) in cells:
        dx, dy = x + 0.5 - cx, y + 0.5 - cy
        r = math.hypot(dx, dy)
        s = max(-1.0, min(1.0, ((r - rin) / float(rout - rin) - 0.5) * 2))
        ex, ey = dx / r, dy / r
        nz = math.sqrt(max(0.0, 1 - s * s))
        v = max(0.0, min(1.0, (s * (ex * lx + ey * ly) + nz * lz) * 0.62 + 0.38))
        f = v * (n - 1); i0 = int(math.floor(f)); fr = max(0.0, min(1.0, (f - i0 - 0.5) * sharp + 0.5))
        im.put(x, y, ramp[min(n - 1, i0 + (1 if fr > bay(x, y) else 0))])
    return cells

def seams(im, cx, cy, rin, rout, n, col='K', hi='S', off=0.0):
    for k in range(n):
        a = k * 360.0 / n + off
        for rr in range(int(rin) + 1, int(rout)):
            x, y = polar(cx, cy, rr, a)
            im.put(int(round(x)), int(round(y)), col)
        for rr in range(int(rin) + 2, int(rout) - 1):
            x, y = polar(cx, cy, rr, a + 360.0 / n * 0.04 * 20 / max(rr / 10.0, 1))
            if hi: im.put(int(round(x)), int(round(y)), hi)

def pylon(im, cx, cy, rout, deg, ln, wd, ramp, tip=None, tipcol='y', gl=None, f=0):
    a = math.radians(deg); ux, uy = math.cos(a), math.sin(a); vx, vy = -uy, ux
    r0 = rout - 3
    pts = [(cx + ux * r0 + vx * wd / 2, cy + uy * r0 + vy * wd / 2), (cx + ux * (rout + ln) + vx * wd / 2.6, cy + uy * (rout + ln) + vy * wd / 2.6),
           (cx + ux * (rout + ln) - vx * wd / 2.6, cy + uy * (rout + ln) - vy * wd / 2.6), (cx + ux * r0 - vx * wd / 2, cy + uy * r0 - vy * wd / 2)]
    cs = poly_cells(pts)
    mx, my = cx + ux * (rout + ln / 2), cy + uy * (rout + ln / 2)
    im.shade(cs, ramp, mx, my, ln * 0.7, wd * 0.8, sharp=1.8)
    im.outline(cs, 'K')
    if tip:
        tx, ty = cx + ux * (rout + ln + 1), cy + uy * (rout + ln + 1)
        im.put(int(round(tx)), int(round(ty)), tipcol)
        if gl is not None: gl.blob(tx, ty, 6, tipcol, 120, 1.7)
    return cs

# ------------------------------------------------------------------ Concord
def concord_field(im, gl, f, R):
    # the Lattice, restarted: a calm bright field crossed by a fine net with bright nodes, and rings of light that pulse outward (4-frame loop)
    S = 10
    for y in range(GY - R, GY + R + 1):
        for x in range(GX - R, GX + R + 1):
            dx, dy = x + 0.5 - GX, y + 0.5 - GY
            d = math.hypot(dx, dy) / R
            if d > 1: continue
            v = 1.0 - 0.62 * d ** 1.5
            wave = abs(((d * 3 - f * 0.25) % 1.0) - 0.5)
            if wave < 0.07: v += 0.10
            a1, a2 = int(round(dx + dy)) % S == 0, int(round(dx - dy)) % S == 0
            c = pick(v, ['J', 'j', 'b', 'k', 'i', 'z', 'H'], x, y, 1.9)
            if a1 != a2: c = darken(c) if d > 0.25 else c
            if a1 and a2: c = lighten(c) if c != 'H' else c
            im.put(x, y, c)
    im.disc(GX, GY, 4, 'H')
    gl.blob(GX, GY, R + 12, 'b', 100, 1.1)
    gl.blob(GX, GY, R * 0.55, 'z', 80, 1.6)

def concord_ring(im, gl, f, rin, rout):
    cells = torus(im, GX, GY, rin, rout, ['E', 'W', 'S', 'M', 'L', 'H'])
    im.outline(cells, 'K'); im.outline(ellipse_cells(GX, GY, rin, rin), 'K')
    seams(im, GX, GY, rin, rout, 24, 'E', None)
    # the blue inlay along the ring's centre, and amber registry marks
    mid = (rin + rout) / 2.0
    for a in range(0, 360, 1):
        x, y = polar(GX, GY, mid, a)
        im.put(int(round(x)), int(round(y)), 'b' if a % 15 else 'j')
        x, y = polar(GX, GY, mid + 1, a)
        if a % 15 != 0: im.put(int(round(x)), int(round(y)), 'j')
    # a thin outer registry ring with tick marks (one long tick per pylon)
    for a in range(360):
        x, y = polar(GX, GY, rout + 3, a)
        im.put(int(round(x)), int(round(y)), 'M' if a % 5 else 'L'); x, y = polar(GX, GY, rout + 4, a); im.put(int(round(x)), int(round(y)), 'E')
        if a % 15 == 0:
            for rr in (rout + 5, rout + 6): x, y = polar(GX, GY, rr, a); im.put(int(round(x)), int(round(y)), 'M')
    for k in range(12):                                             # pylons with amber lamps
        pylon(im, GX, GY, rout + 4, k * 30 + 15, 6, 8, ['E', 'W', 'S', 'M'], True, 'y' if (k + f) % 2 == 0 else 'a', gl, f)
    # running lights on the inner edge: a lit one walks round (36 lamps)
    for k in range(36):
        x, y = polar(GX, GY, rin + 1.5, k * 10)
        on = (k - f * 3) % 12 == 0
        im.put(int(round(x)), int(round(y)), 'H' if on else 'k')
        if on: gl.blob(x, y, 5, 'z', 120, 1.7)

def ship_rows(im, gl, f, rows):
    for ri, (rx, ry, n, L, off) in enumerate(rows):
        for k in range(n):
            a = off + k * 360.0 / n
            x, y = GX + rx * math.cos(math.radians(a)), GY + ry * math.sin(math.radians(a))
            if x < -L or x > 320 + L or y < -L or y > 180 + L: continue
            ang = math.degrees(math.atan2(GY - y, GX - x))
            concord(im, gl, int(round(x)), int(round(y)), ang, L, f, ph=(k + ri) % 2)

def concord_scene(f=0):
    im, gl = Ill(320, 180, 'N'), Glow()
    space_gradient(im, 0, 180, ('N', 'N', 'I'), 0, 1)
    im.rgrad(GX, GY, 130, ['J', 'I', 'N', '.'], sharp=1.0, squash=0.75)
    starfield(im, gl, f, 3, 150)
    # formation lines: thin dotted rings between the rows, like a chart
    for rx, ry in ((89, 74), (117, 88)):
        for a in range(0, 360, 2):
            x, y = GX + rx * math.cos(math.radians(a)), GY + ry * math.sin(math.radians(a))
            if 0 <= x < 320 and 0 <= y < 180 and (a // 2) % 2 == 0: im.put(int(x), int(y), 'J')
    concord_field(im, gl, f, 38)
    concord_ring(im, gl, f, 38, 52)
    ship_rows(im, gl, f, [(76, 66, 16, 18, 11.25), (102, 82, 22, 14, 0), (132, 94, 30, 12, 6)])
    motes(im, gl, f, 8, 14, (40, 20, 280, 160), ('z', 'k'), 0, 1)
    return im, gl

# ------------------------------------------------------------------ Clans
def clans_field(im, gl, f, R):
    ph = f * math.pi / 2
    for y in range(GY - R, GY + R + 1):
        for x in range(GX - R, GX + R + 1):
            dx, dy = x + 0.5 - GX, y + 0.5 - GY
            d = math.hypot(dx, dy) / R
            if d > 1: continue
            th = math.atan2(dy, dx)
            v = 1.06 - d ** 1.25 * 0.85 + 0.17 * d ** 1.6 * math.sin(4 * th - 8 * d + ph) + 0.06 * d ** 2 * math.sin(7 * th + 5 * d - ph)
            im.put(x, y, pick(min(v, 0.9), ['d', 'r', 'o', 'a', 'y', 'Y', 'H'], x, y, 1.7))
    im.disc(GX, GY, 7, 'H'); im.fill(ring_cells(GX, GY, 9, 9, 2), 'Y')
    gl.blob(GX, GY, R + 16, 'o', 120, 1.1)
    gl.blob(GX, GY, R * 0.6, 'y', 110, 1.5)

def girder(im, x0, y0, x1, y1, c1='M', c2='L', c3='W'):
    """a lattice truss: two chords 3 px apart (lit on the top-left one) with diagonal ties between them."""
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    ux, uy = (x1 - x0) / float(n), (y1 - y0) / float(n)
    vx, vy = -uy, ux
    for (x, y) in line_cells(x0, y0, x1, y1):
        im.put(x, y, c2)
        im.put(int(round(x + vx * 3)), int(round(y + vy * 3)), c3)
    for k in range(0, n, 4):
        a = (x0 + ux * k, y0 + uy * k)
        b = (x0 + ux * (k + 2) + vx * 3, y0 + uy * (k + 2) + vy * 3)
        im.line(a[0], a[1], b[0], b[1], c1)

def clans_ring(im, gl, f, rin, rout):
    cells = torus(im, GX, GY, rin, rout, ['n', 'n', 'q', 'u', 'T'])
    im.outline(cells, 'K'); im.outline(ellipse_cells(GX, GY, rin, rin), 'K')
    seams(im, GX, GY, rin, rout, 18, 'n', None, 5)
    r = Lcg(66)
    # plates that don't match: steel and navy patches bolted over the rust, with rivets
    for k in range(9):
        a = r.below(360); w = r.rng(8, 14)
        for rr in range(int(rin) + 2, int(rout) - 1):
            for da in range(w):
                x, y = polar(GX, GY, rr, a + da * 360.0 / (2 * math.pi * rr) * 1.0)
                c = 'S' if k % 3 == 0 else 'W' if k % 3 == 1 else 'J'
                if (rr + da) % 5 == 0: c = lighten(c)
                im.put(int(round(x)), int(round(y)), c)
        for (rr, da) in ((rin + 2, 1), (rout - 3, 1), (rin + 2, w - 2), (rout - 3, w - 2)):
            x, y = polar(GX, GY, rr, a + da * 360.0 / (2 * math.pi * rr)); im.put(int(round(x)), int(round(y)), 'L')
    # hazard tape wrapped round the inner lip
    for a in range(0, 360, 1):
        x, y = polar(GX, GY, rin + 2, a)
        im.put(int(round(x)), int(round(y)), 'a' if (a // 4) % 2 == 0 else 'K')
    # scaffolding: an outer ring of poles, cross-braces back to the gate, planks and tied-off cables
    so = rout + 14
    for k in range(18):
        a = k * 20 + 5
        x0, y0 = polar(GX, GY, rout - 1, a); x1, y1 = polar(GX, GY, so, a + 10)
        girder(im, int(x0), int(y0), int(x1), int(y1))
        x2, y2 = polar(GX, GY, so, a - 10)
        girder(im, int(x0), int(y0), int(x2), int(y2), 'S', 'M', 'E')
    for k in range(6):                                           # canvas tarps lashed between the braces
        a = k * 60 + 33
        pts = [polar(GX, GY, rout + 1, a - 8), polar(GX, GY, so - 1, a - 6), polar(GX, GY, so - 1, a + 6), polar(GX, GY, rout + 1, a + 8)]
        tc = poly_cells(pts)
        for (x, y) in tc: im.put(x, y, 'Q' if (x + 2 * y) % 7 else 'q')
        for (x, y) in tc:
            if (x - 1, y - 1) not in tc: im.put(x, y, 'Y')
    for a in range(0, 360, 2):
        x, y = polar(GX, GY, so, a)
        im.put(int(round(x)), int(round(y)), 'M' if a % 30 else 'L'); x, y = polar(GX, GY, so + 1, a); im.put(int(round(x)), int(round(y)), 'E')
    for k in range(12):                                          # poles
        x0, y0 = polar(GX, GY, so - 2, k * 30 + 22); x1, y1 = polar(GX, GY, so + 11 + (k % 3) * 4, k * 30 + 22)
        for (x, y) in line_cells(x0, y0, x1, y1): im.put(x, y, 'Q'); im.put(x + 1, y, 'q')
        im.put(int(round(x1)), int(round(y1)), 'M')
    for k in range(6):                                           # planks
        a = k * 60 + 40
        for da in range(-8, 9, 1):
            x, y = polar(GX, GY, so + 3, a + da)
            im.put(int(round(x)), int(round(y)), 'Q' if da % 4 else 'n')
    # pennants on three poles: rags that wave 4 ways
    for k, (a, c) in enumerate(((52, 'r'), (172, 'a'), (292, 'r'))):
        x0, y0 = polar(GX, GY, so + 15, a)
        x0, y0 = int(x0), int(y0)
        for i in range(10):
            wv = int(round(math.sin(i * 0.8 + f * math.pi / 2 + k) * 1.5))
            im.put(x0 + i * (1 if a < 180 else -1) // 1, y0 + wv - i // 3, c)
            im.put(x0 + i * (1 if a < 180 else -1) // 1, y0 + wv - i // 3 + 1, c if i < 7 else '.')
    # hanging lamps on cable swags
    for k in range(8):
        a0 = k * 45 + 10
        pts = []
        for t in range(0, 21):
            a = a0 + t * 1.2
            x, y = polar(GX, GY, so + 4 + math.sin(t / 20.0 * math.pi) * 5, a)
            pts.append((x, y))
        for (p, q) in zip(pts, pts[1:]): im.line(p[0], p[1], q[0], q[1], 'W')
        for t in (5, 10, 15):
            on = (t // 5 + f + k) % 2 == 0
            x, y = pts[t]; im.put(int(round(x)), int(round(y)) + 1, 'y' if on else 'a')
            gl.blob(x, y + 1, 6 if on else 4, 'y', 110 if on else 60, 1.8)
    # welders at work: a flash, and sparks that fly different ways each frame
    for k, a in enumerate((20, 140, 250)):
        x, y = polar(GX, GY, rout + 2, a)
        im.put(int(x), int(y), 'H'); 
        rr = Lcg(a * 7 + f * 31)
        for s in range(6):
            sx, sy = int(x + rr.rng(-5, 5)), int(y + rr.rng(-5, 5)); im.put(sx, sy, 'y' if s % 2 else 'o')
        gl.blob(x, y, 11, 'y', 160, 1.6)
    # a crane: an A-frame on the scaffold ring with a boom that reaches over the gate and a lamp on the hook
    bx, by = polar(GX, GY, so + 2, -52)
    bx, by = int(bx), int(by)
    ax, ay = bx + 14, by - 40
    girder(im, bx - 7, by + 4, ax, ay); girder(im, bx + 9, by + 4, ax, ay)
    girder(im, ax, ay, GX - 14, GY - 62, 'S', 'M', 'E')
    im.rect(ax - 2, ay - 2, 5, 4, 'W'); im.hline(ax - 2, ay - 2, 5, 'L')
    hx, hy = GX - 14, GY - 62 + 14 + (1 if f % 2 else 0)
    im.vline(GX - 14, GY - 62, 14, 'M'); im.rect(hx - 2, hy, 5, 3, 'a'); im.hline(hx - 2, hy, 5, 'y')
    gl.blob(hx, hy + 1, 10, 'y', 140, 1.6)
    # pylons (the gate's own), lit amber
    for k in range(6):
        pylon(im, GX, GY, rout, k * 60 + 30, 5, 8, ['n', 'q', 'u', 'T'], True, 'y' if (k + f) % 2 == 0 else 'o', gl, f)

def clans_ships(im, gl, f):
    r = Lcg(2024)
    outs = []
    k = 0
    for i in range(120):
        a = r.below(360)
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        tx = (320 - GX) / ca if ca > 1e-3 else (GX / -ca if ca < -1e-3 else 9e9)
        ty = (180 - GY) / sa if sa > 1e-3 else (GY / -sa if sa < -1e-3 else 9e9)
        dmax = min(tx, ty)
        if dmax < 92: continue
        dist = 72 + max(4, dmax - 80) * (0.04 + 0.96 * (r.f() ** 1.3))
        if any(abs(((a - b_) + 180) % 360 - 180) < 7 and abs(dist - d_) < 40 for (d_, b_, _) in outs): continue
        outs.append((dist, a, k)); k += 1
        if k >= 34: break
    outs.sort()
    for (dist, a, k) in outs[::-1]:
        L = int(9 + (dist - 64) * 0.13)
        x, y = polar(GX, GY, dist, a)
        for t in range(int(L * 1.8)):
            sx, sy = polar(GX, GY, dist - L * 0.55 - t, a)
            if t % 2 == 0 or t < L * 0.5: im.put(int(round(sx)), int(round(sy)), 'a' if t < L else 'u')
        scrap(im, gl, int(round(x)), int(round(y)), a, L, f, seed=k + 1, ph=k % 2)

def clans_scene(f=0):
    im, gl = Ill(320, 180, 'N'), Glow()
    space_gradient(im, 0, 180, ('N', 'N', 'I'), 0, 1)
    nebula(im, 5, 160, 90, 190, 100, ['.', 'I', 'd', 'u'], thr=0.34, gain=1.8, scale=(50, 40))
    starfield(im, gl, f, 4, 200)
    clans_field(im, gl, f, 42)
    clans_ring(im, gl, f, 42, 58)
    clans_ships(im, gl, f)
    motes(im, gl, f, 15, 24, (20, 10, 300, 170), ('y', 'o', 'Y'), 1, -1, 'o', 40)
    return im, gl

# ------------------------------------------------------------------ Lumen
def lumen_field(im, gl, f, R):
    """somewhere impossible: a dusk sky that is brighter overhead's opposite, a floor hanging from the top of the world and another standing at the bottom, each
    with spires pointing at the other, a white sun and a hollow magenta one, drifting shards and a ribbon of light that goes out of one floor and into the other."""
    ph = f * math.pi / 2
    top_edge = lambda dx: -0.56 + 0.06 * math.sin(dx * 5 + 1.0) + 0.03 * math.sin(dx * 13)
    bot_edge = lambda dx: 0.58 + 0.05 * math.sin(dx * 4 + 2.0) + 0.03 * math.sin(dx * 11 + 1)
    for y in range(GY - R, GY + R + 1):
        for x in range(GX - R, GX + R + 1):
            dx, dy = (x + 0.5 - GX) / float(R), (y + 0.5 - GY) / float(R)
            if math.hypot(dx, dy) > 1: continue
            if dy < top_edge(dx):
                c = 'N' if (x * 3 + y) % 7 else 'I'
                if dy > top_edge(dx) - 0.07: c = 'J'
                im.put(x, y, c)
            elif dy > bot_edge(dx):
                c = 'N' if (x + y * 3) % 7 else 'I'
                if dy < bot_edge(dx) + 0.06: c = 'J'
                im.put(x, y, c)
            else:
                v = (dy - top_edge(dx)) / (bot_edge(dx) - top_edge(dx))
                v = 0.04 + 0.92 * (v ** 0.9) + 0.03 * math.sin(dx * 9 + ph)
                im.put(x, y, pick(v, ['Z', 'V', 'P', 'm', 'X', 'i', 'z'], x, y, 1.6))
    # glowing lips where the floors meet the sky
    for x in range(GX - R, GX + R + 1):
        dx = (x + 0.5 - GX) / float(R)
        for (e, c) in ((top_edge(dx), 'c'), (bot_edge(dx), 'c')):
            y = int(round(GY + e * R))
            if math.hypot(x + 0.5 - GX, y - GY) < R - 1: im.put(x, y, c)
    # spires standing on the lower floor and hanging from the upper one, pointing at each other
    for k in range(-5, 6):
        for sg in (1, -1):
            x = GX + k * 8 + (2 if sg > 0 else -2) + int(2 * math.sin(k * 2.1 + sg))
            dx = (x - GX) / float(R)
            h = 6 + abs((k * 5 + sg * 3) % 9)
            base = int(round(GY + (bot_edge(dx) if sg > 0 else top_edge(dx)) * R))
            for j in range(h):
                w = max(0, (h - j) // 3)
                for i in range(-w, w + 1):
                    xx, yy = x + i, base - sg * j
                    if math.hypot(xx - GX, yy - GY) < R - 1: im.put(xx, yy, 'j' if i < 0 else 'I' if i > 0 else 'J')
            tx, ty = x, base - sg * h
            if math.hypot(tx - GX, ty - GY) < R - 1: im.put(tx, ty, 'z'); im.put(tx, ty + sg, 'c')
    # the white sun, and beside it a hollow magenta one
    sx, sy = GX - 14, GY - 1
    for (x, y) in ellipse_cells(sx, sy, 7, 7): im.put(x, y, 'H')
    for (x, y) in ring_cells(sx, sy, 11, 11, 2) - ellipse_cells(sx, sy, 7, 7): im.put(x, y, 'z' if (x + y) % 2 else 'i')
    for (x, y) in ring_cells(GX + 17, GY - 8, 7, 7, 2):
        if math.hypot(x - GX, y - GY) < R - 1: im.put(x, y, 'm')
    # the ribbon: out of the floor, a loop in the sky, into the ceiling
    for t in range(0, 140):
        u = t / 139.0
        y = GY + R * 0.92 - u * R * 1.84
        x = GX + math.sin(u * math.pi * 2.6 + 0.5) * R * 0.5 * (1 - 0.35 * abs(u - 0.5))
        if math.hypot(x - GX, y - GY) < R - 1:
            c = 'H' if (t + f * 9) % 16 < 4 else 'z'
            im.put(int(round(x)), int(round(y)), c); im.put(int(round(x)) + 1, int(round(y)), 'c')
    # little crystal islands adrift in the sky
    for (ix, iy, sz) in ((-26, -14, 3), (22, 14, 2), (-6, 18, 2), (30, -22, 2)):
        iy2 = iy + (1 if (f + ix) % 2 else 0)
        for (x, y) in poly_cells([(GX + ix - sz * 2, GY + iy2), (GX + ix + sz * 2, GY + iy2), (GX + ix, GY + iy2 + sz * 2)]): im.put(x, y, 'J')
        im.hline(GX + ix - sz * 2, GY + iy2, sz * 4, 'c')
        im.put(GX + ix, GY + iy2 - 1, 'z'); im.put(GX + ix, GY + iy2 - 2, 'c')
    gl.blob(GX, GY, R + 12, 'c', 90, 1.1)
    gl.blob(sx, sy, 24, 'z', 130, 1.6)
    gl.blob(GX + 17, GY - 8, 16, 'm', 100, 1.6)

def facet_ring(im, gl, f, rin, rout):
    cells = torus(im, GX, GY, rin, rout, ['N', 'I', 'J', 'j', 'C'], sharp=2.2)
    im.outline(cells, 'N'); im.outline(ellipse_cells(GX, GY, rin, rin), 'N')
    # crystal facets: radial triangles with cyan edges
    n = 16
    for k in range(n):
        a0, a1 = k * 360.0 / n, (k + 1) * 360.0 / n
        am = (a0 + a1) / 2
        for (aa, c) in ((a0, 'c'), ):
            for rr in range(int(rin) + 1, int(rout)):
                x, y = polar(GX, GY, rr, aa)
                im.put(int(round(x)), int(round(y)), 'c' if (rr + k) % 3 else 'z')
        # a diamond highlight in the middle of each facet
        x, y = polar(GX, GY, (rin + rout) / 2.0, am)
        xi, yi = int(round(x)), int(round(y))
        im.put(xi, yi, 'z')
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)): im.put(xi + dx, yi + dy, 'C')
    # outer and inner edge lines in cyan, with a shimmer that slides round (a lit span of ring per frame)
    for a in range(360):
        for (rr, c) in ((rout - 1, 'C'), (rin + 1, 'C')):
            x, y = polar(GX, GY, rr, a)
            lit_ = ((a - f * 22) % 90) < 14
            im.put(int(round(x)), int(round(y)), ('H' if lit_ and rr == rout - 1 else 'z' if lit_ else c))
    # crystal spikes growing off the ring
    for k in range(8):
        a = k * 45 + 22
        h = 10 + (k * 7) % 9
        pylon(im, GX, GY, rout, a, h, 8, ['I', 'J', 'j', 'C', 'i'], True, 'z', gl, f)
        pylon(im, GX, GY, rout, a + 14, h // 2, 5, ['N', 'I', 'J', 'j'], True, 'c', gl, f)
    gl.blob(GX, GY, rout + 14, 'c', 70, 1.2)
    for k in range(16):
        x, y = polar(GX, GY, (rin + rout) / 2.0, k * 22.5 + 11)
        gl.blob(x, y, 7, 'c' if (k + f) % 2 else 'm', 80, 1.8)

def shards(im, gl, f):
    r = Lcg(77)
    for k in range(26):
        a = r.below(360); d0 = r.rng(64, 150); sp = r.rng(2, 4)
        ph = r.below(4); t = (f + ph) % 4
        if t == 3: continue
        x, y = polar(GX, GY, d0 + t * sp, a)
        x, y = int(round(x)), int(round(y))
        if not (0 <= x < 320 and 0 <= y < 180): continue
        sz = 1 + (k % 3)
        c1, c2 = (('c', 'z') if k % 3 else ('m', 'X'))
        for j in range(-sz, sz + 1):
            for i in range(-(sz - abs(j)), sz - abs(j) + 1): im.put(x + i, y + j, c1)
        im.put(x, y, c2); im.put(x - 1, y - 1, 'H') if sz > 1 else None
        gl.blob(x, y, 5 + sz * 2, 'c' if k % 3 else 'm', 80, 1.7)

def rays(im, f):
    # prism beams: thin dithered rays out of the gate, fading with distance
    for (a, c, w) in ((8, 'c', 3), (62, 'm', 3), (118, 'c', 4), (190, 'm', 3), (244, 'c', 3), (298, 'm', 4), (340, 'c', 2)):
        for y in range(180):
            for x in range(320):
                dx, dy = x - GX, y - GY
                dist = math.hypot(dx, dy)
                if dist < 70: continue
                ang = math.degrees(math.atan2(dy, dx)) % 360
                d = abs(((ang - a + 180) % 360) - 180)
                if d < w:
                    t = (1 - d / w) * max(0.0, 1.1 - dist / 170.0)
                    if t * 0.9 > bay(x, y):
                        cur = im.get(x, y)
                        if cur in ('N', 'I', 'J', 'Z', 'd'): im.put(x, y, c if t > 0.5 else 'C' if c == 'c' else 'P')

def lumen_scene(f=0):
    im, gl = Ill(320, 180, 'N'), Glow()
    space_gradient(im, 0, 180, ('N', 'N', 'I'), 0, 1)
    nebula(im, 9, 160, 90, 190, 110, ['.', 'I', 'Z', 'V', 'P'], thr=0.32, gain=2.2, scale=(48, 40))
    nebula(im, 12, 90, 120, 130, 60, ['.', 'I', 'B', 'C'], thr=0.40, gain=1.8, scale=(44, 36))
    starfield(im, gl, f, 6, 230)
    rays(im, f)
    lumen_field(im, gl, f, 46)
    facet_ring(im, gl, f, 46, 62)
    # a lone skiff, small, about to go in
    lumen_td(im, gl, 84, 138, -36, 30, f)
    shards(im, gl, f)
    return im, gl

REG = {
 'wayout_concord': (concord_scene, 4, "The Concord way out: the gate restarted as a calm lattice of light, ringed by 68 escorts in three neat rows, all nose-in. Frames: pulses ripple out of the gate, the running lights walk round, nav lights blink in step."),
 'wayout_clans': (clans_scene, 4, "The Clan way out: the gate wrapped in scrap scaffolding, patched with mismatched plates, pennants and lamps, ships pouring out in a burst. Frames: the field swirls, welders spark, pennants wave, ships surge."),
 'wayout_lumen': (lumen_scene, 4, "The Lumen way out: a crystal gate opening onto somewhere impossible (a floor above, a hollow sun, a ribbon that loops), a lone skiff about to enter. Frames: facets shimmer, shards drift, the ribbon runs."),
}
