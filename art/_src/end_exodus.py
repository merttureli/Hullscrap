"""haven_exodus: a convoy of mismatched ships arriving at Halcyon (seen from outside, the dome glowing warm)."""
import math
from ill import *
from scene_common import *
from ships_side import *

DCX, DCY, DRX, DRY = 262, 86, 48, 42       # the dome

def backdrop(im, gl, f):
    space_gradient(im, 0, 180, ('N', 'N', 'I', 'I', 'J'), 0.0, 0.85)
    # the Lantern Reach glows plum and rose behind the ship
    nebula(im, 21, 250, 70, 210, 110, ['.', 'I', 'Z', 'd', 'P', 'w'], thr=0.30, gain=2.6, scale=(52, 44), tilt=0.6)
    nebula(im, 33, 40, 150, 120, 60, ['.', 'I', 'J', 'Z'], thr=0.40, gain=2.0, scale=(60, 40))
    starfield(im, gl, f, 17, 360, 170)
    # a far, cold sun top-left (the light)
    im.rgrad(30, 16, 16, ['H', 'z', 'i', 'J', '.'], sharp=1.0)
    gl.blob(30, 16, 26, 'i', 80, 2.0)

def halcyon(im, gl, f):
    # the hull: a long slab with a tapered bow, rim-lit on top, warm window rows
    hull = poly_cells([(176, 122), (190, 100), (204, 90), (330, 90), (330, 156), (300, 160), (220, 158), (200, 150), (186, 138)])
    body(im, hull, ['E', 'W', 'S', 'M', 'L'], 90, 158, sharp=2.4, tl=0.25, x0=176, x1=330)
    # seams: big panels, a lower belt, bolt rows
    for sx in range(196, 330, 17): im.vline(sx, 92, 64, 'E')
    for sy in (102, 126, 146): im.hline(180, sy, 150, 'E')
    for sy in (103, 127, 147):
        for x in range(198, 330, 17): im.put(x + 2, sy, 'M'); im.put(x + 14, sy, 'S')
    # plates that have been replaced over forty years: a few rust and navy patches
    for (x, y, w, h, c) in ((200, 106, 15, 14, 'u'), (286, 130, 15, 14, 'u'), (234, 130, 15, 14, 'J'), (250, 104, 12, 10, 'u')):
        for j in range(h):
            for i in range(w):
                if (x + i, y + j) in hull: im.put(x + i, y + j, ('T' if c == 'u' else 'j') if j == 0 else c if j < h - 2 else darken(c))
        for (bx, by) in ((x + 1, y + 1), (x + w - 2, y + 1), (x + 1, y + h - 2), (x + w - 2, y + h - 2)): im.put(bx, by, 'M')
    # structural frames (heavier ribs every third panel), a pipe bundle low on the hull, rust streaks under the patches
    for sx in (213, 281):
        im.vline(sx - 1, 92, 64, 'M'); im.vline(sx, 92, 64, 'S'); im.vline(sx + 1, 92, 64, 'E'); im.vline(sx + 2, 92, 64, 'K')
    for k in range(4):
        im.hline(184, 153 + k % 2 - (1 if k == 3 else 0), 146, ['W', 'S', 'M', 'E'][k]) if False else None
    for i, c in enumerate(['E', 'S', 'M']): im.hline(190, 152 + i, 140, c)
    for (x, y) in ((206, 121), (292, 145), (241, 145), (309, 118)):
        for j in range(5 + x % 4): 
            if (x, y + j) in hull and (x + j) % 3: im.put(x, y + j, 'q' if j < 3 else 'n')
    # the lantern badge on the hull
    bd = ring_cells(306, 122, 8, 8, 2); im.fill(bd, 'a'); im.outline(bd, 'K'); im.fill(ellipse_cells(306, 122, 5, 5), 'I')
    im.rect(305, 118, 3, 7, 'y'); im.put(306, 117, 'H'); gl.blob(306, 122, 9, 'y', 70, 1.8)
    # window rows (cosy, warm)
    for (y, n, st) in ((112, 14, 8), (120, 14, 8), (140, 14, 8)):
        for k in range(n):
            x = 198 + k * 9
            on = (k * 5 + y) % 7 != 0 or f % 2
            if x < 326:
                im.put(x, y, 'y' if on else 'W'); im.put(x + 1, y, 'a' if on else 'W')
                if on and k % 2 == 0: gl.blob(x, y, 4, 'y', 50, 1.8)
    # HALCYON in stencil letters (3x5 font at 2x)
    tx = 206
    for ch in 'HALCYON':
        g = F35[ch]
        for i, b in enumerate(g):
            if b == '1':
                for dy in range(2):
                    for dx in range(2): im.put(tx + (i % 3) * 2 + dx, 149 + (i // 3) * 2 + dy - 1, 'a')
        tx += 8
    # the bow: a docking collar ringed with lamps
    collar = ring_cells(184, 120, 17, 17, 4)
    im.shade(collar, ['D', 'E', 'W', 'S', 'M'], 184, 118, 17, 17)
    im.outline(collar, 'K')
    for k in range(16):
        a = math.radians(k * 22.5)
        x, y = int(184 + 15 * math.cos(a)), int(120 + 15 * math.sin(a))
        on = (k - f) % 4 == 0
        im.put(x, y, 'y' if on else 'W')
        if on: gl.blob(x, y, 5, 'y', 120, 1.8)
    im.disc(184, 120, 9, 'N'); im.disc(184, 120, 8, 'I')
    im.rgrad(184, 120, 8, ['y', 'Y', 'a', 'T', 'I'], sharp=1.0)
    gl.blob(184, 120, 24, 'y', 110, 1.8)
    im.outline(ellipse_cells(184, 120, 9, 9), 'K')

def dome(im, gl, f):
    # glass dome on the back of the hull, lit warm from inside
    d = ellipse_cells(DCX, DCY, DRX, DRY) & rect_cells(DCX - DRX - 2, DCY - DRY - 2, 2 * DRX + 4, DRY + 3)
    for (x, y) in d:
        t = (y - (DCY - DRY)) / float(DRY)
        v = pick(1 - t * 0.95 + 0.04, ['y', 'Y', 'a', 'T', 'd'], x, y, 1.6)
        im.put(x, y, v)
    # the gardens inside: dark tree-lines and a lit village row
    r = Lcg(5)
    for x in range(DCX - DRX + 2, DCX + DRX - 1):
        top = DCY - 6 - int(5 * math.sin(x / 5.0) + 3 * math.sin(x / 2.3 + 1) + 2 * r.f())
        for y in range(top, DCY + 1):
            if (x, y) in d: im.put(x, y, 'A' if y > top + 1 else 'O')
    for k in range(9):
        x = DCX - 38 + k * 9 + (k * 3) % 4
        if (x, DCY - 3) in d:
            im.put(x, DCY - 3, 'y' if (k + f) % 3 else 'H'); im.put(x, DCY - 2, 'a')
            gl.blob(x, DCY - 3, 4, 'y', 80, 1.6)
    # ribs
    for c in (0.2, 0.45, 0.7, 0.92):
        arc = ellipse_cells(DCX, DCY, DRX * c, DRY) & rect_cells(0, 0, 400, DCY + 1)
        edge = arc - shrink(arc, 1)
        for (x, y) in edge:
            if (x, y) in d and y < DCY: im.put(x, y, 'S' if x >= DCX else 'M')
    for h in (0.3, 0.6):
        yy = int(DCY - DRY * h); wd = DRX * math.sqrt(1 - h * h)
        for x in range(int(DCX - wd), int(DCX + wd)):
            if (x, yy) in d: im.put(x, yy, 'M' if x < DCX else 'S')
    edge = d - shrink(d, 1)
    for (x, y) in edge:
        if y < DCY: im.put(x, y, 'M' if (x < DCX - 8 and y < DCY - 6) else 'S')
    im.outline(d, 'K')
    im.hline(DCX - DRX - 3, DCY + 1, 2 * DRX + 6, 'S'); im.hline(DCX - DRX - 3, DCY + 2, 2 * DRX + 6, 'E')
    # glass glint
    for k in range(7): im.put(DCX - 36 + k, DCY - 26 + k // 2 * 0 - k, 'z' if k < 5 else 'H')
    # the spire and its lantern
    top = DCY - DRY
    im.vline(DCX, top - 18, 18, 'M'); im.vline(DCX + 1, top - 18, 18, 'E')
    for j in range(0, 18, 6): im.hline(DCX - 1, top - j - 2, 4, 'S')
    lit = ['H', 'y', 'H', 'y'][f % 4]
    im.rect(DCX - 1, top - 23, 4, 4, lit); im.put(DCX - 1, top - 24, 'M'); im.put(DCX + 2, top - 24, 'S')
    gl.blob(DCX + 1, top - 21, 30 if f % 2 == 0 else 24, 'y', 160, 1.7)
    gl.blob(DCX + 1, top - 21, 10, 'H', 130, 1.4)
    gl.blob(DCX, DCY - 10, 60, 'y', 55, 1.6, squash=0.7)

def arm(im, gl, f):
    # a short docking gantry from the collar, and a lane of approach beacons that leads the convoy in (the lit one walks toward the ship)
    y = 120
    for x in range(138, 168):
        im.put(x, y - 2, 'S'); im.put(x, y - 1, 'M'); im.put(x, y, 'W'); im.put(x, y + 1, 'E'); im.put(x, y + 2, 'K')
        if x % 6 == 0: im.line(x, y - 2, x + 3, y + 2, 'E')
    for px in (146, 160):
        im.vline(px, y - 11, 9, 'E'); im.vline(px + 1, y - 11, 9, 'W'); im.rect(px - 2, y - 13, 6, 3, 'S'); im.hline(px - 2, y - 13, 6, 'M')
        im.vline(px, y + 3, 8, 'E'); im.vline(px + 1, y + 3, 8, 'W')
    for k, x in enumerate(range(4, 138, 11)):
        on = (k - f) % 4 == 0
        im.rect(x, y - 1, 2, 3, 'y' if on else 'a')
        if on: gl.blob(x + 1, y, 9, 'y', 150, 1.7)
        else: gl.blob(x + 1, y, 4, 'a', 50, 1.7)

def bounce(im, cx, cy, r, letters='SMLH'):
    """warm light from the dome falling on the hull around it."""
    for y in range(int(cy - r), int(cy + r)):
        for x in range(int(cx - r * 1.6), int(cx + r * 1.6)):
            c = im.get(x, y)
            if c not in letters: continue
            d = math.hypot((x - cx) / 1.6, y - cy) / r
            if d < 1 and (1 - d) * 0.75 > bay(x, y): im.put(x, y, 'Y' if c in 'LH' else 'Q' if c == 'M' else 'q')

def convoy(im, gl, f):
    for (x, y, L, c) in ((22, 60, 12, ('S', 'M', 'L')), (52, 40, 10, ('S', 'M', 'L')), (140, 56, 11, ('S', 'M', 'L')), (196, 42, 10, ('M', 'L', 'H')), (30, 84, 9, ('S', 'M', 'L'))):
        dart(im, gl, x, y + (1 if f % 2 and x % 4 == 0 else 0), L, f, x)
    raft(im, gl, 34, 100, 34, f, 5)
    liner(im, gl, 104, 84, 62, f, 3)
    lumen(im, gl, 160, 94, 30, f)
    tug(im, gl, 126, 128, 34, f, 2)
    hauler(im, gl, 62, 156, 96, f, 11)
    frigate(im, gl, 172, 166, 68, f)

def render(f=0):
    im, gl = Ill(), Glow()
    backdrop(im, gl, f)
    halcyon(im, gl, f)
    dome(im, gl, f)
    bounce(im, DCX, 92, 16)
    arm(im, gl, f)
    convoy(im, gl, f)
    motes(im, gl, f, 91, 26, (0, 20, 319, 170), ('z', 'L', 'M'), 1, 0)
    return im, gl
